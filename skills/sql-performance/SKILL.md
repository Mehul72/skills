---
name: sql-performance
description: >-
  Diagnose and fix a slow query, design the right index for it, or review ORM-generated SQL
  before it ships. Use when a query or endpoint is slow, when a database is showing high CPU
  or lock waits, when reviewing a new query or index, or on any mention of EXPLAIN, query
  plan, full table scan, N+1, missing index, or slow query log.
---

# SQL Performance

The goal is always the same: **make the database touch fewer rows**. Everything below is a way of finding out how many rows it currently touches and why.

Never optimize from intuition. Get the plan first.

Not for: the schema change that adds the index (use `migration-safety`, a `CREATE INDEX` without `CONCURRENTLY` blocks writes for the whole build), or a page that renders slowly (use `web-performance`).

## Step 1: Find the actual query

If you have a slow endpoint but not a slow query, get the query before theorizing:

- **Postgres:** `pg_stat_statements`, ordered by `total_exec_time` (the query burning the most total time matters more than the single slowest call).
- **MySQL:** the slow query log, digested with `pt-query-digest`, or `performance_schema.events_statements_summary_by_digest`.
- **ORM code:** turn on query logging for one request. This is usually where the N+1 becomes obvious.

Rank by **total time = mean × calls**, not by worst case. A 3 ms query called 50,000 times an hour is a bigger problem than one 2-second report that runs nightly.

## Step 2: Read the plan

Get a real plan with real timings, not an estimate:

- Postgres: `EXPLAIN (ANALYZE, BUFFERS) <query>`
- MySQL 8.0+: `EXPLAIN ANALYZE <query>`, or `EXPLAIN FORMAT=JSON`

`references/explain.md` covers how to read each. The three things to look for, in order:

1. **Row estimate vs. actual.** If the planner expected 10 rows and got 400,000, the plan was built on a lie, the fix is usually statistics (`ANALYZE`), not an index.
2. **The widest scan.** Find the node touching the most rows and work outward from there. Everything above it is downstream of that mistake.
3. **Rows read vs. rows returned.** Reading 2M rows to return 20 means the filtering is happening too late, after the scan instead of inside the index.

## Step 3: Match the fix to the cause

| Symptom in the plan | Cause | Fix |
|---|---|---|
| Seq Scan / `type: ALL` on a large table | No usable index | Add one, see Step 4 |
| Index scan reads far more rows than it returns | Index isn't selective enough, or filtering happens after the scan | Add the filter column to the index |
| Estimate wildly off from actual | Stale or insufficient statistics | `ANALYZE`; raise the statistics target on skewed columns |
| Nested Loop over a large outer relation | Bad row estimate feeding join choice | Fix the estimate first; the join method usually corrects itself |
| Sort with `external merge` / disk spill | `work_mem` too small, or sorting more than needed | Index in sort order, or reduce the row count before sorting |
| High `Buffers: read` vs `hit` | Working set doesn't fit in cache | Reduce rows touched; a covering index often fixes this |
| Same query shape repeated N times per request | ORM lazy-loading | Eager-load / batch, see N+1 below |

## Step 4: Design the index deliberately

Column order in a composite index is the whole game, and it is not arbitrary.

**The leftmost-prefix rule.** An index on `(a, b, c)` can serve queries filtering on `a`, on `(a, b)`, or on `(a, b, c)`, but not on `b` alone, and not on `(b, c)`. It's sorted like a phone book: surname first, then first name. You can't look someone up by first name alone.

**Order the columns:**
1. **Equality predicates first** (`WHERE status = ?`), most selective first among them.
2. **Then one range predicate** (`>`, `<`, `BETWEEN`, `LIKE 'x%'`). Everything after a range column is unusable for filtering, a range stops the seek.
3. **Then `ORDER BY` columns**, in matching order and direction, so the sort disappears.
4. **Then columns needed only for output**, to make the index covering (Postgres: put these in `INCLUDE`).

So for `WHERE tenant_id = ? AND status = ? AND created_at > ? ORDER BY created_at DESC`, the index is `(tenant_id, status, created_at)`, not any other permutation.

**Before adding one, check whether it already exists.** An index on `(a, b, c)` already serves `(a)` and `(a, b)`. Adding those is pure write overhead. Conversely, drop indexes nothing uses: every index is a tax on every `INSERT`, `UPDATE` and `DELETE`, and extra bytes in the buffer pool.

```sql
-- Postgres: indexes that are never scanned
SELECT relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY pg_relation_size(indexrelid) DESC;
```

Adding the index is a schema migration. Route it through the `migration-safety` skill, a `CREATE INDEX` without `CONCURRENTLY` blocks writes for the whole build.

## Step 5: Check for the usual anti-patterns

**Predicates that silently disable an index:**
- A function or cast on the indexed column, `WHERE DATE(created_at) = ?`, `WHERE LOWER(email) = ?`. Rewrite as a range (`created_at >= ? AND < ?`) or build a matching expression index.
- **Implicit type conversion:** a `VARCHAR` column compared to a number, or a `BIGINT` column compared to a string. MySQL will scan the whole table and give you no warning. Check that parameter types match the column types exactly.
- Leading wildcard, `LIKE '%foo'` cannot seek. Use a trigram index (Postgres `pg_trgm`) or full-text search.
- `OR` across different columns, often better as a `UNION ALL` of two indexed branches.
- `NOT IN` with a nullable subquery, semantics force a full scan *and* return surprising results. Use `NOT EXISTS`.

**`OFFSET` pagination.** `LIMIT 20 OFFSET 100000` makes the database walk and discard 100,000 rows. Cost grows linearly with page number, so page 1 is fast and page 5,000 times out. Use keyset pagination:

```sql
SELECT * FROM events
WHERE (created_at, id) < (:last_created_at, :last_id)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

This is O(1) per page regardless of depth. It costs you random access to arbitrary page numbers, accept that trade, or cap how deep offset paging is allowed to go.

**N+1 queries.** One query for a list, then one more per row. Nearly always an ORM lazy-loading relations. Fix with eager loading (`JOIN` / `IN (...)` batch), not by adding an index. Detect it by counting queries per request, not by reading code.

**`SELECT *`.** Prevents covering indexes, ships columns nobody reads, and turns a later `ADD COLUMN` into a wire-format change. Name the columns.

**Unbounded queries.** Any query without a `LIMIT` whose result set grows with your data will eventually take the process down. Bound it.

## Output

Report: the query, its current plan with real timings, the specific line in the plan that explains the cost, the fix, and the plan after the fix. Include the before/after row counts and timing, a performance claim without a measurement is a guess.

If the fix is a new index, state its write cost and confirm no existing index already covers the prefix.
