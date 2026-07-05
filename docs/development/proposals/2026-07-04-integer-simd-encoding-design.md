# Integer SIMD — Phase 0 encoding design decision (the pin)

> **Arc**: v6.4.x integer SIMD (arc opener, ML/AI priority). **Phase 0 — the encoding
> design gate**: no emit code until the type-class encoding + param-mask + builtin-dispatch
> scheme are pinned (they drive the whole 5–7 release arc and are expensive to reverse).
> Grounded in a 2026-07-04 code-mapping pass (exact file:line sites verified in-tree).
> Companion: [`2026-06-23-integer-simd.md`](2026-06-23-integer-simd.md) (the arc proposal).

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

## Release-1 minimal op set (unblock tentib 0.4.1, not the full matrix)

The tentib b1.58 ternary matmul-free kernel needs only a small op set — ship **that** first,
x86 128-bit (SSE2/SSSE3) only:

- `i8` load / store / broadcast
- **sign-select** (ternary {−1,0,+1} select via mask-blend: `pcmpgtb` + `pand`/`pandn`/`por`)
- **`i16` widening multiply-accumulate** (`pmaddubsw` → `pmaddwd`; VNNI `vpdpbusd` where the
  host has it — feature-gated, SSE2 fallback otherwise)
- **horizontal reduce** to a scalar accumulator (`phaddw`/`phaddd` or shuffle-add)

That's the whole b1.58 inner loop. The full lane-op matrix (add/sub/and/or/xor/shl/shr/cmp/
blend/broadcast across all widths) + AVX2 256-bit + aarch64 NEON (`sdot`/`smlal`) fill in
across Phases 2–4.

## Phase plan (this doc = Phase 0)

- **Phase 0 ✅ (this doc)** — encoding + dispatch + minimal-op decision pinned.
- **Phase 1** — one lane width (`i8v16`) end-to-end on x86: descriptor + `_vec_desc`, var-decl,
  return ABI, param ABI, value/pointer dual-form. Prove the encoding scales. Byte-identical
  default (f64 untouched); differential status-diff=0.
- **Phase 2** — the release-1 op set + tentib-0.4.1 acceptance bench, x86, bench-gated.
- **Phase 3** — fill the `i8/i16/i32/i64 × 128/256-bit` matrix (AVX2).
- **Phase 4** — aarch64 NEON parity (`sdot`/`smlal`) + cx stubs + PE gating (mandatory
  cross-arch, 4-host self-host each release).
- **Phase 5** — `lib/simd.cyr` `iNvM` wrappers + guide/vidya docs.
- **Phase 6** — repair tail (budgeted 1–2; lane-width sign-ext, widening overflow, cross-arch
  mask divergence — the generics-arc .37/.38/.39 precedent).

## Sub-decisions folded into this recommendation (open to adjust)

1. **Descriptor in the sentinel vs a side-table** → **sentinel** (recommended): no new heap
   region / no 7-fork `_fnt_grow` addition, one lookup, and the reserved band is collision-free.
   (Facet 1/2 floated a side-table; the sentinel is lower-churn given the descriptor is small.)
2. **Fold f64 onto the unified scheme now vs later** → **later** (recommended): keep −20/−21 in
   release-1 for byte-identity; unify as an optional cleanup once integer lands.
3. **4 width-tokens vs one `isimd` family** → **4 width-tokens** (recommended): lower churn,
   width statically visible, reuses the `LEXKW` pattern.
4. **Release-1 arch** → **x86 128-bit first**, aarch64 NEON in Phase 4 (arc lands x86, then the
   mandatory cross-arch propagation).

**Status: Phase 0 design pinned, pending sign-off. On approval → Phase 1 (i8v16 end-to-end,
x86).**
