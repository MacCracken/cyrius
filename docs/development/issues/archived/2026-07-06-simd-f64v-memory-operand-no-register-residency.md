> ### ✅ CLOSED at v6.5.66. Items 1 and 2 shipped across v6.5.64–.66; item 3 shipped at v6.5.24.
>
> **Item 1 — register-operand vector arithmetic.** `EMIT_VEC_DIRECT` (`backend/x86/float.cyr`)
> emits `movupd`/packed-op/`movupd` on frame displacements for a constant-lane op on `&local`
> operands, chosen by pure token lookahead in `_try_vec_direct`. Intermediates now stay in `xmm0`
> ACROSS chain links — the file's own ask, "loading/storing only at the chain's boundaries".
> Verified in the emitted code: in a 3-link chain, links 2 and 3 carry no accumulator reload.
>
> **Item 2 — inline the wrappers so the backend sees the whole chain.** Shipped v6.5.58 (the
> predicate saw wide params of every width), v6.5.63 (`#inline`), and completed here: the replay's
> param COPY is redirected (v6.5.65 provenance) and then harvested when dead (v6.5.66).
>
> **Measured, latency-bound 3-link chain (2M iterations, best-of-15, pinned, idle box):**
>
> | | f32v4 | f64v2 |
> |---|---|---|
> | v6.5.63 baseline | 33.36 ms | 33.52 ms |
> | v6.5.66 | **13.34 ms** | **12.88 ms** |
> | | **2.50×** | **2.60×** |
>
> ⛔ **THE FILING'S DIAGNOSIS WAS RIGHT AND ITS IMPLIED FIX WAS NOT.** It reads as "the memory
> round-trips are the cost, so remove them". Measured before building: a hand-written replica
> that removes exactly that scaffolding — 22 of 28 instructions per link — runs **33.99 ms against
> 33.96 ms, i.e. 1.00×**. The cost is 16-byte **store-to-load forwards**, not instruction count.
> Every gain above came from deleting a FORWARD; the instruction savings were incidental.
>
> ⚠ **What is NOT done, stated honestly.** The measured ceiling for a fully register-resident
> chain was **8.26×**; this is 2.5×. The gap is the per-link result store plus the loop-carried
> round-trip through the accumulator across the loop back-edge — that needs vector allocation at
> LOOP scope, which is a different problem from the chain this issue is about. Item 4
> (auto-vectorisation) was explicitly out of scope in the filing and remains so.
>
> **Gates:** `tests/gates/codegen/simd_direct_form.sh` (8 axes, every one mutation-proven),
> `tests/tcyr/crossos/simd_inline_param_provenance.tcyr`, `tests/tcyr/crossos/simd_param_then_scalar.tcyr`.

# SIMD `f64v_*` ops are memory-operand array kernels — no register-resident vector-value arithmetic, so hand-SIMD of a tight per-element chain gets ~no speedup

**Status:** ✅ **CLOSED at v6.5.66** — see the header above.

> ### ✅ Item 3 (256-bit AVX for f64) is DONE — v6.5.24
>
> `EMIT_F64V4_LOOP` (`src/backend/x86/float.cyr`) emits `vaddpd`/`vsubpd`/`vmulpd`/`vdivpd`
> on **ymm**, four f64 lanes per iteration, reached through four builtins
> (`f64v256_add`/`sub`/`mul`/`div`) whose `lib/simd.cyr` wrappers gate on
> `simd_has_avx2()`. All eight f64v4 wrappers (4 ops × value/`_ptr`) take it when the host
> has AVX2. **Measured 15.9 → ~7.9 ns.** Named for register width, not lane count, because
> `f64v4_add` is already a lib value-form fn.
>
> ⛔ **AND IT NEEDED NO SUBSTRATE.** This filing bundles item 3 with items 1-2, and the
> roadmap gated all three behind Slot 3's IR/regalloc work — so a self-contained emitter
> mirroring `EMIT_F32V8_LOOP`, worth a measured 2×, sat unbuilt waiting on machinery it never
> required. **Bundling a substrate-independent item with substrate-dependent ones is what
> delayed it**; that is the transferable lesson, not the encoding.
>
> Gate `tests/gates/codegen/f64v4_ymm_disasm.sh` pins the exact VEX bytes AND mnemonics
> (`pd` vs `ps` is one bit in the second VEX byte) plus the 4-lane stride — mutation-proven,
> and the stride mutation is the one a value test cannot catch: it left
> `crossos/f64v4_ymm.tcyr` passing 23/23 while writing 16 bytes past the vector.

**Still open — items 1 and 2, unchanged and genuinely substrate-dependent.** Re-read live on
cycc 6.5.25: `EMIT_F64V_LOOP` remains the `movupd xmm0,[rdx+rsi*8]` → `addpd` → `movupd`
memory-loop shape for the 128-bit path, and there is **still no value-form f64v arithmetic
emitter** — only `EMIT_F64V_{LOOP,UNARY,DOT,SCALE,AXPY,FMADD}`, all memory-loop. The 25
value-form `lib/simd.cyr` wrappers still round-trip through memory. Those two need the
register-residency substrate (roadmap band F/Slot 5) and are correctly pinned there; the
`_ptr`/bulk forms stay memory-loop by design.
v6.4.31/.53 work on value-form SIMD *params and returns* is a different thing from register-resident
*arithmetic chains* — do not read it as closing this.
**Placement:** **SPLIT — the three fix-list items do NOT share a slot.** Items 1–2 (register-resident value-form arithmetic; wrapper inlining) are **v6.5.31–.32 — band G, Slot 6**, hard-gated on the IR substrate. ⭐ **Item 3 is NOT gated and moves to v6.5.24/.25 (bands C/D).**

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⭐ **FIX-LIST ITEM 3 NEVER NEEDED THE SUBSTRATE.** Widening f64v4 to `vmulpd`/`vaddpd` ymm is a self-contained emitter mirroring `EMIT_F32V8_LOOP` (`src/backend/x86/float.cyr:226-250`), needing only a `simd_has_avx2()`-gated wrapper and a distinct builtin. Measured **15.9 → ~7.9 ns** available today. The roadmap gated all three behind Slot 3 for no reason. ⚠ The ymm loop advances `rsi += 4`, so it CANNOT be selected for the n=2 f64v2 caller. Items 1–2 genuinely need the substrate.
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
