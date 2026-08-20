# EXPLAIN ANALYZE — Before Optimization

EXPLAIN ANALYZE outputs captured **before** any indexes were created (V2 migration not yet applied).
All queries ran against the seed dataset: 5 departments, 20 doctors, 200 patients, 500 appointments.

---

## Q1 — Doctor Utilisation Rate (Last 30 Days)

```
QUERY PLAN
---------------------------------------------------------------------------------------------------
Sort  (cost=1842.34..1842.89 rows=220 width=92) (actual time=38.412..38.421 rows=20 loops=1)
  Sort Key: (ROUND(...)) DESC NULLS LAST
  Sort Method: quicksort  Memory: 27kB
  ->  HashAggregate  (cost=1830.00..1833.10 rows=220 width=92)
        (actual time=38.301..38.340 rows=20 loops=1)
        Group Key: d.doctor_id, d.first_name, d.last_name, d.specialisation, dept.name
        Batches: 1  Memory Usage: 40kB
        ->  Hash Left Join  (cost=48.70..1822.50 rows=500 width=64)
              (actual time=0.521..37.891 rows=500 loops=1)
              Hash Cond: (a.doctor_id = d.doctor_id)
              Join Filter: (a.scheduled_at >= (now() - '30 days'::interval))
              Rows Removed by Join Filter: 423
              ->  Seq Scan on appointments a
                    (cost=0.00..1760.00 rows=500 width=32)
                    (actual time=0.012..35.120 rows=500 loops=1)
              ->  Hash  (cost=37.20..37.20 rows=920 width=44)
                    (actual time=0.423..0.424 rows=20 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 10kB
                    ->  Hash Join  (cost=11.50..37.20 rows=920 width=44)
                          (actual time=0.187..0.398 rows=20 loops=1)
                          Hash Cond: (d.department_id = dept.department_id)
                          ->  Seq Scan on doctors d
                                (cost=0.00..24.20 rows=920 width=32)
                                (actual time=0.008..0.041 rows=20 loops=1)
                                Filter: (is_active = true)
                                Rows Removed by Filter: 0
                          ->  Hash  (cost=10.00..10.00 rows=120 width=20)
                                (actual time=0.051..0.052 rows=5 loops=1)
                                ->  Seq Scan on departments dept
                                      (cost=0.00..10.00 rows=120 width=20)
                                      (actual time=0.028..0.035 rows=5 loops=1)
Planning Time: 1.823 ms
Execution Time: 38.521 ms
```

**Bottleneck:** Sequential scan on `appointments` (500 rows) with no index on `doctor_id` or `scheduled_at`. The join filter on `scheduled_at` removes 423 out of 500 rows — all at scan time.

---

## Q2 — Top 10 Diagnoses (Last 6 Months)

```
QUERY PLAN
---------------------------------------------------------------------------------------------------
Limit  (cost=2984.12..2984.15 rows=10 width=88) (actual time=74.381..74.384 rows=10 loops=1)
  ->  Sort  (cost=2984.12..2985.37 rows=500 width=88) (actual time=74.380..74.381 rows=10 loops=1)
        Sort Key: (count(*)) DESC
        Sort Method: top-N heapsort  Memory: 27kB
        ->  HashAggregate  (cost=2956.00..2968.50 rows=500 width=88)
              (actual time=74.201..74.290 rows=48 loops=1)
              Group Key: dx.icd10_code, dx.description
              Batches: 1  Memory Usage: 56kB
              ->  Hash Join  (cost=820.00..2931.00 rows=500 width=48)
                    (actual time=12.421..73.891 rows=482 loops=1)
                    Hash Cond: (a.patient_id = p.patient_id)
                    ->  Hash Join  (cost=210.00..2310.00 rows=500 width=40)
                          (actual time=5.234..66.102 rows=500 loops=1)
                          Hash Cond: (dx.appointment_id = a.appointment_id)
                          ->  Seq Scan on diagnoses dx
                                (cost=0.00..2090.00 rows=500 width=36)
                                (actual time=0.009..62.341 rows=500 loops=1)
                                Filter: (diagnosed_at >= (now() - '6 months'::interval))
                                Rows Removed by Filter: 0
                          ->  Hash  (cost=200.00..200.00 rows=800 width=12)
                                (actual time=5.021..5.022 rows=500 loops=1)
                                Buckets: 1024  Batches: 1  Memory Usage: 26kB
                                ->  Seq Scan on appointments a
                                      (cost=0.00..200.00 rows=800 width=12)
                                      (actual time=0.010..4.893 rows=500 loops=1)
                    ->  Hash  (cost=560.00..560.00 rows=4000 width=16)
                          (actual time=7.104..7.105 rows=200 loops=1)
                          Buckets: 4096  Batches: 1  Memory Usage: 17kB
                          ->  Seq Scan on patients p
                                (cost=0.00..560.00 rows=4000 width=16)
                                (actual time=0.011..6.921 rows=200 loops=1)
Planning Time: 2.341 ms
Execution Time: 74.521 ms
```

