# Final Project Report

**Project:** Hospital Management System — Database Capstone  
**Author:** Atinda Hillary (atindahhillary@gmail.com)  
**Organization:** Atinda  
**Date:** 2026-08-20  
**Repository:** https://github.com/naisoisharonkarinoh/database-capstone-project

---

## 1. Executive Summary

This project delivers a complete, production-grade PostgreSQL database solution for a single-site hospital in Uganda. The system manages patient records, appointment scheduling, clinical data, billing, and security auditing for a hospital with 5 departments and 20+ doctors. The implementation demonstrates five core database engineering competencies: normalised relational schema design, versioned schema migrations, query optimisation through targeted indexing, defence-in-depth security, and polyglot persistence with MongoDB and Redis.

All six analytical queries run in under 15 milliseconds post-optimisation, achieving an average 17× speedup over baseline. Row-level security policies enforce per-role data isolation at the storage layer. An immutable audit trail records every INSERT, UPDATE, and DELETE across six sensitive tables. Daily backups with 30-day retention have been tested and verified with a complete restore cycle.

---

## 2. Project Objectives and Outcomes

| Objective | Target | Outcome |
|-----------|--------|---------|
| Normalised relational schema | 3NF minimum | ✅ 11 tables in 3NF; circular FK resolved via ALTER TABLE |
| Versioned schema migrations | Flyway, 5 versions | ✅ V1–V5 with checksums; reproducible in <10 seconds |
| Query optimisation | Sub-second response | ✅ All 6 queries under 15 ms; average 17.2× speedup |
| Role-based access control | 7 roles minimum | ✅ 7 roles, 7 login users, REVOKE PUBLIC |
| Row-level security | Per-role row isolation | ✅ 31 policies across 8 tables; FORCE ROW LEVEL SECURITY |
| Audit logging | Append-only trail | ✅ Generic trigger on 6 tables; no-op skipping; immutable |
| MongoDB integration | Clinical notes design | ✅ 2 collections with schema validation and TTL indexes |
| Redis integration | Session + cache | ✅ 4 use cases: sessions, pub/sub, rate limiting, cache |
| Backup and recovery | Daily backup + verify | ✅ Script + restore script + row-count verification |

---

## 3. Schema Design

### 3.1 Design Decisions

**Integer cents for monetary values:** All financial amounts are stored as INTEGER columns in UGX cents (UGX × 100). This eliminates IEEE 754 floating-point representation errors in financial totals. The application divides by 100 for display.

**bcrypt for national IDs:** National identification numbers are never stored in plaintext. The schema stores a bcrypt hash in `patients.national_id_hash`. If the database is compromised, patient identities cannot be recovered from the hash.

**EXCLUDE USING GIST for double-booking prevention:** The appointments table uses a GIST exclusion constraint that prevents any two appointments for the same doctor from occupying overlapping time slots. This is enforced atomically inside each transaction, eliminating the race condition that application-layer checks cannot prevent.

**Circular FK resolution:** The departments–doctors circular dependency (a department has a head doctor; a doctor belongs to a department) is resolved by creating departments first without the FK, creating doctors with its FK to departments, then adding the departments FK via ALTER TABLE.

**Soft deletes:** Doctors and patients are soft-deleted via `is_active = FALSE` rather than hard deletion. This preserves referential integrity with historical appointments, diagnoses, and invoices.

### 3.2 Table Summary

| Table | Rows (seed) | FK count | Audit trigger |
|-------|------------|----------|---------------|
| departments | 5 | 1 (head_doctor_id) | No |
| doctors | 20 | 1 (department_id) | Yes |
| patients | 200 | 0 | Yes |
| appointments | 500 | 3 | Yes |
| diagnoses | 500 | 1 | No |
| prescriptions | 487 | 1 | No |
| wards | 10 | 1 | No |
| admissions | 50 | 3 | Yes |
| invoices | 490 | 3 | Yes |
| payments | 489 | 1 | Yes |
| audit_log | 0 (runtime) | 0 | — |

---

## 4. Migration Architecture

Flyway manages all schema changes as versioned, checksum-validated SQL files stored in the `migrations/` directory.

```
V1__core_tables.sql       → 11 tables, extensions, constraints, circular FK
V2__indexes.sql           → 28 indexes (B-tree, composite, partial, BRIN)
V3__audit_and_triggers.sql → Audit function, 6 triggers, invoice sync trigger, updated_at
V4__row_level_security.sql → Helper functions, 31 RLS policies, FORCE RLS
V5__seed_demo_data.sql    → 560 rows of realistic demo data
```

Each migration is idempotent at the version level. The `flyway clean migrate` cycle reproducibly restores the full schema from zero in under 10 seconds.

---

## 5. Query Optimisation

### 5.1 Index Strategy

28 indexes were created in V2, grouped into four categories:

**Foreign key indexes:** PostgreSQL does not auto-index FK columns. Every FK received a B-tree index, converting hash join build phases from sequential scans to index scans.

**Composite indexes:** Column order follows equality-first, range-second to maximise index selectivity. The most impactful composite index is `idx_appt_doctor_scheduled` (doctor_id, scheduled_at) with a partial clause excluding cancelled/no-show rows.

