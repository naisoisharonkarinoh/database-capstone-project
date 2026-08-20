-- =============================================================================
-- audit_implementation.sql
-- Hospital Management System — Audit Table, Triggers & Helpers (Standalone)
-- =============================================================================
-- This file is a standalone reference for the audit subsystem.
-- The canonical implementation lives in V3__audit_and_triggers.sql.
--
-- Design principles:
--   • Single generic trigger function (fn_audit_trigger) handles all tables.
--   • SECURITY DEFINER ensures the trigger writes to audit_log regardless of
--     the caller's role — even if the caller has no direct INSERT permission.
--   • No-op UPDATE detection: if OLD and NEW data are identical, no audit row
--     is written (avoids flooding the log with heartbeat updates).
--   • app.user_id session variable captures the application-layer user ID
--     (separate from the database role) for end-to-end accountability.
--   • audit_log is append-only: RLS blocks all UPDATE and DELETE; no policy
--     is defined for those operations so the default DENY applies.
-- =============================================================================

-- =============================================================================
-- 1. Audit Log Table
-- =============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id    BIGSERIAL       PRIMARY KEY,
    table_name  VARCHAR(100)    NOT NULL,
    operation   VARCHAR(10)     NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    record_id   INTEGER,                        -- PK of the affected row
    old_data    JSONB,                          -- Previous row state (NULL for INSERT)
    new_data    JSONB,                          -- New row state (NULL for DELETE)
    changed_by  VARCHAR(150)    NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    app_user_id INTEGER         -- Application-layer user (SET LOCAL app.user_id = ...)
);

COMMENT ON TABLE  audit_log IS 'Immutable audit trail — append-only via RLS';
COMMENT ON COLUMN audit_log.old_data    IS 'Full row snapshot before change (NULL for INSERT)';
COMMENT ON COLUMN audit_log.new_data    IS 'Full row snapshot after change (NULL for DELETE)';
COMMENT ON COLUMN audit_log.app_user_id IS 'App-layer user ID from SET LOCAL app.user_id';

-- Make append-only at database level
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS audit_insert_only
    ON audit_log FOR INSERT WITH CHECK (true);

CREATE POLICY IF NOT EXISTS audit_admin_select
    ON audit_log FOR SELECT
    USING (
        current_user = 'hms_admin'
        OR pg_has_role(current_user, 'hms_admin', 'MEMBER')
        OR pg_has_role(current_user, 'hms_auditor', 'MEMBER')
    );

