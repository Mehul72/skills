# Skills Library

Portable agent skills for backend work. Drop them into any repo so the coding agent
in that repo picks them up.

## Install

One command, on any machine:

```bash
npx github:Mehul72/skills install
```

npm 12 and later refuse git sources unless you say so, so on those add one flag:

```bash
npx --allow-git=root github:Mehul72/skills install
```

Either way you get the global layer installed and `skills` on your PATH. There is a
curl equivalent if you would rather not go through npm:

```bash
curl -fsSL https://raw.githubusercontent.com/Mehul72/skills/main/bootstrap.sh | bash
```

Both clone or copy the library to `~/.agent-skills`, install the global layer, and put
`skills` on your PATH. Private repo? Clone it yourself and run `./bootstrap.sh` from
inside the clone; it detects that and skips the network.

If the repo was uploaded through a web UI, its files lose their executable bit. That
is handled: run `bash bootstrap.sh` instead of `./bootstrap.sh` and it restores the
bits itself before installing.

Then, once per repo you work in:

```bash
skills init
```

### Installing as a package

`npm install -g github:Mehul72/skills` works too, and gives you the `skills` command,
but it does not always finish the job by itself:

| npm | what happens |
|---|---|
| 11 and earlier | the postinstall runs `skills install` for you |
| 12 and later | git sources need `--allow-git=root`, and install scripts are blocked, so run `skills install` yourself afterwards |

npm 12 blocks package install scripts by default and its own suggested
`--allow-scripts` flag did not lift the block in testing, so treat the postinstall as
a convenience on older npm and `skills install` as the thing that actually installs.
Either way, one command finishes it:

```bash
npm install -g --allow-git=root github:Mehul72/skills
skills install
```

The package never installs anything from a plain `npm install` as a dependency. The
postinstall exits immediately unless the install was global, so adding this to a
project's `package.json` cannot write to your `~/.claude`.

**npm is a delivery mechanism, not the home.** An npm package directory is a bad place
to live: npx wipes its cache, and nvm puts the node version in the global prefix path,
so every symlink and every absolute `@import` pointing into one breaks silently on the
next node upgrade. So an npm install copies the library to `~/.agent-skills` first and
installs from there. If you already have a git clone at that path, it is used as is and
the npm copy is ignored.

Skip the postinstall entirely with `SKILLS_SKIP_POSTINSTALL=1`. It is also skipped
when `CI` is set.

### Why two commands

Agents split into two groups, and only one of them has a machine wide config.

**Global, done once by `skills install`:**

