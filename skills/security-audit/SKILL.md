---
name: security-audit
description: >-
  Audit a whole repository for security problems that already exist, rather than reviewing a
  change about to land. Covers secrets sitting in git history, dependency supply chain, CI/CD
  pipeline security, and infrastructure config, then filters the results so what you report is
  worth acting on. Use when asked for a security audit, a threat model, a pentest style
  review, a secrets sweep, or a dependency and CI/CD risk check; when onboarding to an
  unfamiliar codebase; or before an external review.
---

# Security Audit

An audit is a different job from hardening. Hardening asks whether the code you are writing now is safe. An audit asks what is already wrong in code nobody is currently looking at, including code written before anyone cared.

Two failure modes, and the second is the one that kills audits.

**Missing the real thing.** Grepping for `password` finds variable names, not the AWS key that was committed in 2023, deleted in the next commit, and is still in the history and still valid.

**Drowning it in noise.** An audit that reports forty issues gets skimmed and shelved. Six real ones get fixed. Every candidate finding is guilty until proven, and the filtering step matters more than the scanning step.

Not for: reviewing a change before it merges, which is `security-hardening`. Not for an active compromise, which is `incident-response`. Not for general diff quality, which is `code-quality`.

## Step 1: Set the bar before you start

Decide the confidence gate first, so you are not tempted to move it once you have findings you like.

| Mode | Gate | When |
|---|---|---|
| Routine | Report only what you would bet on. Certain exploit path, or a clear vulnerability pattern with a known exploitation method | Recurring pass, pre-release check, onboarding |
| Deep | Report anything that might be real, each one labelled as unconfirmed | Annual review, pre-audit prep, post-incident |

In routine mode, a finding you cannot argue for concretely does not go in the report. Not in an appendix, not as a note. Out.

Score every finding 1 to 10 and put the score in the report. A reader who knows a 6 from a 9 can triage; a reader given a flat list cannot.

| Score | Meaning |
|---|---|
| 9 to 10 | Read the code, traced the path, can describe the exploit |
| 7 to 8 | Strong pattern match, very likely real, path not fully traced |
| 5 to 6 | Plausible, needs someone with context to confirm |
| Below 5 | Suppress in routine mode |

## Step 2: Map the attack surface

You cannot audit what you have not enumerated. Before reading any code, list:

- Every route, RPC method, and message queue consumer, and which of them require authentication
- Every place a request reaches the shell, a query, a template, a deserializer, or an outbound URL
- Every webhook receiver and what verifies its signature
- Every scheduled job and what it runs as
- Every admin path, debug endpoint, health check, and metrics endpoint, and whether they are publicly reachable
- What data the system holds that would matter if it leaked

Write this down. It is the checklist the rest of the audit works through, and gaps in it are findings on their own.

## Step 3: Secrets archaeology

`security-hardening` says rotate anything that ever reached a commit. This is how you find out whether anything did.

Deleting a secret in a later commit does not remove it. Anyone with a clone has it.

```bash
# Credentials by known prefix, across every branch and every commit.
git log -p --all -S 'AKIA' -- '*.env' '*.yml' '*.yaml' '*.json' '*.tf'
git log -p --all -G 'sk-[a-zA-Z0-9]{20}|sk_live_'
git log -p --all -G 'ghp_|gho_|github_pat_'
git log -p --all -G 'xoxb-|xoxp-|xapp-'
git log -p --all -G '-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY-----'

# Generic credential words, restricted to config files so the noise stays low.
git log -p --all -G 'password|secret|api_key|token' -- '*.env' '*.yml' '*.json' '*.conf' '*.ini'
```

Then check the present state:

```bash
# A .env that is tracked is a .env that shipped.
git ls-files '*.env' '.env.*' | grep -vE '\.(example|sample|template|dist)$'

# And whether it can happen again.
grep -qE '^\.env($|\.)' .gitignore || echo 'WARNING: .env is not gitignored'
```

