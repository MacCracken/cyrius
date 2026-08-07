# SIMD `f64v_*` ops are memory-operand array kernels — no register-resident vector-value arithmetic, so hand-SIMD of a tight per-element chain gets ~no speedup

**Status:** 🟡 **OPEN** — the root cause is unchanged. **Re-read live on cycc 6.5.10, 2026-08-07:**
`EMIT_F64V_LOOP` (`src/backend/x86/float.cyr:152`) still emits exactly the
`movupd xmm0,[rdx+rsi*8]` → `addpd/subpd/mulpd/divpd` → `movupd [rdx+rsi*8],xmm0` shape described
below, with **no AVX branch and no register-residency path**, and there is no value-form f64v
arithmetic emitter.
**One correction to the fix list, not to the verdict:** item 3 ("true 256-bit AVX") has since landed
**for f32 only** — `EMIT_F32V_LOOP` (`float.cyr:191`, widened at `:217-248` to
`vmovups`/`vaddps`/`vsubps`/`vmulps` **ymm** + `vzeroupper`) and the FMA/dot emitters (`:271-278`
`vfmadd231ps ymm`, `:295-304`) during the v6.4.x SIMD arc. `f64v4` was **not** widened and is still a
two-iteration `xmm` loop, so both item 3 (for f64) and the load-bearing items 1–2 remain open. The
v6.4.31/.53 work on value-form SIMD *params and returns* is a different thing from register-resident
*arithmetic chains* — do not read it as closing this.
**Placement:** **v6.5.x Slot 6 (`.24`–`.25`) — "SIMD register residency"** (`roadmap.md` v6.5.x slot
table, verified live 2026-08-07; scope recorded there as **fix-list items 1–3 only**). Explicitly
**gated behind** the IR-substrate anchor at Slot 3
([`2026-07-02-ir-regalloc-rewrite-needs-reemit.md`](2026-07-02-ir-regalloc-rewrite-needs-reemit.md)):
this is a codegen-QUALITY gap — bit-identical output, no wrong results — so it cannot batch ahead of
the substrate that has to model a vector register class. 6.x line, never 7.x.

- **Filed**: 2026-07-06 (found optimizing svara formant synthesis; repro on cc 6.4.12)
- **Severity**: P2 (Medium) — codegen *quality*, not correctness. The vector path is
  bit-identical and safe; this is an optimization gap that caps first-party numeric /
  DSP code far below the Rust/LLVM baseline (svara synthesis runs 10–38× its Rust
  equivalent). No wrong results, no memory-unsafety.
- **Scope**: the `f64v_*` / `f64v2` / `f64v4` arithmetic emitters in
  `src/backend/x86/float.cyr`. Affects any tight per-element numeric recurrence;
  surfaced in svara (audio synthesis). This is a **compiler** item — svara used the
  SIMD API exactly as designed.

## Symptom

Hand-vectorizing a tight per-sample DSP loop with the `f64v4` API compiles, passes
tolerance (bit-identical to the scalar path), and delivers **~no speedup** — where
the same restructure under LLVM is 2–4×.

Concrete case: svara's 8-slot SOA formant biquad bank
(`svara_formant_bank_process`, `svara/src/formant.cyr`). Per sample it computes
`y = b0·in + b2·x2 − a1·y1 − a2·y2` for 8 independent biquads (perfect SIMD shape —
per-lane-independent, already SOA-laid-out). A bit-identical `f64v4` rewrite (two
4-lane groups) measured (`benches/hotpath.bcyr`, cc 6.4.12):

| | scalar | hand-`f64v4` | Rust/LLVM |
|---|---|---|---|
| `formant process_sample` | 176 ns | 158 ns (~10%) | ~4.7 ns |
| `formant process_block 1024` | 186 µs | 181 µs (~3%) | 4.84 µs |

~5% instead of the expected multiple. The scalar↔Rust gap is **38×**; hand-SIMD
barely dented it.

## Root cause

The `f64v_*` primitives are **bulk-array kernels**, not register-resident
vector-value operations. `EMIT_F64V_LOOP` (`src/backend/x86/float.cyr:152-184`,
re-derived 2026-08-07) emits, per operation:

```
# rdx = a base;  movupd xmm0, [rdx+rsi*8]     # load operand A from MEMORY
# rdx = b base;  movupd xmm1, [rdx+rsi*8]     # load operand B from MEMORY
#                addpd/mulpd xmm0, xmm1        # the SIMD op
# rdx = dst base; movupd [rdx+rsi*8], xmm0    # store result to MEMORY
```

