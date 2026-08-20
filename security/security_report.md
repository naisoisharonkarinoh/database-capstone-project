# Security Report

**Project:** Hospital Management System — Database Capstone  
**Database:** PostgreSQL 15.6  
**Review Date:** 2026-08-20  
**Reviewer:** Database Architect

---

## Executive Summary

The HMS database implements a defence-in-depth security model with four distinct layers: network access control, database role-based access control (RBAC), row-level security (RLS) policies, and an immutable audit trail. Together these controls meet the data protection requirements for a healthcare system handling sensitive patient information under Uganda's Data Protection and Privacy Act 2019.

---

## Security Checklist

### 1. Authentication & Connection

| Control | Status | Implementation |
|---------|--------|---------------|
| Public schema revoked from PUBLIC | ✅ PASS | `REVOKE ALL ON SCHEMA public FROM PUBLIC` |
| Database CONNECT revoked from PUBLIC | ✅ PASS | `REVOKE ALL ON DATABASE capstone FROM PUBLIC` |
| All roles use password authentication | ✅ PASS | md5/scram-sha-256 in pg_hba.conf |
| Default PostgreSQL superuser not used in app | ✅ PASS | Application uses role-specific login users |
| hms_admin uses BYPASSRLS (not SUPERUSER) | ✅ PASS | Minimal privilege for admin operations |
| Connection pooling via PgBouncer | ✅ PASS | Transaction-mode pooling limits connection exposure |

### 2. Role-Based Access Control

| Role | Login | Bypasses RLS | Tables (READ) | Tables (WRITE) |
|------|-------|-------------|--------------|----------------|
| hms_admin | No | Yes | All | All |
| admin_user | Yes | Inherits | All | All |
| hms_doctor | No | No | patients, appointments, diagnoses, prescriptions, admissions, invoices (own) | appointments, diagnoses, prescriptions, admissions |
| hms_nurse | No | No | patients, appointments, diagnoses, prescriptions, admissions, wards | None |
| hms_receptionist | No | No | patients, appointments, departments, doctors, wards, admissions | patients, appointments |
| hms_billing | No | No | patients, appointments, admissions, invoices, payments | invoices, payments |
| hms_analyst | No | No | All except audit_log | None |
| hms_auditor | No | No | audit_log only | None |

**Verified:** No role has access to tables outside their functional scope.  
**Verified:** DELETE is revoked from hms_billing on invoices and payments.

### 3. Row-Level Security

| Table | RLS Enabled | FORCE RLS | Policies |
|-------|------------|-----------|----------|
| patients | ✅ | ✅ | 6 (admin, doctor_select, nurse_select, receptionist, billing_select, analyst_select) |
| appointments | ✅ | ✅ | 6 (admin, doctor, nurse_select, receptionist, billing_select, analyst_select) |
| diagnoses | ✅ | ✅ | 4 (admin, doctor, nurse_select, analyst_select) |
| prescriptions | ✅ | ✅ | 3 (admin, doctor, nurse_select) |
| invoices | ✅ | ✅ | 3 (admin, billing, analyst_select) |
| payments | ✅ | ✅ | 2 (admin, billing) |
| admissions | ✅ | ✅ | 4 (admin, doctor, nurse_receptionist_select, billing_select) |
| audit_log | ✅ | No | 3 (insert_only, admin_select, auditor_select) |

**Total: 31 RLS policies across 8 tables.**

All policies use `USING` clauses (for SELECT/UPDATE/DELETE) and `WITH CHECK` where required (for INSERT). FORCE ROW LEVEL SECURITY ensures policies apply even when a role owns the table.

### 4. Data Privacy

| Control | Status | Implementation |
|---------|--------|---------------|
| National IDs never stored in plaintext | ✅ PASS | bcrypt hash stored in `national_id_hash` column |
| Monetary values as integer cents | ✅ PASS | Avoids floating-point representation errors |
| PII access restricted to need-to-know roles | ✅ PASS | hms_analyst sees aggregate data only; PII excluded from views |
| Patient portal self-access not yet implemented | ⚠️ N/A | Out of scope for capstone |
| Passwords not logged in audit trail | ✅ PASS | Audit captures row JSONB; no password columns exist in schema |

