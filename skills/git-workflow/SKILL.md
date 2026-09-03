---
name: git-workflow
description: >-
  Prepare work for review without ever publishing it: branch hygiene, deliberate staging,
  atomic commits, short commit messages carrying no agent attribution, and a PR description
  written into the chat for the user to use. The agent commits locally and stops; pushing,
  opening the PR, and merging belong to the user. Use when committing, staging, splitting a
  large change, writing a commit or PR description, or responding to review comments.
---

# Git Workflow

**A commit is both the unit of review and the unit of revert.** Size it so both work. A commit too big to review is also too big to revert cleanly at 2am, which is when you find out.

The reviewer, and the person bisecting six months from now, only ever see what history says. Effort spent shaping history is not bookkeeping, it is the only part of this work that outlives the branch.

Not for: whether the code is good enough to merge, which is `code-quality`. Not for the checks that gate the merge (`ci-cd`) or what happens to the artifact afterwards (`safe-rollout`).

## The boundary: commit locally, never publish

Three rules, and none of them has an exception worth taking.

**1. Never push. Never open a PR. Never merge.** Not `git push` in any form, not `gh pr create`, not `gh pr merge`, not a push button in an IDE integration, not "just to a feature branch". Publishing is the user's action, because it is the point where the change becomes visible to other people and to CI, and that call is theirs. Prepare the commit, say it is ready, and stop.

**2. The history shows exactly one contributor: the user.** No `Co-Authored-By:` naming a model, an agent, or a tool. No `Signed-off-by:`, since you signed nothing. No "Generated with", no tool name, no robot emoji, in the subject, the body, or a trailer. Never set or override `user.name`, `user.email`, `GIT_AUTHOR_*`, `GIT_COMMITTER_*`, or pass `--author`. The commit is authored by whoever is running the session, with their configured identity, and nothing in it says otherwise.

**3. Asked for a PR description, write it into the chat.** As text the user can copy, not into a PR you created, and not into a file unless they asked for a file.

Committing at all is still something the user asks for. "The work is finished" is not "commit it".

## Step 1: Branch first

Never commit to `main` or a shared branch directly, including "just this one small fix". Branch before the first edit, not after, so the working tree can always be thrown away without losing anything.

One branch, one concern. If the branch name needs "and" in it, it is two branches.

Match the repo's existing naming rather than importing a convention:

```bash
git log --oneline -20                              # message style, prefixes, tense
git branch -a --sort=-committerdate | head -20     # branch naming
```

## Step 2: Stage deliberately

`git add -A` is how a `.env`, a 40MB fixture, a stray debug script, and someone else's half finished work end up in a commit. Stage what you meant to change:

```bash
git status                  # anything here you did not expect?
git diff                    # read your own change before anyone else does
git add <specific paths>
git diff --cached           # what is actually about to be committed
```

Before the commit lands, check the staged diff for: credentials and tokens, debug prints and commented out code, a TODO added by this change, generated files that belong in `.gitignore`, and unrelated formatting churn that will bury the real change. A key in a diff means stop and load `security-hardening`. A key already in history means `security-audit`, sweep, and rotate, because deleting it in a later commit does not remove it.

Files that are personal to your clone belong in `.git/info/exclude`, not the shared `.gitignore`.

## Step 3: Shape the commit

Each commit should build, pass tests, and do exactly one thing.

**Never mix a refactor with a behaviour change.** A rename touching 40 files plus a two line logic change produces a diff where the logic change is invisible, and a revert that undoes far more than intended. Move first, change second, two commits.

| Situation | Do |
|---|---|
| Refactor plus new behaviour | Two commits, refactor first |
| Formatting or a linter sweep | Its own commit, ideally its own branch |
| A dependency bump the feature needs | Its own commit, so it can be reverted alone |
| Fixing your own earlier commit on this branch | `git commit --fixup`, then `--autosquash` before handing over |
| A drive by fix you noticed | Its own commit, and say so when you report |

If the branch has become a pile, reshape it before handing it over: `git rebase -i` to squash noise and reorder, `git add -p` to split a commit that does two things. Reshaping an unpushed branch is free, which is another reason nothing gets pushed early.

## Step 4: Keep the message short

**One line.** Imperative, 72 characters or fewer, specific about what changed.

```
<prefix per repo convention>: <imperative summary>
```

Match the repo's convention first, from Step 1's `git log`: its prefixes, its tense, its capitalisation. A library that writes `feat: added X` gets `feat: added Y`, not a lecture about the imperative mood.

Add a body only when the user asks for one. If the change feels like it needs three paragraphs to justify, that is usually a signal to act on rather than prose to write: either the commit is doing two things and should be split, or the reasoning belongs somewhere that outlives a commit message, an `adr` or the PR description.

Never in a message, in any position:

- `Co-Authored-By:` naming a model, an agent, or a tool
- `Signed-off-by:` added on someone's behalf
- "Generated with", "Created by", "Made with", a tool name, or a robot emoji
- `wip`, `fix`, `updates`, `changes`, `address comments` as the entire subject
- "as requested" or "per review", which say nothing about what changed

