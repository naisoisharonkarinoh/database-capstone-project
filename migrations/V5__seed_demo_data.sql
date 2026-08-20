-- =============================================================================
-- V5__seed_demo_data.sql
-- Hospital Management System — Realistic Demo Data
-- 5 departments · 20 doctors · 200 patients · 500 appointments
-- =============================================================================

-- Disable audit triggers during seeding to avoid flooding audit_log
SET session_replication_role = replica;

-- DEPARTMENTS (5)
INSERT INTO departments (name, location) VALUES
    ('Cardiology',       'Block A, Floor 2'),
    ('Paediatrics',      'Block B, Floor 1'),
    ('Orthopaedics',     'Block C, Floor 3'),
    ('General Medicine', 'Block A, Floor 1'),
    ('Obstetrics',       'Block D, Floor 2');

-- DOCTORS (20)
INSERT INTO doctors (first_name, last_name, email, phone, specialisation, department_id, license_number) VALUES
    ('James',     'Ochieng',   'j.ochieng@hms.ug',   '+256701000001', 'Cardiologist',         1, 'UG-MED-0001'),
    ('Grace',     'Nakato',    'g.nakato@hms.ug',    '+256701000002', 'Cardiologist',         1, 'UG-MED-0002'),
    ('Peter',     'Ssemakula', 'p.ssemakula@hms.ug', '+256701000003', 'Paediatrician',        2, 'UG-MED-0003'),
    ('Fatuma',    'Abubakar',  'f.abubakar@hms.ug',  '+256701000004', 'Paediatrician',        2, 'UG-MED-0004'),
    ('Emmanuel',  'Byarugaba', 'e.byarugaba@hms.ug', '+256701000005', 'Orthopaedic Surgeon',  3, 'UG-MED-0005'),
    ('Sylvia',    'Namusisi',  's.namusisi@hms.ug',  '+256701000006', 'Orthopaedic Surgeon',  3, 'UG-MED-0006'),
    ('Robert',    'Okello',    'r.okello@hms.ug',    '+256701000007', 'General Practitioner', 4, 'UG-MED-0007'),
    ('Diana',     'Achola',    'd.achola@hms.ug',    '+256701000008', 'General Practitioner', 4, 'UG-MED-0008'),
    ('Samuel',    'Tumwine',   's.tumwine@hms.ug',   '+256701000009', 'General Practitioner', 4, 'UG-MED-0009'),
    ('Christine', 'Namukasa',  'c.namukasa@hms.ug',  '+256701000010', 'General Practitioner', 4, 'UG-MED-0010'),
    ('Isaac',     'Wamala',    'i.wamala@hms.ug',    '+256701000011', 'Obstetrician',         5, 'UG-MED-0011'),
    ('Patience',  'Kabuye',    'p.kabuye@hms.ug',    '+256701000012', 'Obstetrician',         5, 'UG-MED-0012'),
    ('Moses',     'Kizza',     'm.kizza@hms.ug',     '+256701000013', 'Cardiologist',         1, 'UG-MED-0013'),
    ('Juliet',    'Nanyonga',  'j.nanyonga@hms.ug',  '+256701000014', 'Paediatrician',        2, 'UG-MED-0014'),
    ('Alex',      'Ssenteza',  'a.ssenteza@hms.ug',  '+256701000015', 'Orthopaedic Surgeon',  3, 'UG-MED-0015'),
    ('Miriam',    'Nabukenya', 'm.nabukenya@hms.ug', '+256701000016', 'General Practitioner', 4, 'UG-MED-0016'),
    ('Denis',     'Mutebi',    'd.mutebi@hms.ug',    '+256701000017', 'Obstetrician',         5, 'UG-MED-0017'),
    ('Sarah',     'Nalubega',  's.nalubega@hms.ug',  '+256701000018', 'General Practitioner', 4, 'UG-MED-0018'),
    ('John',      'Wasswa',    'j.wasswa@hms.ug',    '+256701000019', 'Cardiologist',         1, 'UG-MED-0019'),
    ('Agnes',     'Birungi',   'a.birungi@hms.ug',   '+256701000020', 'Paediatrician',        2, 'UG-MED-0020');

