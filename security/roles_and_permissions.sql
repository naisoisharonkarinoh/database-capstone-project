-- =============================================================================
-- roles_and_permissions.sql
-- Hospital Management System — Roles, Login Users & Grants
-- =============================================================================
-- Role hierarchy:
--   hms_admin       (superuser-equivalent — bypasses RLS via BYPASSRLS)
--   hms_doctor      (own patients + appointments + clinical records)
--   hms_nurse       (read-all appointments, patients; no write to clinical)
--   hms_receptionist (patient registration + appointment management)
--   hms_billing     (invoices + payments; no clinical data)
--   hms_analyst     (read-only across all non-PII tables)
--   hms_auditor     (read-only on audit_log only)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Step 1: Revoke public schema access from PUBLIC
-- By default PostgreSQL grants CONNECT + USAGE to PUBLIC. Remove it.
-- ---------------------------------------------------------------------------
REVOKE ALL ON DATABASE capstone FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Re-grant USAGE to roles that need it (applied below per role)

-- ---------------------------------------------------------------------------
-- Step 2: Create group roles (no LOGIN)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_admin') THEN
        CREATE ROLE hms_admin NOLOGIN BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_doctor') THEN
        CREATE ROLE hms_doctor NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_nurse') THEN
        CREATE ROLE hms_nurse NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_receptionist') THEN
        CREATE ROLE hms_receptionist NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_billing') THEN
        CREATE ROLE hms_billing NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_analyst') THEN
        CREATE ROLE hms_analyst NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hms_auditor') THEN
        CREATE ROLE hms_auditor NOLOGIN;
    END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Step 3: Create login users (one per role for demonstration)
-- IMPORTANT: Use strong passwords in production — these are placeholders.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
        CREATE ROLE admin_user LOGIN PASSWORD 'Adm!nS3cur3#2026' IN ROLE hms_admin;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctor_user') THEN
        CREATE ROLE doctor_user LOGIN PASSWORD 'D0ct0rP@ss#2026' IN ROLE hms_doctor;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nurse_user') THEN
        CREATE ROLE nurse_user LOGIN PASSWORD 'Nurs3P@ss#2026' IN ROLE hms_nurse;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reception_user') THEN
        CREATE ROLE reception_user LOGIN PASSWORD 'R3c3pt!on#2026' IN ROLE hms_receptionist;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'billing_user') THEN
        CREATE ROLE billing_user LOGIN PASSWORD 'B!ll!ng#2026' IN ROLE hms_billing;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analyst_user') THEN
        CREATE ROLE analyst_user LOGIN PASSWORD 'An@lyst#2026' IN ROLE hms_analyst;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auditor_user') THEN
        CREATE ROLE auditor_user LOGIN PASSWORD 'Aud!t0r#2026' IN ROLE hms_auditor;
    END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Step 4: Grant CONNECT and USAGE on schema to all HMS roles
-- ---------------------------------------------------------------------------
GRANT CONNECT ON DATABASE capstone TO
    hms_admin, hms_doctor, hms_nurse, hms_receptionist,
    hms_billing, hms_analyst, hms_auditor;

GRANT USAGE ON SCHEMA public TO
    hms_admin, hms_doctor, hms_nurse, hms_receptionist,
    hms_billing, hms_analyst, hms_auditor;

-- ---------------------------------------------------------------------------
-- Step 5: hms_admin — full access to everything
-- ---------------------------------------------------------------------------
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO hms_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hms_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO hms_admin;

-- Future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES    TO hms_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO hms_admin;

-- ---------------------------------------------------------------------------
-- Step 6: hms_doctor — clinical read/write for own patients
-- RLS policies enforce the per-doctor row filter.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON
    patients, appointments, diagnoses, prescriptions, admissions
    TO hms_doctor;

GRANT SELECT ON
    departments, doctors, wards
    TO hms_doctor;

-- Doctors can view their own invoices (read-only) for patient billing queries
GRANT SELECT ON invoices TO hms_doctor;

-- Sequence access for INSERT
GRANT USAGE ON SEQUENCE
    appointments_appointment_id_seq,
    diagnoses_diagnosis_id_seq,
    prescriptions_prescription_id_seq,
    admissions_admission_id_seq
    TO hms_doctor;

