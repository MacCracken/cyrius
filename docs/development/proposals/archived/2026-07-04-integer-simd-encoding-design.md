# Packed SIMD compute (f32-first, then integer) — Phase 0 encoding design decision (the pin)

> **Arc**: v6.4.x SIMD-compute (ML/AI priority). **Sequence pivot (user 2026-07-04): f32
> SIMD compute FIRST, then the lower-int lanes.** Model testing shows f32+SIMD is the primary
> throughput lever, with int8/quantized lanes as the optimization layer on top. **Phase 0 —
> the encoding design gate**: no emit code until the type-class encoding + param-mask +
> builtin-dispatch are pinned (they drive the whole 5–7 release arc and are expensive to
> reverse). Grounded in a 2026-07-04 code-mapping pass (exact file:line sites verified
> in-tree). Companion: [`2026-06-23-integer-simd.md`](2026-06-23-integer-simd.md).

## Design frame — the i64 oracle + free type movement (user 2026-07-04)

The durable type-model principle this arc extends: **`i64` is the ORACLE** — the canonical,
default, ground-truth type — and every other type (`i8/i16/i32`, `u8..u64`, `f32/f64`, and
the vector types) is a **view/optimization** you can **move freely into and out of, always
returning to i64**. This is already the embryonic architecture: `i64` is the untyped default;
sub-width ints are SLTYPE-sentinel views; floats live in a separate TYID channel reached by a
**conversion hub** that is already heavily used — `f64_from` (i64→float, 125×), `f64_to`
(float→i64, 56×), `f32_from`/`f32_to` (narrow/widen), `cvt*`. Scalar float arithmetic already
funnels through `f64` (f32 is storage-only today; `parse_expr.cyr:506` resets an f32 load to
i64/untyped). **The SIMD types are the next views on this lattice**: a vector is N lanes of an
element type; you enter it by broadcast/load and **return to the i64 oracle by extract/reduce**.
The encoding below is chosen so vectors are first-class *views* — freely convertible, never a
parallel type universe — with `i64` still the anchor everything reduces to.

## The problem — three walls the f64-only encoding hits

Cyrius SIMD is **f64-only** today: exactly two vector types, `f64v2` (16 B) / `f64v4`
(32 B), carried as the negative SLTYPE sentinels **−20 / −21**. The integer arc needs **8**
vector types (`i8v16 i8v32 i16v8 i16v16 i32v4 i32v8 i64v2 i64v4`) plus a real integer op
set. Three independent walls block "just add more sentinels":

1. **Sentinel collision with struct sids.** SLTYPE stores a struct-typed local as `0 − sid`,
   `sid ∈ 1..1024` (cap at `parse_types.cyr:75`). The SIMD codes −20/−21 sit **inside** that
   band; `parse_decl.cyr:1449` literally does `if (sv_sid==20) sz=16` on a negated struct sid.
   It's latent today (SIMD vs struct locals arrive on different decl branches), but 8 more
   sentinels in the −1..−1024 band widen the collision surface 4×. There is no tag bit
   distinguishing "this negative number is a struct sid" from "…a type-class sentinel."
2. **A flat sentinel per type → an N-arm ladder explosion.** One flat integer per type means
   the backend grows an 8-way `if lt==−22 elif −23…` in **every** emit / return / param path
   (5 backends × ~3 paths ≈ a 120-arm explosion), and nothing is derivable (lane width, count,
   signedness) — it's all hard-coded per code.
3. **The 2-bit param mask is saturated.** `_fnt_simdmask` gives 2 bits/param (`00`=int,
   `01`=f64v2, `10`=f64v4, `11`=free) — it cannot encode 10 SIMD classes.

## The decision — a structured descriptor, additive to the f64 path

The four independent facet-maps converged on the same shape. **Do not widen the −20/−21
range.** Encode an integer vector as a **structured descriptor in a reserved sentinel band
clearly below the struct-sid floor**, decoded arithmetically by one helper, and keep the
existing f64 machinery byte-identical.

### 1. Type-class encoding — structured SLTYPE descriptor + one decoder

- Reserve a band **`SIMD_BASE = −2048` and below** (struct sids ≤ 1024, so this is
  collision-free with 1024 of headroom). An integer vector local/return/param carries
  `SLTYPE = −(SIMD_BASE + desc)` where `desc` packs the vector shape:
  `desc = (elem_log2 << 4) | (lanes_log2 << 1) | signed` — `elem_log2` 0..3 = i8/i16/i32/i64,
  `lanes_log2` gives 128b vs 256b, `signed` = 1 bit. (Exact bit layout finalized in Phase 1;
  the invariant is: **shape is derivable by shift+mask, not a per-type code**.)