| Agent | Written to |
|---|---|
| Claude Code | `~/.claude/skills/` (one symlink per skill), `~/.claude/CLAUDE.md`, `~/.claude/settings.json` |
| Codex | `~/.codex/skills/` (one symlink per skill), `~/.codex/AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| The `skills` launcher | `~/.local/bin/skills`, or `$SKILLS_BIN` |

Claude Code and Codex use the same skill format, `<name>/SKILL.md` with `name` and
`description` frontmatter, so one directory of skills feeds both. Codex keeps its own
bundled skills in `~/.codex/skills/.system/`, which the installer never touches.

Gemini CLI has no skills directory, so it gets the always on `AGENTS.md` layer only.

**Per repo, done by `skills init`:** Cursor, Copilot, Cline, Windsurf, Aider, and Zed
all read a file from the repo root and have no global equivalent. `skills init` writes
`AGENTS.md` and points every one of them at it:

```
AGENTS.md                          the real file
CLAUDE.md                          @AGENTS.md          Claude Code
.github/copilot-instructions.md -> ../AGENTS.md        Copilot
.clinerules                     -> AGENTS.md           Cline
.windsurfrules                  -> AGENTS.md           Windsurf
GEMINI.md                       -> AGENTS.md           Gemini CLI
CONVENTIONS.md                  -> AGENTS.md           Aider
```

Relative symlinks, so the repo stays portable and one edit updates every agent.

### Those files stay out of git

`skills init` adds what it wrote to `.git/info/exclude`, so none of it shows up in
`git status`. That file is local to one clone and is never committed, so a teammate
who clones the repo sees nothing of your setup, and no `.gitignore` change is proposed
in your diff.

Two things it deliberately does not do. A file already tracked in the repo is left
alone and reported, because exclude has no effect on anything in the index and hiding
a real `AGENTS.md` would be worse than showing it. And it never touches a repo before
`git init`; run init again afterwards, or pass `--no-exclude` to skip the whole thing.

```bash
skills init                 # excludes AGENTS.md, CLAUDE.md, and the five aliases
skills init --no-exclude    # leave them visible, to commit them for the team
```

Committing one anyway after the fact is `git add -f AGENTS.md`.

### Everything auto-updates

Skills are symlinked into `~/.claude/skills/`, and the global instruction files import
`AGENTS.md` from `~/.agent-skills` by absolute path. So:

```bash
skills update      # git pull, then re-link
```

updates skills, rules, and the hook together. That works when `~/.agent-skills` is a
git clone. Install through npm instead and it is a plain copy with nothing to pull, so
`skills update` tells you to re-run the installer. Claude Code also watches the skills
directory, so edits land in a session you already have open.

### Commands

```bash
skills install          global layer  (Claude Code, Codex, Gemini CLI)
skills init [dir]       repo layer    (everything else)
skills doctor           show what is installed where
skills update           refresh the library, then re-install
skills list             list the skills
skills uninstall        remove the skills
```

Flags: `--dry-run` to see what it would do, `--copy` instead of symlinks, `--force` to
overwrite, `NO_HOOK=1` to skip the per-turn hook, `--no-exclude` or `NO_EXCLUDE=1` to
leave the repo files visible to git.

**Nothing is ever overwritten.** An existing `AGENTS.md`, `CLAUDE.md`, or agent rules
file is left alone; the installer writes a `.from-skills-library` copy beside it and
prints the one line you need to add. The hook is merged into `settings.json` without
touching anything already configured.

The lower level `./install.sh` is still there for a single repo install without the CLI.

`skills update` pulls when the library is a git clone. On an npm copy there is
nothing to pull, so it prints the install command to re-run instead.

### Validate

```bash
./validate.sh
```

Checks frontmatter, name to directory match, cross references, and the em dash ban.
Run it before committing. It exists because a markdown formatter that does not
understand YAML frontmatter reads a closing `---` as a Setext heading underline and
rewrites `name:` into `## name:`, which silently breaks skill discovery. If your
editor formats markdown on save, exclude `skills/**/SKILL.md` or run this after.

### The always on layer

Skills load on demand, when the model decides the description matches. That is not
enough for rules that must apply to every reply, so the installer also writes two files
to the repo root:

- **`AGENTS.md`** carries the output rules, the confidence rules, the production bar, and
  the skill routing table. Cursor and Codex read it directly. It names each skill and
  tells the agent to load it through its own skill mechanism. It deliberately does not
  give a path to go read, because a path that is right for one agent is wrong for the
  next, and an agent handed a stale one reports the skill as missing.
- **`CLAUDE.md`** is one line, `@AGENTS.md`, plus a few Claude specific notes. Claude Code
  reads `CLAUDE.md` and not `AGENTS.md`, so the import is what connects them.

Neither is ever overwritten. If you already have one, the installer writes
`AGENTS.md.from-skills-library` beside it and tells you what to merge.

Re-running `skills init` after the library changes does update the repo's `AGENTS.md`,
but only when you have not touched it. `init` records a checksum of what it wrote in
`.git/info/skills-init.sha`, local to the clone and never committed. On the next run a
copy that still matches that checksum is refreshed in place; one that does not is
treated as yours and left alone. `--force` overwrites either way.

A repo set up before this existed has no checksum on file, so its first re-init still
parks a `.from-skills-library`. Diff the two, then take the update with `--force`.

#### Agent coverage

