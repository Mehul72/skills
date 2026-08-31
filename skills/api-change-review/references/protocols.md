# Per-Protocol Compatibility Rules

## Protobuf / gRPC

### Field numbers are the contract

The wire format carries **tag numbers, not names**. This inverts the usual intuition:

- **Renaming a field is wire-safe** (same tag) but **source-breaking**, every generated stub that referenced the old name fails to compile.
- **Reusing a tag number is catastrophic.** Old clients deserialize new data into the old field's type. Silent corruption, no error.
- Reserve tags and names on removal, always:
  ```protobuf
  message User {
    reserved 4, 7 to 9;
    reserved "email", "legacy_id";
  }
  ```
  Without `reserved`, someone reuses tag 4 in six months and no tool will stop them.
- Tags 1-15 use one byte, 16-2047 use two. Spend the single-byte tags on frequently-set fields.

### Type changes

Wire-compatible pairs (same wire type, old bytes still parse):
`int32` ↔ `int64` ↔ `uint32` ↔ `uint64` ↔ `bool` ↔ `enum` (all varint);
`sint32` ↔ `sint64`; `fixed32` ↔ `sfixed32`; `fixed64` ↔ `sfixed64`;
`string` ↔ `bytes` (when the bytes are valid UTF-8).

**But wire-compatible is not safe.** Every one of these breaks generated code in statically typed languages, and several truncate: `int64` → `int32` silently drops the high bits. `int32` → `int64` is the widening people assume is free. It is not, it is a source break. Treat all type changes as breaking; add a new field instead.

Never wire-compatible: anything crossing wire types (`int32` ↔ `fixed32`, `string` ↔ `int32`), or changing `repeated` ↔ singular.

### oneof and optional

- Moving an existing field **into or out of a `oneof`** is breaking. It changes the generated API surface (and breaks the Go protobuf stubs outright). Adding a *new* field to an existing `oneof` is safe.
- proto3 scalars have no presence by default: unset and zero-valued are indistinguishable on the wire. Mark a field `optional` to restore presence tracking. Adding `optional` to an existing field is wire-safe but changes the generated accessors, a source break.
- Merging two existing `oneof`s, or splitting one, is breaking.

### Other rules

- **Never move a message or enum between files:** it breaks generated import paths even though the wire format is identical.
- **Package renames are breaking:** the fully-qualified name appears in the gRPC method path (`/pkg.Service/Method`).
- Changing a method's streaming-ness (unary ↔ streaming) is breaking.
- Removing a service method is breaking; old clients get `UNIMPLEMENTED`.
- Enum: the zero value must be `_UNSPECIFIED` and must never be reused. Adding values is safe for what you *receive*, breaking for what you *return* to clients without an unknown-value path.
- Deleting a field without `reserved` is the single most dangerous edit in a `.proto` file.

### Enforce it in CI

```bash
buf breaking --against '.git#branch=main'
```

Run it on every PR touching a `.proto`. Human review does not reliably catch tag reuse.

## Apache Thrift

Same tag-number model as protobuf, with sharper edges:

- Field IDs are the contract. Never reuse an ID; Thrift has no `reserved` keyword, so record retired IDs in a comment and enforce it in review.
- **Always number fields explicitly.** Thrift auto-assigns negative IDs to unnumbered fields, and the assignment shifts when you insert a field, silently repointing every field after it.
- `required` is a trap: a `required` field can never be removed, and a peer that omits it fails to deserialize entirely. Prefer `optional` for everything new. Changing `optional` → `required` is breaking; `required` → `optional` breaks old readers that expect it present.
- Changing a field's type is breaking even between numeric widths, Thrift's binary protocol encodes the type byte, so a mismatch is a hard deserialization failure, not a silent truncation.
- Adding a field to a struct is safe. Adding a parameter to a service method is safe if optional; changing the return type is breaking.
- Adding a new exception to a method's `throws` clause is breaking for clients that don't handle it.
- Renaming a service or method is breaking (the name is on the wire).

## REST / JSON

JSON has no tags, so **field names are the contract** and every rename is breaking.

**Safe:**
- Adding a new optional field to a response, *provided* clients ignore unknown fields. Verify this: strict deserializers (some Java/Go/Swift configs) reject unknown fields and will break. Check before assuming.
- Adding a new optional request field with a backwards-compatible default.
- Adding a new endpoint.
- Relaxing validation.

**Breaking:**
- Renaming or removing any field, including nested ones.
- Changing a JSON type, notably `123` → `"123"`. Watch for large integers: IDs above 2^53 lose precision in JavaScript clients, so return them as strings from the start.
- Changing null handling, omitting a field that was previously `null`, or vice versa. Pick one and never change it.
- Changing an array's element shape or its ordering guarantee.
- Changing a status code for an existing condition.
- Changing a resource identifier's format.
- Turning a scalar into an object (`"owner": "u_1"` → `"owner": {"id": "u_1"}`). Add a new field instead.

**HTTP semantics to check:**
- `GET`, `HEAD`, `PUT`, `DELETE` must be idempotent; `GET` and `HEAD` must have no side effects. A `GET` that mutates will be triggered by a crawler, a prefetcher, or a retry.
- `POST` is not idempotent, require an idempotency key for retryable creates.
- `PATCH` needs a defined semantic: JSON Merge Patch (RFC 7386) or JSON Patch (RFC 6902). "We made one up" is a bug report waiting to happen, particularly around clearing a field to null.
- `Cache-Control` on anything cacheable; explicit `no-store` on anything containing user data.
- Rate limits: `429` plus `Retry-After`.

### Enforce it in CI

```bash
oasdiff breaking old-openapi.yaml new-openapi.yaml
```

Requires the OpenAPI spec to be generated from the code (or the code from the spec). A hand-maintained spec drifts and gives false confidence.

## GraphQL

- Removing a field or type, or adding a non-null argument, is breaking.
- Making a nullable field non-null is safe for clients; the reverse is breaking.
- Adding an enum value is breaking for clients that exhaustively switch.
- No versioning by convention, deprecate with `@deprecated(reason:)` and track field-level usage before removal. Field-level usage tracking is not optional here; it is the only way to know what is safe to delete.