-- ---------------------------------------------------------------------------
-- Step 7: hms_nurse — read all clinical records, no writes
-- ---------------------------------------------------------------------------
GRANT SELECT ON
    patients, appointments, diagnoses, prescriptions,
    admissions, wards, departments, doctors
    TO hms_nurse;

-- Nurses do NOT get access to invoices or payments

-- ---------------------------------------------------------------------------
-- Step 8: hms_receptionist — patient registration + appointment management
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON
    patients, appointments
    TO hms_receptionist;

GRANT SELECT ON
    departments, doctors, wards, admissions
    TO hms_receptionist;

GRANT USAGE ON SEQUENCE
    patients_patient_id_seq,
    appointments_appointment_id_seq
    TO hms_receptionist;

-- ---------------------------------------------------------------------------
-- Step 9: hms_billing — invoices and payments only
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON
    invoices, payments
    TO hms_billing;

GRANT SELECT ON
    patients, appointments, admissions
    TO hms_billing;

GRANT USAGE ON SEQUENCE
    invoices_invoice_id_seq,
    payments_payment_id_seq
    TO hms_billing;

-- Billing staff cannot DELETE invoices or payments — only admin can
REVOKE DELETE ON invoices, payments FROM hms_billing;

-- ---------------------------------------------------------------------------
-- Step 10: hms_analyst — read-only across all tables (PII excluded via views)
-- ---------------------------------------------------------------------------
-- Grant on underlying tables for aggregation queries
GRANT SELECT ON
    departments, doctors, patients, appointments,
    diagnoses, prescriptions, wards, admissions,
    invoices, payments
    TO hms_analyst;

-- Analyst explicitly CANNOT read audit_log
REVOKE ALL ON audit_log FROM hms_analyst;

-- ---------------------------------------------------------------------------
-- Step 11: hms_auditor — audit_log read-only; nothing else
-- ---------------------------------------------------------------------------
GRANT SELECT ON audit_log TO hms_auditor;

-- Auditors must not see clinical or financial data
REVOKE ALL ON
    patients, appointments, diagnoses, prescriptions,
    admissions, invoices, payments
    FROM hms_auditor;

-- ---------------------------------------------------------------------------
-- Step 12: Force RLS for all non-superuser roles
-- Even table owners obey RLS policies unless BYPASSRLS is set.
-- ---------------------------------------------------------------------------
ALTER TABLE patients      FORCE ROW LEVEL SECURITY;
ALTER TABLE appointments  FORCE ROW LEVEL SECURITY;
ALTER TABLE diagnoses     FORCE ROW LEVEL SECURITY;
ALTER TABLE prescriptions FORCE ROW LEVEL SECURITY;
ALTER TABLE invoices      FORCE ROW LEVEL SECURITY;
ALTER TABLE payments      FORCE ROW LEVEL SECURITY;
ALTER TABLE admissions    FORCE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Step 13: Restrict EXECUTE on sensitive functions
-- Only hms_admin may call pg_dump-style functions; restrict advisory locks.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION app_user_role()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION app_doctor_id()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION app_patient_id() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_user_role()  TO hms_doctor, hms_nurse, hms_receptionist, hms_billing, hms_analyst;
GRANT EXECUTE ON FUNCTION app_doctor_id()  TO hms_doctor;
GRANT EXECUTE ON FUNCTION app_patient_id() TO hms_doctor, hms_receptionist, hms_billing;

-- ---------------------------------------------------------------------------
-- Verification: list roles and their membership
-- ---------------------------------------------------------------------------
SELECT
    r.rolname                             AS role_name,
    r.rollogin                            AS can_login,
    r.rolbypassrls                        AS bypasses_rls,
    r.rolcreatedb                         AS can_createdb,
    r.rolsuper                            AS is_superuser,
    array_agg(m.rolname ORDER BY m.rolname) FILTER (WHERE m.rolname IS NOT NULL)
                                          AS member_of
FROM   pg_roles r
LEFT JOIN pg_auth_members am ON am.member = r.oid
LEFT JOIN pg_roles m         ON m.oid     = am.roleid
WHERE  r.rolname LIKE 'hms_%' OR r.rolname LIKE '%_user'
GROUP  BY r.rolname, r.rollogin, r.rolbypassrls, r.rolcreatedb, r.rolsuper
ORDER  BY r.rolname;
