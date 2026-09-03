---
name: resilience-review
description: >-
  Review or design how a service calls its dependencies so a downstream failure doesn't take
  it down: timeouts, deadline propagation, retries with jitter, retry budgets, circuit
  breakers, idempotency, and load shedding. Use when adding an outbound RPC/HTTP call,
  reviewing retry or timeout config, diagnosing a cascading failure or retry storm, or
  hardening a service for production.
---

# Resilience Review

Every outbound call is a chance for someone else's bad day to become yours. This skill is about the code between your service and its dependencies: what happens when the dependency is slow, wrong, or gone.

The failure mode that matters most is not "the dependency went down". It is **"the dependency got slow, and we amplified it"**.

Not for: a retry storm happening right now (use `incident-response`). Instrumenting the signals that show these failures is `observability`.

## Step 1: Inventory the calls

List every outbound dependency, RPC, HTTP, database, cache, queue, object store, third-party. For each, record what it does when the dependency is unavailable and when it is *slow*. Slow is the harder case and the one people skip.

For each call, work through the checks below in order. They build on each other: retries without timeouts are meaningless, and circuit breakers without both are decoration.

## Step 2: Timeouts

**Rule: every call has an explicit timeout.** No exceptions. A call without a timeout will eventually hang forever, and the thread, goroutine, or connection holding it never comes back. That is how a slow dependency turns into an exhausted pool and a total outage, the dependency never even had to fail.

Check specifically:
- Default client timeouts are usually wrong or infinite. Go's `http.Client` zero value has **no timeout at all**. JDBC and many database drivers default to none. Never rely on a library default. Set it explicitly and state why.
- Set connect, read/write, and total-request timeouts. A read timeout alone doesn't bound a slow-trickling response.
- Size the timeout from the dependency's **p99 latency, not its mean**, typically a small multiple of p99. A timeout below p99 turns normal slow-tail requests into errors; a timeout of 30s on a service with a 50 ms p99 isn't a timeout, it's a hang.
- The timeout budget must shrink as you go down the stack. If your handler has 1s and calls three services in sequence, they cannot each have 1s.

**Propagate deadlines.** Pass the caller's remaining deadline downstream (`context.Context` in Go, gRPC deadlines, a deadline header for HTTP) rather than inventing a fresh one at each hop. Then check it before starting expensive work: if the deadline has already passed, fail immediately instead of doing work whose result nobody is waiting for. Under overload, a service without deadline propagation spends all its capacity computing responses that have already been abandoned, and never recovers on its own.

## Step 3: Retries

Retries are the most common cause of the outage they were added to prevent. Each check below is one of the ways that happens.

**Only retry what is safe to retry.** Retry on connection failures, timeouts, 429, 502/503/504, and explicitly retryable RPC codes (`UNAVAILABLE`, `RESOURCE_EXHAUSTED`). Never retry 400, 401, 403, 404, 422, or `INVALID_ARGUMENT`, the answer won't change, and you've turned one client error into five.

**A timeout is ambiguous.** You do not know whether the write happened. Retrying a non-idempotent write after a timeout duplicates it. Either make the operation idempotent (Step 5) or do not retry it.

**Always backoff with jitter.** Fixed-interval retries synchronize clients into waves that arrive together and re-break the recovering dependency. Use **full jitter**, which measured best in AWS's published comparison, lowest total work, competitive completion time:

```
sleep = random_between(0, min(cap, base * 2^attempt))
```

Not `base * 2^attempt` (synchronizes), and not `half + random(half)` (equal jitter, measurably worse than full jitter on both work and time).

**Cap the attempts.** Two or three, then fail. "Retry until success" is how a service DDoSes its own dependency.

**Never stack retries across layers.** Three layers retrying three times each is 27 requests from one user action. Retry at exactly one layer, usually the one closest to the caller that can still make a meaningful decision, and make every other layer pass the failure through. This is the single most destructive pattern in this document, and it's invisible in any one file: you have to trace the whole call path to find it.

**Budget the retries.** Per-request limits don't stop a fleet-wide storm: if every request is failing, every request is also retrying, and you've tripled load on a dependency that is already falling over. Add a service-wide budget, a token bucket allowing retries only up to a small fraction (commonly ~10%) of successful request volume. When the budget is exhausted, fail immediately without retrying. This is what converts a death spiral into a partial outage that recovers.

