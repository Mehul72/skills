---
name: api-change-review
description: >-
  Review a change to an API contract for compatibility before it ships, across REST/JSON,
  gRPC/protobuf, or Thrift IDL. Catches breaking changes, wrong field numbering, missing
  pagination, weak error models, and non-idempotent writes. Use when adding or changing an
  endpoint or RPC, editing a .proto or .thrift file, versioning or deprecating an API, or
  reviewing an API design or PR that touches a public contract.
---

# API Change Review

An API contract is a promise to code you cannot see and cannot redeploy. The reviewer's job is to find every way this change breaks a client that is still running the old version, because at least one always is.

Not for: retiring the old contract once the new one lands (use `deprecation`), or the schema change behind it (use `migration-safety`).

## Step 1: Identify the blast radius

Before judging anything, establish:

- **Who consumes this?** Internal services only, mobile apps you can't force-update, third parties, or all three. Mobile clients live in the field for *years*; a change that is fine for internal RPC is permanent for an app.
- **Is it already released?** An unreleased endpoint can change freely. Say so and move on. Don't apply release discipline to code nobody calls.
- **Can you verify?** Grep the monorepo for callers, check API gateway logs for actual traffic per field/endpoint. "Nobody uses that field" is a claim to verify, not assume.

## Step 2: Check for breaking changes

Compatibility has three layers, and all three matter:

- **Wire compatibility:** old bytes still deserialize.
- **Source compatibility:** regenerated client stubs still compile.
- **Semantic compatibility:** the same request still means the same thing.

Wire-compatible is not enough. Changing a field's meaning while keeping its type breaks clients silently, which is worse than breaking them loudly.

### Always breaking, in every protocol

- Removing or renaming a field, method, endpoint, or service
- Making an optional field required, or adding a new required field
- Narrowing an accepted value range, string length, or enum set
- Changing a field's type, including "compatible" widenings like `int32` → `int64`, which break generated code
- Changing the format of an existing value (an ID's shape, a timestamp's precision, a resource-name pattern)
- Changing a default value, or whether an absent field is serialized
- Changing pagination, sort order, or filtering semantics
- Adding a new enum value that old clients will receive, old clients have no case for it. Safe to *accept* a new value, breaking to *return* one, unless clients were built to tolerate unknowns from day one
- Tightening validation on an existing field, yesterday's accepted request starts 400ing
- **Changing observable behavior clients depend on, even if undocumented.** If it was observable, someone depends on it.

Per-protocol specifics, field numbering, reserved tags, oneof rules, JSON encoding, are in `references/protocols.md`. Load it for any `.proto` or `.thrift` review.

### Safe, generally

- Adding a new optional field (with a new tag number)
- Adding a new method, endpoint, or message type
- Adding a new enum value that only clients *send*
- Relaxing validation
- Adding a new optional query parameter with a backwards-compatible default

## Step 3: Review the design, not just the diff

Compatibility is the floor. These are the things that get regretted later:

**Pagination.** Any endpoint returning a list needs it from day one, retrofitting pagination is itself a breaking change. Prefer cursor/keyset over offset: offset pagination degrades linearly with page depth and skips or duplicates rows when the underlying data shifts between calls. Return an opaque `next_page_token`; never document its internal structure, or clients will parse it and you can never change it.

**Every list endpoint needs a bounded default and a maximum.** An unbounded list endpoint is a denial-of-service vector against your own database.

**Error model.** One consistent shape across the whole API: a stable machine-readable code, a human-readable message, and a request/trace ID. The code is the contract, clients switch on it, so it can never change meaning. The message is for humans and can. Never make clients string-match on the message. Map to correct status codes: 400 for malformed, 401 unauthenticated, 403 unauthorized, 404 missing, 409 conflict, 422 semantically invalid, 429 rate-limited (with `Retry-After`), 503 for shed load.

**Idempotency.** Every write that a client may retry needs to be safe to retry, and clients *will* retry, because timeouts are indistinguishable from failures. Accept a client-supplied idempotency key on non-idempotent creates, store it with the result, and return the original response on replay. Without this, every network blip becomes a duplicate order. State the key's retention window in the contract.

**Nullability and absence.** Distinguish "field not sent", "field explicitly null", and "field set to zero". In proto3 an unset scalar and a zero are the same on the wire, if the difference matters for a partial update, use `optional` (which restores presence tracking) or a `FieldMask`. Getting this wrong turns partial updates into accidental data deletion.

**Timestamps and money.** Timestamps: RFC 3339 with explicit offset, UTC. Never a bare local datetime. Money: integer minor units plus a currency code, never a float.

**Enums over booleans.** A boolean that might one day have a third state is a breaking change waiting to happen. `status: ACTIVE|PAUSED` costs nothing now and saves a migration later.

**Unbounded fields.** Any field a client controls needs a documented maximum length, and any collection a documented maximum size. Note that you can tighten these only by breaking clients, so set them at design time, deliberately.

## Step 4: Check the rollout

- **Versioning:** major version in the URL path (`/v2/`) or the proto package (`v1` → `v2`). Never version by header alone; it makes routing, caching, and debugging harder for everyone.
- **Deprecation:** mark deprecated (`[deprecated = true]`, `Deprecation`/`Sunset` headers), announce a date, then measure real traffic on the old path before removing it. Removal is gated on the traffic hitting zero, not on the date passing.
- **Server before client.** The server must accept the new field before any client sends it, and keep accepting the old one until every client stops. Same expand/contract shape as a schema migration.
- **Contract test.** If the repo has a checked-in schema, the diff should be enforced in CI, `buf breaking` for protobuf, an OpenAPI diff tool for REST. A human reviewer is not a substitute for the check.

## Output

Report, per change: what it is, whether it is breaking (and at which layer, wire, source, or semantic), which consumers it breaks, and the compatible alternative.

Separate **blocking** findings (breaks a live client) from **design** findings (works, but will be regretted). Don't bury a wire-format break in a list of naming nits.

If nothing is breaking, say so plainly rather than manufacturing findings.
