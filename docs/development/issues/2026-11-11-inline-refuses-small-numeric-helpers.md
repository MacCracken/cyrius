# `#inline` refuses the small helpers numeric kernels are made of (more than 2 parameters, a pointer parameter) — open (performance request)

**Status:** 🟡 **OPEN** — measured on cyrius 6.7.18 (x86_64 Linux ELF), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M2, the shallow-water step).
**Reporter:** pravash 2.0.0 port (`pravash/docs/benchmarks-rust-v-cyrius.md`, M2).
**Severity:** **Low–medium (performance).** Nothing is wrong; the helpers simply stay calls.

## Summary

A shallow-water step on a 32 × 32 grid takes **221 µs in Cyrius against 30.7 µs in Rust** (7.2×). The step is
written on f64 locals and raw loads, as the language's performance notes advise. What remains is calls: per cell it
calls about 30 small helpers, none more than a few operations long. Each was marked `#inline` to try it, and the
compiler declined every one:

```text
warning:src/mathx.cyr:54:1: #inline ignored: body exceeds 32 tokens
warning:src/column.cyr:75:5: #inline ignored: pointer (*T) parameter
warning:src/shallow.cyr:225:1: #inline ignored: fn takes more than 2 parameters
```

The helpers are:
- **`_pv_max(x, y)`,** Rust's NaN-ignoring `f64::max`: three comparisons, 36 tokens;
- **an upwind difference** `(f, i, vel, stride, inv_dx)`: five parameters, two loads, a branch;
- **a depth** `(sh, ground, k)`: three parameters, two loads, a max;
- **a column's unchecked load** `c.at(i)`, a method on a `*PvColumn`.

Writing them out by hand works. pravash's `total_volume` went from 14.6 µs to 4.75 µs, 3.1×, once its two
helper calls per cell became inline code. But hand-inlining a 300-line kernel, and keeping it Rust's operation
order, is error-prone. Kernels of this shape are the rest of pravash: the SPH pair loops, the grid stencils, MPM's
transfers.

## Ask

Let `#inline` take more of these. In order of payoff here:
1. **More parameters:** up to 6, say. The rule could be on the body's size alone.
2. **A larger body limit,** about 64 tokens, so a three-branch `max` fits.
3. **`*T` parameters,** for methods on a pointer receiver.

Or an `#inline(always)` that skips the heuristics and is the author's responsibility. The before numbers are
pravash's `tests/pravash.bcyr` rows `shallow_step/*` and `shallow_volume/*`.

## Also needed: ushma (2026-11-12, cyrius 6.7.18): a fourth refusal, `if` and `var`

ushma's port hits a refusal this file doesn't list: **`#inline ignored: body has control flow or a var
declaration`**. It declines a body of 2 parameters and about a dozen tokens, inside the three limits above, for one
`if` or one local:

```text
warning:<source>:8:1: #inline ignored: body has control flow or a var declaration
warning:<source>:15:1: #inline ignored: body has control flow or a var declaration
```

**Where it costs** (ushma 2.0.0, `ushma/docs/benchmarks-rust-v-cyrius.md`, M1):
- **Range checks.** Every fallible function opens with one "finite and above a bound" check per argument. Written as
  an `if` around a call to an `is_finite` helper, three of them cost 21 ns; as one `if` in one fn, 12 ns; rewritten as
  the single expression `(x > b) & (x < INF)`, which `#inline` takes, 6 ns (the harness floor subtracted). The rewrite
  took ushma's thermal diffusivity from 33 to 16 ns (Rust 4.49), its Biot number from 29 to 15 (3.99) and its
  parallel resistance from 47 to 31 (9.28).
- **Level-gated spans.** `if (sakshi_get_level() >= SK_DEBUG) { sakshi_span_enter(name, len); }` has no single
  expression form, so each instrumented function pays 7 ns for its enter and exit with DEBUG off: 7 of
  `ideal_gas_pressure`'s 24 ns (Rust 9.58).

The expression rewrite works only for a predicate. A guard with an early return, a NaN-aware max (pravash's `_pv_max`
above) or a check that calls something has no branch-free form.

**Repro:** `repros/2026-11-11-inline-refuses-small-numeric-helpers-if-var.sh` builds the same check three ways (an
`if`, a local, one expression), confirms the three agree on 2.0 and NaN, and **exits 1 while the first two are
refused**. Run on cyrius 6.7.18, x86_64, 2026-11-12: exit 1, both warnings above.

**Ask (4):** let `#inline` take a body with `if` / `else`, early `return`s and local `var`s, inside the size limit:
each `return` a jump to the end of the inlined block, each local a slot in the caller's frame. With pravash's 1–3,
ushma's checks and span gates would inline as they are written.
