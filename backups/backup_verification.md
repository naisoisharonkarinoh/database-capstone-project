# Backup Verification Log

**Project:** Hospital Management System — Database Capstone  
**Database:** capstone (PostgreSQL 15.6)  
**Backup Tool:** pg_dump --format=custom --compress=9  
**Restore Tool:** pg_restore --jobs=4

---

## Backup Run #1 — 2026-08-20

### Execution

```bash
$ ./backups/backup_script.sh

[2026-08-20 02:00:01] === HMS Backup Starting ===
[2026-08-20 02:00:01] Database : localhost:5432/capstone
[2026-08-20 02:00:01] User     : hms_admin
[2026-08-20 02:00:01] Output   : ./backups/dumps/capstone_full_2026-08-20_020001.dump
[2026-08-20 02:00:01] Database connectivity: OK
[2026-08-20 02:00:01] Running pg_dump...
[2026-08-20 02:00:03] Backup written: ./backups/dumps/capstone_full_2026-08-20_020001.dump
[2026-08-20 02:00:03] Verifying backup integrity with pg_restore --list...
[2026-08-20 02:00:03] Backup integrity: OK (312 objects)
[2026-08-20 02:00:03] Backup size: 1.2M
[2026-08-20 02:00:03] Applying 30-day retention policy...
[2026-08-20 02:00:03] Deleted 0 backup(s) older than 30 days
[2026-08-20 02:00:03] === Backup Complete ===
[2026-08-20 02:00:03] File     : ./backups/dumps/capstone_full_2026-08-20_020001.dump
[2026-08-20 02:00:03] Size     : 1.2M
[2026-08-20 02:00:03] Objects  : 312
[2026-08-20 02:00:03] Retained : 1 backup file(s) in ./backups/dumps
[2026-08-20 02:00:03] Log      : ./backups/dumps/backup_2026-08-20_020001.log
```

### Result: ✅ PASS

| Check | Result |
|-------|--------|
| pg_dump exit code | 0 (success) |
| Backup file created | Yes |
| Object count | 312 |
| Backup size | 1.2 MB |
| File permissions | 600 (owner read-only) |
| Retention cleanup | 0 old files deleted |

---

## Restore Test #1 — 2026-08-20

### Execution

```bash
$ ./backups/restore_commands.sh backups/dumps/capstone_full_2026-08-20_020001.dump

[2026-08-20 09:15:22] === HMS Restore Starting ===
[2026-08-20 09:15:22] Backup file : backups/dumps/capstone_full_2026-08-20_020001.dump
[2026-08-20 09:15:22] Target DB   : localhost:5432/capstone
[2026-08-20 09:15:22] User        : hms_admin
[2026-08-20 09:15:22] Parallel    : 4 jobs
[2026-08-20 09:15:22] Backup file exists: OK
[2026-08-20 09:15:22] Database reachable: OK
[2026-08-20 09:15:22] Verifying backup file integrity...
[2026-08-20 09:15:22] Backup contains 312 objects: OK
[2026-08-20 09:15:22] WARNING: This will DROP and recreate the capstone database.
Type YES to continue: YES
[2026-08-20 09:15:25] Database recreated: OK
[2026-08-20 09:15:25] Running pg_restore...
[2026-08-20 09:15:27] pg_restore complete (exit code: 0)
[2026-08-20 09:15:27] === Verification Checks ===
[2026-08-20 09:15:27] Table departments: OK (5 rows)
[2026-08-20 09:15:27] Table doctors: OK (20 rows)
[2026-08-20 09:15:27] Table patients: OK (200 rows)
[2026-08-20 09:15:27] Table appointments: OK (500 rows)
[2026-08-20 09:15:27] Table diagnoses: OK (500 rows)
[2026-08-20 09:15:27] Table prescriptions: OK (487 rows)
[2026-08-20 09:15:27] Table wards: OK (10 rows)
[2026-08-20 09:15:27] Table admissions: OK (50 rows)
[2026-08-20 09:15:27] Table invoices: OK (490 rows)
[2026-08-20 09:15:27] Table payments: OK (489 rows)
[2026-08-20 09:15:27] Table audit_log: OK (0 rows)
[2026-08-20 09:15:27] Extensions: btree_gist, pgcrypto
[2026-08-20 09:15:27] Indexes: 32 (expected: 28+)
[2026-08-20 09:15:27] RLS-enabled tables: 8 (expected: 8)
[2026-08-20 09:15:27] Triggers: 8 (expected: 6+ audit triggers)
[2026-08-20 09:15:27] === Restore Complete ===
[2026-08-20 09:15:27] Database  : capstone on localhost:5432
[2026-08-20 09:15:27] Restored  : backups/dumps/capstone_full_2026-08-20_020001.dump
[2026-08-20 09:15:27] Log file  : /tmp/hms_restore_2026-08-20_091522.log
```

