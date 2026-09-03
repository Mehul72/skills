---
name: observability
description: >-
  Add or review logging, metrics, tracing, and alerts for a backend service so production
  failures are diagnosable: structured log discipline, RED/USE metrics, OpenTelemetry span
  conventions, cardinality control, and symptom-based alerting. Use when instrumenting a new
  service or endpoint, when an incident revealed you couldn't see what happened, when
  reviewing log/metric/alert changes, or on any mention of tracing, spans, dashboards, SLOs,
  or on-call alerts.
---

# Observability

The test for instrumentation is not "did we log something". It is: **when this breaks at 3am, can someone who has never read this code find the cause without adding new instrumentation and redeploying?**

Instrument for the questions you'll need to answer, not for the code paths that happen to exist.

Not for: diagnosing a failure happening right now (use `incident-response`, then `systematic-debugging`). This skill is what makes those fast next time. Not for optimizing a measured-slow query either (use `sql-performance`).

## Start from the questions, not the code

Telemetry without a question is noise. Before adding anything, write down the two to four questions an on-call engineer will ask about this feature:

```
FEATURE: checkout payment retry
ON-CALL WILL ASK:
1. What fraction of payments succeed first attempt vs. after retry?
2. When one fails permanently, why, provider error, timeout, or validation?
3. Is the provider slower than usual, and since when?
→ every signal below must answer one of these.
```

If you can't name the questions, you aren't ready to instrument. You'll log everything and learn nothing. This is also the test for *removing* instrumentation: a metric that answers no question anyone asks is cost without value.

## Choosing the signal

Use all three, for different jobs. The most common mistake is logging things that should be metrics, which is both expensive and useless for alerting.

| Signal | Answers | Cost | Use for |
|---|---|---|---|
| **Metrics** | "How often, how slow, how many?" | Cheap, aggregatable, bounded | Alerting, dashboards, trends, SLOs |
| **Traces** | "Where did this one request spend its time?" | Moderate, sampled | Latency breakdown, cross-service causality |
| **Logs** | "What exactly happened in this case?" | Expensive at volume | Debugging specific events, audit trails |

Rule of thumb: if you'd ever want to *graph* it or *alert* on it, it's a metric. If you'd want to read it for one specific request, it's a log line or a span. Counting log lines to produce a rate is a sign the metric is missing.

## Metrics

**For request-driven services, use RED**, per endpoint or RPC method:
- **Rate:** requests/sec
- **Errors:** failed requests/sec, split by cause. Client error, server error, and timeout need different responses
- **Duration:** a latency *histogram*, not an average

**For resources** (connection pools, queues, thread pools, caches) **use USE:**
- **Utilization:** how full (pool in-use / capacity)
- **Saturation:** the queue depth or wait time when it's full
- **Errors:** acquisition timeouts, rejections, evictions

**Always histograms for latency, never averages.** An average hides exactly the tail you care about, and averages of averages are meaningless. Record a histogram and derive p50/p90/p99/p99.9 at query time.

**Instrument the things that break:** connection pool exhaustion, queue depth and consumer lag, retry counts, circuit breaker state transitions, cache hit rate, goroutine/thread counts, GC pause time. Pool exhaustion and queue depth are the two that most often explain an outage and most often aren't measured.

### Cardinality is a budget

A metric's cost is `series = product of all label value counts`. Labels multiply. One well-meaning `user_id` label on a metric with 5 other labels can produce millions of series and take down your metrics backend, a genuinely common way to cause a second incident during the first one.

- **Never label with:** user ID, request ID, trace ID, email, raw URL path, full error message, timestamp, session ID.
- **Safe labels:** endpoint/route *template* (`/users/{id}`, never `/users/12345`), method, status class, region, service version, a bounded error-code enum.
- Before adding a label, multiply out the worst-case series count. If it isn't bounded by a value you control, it doesn't belong on a metric. Put it in a log line or span attribute instead, where high cardinality is fine.

## Traces

Follow OpenTelemetry semantic conventions rather than inventing attribute names, the tooling depends on them.

**Span naming:** `{method} {low-cardinality target}`, `GET /users/{id}`, not `GET /users/12345`. The spec is explicit that instrumentation must **not** default to the raw URI path as the span name; it destroys the ability to aggregate. Use the route template (`http.route`).

**Key attributes:**
- HTTP server: `http.request.method`, `url.path`, `url.scheme`, `http.route`, `http.response.status_code`, `client.address`
- HTTP client: `http.request.method`, `server.address`, `server.port`, `url.full`
- Set span status to Error on 5xx and on request failures, with `error.type`. For 4xx: error on the **client** span, unset on the **server** span, a 400 is the client's bug, not the server's failure.

**What to span:** every inbound request, every outbound call (RPC, HTTP, DB, cache), and any in-process step over ~10 ms that you'd want broken out. Don't span every function, a trace with 400 spans is as unreadable as one with none.

**Attributes over log lines.** Inside a span, attach context as span attributes rather than emitting logs. High cardinality is fine here. That's the point of spans.

**Propagate context across every boundary**, including queues. A trace that stops at the producer and resumes as a separate trace in the consumer has lost the causality you needed. Inject W3C `traceparent` into message headers.