`AGENTS.md` is a cross tool convention with wide native support: Codex, Cursor,
Copilot Coding Agent, Gemini CLI, Windsurf, Zed, Aider, Devin, Jules, JetBrains
Junie, Amp, RooCode, Warp, VS Code, and others read it from the repo root, with
nested files in subdirectories taking precedence over the root one.

| Agent | Reads | Notes |
|---|---|---|
| Codex, Cursor, Copilot, Gemini CLI, Windsurf, Zed, Aider, Devin, Jules | `AGENTS.md` | Native, nothing extra needed |
| Claude Code | `CLAUDE.md` only | The `@AGENTS.md` import is what bridges it |
| Cline | `.clinerules` | Not covered. Symlink it: `ln -s AGENTS.md .clinerules` |
| GitHub Copilot in the editor | `.github/copilot-instructions.md` | Separate from the Coding Agent. Symlink if you use it |

Cursor also accepts `.cursor/rules/*.mdc` with `alwaysApply: true`, which is
equivalent to `AGENTS.md` for this purpose. Use one or the other, not both.

#### Per turn reinforcement

Every tool above loads its instruction file **once, at the start of the session**,
into the front of the context. The file does not vanish after the first message,
so the rules are technically present the whole time. What decays is attention to
them, over a long conversation with a lot of tool output in between.

Claude Code is the only one of these with a per turn injection point, the
`UserPromptSubmit` hook, which fires before the model sees each prompt and can add
context. The installer wires one up:

- `.claude/hooks/session-rules.md` holds the compact reminder. Edit it freely.
- `.claude/hooks/inject-rules.sh` prints it.
- The hook is registered in `.claude/settings.json`, merged in without touching
  anything already there.

It costs roughly 190 tokens per turn, so keep the file short. It restates only the
hard rules: output style, confidence marking, the done bar, and the four security
non negotiables. The full detail stays in `AGENTS.md` and the skills, loaded once.

Skip it with `NO_HOOK=1 ./install.sh`. Verify it is live with `/hooks` in a
Claude Code session.

## Skills

Grouped by when you'd reach for them.

```
Deciding what to build ──→ grilling ──→ adr (the decision) ──→ backend-design-doc (the design)
Writing it ─────────────→ readable-code · unit-test-gen · observability
Changing something live ─→ migration-safety (schema) · api-change-review (contract)
                           resilience-review (calls out) · safe-rollout (the deploy)
Taking something away ───→ deprecation
It's broken ────────────→ incident-response (on the clock) ──→ systematic-debugging (root cause)
It's slow ──────────────→ sql-performance (the query) · web-performance (the page)

Frontend ───────────────→ frontend-data-fetching (talking to your API) · react-review
                          accessibility · web-performance

Before calling it done ──→ security-hardening · code-quality · code-simplification
Auditing what exists ───→ security-audit (secrets in history, deps, CI/CD)
Writing it down ────────→ documentation (runbooks, and what a change made false)
Every reply ────────────→ response-style        Routing itself ──→ orchestrator
Out of context ─────────→ handoff (summarise, then open a fresh window)
```

Each skill's opening also says what it is *not* for, and routes to its sibling.

### Writing code

| Skill | What it does |
|---|---|
| `unit-test-gen` | Generates, fixes, and maintains unit tests for Go, Python, Java, JS/TS, and C++. Routes between a single-agent "lite" flow and a multi-agent writer/fixer pipeline based on how many functions are in scope. Carries per-language conventions (naming, mocking, run commands) and a defect-severity taxonomy covering concurrency, data persistence, interface contracts, and security. |
| `readable-code` | The standard for code a stranger can read in one pass. Names that state intent and carry their units, comments that explain why in plain English and never restate the line below, the happy path least indented, and error messages someone can act on. Corrects the specific direction generated code fails in: over commented and under named. |
| `observability` | Adds or reviews logs, metrics, traces, and alerts. Structured-log discipline, RED/USE metric selection, OpenTelemetry span conventions, a cardinality budget that keeps a stray `user_id` label from taking down your metrics backend, and symptom-based alerting with burn-rate thresholds. |

### Changing things that are already live

