---
name: security-hardening
description: Harden code against the OWASP Top 10 2025 before it ships, and review existing code for the vulnerability classes that generated code most often gets wrong. Covers missing authorization, injection, secrets handling, misconfiguration, dependency risk, and fail-open error handling. Use when writing or reviewing an endpoint, auth logic, a query, file upload, deserialization, or config; when handling user input or secrets; or on any mention of security, vulnerability, injection, authz, or hardening.
---

# Security Hardening

Two facts shape this skill.

First, the default failure is omission, not error. Generated code implements the path that was asked for and quietly skips the check nobody mentioned. Missing authorization looks exactly like working code in every test you would think to write.

Second, security bugs do not surface in normal use. They surface when someone goes looking. So this is a checklist discipline, not an intuition one.

Not for: reviewing a diff for correctness or clarity, which is `code-quality`. Not for a live compromise, which is `incident-response`.

## Step 1: Name the trust boundary

Before reviewing anything, answer three questions.

**What is untrusted here?** Request bodies, query params, headers, cookies, path segments, uploaded files, webhook payloads, message queue contents, third party API responses, and anything read back from the database that a user once wrote. That last one gets missed constantly. Data does not become trustworthy by making a round trip through storage.

**Who is the caller allowed to be?** Authenticated, and authorized for this specific object. Those are separate checks and the second one is the one that gets skipped.

**What is the blast radius if this is wrong?** A read of public data and a funds transfer deserve different scrutiny.

## Step 2: Work the Top 10

OWASP Top 10:2025 is the current list. Two categories are new in this revision, and SSRF has been folded into A01.

### A01 Broken Access Control

Still number one, and the most common serious flaw in generated code.

- **Every endpoint checks authorization, not just authentication.** A valid token proves who you are, never what you may touch.
- **Check ownership on the object, not the ID in the request.** `GET /orders/{id}` must verify this order belongs to this caller. Otherwise incrementing the ID walks the whole table. This is IDOR and it is everywhere.
- **Deny by default.** New endpoints start closed. A route that is public because nobody added a guard is an outage waiting to be discovered by someone else.
- **Enforce server side.** A hidden field, a disabled button, or a client side role check is decoration.
- **Never trust a user supplied role, tenant, or price.** Read those from the session or the database.
- **SSRF now lives here.** Any URL a user can influence, including webhooks, image fetchers, and PDF renderers, must go through an allowlist. Block link local and private ranges, and re-check after redirects. Blocklists get bypassed with DNS rebinding and alternate encodings.

### A02 Security Misconfiguration

Moved up to second. Mostly things that get set to "permissive" during development and never reverted.

- Debug mode, stack traces, and directory listings off in production.
- CORS restricted to specific origins. `Access-Control-Allow-Origin: *` combined with credentials is a data leak.
- Default credentials changed, admin panels not publicly reachable.
- Security headers set: HSTS, `X-Content-Type-Options: nosniff`, a real CSP, `X-Frame-Options` or `frame-ancestors`.
- Cloud storage buckets not public. Check the actual policy, not the intent.
- Verbose errors never reach the client. See A10.

### A03 Software Supply Chain Failures

New category.

- Pin exact versions and commit the lockfile. A floating range means the build is not reproducible and a compromised patch release ships silently.
- Run the ecosystem audit (`npm audit`, `pip-audit`, `govulncheck`, `cargo audit`) in CI, and fail the build on high and critical.
- **Verify every dependency exists and is the one you meant.** Generated code sometimes names packages that do not exist or that resemble a real one. Typosquats rely on exactly that.
- Prefer fewer dependencies. A one function package is a supply chain entry with a maintainer you do not know.

### A04 Cryptographic Failures

- **Never invent crypto.** Use the platform library and a vetted mode.
- Passwords hashed with argon2id, scrypt, or bcrypt. Never MD5, SHA-1, or a bare SHA-256.
- TLS everywhere including internal hops. Never disable certificate verification, not even in a comment marked temporary.
- AES-GCM or ChaCha20-Poly1305, never ECB. Never reuse a nonce.
- Secrets come from a secret manager or the environment, never from source, never from a config file in the repo.
- `crypto.randomBytes` and equivalents for tokens. `Math.random()` and `rand()` are predictable.
- Compare secrets and MACs with a constant time function, not `==`.

### A05 Injection

- **Parameterized queries, always.** Not escaping, not a sanitizer, not an ORM method that takes a raw fragment. If you are concatenating a string into SQL, that is the bug.
- Table and column names cannot be parameterized. If one must be dynamic, validate it against a hardcoded allowlist.
- Command execution: pass an argument array, never a shell string. Better, use a library instead of shelling out.
- Output encoding is context specific. HTML body, attribute, JavaScript, URL, and CSS each need different treatment. Use the framework's escaping and never build HTML by concatenation. `dangerouslySetInnerHTML`, `v-html`, and `innerHTML` all need a sanitizer such as DOMPurify.
- Same discipline for LDAP, XPath, NoSQL operators, template engines, and log lines.

