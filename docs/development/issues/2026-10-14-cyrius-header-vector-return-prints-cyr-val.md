# `cyrius header` prints `cyr_val f(..)` for a fn returning a SIMD vector (`f64v2`, `f64v4`, `i32v4`, ...) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 tools lane (l6711-tools, after the header
struct-return bite) with its `build/cyrius` (throwaway `HOME` / `CYRIUS_HOME`).
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D24 — refuse every vector return by name.
**Discovered:** 2026-10-14 by the 6.7.11 tools lane, unit T5 (issues/archived/2026-10-10-cyrius-header-ignores-struct-returns.md),
which taught the verb to read a fn's return type for structs, a `dyn` and multi-value returns. A vector return is
outside that filing's surface (it names structs and `dyn`), so the bite left it printing the pre-6.7.11 word.
**Severity:** Medium — a generated C header that is wrong for every vector-returning public fn: the C caller reads
rax / x0 while cycc returns the vector elsewhere (no memory corruption for a 16-byte register return; on Win64,
where cycc returns a vector through a result pointer, the prototype's first `cyr_val` lands in the callee's result
slot — the >16 B struct shape the parent issue fixed).
**Affects:** the `cyrius header` verb (`cbt/quality.cyr` `cmd_header` / `_hdr_ret_class`), every version that has it.

## Reproduction

```cyrius
fn rv2(a): f64v2 { var v: f64v2; return v; }
fn rv4(): f64v4 { var v: f64v4; return v; }
fn ri4(): i32v4 { var v: i32v4; return v; }
```

The file builds with `build/cycc` (rc 0). Then:

```sh
T=$(mktemp -d); HOME=$T CYRIUS_HOME=$T/.cyrius build/cyrius header vec.cyr | grep '^cyr'; rm -rf "$T"
```

```
actual:   cyr_val rv2(cyr_val a);
          cyr_val rv4(void);
          cyr_val ri4(void);
expected: a prototype in the vector type C uses for the same registers (on SysV and AAPCS64 a 16-byte vector is
          returned in xmm0 / v0, so `__m128d`-shaped or `double __attribute__((vector_size(16)))`), guarded by
          target where cycc's convention differs from C's (Win64 returns it through a result pointer; f64v4 is
          XMM0:XMM1 / V0:V1 here, where C returns a 32-byte vector in ymm0 or memory), or the fn refused by name
          (stderr, rc 1), as the parent issue refuses what it cannot express — never `cyr_val`.
```

## Root cause

`_hdr_ret_class` (cbt/quality.cyr) recognises the twelve vector type names (`_hdr_vec_name`) and answers class 0, a
word, to keep the pre-6.7.11 output. cycc returns a vector in a different convention on every target
(src/frontend/parse_fn.cyr, the multi-value arm's comment: XMM0/XMM1, V0/V1, four cx R-regs, a PE retptr), none of
them rax.

## Proposed fix

The user's decision: model each vector return per target (C vector types under target guards, as the pair is under
`#ifndef _WIN64`) or refuse every vector return by name. Rows in tests/gates/toolchain/header_spellings_and_size.sh,
replacing H8's "a SIMD vector return keeps its pre-6.7.11 word" row.
