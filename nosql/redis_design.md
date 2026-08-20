# Redis Design — Hospital Management System

## What Data Is Stored in Redis

Redis serves as the in-memory caching and real-time messaging layer for the HMS.
Five distinct use cases are implemented:

---

### 1. Session Storage (Hash)

JWT tokens alone are stateless, but the application needs to invalidate sessions on
logout or role change without waiting for token expiry.

Key pattern: session:{session_token}

  HSET session:abc123xyz user_id 42 role "doctor" doctor_id 7 full_name "Dr. Grace Nakato"
  EXPIRE session:abc123xyz 3600   # 1-hour TTL

Benefits: O(1) lookup; instant invalidation via DEL session:{token}; automatic expiry.

---

### 2. Appointment Queue & Notifications (Pub/Sub + List)

When a receptionist books an appointment, a notification must reach the doctor's
dashboard within seconds — without polling the database.

Real-time channel:
  PUBLISH doctor:appointments:7 '{"event":"BOOKED","appointment_id":1042,"time":"09:30"}'

Persistent queue (when doctor is offline):
  LPUSH doctor:7:pending_notifications '{"type":"NEW_APPOINTMENT","appt_id":1042}'
  LRANGE doctor:7:pending_notifications 0 -1   # pop on login

---

### 3. Doctor Availability Cache (Sorted Set)

Key pattern: availability:{doctor_id}:{date} — score = slot time as Unix timestamp

  ZADD availability:7:2026-08-20 1724140800 "09:00"
  ZADD availability:7:2026-08-20 1724143200 "09:30"
  EXPIRE availability:7:2026-08-20 86400        # expires end of day
  ZREM availability:7:2026-08-20 "09:30"        # remove on booking
  ZRANGEBYSCORE availability:7:2026-08-20 -inf +inf  # get remaining slots

---

### 4. Rate Limiting (Counter with TTL)

Key pattern: ratelimit:{ip}:{endpoint}

  INCR   ratelimit:10.0.0.42:/api/login
  EXPIRE ratelimit:10.0.0.42:/api/login 60   # 60-second window
  # Application returns 429 if counter > 5

---

### 5. Dashboard Statistics Cache (String/JSON)

Key: stats:dashboard

  SET stats:dashboard '{"total_patients":8421,"today_appointments":47,"monthly_revenue_cents":34500000}'
  EXPIRE stats:dashboard 300   # refresh every 5 minutes

---

## Why Redis Was Selected

| Factor | Rationale |
|--------|-----------|
| Sub-millisecond latency | Session lookup on every API request must not add latency |
| Automatic expiry (TTL) | Sessions, caches, and rate-limit windows expire without a cleanup job |
| Pub/Sub | Native publish/subscribe for real-time appointment notifications |
| Atomic counters | INCR is atomic — correct rate limiting without race conditions |
| Sorted Sets | Natural fit for ordered availability slots |
| AOF Persistence | Pending notification queue survives a Redis restart |

---

## Benefits Provided

- Reduces PostgreSQL load by caching hot data — estimated 40% reduction in peak read queries
- Improves UX: doctor dashboard shows new appointments in real time without page refresh
- Security: centralised session store enables immediate logout and session revocation
- Resilience: pending notifications survive doctor offline periods and are delivered on reconnect

---

## Redis Configuration Applied

Relevant redis.conf settings:
  maxmemory           256mb
  maxmemory-policy    allkeys-lru        # evict least-recently used when full
  appendonly          yes                # AOF persistence for queues
  appendfsync         everysec           # balance durability vs. performance
  requirepass         <strong_password>  # authentication required
  bind                127.0.0.1          # localhost only
