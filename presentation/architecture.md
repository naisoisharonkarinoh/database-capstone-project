# System & Database Architecture

**Project:** Hospital Management System — Database Capstone  
**Author:** Atinda Hillary  
**Date:** 2026-08-20

---

## System Overview

The HMS database layer is a multi-tier architecture that separates concerns between the application, connection management, primary relational store, document store, and cache.

```
┌─────────────────────────────────────────────────────────────────┐
│                        APPLICATION LAYER                        │
│   Web API / Clinical Portal / Admin Dashboard / Billing UI     │
└───────────────────────────────┬─────────────────────────────────┘
                                │ SQL (parameterised)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PgBouncer (Transaction Pooling)             │
│   Max 100 server connections · Port 6432 · Pool mode: transaction│
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│               PostgreSQL 15.6 — Primary Database                │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Relational   │  │   Security   │  │    Optimisation      │  │
│  │ Schema       │  │   Layer      │  │    Layer             │  │
│  │              │  │              │  │                      │  │
│  │ 11 tables    │  │ 7 roles      │  │ 28 indexes           │  │
│  │ 5 migrations │  │ 31 RLS pol.  │  │ B-tree, composite    │  │
│  │ FK + CHECK   │  │ FORCE RLS    │  │ partial, BRIN        │  │
│  │ constraints  │  │ Audit trail  │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                 │
│  Extensions: pgcrypto · btree_gist                             │
└───────────────────────────────┬─────────────────────────────────┘
                                │
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   MongoDB 7.0    │  │   Redis 7.2      │  │   File System    │
│                  │  │                  │  │                  │
│ Clinical notes   │  │ Session cache    │  │ pg_dump backups  │
│ Activity logs    │  │ Pub/Sub notif.   │  │ 30-day retention │
│ TTL indexes      │  │ Rate limiting    │  │ chmod 600        │
│ Schema valid.    │  │ Dashboard stats  │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

---

## Database Schema Architecture

### Entity Groups

**Core Clinical** (patient-facing records)
- `patients` — 200 demo patients; bcrypt-hashed national IDs
- `appointments` — 500 scheduled visits; EXCLUDE USING GIST prevents double-booking
- `diagnoses` — ICD-10 coded diagnoses per appointment
- `prescriptions` — medications per appointment

**Operational** (hospital operations)
- `departments` — 5 departments with head doctor references
- `doctors` — 20 practitioners with specialisation and active flag
- `wards` — 10 inpatient wards (general, ICU, maternity, paediatric, surgical)
- `admissions` — 50 inpatient stays; CHECK constraint enforces discharge > admit

**Financial** (billing pipeline)
- `invoices` — 490 invoices; amounts in UGX cents (integer) to avoid float errors
- `payments` — 489 payment transactions; 5 payment methods

**Audit**
- `audit_log` — append-only; 6 trigger-covered tables; BRIN indexed

### Circular FK Resolution

Departments reference a head doctor; doctors reference a department. This circular dependency is resolved by:
1. Creating `departments` without the FK
2. Creating `doctors` with FK to `departments`
3. Using `ALTER TABLE departments ADD CONSTRAINT fk_dept_head_doctor ...`

---

## Migration Architecture

Flyway manages all schema changes as versioned, checksum-validated SQL files:

| Version | File | Content |
|---------|------|---------|
| V1 | core_tables.sql | 11 tables, extensions, constraints |
| V2 | indexes.sql | 28 indexes (B-tree, composite, partial, BRIN) |
| V3 | audit_and_triggers.sql | Audit triggers, invoice sync, updated_at trigger |
| V4 | row_level_security.sql | Helper functions, 31 RLS policies, FORCE RLS |
| V5 | seed_demo_data.sql | 5 depts · 20 doctors · 200 patients · 500 appts |

Each migration is idempotent within its version; rollback is via `flyway clean migrate` in development only.

---

## Security Architecture

### Role Hierarchy

```
hms_admin (BYPASSRLS)
    │
    ├── hms_doctor      → own patients + clinical records
    ├── hms_nurse       → read-all clinical (no write)
    ├── hms_receptionist → patient registration + appointments
    ├── hms_billing     → invoices + payments only
    ├── hms_analyst     → read-only aggregate access
    └── hms_auditor     → audit_log read-only
```

### Session-Variable-Driven RLS

The application sets local session variables before every transaction:

```sql
BEGIN;
SET LOCAL app.user_role = 'doctor';
SET LOCAL app.doctor_id = '7';
-- All queries in this transaction are filtered by the policies
COMMIT;
```

SECURITY DEFINER helper functions read these variables so no role can spoof them.

---

## NoSQL Integration Architecture

### MongoDB — Clinical Encounters

MongoDB stores the **unstructured, evolving** part of clinical records that doesn't fit a fixed schema:

- **clinical_encounters** collection: full encounter notes, vital signs arrays, attachments, follow-up actions
- **activity_logs** collection: system-level user actions (TTL = 90 days)

The `appointment_id` foreign key links MongoDB documents back to PostgreSQL for cross-store queries.

### Redis — Performance & Notifications

Redis handles **transient, high-frequency** data that benefits from sub-millisecond access:

- **Session store:** `session:{token}` Hash + TTL (30 min rolling)
- **Appointment notifications:** `appt_notifications:{doctor_id}` List (pub/sub fallback)
- **Doctor availability cache:** Sorted Set with 5-minute TTL
- **Rate limiter:** INCR + EXPIRE per user per endpoint
- **Dashboard stats:** Cached aggregate counts, refreshed every 60 seconds

---

## Backup Architecture

```
[Cron: 02:00 daily]
        │
        ▼
backup_script.sh
  pg_dump --format=custom --compress=9
        │
        ▼
./backups/dumps/capstone_full_YYYY-MM-DD_HHmmSS.dump
  chmod 600 (owner read-only)
        │
        ▼
Integrity check: pg_restore --list (>10 objects)
        │
        ▼
Retention: find -mtime +30 -delete
```

Restore is tested weekly via restore_commands.sh with post-restore row count, index count, RLS, and trigger verification.
