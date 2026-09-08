# `f64_exp` / `f64_exp2` return NaN for an infinite argument — the range reduction computes `inf − inf`

**Status:** 🟡 **OPEN** — verified against live code at cycc 6.6.0 on x86_64,
2026-09-08: `f64_exp(+inf)`, `f64_exp(−inf)`, `f64_exp2(+inf)` and `f64_exp2(−inf)`
all return NaN, and `_f64_exp_polyfill(+inf)` does too, so it is not an x87
artefact. Repro exits 4 (the number of wrong answers) and will exit 0 when fixed.
**Placement:** unpinned — 6.6.x-line backlog. Small and self-contained: two guard
clauses in `lib/math.cyr` plus the matching native-path guard. Never 7.x.
**Discovered:** 2026-09-08 during the ganita 1.2.4 repair of its own P(−1) audit backlog
**Severity:** Medium — silently wrong answer from a stdlib math function, with a
consumer-side workaround available (and shipped, see below).
**Affects:** cycc **6.6.0** verified. Almost certainly the whole range back to
**v5.5.0** (where the f64 transcendentals landed) — the mechanism is in the range
reduction that both the native x87 path and the polyfills use, and the polyfills
(`_f64_exp_polyfill` v5.7.31, `_f64_exp2_polyfill` v6.4.25) reproduce it exactly.
⚠ Only 6.6.0 was actually tested; the earlier range is inference from the code
shape, not measurement.

## Summary

`f64_exp` and `f64_exp2` return **NaN** for `±inf`. C and IEEE-754 both say:

| | C / IEEE-754 | cycc 6.6.0 |
|---|---|---|
| `exp(+inf)` | `+inf` | **NaN** |
| `exp(−inf)` | `+0` | **NaN** |
| `exp2(+inf)` | `+inf` | **NaN** |
| `exp2(−inf)` | `+0` | **NaN** |

**The defect is confined to these two.** Everything else in the f64 surface
already agrees with C, which is why this is a narrow fix rather than a sweep:
`f64_ln`, `f64_log2`, `f64_sqrt`, `f64_sin`, `f64_cos`, `f64_floor`, `f64_round`
and `f64_abs` all give the right answer at `±inf`, and `f64_atan(±inf)` is
**bit-exactly** `±π/2`. The repro checks all of them so a reader can see the
boundary of the claim rather than take it on trust.

The finite extremes are also fine and are not what this is about: `exp(710)`
overflows to `+inf`, `exp(−800)` underflows to `0`, `exp(−745)` is correctly
subnormal.

## Why it matters downstream

This is not only an edge case someone stumbles into with a hand-written
infinity. It propagates through **every stdlib and consumer function whose
identity contains an exponential**, turning a defined infinite result into NaN:

- `sinh(x) = (eˣ − e⁻ˣ)/2` — `sinh(+inf)` should be `+inf`, becomes NaN.
- `cosh(x) = (eˣ + e⁻ˣ)/2` — `cosh(±inf)` should be `+inf`, becomes NaN.
- Anything reaching `exp` through a `pow`/`log` identity inherits it.

ganita hit exactly this in its 1.2.3 P(−1) audit: `ganita_f64_sinh(+inf)` and
`ganita_f64_cosh(±inf)` returned NaN, and the audit could not tell from the
outside whether the bug was ganita's or the stdlib's until the polyfill was
called directly. That is the real cost here — a NaN with no diagnostic sends the
consumer looking in their own code first.

## Reproduction

[`repros/2026-09-08-f64-exp-nan-for-infinite-argument.cyr`](repros/2026-09-08-f64-exp-nan-for-infinite-argument.cyr)

```sh
cyrius build docs/development/issues/repros/2026-09-08-f64-exp-nan-for-infinite-argument.cyr /tmp/expinf
/tmp/expinf; echo "exit=$?"
```

It exits with the number of wrong answers — **4** today, **0** when fixed — so it
works as a regression witness as well as a demonstration.

```
=== the defect: exp and exp2 ===
  f64_exp(+inf)       got NaN      want +inf     <-- WRONG
  f64_exp(-inf)       got NaN      want 0.0      <-- WRONG
  f64_exp2(+inf)      got NaN      want +inf     <-- WRONG
  f64_exp2(-inf)      got NaN      want 0.0      <-- WRONG

=== the polyfill has the SAME defect (so it is not an x87 artefact) ===
  _f64_exp_polyfl(+i  got NaN      want +inf     <-- WRONG

=== every other f64 builtin already agrees with C ===
  f64_ln(+inf)        got +inf     want +inf
  f64_sqrt(-inf)      got NaN      want NaN
  f64_sin(+inf)       got NaN      want NaN
  ... (10 rows, all pass)
  f64_atan(+inf) is bit-exactly pi/2:  1
```

