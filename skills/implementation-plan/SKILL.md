---
name: implementation-plan
description: >-
  Turn agreed work into a written plan file with verifiable steps, then execute it one step at
  a time with the file as the source of truth. Covers step sizing, what "done" means per step,
  surviving a context reset, and amending the plan when reality disagrees with it. Use before
  starting multi step or multi file work, when a task will outlive one context window, when
  work has drifted from what was agreed, or when asked for a plan, a breakdown, or a TODO
  list.
---

# Implementation Plan

Context is the least durable place to keep a plan. It gets compacted, truncated, or replaced by a fresh window, and when that happens an unwritten plan is gone with no error message and no way to tell what was already finished. **The plan is a file in the repo, not a message in the conversation.**

That fixes the second failure too: asked for four things, an agent reliably delivers three, because nothing outside its context is tracking the fourth. A checklist that lives on disk, gets ticked as work actually lands, and is re-read before each step, closes both gaps at once.

Not for: deciding whether the approach is right, which is `grilling` and comes before this. Not for recording why a decision was made (`adr`) or specifying how the system works (`backend-design-doc`), a plan sequences work that has already been decided. Not for rescuing a session that is already out of context, which is `handoff`.

## Step 1: Decide whether it needs a plan

Planning overhead that exceeds the task is its own failure.

| The work | What it gets |
|---|---|
| One file, one obvious change | Nothing. Do it |
| A few files, one sitting, no unknowns | A short checklist in the reply |
| Multi file, or it touches live behaviour | A plan file |
| Longer than one context window, or someone else picks it up | A plan file, not optional |
| Unknowns still open | Not ready to plan. `grilling` first |

The tell that you needed a file and did not write one: you are asking the user "where were we?"

## Step 2: Do not plan around an unsettled decision

A plan whose first step is "decide whether to use a queue" is not a plan, it is a decision wearing a checkbox. Settle it first, then write steps that follow from it.

Before writing any steps, be able to state:

- **The goal in one paragraph**, in terms someone else can check.
- **The decisions already made**, and where they are recorded. Copy the conclusion into the plan so executing it does not require re-reading the ADR.
- **What is explicitly out of scope.** This is what stops scope creep mid execution, and it is the section people skip.
- **The unknowns that are still open**, and which step each one blocks.

An open question that blocks step 1 means stop and resolve it. An open question that blocks step 6 means start, and put it in the file.

## Step 3: Write the file

Put it where the repo already puts plans. If there is no convention, `docs/plans/<short-name>.md`. If the plan is throwaway and should not be committed, keep it out with `.git/info/exclude` rather than editing the shared `.gitignore`.

```markdown
# Plan: idempotent payment submission
Status: in progress
Branch: feat/payment-idempotency

## Goal
A retried payment submission with the same client key returns the original result and
charges once. Verifiable by replaying a request and seeing one row in `payments`.

## Decided already
- Key comes from the client, not generated server side (ADR 014).
- Stored in Postgres in the same transaction as the write, not Redis. Atomicity beats latency here.

## Out of scope
- The refund path. Separate change, separate plan.
- Backfilling keys for historical payments. Nobody needs it.

## Steps
- [x] 1. Add `idempotency_keys` table, migration only, nothing reads it yet
      files: migrations/0042_idempotency_keys.sql
      done when: applies and rolls back against a prod sized schema copy, lock time recorded
- [ ] 2. Write and read the key inside the existing payment transaction
      files: internal/payment/handler.go, internal/payment/store.go
      done when: a unit test proves a duplicate key returns the first response and does not re-charge
- [ ] 3. Return the original response on replay, with the agreed status code
      done when: integration test covers replay; error model checked against api-change-review
- [ ] 4. Metric `payment_idempotent_replay_total`, no alert
      done when: visible in staging with a non zero value after a manual replay

## Open questions
- Does the mobile client reuse the key on retry today? Asked, no answer yet. Blocks step 3.

## Log
- 2026-09-03 step 1 landed as abc1234. Migration took 8ms on a prod sized copy.
- 2026-09-03 step 2: the transaction was not actually shared with the store call. Fixing that first.
```

