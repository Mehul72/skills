---
name: orchestrator
description: >-
  Route a request to the right skills in this library and sequence them. Reads the request,
  names which skills apply, loads them, and orders the work. Use at the start of any non
  trivial task, when a request spans several areas, when unsure which skill fits, or when
  asked which skills apply.
---

# Orchestrator

Picks the skills for a request and puts them in order. Runs before the work, not after.

Note on activation: a skill loads when its description matches the request, so this file alone does not fire on every prompt. The always on layer is `AGENTS.md` at the repo root, which carries the routing table and loads every session. This skill is the full version that file points at.

## Step 1: Classify

Read the request and answer three questions.

**What kind of work is it?** Match against the table in Step 2. A request often spans several rows.

**What is the blast radius?** Local change, or something touching live traffic, data, or a contract other people depend on. Higher radius pulls in more skills and raises the bar for calling it done.

**What is not stated?** The gap between what was asked and what shipping it actually requires. A request to "add an endpoint" implies auth, validation, error handling, tests, and observability. Nobody lists those. Skipping them because they were unstated is the main failure this library exists to prevent.

## Step 2: Select

| Request looks like | Load |
|---|---|
| Decide between approaches, stress test a plan | `grilling`, then `adr` for the record |
| Design a feature, write a tech design | `backend-design-doc` |
| Sequence multi step work, or work longer than one sitting | `implementation-plan` |
| Record why a decision was made | `adr` |
| Write or fix tests | `unit-test-gen` |
| Add logs, metrics, traces, alerts | `observability` |
| Change a schema, add a column or index, backfill | `migration-safety` |
| Change an API, edit a `.proto` or `.thrift` | `api-change-review` |
| Add an outbound call, set timeouts or retries | `resilience-review` |
| Deploy something risky, plan a rollout or rollback | `safe-rollout` |
| Remove an endpoint, service, table, or feature | `deprecation` |
| Production is broken right now | `incident-response` |
| Find why something is wrong | `systematic-debugging` |
| A query or endpoint is slow | `sql-performance` |
| A page is slow, Core Web Vitals | `web-performance` |
| UI calling an API, loading states, caching | `frontend-data-fetching` |
| React components | `react-review` |
| Keyboard, screen reader, WCAG | `accessibility` |
| Handling user input, auth, secrets, config | `security-hardening` |
| Audit an existing repo, sweep for secrets, threat model | `security-audit` |
| Write or fix a README, runbook, or API docs | `documentation` |
| Naming, comments, code that is hard to follow | `readable-code` |
| Review a diff, or decide whether it is ready | `code-quality` |
| Clean up working code | `code-simplification` |
| Commit, write a PR description, respond to review | `git-workflow` |
| Build pipeline, required checks, flaky tests, red main | `ci-cd` |
| Any output the user reads | `response-style` (always) |
| Summarise the chat for a new agent window | `handoff` |

**Always active regardless of task:** `response-style` for how output is written, and the production bar in `code-quality` before reporting anything complete.

## Step 3: Sequence

Order matters. Some skills gate others.

**Writing something new**
```
grilling (if the approach is unsettled)
  → backend-design-doc or adr (if worth recording)
  → implementation-plan  (if it outlives one sitting; write the file before the first edit)
  → write the code       (readable-code applies while writing, not after)
  → security-hardening   (input, auth, secrets)
  → unit-test-gen        (tests, run them)
  → observability        (can we see it working)
  → code-quality         (the bar, before saying done)
  → documentation        (only what the change made wrong)
  → git-workflow         (commits, PR, review, merge)
```

**Changing something already live**
```
api-change-review  (contract compatible)
migration-safety   (schema safe, deploy order)
resilience-review  (new calls bounded)
  → safe-rollout   (how it goes out and comes back)
```

**Something is broken**
```
production down?  → incident-response  (mitigate first, always)
                       ↓ once stable
                    systematic-debugging (prove the mechanism)
                       ↓
                    code-quality (fix meets the bar, regression test exists)
```

**Something is slow**
```
which layer?  query → sql-performance
              page  → web-performance
              calls out → resilience-review
```

Rules for sequencing:

- **Mitigation before diagnosis**, always, when production is affected.
- **Security and tests before "done"**, never after.
- **Contract and schema review before the rollout plan**, because they change the deploy order.
- **Simplification after it works**, never during.
- **The plan file before the first edit**, not after the work has already sprawled.
- **CI green before merge**, and green because the checks ran, not because they were skipped.

## Step 4: Announce

Say which skills you are applying and why, in one line, before starting. The user can then redirect you before you spend the work.

```
Using migration-safety (adding a column to a live table) and
safe-rollout (needs a flag, the backfill is not reversible).
```

Keep it to one or two lines. If only one skill applies, one clause is enough. If none applies, say so and proceed normally rather than forcing a fit.

## Step 5: Check before reporting

Before saying anything is complete, confirm:

- Every selected skill was actually applied, not just named.
- The production bar in `code-quality` is met, or you have said which line is not met and why.
- The output follows `response-style`.
- Claims match what you verified. "Tests pass" only if you ran them and read the output.

## Escalation triggers

Pull in a skill that was not in the original plan when any of these appear mid task.

| You notice | Pull in |
|---|---|
| The change touches a `.sql`, migration dir, or schema file | `migration-safety` |
| The change touches a `.proto`, `.thrift`, or a public route | `api-change-review` |
| A new `http`, `rpc`, or client call appears | `resilience-review` |
| User input reaches a query, a shell, or a template | `security-hardening` |
| A credential, key, or token appears in a diff | `security-hardening`, and stop |
| A secret is found in git history, not just the diff | `security-audit`, sweep and rotate |
| A renamed flag, env var, or endpoint is documented somewhere | `documentation` |
| An error path is being written | `code-quality`, error handling section |
| The diff is much larger than the problem | `code-simplification` |
| A workflow or pipeline file changes, or CI fails on a re-run | `ci-cd` |
| The work spans more files or sessions than you can hold | `implementation-plan` |
| A commit is about to be made, or a PR description is asked for | `git-workflow` |
| You cannot explain why a fix works | `systematic-debugging` |

## When no skill applies

Most requests do not need one. A question, a small edit, a lookup. Do not force a skill onto a task that does not need it, and do not announce routing for a one line answer. Overhead that exceeds the task is its own failure.

The always on parts still apply: write the output per `response-style`, and do not claim more confidence than you have.
