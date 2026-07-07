# Struct-id 20/21 collides with the f64v2/f64v4 SIMD sentinels → `.field` on the 20th/21st struct is rejected as "SIMD vector has no named fields"

- **Filed**: 2026-07-06 (found porting stiva Rust→Cyrius; repro on cc 6.4.10 AND 6.4.11)
- **Severity**: P1 (High) — hard compile error that blocks *correct* programs;
  data-dependent and "spooky" (adding an unrelated struct/module anywhere breaks
  a different module's field access). Fail-closed (no memory-unsafety, no wrong
  result), but it stops any unit that crosses 20 structs and uses the
  `var x: Struct; x.field` typed-local pattern on a reachable path.
- **Scope**: pre-existing; not introduced by any recent SIMD arc. Affects the
  two *legacy flat* SIMD sentinels only (`f64v2` -20, `f64v4` -21); the newer
  descriptor-band vectors (≤ -2048) also collide with struct-ids ≥ 2048 but the
  struct-def cap (1024) fences that off, so 20/21 is the live case.

## Symptom

A struct-typed local field access —

```
var x: SomeStruct = p;
x.a = 42;               # error: SIMD vector has no named fields
```

— hard-errors **iff `SomeStruct` is the 20th or 21st struct defined in the
compilation unit**. The 19th (or 22nd) is fine. It is not the struct's contents
or the access site that matters — only its ordinal struct-id.

Because struct-ids are assigned sequentially over **every** struct in the unit
(explicit `struct`s + enum/tagged-union-generated + `Result`/`Option`/`Either` +
generic monomorphizations + all structs in the auto-prepended stdlib and
git-dep bundles), the collision lands on whichever struct is 20th/21st *overall*.
In a real build this reads as: "adding module B (or bumping a dep) broke a
`.field` access in unrelated module A" — the id numbering shifted A's struct onto
20 or 21. That is exactly how it surfaced in the stiva port: a 10-module
aggregate built green; wiring two more modules pushed one of their structs onto
id 20/21 and the build failed at that struct's first field write.

## Reproduction

Minimal, self-contained (no includes, no stdlib). Full annotated copy lives at
`stiva/docs/development/cycc-bug-struct-sid-20-21.cyr`:

```
struct S1  { a; }
struct S2  { a; }
# … S3 … S19 …
struct S20 { a; }        # the 20th struct → struct-id 20

fn main() {
    var buf[8];
    var x: S20 = &buf;   # struct-id 20 → SLTYPE -20 == f64v2 sentinel
    x.a = 42;            # error:<source>: SIMD vector has no named fields
    return x.a;
}
var r = main();
syscall(60, r);
```

Deterministic boundary:

| structs | reachably access | result |
|---|---|---|
| 20 | the 20th (id 20) | **error** — SIMD vector has no named fields |
| 21 | the 21st (id 21) | **error** — same |
| 20 | the 19th (id 19) | OK — compiles, runs, returns 5 |

Notes:
- Only a **reachable** access triggers it — a `.field` on the id-20/21 struct
  inside a DCE-eliminated function is never checked, so unreachable code masks it.
- Accessing the id-20/21 struct via `store64`/`load64` offsets or accessor fns
  (not the `var x: Struct; x.field` typed-local form) also dodges it.
- 1030 structs cleanly hits `too many struct definitions (max 1024)` — a
  different, correct error — so this is NOT the struct-def cap.

## Root cause

A struct-typed local's type is stored as `SLTYPE = (0 - struct_id)` — a negative
type word (`src/common/util.cyr`, `GLTYPE`/`SLTYPE` ~594). The two legacy SIMD
vector types reuse two of those exact negative values as flat sentinels:

```
f64v2 → -20      f64v4 → -21
```

(new vectors live in the reserved band `≤ -2048`; see `src/common/util.cyr`
~607 `_vec_desc`.) The field-access guards in `src/frontend/parse_decl.cyr`
(`PARSE_FIELD_LOAD` ~219 and `PARSE_FIELD_STORE` ~434) reject `.field` on a SIMD
local:

```
if (lt == 0 - 20 || lt == 0 - 21 || lt <= 0 - 2048) {
    ERR_MSG(S, "SIMD vector has no named fields", 31);
}
```

When `struct_id == 20`, the local's `lt` is `-20` — byte-identical to the f64v2
sentinel — so the guard fires on an ordinary struct. Same for id 21 vs f64v4.
The comment at `util.cyr` ~611 ("struct sids cap at 1024, so `0-sid` never
reaches -2048") correctly reasons about the -2048 band but does **not** account
for the two flat -20/-21 sentinels sitting *inside* the struct-id range.

## Impact

- Blocks the stiva Rust→Cyrius port (image/registry modules can't be wired;
  currently held out with the other 10 modules green — 227 tests). It will also
  block any first-party consumer whose unit crosses 20 structs (the AGNOS dep
  bundles alone define dozens), so it is a general ecosystem hazard, not
  stiva-specific.
- Silent until it bites, and bites data-dependently — a small unrelated change
  can move the collision onto or off a struct, so it presents as flaky/spooky.

## Suggested fix direction (compiler)

Disambiguate struct-ids from the flat f64v2/f64v4 sentinels. Any of:

1. Give `f64v2`/`f64v4` descriptor-band sentinels (`≤ -2048`) like every other
   vector type, retiring the flat -20/-21 codes (then the guard is a single
   `lt <= -2048` range test and struct-ids are collision-free up to 2048).
2. Offset the struct `SLTYPE` encoding (e.g. `-(struct_id + K)` with `K` chosen
   so no valid struct-id maps onto -20/-21) — cheap but leaves the two magic
   numbers around.
3. Carry `is_simd` as a separate flag/tag rather than overloading the sign of
   the type word, so struct-ids and vector descriptors never share a value space.

Option 1 is the cleanest (unifies the vector encoding on the descriptor band).

## Reproducer artifact

`stiva/docs/development/cycc-bug-struct-sid-20-21.cyr` — the annotated 20-struct
repro above; `cyrius build` it to see `error:<source>:25: SIMD vector has no
named fields`. (Filed from the stiva port; no compiler source was modified.)