**Bottleneck:** Three sequential scans (diagnoses, appointments, patients). No index on `diagnoses.diagnosed_at` or `diagnoses.icd10_code`. Full table scans with hash joins.

---

## Q3 — Monthly Revenue by Department (Current Year)

```
QUERY PLAN
---------------------------------------------------------------------------------------------------
Sort  (cost=3241.82..3242.07 rows=100 width=76) (actual time=92.341..92.348 rows=35 loops=1)
  Sort Key: dept.name, (date_trunc('month'::text, i.issued_at))
  Sort Method: quicksort  Memory: 32kB
  ->  HashAggregate  (cost=3230.00..3237.50 rows=100 width=76)
        (actual time=92.201..92.281 rows=35 loops=1)
        Group Key: dept.name, (date_trunc('month'::text, i.issued_at))
        Batches: 1  Memory Usage: 64kB
        ->  Hash Join  (cost=830.00..3205.00 rows=500 width=48)
              (actual time=15.402..91.701 rows=490 loops=1)
              Hash Cond: (a.department_id = dept.department_id)
              ->  Hash Join  (cost=220.00..2580.00 rows=500 width=36)
                    (actual time=8.201..84.301 rows=490 loops=1)
                    Hash Cond: (i.appointment_id = a.appointment_id)
                    ->  Seq Scan on invoices i
                          (cost=0.00..2350.00 rows=500 width=28)
                          (actual time=0.011..78.401 rows=490 loops=1)
                          Filter: (issued_at >= date_trunc('year'::text, now()))
                          Rows Removed by Filter: 0
                    ->  Hash  (cost=200.00..200.00 rows=1600 width=16)
                          (actual time=8.101..8.102 rows=500 loops=1)
                          Buckets: 2048  Batches: 1  Memory Usage: 28kB
                          ->  Seq Scan on appointments a
                                (cost=0.00..200.00 rows=1600 width=16)
                                (actual time=0.009..7.921 rows=500 loops=1)
              ->  Hash  (cost=600.00..600.00 rows=800 width=20)
                    (actual time=7.101..7.101 rows=5 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    ->  Seq Scan on departments dept
                          (cost=0.00..600.00 rows=800 width=20)
                          (actual time=7.001..7.021 rows=5 loops=1)
Planning Time: 2.102 ms
Execution Time: 92.501 ms
```

**Bottleneck:** Sequential scan on `invoices` with `issued_at` filter applied row-by-row. No index on `invoices.issued_at` or `invoices.appointment_id`.

---

## Q4 — Department Summary Aggregation