-- Set department heads
UPDATE departments SET head_doctor_id = 1  WHERE department_id = 1;
UPDATE departments SET head_doctor_id = 3  WHERE department_id = 2;
UPDATE departments SET head_doctor_id = 5  WHERE department_id = 3;
UPDATE departments SET head_doctor_id = 7  WHERE department_id = 4;
UPDATE departments SET head_doctor_id = 11 WHERE department_id = 5;

-- WARDS (10)
INSERT INTO wards (name, department_id, capacity, ward_type) VALUES
    ('Cardiac Ward A',      1, 20, 'general'),
    ('Cardiac ICU',         1, 8,  'ICU'),
    ('Paediatric Ward',     2, 30, 'paediatric'),
    ('Orthopaedic Ward',    3, 25, 'general'),
    ('Surgical ICU',        3, 6,  'ICU'),
    ('General Ward A',      4, 40, 'general'),
    ('General Ward B',      4, 40, 'general'),
    ('Maternity Ward',      5, 20, 'maternity'),
    ('Labour Suite',        5, 10, 'maternity'),
    ('High Dependency Unit',4, 12, 'ICU');

-- PATIENTS (200) via generate_series
INSERT INTO patients (first_name, last_name, date_of_birth, gender, phone, email, blood_type,
                      emergency_contact_name, emergency_contact_phone, insurance_provider)
SELECT
    (ARRAY['Aisha','Brian','Christine','David','Esther','Francis','Grace','Henry',
           'Irene','Joseph','Katherine','Lawrence','Mary','Nathan','Olivia','Paul',
           'Queen','Richard','Stella','Thomas'])[1 + (n % 20)],
    (ARRAY['Nakato','Okello','Ssemakula','Abubakar','Byarugaba','Namusisi','Kizza',
           'Wamala','Kabuye','Nanyonga','Mutebi','Nalubega','Wasswa','Birungi',
           'Ochieng','Tumwine','Achola','Namukasa','Ssenteza','Nabukenya'])[1 + (n % 20)],
    CURRENT_DATE - ((n * 137) % (80 * 365) + 365)::INTEGER * interval '1 day',
    CASE WHEN n % 3 = 0 THEN 'Female' WHEN n % 3 = 1 THEN 'Male' ELSE 'Other' END,
    '+2567' || LPAD((10000000 + n * 7919)::TEXT, 8, '0'),
    'patient' || n || '@mail.ug',
    (ARRAY['A+','A-','B+','B-','O+','O-','AB+','AB-'])[1 + (n % 8)],
    'Emergency Contact ' || n,
    '+2567' || LPAD((20000000 + n * 6271)::TEXT, 8, '0'),
    (ARRAY['NHIS Uganda','Jubilee Insurance','AAR Health','UAP Insurance',NULL])[1 + (n % 5)]
FROM generate_series(1, 200) AS s(n);

-- APPOINTMENTS (500)
INSERT INTO appointments (patient_id, doctor_id, department_id, scheduled_at, duration_minutes, status, reason)
SELECT
    1 + (n % 200),
    1 + (n % 20),
    (SELECT department_id FROM doctors WHERE doctor_id = 1 + (n % 20)),
    NOW() - ((365 - (n % 365)) * interval '1 day') + ((n % 9) * interval '1 hour') + interval '8 hours',
    CASE WHEN n % 5 = 0 THEN 60 ELSE 30 END,
    (ARRAY['completed','completed','completed','completed',
           'scheduled','confirmed','cancelled','no_show','completed'])[1 + (n % 9)],
    (ARRAY['Chest pain','Fever and cough','Knee pain','Follow-up visit','Routine checkup',
           'Pregnancy check','Headache','Back pain','Vaccination','Shortness of breath'])[1 + (n % 10)]
