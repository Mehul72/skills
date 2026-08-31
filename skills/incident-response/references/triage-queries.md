# Incident Triage Commands

Adapt names and namespaces to the environment. Run the cheap, read-only checks first, several of these (heap dumps, `pg_terminate_backend`) have real side effects and are marked.

## What changed

```bash
git log --oneline --since="4 hours ago"
git log --oneline --since="4 hours ago" -- path/to/suspect/service

# Kubernetes rollout history
kubectl rollout history deployment/<name>
kubectl rollout status  deployment/<name>
kubectl rollout undo    deployment/<name>            # MITIGATION, announce first
kubectl rollout undo    deployment/<name> --to-revision=<n>

# What was recently applied
kubectl get events --sort-by=.lastTimestamp | tail -40
```

Also check by hand: feature-flag audit log, config-service change history, certificate expiry, and the status pages of every third-party dependency.

## Service health

```bash
curl -sf -o /dev/null -w '%{http_code} %{time_total}s\n' https://svc/health
curl -s https://svc/health | jq .

# Is it the LB, the app, or the dependency? Hit each layer directly.
```

## Kubernetes

```bash
kubectl get pods -A | grep -Ev 'Running|Completed'
kubectl get pods -l app=<name> -o wide

kubectl describe pod <pod> | tail -40          # Events: OOMKilled, scheduling failures, probe failures
kubectl logs <pod> --tail=200 --since=15m
kubectl logs <pod> --previous --tail=200       # the crashed container, not the new one

kubectl top pods  --sort-by=memory
kubectl top nodes

# Restart counts: the fastest read on a crashloop
kubectl get pods -l app=<name> \
  -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATE:.status.phase

# Is HPA maxed out?
kubectl get hpa
```

`OOMKilled` in pod events means the memory limit, not necessarily a leak. Check whether the limit changed before assuming the code did.

## Host / process

```bash
uptime                       # load average vs. core count
vmstat 1 5                   # r column = runnable queue; si/so = swapping
iostat -x 1 5                # %util near 100 = disk-bound
df -h && df -i               # disk AND inodes, inode exhaustion looks like a disk-full bug
ss -s                        # socket summary; look for TIME-WAIT / CLOSE-WAIT buildup
ss -tan state close-wait | wc -l   # CLOSE-WAIT growth = app not closing sockets

# Per-process
top -b -n1 | head -20
lsof -p <pid> | wc -l        # file descriptor count
cat /proc/<pid>/limits       # against the FD limit
```

## Go services

```bash
# Requires net/http/pprof registered
curl -s localhost:6060/debug/pprof/goroutine?debug=1 | head -50   # goroutine leak: count climbing
curl -s localhost:6060/debug/pprof/heap > heap.out                # SIDE EFFECT: brief stop-the-world
go tool pprof -top heap.out

curl -s 'localhost:6060/debug/pprof/profile?seconds=30' > cpu.out # 30s CPU profile
go tool pprof -top cpu.out
```

A steadily climbing goroutine count is the signature of missing timeouts or an unclosed response body.

## JVM services

```bash
jcmd <pid> Thread.print | head -100      # thread dump, look for BLOCKED threads on a common lock
jcmd <pid> GC.heap_info
jstat -gcutil <pid> 1000 10              # GC pressure: FGC climbing = full GCs
jcmd <pid> GC.heap_dump /tmp/heap.hprof  # SIDE EFFECT: pauses the JVM, writes a large file
```

## PostgreSQL

```sql
-- Connection count vs. limit: exhaustion looks like a total outage
SELECT count(*) FROM pg_stat_activity;
SHOW max_connections;
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

-- Long-running queries
SELECT pid, now() - query_start AS duration, state, wait_event_type, wait_event,
       left(query, 100) AS query
FROM pg_stat_activity
WHERE state <> 'idle' AND now() - query_start > interval '30 seconds'
ORDER BY duration DESC;

-- Blocking chains: who is waiting on whom
SELECT blocked.pid AS blocked_pid, left(blocked.query, 60) AS blocked_query,
       blocking.pid AS blocking_pid, left(blocking.query, 60) AS blocking_query,
       now() - blocking.query_start AS blocking_duration
FROM pg_stat_activity blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS bpid ON true
JOIN pg_stat_activity blocking ON blocking.pid = bpid
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;

-- Idle in transaction: holds locks, blocks DDL, prevents vacuum
SELECT pid, now() - state_change AS idle_for, left(query, 80)
FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY idle_for DESC;

-- Top queries by total time (needs pg_stat_statements)
SELECT calls, round(total_exec_time::numeric, 0) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms, left(query, 90)
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 15;

-- Replication lag
SELECT client_addr, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

-- MITIGATION, cancel, then kill. Announce before running.
SELECT pg_cancel_backend(<pid>);     -- polite: cancels the query
SELECT pg_terminate_backend(<pid>);  -- forceful: kills the connection
```

## MySQL

```sql
SHOW GLOBAL STATUS LIKE 'Threads_connected';
SHOW GLOBAL VARIABLES LIKE 'max_connections';

-- Long-running / stuck queries
SELECT id, user, host, db, command, time, state, LEFT(info, 100)
FROM information_schema.processlist
WHERE command <> 'Sleep' AND time > 30 ORDER BY time DESC;

-- Open transactions (the ones holding locks)
SELECT trx_id, trx_state, trx_started,
       TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_s,
       trx_rows_locked, trx_mysql_thread_id, LEFT(trx_query, 80)
FROM information_schema.innodb_trx ORDER BY trx_started;

-- Lock waits (MySQL 8.0)
SELECT r.trx_id AS waiting_trx, LEFT(r.trx_query, 50) AS waiting_query,
       b.trx_id AS blocking_trx, LEFT(b.trx_query, 50) AS blocking_query
FROM performance_schema.data_lock_waits w
JOIN information_schema.innodb_trx r ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.innodb_trx b ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID;

SHOW ENGINE INNODB STATUS\G      -- deadlock history, buffer pool, pending I/O
SHOW REPLICA STATUS\G            -- Seconds_Behind_Source

-- MITIGATION, announce before running
KILL QUERY <thread_id>;          -- kills the statement, keeps the connection
KILL <thread_id>;                -- kills the connection
```

## Redis

```bash
redis-cli INFO stats | grep -E 'instantaneous_ops|keyspace_(hits|misses)|rejected'
redis-cli INFO clients            # connected_clients, blocked_clients
redis-cli INFO memory             # used_memory vs maxmemory; evicted_keys
redis-cli INFO replication
redis-cli SLOWLOG GET 20
redis-cli --latency-history

# NEVER run KEYS * on a production instance. It blocks the server.
redis-cli --scan --pattern 'prefix:*' | head
```

## Kafka / consumers

```bash
# Consumer lag is the number that matters
kafka-consumer-groups.sh --bootstrap-server <broker> --describe --group <group>

# Partition skew: one hot partition looks like a broken consumer
kafka-topics.sh --bootstrap-server <broker> --describe --topic <topic>
```

## Load balancer / edge

Check, in this order: 5xx rate at the edge vs. at the app (a gap means the LB or a proxy), upstream health-check status, TLS certificate expiry, DNS resolution, and connection/queue limits at the proxy.

A 502/504 at the edge with clean app logs usually means the app never received the request, look at connection limits, health checks, and pod readiness, not application code.
