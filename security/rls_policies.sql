-- =============================================================================
-- rls_policies.sql
-- Hospital Management System — Row-Level Security Policies (Standalone)
-- =============================================================================
-- This file documents all RLS policies applied to the HMS schema.
-- The canonical application of these policies is in V4__row_level_security.sql.
-- This standalone file is provided for audit and security review purposes.
--
-- Policy strategy:
--   • Policies use session variables set by the application layer:
--       SET LOCAL app.user_role = 'doctor';
--       SET LOCAL app.doctor_id = '7';
--   • FORCE ROW LEVEL SECURITY is applied to all sensitive tables so that
--     even table owners and role members cannot bypass policies.
--   • The hms_admin role is granted BYPASSRLS at the role level.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper Functions (SECURITY DEFINER — caller cannot inspect their internals)
-- ─────────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: patients
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients FORCE ROW LEVEL SECURITY;

-- Admin: unrestricted
CREATE POLICY patients_admin
    ON patients
    USING (app_user_role() = 'admin');

-- Doctor: only patients they have had an appointment with
CREATE POLICY patients_doctor_select
    ON patients FOR SELECT
    USING (
        app_user_role() = 'doctor'
        AND patient_id IN (
            SELECT patient_id FROM appointments
            WHERE  doctor_id = app_doctor_id()
        )
    );

-- Nurse: read all active patients
CREATE POLICY patients_nurse_select
    ON patients FOR SELECT
    USING (app_user_role() = 'nurse' AND is_active = TRUE);

-- Receptionist: full CRUD for registration workflow
CREATE POLICY patients_receptionist
    ON patients
    USING (app_user_role() = 'receptionist');

-- Billing staff: read active patients only
CREATE POLICY patients_billing_select
    ON patients FOR SELECT
    USING (app_user_role() = 'billing_staff' AND is_active = TRUE);

-- Analyst: read-only (PII exclusion enforced at view layer)
CREATE POLICY patients_analyst_select
    ON patients FOR SELECT
    USING (app_user_role() = 'readonly_analyst');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: appointments
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments FORCE ROW LEVEL SECURITY;

CREATE POLICY appointments_admin
    ON appointments
    USING (app_user_role() = 'admin');

-- Doctor: only their own appointments
CREATE POLICY appointments_doctor
    ON appointments
    USING (
        app_user_role() = 'doctor'
        AND doctor_id = app_doctor_id()
    );

-- Nurse: read-only across all appointments
CREATE POLICY appointments_nurse_select
    ON appointments FOR SELECT
    USING (app_user_role() = 'nurse');

-- Receptionist: full CRUD (creates and reschedules appointments)
CREATE POLICY appointments_receptionist
    ON appointments
    USING (app_user_role() = 'receptionist');

-- Billing: read-only (needs appointment to link to invoice)
CREATE POLICY appointments_billing_select
    ON appointments FOR SELECT
    USING (app_user_role() = 'billing_staff');

-- Analyst: read-only
CREATE POLICY appointments_analyst_select
    ON appointments FOR SELECT
    USING (app_user_role() = 'readonly_analyst');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: diagnoses
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE diagnoses FORCE ROW LEVEL SECURITY;

CREATE POLICY diagnoses_admin
    ON diagnoses USING (app_user_role() = 'admin');

-- Doctor: only diagnoses from their own appointments
CREATE POLICY diagnoses_doctor
    ON diagnoses
    USING (
        app_user_role() = 'doctor'
        AND appointment_id IN (
            SELECT appointment_id FROM appointments
            WHERE  doctor_id = app_doctor_id()
        )
    );

CREATE POLICY diagnoses_nurse_select
    ON diagnoses FOR SELECT USING (app_user_role() = 'nurse');

CREATE POLICY diagnoses_analyst_select
    ON diagnoses FOR SELECT USING (app_user_role() = 'readonly_analyst');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: prescriptions
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions FORCE ROW LEVEL SECURITY;

CREATE POLICY prescriptions_admin
    ON prescriptions USING (app_user_role() = 'admin');

CREATE POLICY prescriptions_doctor
    ON prescriptions
    USING (
        app_user_role() = 'doctor'
        AND appointment_id IN (
            SELECT appointment_id FROM appointments
            WHERE  doctor_id = app_doctor_id()
        )
    );

-- Nurses can read prescriptions (medication administration)
CREATE POLICY prescriptions_nurse_select
    ON prescriptions FOR SELECT USING (app_user_role() = 'nurse');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: invoices
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;

CREATE POLICY invoices_admin
    ON invoices USING (app_user_role() = 'admin');

-- Billing staff: full access to invoices
CREATE POLICY invoices_billing
    ON invoices USING (app_user_role() = 'billing_staff');

CREATE POLICY invoices_analyst_select
    ON invoices FOR SELECT USING (app_user_role() = 'readonly_analyst');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: payments
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments FORCE ROW LEVEL SECURITY;

CREATE POLICY payments_admin
    ON payments USING (app_user_role() = 'admin');

CREATE POLICY payments_billing
    ON payments USING (app_user_role() = 'billing_staff');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: admissions
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE admissions FORCE ROW LEVEL SECURITY;

CREATE POLICY admissions_admin
    ON admissions USING (app_user_role() = 'admin');

-- Doctor: only admissions where they are the admitting doctor
CREATE POLICY admissions_doctor
    ON admissions
    USING (
        app_user_role() = 'doctor'
        AND admitting_doctor_id = app_doctor_id()
    );

-- Nurses and receptionists: read all admissions (ward coordination)
CREATE POLICY admissions_nurse_receptionist_select
    ON admissions FOR SELECT
    USING (app_user_role() IN ('nurse','receptionist'));

-- Billing: read-only (needed for inpatient invoicing)
CREATE POLICY admissions_billing_select
    ON admissions FOR SELECT
    USING (app_user_role() = 'billing_staff');

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: audit_log (append-only enforcement)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- All roles may INSERT audit records (trigger runs as SECURITY DEFINER)
CREATE POLICY audit_insert_only
    ON audit_log FOR INSERT WITH CHECK (true);

-- Only hms_admin may SELECT audit records
CREATE POLICY audit_admin_select
    ON audit_log FOR SELECT
    USING (
        current_user = 'hms_admin'
        OR pg_has_role(current_user, 'hms_admin', 'MEMBER')
    );

-- Auditor role may also read (added separately)
CREATE POLICY audit_auditor_select
    ON audit_log FOR SELECT
    USING (pg_has_role(current_user, 'hms_auditor', 'MEMBER'));

-- Nobody may UPDATE or DELETE audit records — no policies defined for those operations
-- means the default-deny applies.

-- ─────────────────────────────────────────────────────────────────────────────
-- Policy Inventory (run after migration to verify)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM   pg_policies
WHERE  schemaname = 'public'
ORDER  BY tablename, policyname;
