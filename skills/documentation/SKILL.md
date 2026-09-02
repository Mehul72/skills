---
name: documentation
description: Write documentation that stays true, and find what a change just made false. Covers picking the right kind of document (tutorial, how to, reference, explanation), auditing docs for drift after shipping, writing a runbook someone can follow at 3am, and deciding what not to write. Use when adding or updating a README, runbook, or API docs, when a change alters behaviour someone has written down, after shipping a feature, when onboarding docs are wrong, or on any mention of documentation, docs, or a runbook.
---

# Documentation

Documentation fails in two ways, and the second one causes outages.

**The document that was never written.** Annoying. Someone reads the code instead and loses an hour.

**The document that is now a lie.** Dangerous. Someone follows a runbook that describes last quarter's architecture, at 3am, during an incident, and makes it worse. A wrong document is worse than a missing one, because a missing one sends you to the source.

This means the maintenance question comes first: before writing anything, decide what makes it false and whether anyone will notice when it happens.

Not for: a design document for a change you are about to make, which is `backend-design-doc`. Not for recording why a decision was made, which is `adr`. Not for comments inside code, which is `readable-code`. Not for the API contract itself, which is `api-change-review`.

## Step 1: Pick one kind and stay in it

Four kinds, from the Diataxis framework. Each serves a different reader in a different state. The usual failure is one document trying to be all four, which serves none of them.

| Kind | Reader | Question | Shape |
|---|---|---|---|
| Tutorial | New, no context | "Get me a first success" | One path, no choices, guaranteed to work |
| How to | Working, has a goal | "How do I do X" | Task focused, assumes context, states prerequisites |
| Reference | Working, needs a fact | "What are the parameters" | Complete, dry, structured, no narrative |
| Explanation | Curious, deciding | "Why is it built this way" | Discursive, covers alternatives and trade offs |

The tells that a document is mixing kinds:

- A tutorial that says "you could also use X" has become an explanation and lost the reader.
- Reference material with a story in it is unusable for lookup.
- A how to that starts by teaching concepts is a tutorial nobody asked for.
- An explanation with step by step commands is a how to that will drift.

For a backend service, the set that earns its keep is usually: a README that gets a new engineer running locally (tutorial), runbooks for the things that page you (how to), generated API reference (reference), and an ADR trail (explanation). Everything else is optional and everything optional rots.

## Step 2: After a change, find what it made false

This is the step that gets skipped, and it is the one that prevents the dangerous failure.

Work from the diff, not from memory. For each thing the change touched, search the docs for what mentions it.

```bash
# What changed, at the level docs talk about.
git diff --name-only <base>..HEAD

# Identifiers that changed, then find every doc mentioning them.
git diff <base>..HEAD | grep -E '^[-+].*(func |def |class |route|endpoint)' | head -40
grep -rn '<changed-name>' --include='*.md' --include='*.rst' --include='*.txt' .
```

Then walk the specific things that go stale, because each has a different tell:

| Changed | Now check |
|---|---|
| An endpoint, its path, or its shape | README examples, API docs, client snippets, Postman or `.http` files |
| An environment variable | `.env.example`, deploy config, the setup section, the runbook |
| A CLI flag or command name | Help text, README usage, CI workflows, anything pasted into a doc |
| A default value | Every doc that states the old default as fact |
| A dependency or its minimum version | Install instructions, the prerequisites section, CI matrix |
| A schema or migration | Data model docs, ER diagrams, anything describing a column that moved |
| An error code or message | Runbooks that match on the old text, alert definitions, support docs |
| An alert threshold or an SLO | The runbook that responds to it |
| A deploy or rollback step | The runbook, and whoever will run it under pressure |

A code example in a document is a claim you are making. If it no longer runs, the document is lying in the most convincing possible format.

## Step 3: Runbooks

The one kind of documentation a backend engineer is judged on, because it gets read under pressure by someone who did not write it.

A usable runbook has:

- **The trigger, stated exactly.** The alert name or the symptom, matching what the pager actually says.
- **How to confirm it is really this.** The query or dashboard that distinguishes this from the three things that look like it.
- **Mitigation before diagnosis.** What restores service now. Put it first. Root cause comes after the bleeding stops.
- **Commands that can be pasted.** Real commands with real flags, not a description of what to do. Mark anything destructive as such.
- **How to tell it worked.** The specific signal that says the mitigation took effect.
- **When to escalate, and to whom.** With a time bound, not "if it seems bad".

What makes a runbook fail:

- Written for the author. It says "restart the worker" without saying where it runs or how.
- No verification step, so the responder does not know whether they helped.
- Diagnosis before mitigation, so the outage lasts as long as the investigation.
- Never executed since it was written. A runbook nobody has followed is a hypothesis.

Test a runbook by having someone who did not write it follow it. Everything they have to ask about is a defect in the document.

## Step 4: Decide what not to write

Every document is a maintenance liability. The ones worth keeping are the ones where the cost of being wrong exceeds the cost of upkeep.

Do not write:

- **Anything the code already says.** A list of endpoints that a generator can produce from the routes. Generate it or link to it.
- **Anything a comment restating the mechanism would say.** See `readable-code`.
- **Architecture prose that duplicates a diagram** which duplicates the module layout.
- **A tutorial for an internal tool with three users.** Talk to them.
- **Aspirational docs.** Describing how the system should work reads identically to describing how it does, and the reader cannot tell which they got.

Prefer, in order: make it obvious in the code, generate it from the code, write it down. Only the third one drifts.

## Step 5: Make drift detectable

A document only stays true if something notices when it stops being true.

- **Generate reference material** from the source of truth: OpenAPI from the route definitions, schema docs from migrations, CLI help from the parser.
- **Execute the examples.** A README snippet that runs in CI cannot silently rot. Doctests, tested code blocks, or a smoke script that runs the documented commands.
- **Check links in CI.** A dead link is the cheapest possible signal that a document has been abandoned.
- **Keep the doc next to the code it describes**, so it appears in the same diff and the reviewer sees both.
- **Put the ones that matter in review.** A change to an alert threshold that leaves the runbook alone should not pass review.

Date anything you cannot automate, so a reader can weigh it. "Last verified 2026-03" tells the reader more than a confident sentence with no provenance.

## Common rationalizations

| Claim | Reality |
|---|---|
| "The code is self documenting" | True for what it does, never for why, and never for how to operate it |
| "We will document it after the launch" | After the launch is when the author forgets and moves on |
| "The doc is mostly right" | The reader cannot tell which part is the mostly |
| "Everyone knows how the deploy works" | Everyone currently on the team, while they are awake and available |
| "It is in the wiki" | Then check when it was last edited before relying on it |
| "Updating docs is not part of this change" | The change is what made them wrong |
| "The runbook is thorough" | Thorough is not the goal. Followable by a tired stranger is |

## Red flags

- A runbook nobody has executed since it was written
- Setup instructions that fail on a clean machine
- A code example that does not run
- Two documents describing the same thing differently, with no way to tell which is current
- An environment variable in the code that appears in no `.env.example`
- A merged change that renamed something, with no doc touched in the same diff
- A README whose first section is architecture rather than how to run the thing
- Documentation written in the future tense about code that already shipped

Document kinds follow the Diataxis framework by Daniele Procida. The post change drift
audit is adapted from gstack by Garry Tan (MIT).