**Respect `Retry-After`.** If the dependency told you when to come back, backing off sooner is just noise.

## Step 4: Circuit breakers and load shedding

**Circuit breaker** on each dependency: after a failure-rate threshold over a rolling window, open the circuit and fail fast for a cooldown, then let a small number of trial requests through (half-open) before closing. The point is to stop spending your own resources, threads, connections, memory, waiting on something you already know is broken.

Trip on **rate over a window**, not on consecutive failures, and require a minimum request volume so three failures on a quiet endpoint don't open the circuit.

**Shed load at the entrance.** When in-flight requests exceed what the service can handle, return 503 immediately rather than queueing. Queueing under overload converts a capacity problem into a latency problem and then into a timeout cascade, the requests still get served, just after everyone gave up.

**Bound every queue.** An unbounded work queue is a memory leak with extra steps: it absorbs the backpressure that should have been visible, then the process OOMs. Small queues relative to worker count; reject early when full.

**Degrade gracefully where you can.** Serving stale cache, a partial result, or a sane default beats a 500, when the semantics allow it. Be explicit about when they don't: a stale authorization check or a defaulted payment amount is worse than an error. Say which mode this call is in.

**Isolate the pools.** One connection pool shared across a critical and a non-critical dependency means the non-critical one can starve the critical one. Separate pools per dependency, sized deliberately.

## Step 5: Idempotency

Any operation a client might retry must be safe to execute more than once. Since timeouts are indistinguishable from failures, "might retry" means "will retry".

- **Idempotency keys** for creates: the client sends a unique key, the server stores key → result, and a replay returns the stored result rather than re-executing. Persist the key in the same transaction as the effect, or the guarantee is fictional. Document the retention window.
- **Natural idempotency** where possible: `SET x = 5` is idempotent, `x = x + 1` is not. Prefer absolute writes to relative ones.
- **Conditional writes** for read-modify-write: compare-and-swap on a version column, or `If-Match`/ETag. Without this, two concurrent updates silently lose one.
- **Consumers must assume redelivery.** Nearly every queue is at-least-once, so every consumer needs a dedupe key or an idempotent effect. Check this explicitly. It's a common gap.
- **Exactly-once delivery does not exist.** If a design depends on it, that's the finding.

## Step 6: Verify it

Configuration that has never been exercised is a hypothesis:

- Does the timeout actually fire? Point the client at a sinkhole that accepts and never responds.
- Does the circuit breaker open, and does it close again?
- Are retries actually bounded? Count the requests reaching a fault-injected dependency.
- What happens under 2x expected load, does the service shed, or does it fall over?
- Load-test with the dependency *slow*, not just *down*. Slow is the case that exhausts pools, and the one nobody tests.

## Common rationalizations

| "..." | Reality |
|---|---|
| "The client library has sensible defaults" | Go's `http.Client` zero value has no timeout at all. Check, don't assume |
| "It's an internal service, it's reliable" | Internal services deploy, GC, saturate, and get rate-limited like everything else |
| "Retrying makes it more reliable" | Unbudgeted retries are how a degraded dependency becomes a dead one |
| "We retry at the gateway anyway" | Then you have stacked retries and don't know your real amplification factor. Trace the whole path |
| "The timeout is generous so we don't get false failures" | A 30s timeout on a 50ms service isn't a timeout, it's a hang that exhausts your pool |
| "It's idempotent enough" | Either it is or it isn't. `x = x + 1` is not, and a retry after a timeout will run it twice |
| "The queue guarantees exactly-once" | It does not. Nothing does. Assume redelivery and dedupe |
| "We'll add the circuit breaker if it becomes a problem" | It becomes a problem during the incident, which is the worst time to be writing one |

## Red flags

- Any outbound call with no explicit timeout
- A retry wrapping a non-idempotent write
- Retry logic at more than one layer of the same call path
- Exponential backoff with no jitter
- A circuit breaker tripping on consecutive failures with no minimum volume
- One connection pool shared between a critical and a non-critical dependency
- An unbounded work queue or channel
- A new deadline created at each hop instead of the caller's being propagated
- Resilience config that has never been exercised against a *slow* dependency

## Output

Produce a table: dependency, timeout (and the p99 it was derived from), retry policy, breaker config, idempotency mechanism, and behavior on total failure.

Flag as **blocking**: any call with no timeout, any retry of a non-idempotent write, and any stacked retry across layers. Everything else is a recommendation with its risk stated.
