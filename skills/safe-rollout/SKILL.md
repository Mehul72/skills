---
name: safe-rollout
description: Plan and execute a production rollout so a bad change is caught early and reversed cheaply: feature flags, shadow traffic, canary and staged percentages, advance/hold/rollback thresholds, and a written rollback plan. Use when deploying a risky change, planning a launch or staged rollout, setting up a feature flag, or when asked for a rollback or cutover plan.
---

# Safe Rollout

The question is not "does this work?", it's **"when this turns out to be wrong, how quickly and cheaply do we undo it?"** Design the rollout around that, and the launch stops being an event you dread.

Not for: an incident already in progress (use `incident-response`), or the schema change itself (use `migration-safety`, deploy sequencing is covered there, and every rollout touching the database depends on it).

## Step 1: Rate the risk, pick the mechanism

Not everything needs a canary. Match the machinery to the blast radius:

| Risk | Examples | Mechanism |
|---|---|---|
| **Low** | Internal endpoint, additive change behind existing tests | Deploy, watch dashboards |
| **Medium** | Changed behavior on a live path, new dependency | Feature flag + staged percentage |
| **High** | Write path, money, auth, data model, migration | Flag + shadow traffic + canary + explicit gates |
| **One-way** | Data deletion, external notification, irreversible migration | Extra approval, dry-run first, backup verified restorable |

**Identify one-way doors explicitly.** Anything you cannot undo, a sent email, a deleted row, a charged card, a published event, is not covered by a rollback, and needs to be gated before it happens rather than reversed after.

## Step 2: Decouple deploy from release

**Deploying code and turning on behavior should be separate actions.** A change that ships dark and activates by flag can be turned off in seconds, without a build, a deploy pipeline, or a rollback. That difference, seconds versus twenty minutes, is usually the difference between a blip and an incident.

Flag discipline:
- **Default off.** The flag's absence must produce the old behavior, so a config-service failure degrades to the known-good path.
- **Check it in one place**, not scattered across the codebase. Scattered checks are how half a request executes new logic and half executes old.
- **Kill switch separate from rollout percentage.** You want "off for everyone now" as a distinct control from "currently at 25%".
- **Flags are temporary.** Every flag needs an owner and a removal date. A codebase full of stale flags has an untested exponential number of code paths, and nobody knows which combination is running.

## Step 3: Test with production traffic before serving it

For high-risk changes, get real-traffic evidence before any user depends on the result:

- **Shadow / mirror traffic:** send a copy of live requests to the new path, discard the response. Catches panics, latency, and load effects with zero user impact. Make sure the shadow path cannot write, send, or charge.
- **Dual-run with comparison:** run old and new, serve the old, log the diffs. The best tool available for a rewrite or a refactor of business logic, because it tells you exactly which inputs disagree.
- **Dark launch:** deploy and exercise the code path internally before exposing it.

## Step 4: Stage the rollout

```
1. Staging          → full test suite, smoke test critical paths
2. Prod, flag OFF   → verify the deploy itself is healthy
3. Internal users   → dogfood; one business cycle
4. Canary 1-5%      → compare against baseline; hold the window
5. 25% → 50%        → same gates at each step
6. 100%             → watch a full week, including a weekend and any batch job
7. Remove the flag  → and the old code path
```

Hold at each step long enough to cover the slow failure modes, a memory leak, a cache filling, a connection leak, a nightly job, not just the first few minutes. Most rollouts fail fast; the expensive ones fail on day three.

**Compare canary against a concurrent baseline**, not against yesterday. Traffic differs by hour, day, and region; "errors are up 3%" means nothing without knowing what the old path is doing at the same moment.

**Route canary traffic consistently:** sticky by user or session. Flapping a user between old and new mid-session produces bugs that exist in neither version.

## Step 5: Set the gates before you start

Write these down *before* the rollout, not while looking at a graph and rationalizing. Baseline is the concurrent control group.

| Signal | Advance | Hold and investigate | Roll back |
|---|---|---|---|
| Error rate (5xx) | Within 10% of baseline | 10-100% above | > 2x baseline |
| p99 latency | Within 20% of baseline | 20-50% above | > 50% above |
| New error types | None | Any, at low volume | Any touching data integrity |
| Dependency load | Flat | Elevated but stable | Downstream shedding or throttling |
| Queue depth / consumer lag | Flat | Rising slowly | Rising without bound |
| Business metric | Neutral or better | Down < 2% | Down > 5% |

**Roll back immediately, without debate**, on: data corruption, incorrect authorization decisions, money moving wrongly, or a security issue. These do not get a "let's watch it a bit longer".

**Nominate who decides** and make sure they're available for the window. A rollout with no named decision-maker drifts forward by default, which is exactly the wrong bias.

## Step 6: Write the rollback plan before deploying

If it isn't written down before the deploy, it will be improvised at the worst possible moment.

```markdown
## Rollback plan: <change>
**Trigger:**      error rate > 2x baseline for 5m, OR any data-integrity report
**Action:**       disable flag `checkout_v2` in <config system>   (~10s)
**Fallback:**     redeploy <previous SHA>                         (~12m)
**Data:**         v2 writes to new column only; old path ignores it, no cleanup needed
**Irreversible:** none
**Verify:**       error rate returns to baseline; run <smoke check>
**Owner:**        @name, reachable until 22:00
```

Then answer the parts people skip:

- **Is the rollback actually tested?** An untested rollback is a plan, not a capability. Exercise it in staging.
- **What about data written by the new path?** If the new code wrote rows the old code cannot read, rolling back the code does not roll back the data. This is the most common way a "safe" rollback fails.
- **Is roll-forward faster?** Sometimes it is, but only when the fix is understood. "Roll forward" chosen because rolling back feels like an admission is how a 10-minute incident becomes two hours.
- **Do downstream consumers need to roll back too?** If they've started reading a new field, your rollback breaks them.

## Step 7: Verify, then clean up

**Verify against user-facing behavior**, not the absence of alerts. Absence of alerts frequently means the alert is missing.

- [ ] The feature works in production, checked directly, not inferred from a green deploy
- [ ] Error rate, latency, and the relevant business metric are at baseline
- [ ] Logs show the new path executing (and the old one no longer executing at 100%)
- [ ] Dependencies and queues absorbed the change without elevated load
- [ ] The rollback was exercised at least once somewhere
- [ ] Flag removed and old code path deleted once fully rolled out

## Common rationalizations

| "..." | Reality |
|---|---|
| "It's a tiny change" | Blast radius, not diff size, determines risk. One-line config changes cause outages routinely |
| "It works in staging" | Staging has different data volume, traffic shape, and dependency behavior. Staging catches bugs; production finds the ones that matter |
| "We'll monitor it after we ship" | Monitoring added after the fact isn't there during the window when it's needed |
| "Rolling back looks bad" | An outage looks worse. Rollback is the cheap option and should be boring |
| "We can skip the canary, we're behind schedule" | The canary is 30 minutes. The incident is a day, plus the postmortem |
| "The flag adds complexity" | It does, for a few days. Removal is scheduled work; an un-revertable deploy is unbounded risk |
| "Nobody uses this endpoint" | Verify it. Traffic logs, not intuition |

## Red flags

- No way to disable the change without a redeploy
- A rollback plan that is "revert the commit" with no thought given to data written in the meantime
- Canary compared against yesterday instead of a concurrent baseline
- Rollout advancing on "looks fine" rather than the thresholds written down beforehand
- Schema migration and application change in the same irreversible step
- A flag with no owner and no removal date
- The one-way doors were never enumerated
- Launching Friday afternoon, or into a period when nobody is around to watch it