The `Log` matters more than it looks. It is where the next window (or the next person) learns what already went wrong, so the same wall does not get hit twice.

## Step 4: Size the steps

**One step is one verifiable outcome that could be committed on its own.** That single rule fixes most bad plans.

Each step states the files it expects to touch and how you will know it worked. "Done when" is a check someone else could run, not a feeling. `done when: it works` is not a step, it is a hope.

| Bad step | Why | Better |
|---|---|---|
| "Implement the backend" | Not verifiable, not committable, hides ten decisions | Split by seam: schema, then write path, then read path |
| "Write tests" | Tests are part of each step, not a step | Fold into each step's "done when" |
| "Fix everything the review found" | Unbounded, invisible progress | One step per finding worth its own commit |
| "Refactor while adding the endpoint" | Mixes behaviour change with movement, unreviewable | Two steps, refactor first, behaviour second |

Order steps so the tree is working after each one. A step that leaves the build broken until the next step lands is one step, not two.

If a plan has more than about ten steps, it is two plans, or the steps are too small to be worth tracking.

## Step 5: Execute one step at a time

- **Re-read the file before each step**, not from memory of it. That is the entire point of it being a file. Memory of a plan is exactly the thing that decays.
- **Do the step, verify it, then tick it.** A checkbox ticked because you wrote the code and it looked right is how a plan starts lying. Tick after the "done when" actually passed, and say what you ran.
- **The step boundary is where a commit goes**, when the user is committing. `git-workflow` covers shaping it, and carries the rule that you commit locally and never push. A plan step and a commit being the same unit is what makes the work revertible at the granularity you reasoned about.
- **Append to the log** when something surprises you: a wrong assumption, a dependency that behaved differently, a decision made in passing. Cheap now, expensive to reconstruct later.
- **Do not run ahead.** Finishing step 2 and drifting into step 5 because it seemed adjacent is the drift this file exists to prevent.

## Step 6: Amend the plan when reality disagrees

Plans meet the codebase and lose. That is expected, and it is not a reason to abandon the file.

When a step turns out to be wrong or impossible: **update the file first, then continue.** Say what changed and why, in the log. The plan is now still true, which is the property that makes it worth having.

What warrants going back to the user rather than editing quietly:

- The goal changed, not just the route to it.
- Something now out of scope was in scope when they agreed to it.
- The cost moved by a lot, in either direction.
- A decision recorded in "Decided already" turns out to be wrong. That is an `adr` update, not a silent edit.

Reordering steps, splitting one into two, or dropping a step made unnecessary by an earlier one, all fine, just record it.

## Step 7: Finish

The plan is done when every checkbox is ticked **and** each was verified by its own "done when", not when the steps have all been attempted.

- [ ] Every step ticked, with its check actually run
- [ ] Open questions all closed, or moved somewhere that outlives the plan
- [ ] Nothing in "out of scope" quietly landed anyway
- [ ] The production bar in `code-quality` is met for the change as a whole
- [ ] Plan file either deleted, or marked `Status: done` and left as the record

Then report against the plan, step by step, including the steps that changed shape. A summary that does not mention the two steps you dropped is a summary the user cannot trust.

## Common rationalizations

| "..." | Reality |
|---|---|
| "I'll keep the plan in my head" | Your head is a context window that gets compacted without warning |
| "Writing it down is overhead" | It is a few minutes against redoing work you cannot remember finishing |
| "The plan will just change anyway" | Then amend it. An amended plan is still a record; an unwritten one is not |
| "I'll write the plan after I explore a bit" | Fine, exploring is not planning. Write it before the first edit |
| "The steps are obvious" | Then they are cheap to write, and the fourth one still gets forgotten |
| "I ticked it, I'll verify at the end" | At the end you will verify the whole thing at once, badly, and one broken step will be invisible |
| "It's only two steps" | Then no file. This is the case where skipping it is right |

## Red flags

- The plan exists only in the conversation
- A step nobody could verify without asking you what you meant
- "Implement X" as a single step, where X is the whole feature
- Checkboxes ticked in a batch at the end
- The file has not been touched since it was written, but four steps landed
- Work in progress that appears in no step
- Open questions listed but not tied to the step they block
- The tree does not build between steps
