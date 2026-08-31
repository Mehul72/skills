# Security Review Checklist

Work top to bottom on any diff that touches an endpoint, a query, auth, config, or user input.

## Per change

- [ ] Every new or changed endpoint has an authorization check, not just authentication
- [ ] Object level ownership verified against the caller, not the ID in the request
- [ ] All queries parameterized; no string built SQL anywhere in the diff
- [ ] Input validated server side at the boundary, by allowlist, with a length cap
- [ ] Output encoded for its context; no raw HTML assembly
- [ ] No secret, key, token, or credential literal
- [ ] Errors return a generic message plus a correlation ID; detail logged server side
- [ ] No empty catch, no discarded error return, no auth check that can fail open
- [ ] New dependencies pinned, confirmed to exist, and audited
- [ ] Security relevant events logged; no secrets in the log line
- [ ] Negative tests exist: wrong user, no token, expired token, malformed and oversized input

## Language specific

### Go
- Ignoring an `err` is the dominant fail open path. `errcheck` catches it.
- `database/sql` with `?` or `$1` placeholders. `fmt.Sprintf` into a query is the bug.
- `exec.Command("sh", "-c", userInput)` is command injection. Pass an argument slice.
- `html/template` escapes by context. `text/template` does not. Never use `text/template` for HTML.
- `crypto/rand`, never `math/rand`, for tokens.
- `subtle.ConstantTimeCompare` for secret comparison.
- Run `gosec` and `govulncheck` in CI.

### Python
- `pickle`, `marshal`, and `yaml.load` without `SafeLoader` on untrusted input are RCE. Use `yaml.safe_load`.
- Parameterize with `cursor.execute(sql, params)`. Never `%` or f-strings into SQL.
- `subprocess` with `shell=True` and interpolated input is command injection. Pass a list.
- Django: `.raw()` and `.extra()` bypass the ORM's protection. `mark_safe` disables escaping.
- Flask: `render_template_string` on user input is server side template injection.
- `secrets` module for tokens, never `random`.
- `hmac.compare_digest` for secret comparison.
- Run `bandit` and `pip-audit`.

### Java / Spring
- `PreparedStatement`, never string concatenation. In JPA, avoid concatenated JPQL.
- Native Java deserialization of untrusted bytes is RCE. Use JSON with an explicit type.
- Spring Security: verify method level annotations are actually applied. A misplaced `@PreAuthorize` silently does nothing.
- Disable XXE on every XML parser: `setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)`.
- `SecureRandom`, never `Random`.
- `MessageDigest.isEqual` for constant time comparison.

### Node / TypeScript
- Parameterized queries in the driver. Template literals into SQL are the bug.
- `child_process.exec` with interpolation is injection. Use `execFile` with an argument array.
- `eval`, `new Function`, and `vm` on user input are RCE.
- Prototype pollution: validate keys before merging untrusted objects. Watch `__proto__` and `constructor`.
- `crypto.randomBytes`, never `Math.random`.
- `crypto.timingSafeEqual` for secret comparison.
- Set `helmet` for security headers. Configure CORS explicitly.
- ReDoS: user controlled input against a regex with nested quantifiers hangs the event loop.

## Authorization test pattern

The one test that catches most real access control bugs:

```
create user A, create resource R owned by A
authenticate as user B
request R
expect 403 or 404, never 200
```

Repeat for read, update, delete, and list. List endpoints leak the most, because filtering by tenant is easy to forget.

## Secrets

- Scan the working tree and the full history. `gitleaks detect` and `trufflehog`.
- Any secret that reached a commit is compromised. Rotate it. Removing the commit does not help, because clones and caches persist.
- `.env` files in `.gitignore`, never committed, never in an example with a real value.
- Secret manager or injected environment variables in production.

## Config to verify before shipping

- [ ] Debug and verbose error output disabled
- [ ] Default credentials changed
- [ ] CORS restricted to known origins; not `*` with credentials
- [ ] TLS enforced, HSTS set, certificate verification enabled everywhere
- [ ] Security headers present: CSP, `nosniff`, frame protection
- [ ] Storage buckets and object ACLs verified non public
- [ ] Admin and metrics endpoints not publicly reachable
- [ ] Rate limits on auth, reset, OTP, and expensive endpoints
- [ ] Dependency audit and secret scan running in CI and failing the build