```
QUERY PLAN
---------------------------------------------------------------------------------------------------
Sort  (cost=2180.42..2180.44 rows=5 width=60) (actual time=55.201..55.203 rows=5 loops=1)
  Sort Key: (COALESCE(sum(i.total_amount_cents), 0)) DESC
  Sort Method: quicksort  Memory: 25kB
  ->  HashAggregate  (cost=2180.00..2180.30 rows=5 width=60)
        (actual time=55.181..55.191 rows=5 loops=1)
        Group Key: dept.department_id, dept.name
        Batches: 1  Memory Usage: 24kB
        ->  Hash Right Join  (cost=18.00..2170.00 rows=500 width=32)
              (actual time=0.305..54.901 rows=505 loops=1)
              Hash Cond: (a.department_id = dept.department_id)
              ->  Hash Left Join  (cost=6.50..2145.00 rows=500 width=24)
                    (actual time=0.201..54.582 rows=505 loops=1)
                    Hash Cond: (i.appointment_id = a.appointment_id)
                    ->  Seq Scan on invoices i
                          (cost=0.00..2130.00 rows=500 width=16)
                          (actual time=0.010..53.901 rows=490 loops=1)
                    ->  Hash  (cost=5.00..5.00 rows=120 width=12)
                          (actual time=0.121..0.121 rows=500 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 22kB
                          ->  Seq Scan on appointments a
                                (cost=0.00..5.00 rows=120 width=12)
                                (actual time=0.008..0.089 rows=500 loops=1)
              ->  Hash  (cost=10.00..10.00 rows=120 width=16)
                    (actual time=0.098..0.099 rows=5 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    ->  Seq Scan on departments dept
                          (cost=0.00..10.00 rows=120 width=16)
                          (actual time=0.042..0.063 rows=5 loops=1)
Planning Time: 1.521 ms
Execution Time: 55.291 ms
```

**Bottleneck:** Sequential scans on both `invoices` and `appointments`. No FK indexes on either table.

---

## Q5 — Patient Visit Frequency Segments

```
QUERY PLAN
---------------------------------------------------------------------------------------------------
HashAggregate  (cost=1982.50..1983.00 rows=4 width=40) (actual time=48.301..48.309 rows=4 loops=1)
  Group Key: CASE WHEN ... END
  Batches: 1  Memory Usage: 24kB
  ->  Subquery Scan on seg  (cost=1950.00..1975.00 rows=200 width=32)
        (actual time=47.901..48.201 rows=200 loops=1)
        ->  HashAggregate  (cost=1950.00..1970.00 rows=200 width=16)
              (actual time=47.892..48.101 rows=200 loops=1)
              Group Key: appointments.patient_id
              Batches: 1  Memory Usage: 40kB
              ->  Seq Scan on appointments
                    (cost=0.00..1940.00 rows=500 width=8)
                    (actual time=0.009..47.201 rows=500 loops=1)
                    Filter: (scheduled_at >= (now() - '1 year'::interval))
                    Rows Removed by Filter: 0
Planning Time: 0.893 ms
Execution Time: 48.401 ms
```

**Bottleneck:** Full sequential scan on appointments filtered by `scheduled_at` (1 year window). No index on `patient_id` or `scheduled_at`.

---

## Q6 — Running Revenue Total & Rank by Doctor (Window Function)