-- Indexes on audit_log
CREATE INDEX IF NOT EXISTS idx_audit_table_name ON audit_log (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_record_id  ON audit_log (table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_changed_at ON audit_log USING BRIN (changed_at);
CREATE INDEX IF NOT EXISTS idx_audit_changed_by ON audit_log (changed_by);

-- =============================================================================
-- 2. Generic Audit Trigger Function
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER   -- runs as the function owner, not the calling role
SET search_path = public
AS $$
DECLARE
    v_record_id  INTEGER;
    v_old_data   JSONB;
    v_new_data   JSONB;
    v_app_user   INTEGER;
BEGIN
    -- Capture application-layer user ID (returns NULL if not set)
    v_app_user := NULLIF(current_setting('app.user_id', true), '')::INTEGER;

    IF TG_OP = 'INSERT' THEN
        v_record_id := NEW.tableoid::INTEGER;  -- fallback
        -- Try to get the actual PK value dynamically
        BEGIN
            EXECUTE format('SELECT ($1).%I', TG_TABLE_NAME || '_id')
                INTO v_record_id USING NEW;
        EXCEPTION WHEN OTHERS THEN
            -- Table uses a different PK name — use row's ctid as fallback
            v_record_id := NULL;
        END;
        v_new_data  := to_jsonb(NEW);
        v_old_data  := NULL;

    ELSIF TG_OP = 'UPDATE' THEN
        -- Skip no-op updates (identical rows)
        IF to_jsonb(OLD) = to_jsonb(NEW) THEN
            RETURN NEW;
        END IF;
        BEGIN
            EXECUTE format('SELECT ($1).%I', TG_TABLE_NAME || '_id')
                INTO v_record_id USING NEW;
        EXCEPTION WHEN OTHERS THEN
            v_record_id := NULL;
        END;
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);

    ELSIF TG_OP = 'DELETE' THEN
        BEGIN
            EXECUTE format('SELECT ($1).%I', TG_TABLE_NAME || '_id')
                INTO v_record_id USING OLD;
        EXCEPTION WHEN OTHERS THEN
            v_record_id := NULL;
        END;
        v_old_data := to_jsonb(OLD);
        v_new_data := NULL;
    END IF;

    INSERT INTO audit_log (
        table_name, operation, record_id,
        old_data, new_data,
        changed_by, app_user_id
    ) VALUES (
        TG_TABLE_NAME, TG_OP, v_record_id,
        v_old_data, v_new_data,
        current_user, v_app_user
    );

    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

COMMENT ON FUNCTION fn_audit_trigger() IS
    'Generic AFTER trigger that records INSERT/UPDATE/DELETE to audit_log. '
    'Skips no-op updates. Uses app.user_id session variable for app-layer attribution.';

-- =============================================================================
-- 3. Attach Audit Triggers to Sensitive Tables
-- =============================================================================

-- patients (PII changes must be fully audited)
DROP TRIGGER IF EXISTS trg_audit_patients ON patients;
CREATE TRIGGER trg_audit_patients
    AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- doctors (credential and department changes)
DROP TRIGGER IF EXISTS trg_audit_doctors ON doctors;
CREATE TRIGGER trg_audit_doctors
    AFTER INSERT OR UPDATE OR DELETE ON doctors
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- appointments (scheduling changes)
DROP TRIGGER IF EXISTS trg_audit_appointments ON appointments;
CREATE TRIGGER trg_audit_appointments
    AFTER INSERT OR UPDATE OR DELETE ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- invoices (financial integrity)
DROP TRIGGER IF EXISTS trg_audit_invoices ON invoices;
CREATE TRIGGER trg_audit_invoices
    AFTER INSERT OR UPDATE OR DELETE ON invoices
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- payments (financial integrity)
DROP TRIGGER IF EXISTS trg_audit_payments ON payments;
CREATE TRIGGER trg_audit_payments
    AFTER INSERT OR UPDATE OR DELETE ON payments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- admissions (inpatient tracking)
DROP TRIGGER IF EXISTS trg_audit_admissions ON admissions;
CREATE TRIGGER trg_audit_admissions
    AFTER INSERT OR UPDATE OR DELETE ON admissions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- =============================================================================
-- 4. Helper: Query Recent Audit Trail for a Table
-- =============================================================================
CREATE OR REPLACE FUNCTION audit_recent(
    p_table  VARCHAR,
    p_hours  INTEGER DEFAULT 24
)
RETURNS TABLE (
    audit_id    BIGINT,
    operation   VARCHAR,
    record_id   INTEGER,
    changed_by  VARCHAR,
    app_user_id INTEGER,
    changed_at  TIMESTAMPTZ,
    old_data    JSONB,
    new_data    JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT
        audit_id, operation, record_id,
        changed_by, app_user_id, changed_at,
        old_data, new_data
    FROM   audit_log
    WHERE  table_name  = p_table
      AND  changed_at >= NOW() - (p_hours || ' hours')::INTERVAL
    ORDER  BY changed_at DESC;
$$;

COMMENT ON FUNCTION audit_recent(VARCHAR, INTEGER) IS
    'Returns recent audit entries for a given table within the last N hours (default 24).';

-- =============================================================================
-- 5. Verify Trigger Installation
-- =============================================================================
SELECT
    trigger_name,
    event_manipulation  AS event,
    event_object_table  AS table_name,
    action_timing       AS timing,
    action_orientation  AS level
FROM   information_schema.triggers
WHERE  trigger_schema = 'public'
  AND  trigger_name LIKE 'trg_audit_%'
ORDER  BY event_object_table, event_manipulation;
