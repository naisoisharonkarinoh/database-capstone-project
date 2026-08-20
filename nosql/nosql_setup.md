# NoSQL Setup — Hospital Management System

## Technologies Used

| Technology | Version | Role |
|------------|---------|------|
| MongoDB | 7.0 Community | Clinical notes and activity event logs |
| Redis | 7.2 | Session cache, appointment queue, rate limiting |

---

## MongoDB Setup (Ubuntu 22.04)

### Installation

    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
        sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
        https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
        sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

    sudo apt-get update && sudo apt-get install -y mongodb-org
    sudo systemctl enable --now mongod

### Initial Configuration (mongosh)

    use hms_db

    db.createUser({
      user: "hms_app",
      pwd: "<strong_password>",
      roles: [{ role: "readWrite", db: "hms_db" }]
    });

    db.createCollection("clinical_encounters", {
      validator: {
        $jsonSchema: {
          bsonType: "object",
          required: ["appointment_id", "patient_id", "doctor_id", "encounter_date"],
          properties: {
            appointment_id: { bsonType: "int" },
            patient_id:     { bsonType: "int" },
            doctor_id:      { bsonType: "int" },
            encounter_date: { bsonType: "date" }
          }
        }
      },
      validationLevel: "moderate"
    });

    db.createCollection("activity_logs");

### Create Indexes

    db.clinical_encounters.createIndex({ appointment_id: 1 }, { unique: true });
    db.clinical_encounters.createIndex({ patient_id: 1, encounter_date: -1 });
    db.clinical_encounters.createIndex({ doctor_id: 1, encounter_date: -1 });
    db.clinical_encounters.createIndex(
      { chief_complaint: "text", assessment: "text", plan: "text" },
      { name: "clinical_text_search" }
    );
    db.activity_logs.createIndex({ timestamp: 1 }, { expireAfterSeconds: 63072000 });
    db.activity_logs.createIndex({ "actor.user_id": 1, timestamp: -1 });
    db.activity_logs.createIndex({ event_type: 1, timestamp: -1 });

### Verify MongoDB

    sudo systemctl status mongod
    mongosh --username hms_app --password --authenticationDatabase hms_db
    db.getCollectionNames()
    db.clinical_encounters.getIndexes()

---

## Redis Setup (Ubuntu 22.04)

### Installation

    sudo apt-get install -y redis-server
    sudo systemctl enable --now redis-server
    redis-cli ping   # Expected: PONG

### Configuration (/etc/redis/redis.conf)

    maxmemory           256mb
    maxmemory-policy    allkeys-lru
    appendonly          yes
    appendfsync         everysec
    requirepass         <strong_password>
    rename-command FLUSHALL ""
    rename-command FLUSHDB  ""
    rename-command CONFIG   ""
    bind                127.0.0.1 ::1

    sudo systemctl restart redis-server

### Verify Redis

    redis-cli -a <password>

    # Session test
    HSET session:test user_id 1 role admin
    EXPIRE session:test 3600
    HGETALL session:test

    # Pub/Sub test
    SUBSCRIBE doctor:appointments:1
    PUBLISH  doctor:appointments:1 '{"event":"TEST"}'

    # Rate-limit test
    INCR ratelimit:127.0.0.1:/api/login
    TTL  ratelimit:127.0.0.1:/api/login

    # Availability slot test
    ZADD availability:1:2026-08-20 1724140800 "09:00"
    ZRANGEBYSCORE availability:1:2026-08-20 -inf +inf

---

## Environment Variables

    MONGODB_URI=mongodb://hms_app:<password>@localhost:27017/hms_db
    REDIS_URL=redis://:<password>@127.0.0.1:6379/0
    REDIS_SESSION_TTL=3600
    REDIS_STATS_TTL=300

---

## Architecture Integration

    Application (Node.js / FastAPI)
            |
            |-- PostgreSQL (pg_pool)   <-- Structured transactional data
            |-- MongoDB (mongoose)     <-- Clinical notes and activity logs
            |-- Redis (ioredis)        <-- Sessions, cache, pub-sub
