# A method or `callptr(&f, ..)` declared to return a vector that STARTS an assignment's right-hand side, and a vector call in parentheses that STARTS an integer initialiser or right-hand side, store the result's word plus the rest — the unwrapped by-name call is refused — RESOLVED

> ✅ **RESOLVED in v6.7.16** (RV-5, `15cb1124f`, and the RV-5r review fix `0b2446c31` — D25, the user, 2026-10-19: "Refused, as the by-name call"; D26, the user, 2026-10-19: "Refused, as unwrapped". `_vasg_vt` reads `_vcall_vt` with `start` 1, so a method / `callptr(&f, ..)` / `fncallN(&f, ..)` that starts an assignment's right-hand side (a local, a global in a fn or at top level, a for step) is refused as the by-name call; `_vcall_vt`'s `start` 1 looks through every leading `(` before a call (`_vcv_wpeel`, RV-5r) and takes a call that starts a whole wrap's inside. The filed rows, verbatim, are refused once on x86_64, IR=3, aarch64, cx and PE (each stored the result's word plus 1: 1, or 42 on cx / PE): rows 1 `x = s.m2() + 1;`, 2 `x = callptr(&mk2, 41, 7) + 1;` and 4 `x = (mk2(41, 7)) + 1;` "vector return type does not match the assigned variable", rows 3 `var x: i64 = (mk2(41, 7)) + 1;` and 5 `var x: i64 = (s.m2()) + 1;` ".. the declared type". Also refused: `(mk2(41, 7) + 1)`, double wraps, a parenthesised head inside a wrap, top-level `var X: i64 = (mkv(..)) + 1;`, and since RV-5r parentheses closing after an operator, `var x: i64 = (mk2(41, 7) + 1) * 2;` (⚠ beyond D26's text; D100, 2026-10-20, covers any position). Rows: `simd_return_shapes.sh` WRK12 – WRK16 (the filed rows verbatim) – WRK41, OP22 – OP25 and the controls WR7, on five legs. Mutations M-WR5 – M-WR8 each RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (unit V3's final tree, 89fd5ad53), x86_64 /
x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine); x86_64 the same on the lane's tree before V3 (024a5e421).
Pre-existing: V3's D28 / D29 bite (issues/2026-10-17-wrapped-vector-call-into-untyped-or-scalar-declaration-binds-a-
word.md) refuses the WHOLE wrapped call and a method starting a DECLARATION, as decided, and leaves these.
**Placement:** 6.7.16 — Break 2, repair 6 (receives lane, wave 3, unit R2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D25 — Refused, as the by-name call.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D26 — Refused, as unwrapped.
**Severity:** Medium — compiles with no diagnostic; the destination holds the call's first word plus 1, a value that
differs per target, where the same source spelled with an unwrapped by-name call is refused.
**Kind:** language (decision) — the shapes are the assignment twin of 6.7.15's D29 (a method starting an integer
INITIALISER is refused, as the by-name call that starts one is) and the "starts it" twin of 6.7.15's D28 (parentheses
around a WHOLE vector call are transparent). Neither decision's filed surface named them.
**Discovered:** 2026-10-18, implementing D28 / D29 (unit V3).

## Reproduction

```cyrius
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
fn r(): i64 { var s: Mv = Mv { 1 }; var x = 0; x = s.m2() + 1; return x; }
syscall(60, r() % 256);
```

The same header with `fn r()` replaced by each row:

```
row 1 (above)  x = s.m2() + 1;                        x86_64 / IR=3 / aarch64 1, cx 42, PE 42
row 2          x = callptr(&mk2, 41, 7) + 1;          x86_64 / IR=3 / aarch64 1, cx 42, PE 42
row 3          var x: i64 = (mk2(41, 7)) + 1;          x86_64 / IR=3 / aarch64 1, cx 42, PE 42
row 4          x = (mk2(41, 7)) + 1;                   x86_64 / IR=3 / aarch64 1, cx 42, PE 42
row 5          var x: i64 = (s.m2()) + 1;              x86_64 / IR=3 / aarch64 1, cx 42, PE 42
(every row compiles with rc 0 and no diagnostic)
```

Compare, refused on every target: `x = mk2(41, 7) + 1;` ("vector return type does not match the assigned variable",
since 6.7.11), `var x: i64 = mk2(41, 7) + 1;`, and since 6.7.15 (D29) `var x: i64 = s.m2() + 1;` and `var x: i64 =
callptr(&mk2, 41, 7) + 1;` ("vector return type does not match the declared type").

## Root cause

The by-name check (`_try_vector_call_assign`'s arm, PARSE_VAR's vin block) reads `_vcall_fi` at the source's first
token, so a by-name call that starts the source is refused. The declaration's other spellings read `_vcall_vt(.., 1)`
(6.7.15: a method / `callptr(&f)` may start it, unwrapped); the assignment's (`_vasg_mscal`) read `_vcall_vt(.., 0)` —
a whole call only (src/frontend/parse_decl.cyr). And `_vcall_vt`'s `start` 1 accepts only an UNWRAPPED call at the
source's first token: `(call) + 1` peels no wrap (the parentheses are not the whole source), so it is no call.

## The question

Is a method or `callptr(&f, ..)` that starts an assignment's right-hand side refused as the by-name call that starts
one is (rows 1, 2), and is a vector call in parentheses that starts an integer initialiser or right-hand side refused as
the unwrapped one is (rows 3-5)?
