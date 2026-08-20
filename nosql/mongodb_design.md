# MongoDB Design — Hospital Management System

## What Data Is Stored in MongoDB

MongoDB handles two categories of data that benefit from a flexible, document-oriented model:

### 1. Clinical Notes & Encounter Documents

Each appointment generates a rich clinical encounter document that varies by specialisation.
A cardiologist note differs structurally from an orthopaedic note — forcing them into a fixed
relational schema either wastes columns or creates unmaintainable EAV tables.

**Collection: clinical_encounters** stores per-appointment encounter documents with fields:
appointment_id (references PostgreSQL), patient_id, doctor_id, department, encounter_date,
chief_complaint, vital_signs (nested: BP systolic/diastolic, heart_rate, temperature, SpO2, weight),
investigations_ordered (array of test/urgency objects), examination_findings, assessment,
plan, follow_up_days, attachments (array with type/url/uploaded_at), created_at, updated_at.

### 2. User Activity & System Event Logs

**Collection: activity_logs** stores high-volume event stream data with fields:
event_type, actor (user_id, role, name), target (resource, resource_id),
metadata (contextual data varies by event), ip_address, user_agent, timestamp, status.

---

## Why MongoDB Was Selected

| Factor | Rationale |
|--------|-----------|
| Schema flexibility | Clinical notes vary by specialty — fixed schema forces NULLs or EAV patterns |
| Nested documents | Vital signs and investigations are naturally nested, no JOIN required |
| High write throughput | Activity logs arrive at 100+ events/sec during peak hours |
| TTL indexes | Activity logs older than 2 years auto-expired automatically |
| Horizontal scaling | Sharding supports growth without schema changes |

The hybrid approach keeps PostgreSQL for structured transactional data (appointments, billing)
and MongoDB for unstructured, high-volume document data — each engine used where it excels.

---

## Key Indexes in MongoDB

For clinical_encounters collection:
- { appointment_id: 1 } with unique: true
- { patient_id: 1, encounter_date: -1 }
- { doctor_id: 1, encounter_date: -1 }
- Text index on chief_complaint, assessment, plan fields

For activity_logs collection:
- { timestamp: 1 } with expireAfterSeconds: 63072000 (2-year TTL)
- { "actor.user_id": 1, timestamp: -1 }
- { event_type: 1, timestamp: -1 }

---

## Sample Queries

Get all clinical encounters for a patient, newest first:
  db.clinical_encounters.find({ patient_id: 77 }).sort({ encounter_date: -1 })

Full-text search across clinical notes:
  db.clinical_encounters.find({ $text: { $search: "chest pain ECG" } })

Count activity events by type in the last 24 hours:
  db.activity_logs.aggregate([
    { $match: { timestamp: { $gte: new Date(Date.now() - 86400000) } } },
    { $group: { _id: "$event_type", count: { $sum: 1 } } },
    { $sort: { count: -1 } }
  ])
