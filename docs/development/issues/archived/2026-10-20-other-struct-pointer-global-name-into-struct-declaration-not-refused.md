# A `*U` GLOBAL's name into a struct `S` declaration is not refused — `var t: P = GU;` binds a handle (in a fn, and over 8 B at top level) or holds the pointer word (8 B or less at top level), where a `*U` LOCAL is refused by name — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-39, `da785ce3c`, and the review fix SS-39r, `75e50e3cf` (with SS-40 `e77a2b66a`, a zone tuple global's double error, met) — D87 (a) (the user, 2026-10-20: "Refuse it by name at every size"). In a fn `_sci_gpu_type` types a `*U` global so the existing refusal names it; at top level `_gz_pnu` refuses it in the replay and after the first statement; SS-39r carries the refusal to every other `*U` source the assignment refuses — a `: *U` call or method, a `*U` field, pointer arithmetic, a generic instance's (beyond D87's text). The filed repro is refused at each of its six declarations, "cannot copy 'GU' into a variable of a different struct/vector type: 'Z'" (11:12, 12:14, 14:10, 15:12, 16:24, 16:41), with no cascade (it compiled and printed `0999962938166293816`), on x86_64, aarch64, cx and PE; `var t: U = GU;` copies and `var t: *U = GU;` aliases, unchanged. Rows: `small_struct_handle_line.sh` GC15 (the repro verbatim) – GC19; `tuple_checked.sh` CS8d – CS8h; mutations MY4, MY5. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at 6b6b1b149, unit Z4, x86_64; the
shared front end, every target alike). Pre-existing: b73e8d5fe's compiler gives the same output. Met while landing
6.7.16's D18 (a) (issues/archived/2026-10-18-top-level-declaration-from-double-pointer-single-deref-binds-handle.md, commit
62ba267ac: a top-level `var G: S = P;` with P a `*S` global's name is a copy at every size). D18 decided the `*S` name of
the declared struct; a `*U` of ANOTHER struct is beyond its surface, so it is filed, not fixed (62ba267ac leaves it
exactly as it was).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ3) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D87 — (a) Refuse it by name at every size.
**Severity:** Medium — compiles with no diagnostic; the declaration reads U's bytes as a P (a handle onto the U object),
or at 8 B or less at top level the address as the struct's word.
**Kind:** bug (a missing refusal).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct P { x; y; }
struct U { a; b; }
struct P8 { v; }
struct U8 { w; }
var GSU = U { 3, 4 };
var GU: *U = &GSU;
var GSU8 = U8 { 6 };
var GU8: *U8 = &GSU8;
var Z: P = GU;             # the declaration zone: a `*U` global's name into a P global
var Z8: P8 = GU8;
fmt_int(0);
var T: P = GU;             # after the first statement
var T8: P8 = GU8;
fn f(): i64 { var t: P = GU; var t8: P8 = GU8; GSU.b = 9; GSU8.w = 9; return t.y * 10 + t8.v; }
fmt_int(f()); fmt_int(Z.y); fmt_int(T.y); fmt_int(Z8.v); fmt_int(T8.v);
syscall(60, 0);
```

```
$ build/cycc < u.cyr > u && ./u; echo " exit=$?"
0999962938166293816 exit=0
```

Compiled with no diagnostic: in the fn `t` / `t8` are handles onto GSU / GSU8 (they read the later writes, 99); at top
level Z / T are handles (9, 9) and Z8 / T8 hold GU8's address (6293816). The same declaration from a `*U` LOCAL is
refused by name (6.6.6 / 6.7.0):

```cyrius
struct P { x; y; }
struct U { a; b; }
fn f(): i64 { var u = U { 3, 4 }; var pu: *U = &u; var t: P = pu; return t.y; }
syscall(60, f());
```
```
error:<source>:3:61: cannot copy 'pu' into a variable of a different struct/vector type: 't'
```

and so is `var t: P = *GU;` (a dereference of the `*U` global), in a fn and at top level
(tests/gates/codegen/small_struct_handle_line.sh GC2).

## Root cause

In a fn, `_try_struct_copy_init` (src/frontend/parse_decl.cyr) takes a `*T` GLOBAL source only when T is the declared
struct (`_sci_gptr_src`); any other global goes to `_sci_global_src`, which answers -1 for it, and the refusal it then
asks (`_AGG_ASSIGN_TYPE_ERR` with `_sci_gsrc_type`) gets 0 for a `*U` global (`_sci_gsrc_type` types only an inline
struct global, GVPM 2), so nothing is refused and the scalar init binds a handle. At top level the declaration-zone sweep's `_gz_pname` (and PARSE_VAR's
`_gz_late` through `_gz_truth`) still answers "a struct value" for ANY `*T` name, the 6.7.9 layout 6.7.16's D18 left in
place for another struct: 8 B or less an inline value holding the pointer word, over 8 B a handle.

## Fix direction

Refuse a `*U` global's name into an `S` declaration by name, as the `*U` local and `*GU` are ("cannot copy 'GU' into a
variable of a different struct/vector type: 't'"), in a fn and at top level (the zone's replay and PARSE_VAR's global
arm), at every size. It changes what compiles, so it is the user's call whether to refuse or to keep the bind.
