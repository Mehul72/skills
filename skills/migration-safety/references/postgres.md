# Postgres Migration Hazards

Version notes matter, several of these were fixed in specific releases. Check `SELECT version()` before trusting a "safe" classification.

## Operation classification

| Operation | Lock taken | Why it hurts | Safe alternative |
|---|---|---|---|
| `ADD COLUMN` (no default, nullable) | `ACCESS EXCLUSIVE`, brief | Metadata only | Safe |
| `ADD COLUMN ... DEFAULT <constant>` | `ACCESS EXCLUSIVE`, brief on **PG 11+** | Pre-11 rewrote the whole table | PG 11+: safe. Pre-11: add column, set default, backfill |
| `ADD COLUMN ... DEFAULT <volatile>` (`now()`, `random()`, `gen_random_uuid()`) | `ACCESS EXCLUSIVE`, full rewrite | Every row must be computed | Add column → `ALTER ... SET DEFAULT` → batched backfill |
| `ADD COLUMN ... NOT NULL` (no default) | `ACCESS EXCLUSIVE`, full scan | Must verify every row | Add nullable → backfill → `NOT VALID` check → validate → `SET NOT NULL` |
| `ADD COLUMN ... GENERATED ALWAYS AS ... STORED` | `ACCESS EXCLUSIVE`, full rewrite | Computes every row | Plain column + trigger, or a view |
| `DROP COLUMN` | `ACCESS EXCLUSIVE`, brief | Fast in DB; breaks running code | Remove all code references, deploy, soak, then drop |
| `ALTER COLUMN TYPE` | `ACCESS EXCLUSIVE`, full rewrite | Rewrites table and all its indexes | New column → dual-write → backfill → switch reads → drop old |
| `RENAME COLUMN` / `RENAME TABLE` | `ACCESS EXCLUSIVE`, brief | Fast in DB; instantly breaks running code | Never rename in place. Use the add/dual-write/drop sequence |
| `CREATE INDEX` | `SHARE` | Blocks **all writes** for the whole build | `CREATE INDEX CONCURRENTLY` |
| `CREATE INDEX CONCURRENTLY` | `SHARE UPDATE EXCLUSIVE` | Two table passes, slower, can leave an INVALID index | Correct choice, but see caveats below |
| `DROP INDEX` | `ACCESS EXCLUSIVE` | Brief but blocks reads | `DROP INDEX CONCURRENTLY` |
| `ADD FOREIGN KEY` | `SHARE ROW EXCLUSIVE` on **both** tables | Validates every existing row | `ADD CONSTRAINT ... NOT VALID`, then `VALIDATE CONSTRAINT` separately |
| `ADD CHECK` constraint | `ACCESS EXCLUSIVE`, full scan | Validates every row | `NOT VALID`, then `VALIDATE CONSTRAINT` |
| `ADD UNIQUE` constraint | `ACCESS EXCLUSIVE`, builds index | Index built non-concurrently | `CREATE UNIQUE INDEX CONCURRENTLY`, then `ADD CONSTRAINT ... USING INDEX` |
| `ADD EXCLUDE` constraint | `ACCESS EXCLUSIVE`, full scan | Cannot be marked `NOT VALID` | No fully safe route, schedule a maintenance window |
| `SET NOT NULL` | `ACCESS EXCLUSIVE`, full scan | Pre-12 always scanned | **PG 12+**: a validated `CHECK (col IS NOT NULL)` lets `SET NOT NULL` skip the scan. Pre-12: rewrite the table offline |
| `TRUNCATE` | `ACCESS EXCLUSIVE` | Blocks everything | Batched `DELETE`, or swap to a new table |
| `VACUUM FULL` | `ACCESS EXCLUSIVE` | Rewrites the table offline | `pg_repack`, or plain `VACUUM` |
| `json` column |, | No equality operator; breaks `SELECT DISTINCT` and `GROUP BY` on that column | Use `jsonb` |

## The safe NOT NULL sequence (PG 12+)

```sql
-- 1. separate migration
ALTER TABLE users ADD CONSTRAINT users_email_not_null
  CHECK (email IS NOT NULL) NOT VALID;

-- 2. separate migration: scans without an exclusive lock
ALTER TABLE users VALIDATE CONSTRAINT users_email_not_null;

-- 3. separate migration: PG 12+ sees the validated constraint and skips the scan
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users DROP CONSTRAINT users_email_not_null;
```

## CREATE INDEX CONCURRENTLY caveats

- **Cannot run inside a transaction block.** Migration tools wrap statements in transactions by default, disable it for this migration.
- **Can fail and leave an `INVALID` index** that still costs write overhead but is never used for reads. After any failed run, check and clean up:
  ```sql
  SELECT c.relname FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  WHERE NOT i.indisvalid;
  ```
  Then `DROP INDEX CONCURRENTLY` the invalid one and retry.
- **Waits for all transactions older than the build to finish:** twice. A single long-running or idle-in-transaction session will stall it indefinitely.
- Builds one index at a time per table; concurrent builds on the same table deadlock-check against each other.

## Pre-flight checks

```sql
-- Long-running transactions that will block your DDL
SELECT pid, state, now() - xact_start AS age, left(query, 80)
FROM pg_stat_activity
WHERE state <> 'idle' AND xact_start IS NOT NULL
ORDER BY age DESC LIMIT 10;

-- Idle-in-transaction sessions: the classic migration blocker
SELECT pid, now() - state_change AS idle_for, left(query, 80)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_for DESC;

-- Who currently holds locks on the target table
SELECT l.pid, l.mode, l.granted, left(a.query, 80)
FROM pg_locks l JOIN pg_stat_activity a USING (pid)
WHERE l.relation = 'users'::regclass;

-- Table size before deciding whether a rewrite is acceptable
SELECT pg_size_pretty(pg_total_relation_size('users')),
       (SELECT reltuples::bigint FROM pg_class WHERE relname = 'users');
```

## Migration preamble

```sql
SET lock_timeout = '3s';       -- fail fast rather than queue behind a held lock
SET statement_timeout = '30s'; -- cap the whole statement
```

Without `lock_timeout`, a DDL statement waiting on a lock queues every subsequent reader behind it, because Postgres grants locks FIFO. One stuck `ALTER TABLE` becomes a full read outage on that table.
