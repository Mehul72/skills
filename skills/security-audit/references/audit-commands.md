# Audit commands and report template

Commands to run during a `security-audit` pass. Every one is read only. Nothing here
sends a request to a running service or tests a credential.

## Secrets in git history

```bash
# By credential prefix. -S finds commits where the count of the string changed,
# -G matches the diff text against a regex, which catches edits as well as additions.
git log -p --all -S 'AKIA' -- '*.env' '*.yml' '*.yaml' '*.json' '*.tf'
git log -p --all -G 'sk-[a-zA-Z0-9]{20}|sk_live_|pk_live_'
git log -p --all -G 'ghp_|gho_|ghu_|ghs_|github_pat_'
git log -p --all -G 'xoxb-|xoxp-|xapp-|xoxa-'
git log -p --all -G 'AIza[0-9A-Za-z_-]{35}'
git log -p --all -G '-----BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----'
git log -p --all -G 'eyJhbGciOi'
git log -p --all -G 'postgres://[^:]+:[^@]+@|mysql://[^:]+:[^@]+@|mongodb(\+srv)?://[^:]+:[^@]+@'

# Generic words, kept to config files so the result stays readable.
git log -p --all -G 'password|passwd|secret|api_key|apikey|access_token' \
  -- '*.env' '*.yml' '*.yaml' '*.json' '*.conf' '*.ini' '*.properties' '*.tfvars'

# Everything ever committed at a path that looks like a credential file.
git log --all --diff-filter=A --name-only --format='%H %ad' --date=short \
  | grep -iE '\.(env|pem|key|p12|pfx|keystore|jks)$|credentials|id_rsa'
```

Present state:

```bash
git ls-files '*.env' '.env.*' '*.pem' '*.key' '*.p12' '*.pfx' \
  | grep -vE '\.(example|sample|template|dist)$'

grep -qE '^\.env($|\.)' .gitignore || echo 'WARNING: .env is not gitignored'

# Anything staged right now that should not be.
git diff --cached --name-only | grep -iE '\.env$|\.pem$|\.key$|credentials'
```

Dedicated scanners find more than grep and are worth running when available:
`gitleaks detect --no-git=false`, `trufflehog git file://.`, `git-secrets --scan-history`.

## Dependencies

| Ecosystem | Manifest | Audit | Outdated |
|---|---|---|---|
| Node | `package.json` | `npm audit --omit=dev` | `npm outdated` |
| Python | `pyproject.toml`, `requirements.txt` | `pip-audit` | `pip list --outdated` |
| Go | `go.mod` | `govulncheck ./...` | `go list -m -u all` |
| Rust | `Cargo.toml` | `cargo audit` | `cargo outdated` |
| Ruby | `Gemfile` | `bundle audit check --update` | `bundle outdated` |
| Java | `pom.xml`, `build.gradle` | `mvn dependency-check:check` | `mvn versions:display-dependency-updates` |
| PHP | `composer.json` | `composer audit` | `composer outdated` |

Lockfile committed, which is a finding for an application and not for a library:

```bash
for f in package-lock.json yarn.lock pnpm-lock.yaml bun.lock poetry.lock \
         Cargo.lock Gemfile.lock composer.lock go.sum uv.lock; do
  [ -f "$f" ] && { git ls-files --error-unmatch "$f" >/dev/null 2>&1 \
    && echo "tracked:   $f" || echo "UNTRACKED: $f"; }
done
```

Install scripts in production dependencies, which run on every machine that installs:

```bash
# Needs a hydrated node_modules. Lists production packages with lifecycle hooks.
npm ls --omit=dev --parseable --all 2>/dev/null | sort -u | while read -r d; do
  [ -f "$d/package.json" ] || continue
  node -e '
    const p = require(process.argv[1] + "/package.json");
    const s = p.scripts || {};
    const hooks = ["preinstall", "install", "postinstall"].filter(h => s[h]);
    if (hooks.length) console.log(p.name, hooks.join(","), JSON.stringify(s[hooks[0]]));
  ' "$d"
done
```

## CI/CD

```bash
WF=$(find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)

# Runs fork code with write scope and repository secrets. Critical only when the
# workflow also checks out the pull request's ref, so read the checkout step.
grep -ln 'pull_request_target' $WF

# Untrusted event data interpolated into a shell line.
grep -nE 'github\.event\.(issue|pull_request|comment|review)\.(title|body)' $WF

# Third party actions referenced by a movable tag rather than a commit SHA.
grep -hoE 'uses:[[:space:]]*[^[:space:]]+' $WF | sort -u | grep -vE '@[0-9a-f]{40}$'

# Secrets scoped to a whole job rather than the step that needs them.
grep -nE '^\s+[A-Z_]+:\s*\$\{\{\s*secrets\.' $WF

# Who can change the pipeline.
[ -f .github/CODEOWNERS ] && grep -n 'workflows' .github/CODEOWNERS \
  || echo 'no CODEOWNERS entry for workflow files'
```

Also check `.gitlab-ci.yml`, `.circleci/config.yml`, `Jenkinsfile`, and
`azure-pipelines.yml` for the same four questions: what runs untrusted input, with
which credentials, at what scope, and who can change it.

## Infrastructure config

```bash
# Containers running as root in a production image.
grep -Ln '^USER ' $(git ls-files 'Dockerfile*' | grep -viE 'dev|local|test')

# Permissive network rules.
git ls-files '*.tf' '*.tfvars' | xargs grep -nE '0\.0\.0\.0/0|::/0' 2>/dev/null

# Public storage.
git ls-files '*.tf' | xargs grep -nE 'acl\s*=\s*"public-read|public_access_block' 2>/dev/null

# Kubernetes workloads with no security context or running privileged.
git ls-files '*.yaml' '*.yml' | xargs grep -ln 'kind:\s*\(Deployment\|StatefulSet\|DaemonSet\)' 2>/dev/null \
  | xargs grep -Ln 'securityContext' 2>/dev/null
```

## Report template

```markdown
# Security audit: <repo> @ <commit>

Date, mode (routine or deep), confidence gate, and what was covered.

## Summary

<n> findings: <n> critical, <n> high, <n> medium.
Not covered: <areas, and why>.
Could not verify: <findings that stayed unconfirmed, and what would settle them>.

## Findings

### 1. <what an attacker achieves, not the category name>

- Severity: critical | high | medium
- Confidence: n/10, verified | unconfirmed
- Location: path/to/file.ext:LINE
- Attack: the concrete sequence. Who sends what, and what they get back.
- Fix: the specific change.
- Siblings: same pattern found at <paths>, or none found.

## Checked and clean

The areas worked through that produced nothing, so the reader can tell an
unexamined area from an examined one.

## Tools unavailable

Scanners not installed, and what would have been covered had they run.
```

Severity is about the outcome, not the category. Missing authorization on a health
check endpoint and missing authorization on a funds transfer are the same class and
nowhere near the same finding.
