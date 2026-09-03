---
name: migration-safety
description: >-
  Review or write a database schema/data migration so it ships without downtime:
  expand-contract sequencing, lock analysis, safe index creation, and batched backfills. Use
  when the task involves ALTER TABLE, CREATE INDEX, adding/removing/renaming a column or
  table, changing a column type, adding a constraint or foreign key, backfilling data, or any
  DDL that will run against a table with live traffic.
---

# Migration Safety

A migration is safe when **the old code and the new code can both run against the schema at the same time**, and when no statement holds a blocking lock long enough to stall traffic. Almost every migration outage is a violation of one of those two rules.

Not for: making an existing query fast (use `sql-performance`), or the API contract change that accompanies the schema change (use `api-change-review`). The deploy sequencing here pairs with `safe-rollout`.

## Step 1: Establish the facts

Do not review a migration in the abstract. Find out:

- **Which engine and version:** Postgres and MySQL have different hazards, and both fixed major ones in specific versions (see `references/postgres.md`, `references/mysql.md`).
- **How big is the table:** row count and on-disk size. A rewrite of 10k rows is a non-event; a rewrite of 500M rows is an outage. Get the real number, don't estimate.
- **Is the table hot:** writes/sec and reads/sec. A lock on a cold table is free.
- **How the app is deployed:** rolling deploy means old and new code run concurrently, for minutes or hours. If you cannot guarantee otherwise, assume they do.

## Step 2: Classify every operation

For each statement in the migration, decide which bucket it lands in:

| Bucket | Meaning | Action |
|---|---|---|
| **Safe** | Metadata-only, sub-millisecond lock | Ship it |
| **Blocking** | Takes a strong lock for the duration of a table scan or rewrite | Rewrite using the safe alternative |
| **Incompatible** | Schema and running code disagree for some window | Split across deploys (Step 3) |

The per-operation tables in `references/postgres.md` and `references/mysql.md` classify the common operations. Load the one matching the engine. The operations that catch people most often:

- **Adding an index** without `CONCURRENTLY` (Postgres) blocks writes for the whole build.
- **Setting `NOT NULL`** on an existing column scans the table under a lock that blocks reads *and* writes.
- **Adding a foreign key or check constraint** validates every existing row under a lock. Add it `NOT VALID`, then `VALIDATE` in a separate migration.
- **Changing a column type** rewrites the table. Nearly always needs the new-column dance instead.
- **Adding a column with a volatile default** (e.g. `now()`, `random()`, `uuid_generate_v4()`) rewrites the table. A *constant* default is metadata-only on Postgres 11+ and MySQL 8.0.12+ (`ALGORITHM=INSTANT`), but not before.
- **Dropping a column** is fast at the DB level but breaks any running code that still `SELECT *`s or maps that column.

## Step 3: Sequence it as expand → migrate → contract

Any change where old code and new schema cannot coexist must be split into separate, independently deployable steps. Never collapse these into one deploy.

**Adding a column:**
1. Add it nullable, no default (or a constant default). *Deploy.*
2. Deploy application code that writes the new column on every insert and update. *Deploy.*
3. Backfill the existing rows in batches (Step 4).
4. Add `NOT NULL` via the `NOT VALID` check-constraint route.

Step 2 must land before step 3. If you backfill first, every row written between the backfill finishing and the write path deploying is left NULL, and step 4 then fails on data that looks correct.

**Renaming or retyping a column.** Never rename in place:
1. Add the new column. *Deploy.*
2. Dual-write to both old and new from the application. *Deploy.*
3. Backfill the new column for historical rows.
4. Switch reads to the new column. *Deploy.* Let it soak.
5. Stop writing the old column. *Deploy.*
6. Drop the old column.

**Removing a column or table:**
1. Remove every read and write from application code. *Deploy.* Let it soak long enough that you'd have noticed, at minimum a full traffic cycle, including any nightly batch job.
2. Drop it.

