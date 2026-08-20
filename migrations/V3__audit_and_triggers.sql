-- =============================================================================
-- V3__audit_and_triggers.sql
-- Hospital Management System — Audit Trail & Triggers
-- =============================================================================

-- 1. GENERIC AUDIT TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record_id  INTEGER;
    v_old_data   JSONB;
    v_new_data   JSONB;
    v_app_user   INTEGER;
BEGIN
    BEGIN
        v_app_user := current_setting('app.user_id', true)::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        v_app_user := NULL;
    END;

    IF TG_OP = 'INSERT' THEN
        v_new_data  := to_jsonb(NEW);
        v_record_id := (NEW::TEXT::JSONB ->> (TG_ARGV[0]))::INTEGER;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Skip no-op updates
        IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
        v_old_data  := to_jsonb(OLD);
        v_new_data  := to_jsonb(NEW);
        v_record_id := (NEW::TEXT::JSONB ->> (TG_ARGV[0]))::INTEGER;
    ELSIF TG_OP = 'DELETE' THEN
        v_old_data  := to_jsonb(OLD);
        v_record_id := (OLD::TEXT::JSONB ->> (TG_ARGV[0]))::INTEGER;
    END IF;

    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, changed_by, app_user_id)
    VALUES (TG_TABLE_NAME, TG_OP, v_record_id, v_old_data, v_new_data, current_user, v_app_user);

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 2. ATTACH AUDIT TRIGGERS
CREATE TRIGGER trg_audit_patients
    AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('patient_id');

CREATE TRIGGER trg_audit_doctors
    AFTER INSERT OR UPDATE OR DELETE ON doctors
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('doctor_id');

CREATE TRIGGER trg_audit_appointments
    AFTER INSERT OR UPDATE OR DELETE ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('appointment_id');

CREATE TRIGGER trg_audit_invoices
    AFTER INSERT OR UPDATE OR DELETE ON invoices
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('invoice_id');

CREATE TRIGGER trg_audit_payments
    AFTER INSERT OR UPDATE OR DELETE ON payments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('payment_id');

CREATE TRIGGER trg_audit_admissions
    AFTER INSERT OR UPDATE OR DELETE ON admissions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger('admission_id');

-- 3. AUTO-UPDATE updated_at ON appointments
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- 4. AUTO-SYNC invoice status AFTER each payment
CREATE OR REPLACE FUNCTION fn_sync_invoice_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_total  INTEGER;
    v_paid   INTEGER;
    v_status VARCHAR(20);
BEGIN
    SELECT total_amount_cents,
           COALESCE((SELECT SUM(amount_cents) FROM payments WHERE invoice_id = NEW.invoice_id), 0)
    INTO   v_total, v_paid
    FROM   invoices WHERE invoice_id = NEW.invoice_id;

    v_status := CASE
        WHEN v_paid = 0      THEN 'pending'
        WHEN v_paid < v_total THEN 'partial'
        ELSE 'paid'
    END;

    UPDATE invoices
    SET    paid_amount_cents = v_paid, status = v_status
    WHERE  invoice_id = NEW.invoice_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_invoice_status
    AFTER INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION fn_sync_invoice_status();

-- 5. PREVENT APPOINTMENT FOR INACTIVE DOCTOR / PATIENT
CREATE OR REPLACE FUNCTION fn_check_appointment_active()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT (SELECT is_active FROM doctors  WHERE doctor_id  = NEW.doctor_id)  THEN
        RAISE EXCEPTION 'Cannot book appointment: doctor % is inactive', NEW.doctor_id;
    END IF;
    IF NOT (SELECT is_active FROM patients WHERE patient_id = NEW.patient_id) THEN
        RAISE EXCEPTION 'Cannot book appointment: patient % is inactive', NEW.patient_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointment_active_check
    BEFORE INSERT OR UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_check_appointment_active();

-- 6. DOCTOR APPOINTMENT SUMMARY VIEW
CREATE OR REPLACE VIEW v_doctor_daily_appointments AS
SELECT
    d.doctor_id,
    d.first_name || ' ' || d.last_name AS doctor_name,
    d.specialisation,
    DATE(a.scheduled_at AT TIME ZONE 'Africa/Nairobi') AS appointment_date,
    COUNT(*)                                            AS total_appointments,
    COUNT(*) FILTER (WHERE a.status = 'completed')     AS completed,
    COUNT(*) FILTER (WHERE a.status = 'cancelled')     AS cancelled,
    COUNT(*) FILTER (WHERE a.status = 'no_show')       AS no_shows
FROM appointments a
JOIN doctors d USING (doctor_id)
GROUP BY d.doctor_id, d.first_name, d.last_name, d.specialisation,
         DATE(a.scheduled_at AT TIME ZONE 'Africa/Nairobi');
