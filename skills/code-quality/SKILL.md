---
name: code-quality
description: >-
  Hold code to a production ready bar before calling it done, and review a diff against
  correctness, error handling, tests, security, and operability. Use before saying work is
  complete, when reviewing a diff or PR, when a change touches error paths or concurrency, or
  when asked whether code is ready to ship.
---

# Code Quality

"It runs" is not the bar. Production ready means it behaves correctly when the input is wrong, the dependency is down, two requests arrive at once, and the person reading it in six months is not you.

Generated code is usually correct on the path that was described and thin everywhere else. So the review weight goes on what was not described: the empty case, the failure case, the concurrent case.

Not for: security specifically, which is `security-hardening`. Not for reducing complexity that already works, which is `code-simplification`. Not for finding the cause of a known bug, which is `systematic-debugging`.

## The bar

Do not report work as complete until every line is true. If one is not, say which and why.

- [ ] It does what was asked, including the parts not spelled out
- [ ] Every error path is handled, or explicitly and visibly propagated
- [ ] Edge cases covered: empty, null, zero, one, maximum, duplicate, out of order, concurrent
- [ ] Tests exist for the new behavior and for the failure modes, and they have actually been run
- [ ] It builds clean with no new warnings, and the linter and type checker pass
- [ ] No debug output, commented out code, or leftover scaffolding
- [ ] Names say what things are; the non obvious decisions carry a short comment saying why
- [ ] Failures are diagnosable in production from logs, metrics, or a trace
- [ ] Nothing hardcoded that belongs in config, and no secret in source
- [ ] Runs safely if the same request arrives twice

**Say what you actually verified.** "Tests pass" means you ran them and read the output. If you did not run them, say that instead. An unverified claim of completion is worse than no claim, because it stops the reader from checking.

## Review order

Review by decreasing cost of being wrong. Do not open with naming.

### 1. Correctness

- Does the logic match the stated intent? Read the code against the requirement, not against itself.
- Off by one at every boundary. Loop bounds, slice indices, ranges, pagination.
- Null, empty, and zero. An empty list and a missing list often need different behavior.
- Are the types honest? A string holding an enum, a float holding money, a nullable that is never checked.
- Integer overflow, truncation, and precision loss on conversion.
- Timezones. A naive datetime crossing a boundary is a bug that appears twice a year.

### 2. Error handling

The largest gap in generated code, so give it real attention.

- Every call that can fail is handled. Nothing swallowed, nothing ignored.
- Errors carry context as they propagate. `fmt.Errorf("fetching user %s: %w", id, err)` and not a bare rethrow.
- Failures are atomic. If step three fails, steps one and two do not leave the system half updated. Transaction, compensation, or an explicit note saying why partial state is acceptable.
- Resources released on every path including the error path. Defer, context manager, try with resources.
- No error text that leaks internals to a caller.
- Timeouts on every external call. See `resilience-review`.

### 3. Concurrency

Only if the code is concurrent, but check hard when it is.

- Shared mutable state guarded. Every access, not most of them.
- Check then act is a race. `if !exists { create() }` needs a lock or a unique constraint.
- Lock ordering consistent everywhere, or it deadlocks under load.
- Nothing spawned without a way to stop it or wait for it.
- Cancellation and context propagated.

### 4. Tests

- Do the tests test behavior, or do they restate the implementation? A test that mocks everything and asserts the mocks were called proves nothing.
- Are the failure paths tested, or only the happy path?
- Would the test fail if the code were wrong? If you cannot answer yes, it is not a test.
- No sleeps, no ordering dependence between tests, no shared mutable fixtures.
- See `unit-test-gen` for generating them.

### 5. Interfaces and data

- Public signatures: right level of abstraction, no leaked internals, hard to call incorrectly.
- Breaking change to a contract? Route to `api-change-review`.
- Schema change? Route to `migration-safety`.
- New query on a hot path? Route to `sql-performance`.

### 6. Operability

- Can you tell from production output that this is working, and why it stopped? See `observability`.
- Is the failure mode acceptable when a dependency is slow rather than down?
- Is it revertible? See `safe-rollout`.

### 7. Clarity

Last in review order, because a clarity problem is cheaper to fix than a correctness one. That is about ordering, not importance: unreadable code is where the next correctness bug comes from.

- Names describe intent. Comments explain why, never what.
- Nesting shallow, functions single purpose.
- Error messages say what happened and what to do.
- Consistent with the surrounding code rather than with your preference.

Full standard, and the naming and comment rules in detail: `readable-code`. Apply it while writing, not only at review.

## Reporting

Separate what blocks from what does not. Burying a data loss bug in a list of naming suggestions is a review failure.

- **Blocking**: wrong behavior, unhandled error path, security issue, data loss risk, breaking change.
- **Should fix**: missing test, weak error message, a real but low probability edge case.
- **Optional**: naming, structure, style preference.

For each finding give the location, what breaks, and the input or sequence that triggers it. A finding without a concrete failure scenario is an opinion, so label it as one.

If the diff is clean, say so plainly. Manufacturing findings to look thorough trains people to ignore the review.

## Common rationalizations

| Claim | Reality |
|---|---|
| "It works, I ran it" | You ran the happy path. The bar is what happens when input is wrong or a dependency is down |
| "Tests pass" | Did you run them, and read the output? Say which |
| "I will add error handling later" | Later is after the silent failure reaches production |
| "The edge case will not happen" | Empty lists, duplicate submits, and concurrent requests all happen on day one |
| "It matches the existing pattern" | Worth checking whether the existing pattern is correct |
| "Adding a test would take too long" | Less time than diagnosing the regression it would have caught |
| "The reviewer will catch it" | The reviewer is reading a diff without the context you have right now |

## Red flags

- A completion claim with no statement of what was actually run
- An error path that logs and continues
- A new external call with no timeout
- A test that asserts a mock was called and nothing else
- A `TODO` or `FIXME` added in the same diff that claims to be done
- Commented out code
- A magic number with no name
- A function that cannot be described in one sentence
- Any nesting deeper than three levels in new code

