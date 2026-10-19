# `var p: *i64 = (0);`, `p = (0);` and a zone `var G: *i64 = (0);` warn "assigning non-pointer to typed pointer", where `= 0;` is quiet — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (l6715-receives, unit R2, after the
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
