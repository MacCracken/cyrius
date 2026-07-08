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

## Investigation 2026-07-08 (v6.4.22) — the consumer's two-struct hypothesis is DISPROVEN; it's subtler

Reproduced against the live stiva repo: reverting the dodge (`exit_status` →
`exit_code` in `src/container.cyr`, 3 lines) makes `tests/runpath.tcyr` **fail to
compile** — `error:<source>:501: unexpected ','` — where clean it passes 171 tests.
So the bug is real and reproduces. BUT the root cause is NOT what was filed:

- **It is NOT the two-struct field-name collision.** Renaming the *other* struct's
  field (`ContainerExecResult.exit_code` → `exec_rc` in `runtime.cyr`) while keeping
  `Container.exit_code` **still errors**. So the trigger is `Container.exit_code`
  *alone* in the large unit, not a pair colliding at 72-vs-0.
- **It does NOT reproduce minimally.** Every small repro resolves correctly: single
  struct `.exit_code` read; two structs sharing `exit_code` at different offsets
  (both declaration orders); field-name == parameter-name shadowing;
  store-in-one-fn / read-in-another. All return the right value. The issue's "small
  repros don't trigger" is confirmed — it's purely size/shape-dependent.
- **The field-resolution code is correct + capped.** `FINDFIELD`/`FIELDOFF`
  (parse_types.cyr) resolve per-struct-type via `field_base[si]`; the packed field
  pool (`0x92A000`, 8192 entries) and struct tables (1024) have hard caps that
  **ERROR** on overflow, not silently corrupt. There is no global name→offset table.
- **Manifestation shifted** vs the filing (silent wrong read on the consumer's
  v6.4.19 → a parse error on v6.4.22), and `exit_status` (11 bytes, unique) vs
  `exit_code` (9 bytes, already used as var/param names elsewhere) differ in
  identifier-buffer / dedup footprint — pointing at a **buffer/table BOUNDARY
  interaction at scale**, not a simple offset collision.
- **Localization is blocked without cycc-internal instrumentation.** cycc reports
  `<source>:501` against its post-`#ifdef`/comment-stripped `preprocess_out`, a
  coordinate system a naive include-expansion doesn't match (line 501 there lands in
  an `lib/alloc.cyr` comment). Pinning it needs a cycc preprocess-dump or
  many-iteration bisection of the full 25-module + 6-dep-bundle unit (~150 s/build).

**Reframed scope:** this is a subtle size-dependent preprocessor/buffer-boundary bug,
materially harder to root-cause than the "key the fast-path table by (structType,
fieldName)" fix the filing suggested (that table doesn't exist). Needs a dedicated
deep-dive with cycc instrumentation, not a clean patch bite. stiva stays on the
rename-dodge in the meantime (no consumer currently blocked).

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
