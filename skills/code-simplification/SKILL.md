---
name: code-simplification
description: Reduce working code to its simplest correct form without changing behavior. Removes speculative abstraction, dead code, redundant state, and defensive noise, and folds duplication that has earned it. Use after a feature works but before it ships, when a file has grown hard to follow, when reviewing a diff that looks larger than the problem, or when asked to clean up, refactor, or simplify.
---

# Code Simplification

Generated code trends long. It adds abstraction for cases nobody asked about, guards against inputs that cannot occur, and keeps every intermediate variable. Each addition looks harmless. Together they produce code where the actual logic is a third of the lines.

The goal is the smallest code that is still correct and still readable. Not the fewest characters. Clever one liners are a different failure.

Rule: **behavior does not change.** If you cannot demonstrate that, it is a rewrite, not a simplification, and it needs tests and a review.

Not for: making code faster, which is `sql-performance` or `web-performance`. Not for finding bugs, which is `code-quality`. Naming, comments, and how code reads are `readable-code`; this skill removes what should not be there, that one makes what remains legible.

## Step 1: Establish the safety net

Simplification without tests is just editing.

- Confirm tests exist and pass before you touch anything. If they do not exist, write characterization tests first: capture what the code does now, correct or not.
- Work in small steps and re-run tests after each one. A large simplification that breaks something is hard to bisect.
- If you notice a bug while simplifying, stop and handle it separately. Mixing a behavior fix into a no behavior change pass hides both.

## Step 2: Delete

Deletion is the highest value operation and the first one to try.

- **Dead code.** Unreachable branches, unused functions, unused parameters, unused imports, unused fields. Let the compiler and linter find them, then check version control rather than keeping code "just in case". That is what version control is for.
- **Commented out code.** Always. It is never restored, and it rots.
- **Speculative flexibility.** A configuration option with one value, a strategy interface with one implementation, a factory that constructs one type, a hook nothing registers on. Build the general case when the second case arrives, not before.
- **Guards against impossible states.** A null check on a value that cannot be null, a type check inside a typed language, validation repeated at three layers. Validate at the boundary and then trust the type.
- **Redundant state.** Anything that can be computed from something else. A cached total, a `count` field alongside the list, a `isEmpty` flag. Two sources of truth diverge.
- **Wrapper layers that only forward.** A service that calls a repository with no logic between them is indirection with no benefit.

Before deleting anything nontrivial, check it is genuinely unused across the whole repo and not part of a public interface.

## Step 3: Flatten

- **Guard clauses over nesting.** Return early on the invalid cases and let the main path sit unindented at the bottom. This alone removes most deep nesting.
- **Invert conditions** to avoid `else` blocks. `if (!ok) return` beats a large `else`.
- **Collapse chained conditionals** into a lookup table or a map when they are just mapping value to value.
- **Extract a named function** when a block needs a comment to explain what it does. The name replaces the comment.
- Aim for a maximum of three levels of nesting in new code.

## Step 4: Fold duplication carefully

The rule is three, not two. Two similar blocks are often coincidence, and merging them creates a shared abstraction that both callers then fight against.

- Fold when the duplicated code represents the same *decision*, so it should change in both places for the same reason.
- Do not fold when the code merely looks alike. Two validators with the same shape but different rules will diverge.
- **Duplication is cheaper than the wrong abstraction.** Backing out a bad merge is far more expensive than backing out a copy.
- Watch for the tell: a shared function with a boolean parameter that switches behavior. That is two functions wearing one name.

## Step 5: Simplify the shape

- **Fewer parameters.** More than three or four suggests a missing type. A boolean parameter at a call site is unreadable, so pass an enum or split the function.
- **Return early, return one type.** A function returning a value, or null, or throwing, on three different paths is three functions.
- **Narrow scope.** Declare variables where used, not at the top. Shrink visibility to the minimum.
- **Prefer the standard library.** A hand written utility that duplicates a built in is code to maintain and a place for bugs.
- **Immutable by default.** Fewer moving parts to reason about.
- **Delete the intermediate variable** when it is used once and named after its type rather than its meaning. Keep it when the name explains something the expression does not.

## Step 6: Verify nothing changed

- Tests pass, same as before.
- The diff is genuinely smaller, or genuinely clearer. If it is neither, revert it.
- No public signature changed unless that was the point and it was reviewed.
- Read the result once as a stranger. Simplification that makes code shorter and harder to follow has failed.

## What not to do

- Do not remove error handling to shorten code. That is not simplification.
- Do not collapse code that is deliberately explicit for clarity, such as a step by step state machine.
- Do not rename widely used identifiers as part of a simplification pass. It buries the real change in noise.
- Do not chase a line count target. The measure is whether the next reader understands it faster.
- Do not simplify code you do not understand. Understand it first, or leave it.

## Common rationalizations

| Claim | Reality |
|---|---|
| "The abstraction will be useful later" | Later rarely arrives, and when it does the requirement differs from what you guessed |
| "I will leave it commented in case we need it" | Version control already does this, without the rot |
| "It is only a small extra layer" | Every layer is a hop the next reader has to follow to find the logic |
| "Both blocks look the same, merge them" | Look the same is not the same reason to change. Wait for the third |
| "Defensive checks are safer" | A check on an impossible state hides the real invariant and adds a path nobody tests |
| "More configuration makes it flexible" | Every option is a combination nobody tested |
| "Shorter is better" | Clearer is better. Sometimes that is longer |

## Red flags

- An interface with one implementation
- A config flag with one value in every environment
- A function with a boolean parameter that selects between two behaviors
- The same validation performed at three layers
- A field that duplicates something derivable
- A wrapper whose every method forwards unchanged
- Commented out code of any age
- Nesting beyond three levels
- A comment explaining what a block does rather than why
