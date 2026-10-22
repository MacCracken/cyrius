# `var p: *i64 = (0);`, `p = (0);` and a zone `var G: *i64 = (0);` warn "assigning non-pointer to typed pointer", where `= 0;` is quiet — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-17, `2d5f8387b` — no decision needed (6.7.13's D18 (a), "the literal 0 alone is a null pointer", read through the guide's whole-wrap transparency, as 6.7.15's D59 did for a string). `_tp_null_exempt` (src/frontend/parse_decl.cyr) peels k `(`, the literal 0, k `)` and takes the `;`, at every `_tp_exempt` site (`_tp_warn`, the zone's `_tp_warn_gv`, the baked `_tp_warn_baked`). The filed repro now compiles with no warning (it printed three, at 2:22, 3:12 and 6:18), rc 0, exit 0, binary unchanged, on x86_64, aarch64, cx, PE and Mach-O; `((0))`, a `*P` local, a parameter, after the first statement and a global assignment too. `(0) + 1`, `(1)` and `(0) + 0` still warn. Rows: `tests/gates/diagnostics/false_warnings_valid_shapes.sh` N0 (the repro verbatim), N1, N2 (the controls: 6 warnings); mutation (no wrap peeled) RED N0, N1. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (l6715-receives, unit R2, after the
string-literal bite) with a compiler built from that tree; the warning is the shared frontend's, every target the same.
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a false warning on valid code that runs right; nothing miscompiles.
**Kind:** bug (diagnostic).
**Discovered:** 2026-10-18 by unit R2 while fixing issues/archived/2026-10-17-string-literal-expression-into-byte-pointer-still-warns.md:
that filing widens the STRING literal's exemption to a whole wrap (`("xyz")`, `(("x"))`) and to `"abc" + n`. The literal
0's exemption (6.7.13's D18 (a): "The literal 0 alone is a null pointer") has the same one-token shape, and a wrapped
`(0)` was outside that filing's surface, so it was not widened.

## Reproduction

```cyrius
fn main(): i64 {
    var p: *i64 = (0);
    p = (0);
    return 0;
}
var G: *i64 = (0);
syscall(60, main());
```

```
warning:<source>:2:22: assigning non-pointer to typed pointer
warning:<source>:3:12: assigning non-pointer to typed pointer
warning:<source>:6:18: assigning non-pointer to typed pointer
```

rc 0, exit 0. The same three lines with `0` unwrapped are quiet. (Whether `0 + 0` or a constant expression that folds to
0 is a null pointer too is a separate question; guide § Parentheses makes only the WHOLE wrap transparent.)

## Root cause

`_tp_exempt` (src/frontend/parse_decl.cyr) tests the literal 0 only as the one token before the `;`
(`TOKTYP(S, st) == 1`, `TOKTYP(S, st + 1) == 5`); since 6.7.15 the string literal's arm (`_tp_str_exempt`) peels a
whole wrap first, the 0 arm does not. Peeling the wrap for the 0 arm too (the k `(` before it, k `)` after it, then the
`;`) would make `(0)` the null literal at every site `_tp_exempt` serves.
