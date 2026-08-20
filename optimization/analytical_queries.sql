-- =============================================================================
-- analytical_queries.sql
-- Hospital Management System — Analytical & Reporting Queries
-- 3 analytical + 2 aggregation + 1 window function query
-- =============================================================================

-- Q1 (ANALYTICAL): Doctor Utilisation Rate — Last 30 Days
EXPLAIN ANALYZE
SELECT
    d.doctor_id,
    d.first_name || ' ' || d.last_name   AS doctor_name,
    d.specialisation,
    dept.name                             AS department,
    COUNT(a.appointment_id)               AS total_appointments,
    COUNT(a.appointment_id) FILTER (WHERE a.status = 'completed')  AS completed,
    COUNT(a.appointment_id) FILTER (WHERE a.status = 'no_show')    AS no_shows,
    COUNT(a.appointment_id) FILTER (WHERE a.status = 'cancelled')  AS cancelled,
    ROUND(
        COUNT(a.appointment_id)::NUMERIC / NULLIF(22 * 16, 0) * 100, 1
    ) AS utilisation_pct
FROM   doctors d
JOIN   departments dept USING (department_id)
LEFT JOIN appointments a
       ON  a.doctor_id    = d.doctor_id
       AND a.scheduled_at >= NOW() - INTERVAL '30 days'
WHERE  d.is_active = TRUE
GROUP  BY d.doctor_id, d.first_name, d.last_name, d.specialisation, dept.name
ORDER  BY utilisation_pct DESC NULLS LAST;

-- Q2 (ANALYTICAL): Top 10 Diagnoses — Last 6 Months
EXPLAIN ANALYZE
SELECT
    dx.icd10_code,
    dx.description,
    COUNT(*)                              AS diagnosis_count,
    COUNT(*) FILTER (WHERE p.gender = 'Male')   AS male_count,
    COUNT(*) FILTER (WHERE p.gender = 'Female') AS female_count,
    AVG(DATE_PART('year', AGE(p.date_of_birth)))::INT AS avg_patient_age,
    COUNT(*) FILTER (WHERE DATE_PART('year', AGE(p.date_of_birth)) < 18)  AS under_18,
    COUNT(*) FILTER (WHERE DATE_PART('year', AGE(p.date_of_birth)) BETWEEN 18 AND 45) AS age_18_45,
    COUNT(*) FILTER (WHERE DATE_PART('year', AGE(p.date_of_birth)) > 45)  AS over_45
FROM   diagnoses dx
JOIN   appointments a  USING (appointment_id)
JOIN   patients p      USING (patient_id)
WHERE  dx.diagnosed_at >= NOW() - INTERVAL '6 months'
GROUP  BY dx.icd10_code, dx.description
ORDER  BY diagnosis_count DESC
LIMIT  10;

-- Q3 (ANALYTICAL): Monthly Revenue by Department — Current Year
EXPLAIN ANALYZE
SELECT
    dept.name                              AS department,
    DATE_TRUNC('month', i.issued_at)       AS billing_month,
    COUNT(DISTINCT i.invoice_id)           AS invoices_issued,
    SUM(i.total_amount_cents) / 100.0      AS total_billed_ugx,
    SUM(i.paid_amount_cents)  / 100.0      AS total_collected_ugx,
    SUM(i.total_amount_cents - i.paid_amount_cents) / 100.0 AS outstanding_ugx,
    ROUND(
        SUM(i.paid_amount_cents)::NUMERIC /
        NULLIF(SUM(i.total_amount_cents), 0) * 100, 1
    ) AS collection_rate_pct
FROM   invoices i
JOIN   appointments a   ON  a.appointment_id = i.appointment_id
JOIN   departments dept ON  dept.department_id = a.department_id
WHERE  i.issued_at >= DATE_TRUNC('year', NOW())
GROUP  BY dept.name, DATE_TRUNC('month', i.issued_at)
ORDER  BY dept.name, billing_month;

-- Q4 (AGGREGATION): Department Summary — Patients, Appointments, Revenue
EXPLAIN ANALYZE
SELECT
    dept.name                               AS department,
    COUNT(DISTINCT a.patient_id)            AS unique_patients,
    COUNT(a.appointment_id)                 AS total_appointments,
    COUNT(a.appointment_id) FILTER (WHERE a.status = 'completed') AS completed_appointments,
    COALESCE(SUM(i.total_amount_cents), 0) / 100.0 AS total_revenue_ugx,
    COALESCE(SUM(i.paid_amount_cents), 0)  / 100.0 AS collected_revenue_ugx
FROM   departments dept
LEFT JOIN appointments a   USING (department_id)
LEFT JOIN invoices i       ON  i.appointment_id = a.appointment_id
GROUP  BY dept.department_id, dept.name
ORDER  BY total_revenue_ugx DESC;

-- Q5 (AGGREGATION): Patient Visit Frequency Segments
EXPLAIN ANALYZE
SELECT
    visit_segment,
    COUNT(*) AS patient_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM (
    SELECT
        patient_id,
        COUNT(appointment_id) AS visit_count,
        CASE
            WHEN COUNT(appointment_id) = 1              THEN 'One-time'
            WHEN COUNT(appointment_id) BETWEEN 2 AND 4  THEN 'Occasional (2-4)'
            WHEN COUNT(appointment_id) BETWEEN 5 AND 10 THEN 'Regular (5-10)'
            ELSE                                             'Frequent (10+)'
        END AS visit_segment
    FROM   appointments
    WHERE  scheduled_at >= NOW() - INTERVAL '1 year'
    GROUP  BY patient_id
) seg
GROUP  BY visit_segment
ORDER  BY patient_count DESC;

-- Q6 (WINDOW FUNCTION): Running Revenue Total & Rank by Doctor
EXPLAIN ANALYZE
SELECT
    doctor_name,
    department,
    billing_month,
    monthly_revenue_ugx,
    SUM(monthly_revenue_ugx) OVER (
        PARTITION BY doctor_id
        ORDER BY billing_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue_ugx,
    RANK() OVER (
        PARTITION BY department, billing_month
        ORDER BY monthly_revenue_ugx DESC
    ) AS dept_rank_this_month,
    AVG(monthly_revenue_ugx) OVER (
        PARTITION BY doctor_id
        ORDER BY billing_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_ugx
FROM (
    SELECT
        d.doctor_id,
        d.first_name || ' ' || d.last_name    AS doctor_name,
        dept.name                              AS department,
        DATE_TRUNC('month', i.issued_at)       AS billing_month,
        COALESCE(SUM(i.paid_amount_cents), 0) / 100.0 AS monthly_revenue_ugx
    FROM   doctors d
    JOIN   departments dept USING (department_id)
    LEFT JOIN appointments a   ON  a.doctor_id = d.doctor_id
    LEFT JOIN invoices i       ON  i.appointment_id = a.appointment_id
    WHERE  i.issued_at >= NOW() - INTERVAL '12 months'
    GROUP  BY d.doctor_id, d.first_name, d.last_name, dept.name,
              DATE_TRUNC('month', i.issued_at)
) monthly
ORDER  BY doctor_name, billing_month;