**Sample head-based for volume, tail-based for value.** Tail sampling lets you keep 100% of errors and slow requests while dropping most successful ones, which is what you actually want. Always propagate the sampling decision.

## Logs

**Structured, always.** JSON or logfmt with typed fields. Never interpolated prose. `log.Info("user login failed", "user_id", id, "reason", reason)`, never `log.Info(fmt.Sprintf("login failed for %s: %s", id, reason))`. Interpolated messages can't be filtered, aggregated, or alerted on.

**Every log line carries correlation IDs:** `trace_id`, `span_id`, `request_id`, plus tenant/user where relevant. A log you can't tie back to a request is nearly useless during an incident. Put this in middleware once; don't rely on every call site remembering.

**Levels, with actual meaning:**
- `ERROR`: a human needs to look at this. If it fires routinely and nobody looks, it isn't an error, and it's training your team to ignore real ones.
- `WARN`: degraded but handled. Worth a graph, not a page.
- `INFO`: significant state changes and request boundaries. Low volume.
- `DEBUG`: off in production, toggleable per-request or per-component without redeploy.

**Log errors once, at the point where they're handled.** Logging at every level of the call stack as an error bubbles up produces five lines for one failure and makes error counts meaningless. Wrap with context on the way up (`fmt.Errorf("fetching user %s: %w", id, err)`), log at the top.

**Never log:** passwords, tokens, API keys, session cookies, full card numbers, government IDs, or raw request bodies that might contain any of these. Redact at the logging layer, not at each call site, call sites forget, and one leak is permanent. Watch for the indirect paths: a struct dumped with `%+v`, an error string embedding a connection URL with credentials, a stack trace containing arguments.

**Log the inputs needed to reproduce.** An error line without the identifiers of what it was operating on can't be acted on. "Failed to process order" is not a log line; "failed to process order" with `order_id`, `merchant_id`, and the wrapped cause is.

**Sample high-volume lines.** A per-request log at 50k rps is a cost problem and a signal-to-noise problem.

## Alerts

**Alert on symptoms, not causes.** Page on "checkout error rate exceeds 2%" or "p99 latency exceeds the SLO", not on "CPU is above 80%". High CPU with healthy latency is not a problem; it's a well-utilized machine. Cause-based alerts train people to ignore pages.

**Every page must be actionable and urgent.** If the response is "watch it" or "fix it Monday", it is a ticket or a dashboard, not a page. Alert fatigue is the mechanism by which the one real page gets missed.

**Alert on SLO burn rate, not raw thresholds.** Multi-window burn-rate alerting, a fast window to catch acute breakage, a slow window to catch a steady leak, is what keeps a brief blip from paging while a sustained 1% error rate still does.

**Every alert needs a runbook link** answering: what does this mean, what's the blast radius, what do I check first, how do I mitigate. Write it when you write the alert; it will never be written afterward.

**Alert on staleness too.** A metric that stopped reporting looks identical to a healthy zero. `absent()` or a heartbeat check catches the collector dying, an outage class that is otherwise entirely invisible.

## Verify the telemetry itself

Instrumentation is code, and it can be wrong. Before calling it done, trigger the paths and look at real output:

- Force an error in staging → find it by `request_id`; confirm fields are structured, not `[object Object]` or a stringified struct
- Send test traffic → confirm the metric series appear, with the expected labels and sane values
- Follow one request across services in the tracing UI → no broken or orphaned spans
- Fire each new alert once, by temporarily lowering the threshold → confirm it reaches the right channel and the runbook link resolves

An alert that has never fired is an alert you have no reason to believe works.

## Common rationalizations

| "..." | Reality |
|---|---|
| "I'll add logging after it works" | "After" means "after the first incident", the most expensive moment to discover you're blind |
| "More logs means more observability" | Unstructured volume makes incidents slower. Three queryable events beat three hundred prose lines |
| "We'll look at the dashboards when it breaks" | Dashboards built without defined questions show you everything except the answer |
| "Alert on everything important, tune later" | The tuning never happens. The ignored pager does |
| "User ID as a label makes debugging easier" | And makes the metrics backend fall over. High cardinality belongs in logs and spans |
| "Tracing is overkill for two services" | Two services already produce cross-service latency questions logs cannot answer |
| "The error is logged upstream" | Then it's logged three times and the count means nothing. Log once, where it's handled |

## Red flags

- A PR adding retries, queues, or external calls with no new telemetry
- Log lines built by string interpolation instead of structured fields
- No correlation ID, every log line is an orphan
- Metrics labeled with user IDs, raw URLs, or error message text
- Latency tracked as an average, with no percentiles
- Alerts that fire daily and are acknowledged without action
- Alerts paging on CPU while user-facing error rate is unmonitored
- Secrets, tokens, or raw request bodies in log output
- A metric that stopped reporting and looks identical to a healthy zero

## Output

When instrumenting: the metrics with names, types, and labels (with the cardinality bound stated); the spans and attributes; the log lines with fields; the alerts with thresholds and runbook stubs.

When reviewing: name the questions this instrumentation cannot answer. The valuable finding is not "add more logs", it's "when this endpoint returns 500, nothing records *which* dependency failed."