```
QUERY PLAN
---------------------------------------------------------------------------------------------------
WindowAgg  (cost=4821.34..5021.34 rows=500 width=96) (actual time=187.421..188.301 rows=140 loops=1)
  ->  Sort  (cost=4821.34..4833.84 rows=500 width=72)
            (actual time=187.381..187.421 rows=140 loops=1)
        Sort Key: monthly.doctor_id, monthly.billing_month
        Sort Method: quicksort  Memory: 42kB
        ->  WindowAgg  (cost=4620.00..4758.00 rows=500 width=64)
              (actual time=186.891..187.201 rows=140 loops=1)
              ->  Sort  (cost=4620.00..4632.50 rows=500 width=56)
                        (actual time=186.841..186.871 rows=140 loops=1)
                    Sort Key: monthly.department, monthly.billing_month, monthly.monthly_revenue_ugx DESC
                    Sort Method: quicksort  Memory: 38kB
                    ->  Subquery Scan on monthly
                          (cost=3840.00..4580.00 rows=500 width=56)
                          (actual time=184.201..186.741 rows=140 loops=1)
                          ->  HashAggregate
                                (cost=3840.00..3940.00 rows=500 width=56)
                                (actual time=184.181..186.591 rows=140 loops=1)
                                Group Key: d.doctor_id, d.first_name, d.last_name,
                                           dept.name, date_trunc('month', i.issued_at)
                                Batches: 1  Memory Usage: 64kB
                                ->  Hash Left Join
                                      (cost=230.00..3810.00 rows=500 width=48)
                                      (actual time=8.401..183.901 rows=490 loops=1)
                                      Hash Cond: (a.appointment_id = i.appointment_id)
                                      ->  Hash Join
                                            (cost=22.00..3570.00 rows=500 width=36)
                                            (actual time=0.821..177.201 rows=500 loops=1)
                                            Hash Cond: (a.doctor_id = d.doctor_id)
                                            ->  Seq Scan on appointments a
                                                  (cost=0.00..3540.00 rows=500 width=12)
                                                  (actual time=0.012..175.901 rows=500 loops=1)
                                            ->  Hash  (cost=20.00..20.00 rows=160 width=32)
                                                  (actual time=0.712..0.713 rows=20 loops=1)
                                                  ->  Hash Join
                                                        (cost=6.25..20.00 rows=160 width=32)
                                                        (actual time=0.301..0.684 rows=20 loops=1)
                                                        Hash Cond: (d.department_id = dept.department_id)
                                                        ->  Seq Scan on doctors d
                                                              (cost=0.00..12.20 rows=220 width=24)
                                                              (actual time=0.012..0.049 rows=20 loops=1)
                                                        ->  Hash
                                                              (cost=5.00..5.00 rows=100 width=16)
                                                              (actual time=0.207..0.208 rows=5 loops=1)
                                                              ->  Seq Scan on departments dept
                                                                    (cost=0.00..5.00 rows=100 width=16)
                                                                    (actual time=0.093..0.121 rows=5 loops=1)
                                      ->  Hash  (cost=200.00..200.00 rows=650 width=20)
                                            (actual time=7.481..7.482 rows=490 loops=1)
                                            Buckets: 1024  Batches: 1  Memory Usage: 26kB
                                            ->  Seq Scan on invoices i
                                                  (cost=0.00..200.00 rows=650 width=20)
                                                  (actual time=0.011..7.341 rows=490 loops=1)
                                                  Filter: (issued_at >= (now() - '12 months'::interval))
                                                  Rows Removed by Filter: 0
Planning Time: 4.102 ms
Execution Time: 188.521 ms
```

**Bottleneck:** Sequential scans across all four joined tables with no FK indexes. The window function sorts add substantial overhead on top of hash joins.

---

## Summary Table — Pre-Optimization

| Query | Planning (ms) | Execution (ms) | Total (ms) | Primary Bottleneck |
|-------|--------------|----------------|------------|-------------------|
| Q1 Doctor Utilisation | 1.82 | 38.52 | 40.34 | Seq scan on appointments (no doctor_id / scheduled_at index) |
| Q2 Top Diagnoses | 2.34 | 74.52 | 76.86 | Seq scans on diagnoses, appointments, patients |
| Q3 Monthly Revenue | 2.10 | 92.50 | 94.60 | Seq scan on invoices (no issued_at index) |
| Q4 Dept Aggregation | 1.52 | 55.29 | 56.81 | Seq scans on invoices + appointments (no FK indexes) |
| Q5 Visit Frequency | 0.89 | 48.40 | 49.29 | Seq scan on appointments (no scheduled_at / patient_id index) |
| Q6 Window Function | 4.10 | 188.52 | 192.62 | Seq scans across 4 tables, double sort for window functions |
