# Saturating and checked ops (`+| +? -| -? *| *?`) keep an f64 right operand's type, where the guide says only `+ - * /` do — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 wave-3 receives lane (fix step), 2026-10-20.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 receives lane (fix step); placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; f16 lane, wave 4, unit FG4) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D104 — Integer, as the guide says (`+| +? -| -? *| *?` give an integer result, as `&` does).
**Severity:** Low — a value typed against the guide's rule (warned).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/overflow.cyr"
fn f(x: f64): i64 { var a = (2 +| x) * 3; return a; }
```

`* 3` takes the f64 arm ("f64 arithmetic with a non-f64 right operand"), while `(2 & x) * 3` is integer (6.7.13's D12). The guide: "Only `+ - * /` keep an f64 right operand's type".

## Acceptance (D104)

The six operators give an integer-typed result whatever their right operand; the f64 warning on `(2 +| x)`'s own operand stays as the guide says; the receives lane's tuple-wording row R17y16 follows. Rows beside 6.7.13's D12 rows.