### A06 Insecure Design

Flaws no amount of careful implementation fixes.

- Rate limit authentication, password reset, OTP, and anything expensive. Per account and per IP.
- Enforce business limits server side: withdrawal caps, quantity bounds, refund windows.
- Design the abuse case, not just the happy path. Ask what a motivated user does with this endpoint in a loop.

### A07 Authentication Failures

- Session token regenerated on login and on privilege change.
- Cookies `HttpOnly`, `Secure`, `SameSite`.
- Real logout that invalidates server side.
- MFA on anything privileged.
- Generic failure messages. "Invalid email or password" and not "no such user", which enumerates accounts.
- JWT: verify the signature, pin the algorithm, reject `alg: none`, check `exp`, `aud`, and `iss`. Never trust the header to select the algorithm. Remember that a JWT cannot be revoked before expiry, so keep access tokens short lived.
- Password reset tokens single use, short lived, and random.

### A08 Software or Data Integrity Failures

- **Never deserialize untrusted data into arbitrary types.** Python `pickle`, Java native serialization, PHP `unserialize`, and YAML with an unsafe loader are all remote code execution. Use JSON with an explicit schema.
- Verify signatures on anything auto updated or fetched at runtime.
- Validate webhook signatures before acting on the payload.

### A09 Security Logging and Alerting Failures

- Log authentication attempts, authorization denials, and privileged actions with actor, action, target, and time.
- **Never log secrets, tokens, passwords, or full card numbers.** Watch the indirect paths: a struct printed with `%+v`, an error string carrying a connection URL, a stack trace with arguments.
- Make sure someone is actually alerted. See `observability`.

### A10 Mishandling of Exceptional Conditions

New category, and the one most relevant to generated code.

- **Fail closed.** An error in an authorization check must deny. A `catch` that logs and continues past a failed permission check is a full bypass.
- **Never swallow an exception.** An empty `catch`, a bare `except: pass`, or an ignored error return hides the failure and leaves the system in an undefined state.
- **Do not leak internals in errors.** Stack traces, SQL fragments, file paths, and dependency versions are reconnaissance. Return a generic message plus a correlation ID, and log the detail server side.
- Handle partial failure explicitly. If step three of five fails, say what happens to the first two.
- Check every error return. In Go, an ignored `err` is the single most common source of this class.

## Step 3: Validate input properly

- **Validate at the trust boundary, on the server**, before the value reaches business logic.
- **Allowlist, not blocklist.** Define what is acceptable and reject everything else. Blocklists are always incomplete.
- Validate type, length, range, and format. Every string a client controls needs a maximum length.
- Canonicalize before validating, or `../` and Unicode tricks slip past.
- File uploads: verify content type by inspecting the bytes rather than trusting the header or extension, cap the size, generate your own filename, and store outside the web root.
- Path parameters: resolve the final path and confirm it is inside the intended directory.

## Step 4: Verify

- Run the ecosystem audit and a static analysis pass (Semgrep, CodeQL, `gosec`, `bandit`).
- Secret scanning in CI plus a pre-commit hook. Rotate anything that ever reached a commit, because history is forever.
- Write the negative tests. Wrong user, missing token, expired token, malformed input, oversized input. A test suite that only proves the happy path proves nothing about security.
- For authorization specifically, test as user B against user A's object. That single test catches most IDOR.

`references/checklist.md` holds the per language notes and the review checklist.

## Common rationalizations

| Claim | Reality |
|---|---|
| "It is an internal service" | Internal is one SSRF or one compromised credential away from external. Assume the network is hostile |
| "The frontend validates it" | The frontend is a suggestion. Anyone can call the API directly |
| "The ORM prevents injection" | Only for parameterized paths. Raw fragments and dynamic column names bypass it |
| "We will add auth checks later" | Later is after the endpoint is live and being called |
| "The input comes from our own database" | A user wrote it. Storage does not sanitize |
| "It is behind a login" | Authentication is not authorization. Any logged in user can now reach it |
| "We sanitize the input" | Sanitizing is lossy and bypassable. Parameterize and encode on output |
| "Nobody knows this endpoint exists" | Scanners find it within hours of it being reachable |

## Red flags

- A handler that reads an ID from the request and queries it with no ownership check
- String concatenation or f-string interpolation building SQL
- `catch` or `except` with an empty body, or a discarded error return
- A permission check inside a `try` whose `catch` continues
- Any credential, key, or token literal in source
- `verify=False`, `rejectUnauthorized: false`, or a disabled certificate check
- `Access-Control-Allow-Origin: *` alongside credentials
- Deserialization of user input with `pickle`, `yaml.load`, or native deserialization
- A raw exception or stack trace returned in a response body
- A dependency added without a pinned version, or one you have not confirmed exists
- Login or reset endpoints with no rate limit