## Root cause

**Range reduction subtracts a multiple of the argument from itself, and
`inf − inf` is NaN.** Both implementations do this, which is why both fail.

`lib/math.cyr:69` `_f64_exp_polyfill` — the arithmetic is explicit:

```cyrius
var n_f = f64_round(f64_mul(x, LOG2E));      # x=+inf  ->  n_f = +inf
var r   = f64_sub(x, f64_mul(n_f, LN2));     # +inf - +inf  ->  NaN
```

Every Horner term downstream then inherits the NaN. The repro prints both steps:

```
  round(+inf * log2e)      = +inf
  +inf - round(...) * ln2  = NaN      <-- inf - inf
```

There is a **second**, independent break in the same function even if the
subtraction were fixed — the `2^n` bit-pack reads an infinite exponent:

```cyrius
var n_int = f64_to(n_f);                     # f64_to(+inf) = -9223372036854775808
var two_n_bits = (n_int + 1023) << 52;       # meaningless
```

`f64_to(+inf)` saturates to `i64::MIN`, so `(n_int + 1023) << 52` is not an
exponent at all. Any fix has to guard **before** the reduction, not patch the
subtraction.

`_f64_exp2_polyfill` (added v6.4.25) uses `n = round(x)` and the same
`2^f = exp(f·ln2)` structure, so it fails identically. The **native x87 path** on
x86_64 — which the `lib/math.cyr:55-58` header notes is what x86 builds actually
execute — reaches NaN the same way, since the classic `F2XM1`/`FSCALE` sequence
also splits the argument with `FRNDINT` and subtracts.

*(The x87 claim is by inspection of the standard instruction sequence, not by
disassembly — flag it as speculation. The measured facts are that the native path
and the polyfill both return NaN, and that the polyfill's arithmetic demonstrably
produces it.)*

## Proposed fix

Guard the non-finite cases at the top of both polyfills, before any reduction:

```cyrius
fn _f64_exp_polyfill(x): i64 {
    # NaN in, NaN out.
    if (((x >> 52) & 0x7FF) == 0x7FF && (x & 0x000FFFFFFFFFFFFF) != 0) { return x; }
    # ±inf: exp(+inf) = +inf, exp(-inf) = +0. Must come BEFORE the range
    # reduction, which computes inf - inf, and before the 2^n bit-pack, which
    # reads f64_to(inf) = i64::MIN as an exponent.
    if ((x & 0x7FFFFFFFFFFFFFFF) == 0x7FF0000000000000) {
        if ((x >> 63) & 1 == 1) { return 0; }        # +0
        return 0x7FF0000000000000;                    # +inf
    }
    ...
```

Same three lines in `_f64_exp2_polyfill`, with the same answers (`exp2` has the
same limits as `exp`). The native x86 path needs the equivalent guard wherever
the parser emits the x87 sequence — that is the half I cannot patch from a
consumer repo and have not located.

Worth pairing with a `tests/tcyr/` case in the shape of the existing
`vr01_exp2_atan_bigtrig.tcyr` gate, since the finite range is already covered and
this is precisely the kind of edge that comes back.

## Consumer-side workaround

**ganita 1.2.4 shipped one**, and it is a workaround rather than a fix — the
guards sit in ganita and every other consumer of `f64_exp` still has the defect:

- `src/math_advanced.cyr` — `ganita_f64_sinh` and `ganita_f64_cosh` test for
  `±inf` before touching `f64_exp` and return `±inf` / `+inf` directly.
- `src/math_f32.cyr` — `ganita_f32_exp` and `ganita_f32_exp2` do the same,
  returning the f32 patterns `0x7F800000` / `0`.

The shape, for anyone copying it:

```cyrius
fn _f64_is_inf(v): i64 {
    if ((v & 0x7FFFFFFFFFFFFFFF) == 0x7FF0000000000000) { return 1; }
    return 0;
}
```

⚠ The workaround only covers the paths a consumer knows about. A consumer that
reaches `f64_exp` through some other identity still gets the NaN, which is why
the fix belongs here rather than in each caller.
