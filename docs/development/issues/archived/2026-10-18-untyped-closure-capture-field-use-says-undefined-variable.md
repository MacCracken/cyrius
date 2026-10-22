# A `.field` read, field store or `.m()` on an untyped closure capture is reported "undefined variable 'x'" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-13, `ef63d4610`, and the review fix GB-13r `dd62a8a96` — no decision needed (refused before and after; and valid source refused). The capture routes, as the root cause says, to the `sid == 0` arm: `_cl_cap_fld_any` passes any non-struct capture on as its capture-band index, and the refused-annotation stand-down resolves a capture to the slot of the fn that declared it (`_cl_cap_origin`, through nested closures). The filed repro is refused once at 3:54, "no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)" (it was "undefined variable 'x'"); the store-and-method line gets the assignment and method wordings at 3:47 / 3:62; the refused annotation is one error, the annotation's; a captured f64v2 gives "SIMD vector has no named fields"; a nested closure's capture of a capture the same; `--syntax-only` silent; and a bounded generic's captured receiver at a scalar T (`|| v.show()` at T = i64, `self` in a trait default for i64), refused "undefined variable", now compiles. Rows: `struct_result_type_refused.sh` UC0 (the filed repro verbatim) – UC14, every row on x86_64 / aarch64 / cx / PE since GB-13r; `tests/tcyr/crossos/trait_bounds.tcyr` K1 – K9; the tree before RED 48. Met beside it: a SIMD vector local's `.m()` is one error (GB-12, `4b6958340`). Filed beside it: a capture named like a struct GLOBAL still reads the global's field (issues/archived/2026-10-20-closure-untyped-capture-named-like-struct-global-reads-global-field.md, the user's D96, wave 4). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (l6715-receives, unit R2) with the lane
base's compiler (4862a462e's tree + the lane's earlier units; the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — refused either way (rc 1); the error names the wrong problem: x is declared and captured, and the
real fault is that it has no struct type.
**Kind:** bug (diagnostic).
**Discovered:** 2026-10-18 by unit R2 while fixing issues/archived/2026-10-17-refused-annotation-type-cascades-at-field-uses.md:
a variable whose annotation was refused (`var x: Foo = 5;`), captured by a closure that reads `x.a`, still prints a
second error, "undefined variable 'x'" — and so does any untyped capture, with no refused annotation at all. The
refused-annotation stand-down (`_ann_refd_said`) deliberately looks up no capture, and the capture arm never reaches
the "no struct type in scope" reporters it guards.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; var f = |k| { return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
```

```
error:<source>:3:54: undefined variable 'x'
```

The same for a field store and a method call on the capture:

```
fn main(): i64 { var x = 5; var f = |k| { x.a = k; return x.m(); }; return fncall1(f, 0); }
error:<source>:3:47: undefined variable 'x'
error:<source>:3:62: undefined variable 'x'
```

and, after a refused annotation, as a second error: `var x: Foo = 5; var f = |k| { return x.a + k; };` ->
`unknown type 'Foo' for variable 'x'` then `undefined variable 'x'`. The same use outside the closure
(`var x = 5; return x.a;`) says "no struct type in scope for 'x'; a '.field' access needs its struct declaration";
a struct-typed capture (`var x: Q = Q { 1, 2 }; |k| x.a + k`) compiles.

## Root cause

PARSE_FIELD_LOAD (src/frontend/parse_decl.cyr): a name that is no local is looked up as a capture
(`_CL_CAP_FIELD_IDX`), which answers an index only for a capture with a struct type; an untyped capture falls through
to FINDVAR (globals), misses, and takes the undefined-variable arm (`_undef_var_report`). The field-store and method
paths do the same. A capture with no struct type should reach the `sid == 0` arm ("no struct type in scope for 'x'"),
where the refused-annotation stand-down would then also apply (its capture lookup is skipped today).