Severity: a live credential format in history is critical, regardless of age. A tracked `.env` is high. A suspicious value in `.env.example` is low and usually a placeholder.

Do not test a found key against the live API to see whether it still works. Judge it by format, and tell the owner to rotate. Rotate anyway when in doubt: rotation is cheap and certainty is not.

Exclude: placeholders (`changeme`, `your_key_here`, `xxx`, `TODO`), test fixtures whose value appears nowhere else, and a secret that was added and removed inside the initial commit of a repo that was never pushed until after.

## Step 4: Dependency supply chain

`npm audit` and its equivalents are the floor, not the audit.

Run whatever the ecosystem provides (`npm audit`, `pip-audit`, `govulncheck`, `cargo audit`, `bundle audit`). If a tool is not installed, that is a note in the report, not a finding.

Then check what those tools do not:

- **Is the lockfile committed?** For an application, an uncommitted lockfile is a finding: the build is not reproducible and a compromised patch version ships silently. For a library, it is normal and not a finding.
- **Do any production dependencies run install scripts?** A `preinstall`, `install`, or `postinstall` hook executes on every developer machine and every CI runner. Native build tooling is expected. Anything else deserves a look at what it runs.
- **Does the vulnerable function actually get called?** A CVE in a transitive dependency whose affected code path is never reached is a lower priority than one you invoke directly. Say which it is rather than pasting the advisory.
- **Does every dependency exist and is it the one intended?** Typosquats and hallucinated package names both resolve to something.

Severity: a high or critical CVE in a direct dependency on a reachable path is critical. Install scripts in production dependencies, or a missing application lockfile, are high. A CVE confined to dev dependencies is medium at most, because it needs a developer machine compromise first.

## Step 5: CI/CD pipeline

The pipeline holds every secret the deploy needs and usually gets less review than the code. Worth its own pass.

For each workflow file, check:

- **`pull_request_target` combined with a checkout of the pull request's code.** This runs a fork's code with write permissions and repository secrets in scope. Critical. Without the PR checkout it is fine, so read the checkout step before reporting.
- **Untrusted event data interpolated into a `run:` block.** A PR title or issue body pasted into a shell line is command injection with the runner's token. Critical.
- **Third party actions not pinned to a commit SHA.** A tag can be moved to point at new code. High for third party actions; lower for first party ones from the platform vendor, though still worth pinning.
- **Secrets exposed as environment variables** across a whole job rather than scoped to the step that needs them. They reach every command in the job, including dependency install scripts.
- **Who can change the workflow.** No review requirement on pipeline files means anyone who can merge can exfiltrate every secret.

The same questions apply to any pipeline, not just GitHub Actions: what runs untrusted input, with which credentials, and who can change it.

## Step 6: The code pass

Work the OWASP Top 10 through `security-hardening` rather than repeating it here. Audit specific notes:

- Start from the attack surface list in Step 2 and work it, rather than reading files in whatever order the tool returned them.
- Missing authorization is the finding you are most likely to have. Check ownership enforcement on every endpoint that takes an ID.
- Trace one full request path end to end before generalising. Pattern matching across a codebase produces confident nonsense when the framework already handles something centrally.

## Step 7: Throw most of it away

Every candidate goes through this filter before it reaches the report.

**Discard outright:**

| Class | Why |
|---|---|
| Denial of service, resource exhaustion, missing rate limits | Real concerns, but capacity work, not an audit finding. Unbounded spend against a paid API is a finding, as cost, not as DoS |
| Memory, CPU, or file descriptor exhaustion | Same |
| Memory safety in a memory safe language | Not a thing |
| Missing hardening with no concrete vulnerability | "Could add a header" is advice, not a finding |
| Timing attacks and races with no concrete path | Unless you can describe the sequence that exploits it |
| Log spoofing, missing audit logs | Operability, covered by `observability` |
| Findings only in test files not imported by production code | No path to reach them |
| Input validation on a field with no proven impact | Validate anyway, but it is not a finding |
| CVEs already counted in Step 4 | Report once, in the dependency section |
| Weak randomness outside a security context | A UI element id does not need entropy |
| Local development compose and Dockerfiles | Unless referenced by a production deploy path |

