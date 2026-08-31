---
name: incident-response
description: Drive a production incident: triage severity, mitigate first, then diagnose, communicate, and write a blameless postmortem with real action items. Use during or after an outage, elevated error rates, a latency regression, a bad deploy, or when on-call and paged; also use for writing the postmortem/RCA afterwards.
---

# Incident Response

Two rules govern everything here:

1. **Mitigate before you diagnose.** Stopping the bleeding and understanding the cause are separate jobs. Doing them in the wrong order extends the outage, and you can always root-cause a stable system afterward, but you can't debug your way out of an outage on a clock.
2. **The first question is always "what changed?"** Systems that ran fine for months rarely break spontaneously. Deploys, config and feature-flag flips, migrations, cert expiry, traffic shifts, and dependency releases account for the large majority of incidents.

Not for: a change you are about to ship (use `safe-rollout`). Once stable, root-cause with `systematic-debugging`.

## Phase 1: Triage (first 5 minutes)

**Assign severity** and say it out loud, so everyone is calibrated on the response:

| Sev | Meaning | Response |
|---|---|---|
| **SEV-1** | Total outage, data loss or corruption, security breach | Page everyone, incident channel, exec comms |
| **SEV-2** | Major feature broken or severe degradation for many users | Page the owning team, incident channel |
| **SEV-3** | Partial or degraded functionality, workaround exists | Business hours, tracked |
| **SEV-4** | Minor, cosmetic, or internal-only | Ticket |

**Establish roles** for SEV-1/2, one **incident commander** who coordinates and decides but does not debug, one comms owner, one or more responders. The most common failure at this stage is five people independently investigating the same dashboard while nobody talks to customers or makes a call.

**Scope it before you dig in:**
- What's the user-visible symptom? (Not the alert, the symptom.)
- What fraction of traffic, which regions, which tenants?
- When exactly did it start? Pin this down. It's the key that unlocks "what changed".
- Is it getting worse, stable, or recovering?
- Is data being lost or corrupted right now? If yes, that changes the calculus: stopping writes may beat staying up.

## Phase 2: Mitigate

Get back to a known-good state by the fastest safe route. **You do not need to know the cause to mitigate.**

Ordered by how quickly they usually work:

1. **Roll back the recent deploy.** If the timeline correlates with a release, roll back first and investigate after. Do this even if the connection seems unlikely, a rollback that doesn't help costs you five minutes and eliminates a variable.
2. **Flip the feature flag off.** Fastest available lever when the change was flagged.
3. **Fail over**, to another region, replica, or provider.
4. **Shed load**, rate-limit or disable the expensive endpoint to keep the rest of the system alive. A degraded site beats a dead one.
5. **Scale up**, real if the cause is genuine capacity, useless if there's a lock or a bad query, and actively harmful if more instances mean more load on a struggling dependency.
6. **Restart**, sometimes correct (leaked resource, wedged pool), but it destroys the evidence. **Capture state first** (heap dump, goroutine/thread dump, connection counts, current queries), then restart.

**Announce every action in the channel before you take it**, with the expected effect. Two people mitigating simultaneously in different directions is a real and common way to make an incident worse.

**Verify the mitigation actually worked** by the user-facing metric, not by the absence of alerts. Then keep watching, monitor for at least 30 minutes before declaring it resolved. Bugs that recur after apparent recovery are common, and the second occurrence is much worse if everyone has stood down.

## Phase 3: Diagnose

Once it's stable, find out why. `references/triage-queries.md` has the diagnostic commands, deploy correlation, resource state, Postgres/MySQL locks and slow queries, Kubernetes, and connection pools.

**Build a timeline first.** Every deploy, config change, alert, metric inflection, and action taken, with timestamps. Do this even for small incidents, the timeline is what makes the cause obvious, and it's also most of the postmortem.

**Correlate against changes:**
```bash
git log --oneline --since="4 hours ago"
```
Plus deploy history, feature-flag audit log, infra changes, and dependency incident pages.

**Then work the four usual shapes:**
- **Saturation:** CPU, memory, disk, file descriptors, connection pool, thread pool, queue depth. Check saturation before latency; saturation causes latency.
- **A dependency:** is a downstream service slow or erroring? Check its status page. Are your timeouts and retries amplifying its problem?
- **Data:** a query that got slow because a table crossed a size threshold, a missing index, a lock, a hot partition, a single tenant sending 100x normal volume.
- **The change:** the deploy, migration, or flag flip from your timeline.

From here, hand off to the `systematic-debugging` skill for the root cause. Same discipline applies: prove the mechanism, don't guess.

## Phase 4: Communicate

Update on a **fixed cadence**, every 30 minutes for SEV-1, even when there's nothing new. "Still investigating, no new information, next update at 14:30" is a valuable message; silence makes people interrupt the responders to ask.

Each update: what's broken (in user terms), who's affected, what you're doing, what the workaround is, when the next update lands. Never a root cause you haven't confirmed, a retracted cause costs more trust than saying "unknown".

Say "we don't know yet" when you don't know yet.

## Phase 5: Postmortem

Write it within a few days, while memory is fresh. Structure:

1. **Summary**, what happened, impact, duration, in five sentences.
2. **Impact**, quantified. Requests failed, users affected, revenue, SLO budget burned. Numbers, not "some users".
3. **Timeline**, detection through resolution, timestamped. Include when you detected it versus when it *started*; that gap is usually its own finding.
4. **Root cause**, the causal chain, all the way down. Not "the service crashed", why it crashed, and why nothing prevented it.
5. **What went well / what went badly**, including the response itself, not just the failure.
6. **Action items**, each with an owner and a due date, tracked in the normal backlog.

**Blameless means focusing on the system, not the person.** Not "Alice deployed a bad config" but "a config change with no validation could reach production in one step". If a person could cause this outage, the system permitted it. That's the finding. Blameless postmortems aren't politeness; they're the only way people report what actually happened.

**Interrogate detection and response, not just the cause:**
- How long until we knew? Did an alert catch it, or a customer?
- Did the alert say what was wrong, or just that something was?
- Was there a runbook? Was it correct?
- What made diagnosis slow? Missing instrumentation is an action item.

**Action items must be specific and owned.** "Improve monitoring" is not an action item. "Add an alert on checkout p99 > 800ms over 5m, owner @x, due Friday" is. Cap them at what will genuinely get done, five real items beat twenty that rot. And weight them toward prevention and detection over "be more careful next time", which is not a mechanism.

## Output

During: a running timeline, and clear statements of what you're about to do before you do it.

After: the postmortem in the structure above, with quantified impact and owned action items.
