Database Capstone Project – Inventory Management System
Project Overview

This project is a complete Inventory Management System designed to demonstrate practical database engineering skills using PostgreSQL and Redis.

The system manages products, categories, suppliers, customers, inventory levels, purchases, sales, and user access. It demonstrates relational database design, database migrations, query optimization, security, auditing, NoSQL integration, backup and recovery, and professional documentation.

Objectives

The main objectives of this project are to:

Design and implement a normalized relational database using PostgreSQL.
Manage database changes using Flyway migrations.
Implement indexes and optimize SQL queries.
Use PostgreSQL advanced features such as triggers, views, transactions, and Row-Level Security.
Use Redis for caching frequently accessed inventory information.
Implement database security using roles and permissions.
Track important database changes using audit logging.
Create and test backup and recovery procedures.
Document the complete database architecture and design decisions.
Technologies Used
PostgreSQL – Primary relational database
Flyway – Database migration management
Redis – Caching and fast-access data
SQL – Database queries and analytics
Bash – Backup and restore scripts
Git & GitHub – Version control and project hosting
draw.io / dbdiagram.io – ER and architecture diagrams
Key Features
PostgreSQL Database

The relational database manages:

Users
Roles
Products
Categories
Suppliers
Customers
Inventory
Purchase orders
Sales orders
Order items
Payments
Audit records
Database Migrations

The database is created through five Flyway migrations:

V1__core_tables.sql – Creates the core database tables.
V2__indexes.sql – Adds indexes for improved query performance.
V3__audit_and_triggers.sql – Implements auditing and database triggers.
V4__row_level_security.sql – Implements Row-Level Security.
V5__seed_demo_data.sql – Adds realistic demonstration data.
Redis Integration

Redis is used as a caching layer for frequently requested inventory information.

Example cached information includes:

Product availability
Current stock quantities
Product counts
Frequently accessed product information

Redis reduces unnecessary database queries and improves application response time.

Query Optimization

The project includes analytical SQL queries demonstrating:

Aggregations
GROUP BY operations
JOIN optimization
Window functions
Index usage
EXPLAIN ANALYZE

Query performance is documented before and after optimization.

The optimization report records:

Original execution plan
Performance problem
Optimization change
Improved execution plan
Execution-time improvement
Security

Security is implemented using PostgreSQL roles and permissions.

The project includes:

Read-only database role
Read-write database role
Application role
Least-privilege access
Row-Level Security
Audit logging
Trigger-based change tracking
Protection of sensitive information
Parameterized query recommendations

The application is designed not to use a PostgreSQL superuser account.

Backup and Recovery

The project includes PostgreSQL backup and restore procedures using pg_dump.

Backups are created in custom format and can be restored using pg_restore.

The repository documents:

Backup commands
Restore commands
Backup verification
Restore testing
Recovery considerations
Repository Structure
database-capstone-project/
│
├── requirements/
│   ├── project_requirements.md
│   └── er_diagram.png
│
├── migrations/
│   ├── V1__core_tables.sql
│   ├── V2__indexes.sql
│   ├── V3__audit_and_triggers.sql
│   ├── V4__row_level_security.sql
│   └── V5__seed_demo_data.sql
│
├── nosql/
│   ├── mongodb_design.md
│   ├── redis_design.md
│   └── nosql_setup.md
│
├── optimization/
│   ├── analytical_queries.sql
│   ├── before_explain.md
│   ├── after_explain.md
│   └── optimization_report.md
│
├── security/
│   ├── roles_and_permissions.sql
│   ├── rls_policies.sql
│   ├── audit_implementation.sql
│   └── security_report.md
│
├── backups/
│   ├── backup_script.sh
│   ├── restore_commands.sh
│   └── backup_verification.md
│
├── presentation/
│   ├── architecture.md
│   ├── project_walkthrough.md
│   └── demo_script.md
│
├── docs/
│   ├── architecture_diagram.png
│   ├── data_dictionary.md
│   ├── lessons_learned.md
│   └── final_report.md
│
└── README.md
Setup Instructions
1. Clone the repository
git clone https://github.com/naisoisharonkarinoh/database-capstone-project.git
cd database-capstone-project
2. Create the PostgreSQL database

Create a database named:

capstone

Example:

createdb capstone
3. Configure Flyway

Configure Flyway with the PostgreSQL database connection.

Example:

flyway.url=jdbc:postgresql://localhost:5432/capstone
flyway.user=postgres
flyway.password=YOUR_PASSWORD
4. Run migrations

From the project directory:

flyway clean migrate

This creates the database from an empty state and applies all migrations in the correct order.

5. Verify the database

Connect to PostgreSQL:

psql -d capstone

Then inspect the tables:

\dt
Running the Optimization Tests

Run the analytical queries in:

optimization/analytical_queries.sql

Use:

EXPLAIN ANALYZE

to measure query performance.

Compare the original results with the optimized results documented in:

optimization/before_explain.md
optimization/after_explain.md
optimization/optimization_report.md
Running Redis

Start Redis locally:

redis-server

Verify the server:

redis-cli ping

Expected response:

PONG

Redis configuration and usage are documented in:

nosql/redis_design.md
nosql/nosql_setup.md
Backup

Create a PostgreSQL backup using:

pg_dump -Fc -f backups/capstone_$(date +%F).dump capstone

The backup procedures are documented in:

backups/backup_script.sh
backups/backup_verification.md
Restore

A backup can be restored using:

pg_restore -d capstone backups/capstone_YYYY-MM-DD.dump

Detailed restoration commands are provided in:

backups/restore_commands.sh
Security Verification

The project verifies:

Least-privilege roles implemented

No application uses a superuser account

Row-Level Security implemented where applicable

Audit logging enabled

Sensitive information protected

Parameterized queries documented

Backup and restore procedures tested

Expected Learning Outcomes

By completing this project, the developer demonstrates practical knowledge of:

Relational database modeling
PostgreSQL
SQL
Database migrations
Indexing
Query optimization
EXPLAIN ANALYZE
Aggregation and window functions
PostgreSQL triggers
Row-Level Security
Database roles and permissions
Redis caching
Backup and recovery
Database auditing
Technical documentation
Git and GitHub
Future Improvements

Future versions could include:

A web-based frontend
REST API integration
Automated CI/CD database migrations
PostgreSQL replication
Automated scheduled backups
Monitoring and alerting
Docker deployment
Kubernetes deployment
Advanced Redis caching strategies
Reporting dashboards
Author

Sharon Koina

Database Capstone Project – Inventory Management System
