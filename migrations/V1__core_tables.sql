-- =============================================================================
-- V1__core_tables.sql
-- Hospital Management System — Core Table Definitions
-- =============================================================================

-- Enable extensions needed across the schema
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- 1. DEPARTMENTS
CREATE TABLE departments (
    department_id   SERIAL          PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL UNIQUE,
    head_doctor_id  INTEGER,
    location        VARCHAR(100),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 2. DOCTORS
CREATE TABLE doctors (
    doctor_id       SERIAL          PRIMARY KEY,
    first_name      VARCHAR(50)     NOT NULL,
    last_name       VARCHAR(50)     NOT NULL,
    email           VARCHAR(150)    NOT NULL UNIQUE,
    phone           VARCHAR(20),
    specialisation  VARCHAR(100)    NOT NULL,
    department_id   INTEGER         REFERENCES departments(department_id) ON DELETE SET NULL,
    license_number  VARCHAR(50)     NOT NULL UNIQUE,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

ALTER TABLE departments
    ADD CONSTRAINT fk_dept_head_doctor
    FOREIGN KEY (head_doctor_id) REFERENCES doctors(doctor_id) ON DELETE SET NULL;

-- 3. PATIENTS
CREATE TABLE patients (
    patient_id              SERIAL          PRIMARY KEY,
    first_name              VARCHAR(50)     NOT NULL,
    last_name               VARCHAR(50)     NOT NULL,
    date_of_birth           DATE            NOT NULL,
    gender                  VARCHAR(10)     CHECK (gender IN ('Male','Female','Other')),
    national_id_hash        VARCHAR(64)     UNIQUE,
    phone                   VARCHAR(20),
    email                   VARCHAR(150),
    address                 TEXT,
    blood_type              VARCHAR(5),
    emergency_contact_name  VARCHAR(100),
    emergency_contact_phone VARCHAR(20),
    insurance_provider      VARCHAR(100),
    insurance_policy_number VARCHAR(50),
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 4. APPOINTMENTS
CREATE TABLE appointments (
    appointment_id   SERIAL          PRIMARY KEY,
    patient_id       INTEGER         NOT NULL REFERENCES patients(patient_id)   ON DELETE RESTRICT,
    doctor_id        INTEGER         NOT NULL REFERENCES doctors(doctor_id)      ON DELETE RESTRICT,
    department_id    INTEGER         NOT NULL REFERENCES departments(department_id) ON DELETE RESTRICT,
    scheduled_at     TIMESTAMPTZ     NOT NULL,
    duration_minutes SMALLINT        NOT NULL DEFAULT 30 CHECK (duration_minutes > 0),
    status           VARCHAR(20)     NOT NULL DEFAULT 'scheduled'
                                     CHECK (status IN ('scheduled','confirmed','completed','cancelled','no_show')),
    reason           TEXT,
    notes            TEXT,
    created_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    EXCLUDE USING GIST (
        doctor_id WITH =,
        tstzrange(scheduled_at, scheduled_at + (duration_minutes * interval '1 minute'), '[)') WITH &&
    ) WHERE (status NOT IN ('cancelled','no_show'))
);

-- 5. DIAGNOSES
CREATE TABLE diagnoses (
    diagnosis_id    SERIAL          PRIMARY KEY,
    appointment_id  INTEGER         NOT NULL REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    icd10_code      VARCHAR(10)     NOT NULL,
    description     TEXT            NOT NULL,
    severity        VARCHAR(20)     CHECK (severity IN ('mild','moderate','severe','critical')),
    diagnosed_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 6. PRESCRIPTIONS
CREATE TABLE prescriptions (
    prescription_id SERIAL          PRIMARY KEY,
    appointment_id  INTEGER         NOT NULL REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    medication_name VARCHAR(150)    NOT NULL,
    dosage          VARCHAR(50)     NOT NULL,
    frequency       VARCHAR(50)     NOT NULL,
    duration_days   SMALLINT        NOT NULL CHECK (duration_days > 0),
    instructions    TEXT,
    prescribed_at   TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 7. WARDS
CREATE TABLE wards (
    ward_id         SERIAL          PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL UNIQUE,
    department_id   INTEGER         REFERENCES departments(department_id) ON DELETE SET NULL,
    capacity        SMALLINT        NOT NULL CHECK (capacity > 0),
    ward_type       VARCHAR(30)     CHECK (ward_type IN ('general','ICU','maternity','paediatric','surgical'))
);

-- 8. ADMISSIONS
CREATE TABLE admissions (
    admission_id        SERIAL          PRIMARY KEY,
    patient_id          INTEGER         NOT NULL REFERENCES patients(patient_id)    ON DELETE RESTRICT,
    ward_id             INTEGER         NOT NULL REFERENCES wards(ward_id)          ON DELETE RESTRICT,
    bed_number          VARCHAR(10)     NOT NULL,
    admitted_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    discharged_at       TIMESTAMPTZ,
    admitting_doctor_id INTEGER         REFERENCES doctors(doctor_id)               ON DELETE SET NULL,
    admission_notes     TEXT,
    CONSTRAINT chk_discharge_after_admit CHECK (discharged_at IS NULL OR discharged_at > admitted_at)
);

-- 9. INVOICES
CREATE TABLE invoices (
    invoice_id          SERIAL          PRIMARY KEY,
    patient_id          INTEGER         NOT NULL REFERENCES patients(patient_id)        ON DELETE RESTRICT,
    appointment_id      INTEGER         REFERENCES appointments(appointment_id)         ON DELETE SET NULL,
    admission_id        INTEGER         REFERENCES admissions(admission_id)             ON DELETE SET NULL,
    total_amount_cents  INTEGER         NOT NULL CHECK (total_amount_cents >= 0),
    paid_amount_cents   INTEGER         NOT NULL DEFAULT 0 CHECK (paid_amount_cents >= 0),
    status              VARCHAR(20)     NOT NULL DEFAULT 'pending'
                                         CHECK (status IN ('pending','partial','paid','waived')),
    issued_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    due_date            DATE            NOT NULL,
    CONSTRAINT chk_paid_lte_total CHECK (paid_amount_cents <= total_amount_cents),
    CONSTRAINT chk_invoice_source  CHECK (appointment_id IS NOT NULL OR admission_id IS NOT NULL)
);

-- 10. PAYMENTS
CREATE TABLE payments (
    payment_id       SERIAL          PRIMARY KEY,
    invoice_id       INTEGER         NOT NULL REFERENCES invoices(invoice_id) ON DELETE RESTRICT,
    amount_cents     INTEGER         NOT NULL CHECK (amount_cents > 0),
    payment_method   VARCHAR(30)     CHECK (payment_method IN ('cash','mobile_money','card','insurance','waiver')),
    reference_number VARCHAR(100),
    paid_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 11. AUDIT LOG
CREATE TABLE audit_log (
    audit_id    BIGSERIAL       PRIMARY KEY,
    table_name  VARCHAR(100)    NOT NULL,
    operation   VARCHAR(10)     NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    record_id   INTEGER,
    old_data    JSONB,
    new_data    JSONB,
    changed_by  VARCHAR(150)    NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    app_user_id INTEGER
);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_insert_only ON audit_log FOR INSERT WITH CHECK (true);
CREATE POLICY audit_admin_select ON audit_log
    FOR SELECT USING (current_user = 'hms_admin' OR pg_has_role(current_user, 'hms_admin', 'MEMBER'));
