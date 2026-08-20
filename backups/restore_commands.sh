#!/usr/bin/env bash
# =============================================================================
# restore_commands.sh
# Hospital Management System — Database Restore with Verification
# =============================================================================
# Usage:
#   chmod +x backups/restore_commands.sh
#   ./backups/restore_commands.sh <backup_file.dump>
#
# Examples:
#   ./backups/restore_commands.sh backups/dumps/capstone_full_2026-08-20_020001.dump
#   ./backups/restore_commands.sh /var/backups/capstone_full_2026-08-19_020001.dump
#
# Environment variables:
#   HMS_DB_HOST        PostgreSQL host                (default: localhost)
#   HMS_DB_PORT        PostgreSQL port                (default: 5432)
#   HMS_DB_NAME        Target database name           (default: capstone)
#   HMS_DB_USER        Superuser for restore          (default: hms_admin)
#   HMS_RESTORE_JOBS   Parallel restore workers       (default: 4)
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DB_HOST="${HMS_DB_HOST:-localhost}"
DB_PORT="${HMS_DB_PORT:-5432}"
DB_NAME="${HMS_DB_NAME:-capstone}"
DB_USER="${HMS_DB_USER:-hms_admin}"
RESTORE_JOBS="${HMS_RESTORE_JOBS:-4}"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
LOG_FILE="/tmp/hms_restore_${TIMESTAMP}.log"

# ─── Argument Check ───────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <backup_file.dump>"
    echo "Example: $0 backups/dumps/capstone_full_2026-08-20_020001.dump"
    exit 1
fi

BACKUP_FILE="$1"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2; }

log "=== HMS Restore Starting ==="
log "Backup file : ${BACKUP_FILE}"
log "Target DB   : ${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "User        : ${DB_USER}"
log "Parallel    : ${RESTORE_JOBS} jobs"

# ─── Pre-flight Checks ────────────────────────────────────────────────────────
if [[ ! -f "${BACKUP_FILE}" ]]; then
    err "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

if ! command -v pg_restore &>/dev/null; then
    err "pg_restore not found. Install postgresql-client."
    exit 1
fi

if ! pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" &>/dev/null; then
    err "Cannot reach PostgreSQL at ${DB_HOST}:${DB_PORT}."
    exit 1
fi

log "Backup file exists: OK"
log "Database reachable: OK"

# ─── Verify Backup File Integrity ─────────────────────────────────────────────
log "Verifying backup file integrity..."
OBJECT_COUNT=$(pg_restore --list "${BACKUP_FILE}" 2>/dev/null | wc -l)
if [[ "${OBJECT_COUNT}" -lt 10 ]]; then
    err "Backup file appears corrupt or empty (${OBJECT_COUNT} objects)."
    exit 1
fi
log "Backup contains ${OBJECT_COUNT} objects: OK"

# ─── Safety Prompt ────────────────────────────────────────────────────────────
log "WARNING: This will DROP and recreate the ${DB_NAME} database."
read -p "Type YES to continue: " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
    log "Restore cancelled by user."
    exit 0
fi

# ─── Drop and Recreate Target Database ───────────────────────────────────────
log "Dropping existing database ${DB_NAME}..."
psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" \
    >> "${LOG_FILE}" 2>&1

psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres \
    -c "DROP DATABASE IF EXISTS ${DB_NAME};" \
    >> "${LOG_FILE}" 2>&1

psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres \
    -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" \
    >> "${LOG_FILE}" 2>&1

log "Database recreated: OK"

# ─── Restore ──────────────────────────────────────────────────────────────────
log "Running pg_restore..."
pg_restore \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --jobs="${RESTORE_JOBS}" \
    --no-owner \
    --no-acl \
    --verbose \
    "${BACKUP_FILE}" \
    >> "${LOG_FILE}" 2>&1

RESTORE_EXIT=$?
if [[ "${RESTORE_EXIT}" -ne 0 ]]; then
    err "pg_restore exited with code ${RESTORE_EXIT}. Review ${LOG_FILE}."
    # Non-zero exit may be non-fatal (e.g., pre-existing objects) — continue to verify
fi

log "pg_restore complete (exit code: ${RESTORE_EXIT})"

# ─── Post-Restore Verification ────────────────────────────────────────────────
log "=== Verification Checks ==="

# Check table existence
TABLES=("departments" "doctors" "patients" "appointments" "diagnoses" "prescriptions" "wards" "admissions" "invoices" "payments" "audit_log")
for TABLE in "${TABLES[@]}"; do
    COUNT=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc "SELECT COUNT(*) FROM ${TABLE};" 2>/dev/null || echo "ERROR")
    if [[ "${COUNT}" == "ERROR" ]]; then
        err "Table ${TABLE}: NOT FOUND"
    else
        log "Table ${TABLE}: OK (${COUNT} rows)"
    fi
done

# Check extension existence
EXT_CHECK=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT string_agg(extname, ', ' ORDER BY extname) FROM pg_extension WHERE extname IN ('pgcrypto','btree_gist');" 2>/dev/null)
log "Extensions: ${EXT_CHECK}"

# Check index count
IDX_COUNT=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';" 2>/dev/null)
log "Indexes: ${IDX_COUNT} (expected: 28+)"

# Check RLS enabled tables
RLS_COUNT=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity=true;" 2>/dev/null)
log "RLS-enabled tables: ${RLS_COUNT} (expected: 8)"

# Check trigger count
TRG_COUNT=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='public';" 2>/dev/null)
log "Triggers: ${TRG_COUNT} (expected: 6+ audit triggers)"

# ─── Summary ──────────────────────────────────────────────────────────────────
log "=== Restore Complete ==="
log "Database  : ${DB_NAME} on ${DB_HOST}:${DB_PORT}"
log "Restored  : ${BACKUP_FILE}"
log "Log file  : ${LOG_FILE}"

exit 0
