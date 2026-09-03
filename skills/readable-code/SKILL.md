---
name: readable-code
description: >-
  Write code a stranger can read in one pass: names that state intent, short comments that
  explain why in plain English, shallow control flow, and error messages people can act on.
  Use when writing or reviewing any code, when naming things, when adding comments or
  docstrings, when a function is hard to follow, or when asked to make code clearer or more
  maintainable.
---

# Readable Code

Code is read far more often than it is written, usually by someone who does not have the context you have right now. That person is often you in four months.

Generated code fails readability in a specific direction. It over comments and under names. It writes `// increment the counter` above `count++`, then calls the variable `data`. It explains the obvious and omits the reason. Correct that direction: **put the effort into names and structure, and spend comments only on what the code cannot say.**

The test: can a competent engineer who has never seen this file explain what it does after one read, without asking you?

Not for: reducing complexity in code that already works, which is `code-simplification`. Not for correctness review, which is `code-quality`.

## Names

Naming is the highest leverage thing here. A good name removes the need for a comment.

**Name the intent, not the type or the mechanism.**
```
BAD   userData, resultList, tempStr, dataObj, flag, info, x2
GOOD  activeSubscribers, unpaidInvoices, normalizedEmail, retryDeadline
```

**Length scales with scope.** A loop index living for two lines can be `i`. A package level constant read across ten files needs a full name. A long name in a tiny scope is noise; a short name in a wide scope is a puzzle.

**One word per concept.** Pick `fetch` or `get` or `retrieve` and use it everywhere for the same operation. Three words for one idea makes readers hunt for a distinction that does not exist. The same rule applies to the domain: if the product calls it a "merchant", do not call it a "vendor" in code.

**Booleans read as questions.** `isActive`, `hasPermission`, `shouldRetry`, `canPublish`. Then `if (isActive)` reads as a sentence.

**Avoid negative names.** `notDisabled`, `isNotReady`, `disableValidation` all force double negation at the call site. `if (!notDisabled)` is a puzzle. Name the positive.

**Put units and types in the name when ambiguity is possible.** `timeoutMs`, `sizeBytes`, `priceCents`, `delaySeconds`, `expiresAt` versus `expiresIn`. Most time and money bugs come from a number whose unit was assumed. This costs three characters and prevents a class of bug.

**Functions are verb phrases, values are noun phrases.** `calculateTax()` returns something. `saveOrder()` does something. A function named `data()` tells you nothing.

**Avoid the empty words.** `manager`, `handler`, `helper`, `util`, `processor`, `service`, `data`, `info`, `object`, `stuff`. They fill space without narrowing meaning. `OrderValidator` beats `OrderHelper`. If you genuinely cannot name a class more specifically than `Manager`, it probably does more than one thing.

**Do not abbreviate.** `cnt`, `usr`, `calc`, `tmp`, `btn`, `req`, `resp`. Exceptions are loop indices and abbreviations universal in the domain (`id`, `url`, `http`, `db`). Everything else costs the reader a translation step to save you four keystrokes.

**Make constants searchable.** `86400` appears in six unrelated places; `SECONDS_PER_DAY` appears in one. Magic values cannot be grepped, changed safely, or understood on sight.

## Comments

**Comment why, never what.** The code already says what. If the code does not say what clearly, fix the code rather than annotating it.

```
BAD   // loop through the users and check if they are active
      for (const u of users) { if (u.active) ... }

BAD   // increment the retry counter
      retries++;

GOOD  // Stripe rejects amounts under 50 cents, so we batch small refunds
      // into a nightly job instead of issuing them immediately.
      if (amountCents < 50) { queueForBatch(refund); return; }
```

**Keep them short.** One or two lines. A comment longer than the code it describes usually belongs in a design doc, an ADR, or a function name.

**Write plain English.** Short sentences. Active voice. Common words. Write for a competent engineer who is new to this code, not for a specification.

```
BAD   // This method is responsible for the orchestration of the
      // validation subsystem prior to the persistence operation.
GOOD  // Validate before saving. A bad record here corrupts the
      // nightly export, which is hard to unwind.
```

**Never write "simply", "just", or "obviously".** If it were obvious the comment would not exist. These words tell a stuck reader that they should have understood, which helps nobody.

**Comments worth writing:**

| Kind | Example |
|---|---|
| Why this approach | `// Sorting here rather than in SQL: the index is on created_at, not amount.` |
| Why not the obvious one | `// Not using the bulk API. It silently drops rows over 1MB.` |
| A constraint from outside the code | `// Vendor caps this at 100 per call. See ticket PAY-2214.` |
| A non obvious consequence | `// Order matters. Revoking after deleting leaves an orphan grant.` |
| A warning | `// This runs before auth middleware. Treat every field as hostile.` |
| A link to the source of truth | `// Rounding rule per RFC 8785 section 3.2.2.11.` |

**Comments not worth writing:** anything restating the line below it, a docstring that repeats the signature with no added meaning, section banners in a file that should have been split, commented out code (delete it, version control has it), and `TODO` with no owner and no context.

**A comment explaining what a block does is a signal to extract a function.** The comment becomes the function name and stops going stale.

