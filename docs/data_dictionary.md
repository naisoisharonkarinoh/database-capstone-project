# Data Dictionary

**Project:** Hospital Management System — Database Capstone  
**Database:** capstone (PostgreSQL 15.6)  
**Schema:** public  
**Generated:** 2026-08-20

---

## Table: departments

Stores hospital departments. Head doctor is a nullable FK set after the doctors table is created to resolve the circular dependency.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| department_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| name | VARCHAR(100) | NOT NULL | — | UNIQUE | Department name (e.g. "Cardiology") |
| head_doctor_id | INTEGER | NULL | — | FK → doctors(doctor_id) ON DELETE SET NULL | Appointed head of department |
| location | VARCHAR(100) | NULL | — | — | Physical location in hospital |
| created_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Record creation timestamp |

**Indexes:** idx_departments_name, idx_departments_head_doctor_id

---

## Table: doctors

Registered medical practitioners. Linked to one department. Soft-deleted via is_active flag.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| doctor_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| first_name | VARCHAR(50) | NOT NULL | — | — | Given name |
| last_name | VARCHAR(50) | NOT NULL | — | — | Family name |
| email | VARCHAR(150) | NOT NULL | — | UNIQUE | Contact and login email |
| phone | VARCHAR(20) | NULL | — | — | Mobile number |
| specialisation | VARCHAR(100) | NOT NULL | — | — | Medical specialisation |
| department_id | INTEGER | NULL | — | FK → departments(department_id) ON DELETE SET NULL | Assigned department |
| license_number | VARCHAR(50) | NOT NULL | — | UNIQUE | Medical council license |
| is_active | BOOLEAN | NOT NULL | TRUE | — | FALSE = soft-deleted |
| created_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Record creation timestamp |

**Indexes:** idx_doctors_department_id, idx_doctors_specialisation, idx_doctors_email, idx_doctors_is_active (partial: WHERE is_active=TRUE), idx_doctors_last_first

---

## Table: patients

Registered hospital patients. PII protected: national ID stored as bcrypt hash only.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| patient_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| first_name | VARCHAR(50) | NOT NULL | — | — | Given name |
| last_name | VARCHAR(50) | NOT NULL | — | — | Family name |
| date_of_birth | DATE | NOT NULL | — | — | Used for age calculations |
| gender | VARCHAR(10) | NULL | — | CHECK IN ('Male','Female','Other') | Self-reported gender |
| national_id_hash | VARCHAR(64) | NULL | — | UNIQUE | bcrypt hash — never store plaintext |
| phone | VARCHAR(20) | NULL | — | — | Mobile number |
| email | VARCHAR(150) | NULL | — | — | Contact email |
| address | TEXT | NULL | — | — | Residential address |
| blood_type | VARCHAR(5) | NULL | — | — | ABO/Rh blood type |
| emergency_contact_name | VARCHAR(100) | NULL | — | — | Next of kin |
| emergency_contact_phone | VARCHAR(20) | NULL | — | — | Next of kin phone |
| insurance_provider | VARCHAR(100) | NULL | — | — | Insurance company |
| insurance_policy_number | VARCHAR(50) | NULL | — | — | Policy reference |
| is_active | BOOLEAN | NOT NULL | TRUE | — | FALSE = discharged/inactive |
| created_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Registration timestamp |

**Indexes:** idx_patients_last_first, idx_patients_dob, idx_patients_phone, idx_patients_is_active (partial), idx_patients_active_name (composite partial)

**RLS:** 6 policies — admin, doctor_select, nurse_select, receptionist, billing_select, analyst_select

---

## Table: appointments