- **One decoder** `_vec_desc(sltype) → (nslots, lane_bytes, is_256, signed, elem_class,
  opfamily)` replaces every `== −20 / == −21` byte-compare in var-decl sizing, the return ABI,
  the param ABI, and the emitters.
- **f64v2/f64v4 KEEP −20/−21** in release-1 — the f64 code path is untouched, so **every
  existing (f64-only) SIMD program is byte-identical** and the differential + self-host gates
  stay green from the first release. A later cleanup can fold f64 onto the unified descriptor;
  it is explicitly **not** release-1 scope.

### 2. Param passing — keep the 2-bit mask coarse, full descriptor in SLTYPE

- Keep `_fnt_simdmask` as-is (2 bits/param) as a **coarse route-to-vector-reg flag**
  (`01` = one XMM/V reg / 128b, `10` = two / 256b) — byte-identical for f64. The **full
  integer descriptor lives in the param's own SLTYPE** (params are locals; they have SLTYPE),
  re-read per-arg by `PARSE_FNCALL`. No new param side-table, no cap change (32 params stays),
  and the `simd_pc` XMM/V ordinal counter (128b=+1 reg, 256b=+2) is reused verbatim.

### 3. Builtin dispatch — collapse the op explosion into a table

- Add **four width-keyed lexer tokens** `isimd8 / isimd16 / isimd32 / isimd64` (reusing the
  existing `LEXKW` byte-compare pattern — 4 new arms, not 60–130; the lane width is statically
  visible to the emitter). Each carries an **op operand**.
- Add **one emitter per backend** `EMIT_ISIMD(op, width, signed, vbase)` that switches `op` to
  the packed-integer opcode — **lifting the existing `EMIT_F64V` op→opcode-byte table** one
  level up (`float.cyr:51-54`/`147-149` is `addpd/subpd/mulpd = 0x58/0x5C/0x59`; the integer
  analog is `paddb/w/d/q`, `pand/por/pxor`, `psllw/d/q`, `pcmpeqb/w/d`, `pcmpgtb/w/d`,
  `pmaddubsw`+`pmaddwd` for widening-madd, `phaddw` for hreduce). One dispatch site, a table
  per op — not an if-chain per (op × width).

### 4. Reuse verbatim (no per-width work)

The **pair(2-slot, 128b) / quad(4-slot, 256b) return + param + frame allocator** is
byte-width-generic — `i8v16/i16v8/i32v4/i64v2` are all 16 B (2 slots) and the `…v32/…v4`
forms all 32 B (4 slots), so they reuse `parse_fn.cyr:2966-2980` + `parse_decl.cyr:1449-1450`
slot sizing and the multi-register return ABI (rax/rdx, XMM0, V0, cx r0/r1) **unchanged**. The
`_F64V_DISP` frame-disp formula and the `simd_pc` budget check are reused as-is.

## Release-1 minimal op set — f32 dense matmul (the ML lever)

`f32v4` (128-bit, 4 lanes) **reuses the existing f64 SSE packed path minus the `66` prefix** —
`mulps` = `0F 59` vs `mulpd` = `66 0F 59`, `addps` = `0F 58` vs `addpd` = `66 0F 58` — and the
same 16-byte register + pair/quad slot machinery. The dense-f32 matmul / attention inner loop,
x86 128-bit first:

- `f32v4` load / store / **broadcast** (splat a scalar across 4 lanes)
- **`addps` / `subps` / `mulps`** (packed single add/sub/mul)
- **FMA** — `vfmadd231ps` where AVX2+FMA is present (feature-gated; `mul`+`add` fallback
  otherwise) — the matmul/attention multiply-accumulate
- **horizontal reduce / dot** to a scalar accumulator (`haddps` / shuffle-add, or `dpps` for a
  4-wide dot) → **returns to the f64/i64 oracle**

That's the dense-f32 GEMM/attention inner loop — the primary throughput lever. **Then the
integer layer** (the tentib b1.58 quantized kernel: `i8` load + sign-select via mask-blend +
`i16` widening multiply-accumulate `pmaddubsw`→`pmaddwd` / VNNI `vpdpbusd` + horizontal reduce)
rides the **same** `EMIT_ISIMD` op-table with the packed-integer opcodes. `f32v8` + AVX2 256-bit
and aarch64 NEON (`fmla`/`sdot`) fill in later phases.

