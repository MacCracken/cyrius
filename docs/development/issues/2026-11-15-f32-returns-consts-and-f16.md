# f32 as a first-class type for GPU-facing code: `fn f(): f32` and `const K: f32` are refused, and there are no f16 helpers

**Status:** 🟡 **OPEN** — feature request, verified on cyrius 6.7.18 (x86_64), 2026-11-15.
**Discovered:** 2026-11-15, by soorat's Rust → Cyrius port, probes P1–P3:
- the probes: `soorat/scripts/probes/math/tests/p2_math.tcyr`, `p1_layout.tcyr`;
- the write-up: `soorat/docs/development/port-parity.md` §1.1–1.3, conversion ledger L8.

**Reporter:** soorat 2.0 port (`soorat/docs/development/soorat-port-plan.md` §10). ranga and pravash hit the
same ground (`ranga/src/composite.cyr`'s `_rg_f32_*` helpers; pravash's `PackedParticles`).
**Severity:** Low to medium. Everything is expressible today, but every GPU-facing library pays a boilerplate
tax, and the workarounds hide the f32 type from the compiler.

## Summary

soorat is a renderer: its math is f32 because the GPU's is. P2 ported soorat's whole `math_util` to Cyrius f32
and got **15,318 values bit-identical** to Rust. So the arithmetic is right; the gaps are in the type
surface:

| Gap | Today | Workaround soorat uses |
|---|---|---|
| `fn f(): f32` | refused | return the binary32 bits in an i64; the caller must know they are f32 |
| `const K: f32 = 0.99;` | refused ("a const takes no type annotation") | `var K = 0x3F7D70A4;`, the bits from rustc, because `f32_from(0.99)` rounds twice (the open `2026-11-12-no-f32-decimal-parse.md`) |
| an f32 left operand reads the right operand's low 32 bits | warns only under `--bounds` | every operation through a helper with `: f32` parameters (`fa`, `fs`, `fm`, `fd`), as ranga does |
| binary16 | no `f16_from` / `f16_to` | hand-written conversion (round to nearest even, subnormals, ±inf, NaN) for HDR environment maps |

## Request

1. Allow `: f32` as a **return type**. The value is returned in the low 32 bits, typed, so the caller's
   expression is f32 arithmetic without a helper.
2. Allow an **f32 constant**: `const K: f32 = 0.99;`, rounded once from the decimal (this needs the decimal →
   f32 parse of the open issue above), or an f32 literal suffix (`0.99f`).
3. Two builtins, `f16_from(f32) -> u16 bits` (round to nearest even) and `f16_to(u16) -> f32`, as
   `f32_from` / `f32_to` do for f64 → f32.

## Close

soorat's `mathx` can drop its bit-pattern constants and its `: f32` helper wrappers. soorat's P2 replay stays
bit-identical (`soorat/scripts/probes/math/p2_compare.py`).
