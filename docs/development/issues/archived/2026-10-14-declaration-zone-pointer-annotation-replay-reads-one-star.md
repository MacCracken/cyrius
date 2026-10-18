# A declaration-zone global annotated `**T` is refused "expected '='" — the replay reads one `*` — RESOLVED

> ✅ **RESOLVED in v6.7.14** (FE-13, `1a43291f`: the declaration-zone replay's annotation reader `_gvi_ann` steps every leading `*` (`_gvi_stars`, as pass 1's `_ptr_annot`) and a refused `*( .. )` to its `)`; no decision needed. `var P: **i64 = 0;` in the zone builds and exits 0 (it was "1:10: expected '=', got identifier 'i64'"), `***i64` and `**B<i64>` build and carry their values, and `*(i64, i64)` gives exactly its one refusal, in the zone and after a statement. Rows: new `frontend/zone_pointer_annotation.sh` (13 rows: Z1 – Z3 the filed repros verbatim, Z4 – Z6, R1 – R3 values, A1 – A3 after a statement, W1 6.7.13's D18 warning once); mutations RED on Z1, Z3 – Z6, R1 – R3, W1. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, unit R5) with
`build/cycc < f.cyr` from the tree root, x86_64.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — a valid program does not compile (a `**T` global before the first top-level statement);
the same declaration after a statement, or as a local, compiles. A refused `*( .. )` global gets a second error.
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R5), while checking the declaration-zone form of shape 3
of `2026-10-09-refusal-cascades-tuples-pairs-u128-d19.md` (a refused `*( .. )` annotation). Outside that issue's
filed surface (its shape 3 is a fn local).

## Reproduction

```cyr
var P: **i64 = 0;
fn main(): i64 { return 0; }
syscall(60, main());
```
```
error:<source>:1:10: expected '=', got identifier 'i64'
```
rc 1, no binary. The same line after the first top-level statement compiles (one warning, the `= 0` into a typed
pointer, as every `*T = 0` gets):
```cyr
syscall(1, 1, 0, 0);
var P: **i64 = 0;
syscall(60, 0);
```
```
warning:<source>:2:17: assigning non-pointer to typed pointer
```
rc 0. `fn main(): i64 { var P: **i64 = 0; return 0; }` compiles too.

A refused tuple pointer target in the zone gets the same second error after its refusal:
```cyr
var P: *(i64, i64) = 0;
fn main(): i64 { return 0; }
syscall(60, main());
```
```
error:<source>:1:9: a tuple type cannot be a pointer target `*( .. )`
error:<source>:1:10: expected '=', got identifier 'i64'
```

## Root cause

The replay of a declaration-zone initialiser (EMIT_GVAR_INITS) reads the annotation with `_gvi_ann`
(src/frontend/parse_decl.cyr): after `:` it consumes ONE `*` (`if (PEEKT(S) == 8) { STI(..); ps = 1; }`), then one
token and its `<..>` (`STI(S, GTI(S) + 1); SKIP_GENERICS(S);`). For `**i64` that token is the second `*`, so the
cursor is left on `i64`, and the replay's `if (PEEKT(S) != 4) { .. ERR_EXPECT(S, 4); }` reports it. For `*( .. )` the
token is the `(`, and the cursor is left inside the parentheses. Pass 1 (PARSE_GVAR_REG) reads the annotation whole
(`_ptr_annot`), so the global is registered correctly; only the replay's reader is short.

## Fix

`_gvi_ann` steps the whole annotation as pass 1 reads it: every leading `*`, then a name with its `<..>`, a slice
`[ .. ]`, or a parenthesised type `( .. )` (`_call_close`), returning 0 (a pointer) as it does for `*T` now. Rows:
the three inputs above (the first and an `***i64` compile and run; the `*( .. )` one gives its one refusal), in the
declaration zone and after a statement.