Scheduled patient-doctor visits. Core table for the scheduling system. The EXCLUDE constraint prevents double-booking at the storage layer.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| appointment_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| patient_id | INTEGER | NOT NULL | — | FK → patients ON DELETE RESTRICT | Attending patient |
| doctor_id | INTEGER | NOT NULL | — | FK → doctors ON DELETE RESTRICT | Treating doctor |
| department_id | INTEGER | NOT NULL | — | FK → departments ON DELETE RESTRICT | Hosting department |
| scheduled_at | TIMESTAMPTZ | NOT NULL | — | — | Appointment start time |
| duration_minutes | SMALLINT | NOT NULL | 30 | CHECK > 0 | Slot length |
| status | VARCHAR(20) | NOT NULL | 'scheduled' | CHECK IN ('scheduled','confirmed','completed','cancelled','no_show') | Lifecycle state |
| reason | TEXT | NULL | — | — | Chief complaint |
| notes | TEXT | NULL | — | — | Additional clinical notes |
| created_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Record creation timestamp |
| updated_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Last modification (via trigger) |

**Exclusion constraint:** EXCLUDE USING GIST (doctor_id WITH =, tstzrange(...) WITH &&) WHERE status NOT IN ('cancelled','no_show')

**Indexes:** idx_appt_patient_id, idx_appt_doctor_id, idx_appt_department_id, idx_appt_doctor_scheduled (composite partial), idx_appt_patient_scheduled (composite), idx_appt_scheduled_at, idx_appt_status, idx_appt_created_brin (BRIN)

**RLS:** 6 policies

---

## Table: diagnoses

Clinical diagnoses recorded per appointment using ICD-10 codes.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| diagnosis_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| appointment_id | INTEGER | NOT NULL | — | FK → appointments ON DELETE CASCADE | Parent appointment |
| icd10_code | VARCHAR(10) | NOT NULL | — | — | ICD-10 classification code |
| description | TEXT | NOT NULL | — | — | Human-readable diagnosis description |
| severity | VARCHAR(20) | NULL | — | CHECK IN ('mild','moderate','severe','critical') | Clinical severity |
| diagnosed_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Time of diagnosis |

**Indexes:** idx_diagnoses_appointment_id, idx_diagnoses_icd10_code, idx_diagnoses_code_time (composite: icd10_code, diagnosed_at DESC)

**RLS:** 4 policies

---

## Table: prescriptions

Medications prescribed during appointments.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| prescription_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| appointment_id | INTEGER | NOT NULL | — | FK → appointments ON DELETE CASCADE | Parent appointment |
| medication_name | VARCHAR(150) | NOT NULL | — | — | Drug name (generic) |
| dosage | VARCHAR(50) | NOT NULL | — | — | Dose amount and unit |
| frequency | VARCHAR(50) | NOT NULL | — | — | Administration frequency |
| duration_days | SMALLINT | NOT NULL | — | CHECK > 0 | Treatment duration |
| instructions | TEXT | NULL | — | — | Special administration notes |
| prescribed_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Prescription timestamp |

**Indexes:** idx_prescriptions_appointment_id, idx_prescriptions_medication

**RLS:** 3 policies

---

## Table: wards

Inpatient wards and rooms.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| ward_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| name | VARCHAR(100) | NOT NULL | — | UNIQUE | Ward name |
| department_id | INTEGER | NULL | — | FK → departments ON DELETE SET NULL | Owning department |
| capacity | SMALLINT | NOT NULL | — | CHECK > 0 | Total bed count |
| ward_type | VARCHAR(30) | NULL | — | CHECK IN ('general','ICU','maternity','paediatric','surgical') | Classification |

**Indexes:** idx_wards_department_id, idx_wards_ward_type

---

## Table: admissions

Inpatient admission records. NULL discharged_at means currently admitted.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| admission_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| patient_id | INTEGER | NOT NULL | — | FK → patients ON DELETE RESTRICT | Admitted patient |
| ward_id | INTEGER | NOT NULL | — | FK → wards ON DELETE RESTRICT | Assigned ward |
| bed_number | VARCHAR(10) | NOT NULL | — | — | Specific bed identifier |
| admitted_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Admission timestamp |
| discharged_at | TIMESTAMPTZ | NULL | — | CHECK discharged_at > admitted_at | NULL = still admitted |
| admitting_doctor_id | INTEGER | NULL | — | FK → doctors ON DELETE SET NULL | Admitting physician |
| admission_notes | TEXT | NULL | — | — | Reason and clinical notes |

