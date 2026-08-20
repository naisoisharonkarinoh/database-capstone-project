-- =============================================================================
-- V4__row_level_security.sql
-- Hospital Management System — Row-Level Security (RLS)
-- =============================================================================

-- Helper functions: read session variables set by application layer
CREATE OR REPLACE FUNCTION app_user_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT COALESCE(current_setting('app.user_role', true), 'anonymous');
$$;

CREATE OR REPLACE FUNCTION app_doctor_id()
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT NULLIF(current_setting('app.doctor_id', true), '')::INTEGER;
$$;

CREATE OR REPLACE FUNCTION app_patient_id()
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT NULLIF(current_setting('app.patient_id', true), '')::INTEGER;
$$;

-- =============================================================================
-- PATIENTS
-- =============================================================================
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients FORCE ROW LEVEL SECURITY;

CREATE POLICY patients_admin       ON patients USING (app_user_role() = 'admin');
CREATE POLICY patients_receptionist ON patients USING (app_user_role() = 'receptionist');

CREATE POLICY patients_doctor_select ON patients FOR SELECT
    USING (app_user_role() = 'doctor' AND patient_id IN (
        SELECT patient_id FROM appointments WHERE doctor_id = app_doctor_id()
    ));

CREATE POLICY patients_nurse_select ON patients FOR SELECT
    USING (app_user_role() = 'nurse' AND is_active = TRUE);

CREATE POLICY patients_billing_select ON patients FOR SELECT
    USING (app_user_role() = 'billing_staff' AND is_active = TRUE);

CREATE POLICY patients_analyst_select ON patients FOR SELECT
    USING (app_user_role() = 'readonly_analyst');

-- =============================================================================
-- APPOINTMENTS
-- =============================================================================
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments FORCE ROW LEVEL SECURITY;

CREATE POLICY appointments_admin       ON appointments USING (app_user_role() = 'admin');
CREATE POLICY appointments_receptionist ON appointments USING (app_user_role() = 'receptionist');
CREATE POLICY appointments_doctor      ON appointments
    USING (app_user_role() = 'doctor' AND doctor_id = app_doctor_id());
CREATE POLICY appointments_nurse_select   ON appointments FOR SELECT USING (app_user_role() = 'nurse');
CREATE POLICY appointments_billing_select ON appointments FOR SELECT USING (app_user_role() = 'billing_staff');
CREATE POLICY appointments_analyst_select ON appointments FOR SELECT USING (app_user_role() = 'readonly_analyst');

-- =============================================================================
-- DIAGNOSES
-- =============================================================================
ALTER TABLE diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE diagnoses FORCE ROW LEVEL SECURITY;

CREATE POLICY diagnoses_admin ON diagnoses USING (app_user_role() = 'admin');
CREATE POLICY diagnoses_doctor ON diagnoses
    USING (app_user_role() = 'doctor' AND appointment_id IN (
        SELECT appointment_id FROM appointments WHERE doctor_id = app_doctor_id()
    ));
CREATE POLICY diagnoses_nurse_select   ON diagnoses FOR SELECT USING (app_user_role() = 'nurse');
CREATE POLICY diagnoses_analyst_select ON diagnoses FOR SELECT USING (app_user_role() = 'readonly_analyst');

-- =============================================================================
-- PRESCRIPTIONS
-- =============================================================================
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions FORCE ROW LEVEL SECURITY;

CREATE POLICY prescriptions_admin ON prescriptions USING (app_user_role() = 'admin');
CREATE POLICY prescriptions_doctor ON prescriptions
    USING (app_user_role() = 'doctor' AND appointment_id IN (
        SELECT appointment_id FROM appointments WHERE doctor_id = app_doctor_id()
    ));
CREATE POLICY prescriptions_nurse_select ON prescriptions FOR SELECT USING (app_user_role() = 'nurse');

-- =============================================================================
-- INVOICES
-- =============================================================================
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;

CREATE POLICY invoices_admin          ON invoices USING (app_user_role() = 'admin');
CREATE POLICY invoices_billing        ON invoices USING (app_user_role() = 'billing_staff');
CREATE POLICY invoices_analyst_select ON invoices FOR SELECT USING (app_user_role() = 'readonly_analyst');

-- =============================================================================
-- PAYMENTS
-- =============================================================================
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments FORCE ROW LEVEL SECURITY;

CREATE POLICY payments_admin   ON payments USING (app_user_role() = 'admin');
CREATE POLICY payments_billing ON payments USING (app_user_role() = 'billing_staff');

-- =============================================================================
-- ADMISSIONS
-- =============================================================================
ALTER TABLE admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions FORCE ROW LEVEL SECURITY;

CREATE POLICY admissions_admin ON admissions USING (app_user_role() = 'admin');
CREATE POLICY admissions_doctor ON admissions
    USING (app_user_role() = 'doctor' AND admitting_doctor_id = app_doctor_id());
CREATE POLICY admissions_nurse_select   ON admissions FOR SELECT USING (app_user_role() IN ('nurse','receptionist'));
CREATE POLICY admissions_billing_select ON admissions FOR SELECT USING (app_user_role() = 'billing_staff');
