-- =============================================================================
-- V2__indexes.sql
-- Hospital Management System — Index Strategy
-- =============================================================================

-- DEPARTMENTS
CREATE INDEX idx_departments_name           ON departments (name);
CREATE INDEX idx_departments_head_doctor_id ON departments (head_doctor_id);

-- DOCTORS
CREATE INDEX idx_doctors_department_id  ON doctors (department_id);
CREATE INDEX idx_doctors_specialisation ON doctors (specialisation);
CREATE INDEX idx_doctors_email          ON doctors (email);
CREATE INDEX idx_doctors_is_active      ON doctors (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_doctors_last_first     ON doctors (last_name, first_name);

-- PATIENTS
CREATE INDEX idx_patients_last_first    ON patients (last_name, first_name);
CREATE INDEX idx_patients_dob           ON patients (date_of_birth);
CREATE INDEX idx_patients_phone         ON patients (phone);
CREATE INDEX idx_patients_is_active     ON patients (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_patients_active_name
    ON patients (last_name, first_name)
    WHERE is_active = TRUE;

-- APPOINTMENTS
CREATE INDEX idx_appt_patient_id    ON appointments (patient_id);
CREATE INDEX idx_appt_doctor_id     ON appointments (doctor_id);
CREATE INDEX idx_appt_department_id ON appointments (department_id);

-- Composite: most common query pattern — active appointments for a doctor
CREATE INDEX idx_appt_doctor_scheduled
    ON appointments (doctor_id, scheduled_at)
    WHERE status IN ('scheduled', 'confirmed');

-- Composite: patient appointment history, latest first
CREATE INDEX idx_appt_patient_scheduled
    ON appointments (patient_id, scheduled_at DESC);

CREATE INDEX idx_appt_scheduled_at ON appointments (scheduled_at);
CREATE INDEX idx_appt_status        ON appointments (status);
CREATE INDEX idx_appt_created_brin  ON appointments USING BRIN (created_at);

-- DIAGNOSES
CREATE INDEX idx_diagnoses_appointment_id ON diagnoses (appointment_id);
CREATE INDEX idx_diagnoses_icd10_code     ON diagnoses (icd10_code);
CREATE INDEX idx_diagnoses_code_time
    ON diagnoses (icd10_code, diagnosed_at DESC);

-- PRESCRIPTIONS
CREATE INDEX idx_prescriptions_appointment_id ON prescriptions (appointment_id);
CREATE INDEX idx_prescriptions_medication     ON prescriptions (medication_name);

-- WARDS
CREATE INDEX idx_wards_department_id ON wards (department_id);
CREATE INDEX idx_wards_ward_type     ON wards (ward_type);

-- ADMISSIONS
CREATE INDEX idx_admissions_patient_id  ON admissions (patient_id);
CREATE INDEX idx_admissions_ward_id     ON admissions (ward_id);
CREATE INDEX idx_admissions_doctor_id   ON admissions (admitting_doctor_id);
CREATE INDEX idx_admissions_active
    ON admissions (ward_id, admitted_at)
    WHERE discharged_at IS NULL;
CREATE INDEX idx_admissions_admitted_at ON admissions (admitted_at DESC);

-- INVOICES
CREATE INDEX idx_invoices_patient_id     ON invoices (patient_id);
CREATE INDEX idx_invoices_appointment_id ON invoices (appointment_id);
CREATE INDEX idx_invoices_admission_id   ON invoices (admission_id);
CREATE INDEX idx_invoices_status         ON invoices (status);
CREATE INDEX idx_invoices_unpaid
    ON invoices (patient_id, due_date)
    WHERE status IN ('pending', 'partial');
CREATE INDEX idx_invoices_issued_at ON invoices (issued_at DESC);

-- PAYMENTS
CREATE INDEX idx_payments_invoice_id     ON payments (invoice_id);
CREATE INDEX idx_payments_paid_at        ON payments (paid_at DESC);
CREATE INDEX idx_payments_method         ON payments (payment_method);

-- AUDIT LOG
CREATE INDEX idx_audit_table_name   ON audit_log (table_name);
CREATE INDEX idx_audit_record_id    ON audit_log (table_name, record_id);
CREATE INDEX idx_audit_changed_at   ON audit_log USING BRIN (changed_at);
CREATE INDEX idx_audit_changed_by   ON audit_log (changed_by);
