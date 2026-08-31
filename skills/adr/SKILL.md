---
name: adr
description: Write an Architecture Decision Record capturing why a technical decision was made, what was rejected, and what would reverse it. Use when choosing a framework, datastore, protocol, or vendor, when making a decision that is expensive to reverse, when the same design argument keeps getting relitigated, or when asked for an ADR or decision doc.
---

# Architecture Decision Records

Code shows what was built. An ADR records **why it was built this way, what else was considered, and what would change the answer.** That third part is what makes a decision revisitable instead of merely archaeological.

An ADR is short, one page. If you need diagrams, per-interface flows, and a schema, you want a full design doc: use `backend-design-doc`. The ADR records the *decision*; the design doc records the *design*.

## When it's worth writing one

Write an ADR when the decision is **expensive to reverse** or **non-obvious to a newcomer**:

- Choosing a datastore, queue, framework, protocol, or vendor
- Committing to a data model or partitioning scheme
- An auth or tenancy model
- Sync vs. async, monolith vs. service split, build vs. buy
- Deliberately accepting a tradeoff someone will later think is a bug, a denormalization, a known race, a consistency compromise

**Don't** write one for reversible or obvious choices. An ADR per library upgrade trains people to ignore the directory.

A good trigger: you've explained the same decision three times, or a code review reopened a settled argument. That's a missing ADR.

## Match the existing convention first

Before creating anything, check how this repo already does it, `docs/adr/`, `docs/decisions/`, an `.adr-dir` file, a MADR layout, `adr-tools`. Match the location, filename pattern, numbering sequence, markup, and heading set. Continue the sequence; never restart numbering or introduce a second scheme. If conventions conflict, say so rather than silently adding a third.

Only when no convention exists, use `docs/decisions/NNNN-kebab-title.md` and the template below.

## Template

```markdown
# ADR-0007: Use Redis Streams for the notification fan-out

## Status
Proposed | Accepted | Superseded by ADR-0012 | Deprecated

## Date
2026-08-31

## Context
Notification fan-out currently runs inline in the request path; p99 checkout latency
is 340ms, of which ~180ms is fan-out to 3 downstream consumers. We need it off the
request path before the Q4 traffic increase (~4x projected peak).

Constraints:
- Ops team is 2 people; no appetite for a new stateful system to run
- We already operate Redis (7.x, HA) for caching and rate limiting
- At-least-once delivery is acceptable; consumers are already idempotent
- Peak ~12k notifications/sec projected

## Decision
Use Redis Streams with consumer groups for the fan-out queue.

## Alternatives Considered

### Kafka
- Pros: purpose-built, strong ordering and retention, scales well past our ceiling
- Cons: a new stateful system to operate; ~6 weeks of ops ramp-up we don't have
- Rejected: correct at 10x our volume, too expensive to operate at our size today

### Postgres table as a queue (SKIP LOCKED)
- Pros: no new infrastructure; transactional with the write that triggers it
- Cons: at 12k/sec this becomes the dominant write load on the primary
- Rejected: puts queue load on the datastore least able to absorb it

### SQS
- Pros: fully managed, no ops burden
- Cons: cross-region hop adds ~40ms; a second cloud dependency in the checkout path
- Rejected: latency budget and the added external dependency

## Consequences

### Positive
- Fan-out leaves the request path; expected p99 checkout ~160ms
- No new system to operate
- Consumer groups give us per-consumer lag metrics for free

### Negative
- Redis becomes an availability dependency for notifications, not just a cache, needs its own alerting and a documented failure mode
- Retention is memory-bound: a consumer down for hours will drop messages.
  Mitigation: alert on consumer lag > 60s; cap stream length with MAXLEN ~1M
- No native dead-letter queue; we build one (ADR-0008)

## Revisit If
- Sustained volume exceeds ~50k/sec, or retention needs exceed a few hours
- We add a third team needing the same bus (the operating cost of Kafka amortizes)
- Redis memory pressure from streams starts affecting cache hit rate
```

## What makes it useful

**Context is the constraints, not the backstory.** Write what forced the decision, team size, latency budget, existing infrastructure, deadline, compliance. A reader in two years needs to know which constraints still hold. "We need a queue" is not context; "2-person ops team, 12k/sec, we already run Redis" is.

**Alternatives need real reasons.** A rejected option with "not a good fit" is worthless. State the specific property that disqualified it. Include the option that was genuinely close, an ADR where every alternative was obviously bad is one where the real reasoning is missing, and it reads as justification rather than decision.

**Consequences must include the negatives.** This is the highest-value part and the one people omit. What did we accept? What now needs monitoring? What got harder? An ADR with only upsides is marketing, and the next engineer will hit the downside with no warning.

**"Revisit if" is what stops relitigation.** Name the conditions that would change the answer. Then the future argument is "have those conditions been met?", a fact question, rather than a rerun of the original opinion.

**Write it when deciding, not after building.** Written afterward it becomes justification for what you already did, and the alternatives get thin. Draft at "Proposed", circulate, then mark "Accepted".

**Never edit a decided ADR.** Records are immutable. When the decision changes, write a new one and mark the old one `Superseded by ADR-NNNN`. The old reasoning still explains why the code looked that way for two years.

## Red flags

- No alternatives section, or alternatives that were never seriously considered
- Consequences that are all positive
- Context describing the feature rather than the constraints
- An ADR written after the code shipped, with the outcome as the premise
- Decisions edited in place instead of superseded
- The decision states *what* but never *why*, replaceable by reading the code