**Partial indexes:** Exclude rows never searched (inactive records, active admissions, unpaid invoices). Partial indexes are smaller and have higher cache hit rates than full indexes on the same column.

**BRIN indexes:** For append-only, naturally time-ordered columns (`appointments.created_at`, `audit_log.changed_at`). BRIN stores min/max per 128-page block, making it approximately 1,000× smaller than an equivalent B-tree at scale.

### 5.2 Results

| Query | Before (ms) | After (ms) | Speedup |
|-------|------------|-----------|---------|
| Q1 Doctor Utilisation | 40.3 | 4.1 | 9.8× |
| Q2 Top 10 Diagnoses | 76.9 | 5.7 | 13.6× |
| Q3 Monthly Revenue | 94.6 | 6.2 | 15.2× |
| Q4 Dept Aggregation | 56.8 | 2.6 | 21.8× |
| Q5 Visit Frequency | 49.3 | 1.8 | 27.1× |
| Q6 Window Function | 192.6 | 12.1 | 15.9× |
| **Average** | | | **17.2×** |

All gains were achieved by index additions only. No schema changes or query rewrites were required.

---

## 6. Security Implementation

### 6.1 Role-Based Access Control

Seven group roles implement the principle of least privilege:

- **hms_admin:** BYPASSRLS (not SUPERUSER). Full table access.
- **hms_doctor:** Own patients and clinical records only. FK indexes support RLS subqueries efficiently.
- **hms_nurse:** Read-only across all clinical tables. No invoice or payment access.
- **hms_receptionist:** Patient registration and appointment management.
- **hms_billing:** Invoices and payments only. DELETE revoked.
- **hms_analyst:** Read-only aggregate access. No audit_log access.
- **hms_auditor:** audit_log read-only. No clinical or financial data.

All roles connect through dedicated login users. `REVOKE ALL ON DATABASE capstone FROM PUBLIC` and `REVOKE ALL ON SCHEMA public FROM PUBLIC` prevent anonymous access.

### 6.2 Row-Level Security

31 policies across 8 tables use session variables (`app.user_role`, `app.doctor_id`) set by the application layer before each transaction. SECURITY DEFINER helper functions prevent callers from reading or spoofing these variables. FORCE ROW LEVEL SECURITY ensures policies apply even to table owners.

Key policy example — doctor data isolation:
```sql
CREATE POLICY patients_doctor_select ON patients FOR SELECT
USING (
    app_user_role() = 'doctor'
    AND patient_id IN (
        SELECT patient_id FROM appointments WHERE doctor_id = app_doctor_id()
    )
);
```

### 6.3 Audit Trail

A single generic trigger function (`fn_audit_trigger`, SECURITY DEFINER) is attached to six tables. It captures full before/after row snapshots as JSONB, skips no-op updates, and records the application-layer user ID from `SET LOCAL app.user_id`. The audit_log table has no UPDATE or DELETE policy — no role can erase records.

---

## 7. NoSQL Integration

### 7.1 MongoDB — Clinical Encounters

MongoDB stores the flexible, schema-evolving portion of clinical records. The `clinical_encounters` collection uses a JSON schema validator to enforce required fields while allowing arbitrary additional fields per encounter. The `appointment_id` field maintains referential linkage to PostgreSQL.

The `activity_logs` collection captures system-level actions with a 90-day TTL index (`createdAt` field) — records expire automatically, keeping storage bounded.

### 7.2 Redis — Performance Layer

Four Redis data structures serve distinct performance roles:

- **Session tokens** (Hash + TTL): 30-minute rolling expiry, reset on activity
- **Appointment notifications** (List + Pub/Sub): real-time alerts to doctors when appointments are booked or rescheduled
- **Doctor availability cache** (Sorted Set): 5-minute TTL prevents repeated expensive PostgreSQL queries during peak scheduling
- **Rate limiter** (INCR + EXPIRE): protects API endpoints from brute-force attacks

---

## 8. Backup and Recovery

The automated backup script runs daily at 02:00 via cron, producing a `pg_dump --format=custom --compress=9` file. Each file is `chmod 600` (owner read-only). The 30-day retention policy deletes older files automatically.

Restore verification confirms:
- All 11 tables exist with expected row counts
- Both extensions (pgcrypto, btree_gist) are installed
- All 28+ indexes are present
- All 8 RLS-enabled tables retain their policies
- All audit triggers are attached and functional

Verified restore time: 5 seconds on the seed dataset.

---

## 9. Conclusion

The HMS database delivers all specified objectives within the capstone scope. The most significant technical achievement is the combination of EXCLUDE USING GIST (preventing double-booking at the storage layer) and row-level security (enforcing per-doctor data isolation without application code). Together, these two PostgreSQL features replace thousands of lines of application-layer validation and security logic with a handful of SQL declarations that cannot be bypassed.

For production deployment, the recommended next steps are: enable SSL/TLS for all connections, implement the `patients_self_select` RLS policy for a patient portal, and partition the `appointments` and `audit_log` tables by month once row counts exceed one million.