```
BAD   // check if the user can access this workspace
      if (u.role === 'admin' || (u.workspaces.includes(w.id) && !w.locked)) {

GOOD  if (canAccessWorkspace(user, workspace)) {
```

**A wrong comment is worse than no comment.** It is trusted and it lies. If you change code, change the comment above it or delete it. Comments describing behavior that no longer exists actively mislead.

## Structure for reading

**One function, one job, one level of abstraction.** A function that validates, transforms, saves, and emails is four functions. Mixing high level steps with low level detail in one body forces the reader to change altitude every few lines.

**Order top down.** Put the high level function first and the details it calls below, so a reader gets the shape before the specifics. Public before private. Caller before callee.

**Keep the happy path least indented.** Return early on the invalid cases so the main flow runs straight down the left edge.

```
BAD   if (user) {
        if (user.isActive) {
          if (hasQuota(user)) {
            return process(user);
          } else { return err('quota'); }
        } else { return err('inactive'); }
      } else { return err('missing'); }

GOOD  if (!user) return err('missing');
      if (!user.isActive) return err('inactive');
      if (!hasQuota(user)) return err('quota');
      return process(user);
```

**Three levels of nesting is the ceiling** in new code. Past that, extract.

**Group related lines, separate unrelated ones.** A blank line is a paragraph break. A function that is one unbroken wall of twenty lines is harder to scan than the same lines in four groups.

**Few parameters.** More than three or four suggests a missing type. A bare boolean at a call site is unreadable: `createUser(name, email, true, false)` tells the reader nothing. Pass an options object or named arguments, or split the function.

**Keep related code close.** A variable declared thirty lines before its use makes the reader hold it in their head the whole way.

## Control flow

**Boring beats clever.** A nested ternary, a chained one liner, or a bit twiddling trick saves lines and costs comprehension. Optimize for the reader, not the line count.

**Prefer positive conditions.** `if (isValid)` over `if (!isInvalid)`.

**Do not reuse a variable for two meanings.** Give the second meaning its own name.

**Make the exhaustive cases obvious.** A `switch` over an enum with every case named, and a default that fails loudly, reads better and breaks louder than an `if` chain that silently falls through.

## Types and data

**Types are documentation that cannot go stale.** A named type says more than a comment, and the compiler enforces it. `Duration`, `EmailAddress`, and `OrderId` beat three `string` parameters in a row that can be swapped by accident.

**Enums over booleans and bare strings.** `status: ACTIVE | PAUSED | CANCELLED` tells the reader the full set. A boolean that might grow a third state is a rename waiting to happen.

**Make illegal states unrepresentable** where the language allows. If a record cannot be both `draft` and have a `publishedAt`, model it so that combination cannot be constructed. That removes a whole category of defensive checks and the comments explaining them.

## Text people read

Error and log messages are part of the interface. Same standards apply.

**An error message says what happened, what was expected, and what to do.** Include the identifiers needed to act on it.

```
BAD   "Invalid input"
BAD   "Error: operation failed"
GOOD  "Order 8813 has no shipping address. Add one before marking it shipped."
GOOD  "timeout after 5s calling payments-api (order 8813). Retry is safe."
```

**Never show internals to a user.** Stack traces, SQL fragments, class names, and file paths are for the log. Return a plain message and a correlation ID.

**Log messages follow the same rule as comments:** state the fact and the identifiers, not a narrative.

## Consistency

**Match the surrounding code.** A file with a consistent style you mildly dislike is easier to read than a file with two styles. Follow the project's existing naming, error handling, and file layout, even where your preference differs. If the convention is genuinely wrong, change it everywhere in a separate commit, not partially in this one.

Let the formatter and linter own formatting. Do not spend review attention on what a tool decides.

## Common rationalizations

| Claim | Reality |
|---|---|
| "I will add comments to explain it" | Comments do not fix an unclear name or a function doing four things. Fix those first |
| "More comments means more maintainable" | Every comment is a claim that can go stale. A wrong comment is worse than none |
| "The name is long, I will abbreviate" | The reader pays a translation cost every time. You paid four keystrokes once |
| "It is obvious what this does" | It is obvious to you today, with the context loaded |
| "I will name it properly later" | Names spread. By later it is in twelve files |
| "Everyone knows what `data` means" | Nobody knows what `data` means |
| "Short functions mean more jumping around" | True if split arbitrarily. Split along meaning and each name answers a question |
| "The docstring is required by the linter" | Then write one that adds meaning. Restating the signature satisfies the tool and wastes the reader |

## Red flags

- A comment that restates the line below it
- A variable named `data`, `info`, `temp`, `result`, `obj`, or `item` outside a two line scope
- A class named `Manager`, `Helper`, `Util`, or `Processor`
- A boolean literal at a call site: `send(order, true, false)`
- A number with no name appearing in a condition
- A negative boolean name forcing `!` at every use
- A comment starting with "simply", "just", or "obviously"
- A comment that describes behavior the code no longer has
- Nesting deeper than three levels
- A duration or size variable with no unit in its name
- A function you cannot describe in one sentence
- An error message with no identifier and no action
- Two names for the same concept in one codebase
