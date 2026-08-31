# Human Readable Handoff

Use when the user asks for the readable version: "human", "readable", "for me", "so I can review it".

Different job from the agent version. A person already knows roughly what happened and wants to reload it quickly, check nothing was missed, or forward it to a colleague. So this one is short, narrative where narrative helps, and leads with outcome.

## Rules

- **Half the length of the agent version at most.** If the agent version is comprehensive, this one is selective.
- **Lead with what changed**, not with what was discussed.
- Prose for the story, tables only where things are genuinely compared.
- Skip the machinery a person does not need: exact commands run, per file line counts, verification detail. Keep the conclusion, drop the evidence.
- Keep every correction and every requirement change. A person reviewing wants those most.
- Name open decisions clearly, because those are the ones needing the person's input.
- No em or en dashes. Follow `response-style`.

## Template

```markdown
# <session scope>, <date>

**Where things stand:** <two or three sentences. What exists now, what works,
what does not.>

## What was done

<One short paragraph per topic. What you set out to do, what it took, what the
result is. Mention the interesting surprise if there was one, skip the routine
parts.>

**Topic name.** <paragraph>

**Topic name.** <paragraph>

## Decisions worth remembering

- **<Decision>.** <Why, in one sentence.> <What was rejected, if it was close.>

## Changes of direction

- <What was asked for first, what it became, and why.>

## Corrections

- <What went wrong, how it was caught, what is different now.>

## Still open

- **<Item>.** <Why it is open and what would close it. Flag the ones needing
  your decision rather than more work.>

## If you pick this up again

<The one or two things to do next, in plain terms.>
```

## What to cut relative to the agent version

| Agent version has | Human version |
|---|---|
| Exact verification commands | "Tested and passing" |
| Per file change tables | Named in prose, only where it matters |
| Standing rules restated | Cut, the person already knows their own preferences |
| Out of scope section | Cut unless something was actively declined |
| Full decision tables | The two or three that were close calls |
| Status taxonomy | Plain words: works, half done, not started |

## What to keep at full fidelity

- Requirement changes. The person may not remember agreeing.
- Corrections. The person raised them and will check they landed.
- Open items needing their decision, marked clearly as needing them and not more work.