**Precedents worth holding, because they come up every time:**

- Logging a secret in plaintext is a finding. Logging a URL is not.
- Environment variables and CLI flags are trusted input. The person setting them already has the machine.
- UUIDs are unguessable. Missing validation on one is not access control.
- Client side code does not enforce authorization. That is the server's job, and its absence in the client is not a finding.
- React and Angular escape by default. Only the explicit escape hatches are worth flagging.
- Server side request forgery where the attacker controls only the path, not the host or scheme, is not SSRF.
- Shell interpolation needs a real untrusted input reaching it. Trace the path before calling it injection.

## Step 8: Prove it before you report it

For each finding that clears the gate, confirm it by reading code, not by attacking anything.

- **Secrets:** check the format is a real key shape. Never call the live API.
- **Webhooks:** find the signature check in the middleware chain before claiming it is missing. Never send a forged request to a running service.
- **SSRF:** trace URL construction from the input to the request call, and check what validation sits between. Never make the request.
- **CI/CD:** read the workflow and confirm the dangerous trigger actually checks out untrusted code.
- **Dependencies:** check whether the affected function is imported and called. If not, say the path is unconfirmed rather than implying it is exploitable.

Label each finding `verified` (traced it) or `unconfirmed` (pattern match). Never let an unconfirmed finding read like a verified one.

Do not run exploits against systems in use, and do not test credentials you find, even ones you believe are dead. An audit that causes an incident is worse than no audit.

## Step 9: Look for siblings

One confirmed finding usually has company. Whoever wrote that endpoint wrote others the same way.

When a finding is verified, extract the pattern and search the codebase for it. A single confirmed missing ownership check is a reason to check every handler that takes an ID. Report the siblings as their own findings and say which original they came from.

## Step 10: Report

For each finding: severity, confidence, verified or unconfirmed, file and line, what an attacker does with it, and the fix. Concrete inputs and a concrete outcome, not a category name.

Order by severity. State what you did not cover and what you could not verify, so the reader knows the shape of the gap rather than assuming there is none.

An audit that found nothing says so plainly, and lists what was checked. That is a real result. Padding it with advisory items to look thorough trains the reader to skim the next one.

`references/audit-commands.md` holds the per ecosystem commands and a report template.

## Common rationalizations

| Claim | Reality |
|---|---|
| "That key was rotated" | It was still exposed. Confirm the rotation happened, then confirm the old one is dead |
| "It is only in the git history" | The history is the repository. Every clone has it |
| "The scanner would have caught it" | Scanners find patterns. Missing authorization has no pattern |
| "Nobody can reach that endpoint" | Verify the network path. Internal is one credential away from external |
| "That workflow only runs on our PRs" | Read the trigger. `pull_request_target` fires for forks |
| "It is a dev dependency" | It runs on developer machines and CI runners, both of which hold credentials |
| "We would notice" | Check whether anything alerts on it. Usually nothing does |
| "The audit found forty issues" | Then it found six and buried them |

## Red flags

- A repository with no secret scanning in CI and no pre-commit hook
- A tracked `.env`, or a `.gitignore` that does not cover one
- Third party actions referenced by tag rather than commit SHA
- `pull_request_target` in any workflow that checks out the pull request
- Event payload fields interpolated directly into a shell step
- Production dependencies with install scripts nobody has read
- An application repository with no committed lockfile
- Admin, debug, or metrics endpoints with no authentication in front of them
- A webhook handler that parses the body before checking the signature
- Any finding in your own draft report that you cannot describe an exploit for

Method adapted from gstack by Garry Tan (MIT), specifically its confidence gating and false positive filtering.
