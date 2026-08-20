# Live Demo Script

**Project:** Hospital Management System — Database Capstone  
**Prerequisites:** PostgreSQL running with capstone database, all migrations applied.

```bash
# Connect before demo
psql -U hms_admin -d capstone
```

---

## Demo 1 — Double-Booking Prevention

**Narrative:** "Let me show you that it is physically impossible to double-book a doctor."

```sql
-- Step 1: Find a slot that doctor 1 already has
SELECT doctor_id, scheduled_at, duration_minutes, status
FROM   appointments
WHERE  doctor_id = 1
  AND  status NOT IN ('cancelled','no_show')
ORDER  BY scheduled_at
LIMIT  3;
```

```sql
-- Step 2: Try to book doctor 1 at the same time (use a time from the result above)
INSERT INTO appointments (patient_id, doctor_id, department_id, scheduled_at, duration_minutes, status)
VALUES (50, 1, 1, '2026-08-20 09:00:00+03', 30, 'scheduled');

-- Expected output:
-- ERROR:  conflicting key value violates exclusion constraint "appointments_doctor_id_tstzrange_excl"
-- DETAIL:  Key (doctor_id, tstzrange(...)) = (1, ...) conflicts with existing key.
```

**Explain:** "This error comes from the database — not the application. It cannot be bypassed."

---

## Demo 2 — Row-Level Security in Action

**Narrative:** "Now let me show you that a doctor can only see their own patients."

```sql
-- Step 1: As admin, count all patients
SELECT COUNT(*) AS total_patients FROM patients;
-- Result: 200
```

```sql
-- Step 2: Simulate connecting as doctor 7
BEGIN;
SET LOCAL app.user_role = 'doctor';
SET LOCAL app.doctor_id = '7';

-- Now query patients — only doctor 7's patients are visible
SELECT COUNT(*) AS my_patients FROM patients;
-- Result: ~25 (only patients seen by doctor 7)

SELECT patient_id, first_name, last_name FROM patients LIMIT 5;
-- Only rows where doctor 7 has had an appointment

ROLLBACK;
```

```sql
-- Step 3: Show what billing staff sees
BEGIN;
SET LOCAL app.user_role = 'billing_staff';

SELECT COUNT(*) FROM invoices;
-- Result: 490 (full access to invoices)

SELECT COUNT(*) FROM diagnoses;
-- ERROR: permission denied for table diagnoses
ROLLBACK;
```

**Explain:** "Same database, same tables, completely different views — enforced at the row level."

---

## Demo 3 — Audit Trail

**Narrative:** "Every change is permanently recorded."

```sql
-- Step 1: Update a patient's phone number
UPDATE patients
SET    phone = '+256700000001'
WHERE  patient_id = 1;
```

```sql
-- Step 2: Check the audit log
SELECT
    audit_id,
    table_name,
    operation,
    record_id,
    changed_by,
    changed_at,
    old_data->>'phone'  AS old_phone,
    new_data->>'phone'  AS new_phone
FROM   audit_log
WHERE  table_name = 'patients'
ORDER  BY changed_at DESC
LIMIT  3;
```

```sql
-- Step 3: Try to delete an audit record
DELETE FROM audit_log WHERE audit_id = 1;
-- ERROR: new row violates row-level security policy for table "audit_log"
-- (no DELETE policy exists — default deny applies)
```

**Explain:** "The audit trail is permanent. Even the database administrator cannot delete records."

---

## Demo 4 — Query Optimisation (Before vs After)

**Narrative:** "Let me show the performance difference a single migration makes."

```sql
-- Doctor utilisation with indexes
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    d.first_name || ' ' || d.last_name AS doctor_name,
    COUNT(a.appointment_id)             AS total_appointments,
    ROUND(COUNT(a.appointment_id)::NUMERIC / (22*16) * 100, 1) AS utilisation_pct
FROM   doctors d
LEFT JOIN appointments a
       ON  a.doctor_id    = d.doctor_id
       AND a.scheduled_at >= NOW() - INTERVAL '30 days'
WHERE  d.is_active = TRUE
GROUP  BY d.doctor_id, d.first_name, d.last_name
ORDER  BY utilisation_pct DESC NULLS LAST;

-- Look for: "Index Scan using idx_appt_doctor_scheduled"
-- Execution Time: ~2-4 ms
```

```sql
-- Window function: running revenue per doctor
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT
    doctor_name,
    billing_month,
    monthly_revenue_ugx,
    SUM(monthly_revenue_ugx) OVER (
        PARTITION BY doctor_id ORDER BY billing_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue_ugx
FROM (
    SELECT
        d.doctor_id,
        d.first_name || ' ' || d.last_name AS doctor_name,
        DATE_TRUNC('month', i.issued_at)    AS billing_month,
        COALESCE(SUM(i.paid_amount_cents), 0) / 100.0 AS monthly_revenue_ugx
    FROM   doctors d
    JOIN   departments dept USING (department_id)
    LEFT JOIN appointments a ON a.doctor_id = d.doctor_id
    LEFT JOIN invoices i     ON i.appointment_id = a.appointment_id
    WHERE  i.issued_at >= NOW() - INTERVAL '12 months'
    GROUP  BY d.doctor_id, d.first_name, d.last_name, dept.name,
              DATE_TRUNC('month', i.issued_at)
) monthly
ORDER BY doctor_name, billing_month;

-- Look for: multiple Index Scans, no Seq Scans
-- Execution Time: ~10 ms
```

---

## Demo 5 — Backup and Restore

**Narrative:** "The system runs a daily backup and we can verify it restores completely."

```bash
# Run the backup
./backups/backup_script.sh

# Check what was created
ls -lh backups/dumps/

# List objects in the backup
pg_restore --list backups/dumps/capstone_full_*.dump | head -20

# Run restore (creates a fresh database and verifies all objects)
./backups/restore_commands.sh backups/dumps/capstone_full_*.dump
# Type YES when prompted
```

---

## Demo 6 — Top Diagnoses Analytical Query

**Narrative:** "This is the kind of report the Ministry of Health would request."

```sql
SELECT
    dx.icd10_code,
    dx.description,
    COUNT(*)                                                          AS diagnosis_count,
    COUNT(*) FILTER (WHERE p.gender = 'Male')                        AS male_count,
    COUNT(*) FILTER (WHERE p.gender = 'Female')                      AS female_count,
    AVG(DATE_PART('year', AGE(p.date_of_birth)))::INT                AS avg_patient_age,
    COUNT(*) FILTER (WHERE DATE_PART('year', AGE(p.date_of_birth)) < 18)            AS under_18,
    COUNT(*) FILTER (WHERE DATE_PART('year', AGE(p.date_of_birth)) BETWEEN 18 AND 45) AS age_18_45,
    COUNT(*) FILTER (WHERE DATE_PART('year', AGE(p.date_of_birth)) > 45)            AS over_45
FROM   diagnoses dx
JOIN   appointments a USING (appointment_id)
JOIN   patients p     USING (patient_id)
WHERE  dx.diagnosed_at >= NOW() - INTERVAL '6 months'
GROUP  BY dx.icd10_code, dx.description
ORDER  BY diagnosis_count DESC
LIMIT  10;
```

**Point out:** execution time should be under 5 ms — a query that took 75 ms before indexing.

---

## Closing Demo Notes

- Keep psql open in one terminal, text editor with key SQL files in another
- If a demo step fails: stay calm, check `\errverbose` for detailed error, use it to explain the constraint
- The double-booking demo always works — it is enforced at the storage layer
- RLS demo requires being connected as hms_admin (which has BYPASSRLS) and using SET LOCAL to simulate another role