The soak between steps is the point. Collapsing steps 4 and 5, or dropping on the same deploy that removed the reads, is how a rollback becomes an outage: rolling application code back to the previous version resurrects the reads, but the column is gone.

**A migration must be rollback-safe.** Before shipping, answer: if we redeploy the previous application version 10 minutes from now, does it still work against this schema? If not, the migration is in the wrong order.

## Step 4: Backfills are jobs, not migrations

Never backfill in the same transaction as the DDL, and never in one statement. A single `UPDATE users SET x = ...` over a large table holds row locks for its entire duration, bloats the WAL/redo log, and can block replication for as long as it runs.

- **Batch it.** Iterate over the primary key in ranges (`WHERE id > ? ORDER BY id LIMIT 1000`), not `OFFSET`. Commit each batch separately.
- **Throttle.** Sleep between batches. Watch replication lag and back off when it climbs. This is the failure mode that takes down read replicas.
- **Make it resumable.** Persist the cursor. A backfill that dies at 80% and must restart from zero is a bad backfill.
- **Make it idempotent.** Add `WHERE new_col IS NULL` so reruns are cheap and safe.
- **Run it out-of-band:** a script or job runner, not the migration tool. Migrations should be fast enough that nobody is tempted to kill one mid-run.

## Step 5: Bound every lock

Set a lock timeout so a migration that cannot get its lock fails fast instead of forming a queue behind itself:

```sql
-- Postgres
SET lock_timeout = '3s';
SET statement_timeout = '30s';
```

This matters more than it looks. In Postgres, lock requests are **queued in FIFO order**: if your `ALTER TABLE` is waiting on an `ACCESS EXCLUSIVE` lock held by some long-running transaction, every plain `SELECT` that arrives afterward queues up *behind your ALTER*, even though those reads would not have conflicted with the original holder. One blocked DDL statement stalls all reads on the table. A short `lock_timeout` turns that outage into a failed migration you can retry.

Also check for long-running transactions and idle-in-transaction sessions *before* running DDL; they are the thing your migration will block on.

## Common rationalizations

| "..." | Reality |
|---|---|
| "The table is small" | Check the row count. "Small" is a memory of two years ago, and it's the assumption behind most migration outages |
| "It's just adding a column" | With a volatile default, or `NOT NULL`, that's a full table rewrite under an exclusive lock |
| "We'll deploy the code and migration together" | Then there is a window where one of them is wrong, and no rollback that works |
| "Rolling deploys are fast, old code won't be running long" | Minutes is long enough. And a rollback puts old code back deliberately |
| "The migration ran fine in staging" | Staging has 10k rows and no concurrent traffic. Neither property holds where it matters |
| "We can backfill in the migration, it's one statement" | One statement over a large table holds locks for its whole duration and blocks replication |
| "Nobody reads that column" | Verify it. `SELECT *`, ORM models, analytics jobs, and the reporting replica all read it |
| "We'll add the index later if it's slow" | Adding it later is a `CREATE INDEX` on a bigger table under more traffic |

## Red flags

- A migration file with no `lock_timeout` set
- DDL and backfill in the same transaction
- `CREATE INDEX` without `CONCURRENTLY` (Postgres) or without a stated `ALGORITHM`/`LOCK` (MySQL)
- A column dropped in the same deploy that removed its last reader
- A rename in place
- A backfill with no batching, no cursor, and no replication-lag check
- No answer to "what happens if we redeploy the previous version in 10 minutes?"

## Output

When reviewing, report per statement: the lock it takes, how long it holds it at this table's size, whether old code survives it, and the rewritten version if it isn't safe. Call out the deploy boundaries explicitly. Say which statements ship together and which must wait for the next deploy.

When authoring, emit one file per deploy step, in order, each with the lock/timeout preamble, plus the backfill script separately.

Do not report a migration as safe because it is syntactically valid. Safe means: lock-bounded, rollback-safe, and survivable by the currently deployed code.
