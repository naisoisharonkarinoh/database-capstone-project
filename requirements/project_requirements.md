# Project Requirements

**Project:** Hospital Management System — Database Capstone  
**Author:** Atinda Hillary  
**Date:** 2026-08-20

---

## Problem Statement

A hospital in Uganda with 5 departments and 20+ doctors manages patient records, appointments, clinical data, and billing using disconnected spreadsheets and paper records. This causes:

1. **Double-booked appointments** — no system prevents two patients being scheduled with the same doctor at the same time
2. **Unauthorised data access** — shared login credentials give all staff access to all records
3. **No audit trail** — billing disputes cannot be investigated; no record of who changed what
4. **Slow reporting** — management queries take minutes on large datasets
5. **Data inconsistency** — invoice status is manually updated; payments and invoices can fall out of sync

---

## Business Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-01 | The system must prevent two appointments from being scheduled with the same doctor in overlapping time slots | Critical |
| BR-02 | Patient national ID numbers must never be stored in plaintext | Critical |
| BR-03 | Different staff roles must only access data relevant to their function | Critical |
| BR-04 | All changes to patient records, appointments, invoices, and payments must be permanently logged | High |
| BR-05 | Invoice status must automatically reflect payment transactions | High |
| BR-06 | Management must be able to run utilisation, revenue, and diagnosis reports in under 1 second | High |
| BR-07 | The database must be recoverable from backup within 10 minutes of a failure | High |
| BR-08 | Clinical notes that do not fit a fixed schema must be supported | Medium |
| BR-09 | Doctor availability must be queryable in real time without database overload | Medium |
| BR-10 | The schema must be reproducible from zero with a single command | Medium |

---

## Functional Requirements

### Patient Management
- FR-P01: Register patients with demographic information, contact details, insurance, and emergency contacts
- FR-P02: Store national ID as a one-way bcrypt hash; never expose the plaintext value
- FR-P03: Support soft-delete (is_active flag) to preserve historical records

### Appointment Scheduling
- FR-A01: Schedule appointments linking a patient to a doctor at a specific time
- FR-A02: Enforce no time overlap for the same doctor using a database-level exclusion constraint
- FR-A03: Track appointment status through its lifecycle: scheduled → confirmed → completed / cancelled / no_show
- FR-A04: Support appointment durations in minutes (default 30 minutes per slot)

### Clinical Records
- FR-C01: Record diagnoses using ICD-10 codes per appointment
- FR-C02: Record prescriptions with medication, dosage, frequency, and duration
- FR-C03: Track inpatient admissions with ward, bed, and admitting doctor
- FR-C04: Store extended clinical encounter notes in MongoDB for unstructured data

### Billing
- FR-B01: Generate invoices per appointment or per admission
- FR-B02: Store all monetary amounts as integer cents (UGX × 100) to avoid floating-point errors
- FR-B03: Automatically update invoice status (pending → partial → paid) when payments are recorded
- FR-B04: Support five payment methods: cash, mobile_money, card, insurance, waiver

### Security
- FR-S01: Implement 7 database roles with principle of least privilege
- FR-S02: Enforce row-level security so doctors see only their own patients' data
- FR-S03: Record every INSERT, UPDATE, and DELETE on sensitive tables in an append-only audit log
- FR-S04: Prevent any role from deleting or modifying audit records

### Reporting
- FR-R01: Doctor utilisation rate (appointments vs. theoretical capacity) for the last 30 days
- FR-R02: Top 10 diagnoses by frequency with patient demographic breakdown (last 6 months)
- FR-R03: Monthly revenue by department for the current year
- FR-R04: Department summary aggregation (patients, appointments, revenue)
- FR-R05: Patient visit frequency segmentation (one-time, occasional, regular, frequent)
- FR-R06: Running revenue total and departmental rank per doctor (window function)

### Backup and Recovery
- FR-BK01: Automated daily backup using pg_dump in custom compressed format
- FR-BK02: 30-day backup retention with automatic deletion of older files
- FR-BK03: Restore script that verifies row counts, indexes, RLS policies, and triggers after restore

---

## Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-01 | Performance | All analytical queries must complete in under 1 second on the seed dataset |
| NFR-02 | Security | No plaintext PII stored at rest; all roles use password authentication |
| NFR-03 | Availability | Database must be recoverable from backup within 10 minutes |
| NFR-04 | Maintainability | All schema changes must be managed through Flyway versioned migrations |
| NFR-05 | Reproducibility | `flyway migrate` on a fresh database must produce a complete schema in under 10 seconds |
| NFR-06 | Auditability | Every data change on 6 sensitive tables must produce an audit record within the same transaction |
| NFR-07 | Scalability | Index strategy must remain effective up to 1 million appointment rows |

---

## User Roles

| Role | Description | Key Permissions |
|------|-------------|-----------------|
| Admin | Database administrator | Full access; bypasses RLS |
| Doctor | Medical practitioner | Own patients, appointments, diagnoses, prescriptions |
| Nurse | Nursing staff | Read-only: all patients, appointments, clinical records |
| Receptionist | Front desk | Patient registration; appointment creation and update |
| Billing Staff | Finance department | Invoices and payments; no clinical data |
| Analyst | Management reporting | Read-only aggregates; no PII or audit log |
| Auditor | Compliance officer | Audit log read-only; no other tables |

---

## Technical Assumptions

1. Single-site deployment — one PostgreSQL instance; no replication required for capstone scope
2. Application layer sets `app.user_role` and `app.doctor_id` session variables before each transaction
3. Time zone: East Africa Time (UTC+3); all timestamps stored as TIMESTAMPTZ
4. Currency: Ugandan Shilling (UGX); amounts stored as integer cents
5. MongoDB and Redis run on the same host as PostgreSQL for the capstone environment
6. Backup destination is a local directory; offsite replication is out of scope
7. SSL/TLS configuration is a production hardening step, not required for capstone demonstration
