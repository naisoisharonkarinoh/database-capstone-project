#!/usr/bin/env bash
# =============================================================================
# backup_script.sh
# Hospital Management System — Automated PostgreSQL Backup
# =============================================================================
# Usage:
#   chmod +x backups/backup_script.sh
#   ./backups/backup_script.sh
#
# Environment variables (override defaults):
#   HMS_DB_HOST      PostgreSQL host         (default: localhost)
#   HMS_DB_PORT      PostgreSQL port         (default: 5432)
#   HMS_DB_NAME      Database name           (default: capstone)
#   HMS_DB_USER      Database user           (default: hms_admin)
#   HMS_BACKUP_DIR   Backup destination dir  (default: ./backups/dumps)
#   HMS_RETENTION    Days to keep backups    (default: 30)
#
# Credentials: set PGPASSWORD env var or configure ~/.pgpass
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
DB_HOST="${HMS_DB_HOST:-localhost}"
DB_PORT="${HMS_DB_PORT:-5432}"
DB_NAME="${HMS_DB_NAME:-capstone}"
DB_USER="${HMS_DB_USER:-hms_admin}"
BACKUP_DIR="${HMS_BACKUP_DIR:-$(dirname "$0")/dumps}"
RETENTION_DAYS="${HMS_RETENTION:-30}"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_full_${TIMESTAMP}.dump"
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2; }

# ─── Pre-flight checks ────────────────────────────────────────────────────────
log "=== HMS Backup Starting ==="
log "Database : ${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "User     : ${DB_USER}"
log "Output   : ${BACKUP_FILE}"

# Create backup directory with restricted permissions
if [[ ! -d "${BACKUP_DIR}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    chmod 750 "${BACKUP_DIR}"
    log "Created backup directory: ${BACKUP_DIR}"
fi

# Verify pg_dump is available
if ! command -v pg_dump &>/dev/null; then
    err "pg_dump not found. Install postgresql-client."
    exit 1
fi

# Verify database connectivity
if ! pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null; then
    err "Cannot reach PostgreSQL at ${DB_HOST}:${DB_PORT}. Aborting."
    exit 1
fi
log "Database connectivity: OK"

# ─── Full Backup (Custom Format) ──────────────────────────────────────────────
log "Running pg_dump..."
pg_dump \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --format=custom \
    --compress=9 \
    --no-password \
    --verbose \
    --file="${BACKUP_FILE}" \
    2>> "${LOG_FILE}"

if [[ $? -ne 0 ]]; then
    err "pg_dump failed. Check ${LOG_FILE} for details."
    exit 1
fi

# Restrict file permissions (owner read-only)
chmod 600 "${BACKUP_FILE}"
log "Backup written: ${BACKUP_FILE}"

# ─── Verify Backup Integrity ──────────────────────────────────────────────────
log "Verifying backup integrity with pg_restore --list..."
OBJECT_COUNT=$(pg_restore --list "${BACKUP_FILE}" 2>>/dev/null | wc -l)
if [[ "${OBJECT_COUNT}" -lt 10 ]]; then
    err "Backup appears incomplete (${OBJECT_COUNT} objects). Investigate."
    exit 1
fi
log "Backup integrity: OK (${OBJECT_COUNT} objects)"

# ─── File Size Report ─────────────────────────────────────────────────────────
BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
log "Backup size: ${BACKUP_SIZE}"

# ─── Retention Policy ─────────────────────────────────────────────────────────
log "Applying ${RETENTION_DAYS}-day retention policy..."
DELETED_COUNT=$(find "${BACKUP_DIR}" -name "${DB_NAME}_full_*.dump" -mtime +"${RETENTION_DAYS}" | wc -l)
find "${BACKUP_DIR}" -name "${DB_NAME}_full_*.dump" -mtime +"${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -name "backup_*.log"            -mtime +"${RETENTION_DAYS}" -delete
log "Deleted ${DELETED_COUNT} backup(s) older than ${RETENTION_DAYS} days"

# ─── Summary ──────────────────────────────────────────────────────────────────
REMAINING=$(find "${BACKUP_DIR}" -name "${DB_NAME}_full_*.dump" | wc -l)
log "=== Backup Complete ==="
log "File     : ${BACKUP_FILE}"
log "Size     : ${BACKUP_SIZE}"
log "Objects  : ${OBJECT_COUNT}"
log "Retained : ${REMAINING} backup file(s) in ${BACKUP_DIR}"
log "Log      : ${LOG_FILE}"

exit 0
