# Reading Query Plans

## Postgres

Always use `EXPLAIN (ANALYZE, BUFFERS)`. Plain `EXPLAIN` gives estimates only, and estimates are exactly what you're trying to verify.

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT ... ;
```

> `ANALYZE` **executes the query**. For `INSERT`/`UPDATE`/`DELETE`, wrap it in `BEGIN; ... ROLLBACK;`.

### Structure

Plans are trees, read **innermost/most-indented first**. Each node shows:

```
Index Scan using idx_events_tenant on events  (cost=0.43..812.11 rows=120 width=64)
                                              (actual time=0.031..4.192 rows=98431 loops=3)
  Index Cond: (tenant_id = 42)
  Filter: (status = 'open')
  Rows Removed by Filter: 380122
  Buffers: shared hit=1204 read=88213
```

- `cost=start..total`, arbitrary units, only useful for comparing plans of the same query.
- `rows=` (in `cost`) is the **estimate**; `rows=` in `actual` is the **truth**. A big gap is the single most useful signal in the whole plan.
- `loops=N`, **`actual time` and `rows` are per loop.** Total rows = `rows × loops`. This is the most commonly misread number in Postgres plans; a node showing `rows=1 loops=200000` did 200,000 units of work, not 1.
- `Rows Removed by Filter`, rows read then thrown away. Large values mean the filter should be in the index.
- `Buffers: shared hit=X read=Y`, `hit` came from cache, `read` came from disk. High `read` is where the wall-clock time actually goes.

### Node types worth recognizing

| Node | Meaning | When it's wrong |
|---|---|---|
| `Seq Scan` | Full table read | On a large table with a selective predicate |
| `Index Scan` | Walk index, fetch rows from heap | When it returns a large fraction of the table (seq scan would be cheaper) |
| `Index Only Scan` | Answered from the index alone | Ideal. Check `Heap Fetches` is near zero, else `VACUUM` |
| `Bitmap Heap Scan` | Collect row pointers, then fetch in physical order | Normal for medium selectivity; `Recheck Cond` with `lossy=` means `work_mem` was too small |
| `Nested Loop` | For each outer row, probe inner | Catastrophic when the outer row estimate is badly low |
| `Hash Join` | Build hash of one side | Fine; watch for `Batches: > 1`, which means it spilled to disk |
| `Merge Join` | Both inputs sorted | Fine when inputs are already index-ordered |
| `Sort` | Explicit sort | `Sort Method: external merge Disk: NkB` means it spilled, raise `work_mem` or index in sort order |
| `Materialize` / `Memoize` | Caching inner results | Usually a symptom of a repeated nested loop |

### Fixing bad estimates

```sql
ANALYZE events;                                        -- refresh statistics
ALTER TABLE events ALTER COLUMN tenant_id SET STATISTICS 1000;  -- more buckets on skewed columns
CREATE STATISTICS ev_corr (dependencies) ON tenant_id, status FROM events;  -- correlated columns
ANALYZE events;
```

Multi-column estimates are the usual culprit: the planner assumes independence between columns, so `WHERE country = 'JP' AND language = 'ja'` gets estimated as the product of two selectivities and comes out ~100x too low. Extended statistics fix exactly this.

## MySQL

```sql
EXPLAIN ANALYZE SELECT ...;     -- 8.0.18+: real timings, iterator-tree format
EXPLAIN FORMAT=JSON SELECT ...; -- estimates, but the most detail
EXPLAIN SELECT ...;             -- classic tabular
```

### Classic EXPLAIN columns

- **`type`:** access method, best to worst:
  `system` > `const` > `eq_ref` > `ref` > `range` > `index` > **`ALL`**.
  `ALL` is a full table scan. `index` is a full *index* scan, still reads everything, only narrower.
- **`key`:** the index actually chosen. `NULL` means none.
- **`rows`:** estimated rows examined **at this step**. Multiply down the join order for the real cost.
- **`filtered`:** percentage surviving the `WHERE` after the row fetch. `rows × filtered%` is what flows to the next table. Low `filtered` with high `rows` means the index isn't doing the filtering.
- **`Extra`:** the important column:
  - `Using index`, covering index, good.
  - `Using where`, filtering after reading rows.
  - `Using filesort`, sorting in memory or on disk; not necessarily fatal, but an index in sort order removes it.
  - `Using temporary`, a temp table, usually from `GROUP BY`/`DISTINCT` that can't use an index.
  - `Using join buffer (Block Nested Loop)`, no usable index on the joined column. Almost always a bug.
  - `Impossible WHERE`, the optimizer proved the predicate can never match.

### EXPLAIN ANALYZE output

```
-> Nested loop inner join  (cost=1043 rows=982) (actual time=0.06..48.2 rows=13024 loops=1)
    -> Index range scan on events using idx_tenant  (actual time=0.03..2.1 rows=13024 loops=1)
    -> Single-row index lookup on users using PRIMARY  (actual time=0.003..0.003 rows=1 loops=13024)
```

Same rule as Postgres: `actual time` and `rows` are **per loop**. The `loops=13024` line above ran 13,024 times.

### Checking what the optimizer decided and why

```sql
EXPLAIN FORMAT=JSON SELECT ...;   -- includes cost breakdown per table

-- After running the query:
SHOW WARNINGS;                    -- shows the rewritten query after optimizer transforms

-- Index cardinality: if this is wildly wrong, the optimizer picks badly
SHOW INDEX FROM events;
ANALYZE TABLE events;             -- refresh cardinality estimates
```

If MySQL chooses the wrong index despite good statistics, `FORCE INDEX` works but is a last resort. It goes stale silently when the data distribution changes. Fix the statistics or the index design first.

## Both engines: verify the fix

Re-run `EXPLAIN ANALYZE` after the change and compare **actual rows read** and **actual time**, not cost. Record both numbers in whatever you report. A plan change without a timing change means you fixed nothing.