**Indexes:** idx_admissions_patient_id, idx_admissions_ward_id, idx_admissions_doctor_id, idx_admissions_active (partial: WHERE discharged_at IS NULL), idx_admissions_admitted_at

**RLS:** 4 policies

---

## Table: invoices

Financial invoices per appointment or admission. Amounts stored as integer cents.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| invoice_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| patient_id | INTEGER | NOT NULL | — | FK → patients ON DELETE RESTRICT | Billed patient |
| appointment_id | INTEGER | NULL | — | FK → appointments ON DELETE SET NULL | Source appointment |
| admission_id | INTEGER | NULL | — | FK → admissions ON DELETE SET NULL | Source admission |
| total_amount_cents | INTEGER | NOT NULL | — | CHECK >= 0 | Invoice total in UGX cents |
| paid_amount_cents | INTEGER | NOT NULL | 0 | CHECK >= 0, CHECK <= total | Amount received |
| status | VARCHAR(20) | NOT NULL | 'pending' | CHECK IN ('pending','partial','paid','waived') | Payment status (auto-synced via trigger) |
| issued_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Invoice issue timestamp |
| due_date | DATE | NOT NULL | — | — | Payment due date |

**Constraints:** chk_paid_lte_total, chk_invoice_source (appointment_id OR admission_id must be non-null)

**Indexes:** idx_invoices_patient_id, idx_invoices_appointment_id, idx_invoices_admission_id, idx_invoices_status, idx_invoices_unpaid (partial), idx_invoices_issued_at

**RLS:** 3 policies

---

## Table: payments

Individual payment transactions against invoices.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| payment_id | SERIAL | NOT NULL | auto | PK | Surrogate primary key |
| invoice_id | INTEGER | NOT NULL | — | FK → invoices ON DELETE RESTRICT | Parent invoice |
| amount_cents | INTEGER | NOT NULL | — | CHECK > 0 | Payment amount in UGX cents |
| payment_method | VARCHAR(30) | NULL | — | CHECK IN ('cash','mobile_money','card','insurance','waiver') | Payment channel |
| reference_number | VARCHAR(100) | NULL | — | — | Transaction reference (e.g. M-PESA ID) |
| paid_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Payment timestamp |

**Indexes:** idx_payments_invoice_id, idx_payments_paid_at, idx_payments_method

**Trigger:** fn_sync_invoice_status() — updates invoice.paid_amount_cents and status after each payment

**RLS:** 2 policies

---

## Table: audit_log

Immutable append-only change log for all sensitive table operations.

| Column | Type | Nullable | Default | Constraints | Description |
|--------|------|----------|---------|-------------|-------------|
| audit_id | BIGSERIAL | NOT NULL | auto | PK | Monotonically increasing audit record ID |
| table_name | VARCHAR(100) | NOT NULL | — | — | Name of the modified table |
| operation | VARCHAR(10) | NOT NULL | — | CHECK IN ('INSERT','UPDATE','DELETE') | DML operation type |
| record_id | INTEGER | NULL | — | — | PK value of the affected row |
| old_data | JSONB | NULL | — | — | Full row state before change (NULL for INSERT) |
| new_data | JSONB | NULL | — | — | Full row state after change (NULL for DELETE) |
| changed_by | VARCHAR(150) | NOT NULL | current_user | — | Database role that made the change |
| changed_at | TIMESTAMPTZ | NOT NULL | NOW() | — | Exact change timestamp |
| app_user_id | INTEGER | NULL | — | — | Application-layer user (from SET LOCAL app.user_id) |

**Indexes:** idx_audit_table_name, idx_audit_record_id (composite: table_name + record_id), idx_audit_changed_at (BRIN), idx_audit_changed_by

**RLS:** 3 policies — insert_only (all roles may insert), admin_select, auditor_select. No UPDATE or DELETE policy → default DENY.

**Covered tables:** patients, doctors, appointments, invoices, payments, admissions