## Phase plan (this doc = Phase 0) — f32-first

- **Phase 0 ✅ (this doc)** — encoding + dispatch + f32-first minimal-op decision pinned.
- **Phase 1** — `f32v4` end-to-end on x86: descriptor + `_vec_desc`, var-decl, return/param
  ABI, value/pointer dual-form, load/store/broadcast + `addps`/`mulps`. Reuses the f64 SSE
  packed path (minus the `66` prefix) → the lowest-risk first lane. Byte-identical default (the
  existing f64v2/f64v4 path untouched); differential status-diff=0.
- **Phase 2** — the f32 matmul op set (FMA + horizontal-dot) + a dense-f32 GEMM/attention
  acceptance bench, x86, bench-gated (the ML throughput proof).
- **Phase 3** — the integer lanes (`i8v16`/`i16v8`/`i32v4`/`i64v2`) on the same `EMIT_ISIMD`
  op-table + the tentib-0.4.1 b1.58 quantized-kernel bench.
- **Phase 4** — `f32v8` + the `256-bit` (AVX2) matrix across f32 + int.
- **Phase 5** — aarch64 NEON parity (`fmla`/`sdot`) + cx stubs + PE gating (mandatory
  cross-arch, 4-host self-host each release).
- **Phase 6** — `lib/simd.cyr` `f32vN`/`iNvM` wrappers + guide/vidya docs.
- **Phase 7** — repair tail (budgeted 1–2; the generics-arc .37/.38/.39 precedent).

## Runtime prerequisite on agnos — the shared XMM-state layer

All of this — scalar `f64` (already emitted), `f32`/`f64` SIMD, AND integer SIMD — lives in the
**XMM/YMM register file**. On agnos ring-3 today XMM state is not enabled/context-switched, so the
first `movq %rax,%xmm0` (already emitted by scalar `f64_*`) `#UD`s. The agnos kernel arc that fixes it
— CR4.OSFXSR/OSXMMEXCPT + CR0.MP/EM + `fninit` per core + per-proc `fxsave`/`fxrstor` across context
switches — is **one prerequisite for the whole SIMD/FP surface, not one-per-feature**: when the
int-SIMD instructions land they will `#UD` on agnos for the *exact same reason* scalar f64 does today.
**No cyrius change is required to start that agnos arc** (scalar f64 is sufficient to build + iron-prove
the XMM-state layer); f32/int-SIMD are the *next* consumers of that one `fxsave` proof. Recorded per the
2026-07-04 agnos FP coordination issue §3. The **v6.4.3** `f64v2`/`f64v4` constructors + splat are the
ergonomic complement (§2) — the value-form vectors they build also need this same XMM-state layer to
*run* on agnos, but compile + run on every XMM-enabled host today.

## Sub-decisions folded into this recommendation (open to adjust)

1. **Descriptor in the sentinel vs a side-table** → **sentinel** (recommended): no new heap
   region / no 7-fork `_fnt_grow` addition, one lookup, and the reserved band is collision-free.
   (Facet 1/2 floated a side-table; the sentinel is lower-churn given the descriptor is small.)
2. **Element-classes covered by the descriptor** → **f32 leads, then i8/i16/i32/i64** (u* fold
   in via the signed bit). **Legacy f64v2/f64v4 keep −20/−21** in release-1 for byte-identity;
   f32vN + the integer lanes use the new structured band. (A later cleanup can fold f64 onto the
   unified descriptor — optional, not release-1.)
3. **Builtin dispatch surface** → a single **op-table** per backend (`EMIT_ISIMD`/`EMIT_VSIMD`)
   keyed by the descriptor's (element-class, op) — the exact token spelling (per-type `f32v4`/
   `i8v16` names vs a `vsimd(op, …)` family) is a Phase-1 detail; the load-bearing decision is
   **one dispatch table, not an if-chain per (op × class × width)**.
4. **Release-1 arch** → **x86 128-bit first** (f32v4 rides the proven f64 SSE path), aarch64
   NEON in Phase 5 (arc lands x86, then the mandatory cross-arch propagation).

**Status: Phase 0 design pinned (f32-first), pending sign-off. On approval → Phase 1 (`f32v4`
end-to-end, x86 — the lowest-risk lane, reusing the f64 SSE packed path).**
