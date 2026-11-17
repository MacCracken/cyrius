# A closure's captured `f64` is an untyped word in arithmetic: `k * x` multiplies the bit patterns — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-15.
**Discovered:** 2026-11-15, by pramana's Rust → Cyrius port (M0 step 9, probe P3;
`pramana/docs/development/port-parity.md` §6.2).
**Reporter:** pramana 2.0.0 port (filed with no stand-in: a coding rule covers it, `pramana-port-plan.md` §8.3, §10).
**Severity:** **Medium.** It computes a wrong answer with only a warning, in the form a numerical library reaches for
first: a closure over a parameter (`|x| k * x` for Monte Carlo integrands, MH targets, Gibbs conditionals).

## Summary

Inside a capturing closure, a captured `var k: f64` reads as an untyped word when it is an arithmetic operand:
- `k * x` (the capture on the left) is an **integer** multiply of the two bit patterns. 3.0 × 0.25 gives the bits
  `0x0`, under the warning *integer arithmetic with an f64 right operand*;
- `x * k` (the capture on the right) gives the right value, 0.75, but warns *f64 arithmetic with a non-f64 right
  operand*.

The guide (6.7.16, its D3) says a captured f64 binds `T = f64` when it is passed as a generic argument, so arithmetic
is the one place the capture loses its type. Copying it into a typed local first (`var kf: f64 = k;`) is right and
warning-free.

## Reproduction

[`repros/2026-11-15-closure-captured-f64-is-untyped-in-arithmetic.cyr`](repros/2026-11-15-closure-captured-f64-is-untyped-in-arithmetic.cyr),
from the repo root:

```sh
cyrius build docs/development/issues/repros/2026-11-15-closure-captured-f64-is-untyped-in-arithmetic.cyr /tmp/capf
# warning:<source>:31:28: integer arithmetic with an f64 right operand
# warning:<source>:36:28: f64 arithmetic with a non-f64 right operand
/tmp/capf; echo "exit=$?"
# (|x| k * x)(0.25), k = 3.0 = 0x0   WRONG, want 0x3fe8000000000000
# (|x| x * k)(0.25), k = 3.0 = 0x3fe8000000000000
# exit=1
```

## Ask

**Carry the capture's declared type into the closure body**, so a captured `f64` is an `f64` operand, as a local or
a parameter is. Failing that, make the left-operand case an error rather than a warning: it never computes what the
source says.

## Meanwhile

pramana's rule (its port plan §8.3, CLAUDE.md "Float hygiene"): inside a closure, copy every captured f64 into a typed
local before using it. Its `cyrius test` must be warning-free, so the warning catches a missed copy. Probe P3 measured
the closure forms against `callptr` with a context word: every form costs the same within 1–3 ns, and the
function-pointer-plus-context form (pramana's D7) needs no such rule.