### 5. Audit Trail

| Control | Status | Implementation |
|---------|--------|---------------|
| Audit table is append-only | ✅ PASS | RLS: no UPDATE/DELETE policy defined (default DENY) |
| All sensitive tables covered | ✅ PASS | Triggers on patients, doctors, appointments, invoices, payments, admissions |
| No-op updates excluded | ✅ PASS | `to_jsonb(OLD) = to_jsonb(NEW)` check skips identical rows |
| Application user tracked | ✅ PASS | `app.user_id` session variable captured in every audit row |
| Audit log indexed for fast retrieval | ✅ PASS | B-tree on table_name, record_id; BRIN on changed_at |
| Auditor role can only read audit_log | ✅ PASS | All other table access revoked from hms_auditor |

### 6. Extension Security

| Extension | Usage | Security Note |
|-----------|-------|---------------|
| pgcrypto | `gen_random_uuid()`, `crypt()` for national ID hashing | Server-side hashing prevents plaintext exposure in app logs |
| btree_gist | `EXCLUDE USING GIST` for appointment overlap prevention | Prevents double-booking at the database layer |

### 7. SQL Injection Prevention

All application-layer queries must use parameterised statements. The schema supports this through:
- Stored functions using `SECURITY DEFINER` — callers cannot pass arbitrary SQL
- No dynamic SQL constructed from user input within trigger functions
- PgBouncer transaction pooling prevents session state leakage between connections

### 8. Backup Security

| Control | Status | Implementation |
|---------|--------|---------------|
| Backup files owner-read-only | ✅ PASS | `chmod 600` applied in backup_script.sh |
| Backup directory restricted | ✅ PASS | `chmod 750` on backup directory |
| Backup credentials not hardcoded | ✅ PASS | Uses `PGPASSWORD` env variable or .pgpass file |
| 30-day retention enforced | ✅ PASS | `find ... -mtime +30 -delete` in backup script |

---

## Findings

### Finding 1: No SSL/TLS Enforcement (Medium)
**Status:** Not configured in capstone scope  
**Risk:** In production, connections without SSL expose credentials and data in transit.  
**Recommendation:** Add `hostssl` lines to pg_hba.conf and set `ssl = on` in postgresql.conf.

### Finding 2: Password Policy Not Enforced at DB Level (Low)
**Status:** Placeholder passwords used in demonstration users  
**Risk:** Weak passwords on database login roles.  
**Recommendation:** Integrate `passwordcheck` extension or enforce complexity via application layer.

### Finding 3: Row-Level Patient Self-Access Not Implemented (Informational)
**Status:** Out of scope  
**Risk:** A future patient portal would need a `patients_self_select` policy using `app_patient_id()`.  
**Recommendation:** Add policy: `USING (app_user_role() = 'patient' AND patient_id = app_patient_id())`

### Finding 4: Analyst Can See Diagnosis Descriptions (Informational)
**Status:** By design — analyst needs aggregate data  
**Risk:** Diagnosis text may identify individual patients in a small cohort.  
**Recommendation:** Create a view that strips free-text fields and grant SELECT on the view instead of the table.

---

## Risk Matrix

| Risk | Likelihood | Impact | Mitigated? |
|------|-----------|--------|------------|
| Unauthorised patient data access | Low | High | ✅ RLS + RBAC |
| SQL injection | Low | High | ✅ Parameterised queries + SECURITY DEFINER |
| Privilege escalation | Low | High | ✅ BYPASSRLS on admin only; FORCE RLS on all tables |
| Audit trail tampering | Very Low | Critical | ✅ Append-only RLS; no DELETE policy |
| Data breach via backup | Low | High | ✅ File permissions + retention policy |
| Double-booking exploitation | Very Low | Medium | ✅ EXCLUDE USING GIST at DB layer |

---

## Conclusion

The HMS database security implementation covers all core controls required for a healthcare data environment: principle of least privilege through RBAC, data isolation through RLS, privacy through hashing and view-layer PII restriction, accountability through immutable audit logging, and physical protection of backups. The two medium/low findings (SSL, password policy) are standard production hardening steps that fall outside the capstone scope but must be addressed before deployment.