### Result: ✅ PASS

| Verification Check | Expected | Actual | Status |
|-------------------|----------|--------|--------|
| pg_restore exit code | 0 | 0 | ✅ PASS |
| departments rows | 5 | 5 | ✅ PASS |
| doctors rows | 20 | 20 | ✅ PASS |
| patients rows | 200 | 200 | ✅ PASS |
| appointments rows | 500 | 500 | ✅ PASS |
| diagnoses rows | 500 | 500 | ✅ PASS |
| prescriptions rows | ~487 | 487 | ✅ PASS |
| wards rows | 10 | 10 | ✅ PASS |
| admissions rows | 50 | 50 | ✅ PASS |
| invoices rows | ~490 | 490 | ✅ PASS |
| payments rows | ~489 | 489 | ✅ PASS |
| Extensions restored | 2 | 2 (pgcrypto, btree_gist) | ✅ PASS |
| Indexes restored | 28+ | 32 | ✅ PASS |
| RLS-enabled tables | 8 | 8 | ✅ PASS |
| Audit triggers | 6+ | 8 | ✅ PASS |

---

## Additional Integrity Checks

### Row-Level Security Functional Test

After restore, RLS was verified by connecting with two different roles:

```sql
-- As doctor_user (doctor_id = 1)
SET app.user_role = 'doctor';
SET app.doctor_id = '1';

SELECT COUNT(*) FROM patients;
-- Result: 25 (only patients seen by doctor 1, not all 200)

SELECT COUNT(*) FROM appointments;
-- Result: 25 (only doctor 1's appointments)

SELECT COUNT(*) FROM invoices;
-- Result: 0 (no direct invoice access for doctors in RLS)
```

```sql
-- As billing_user
SET app.user_role = 'billing_staff';

SELECT COUNT(*) FROM invoices;
-- Result: 490 (full access)

SELECT COUNT(*) FROM diagnoses;
-- Result: ERROR: permission denied for table diagnoses
```

**RLS Verification: ✅ PASS** — role isolation confirmed post-restore.

### Double-Booking Constraint Test

```sql
-- Attempt to book doctor 1 at an already-occupied slot
INSERT INTO appointments (patient_id, doctor_id, department_id, scheduled_at, duration_minutes, status)
VALUES (10, 1, 1, '2026-08-20 09:00:00+03', 30, 'scheduled');
-- ERROR: conflicting key value violates exclusion constraint "appointments_doctor_id_tstzrange_excl"
```

**EXCLUDE constraint: ✅ PASS** — constraint survived restore.

### Audit Trigger Test

```sql
-- Update a patient record and verify audit trail
UPDATE patients SET phone = '+256700000999' WHERE patient_id = 1;

SELECT table_name, operation, record_id, changed_by, changed_at
FROM   audit_log
ORDER  BY changed_at DESC LIMIT 1;

-- table_name | operation | record_id | changed_by | changed_at
-- patients   | UPDATE    | 1         | hms_admin  | 2026-08-20 09:16:04+03
```

**Audit trigger: ✅ PASS** — triggers functional after restore.

---

## Scheduled Backup Setup (Cron)

To run the backup script automatically every day at 02:00:

```bash
# Add to crontab (crontab -e)
0 2 * * * /path/to/database-capstone-project/backups/backup_script.sh >> /var/log/hms_backup.log 2>&1
```

---

## Summary

| Item | Status |
|------|--------|
| Backup created successfully | ✅ PASS |
| Backup integrity verified (312 objects) | ✅ PASS |
| Full restore to clean database | ✅ PASS |
| All 11 tables with correct row counts | ✅ PASS |
| Both extensions restored | ✅ PASS |
| All 32 indexes restored | ✅ PASS |
| All 8 RLS policies active | ✅ PASS |
| All 8 audit triggers active | ✅ PASS |
| RLS isolation confirmed post-restore | ✅ PASS |
| Double-booking constraint confirmed | ✅ PASS |
| Audit logging confirmed | ✅ PASS |
| Total restore time | ~5 seconds |
