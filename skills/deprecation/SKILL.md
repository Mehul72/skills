---
name: deprecation
description: Retire an API, endpoint, service, table, or feature without breaking the people still using it: usage measurement, advisory vs. compulsory sunset, migration tooling, and the removal gate. Use when removing or replacing an existing system, sunsetting an endpoint or feature, consolidating duplicate implementations, deleting code nobody seems to own, or deciding whether to maintain or kill a legacy system.
---

# Deprecation

Most teams are good at building and bad at removing, so dead systems accumulate until they're load-bearing by accident. Every retained system costs security patches, dependency bumps, on-call surface, and the cognitive tax on everyone working nearby.

The discipline is: **removal is gated on measured usage reaching zero, never on a date passing.**

Not for: the schema change that implements the removal (use `migration-safety`), or the contract-compatibility analysis of the replacement (use `api-change-review`).

## Step 1: Decide whether to remove it at all

Answer honestly before starting, deprecation is a project, and an abandoned one leaves you maintaining two systems instead of one, which is the worst outcome available:

1. **Does it still provide unique value?** If yes, maintain it deliberately. Say so and stop.
2. **Who depends on it?** Quantify, see Step 2. This number decides everything downstream.
3. **Does a working replacement exist?** If not, build it first. Announcing a deprecation without an alternative just generates anxiety and no migrations.
4. **What does migration cost each consumer?** Trivially scriptable, or a quarter of work per team? If it's the latter and you can't help, you don't have a deprecation plan.
5. **What does *not* removing cost?** Security exposure, on-call load, engineer time, the complexity tax on everything adjacent. If you can't articulate this, the deprecation won't survive its first prioritization meeting.

**Hyrum's Law is the reason this is hard.** With enough consumers, every observable behavior of your system is depended on by someone, including bugs, timing quirks, error message text, field ordering, and side effects you never documented. This is why announcement alone never works: consumers can't "just switch" when they depend on behavior the replacement doesn't reproduce. Expect to discover at least one of these, and budget for it.

## Step 2: Measure usage. Do not guess

"Nobody uses that" is the single most expensive assumption in this workflow. Instrument first, always:

- **Add usage telemetry to the deprecated path** before announcing anything: a counter labeled by caller/client/service, plus a log line with enough identity to reach a human. Let it run at least a full business cycle.
- **Watch for the slow callers.** Monthly batch jobs, quarterly reports, annual compliance exports, and the disaster-recovery runbook nobody has run since last year. A week of clean telemetry proves nothing about a monthly job. This is the classic way a "dead" endpoint turns out to be load-bearing.
- **Grep the org, not just this repo.** Monorepo search, other repos, config, dashboards, alert definitions, cron jobs, notebooks, third-party integrations.
- **Field-level for APIs.** An endpoint's traffic count doesn't tell you whether the field you want to delete is being read. GraphQL and gRPC both need per-field usage tracking to answer this.

Removal is gated on this number reaching zero (or on every remaining caller being identified and signed off). Not on the announced date.

## Step 3: Choose advisory or compulsory

| | Advisory | Compulsory |
|---|---|---|
| **When** | Old path is stable and cheap to keep | Security risk, blocks a migration, or maintenance cost is unsustainable |
| **Mechanism** | Warnings, docs, nudges; consumers migrate on their own timeline | Hard removal date, with migration tooling and support |
| **You must provide** | A migration guide | A migration guide, tooling, hands-on help, and escalation |

**Default to advisory.** Compulsory deprecation spends organizational credit and imposes unplanned work on other teams. Use it when the cost of keeping the old path genuinely justifies that, and when you do, you owe the consumers real migration support, not just a deadline.

## Step 4: Make the deprecation visible where the work happens

A wiki page nobody reads is not an announcement. Put the signal in the path of the person who has to act:

- **In code:** `@Deprecated`, `[deprecated = true]`, `Deprecated` and `Sunset` HTTP headers, a `deprecated` field in the response envelope.
- **At runtime:** a warning log naming the caller and the replacement, sampled so it doesn't flood. Include a link to the migration guide in the message itself.
- **In CI:** a lint rule that fails new usage. **Stopping the bleeding matters more than migrating the existing callers**: a deprecation where new usage keeps appearing never converges.
- **Directly to owners:** identify the teams from your telemetry and tell them, with their specific call sites named. Broadcast announcements get ignored; "your service `foo` calls this 40k times a day, here's the change" does not.

Every notice states the same four things: what is deprecated, what replaces it, how to migrate, and what the removal condition is.

## Step 5: Do the migration for them where you can

The teams you're asking to migrate have their own roadmaps, and your deprecation is not on it. Reduce their cost to as close to zero as you can:

- **Ship a codemod or script** if the change is mechanical. Then open the PRs against their repos yourself.
- **Provide a shim:** the old interface implemented in terms of the new one, so consumers migrate at their own pace while you delete the old implementation. This decouples *your* cleanup from *their* schedule and is often what makes a stalled deprecation finish.
- **Proxy or dual-write** for data and service moves, so consumers don't have to cut over at a single moment.

## Step 6: Remove it, in stages

Never delete the code as the first destructive act. Each stage is reversible in seconds; deletion is not.

1. **Verify usage is zero** on your telemetry, across a full business cycle.
2. **Dark-launch the removal**, return an error, or stop serving, behind a flag, for a short window. Watch for screaming. This catches the caller your instrumentation missed, at a cost of one flag flip to undo.
3. **Turn it off** but leave the code in place, still revertible.
4. **Delete the code**, after the off period has held.
5. **Drop the data** last, with a verified restorable backup, and only after everything above has held for a good while.

Data deletion is the one-way door. Everything before it can be undone in minutes; this cannot. Treat it as a separate decision, made later than feels necessary.

## Common rationalizations

| "..." | Reality |
|---|---|
| "Nobody uses this" | Instrument it and find out. This assumption is wrong often enough to be the main risk in the whole workflow |
| "We announced it, it's their problem now" | Your announcement isn't on their roadmap. If you want it migrated, help migrate it |
| "We'll delete it after the deadline" | Deadline passing is not the gate. Zero usage is |
| "Leaving it costs nothing" | It costs patching, on-call surface, and every future engineer's attention. Cheap ≠ free |
| "Let's just remove it and see who complains" | Fine for an internal dev tool. Not for anything a customer or a payment path touches |
| "We'll keep both until the new one is proven" | Only with a written end date and an owner. Otherwise you now maintain two systems permanently |
| "The old one still works fine" | Then it isn't a deprecation candidate. Say so and stop, rather than half-deprecating it |

## Red flags

- A deprecation announced with no usage telemetry on the deprecated path
- No lint rule or gate stopping *new* usage from appearing
- A removal date with no named owner and no migration tooling
- Code deleted and data dropped in the same change
- A shim or compatibility layer with no removal plan. You've added a system, not removed one
- "Deprecated" annotations older than a year with usage still non-zero and nobody assigned
- The replacement isn't in production yet
