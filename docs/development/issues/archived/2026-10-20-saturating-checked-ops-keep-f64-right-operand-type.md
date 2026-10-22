# Saturating and checked ops (`+| +? -| -? *| *?`) keep an f64 right operand's type, where the guide says only `+ - * /` do — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FB-4, `949e46edd`, and the review fix FB-4r `8e6a65fa0` (a comment) — the user's D104 (2026-10-20): integer, as the guide says. EMIT_OVF_CALL (src/frontend/parse_expr.cyr), the six operators' one emitter, clears the expression type after the helper call (it cleared only a struct), so `+| +? -| -? *| *?` give an integer result whatever their right operand. In the filed repro `(2 +| x) * 3` with `x: f64` is an integer multiply with no warning (it took the f64 arm, "f64 arithmetic with a non-f64 right operand": at x = 1.5, 5 → 6), and `(2 +| x) < 3` compares integers with no warning; an operand's own mix still warns (`2 +| x * 3`: the `x * 3`), the acceptance's "own operand" warning. The receives lane's tuple-wording row follows: `take(2 +| 1.5)` is "an integer" (`_tty_op` / `_tty_bin`, src/frontend/parse_fn.cyr). Rows: `f64_int_mix_warn.sh` axis 20 (nine programs; mutant RED 8); `tests/tcyr/crossos/struct_operator_result_binding.tcyr` c_sadd – c_cmul beside 6.7.13's D12 rows (101 / 101 on x86_64, qemu-aarch64, cxvm, wine; the tree before fails all six); `tuple_checked.sh` R17y16 now "an integer", R17y16a – R17y16e on four legs (the pre-D104 reading RED 24). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found by the 6.7.16 wave-3 receives lane (fix step), 2026-10-20.
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
