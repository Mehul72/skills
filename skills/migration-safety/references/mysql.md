# MySQL / MariaDB Migration Hazards

MySQL's story is `ALGORITHM` and `LOCK`. Since 5.6 many operations are "online", and 8.0 added `INSTANT` for a handful. The trap is that when an operation *cannot* meet the algorithm you wanted, MySQL silently falls back to a full copy, unless you force it to fail instead.

## Always state the algorithm and lock explicitly

```sql
ALTER TABLE users ADD COLUMN nickname VARCHAR(64) NULL,
  ALGORITHM=INPLACE, LOCK=NONE;
```

If MySQL cannot honour `ALGORITHM=INPLACE, LOCK=NONE`, the statement **errors out** instead of quietly rewriting a 300M-row table under a write lock. Never let the algorithm be chosen for you.

Algorithms, cheapest first:

- `INSTANT` (8.0.12+), metadata change only, no table touch, no data copy.
- `INPLACE`, rebuilds in place; usually permits concurrent DML (`LOCK=NONE`), but still costs a full pass over the table and its I/O.
- `COPY`, builds a whole new table. Blocks writes for the duration. Treat as an outage on any large table.

## Operation classification

| Operation | Best algorithm | Concurrent DML? | Notes |
|---|---|---|---|
| `ADD COLUMN` (last position, no default or constant default) | `INSTANT` (8.0.12+) | Yes | Pre-8.0.12: `INPLACE` |
| `ADD COLUMN` at a specific position (`AFTER x`, `FIRST`) | `INPLACE` | Yes | Position forces a rebuild. Always append instead |
| `ADD COLUMN` with expression/volatile default | `COPY` | **No** | Add without default, set default separately, backfill |
| `DROP COLUMN` | `INSTANT` (8.0.29+) | Yes | Earlier: `INPLACE` rebuild. Still breaks running code, remove code references first |
| `RENAME COLUMN` | `INSTANT` / `INPLACE` | Yes | Cheap in DB, instantly breaks running code. Use the add/dual-write/drop sequence |
| `MODIFY COLUMN`, widen `VARCHAR` within the same length-byte class | `INPLACE` | Yes | ≤255 → ≤255 is fine; crossing the 255-byte boundary forces `COPY` |
| `MODIFY COLUMN`, narrow, or change type/charset | `COPY` | **No** | New column → dual-write → backfill → drop old |
| `MODIFY COLUMN`. Add `NOT NULL` | `INPLACE` | Yes | Requires `ALTER TABLE ... ALGORITHM=INPLACE` and no NULLs present; fails otherwise |
| `ADD INDEX` (secondary) | `INPLACE` | Yes | Cheap on small tables, heavy I/O on large ones |
| `DROP INDEX` | `INPLACE` | Yes | Metadata-only in practice |
| `ADD PRIMARY KEY` / change PK | `COPY` | **No** | Full rebuild of table and every secondary index. Use gh-ost/pt-osc |
| `ADD FOREIGN KEY` | `INPLACE` | Yes | Only with `foreign_key_checks=0`; otherwise `COPY` |
| `ADD CHECK` constraint (8.0.16+) | `COPY` | **No** | Add with `NOT ENFORCED`, then enforce separately |
| `CHANGE CHARACTER SET` / `CONVERT TO` | `COPY` | **No** | Full rewrite. Use an external OSC tool |
| `OPTIMIZE TABLE` | `INPLACE` | Yes | Still a full rebuild's worth of I/O |

## When the operation needs COPY: use an online schema change tool

For anything that falls back to `COPY` on a large table, don't run it directly. Use `gh-ost` or `pt-online-schema-change`. Both build a shadow table, copy rows in throttled batches, keep it in sync, then swap.

- **gh-ost** reads the binlog to sync, no triggers, lighter on the primary, pausable, and throttles on replica lag. Prefer it where the binlog is available (`binlog_format=ROW`).
- **pt-online-schema-change** uses triggers, works in more topologies but adds write overhead to every DML on the table for the duration, and interacts badly with existing triggers and some foreign keys.

Either way: throttle on replication lag, and rehearse the cutover. The swap is the risky moment.

## Pre-flight checks

```sql
-- Table size and row estimate
SELECT table_rows,
       ROUND((data_length + index_length)/1024/1024) AS mb
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name = 'users';

-- Long-running transactions that will block metadata locks
SELECT trx_id, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_s,
       trx_mysql_thread_id, LEFT(trx_query, 80) AS q
FROM information_schema.innodb_trx
ORDER BY trx_started;

-- Metadata locks currently held (8.0, requires performance_schema)
SELECT object_name, lock_type, lock_status, owner_thread_id
FROM performance_schema.metadata_locks
WHERE object_schema = DATABASE();

-- Replication lag: the number to watch during a backfill
SHOW REPLICA STATUS\G   -- Seconds_Behind_Source
```

## The metadata lock trap

Every `ALTER TABLE`, even an `INSTANT` one, needs a brief exclusive **metadata lock**. It cannot be granted while any transaction, including a long-idle one that merely `SELECT`ed from the table and never committed, still holds the table open. The `ALTER` then waits, and every subsequent query on that table queues behind it.

Set a bounded wait so this fails fast rather than cascading:

```sql
SET SESSION lock_wait_timeout = 5;  -- seconds; default is 31536000 (1 year)
```

Then kill blockers and retry, rather than letting the ALTER sit there taking the table down.