| Skill | What it does |
|---|---|
| `migration-safety` | Reviews or writes schema and data migrations for zero downtime. Expand-contract sequencing across deploys, per-operation lock classification for Postgres and MySQL, safe `NOT NULL`/foreign-key/index routes, batched resumable backfills, and rollback-safety. |
| `api-change-review` | Checks an API contract change for wire, source, and semantic compatibility across REST/JSON, gRPC/protobuf, and Thrift. Catches tag reuse, "safe" type widenings that break generated stubs, enum additions, and retrofitted pagination, plus the design issues (error model, idempotency keys, unbounded lists) you only regret later. |
| `resilience-review` | Reviews how a service calls its dependencies: timeouts and deadline propagation, retries with full jitter, retry budgets, circuit breakers, load shedding, and idempotency. Aimed at the failure mode that actually causes outages, a dependency getting *slow* and the caller amplifying it. |
| `safe-rollout` | Plans a rollout around the question "how cheaply do we undo this?", risk rating, deploy/release decoupling via flags, shadow traffic, staged canary percentages, advance/hold/rollback thresholds written down *before* the deploy, and a rollback plan that accounts for data the new path already wrote. |
| `deprecation` | Retires an API, endpoint, service, or table without breaking the callers still on it. Usage telemetry before announcement, advisory vs. compulsory sunset, migration tooling you ship yourself, and a removal gated on measured usage hitting zero rather than on a date passing. |

### When something is wrong

| Skill | What it does |
|---|---|
| `systematic-debugging` | Four-phase root-cause discipline: reproduce, isolate by bisection, prove the causal chain, then fix and verify. Exists to stop the guess-and-patch loop, no code changes until the mechanism is explained. |
| `sql-performance` | Diagnoses a slow query end to end: find it in `pg_stat_statements`/the slow log, read the plan properly (including the per-loop trap in both engines), pick the index column order deliberately, and check for the predicates that silently disable indexes. Covers keyset pagination and N+1. |
| `incident-response` | Drives a production incident: severity triage, mitigate-before-diagnose, timeline building, fixed-cadence comms, and a blameless postmortem with owned action items. Ships a reference of triage commands for Kubernetes, Go, JVM, Postgres, MySQL, Redis, and Kafka. |

### Before you commit to an approach

| Skill | What it does |
|---|---|
| `adr` | Writes an Architecture Decision Record, context as constraints, alternatives with real disqualifying reasons, consequences including the negatives, and a "revisit if" clause that turns future relitigation into a fact question. One page; matches whatever ADR convention the repo already uses. |
| `backend-design-doc` | Writes a backend technical design document, background, requirement analysis, system design, per-interface core changes, checklist, with strict Mermaid standards for flowcharts, architecture, sequence, ER, and state diagrams, plus a syntax validation pass. |
| `grilling` | Stress-tests a plan or design by interviewing you against a design tree, asking each round's unblocked questions with a recommended answer. Good before committing to an approach. |
| `grill-me` | Slash-command alias that invokes `grilling`. |

### Frontend, if you end up there

Secondary tier. You're a backend engineer, but these cover the parts of frontend work
where backend instincts don't transfer. Frontend *testing* is already covered by
`unit-test-gen`, which carries React, Vue, Jest, Vitest, and Testing Library references.

| Skill | What it does |
|---|---|
| `frontend-data-fetching` | The backend/frontend seam, and the highest-value one here. Request waterfalls, the race condition where a stale response overwrites a fresh one, the four UI states (loading/error/**empty**/success), why server data is a cache rather than state, optimistic updates with rollback, and token-refresh stampedes. |
| `web-performance` | Core Web Vitals against real field data, not a Lighthouse score: the LCP subpart breakdown that tells you whether it's your problem or the backend's, long-task hunting for INP, layout-shift causes, and a bundle budget enforced in CI. |
| `react-review` | The patterns that actually cause React bugs, effects that should be derived values, props copied into state, index keys, re-render cascades from fresh object identity, stale closures, and premature memoization. |
| `accessibility` | WCAG 2.2 AA in practice, weighted toward forms and widgets: semantic elements over ARIA, focus management in modals and SPA route changes, programmatically associated errors, contrast, and live regions. |

