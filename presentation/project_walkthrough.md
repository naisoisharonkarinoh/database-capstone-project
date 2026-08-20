# Project Walkthrough — 8-Minute Presentation Outline

**Project:** Hospital Management System — Database Capstone  
**Presenter:** Atinda Hillary  
**Duration:** 8 minutes + Q&A

---

## Minute 0:00–1:00 — Problem & Context

**What we built and why:**

A Ugandan hospital with 5 departments and 20+ doctors was managing appointments on paper and in disconnected spreadsheets. This caused:
- Double-booked doctors (no system constraint)
- Unauthorised access to patient records (shared logins)
- No audit trail for billing disputes
- Queries taking minutes instead of milliseconds

**Our solution:** A production-grade PostgreSQL database that enforces all these constraints at the data layer — not the application layer — so they cannot be bypassed.

**One-sentence pitch:** "A hospital database that physically prevents double-booking, cryptographically protects patient identity, and logs every change forever."

---

## Minute 1:00–2:30 — Schema Design

**Show the ER diagram. Walk through the 3 entity groups:**

1. **Clinical** — patients, appointments, diagnoses, prescriptions  
   Key design decision: bcrypt hash for national IDs — if the database is stolen, patient identities remain protected.

2. **Operational** — departments, doctors, wards, admissions  
   Key design decision: the circular FK between departments and doctors, resolved with ALTER TABLE after both tables exist.

3. **Financial** — invoices, payments  
   Key design decision: amounts stored as integer cents (UGX × 100) to avoid floating-point rounding errors on financial calculations.

**Highlight the double-booking prevention:**
```sql
EXCLUDE USING GIST (
    doctor_id WITH =,
    tstzrange(scheduled_at, scheduled_at + duration_minutes * interval '1 minute', '[)') WITH &&
) WHERE (status NOT IN ('cancelled','no_show'))
```
This is enforced at the database level — no application code can schedule two patients with the same doctor in overlapping time slots.

---

## Minute 2:30–3:30 — Flyway Migrations

**Show flyway info output or the migrations/ folder.**

"We use Flyway for versioned, reproducible schema changes. Every change is a numbered SQL file with a checksum. Running `flyway migrate` on a fresh database produces an identical schema every time."

V1 → core tables and constraints  
V2 → 28 indexes for performance  
V3 → audit triggers and business logic  
V4 → row-level security policies  
V5 → 560 rows of realistic demo data  

"This means any developer or deployment can reproduce the entire schema in under 10 seconds with a single command."

---

## Minute 3:30–5:00 — Security (The Most Important Part)

**Three-layer security model:**

**Layer 1: Role-Based Access Control**  
7 roles, principle of least privilege. Billing staff cannot read diagnoses. Nurses cannot write invoices. Analysts cannot read the audit log.

```
hms_admin → everything (BYPASSRLS only, not SUPERUSER)
hms_doctor → own patients + clinical records
hms_nurse → read-all clinical
hms_receptionist → registration + appointments
hms_billing → invoices + payments only
hms_analyst → read-only aggregates
hms_auditor → audit_log only
```

**Layer 2: Row-Level Security (the real enforcement)**  
31 policies across 8 tables. Even if a doctor's password is compromised, they can only see their own patients' data. The policy is enforced at the database row level, not the application level.

Show example: Doctor with `app.doctor_id = 7` can only SELECT rows from `appointments` where `doctor_id = 7`.

**Layer 3: Immutable Audit Trail**  
Every INSERT, UPDATE, DELETE on 6 tables writes a JSON snapshot to audit_log. No UPDATE or DELETE policy exists on audit_log — even hms_admin cannot erase audit records.

---

## Minute 5:00–6:00 — Query Optimisation

**Show the before/after comparison table:**

| Query | Before | After | Speedup |
|-------|--------|-------|---------|
| Doctor utilisation | 40 ms | 4 ms | 9.8× |
| Top diagnoses | 77 ms | 6 ms | 13.6× |
| Monthly revenue | 95 ms | 6 ms | 15.2× |
| Dept aggregation | 57 ms | 3 ms | 21.8× |
| Visit frequency | 49 ms | 2 ms | 27.1× |
| Window function | 193 ms | 12 ms | 15.9× |

"The only change between before and after is running V2__indexes.sql — 28 index definitions. No schema changes, no query rewrites, no hardware upgrade. Index design alone gives us a 15× average speedup."

Key indexes to highlight:
- Composite partial: `idx_appt_doctor_scheduled` (doctor_id, scheduled_at WHERE status IN active)
- BRIN: `idx_audit_changed_at` — 1000× smaller than B-tree for time-ordered data

---

## Minute 6:00–7:00 — NoSQL Integration & Backups

**MongoDB:** "Clinical notes don't fit a fixed schema — a patient might have 2 vitals or 20, with custom fields added by each doctor. MongoDB handles this flexible structure while storing an `appointment_id` that links back to PostgreSQL."

**Redis:** "Three use cases — session tokens with rolling TTL, pub/sub notifications when a new appointment is booked, and a 5-minute cache of doctor availability to avoid repeated expensive queries."

**Backups:** "Daily pg_dump in custom format, compressed, with 30-day retention. Every restore is verified: we check row counts, index count, RLS policy count, and trigger count. Total restore time: 5 seconds."

---

## Minute 7:00–8:00 — Key Takeaways & Demo Invitation

**What makes this production-grade:**
1. Constraints enforced at the database layer — the application cannot bypass them
2. Security enforced at the row level — compromised credentials give minimal access
3. Audit trail that cannot be altered — legal and compliance requirement met
4. Queries optimised to milliseconds — no bottleneck at scale
5. Reproducible from scratch with a single command — devops-ready

**Invite questions and live demo.**

---

## Q&A Preparation

**"Why PostgreSQL over MySQL?"**  
PostgreSQL has native EXCLUDE USING GIST for the overlap constraint, native JSONB for the audit log, and mature RLS. MySQL does not support EXCLUDE constraints.

**"Why not just enforce security in the application?"**  
Application-layer security can be bypassed via direct DB connections, SQL injection, or misconfigured middleware. Database-layer enforcement is the last line of defence.

**"What happens at 1 million appointments?"**  
Partition `appointments` by month on `scheduled_at`. BRIN indexes remain effective. The schema and index strategy were designed with this in mind.

**"Why store money as cents?"**  
IEEE 754 floating point cannot represent 0.1 exactly. `0.1 + 0.2 = 0.30000000000000004` in most languages. Integer cents (UGX × 100) eliminate rounding errors in financial totals.
