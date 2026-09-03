---
name: ci-cd
description: >-
  Design or review a CI/CD pipeline so a green run actually means mergeable: stage ordering
  and feedback latency, deterministic builds, required checks, a flaky test protocol, cache
  keys that cannot lie, and build once then promote the same artifact. Use when adding or
  changing a workflow file, when CI is slow, flaky, or routinely ignored, when main is red,
  when setting up required checks or a release pipeline, or on any mention of GitHub Actions,
  GitLab CI, Jenkins, or a build pipeline.
---

# CI/CD

The pipeline exists to make **"merge it" a safe default**. It fails in two directions, and they are not equally bad.

**False green:** it passes when it should have failed. Direct, and usually a gap in what runs.

**Flaky red:** it fails when it should have passed. Worse, because it teaches everyone to re-run and merge anyway, and once that habit exists every real failure is also ignored. A pipeline people route around has negative value: it costs minutes and buys nothing.

Not for: what the tests should assert (`unit-test-gen`), what happens to the artifact after it is built (`safe-rollout`), or an audit of the credentials and permissions the pipeline holds (`security-audit`, which covers this ground in depth).

## Step 1: Decide what runs when

Feedback latency is the design constraint. Past roughly ten minutes on a pull request, people context switch and stop reading the result, which converts the pipeline into a formality.

| Trigger | Runs | Budget |
|---|---|---|
| Every push to a branch | Lint, type check, unit tests, build | Minutes |
| Pull request | The above, plus integration tests and e2e on critical paths only | Under 10 minutes |
| Merge to main | Full suite, publish the artifact | Whatever it takes |
| Nightly or scheduled | Long e2e, load tests, dependency and license audit | Unbounded |
| Tag or release | Package, sign, publish, deploy gate | Unbounded |

If the PR suite does not fit the budget, cut by relevance, not by importance: move the slow whole-system tests to merge or nightly, keep everything that catches a defect the author introduced.

## Step 2: Order stages by cost of feedback

Cheap and broad first, expensive and narrow last. A pipeline that spends eight minutes on e2e before discovering a type error is wasting the only resource that matters here.

```
lint + type check + unit   (parallel, seconds)
        ↓ fail fast
build / compile
        ↓
integration tests          (parallel by package or shard)
        ↓
e2e on critical paths
        ↓
publish artifact
```

Parallelize across the axis that actually splits the time (packages, shards, matrix entries), and let independent jobs start independently rather than chaining everything to one sequential graph.

## Step 3: Make it deterministic

A pipeline that passes or fails depending on the day is not a signal. Hermetic means the same commit produces the same result on any runner, at any time.

- **Pin everything.** Tool versions, base images by digest rather than a moving tag, and third party pipeline steps by commit SHA rather than a tag someone can move.
- **Install from the lockfile**, with the command that refuses to update it (`npm ci`, not `npm install`). A pipeline that silently resolves a new transitive version tests a build nobody has.
- **No network in unit tests.** A test that reaches a live API fails when that API has a bad day, and the failure has nothing to do with the commit.
- **Fix the environment:** timezone, locale, and any random seed. Then randomize test order deliberately, so order dependence fails loudly instead of hiding until someone adds a test.
- **One entry point, shared with humans.** `make test` or a script that CI calls and developers call. When CI runs different commands than people do locally, "works on my machine" becomes unfalsifiable.

## Step 4: Say what must be green

Required checks are the contract. Without branch protection, a pipeline is advisory and will be treated that way.

- **Name the required checks explicitly.** Green means every one of them ran and passed on this commit.
- **Require the branch to be current with the base**, or CI's answer is about a state that no longer exists. This is how two individually passing PRs merge into a broken main.
- **Watch the path filter trap.** A required check skipped by a path, branch, or commit message filter stays pending and blocks the merge indefinitely. GitHub's own guidance is not to require a workflow that can be skipped; the way to keep the protection is a job that always runs and reports success when there was nothing to do.
- **Admin bypass is an incident tool, not a workflow.** If it is used weekly, the checks are wrong. Fix the checks.
- **A skipped job must not report success.** This is the most common false green there is.

## Step 5: Treat a flake as a bug

**A flaky test is a defect, in the test or in the code under test.** The race it exposes is usually real, which is exactly why blanket auto-retry is the worst option available: it deletes the evidence and ships the race.

The protocol:

1. **Measure.** Track pass rate per test. "It's flaky sometimes" is not actionable; "fails 4% of runs" is.
2. **Quarantine, do not delete or retry silently.** Move it out of the required set, with a named owner and a date. A quarantine with neither is a deletion with extra steps.
3. **Diagnose it as a real bug.** `systematic-debugging` Phase 1 covers exactly this: intermittent means there is a hidden input, usually time, ordering, shared state, or a leaked fixture.
4. **If a retry is unavoidable**, make it visible: count it, alert on it, and never let a retried pass look identical to a clean pass.

A quarantine list with no expiry becomes the place tests go to die, and the coverage it represents was real. Review it.

## Step 6: Cache without lying

A cache that lets a broken build pass is worse than no cache.

- **Key on the lockfile hash**, with a looser restore-key for partial hits. Keying on the branch name alone gives you another branch's dependencies.
- **Never cache the thing under test.** Cache dependencies and toolchains, not build output that could let a stale artifact satisfy a run.
- **Scope by branch, restore from the base.** A cache a fork can write to is a supply chain hole, not a speedup.
- **Do not cache what is cheap to recompute.** Restore time is not free, and a cache that saves twelve seconds costs more in debugging than it returns.

Test the pipeline from a cold cache periodically. A build that only works warm will fail on the day you need it most.

## Step 7: Build once, promote the same artifact

Rebuilding per environment means what you tested is not what you shipped, and the difference will surface in production where it is most expensive.

- Build one artifact, tag it with the commit SHA, and promote that exact artifact through staging to production.
- Configuration comes from the environment at run time. Baking an environment name into the build makes promotion impossible by construction.
- Keep the artifact traceable to a commit, and the deploy traceable to an artifact. Answering "what is actually running in production" should take seconds, not archaeology.

Where the artifact goes from there, gates, canary, thresholds, and rollback, is `safe-rollout`.

## Step 8: Red main stops the line

Main being broken blocks everyone, so it is not a background task.

- **Revert first, diagnose second.** Same rule as `incident-response`: restore the working state, then find out why. `git revert` is reviewable and cheap.
- **Nobody merges onto a red main.** Merging on top makes the eventual bisect worse and hides whose change was at fault.
- **Fix forward only when the fix is understood**, not because reverting feels like an admission.
- Track time to green. A team that tolerates hours of red main has stopped believing the pipeline, and every other practice here decays from there.

## Step 9: The pipeline is production

It holds every deploy credential and runs code on every push. Treat it accordingly, and load `security-audit` for the full sweep.

- **Short lived credentials over stored keys.** Federated identity (OIDC) beats a long lived cloud key in a secret store, which cannot be rotated by anyone in a hurry.
- **Default the token to read only**, and grant write per job that needs it.
- **Never expose secrets to a pull request from a fork.** A trigger that runs with repository secrets and then checks out fork code is the classic pipeline privilege escalation. GitHub says outright not to use `pull_request_target` unless necessary, and never to check out untrusted code from a workflow that has secrets.
- **Pin third party steps by full commit SHA.** A tag is mutable, so a compromise upstream is a compromise in your deploy job. A full length SHA is the only immutable reference an action has.
- **Never echo a secret**, including into a debug run. Masking is best effort, and a secret in a log is a secret to rotate.
- **Gate the deploy job** behind an environment approval when it touches production.

## Common rationalizations

| "..." | Reality |
|---|---|
| "Just re-run it, it's flaky" | You just deleted the evidence for a race that is also in production |
| "CI is slow but it's thorough" | Slow CI gets ignored or bypassed, so it is thorough about nothing |
| "It passes locally" | Then the pipeline is not hermetic, and that is the bug to fix first |
| "We'll add the tests to CI later" | A test not in the pipeline is a test that will be broken within a month |
| "Main is red but everyone knows why" | Everyone knows until the second failure hides behind the first |
| "Pinning versions is a maintenance burden" | Cheaper than an unreproducible failure you cannot bisect |
| "The cache makes it fast" | Only if a cold run still passes. Verify that, on a schedule |
| "We rebuild per environment, it's the same code" | Then it is the same artifact, so build it once and prove it |
| "Only admins bypass the checks" | Admins ship the incidents too |

## Red flags

- A required check that can be skipped and still report success
- `retries: 3` on a test suite, with no count of how often they fire
- Unpinned base images, `latest` tags, or third party steps pinned to a mutable tag
- `npm install` (or the equivalent) instead of the lockfile-respecting command
- A cache key that does not include the lockfile hash
- Secrets available to workflows triggered by forked pull requests
- A pipeline whose commands exist nowhere a developer can run them
- Main red for more than an hour with no revert
- A quarantine list with no owners and no dates
- The artifact deployed to production was built separately from the one that was tested