### Before calling it done

The bar that turns working code into shippable code. These apply at write time, before
the diff exists, which is where the built in `/code-review`, `/security-review`, and
`/simplify` cannot reach.

| Skill | What it does |
|---|---|
| `security-hardening` | The OWASP Top 10:2025, weighted toward what generated code actually gets wrong: authorization omitted because nobody asked for it, SQL built by concatenation, errors that fail open, secrets in source. Ships a per language checklist and the one authorization test that catches most IDOR. |
| `code-quality` | A production ready checklist you must pass before reporting work complete, then a review ordered by cost of being wrong: correctness, error handling, concurrency, tests, interfaces, operability, and clarity last. Requires you to say what you actually ran rather than implying it. |
| `code-simplification` | Reduces working code without changing behavior. Deletes speculative abstraction, dead code, redundant state, and guards against impossible states. Holds the line that duplication is cheaper than the wrong abstraction, so fold on the third occurrence and not the second. |
| `security-audit` | The other half of `security-hardening`: not the change about to land, but what is already wrong. Sweeps git history for credentials that were deleted but never rotated, checks dependency supply chain past `npm audit`, and audits the CI/CD pipeline that holds every deploy secret. Most of it is the filter, because an audit reporting forty issues gets shelved and six get fixed. |
| `documentation` | Picks the right kind of document, then finds what the last change made false. Covers the runbook someone follows at 3am, the drift audit that maps a diff onto the docs it just invalidated, and what not to write, since every document is a maintenance liability. A wrong document is worse than a missing one, because a missing one sends you to the source. |

### How the agent works and writes

| Skill | What it does |
|---|---|
| `response-style` | How output is written. Answer in the first sentence, no em or en dashes, no filler openers or closing offers, no marketing adjectives, and a confidence level attached to every claim: verified, inferred, or unknown. If you are not confident, keep working until you are, rather than hedging the sentence. |
| `handoff` | Summarises the session so a fresh agent window can continue. Splits multi topic sessions into separate blocks, marks superseded requirements as superseded, and records every correction the user made so the next agent does not repeat the mistake. Defaults to a dense agent readable form; `handoff human` gives a short narrative. |
| `orchestrator` | Picks which skills a request needs and puts them in order, including the sequencing rules that matter (mitigate before diagnose, security and tests before done) and the escalation triggers that pull a skill in mid task when a diff touches a migration, a `.proto`, or user input reaching a query. |

## Provenance

### Written for this library

`migration-safety`, `sql-performance`, `api-change-review`, `resilience-review`,
`observability`, `systematic-debugging`, and `incident-response` were written here,
grounded in published references rather than recalled from memory:

- **Migrations:** the [strong_migrations](https://github.com/ankane/strong_migrations)
  operation catalogue, and the Postgres
  [explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html)
  docs for the FIFO lock-queue behaviour that makes one blocked `ALTER TABLE` stall
  every reader on the table.
- **Indexes:** [Use The Index, Luke](https://use-the-index-luke.com/) on concatenated
  index column order and the leftmost-prefix rule.
- **API compatibility:** [AIP-180](https://google.aip.dev/180) on wire vs. source vs.
  semantic compatibility, plus the protobuf and Thrift encoding rules.
- **Resilience:** the Google SRE book on
  [addressing cascading failures](https://sre.google/sre-book/addressing-cascading-failures/)
  for retry budgets, deadline propagation, and load shedding; AWS's
  [exponential backoff and jitter](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)
  for the full-jitter formula and why it beats the alternatives.
- **Observability:** the OpenTelemetry
  [HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/)
  for span naming, required attributes, and the rule against putting raw URI paths in
  span names.
- **Process:** the four-phase debugging and incident structures follow the shape used
  by [obra/superpowers](https://github.com/obra/superpowers) and common SRE practice.

`safe-rollout`, `deprecation`, and `adr` were adapted from the corresponding skills in
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (MIT, © 2025 Addy
Osmani), rewritten for backend work: the frontend-specific gates (Core Web Vitals, bundle
size, client JS errors) were replaced with dependency load, queue depth, and consumer lag,
and the deprecation flow was reoriented around measured usage telemetry as the removal
gate. Three patterns from that repo were also folded back into the skills above, the
"common rationalizations" tables, the "red flags" lists, and the explicit *not for this,
use X instead* routing between sibling skills.

The frontend tier (`web-performance`, `frontend-data-fetching`, `react-review`,
`accessibility`) was written here, checked against current sources rather than memory, [web.dev](https://web.dev/articles/vitals) for the Core Web Vitals thresholds and the fact
that INP replaced FID in 2024, and the [W3C](https://www.w3.org/WAI/standards-guidelines/wcag/)
for WCAG 2.2 being the current Recommendation. `addyosmani/agent-skills` supplied the
starting shape for the performance and accessibility material.

`security-hardening` is built on the [OWASP Top 10:2025](https://owasp.org/Top10/2025/),
confirmed against owasp.org rather than recalled: Broken Access Control still leads,
Security Misconfiguration moved to second, SSRF folded into A01, and two categories are
new, Software Supply Chain Failures and Mishandling of Exceptional Conditions. That last
one is why fail open error handling gets its own section.

`security-audit` and `documentation` were written here, adapting two ideas from
[gstack](https://github.com/garrytan/gstack) by Garry Tan (MIT): its confidence gating
and false positive filtering for security findings, and its post ship documentation
drift audit. The four document kinds follow the
[Diataxis](https://diataxis.fr/) framework by Daniele Procida.

`readable-code`, `handoff`, `response-style`, `orchestrator`, `code-quality`, and
`code-simplification` were written here. The always on split between `AGENTS.md` and `CLAUDE.md` follows the
[Claude Code memory docs](https://code.claude.com/docs/en/memory), which specify that
Claude Code reads `CLAUDE.md` only and recommend the `@AGENTS.md` import to share one
file across agents.

The whole library contains no em or en dashes, checked mechanically. `response-style`
bans them, and a library that banned them while using them everywhere would be teaching
the opposite of what it says.

Engine-specific and protocol-specific detail lives in each skill's `references/`, so a
`SKILL.md` stays short and the Postgres tables only load when the task is a Postgres
migration.

### Carried over from the `api_test` monorepo

`unit-test-gen`, `backend-design-doc`, `grilling`, and `grill-me` came from that repo and
were edited for portability. It held ~140 skills, but nearly all were QA test-case
generators welded to a single business line, or dependent on internal tooling. These four
transfer.

Two were reworked rather than copied:

- **`unit-test-gen`** came from `bits-unit-test-gen`. Removed: a mandatory telemetry
  beacon that posted your username, working directory, agent, and model to an internal
  endpoint on every run, and instructed the agent never to show those commands to you.
  Also removed the `utree` CLI dependency, which downloaded a binary from an internal
  host and uploaded run results; the scratch directory is now a plain `mktemp -d`. Test
  names no longer carry the `_BitsUT` platform suffix, comment language follows the
  project instead of being pinned to Chinese, and the Lynx (internal framework)
  reference is gone. The workflow, language prompts, and reference agents are otherwise
  unchanged.
- **`backend-design-doc`** was extracted from `adk-sdd-erd`, which was welded to
  `.ttadk/` scripts, config, and templates that don't exist outside that repo, and
  ended by uploading to Lark. Kept the diagram standards and document structure;
  dropped the plumbing and the frontend half.

## Adding a skill

Create `skills/<name>/SKILL.md` with YAML frontmatter:

```markdown
---
name: my-skill
description: What it does and when the agent should reach for it. This is the only
  part the agent sees before deciding to load the skill, so make the triggers explicit.
---

# My Skill

Instructions here. Put long reference material in `references/` and load it on demand.
```

Supporting files go in `references/`, `assets/`, and `scripts/` beside `SKILL.md`.
Keep `SKILL.md` short and push detail into `references/` so it loads only when needed.