i.e. every op is *memory → xmm → op → memory*, indexed off pointers, looped over
`n`. Consequences for a per-element chain:

1. **No register residency across a chain.** The lib wrappers pass everything by
   address — `f64v4_mul(a, b)` is `var r: f64v4; f64v_mul(&r, &a, &b, 4); return r`
   (`lib/simd.cyr`). So a chain like `t = b0·in + b2·x2 − a1·y1 − a2·y2` performs
   ~7 memory round-trips of the intermediate `t`/`m` per 4-lane group. LLVM keeps
   those intermediates in `xmm`/`ymm` and touches memory only at the chain's edges.
2. **f64v4 is emitted as SSE2 (`xmm`, 2-wide) looped**, not one 256-bit AVX op —
   `movupd xmm` + a loop over `n`, so a 4-lane op is 2 iterations with loop
   overhead, even when `simd_has_avx2()` is true. (`EMIT_F64V_DOT:533`,
   `EMIT_F64V_SCALE:569`, `EMIT_F64V_FMADD:634` — line numbers re-derived
   2026-08-07, all still the same xmm-loop shape. The f32 siblings did get the
   ymm treatment; the f64 ones did not.)
3. **No auto-vectorizer** — a scalar SOA loop is emitted lane-by-lane; there is no
   pass that packs it. So the *only* way to vectorize is by hand, and (1)+(2) then
   throttle the hand-written version.

For a **tight per-element recurrence**, the memory traffic dominates and the packed
arithmetic is a rounding error on the total — which is exactly the measured ~5%.
The API is well-suited to its design target (long-buffer bulk ops — dot products,
`scale`/`add` over big arrays — where the `[base+rsi*8]` streaming amortizes), just
not to register-resident chains.

## Impact

- First-party numeric / DSP code can't be meaningfully SIMD-accelerated for
  per-element recurrences. svara's synthesis core (formant bank, vocal tract) is
  10–38× its Rust baseline (`svara/docs/benchmarks-rust-v-cyrius.md`) and hand-SIMD
  does not close it, so the gap is a compiler ceiling, not a usage problem.
- Any consumer reaching for `f64v4` to speed up a filter/transform/solver inner
  loop will hit the same wall and (reasonably) conclude SIMD "doesn't work here."

## Suggested fix direction (compiler — within Cyrius's repair abilities)

1. **Register-operand vector arithmetic.** Provide an emission path for the
   value-form ops (`f64v4_add(a, b)`, `_mul`, `_sub`, `_fmadd`, …) that keeps the
   `f64v4` SSA values in vector registers and emits `vaddpd/vmulpd/vfmadd… ymm,
   ymm, ymm` (reg-reg-reg), loading/storing only at the chain's boundaries —
   distinct from the memory-loop array kernels, which stay for the `_ptr`/bulk
   forms. Needs the register allocator to model the vector register class (may
   intersect [`2026-07-02-ir-regalloc-rewrite-needs-reemit.md`](2026-07-02-ir-regalloc-rewrite-needs-reemit.md)).
2. **Inline the `f64v4_*` wrappers + `f64v_*` builtins** so the backend sees the
   whole chain and can keep intermediates resident instead of round-tripping each
   op through a `&r` stack slot.
3. **True 256-bit AVX for f64v4** — one `vmulpd ymm` (4-wide) under
   `simd_has_avx2()`, rather than a 2-iteration `xmm` loop.
4. *(Longer term)* auto-vectorization of scalar per-element loops with an SOA shape,
   so consumers get it without hand-SIMD.

Item 1 (or 1+2) is the high-leverage one: it's what makes hand-written SIMD chains
actually pay off, and it's the piece LLVM has that Cyrius doesn't.

**Out of scope (not a compiler item):** the caller can also cut memory traffic with
data-layout changes (e.g. svara's formant bank stores a per-slot input delay line
that is identical across slots) — that is the *consumer's* optimization and is
tracked svara-side, not here.

## Reproducer

- `svara/src/formant.cyr` — `svara_formant_bank_process` (the scalar 8-slot SOA
  biquad loop that stays memory-bound).
- `svara/benches/hotpath.bcyr` — `formant filter process_block 1024` (186 µs) vs
  Rust `formant_filter_1024` (4.84 µs). A bit-identical `f64v4` prototype of the
  loop measured 181 µs (~3%) on 2026-07-06 before being reverted (svara 3.1.0
  CHANGELOG "Notes"). No compiler source was modified.
