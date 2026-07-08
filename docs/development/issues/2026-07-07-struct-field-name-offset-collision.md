# Struct field READ mis-resolves when two structs share a field name at different offsets

- **Filed**: 2026-07-07 (found wiring stiva's container-state serde; a JSON
  round-trip silently dropped `exit_code`).
- **Severity**: P1 (silent wrong value — no error, no crash; data corruption).
- **Component**: cycc struct-field offset resolution (the `var x: T = p; x.field`
  read path), in a large multi-module compilation unit.

## Symptom

Two structs in the same program declare a field with the **same name** but at
**different byte offsets**:

```
struct Container         { id; name; image_id; image_ref; state; pid;
                           created_at; started_at; config; exit_code; }  # exit_code @ +72
struct ContainerExecResult { exit_code; stdout; stderr; duration_ms; timed_out; } # exit_code @ +0
```

Reading `Container.exit_code` via a typed annotation returns **0** (the wrong
offset), even though the value is correctly stored at +72:

```
var c = container_new(..., /*exit_code*/ 7);   # WRITE: store64(c+72, 7) — correct
load64(c + 72)      == 7                         # raw read: correct
var ct: Container = c; ct.exit_code   == 0       # annotated READ: WRONG (reads as if offset 0)
```

The **write** (`c.exit_code = 7`) lowers correctly to `store64(c+72, …)`. Only the
**read** (`ct.exit_code`) mis-resolves. The serialized JSON showed `"exit_code": 0`
where it should be 7; on parse-back the 0 propagated, silently corrupting the record.

## Key detail: only manifests in a LARGE compilation unit

Small standalone reproductions do **not** trigger it. I built ~5 isolated programs
that construct the same `Container`, call the same serializer, and read
`ct.exit_code` — all returned 7 correctly, including programs that used BOTH
`Container.exit_code` and `ContainerExecResult.exit_code` in one `main`, and in
separate functions.

It reproduced **only** in the full stiva test compilation
(`tests/runpath.tcyr`: 25 included modules + 6 AGNOS dep bundles + ~40 test
functions, both structs' `.exit_code` accessed across many functions). There,
`container_to_jv`'s `ct.exit_code` read yielded 0 while `container_new`'s
`c.exit_code =` write, a few functions away, stored to +72 correctly. So the
offset chosen for the name `exit_code` appears to be resolved **globally/per-unit**
(one winner across the whole compilation) rather than per-annotation — and which
one "wins" depends on the size/shape of the unit, so it's latent until a program
grows past some threshold.

This mirrors the enum-member model ("hoisted globals, last-def-wins") — if struct
field-name→offset shares that global table, any two structs with a same-named
field at different offsets are a landmine, and the codebase has many
(`id`, `name`, `size_bytes`, `digest`, `state`, …). Most survive because the
colliding fields happen to sit at the SAME offset in every struct that has them;
`exit_code` (72 vs 0) is the first with a real offset conflict.

## Consumer workaround applied (stiva)

Renamed the Cyrius field `Container.exit_code` → `Container.exit_status` (unique
name; the JSON key stays `"exit_code"` for Rust-serde parity). With the name no
longer colliding, both structs' reads resolve correctly and the 847-test suite is
green. This is a rename-to-dodge, not a fix.

## Suggested direction (compiler-side)

- Field offsets must be resolved **per struct type via the variable's annotation**,
  never from a global name→offset table. If a global table is used as a fast path,
  it must be keyed by `(structType, fieldName)`, not `fieldName` alone.
- A diagnostic when two in-scope structs declare the same field name at different
  offsets would have turned this silent corruption into a compile-time warning.
- Test matrix: two structs, same field name, offsets A≠B, read via annotation on
  both — in a unit large enough to exercise whatever threshold flips the resolution.

Filed from the stiva port; the language was not modified. The consumer renamed the
field to avoid the collision.
