# A whole vector call returned from a scalar fn, or passed to an integer / untyped parameter, compiles and hands back a per-target word (a fault on PE) — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 wave-3 receives lane (R2), 2026-10-20.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 receives lane (R2); placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; s16 lane, wave 4, unit SZ6) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D101 — Refuse it (a vector value cannot be returned as i64 / passed to an integer parameter, as a vector into an integer declaration is).
**Severity:** Medium — a silent wrong value on every target, a fault on PE (exit 5: mk2's hidden result pointer is not passed).

## Reproduction

`fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }`, then, all rc 0:
- `fn r(): i64 { return mk2(41, 7); }` — 0 on x86_64 / IR=3 / aarch64, 41 on cx, exit 5 on PE (wine);
- `return s.m2();` from a `: i64` fn (`impl Mv { fn m2(self): f64v2 { … } }`), `takei(mk2(41, 7))` into `x: i64` and `take(mk2(41, 7))` untyped — 0 on x86_64 / aarch64, 41 on cx and PE;
- `return mk2(41, 7) + 1;` from `: i64` — 1 on x86_64 / aarch64, 42 on cx / PE.

## Root cause

6.7.11 and 6.7.14's D38 refuse a vector call into a non-vector declaration or assignment; a `return` from a scalar fn and an argument into an integer or untyped parameter are not judged.

## Acceptance (D101)

Each shape above is refused by name, once, on every target ("a vector value cannot be returned as i64" / "… passed to an integer parameter"); a vector-returning fn's own `return mk2(..)` and a `*f64v2` / `f64v2` parameter are unchanged. Rows on x86_64, aarch64 (qemu), cx and PE (wine).
