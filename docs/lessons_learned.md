# Lessons Learned

**Project:** Hospital Management System — Database Capstone  
**Author:** Atinda Hillary  
**Date:** 2026-08-20  
**Word Count:** ~650

---

Building a production-grade hospital database from scratch forced me to confront the gap between knowing database concepts in theory and applying them under real constraints. This reflection covers the six most significant things I learned.

## 1. Constraints at the Data Layer Cannot Be Bypassed

The most important realisation came when implementing the double-booking prevention. My first instinct was to check for overlapping appointments in the application code before inserting. A senior colleague pointed out that this approach has a race condition: two requests arriving simultaneously could both pass the check and both insert. The correct solution is an exclusion constraint using GIST, which PostgreSQL enforces atomically inside the transaction. The lesson is that critical business rules — especially ones with legal or safety implications — belong in the database, not the application. Application code can be bypassed. Constraints cannot.

## 2. Row-Level Security Requires a Complete Mental Model

RLS took the most time to get right. My first attempt added policies but forgot to add `FORCE ROW LEVEL SECURITY`, which meant table owners could bypass every policy. Then I discovered that `SECURITY DEFINER` functions read session variables as the function owner, not the caller — so I had to design the helper functions (`app_user_role()`, `app_doctor_id()`) carefully to avoid privilege escalation. The key insight is that RLS is a complete security layer that interacts with roles, function security contexts, and session state simultaneously. You cannot reason about one without reasoning about all three.

## 3. Index Design Is Both Science and Judgment

Before this project, I thought indexing meant "add an index on columns you filter by." The reality is more nuanced. I learned three things I did not expect: first, PostgreSQL does not automatically index foreign key columns, so every FK in the schema needed an explicit B-tree index. Second, column order in composite indexes is critical — equality filters must come before range filters or the index cannot be used. Third, partial indexes are often more valuable than full indexes because they exclude rows that are never searched, making the index smaller and the cache hit rate higher. The 27× speedup on the visit frequency query came from a single partial composite index — not from rewriting the query.

## 4. Circular Foreign Keys Are a Schema Design Problem, Not a Database Limitation

The circular dependency between `departments` and `doctors` — a department has a head doctor, a doctor belongs to a department — initially seemed like a fundamental flaw. I learned that PostgreSQL handles this cleanly through deferred constraint checking or, more simply, by creating one table first without the FK and adding it with `ALTER TABLE` after the second table exists. This pattern appears in many real schemas. The lesson is that circular references in a data model are not automatically wrong; they sometimes reflect genuine bidirectional relationships, and the database provides clean tools to implement them.

## 5. Flyway Migrations Enforce Discipline That Saves Hours

Running migrations without a tool like Flyway in early testing — applying SQL scripts manually in different orders — produced inconsistent states that were difficult to debug. After adopting Flyway, every migration is versioned, checksummed, and applied in a deterministic order. Attempting to run `flyway migrate` on a schema where a migration had been manually modified produces an immediate checksum error, which forces the developer to acknowledge the change rather than silently creating a divergent state. This discipline costs nothing in development and saves significant time in deployment.

## 6. Backup Verification Is Not Optional

I initially wrote the backup script and assumed it worked because `pg_dump` exited with code 0. When I wrote the restore script and actually ran it against a fresh database, I discovered that three tables were missing because they were created by a migration that `pg_dump` had silently skipped due to a permission issue. Without the restore test, this would have been discovered only during a real outage. The lesson: a backup that has not been restored is not a backup — it is a file of unknown usefulness. Restore verification must be part of the backup process, not an afterthought.

## What I Would Do Differently

If I were starting over, I would write the RLS policies before writing the seed data. I spent considerable time debugging why seed inserts were failing after enabling RLS, eventually discovering that I needed to set `session_replication_role = replica` to bypass triggers and policies during bulk loading. Understanding RLS implications earlier would have saved several hours.

I would also set up Flyway integration before writing the first migration. Retrofitting the migration tool to an existing set of SQL scripts requires manually specifying baseline versions and introduces risk of checksum mismatches. Starting with Flyway on migration V1 removes this complexity entirely.

Overall, this project confirmed that database design is the most leveraged investment in a software system. Schema decisions, security policies, and index strategies made at the database layer affect every application built on top of it — and unlike application code, they are much harder to change after data accumulates.
