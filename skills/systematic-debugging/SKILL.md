---
name: systematic-debugging
description: >-
  Find the actual root cause of a bug instead of guessing at fixes: reproduce, isolate by
  bisection, prove the mechanism, then fix and verify. Use when a test fails, a bug is
  reported, behavior is unexplained, something works locally but not in CI, a bug is
  intermittent or flaky, or when two or three attempted fixes have already failed.
---

# Systematic Debugging

Debugging fails in a predictable way: you form a guess, change something, see if it helps, and repeat. It sometimes works, and when it does you've learned nothing and possibly broken something else. When it doesn't, you've accumulated a pile of speculative edits on top of the original bug.

The discipline is simple: **do not change any code until you can explain the mechanism.** Four phases, in order. Do not skip ahead, a fix applied before Phase 3 is a guess.

Not for: a production outage on the clock (use `incident-response`, mitigate first, come back here for the root cause).

## Phase 1: Reproduce

You cannot fix what you cannot observe, and you cannot verify a fix for a bug you cannot trigger.

- **Get a deterministic reproduction.** Smallest input, fewest steps, fastest loop. A 3-second reproduction lets you test twenty hypotheses; a 20-minute one lets you test two, so you'll start guessing again.
- **Read the actual error.** The full message, the full stack trace, the innermost cause, not the summary, not the top frame, not the part that matches what you already suspect. A surprising fraction of bugs are solved here and nowhere else.
- **Write down what you observe** versus what you expected, precisely. "It's broken" is not an observation. "Returns 404 for user 8813 but 200 for user 8814, both of which exist" is.
- **If it's intermittent, find the variable.** Time, ordering, concurrency, a shared fixture, machine, timezone, locale, cache state, leftover data. Run it 100 times and record the failure rate. That number is data. Intermittent means there is a hidden input; your job in Phase 2 is to name it.
- **If you cannot reproduce it,** that is the problem to solve first. Add instrumentation to production or CI until you can. Do not attempt a fix for a bug you have never seen. You'll have no way to know if it worked.

## Phase 2: Isolate

Cut the search space in half, repeatedly, using evidence instead of intuition. This is mechanical, and that's the point.

- **Bisect in time:** `git bisect` against the reproduction. If it worked before and doesn't now, this finds the commit directly and is almost always faster than reading code. Use `git bisect run <script>` to automate it.
- **Bisect in space:** which layer? Log or breakpoint at the boundaries (handler → service → repository → DB) and find the first place the value is wrong. The bug lives between the last correct observation and the first incorrect one.
- **Bisect in configuration:** differences between the working and failing environment: version, env var, feature flag, data, dependency version, OS, locale.
- **Change one thing at a time.** Two simultaneous changes make the result uninterpretable. Revert each experiment before the next.
- **Keep a log** of hypothesis → experiment → result. Debugging sessions lose their thread after about twenty minutes, and without notes you will re-test things you already ruled out.

**The bug is usually not where you think.** Verify assumptions rather than reasoning from them: is this code even running? Is this the deployed version? Is the config what you believe it is? Is the input what you think it is? Print it. Bugs hide precisely in the places you're confident about, because that's where you don't look.

## Phase 3: Prove the mechanism

This is the phase people skip, and skipping it is what turns a fix into a regression.

- **State the causal chain end to end:** this input → this branch → this state → this observed failure. Every step, no hand-waving. If any link is "and somehow", you're not done.
- **Confirm the chain with evidence:** a log line, a debugger, a failing assertion at the intermediate step. Not by reading the code and finding it plausible; code you've read and found plausible is how the bug got in.
- **Predict something new.** A correct model predicts behavior you haven't observed yet: "if this is the cause, then input X should also fail, and setting Y should stop it." Test the prediction. If it doesn't hold, the model is wrong, go back to Phase 2. This is the single strongest check available, and it costs a minute.
- **Ask why the guard didn't catch it.** Why did no test, type, or validation stop this? The answer often reveals a whole class of the same bug, and is more valuable than the individual fix.

**Do not stop at the first plausible cause.** A `nil` dereference means something was `nil` that shouldn't be; the fix is not a nil check, it's finding out why it was `nil`. Keep asking "and why did *that* happen" until you reach something you can defend as the actual root, usually a wrong assumption, a missing constraint, or an unhandled interleaving, not a missing line.

## Phase 4: Fix and verify

- **Write the failing test first**, at the level that actually exercises the bug. It must fail for the right reason before the fix and pass after. A test written after the fix is a test you've never seen fail. It proves nothing.
- **Fix the root cause, not the symptom.** Symptom fixes: catching an exception thrown by the real bug, adding a retry around a race, special-casing the one input that fails, adding a sleep. Each of these leaves the bug in place and makes the next occurrence harder to find.
- **Revert everything you changed while investigating.** Debug logging, commented-out code, speculative edits from earlier hypotheses. The final diff should contain the fix and the test, nothing else.
- **Verify by the original reproduction**, not by reasoning. For an intermittent bug, run it as many times as it took to fail before, and compare against the failure rate you recorded in Phase 1.
- **Check for siblings.** Grep for the same pattern elsewhere. Bugs of a kind rarely occur once.

## Anti-patterns

| Pattern | Why it fails |
|---|---|
| Changing code to see what happens | Randomizes the system; you lose the ability to interpret any result |
| "It works now" after several changes | You don't know which change did it, or whether it's actually fixed |
| Adding a retry or sleep around a race | Hides it until load changes, then it returns at the worst time |
| Catching the exception the bug throws | Converts a loud failure into silent corruption |
| Blaming the framework, the compiler, or the database | Occasionally right, overwhelmingly not. Exhaust your own code first |
| Reading code hoping to spot it | Fine for 5 minutes; after that, get evidence instead |
| Fixing the test instead of the code | Only correct if you've proven the test was wrong, prove it, don't assume it |

## Common rationalizations

| "..." | Reality |
|---|---|
| "I'm pretty sure it's the cache" | Then proving it costs one log line. Confidence without evidence is how you spend an afternoon on the wrong subsystem |
| "Let me just try this one thing" | That's the guess-and-patch loop restarting. One experiment is fine, an untracked sequence of them is not |
| "It's flaky, just retry it" | Flaky means there's a hidden input you haven't named. The retry ships the bug to production |
| "Reproducing it would take too long" | Longer than the three days you'll spend fixing it blind, twice |
| "The fix works, I don't need to know why" | Then you don't know what else it changed, or whether it fixed the bug or moved it |
| "It must be a framework bug" | Occasionally true, overwhelmingly not. Exhaust your own code first, and if it is the framework, you'll need this evidence to report it anyway |
| "Adding the null check is the fix" | It's the symptom. Something was null that shouldn't be; that's the bug |
| "I'll write the test after" | A test written after the fix has never failed, so it proves nothing about the bug |

## Red flags

- More than two speculative edits in the working tree with no hypothesis log
- A fix whose mechanism you cannot state in one sentence
- "It works now" following several simultaneous changes
- A `sleep`, retry, or broadened `catch` introduced near the failure
- The test was changed to match the behavior, without proving the test was wrong
- Debug logging left in the final diff
- An intermittent bug declared fixed after one passing run

## Output

Report: the reproduction, the causal chain with the evidence for each link, the root cause, the fix, and how it was verified. State explicitly why the fix addresses the cause and not the symptom.

If you could not prove the mechanism, say so and say what evidence you'd need. A fix shipped with "this seems to make it go away" should be labeled as exactly that, so the next person knows the bug is still open.