Good: `fix: return 409 on duplicate idempotency key`. Bad: `fix: bug fix`, and worse with a trailer on the end crediting the machine.

## Step 5: Write the PR description into the chat

When the user asks for a PR description, output it as text they can copy. Do not create the PR.

**Review quality collapses with size.** Past a few hundred changed lines, reviewers stop finding defects and start approving. If the branch is bigger than that, say so and propose the seam it splits along: schema, then write path, then read path, then cleanup. `implementation-plan` steps make good PR boundaries because they were already sized to be committable alone.

```markdown
## What
One or two sentences. The change, not the journey to it.

## Why
The problem, or a link to the issue or ADR. Do not restate a whole design doc here.

## How to verify
The exact commands or steps a reviewer runs, and what they should see.
"Tested locally" tells a reviewer nothing they can check.

## Risk and rollback
What breaks if this is wrong, and how it comes back out. Say "none, additive"
when that is true, do not leave it blank.

## Notes for the reviewer
Where to start, anything deliberately left out, anything you are unsure about.
```

The same attribution rule applies here: nothing in the description says a tool wrote it.

State plainly what you ran and what you did not. A description implying tests were run when they were not is the failure `code-quality` exists to prevent, and it lands here as a sentence someone else will trust.

Name the parts a reviewer cannot see and the user will need to attach: a screenshot for UI, the migration lock time for a schema change, the before and after numbers for a performance fix.

## Step 6: Respond to review

Review comments arrive after the user has published the branch. Your side of it is local: make the change, commit it, and tell the user what is ready to push.

- **Answer every comment**, in the chat if you cannot post. Silence reads as disagreement or as being ignored.
- **Fixup commits, never a rewrite of what is already published.** Once the branch is pushed, its history is shared. Rebasing or squashing it means someone's review is now against a diff that no longer exists, and the user is the one holding the force push you must not do anyway.
- **Disagreeing is fine, guessing is not.** If a comment is wrong, say why with evidence. If it is a preference and the repo has no rule, take the reviewer's version and move on, it is cheaper than the thread.
- **A comment you do not understand is a question, not a change.** Making an edit you cannot explain to satisfy a comment you did not follow is how reviews inject bugs.
- **A finding that reveals a class of problem** goes wider than the one line: fix the class, and say so.

## Step 7: Hand it over

You are done when the branch is ready for the user to push, not when it is pushed. Report what is ready and what remains theirs to do.

- [ ] Commits shaped, messages short, no attribution trailer anywhere
- [ ] Tests run and passing, with the output actually read, per `code-quality`
- [ ] The staged diff carries no secret, no debug output, no unrelated file
- [ ] Migration, contract, and rollout skills applied if the change touches those (`migration-safety`, `api-change-review`, `safe-rollout`)
- [ ] PR description written into the chat, if one was asked for
- [ ] The user told exactly what is unpushed and what you did not do

**Never rewrite published history**, in the rare case you are asked to touch it: no rewriting commits someone else has pulled, and `git revert` rather than a rewrite for a bad commit already on `main`, because a revert is itself reviewable and does not break every clone.

Other things not to do without being asked: committing at all, committing on someone's behalf, amending someone else's commit, `git checkout .` or `git reset --hard` over uncommitted work you did not write, and `git clean -fd` in a tree you did not create. All of these destroy work with no undo.

## Common rationalizations

| "..." | Reality |
|---|---|
| "It's just a feature branch, pushing is harmless" | It triggers CI, notifies people, and is visible. The user decides when that happens |
| "I'll push so the user can see the diff" | `git diff` and `git log -p` show them the diff without publishing it |
| "The co-author trailer is standard practice" | Not here. One contributor, and it is the person running the session |
| "A longer message documents the decision better" | A commit message is the wrong home for a decision. That is an `adr` |
| "It's a one line fix, straight to main" | One line changes cause outages routinely, and the branch costs ten seconds |
| "The PR is big but it's all related" | Related is not reviewable. The reviewer's attention runs out at the same size either way |
| "The formatting change is in there too, it's fine" | It is fine until the revert takes the formatting with it, or hides the real diff |
| "I'll squash the debug commits later" | Do it before handing over, while the branch is still unpublished and free to reshape |
| "Everyone knows why this changed" | For about three weeks. `git blame` is read by people who were not there |

## Red flags

- Any `git push`, `gh pr create`, or `gh pr merge` in the transcript
- `Co-Authored-By`, `Signed-off-by`, or a tool name anywhere in a commit message
- `--author`, `user.name`, or `GIT_AUTHOR_*` set or overridden
- A commit made without being asked for one
- Commits directly on `main`, or a branch nobody can name the concern of
- `git add -A` followed immediately by a commit
- A diff containing a credential, a `.env`, or a large binary
- A commit message that is `wip`, `fix`, `updates`, or `address comments`
- A refactor and a behaviour change in one commit
- A multi paragraph commit message where a split was the real fix
- "How to verify" that says "tested locally"