FROM generate_series(1, 500) AS s(n);

-- DIAGNOSES (completed appointments)
INSERT INTO diagnoses (appointment_id, icd10_code, description, severity)
SELECT
    a.appointment_id,
    (ARRAY['I10','J06.9','M54.5','Z00.00','O80','J18.9','K59.0','I25.10','E11.9','J45.909'])[1 + (a.appointment_id % 10)],
    (ARRAY['Essential hypertension','Acute upper respiratory infection','Low back pain',
           'Routine general medical examination','Normal delivery','Pneumonia unspecified',
           'Constipation','Ischaemic heart disease','Type 2 diabetes mellitus','Asthma'])[1 + (a.appointment_id % 10)],
    (ARRAY['mild','mild','moderate','moderate','severe','mild','mild','severe','moderate','mild'])[1 + (a.appointment_id % 10)]
FROM appointments a WHERE a.status = 'completed';

-- PRESCRIPTIONS
INSERT INTO prescriptions (appointment_id, medication_name, dosage, frequency, duration_days, instructions)
SELECT
    a.appointment_id,
    (ARRAY['Amlodipine','Amoxicillin','Ibuprofen','Paracetamol','Metformin',
           'Salbutamol','Furosemide','Atorvastatin','Omeprazole','Doxycycline'])[1 + (a.appointment_id % 10)],
    (ARRAY['5mg','500mg','400mg','500mg','500mg','100mcg','40mg','20mg','20mg','100mg'])[1 + (a.appointment_id % 10)],
    (ARRAY['Once daily','Three times daily','Twice daily','As needed','Twice daily',
           'As needed','Once daily','Once daily','Once daily','Once daily'])[1 + (a.appointment_id % 10)],
    (ARRAY[30, 7, 5, 3, 90, 30, 30, 90, 14, 7])[1 + (a.appointment_id % 10)],
    'Take with food and water. Avoid alcohol.'
FROM appointments a WHERE a.status = 'completed' AND a.appointment_id % 3 != 0;

-- ADMISSIONS (50: 30 current + 20 discharged)
INSERT INTO admissions (patient_id, ward_id, bed_number, admitted_at, discharged_at, admitting_doctor_id, admission_notes)
SELECT
    1 + (n % 200),
    1 + (n % 10),
    'B-' || LPAD(n::TEXT, 3, '0'),
    NOW() - ((n * 11) % 60) * interval '1 day',
    CASE WHEN n <= 20 THEN NOW() - ((n * 11) % 60) * interval '1 day' + (n % 7 + 1) * interval '1 day'
         ELSE NULL END,
    1 + (n % 20),
    'Patient admitted with ' || (ARRAY['acute chest pain','high fever','fracture',
        'post-operative care','complicated delivery','severe infection'])[1 + (n % 6)]
FROM generate_series(1, 50) AS s(n);

-- INVOICES
INSERT INTO invoices (patient_id, appointment_id, total_amount_cents, paid_amount_cents, status, due_date)
SELECT
    a.patient_id, a.appointment_id,
    CASE WHEN a.appointment_id % 5 = 0 THEN 150000
         WHEN a.appointment_id % 5 = 1 THEN 250000
         WHEN a.appointment_id % 5 = 2 THEN 500000
         WHEN a.appointment_id % 5 = 3 THEN 80000
         ELSE 200000 END,
    0, 'pending',
    (a.scheduled_at + interval '30 days')::DATE
FROM appointments a WHERE a.status = 'completed';

-- PAYMENTS (~90% of invoices)
INSERT INTO payments (invoice_id, amount_cents, payment_method, reference_number)
SELECT
    i.invoice_id, i.total_amount_cents,
    (ARRAY['cash','mobile_money','card','insurance'])[1 + (i.invoice_id % 4)],
    'REF-' || LPAD(i.invoice_id::TEXT, 8, '0')
FROM invoices i WHERE i.invoice_id % 10 != 0;

-- Re-enable audit triggers
SET session_replication_role = DEFAULT;
