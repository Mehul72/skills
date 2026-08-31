---
name: handoff
description: Summarise the current session into a handoff document so a fresh agent window can continue without losing context. Captures per topic state, decisions and why, requirement changes, and corrections the user made, so mistakes are not repeated. Defaults to an agent optimised long form; pass "human" for a readable narrative. Use when asked to summarise the chat, hand off, start a new window, compact the session, or write context for the next agent.
---

# Handoff

The next agent starts with nothing. It cannot see this conversation, the tool output, or the reasoning. It will redo work you already did and repeat mistakes the user already corrected, unless this document stops it.

So the goal is not a summary of the conversation. It is a **state transfer**. Write what is true now, what was decided and why, and what already went wrong. The narrative of how you got there matters only where it changes what the next agent should do.

**Default mode is agent.** Long, dense, structured for a model to consume. Length is not the cost here; a missing decision is. Only produce the human mode when the user asks for it, with "human", "readable", or "for me to read".

## Step 1: Extract

Go back through the session and pull out these, in this order of value.

**Corrections the user made.** The highest value content in the document and the most commonly dropped. Every time the user said "no", "actually", "don't", "that's wrong", or redirected you, that is a rule the next agent needs. Record what you did, what the user said, and the standing rule that follows from it. Without this section the next agent reproduces the same mistake in its first ten minutes.

**Requirement changes.** Anything asked for and then revised, expanded, or dropped. **Mark superseded requirements as superseded.** An unmarked old requirement sitting next to a current one is worse than omitting it, because the next agent may implement the wrong one.

**Decisions and their reasons.** What was chosen, what was rejected, and why. Without the reason the next agent reopens the question and may pick differently, producing an inconsistent codebase.

**Bugs found and fixed during the session.** What broke, the cause, the fix. Prevents reintroduction, and tells the next agent which areas are fragile.

**Current state.** What exists now: files created or modified, what is committed, what is running, what is verified.

**Open items.** What is unfinished, blocked, or deliberately deferred, and which of those the user knows about.

**Standing preferences.** How the user wants things done, stated once and expected to hold. Style, tools, workflow, tone.

## Step 2: Separate topics

If the session covered more than one task, split them. Do not merge unrelated work into one narrative, and do not interleave them chronologically.

- Give each topic its own block with its own state, decisions, and open items.
- Name each topic so the difference is obvious from the heading alone.
- If topics are related, say how in one line. If they are independent, say that too, so the next agent does not hunt for a connection that is not there.
- Order by what the next agent is most likely to continue, not by when it happened.

A session where the user asked for three unrelated things produces three blocks, not one merged story.

## Step 3: Mark status honestly

Every claim carries a status. This is where handoffs mislead most.

| Status | Means |
|---|---|
| **Done, verified** | Built, run, output read. Say what was run |
| **Done, unverified** | Written but not executed. Say so explicitly |
| **In progress** | Partially applied. Say exactly how far |
| **Decided, not started** | Agreed approach, no code |
| **Open** | Not resolved. Say what would resolve it |
| **Superseded** | Was true, no longer is. Keep only if the next agent might otherwise redo it |

**Never write "done" for something only written.** The next agent will build on it, and the failure surfaces later and further away.

## Step 4: Point, do not copy

- Reference files by path and line, not by pasting contents. The next agent can read the file, and a stale copy in the handoff is worse than no copy.
- Do not restate anything derivable from the code, the git history, or the README. That is context the next agent gets for free.
- Do include anything **not** in the repo: reasons, rejected options, constraints the user stated verbally, and things you tried that failed.

The test for including something: would the next agent do the wrong thing without it? If not, cut it.

## Step 5: Write it

Write to `.handoff/YYYY-MM-DD-HHMM.md` and print the path. Tell the user to add `.handoff/` to `.gitignore` if it is not there already. If the user wants it inline to paste directly, print it instead.

Follow `response-style`. No em or en dashes, no filler, no closing offer.

## Agent template (default)

```markdown
# Handoff: <one line scope of the session>

Repo: <path>   Branch: <branch>   Date: <date>
Uncommitted: <yes, list them / no>

## Read first
<the 1 to 3 things that change what the next agent does. If nothing, omit.>

## Standing rules from the user
<preferences stated this session that apply to all future work>
- <rule>. Source: user said "<short quote>"

## Corrections made this session
<what the AI got wrong and was told about. Most important section.>
| What I did | User's correction | Rule going forward |
|---|---|---|
| <action> | "<quote or paraphrase>" | <the durable rule> |

## Topic 1: <name>

**Goal:** <what the user asked for, current version>
**Status:** <done verified / done unverified / in progress / open>

**Requirement changes**
- Originally: <X>. Changed to: <Y>. Reason: <why>. **<X> is superseded.**

**Decisions**
| Decision | Chose | Rejected | Why |
|---|---|---|---|

**Files**
| Path | Change | Verified |
|---|---|---|

**Bugs found and fixed**
- <symptom> caused by <cause>, fixed by <fix> at <path:line>

**Verified by**
- <exact command run and what the output showed>

**Open**
- <item>. Blocked on: <what>. / Deferred because: <why>.

## Topic 2: <name>
<same structure. Repeat per topic. State up front if topics are independent.>

## Explicitly out of scope
<things raised and deliberately not done, so the next agent does not "helpfully" do them>

## Next action
<the single most likely next step, concrete>
```

Omit any section with nothing in it. Do not leave empty headings.

## Human template

Load `references/human-template.md` when the user asks for the readable version.

## Common rationalizations

| Claim | Reality |
|---|---|
| "The next agent can read the code" | It cannot read the reasons, the rejected options, or the corrections. That is the whole point |
| "I will keep it short to save tokens" | A short handoff that omits a decision costs a rewrite. Density is the goal, not brevity |
| "The correction was minor" | It was important enough for the user to type. Record it |
| "Both requirements are in there somewhere" | Unmarked superseded requirements get implemented. Mark them |
| "It is basically done" | Say written and not run, or say what you ran |
| "The topics are related enough to merge" | If the user asked separately, keep them separate |
| "I will summarise what we discussed" | Summarise what is true. Discussion is only relevant where it constrains the next step |

## Red flags

- A chronological narrative of the conversation instead of current state
- A superseded requirement listed with no marker
- "We considered several options" with no statement of which was chosen
- No corrections section in a session where the user pushed back
- "Done" on something never executed
- File contents pasted instead of paths
- Three unrelated tasks merged into one topic
- Content that restates the README or the directory structure
- No concrete next action
