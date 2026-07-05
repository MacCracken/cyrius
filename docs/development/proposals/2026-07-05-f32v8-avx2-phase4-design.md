# SIMD Phase 4 — f32v8 + 256-bit AVX2 (design + implementation reference)

- **Filed**: 2026-07-05 (SIMD arc Pin 1, after v6.4.7 closed the integer sub-arc)
- **Status**: DESIGN PINNED — decisions made by user 2026-07-05 at arc-open,
  grounded in a code-level premise-check (this doc). Implementation = the next
  release(s) in the SIMD arc.
- **Scope**: x86-only (aarch64 256-bit = 2×NEON is a Phase-5 concern; cx stubs; PE gated).
- **Precedent**: mirrors `proposals/2026-07-04-integer-simd-encoding-design.md` (Phase 0).

All VEX byte sequences below were assembled with `llvm-mc -triple=x86_64
--show-encoding` and round-trip-verified with `objdump`. None are hand-guessed.

---

## 1. Ground truth (premise-check, cited to the tree at v6.4.7)

- **No 256-bit AVX exists anywhere.** The only "256-bit" type, `f64v4`, is a
  count-driven **128-bit SSE2 loop** — `EMIT_F64V_LOOP` (`src/backend/x86/float.cyr:128`)
  emits `movupd`/`addpd` on **xmm** and strides `rsi += 2`; `f64v4` just passes `n=4`
  so the loop runs twice. Its value-form ABI is two 128-bit `movupd` into `xmm/xmm+1`
  (`ESTOREPARM_F64V4`, `emit.cyr:2770`), never a `ymm`. A full `src/` scan for
  `ymm|vaddps|vfmadd|vzeroupper` returns only a comment: `decode.cyr:6` "no AVX/VEX/EVEX".
  **VEX encoding is fully greenfield.**
- **The descriptor already fits f32v8 cleanly**: sentinel **−2153** (is_float 1,
  signed 1, lane_log2 2 = f32/4B, lanes_log2 3 = 8 lanes → desc 105 → −(2048+105)).
  Decodes to 32B / 4-slot (`GVEC_NSLOTS==4`) / lane-width 4. The `lt <= 0-2048`
  struct-guard (`parse_decl.cyr:210,418`) and the size-set (`parse_decl.cyr:1489`,
  `GVEC_NSLOTS*8`) handle −2153 with **no change**. The name `f32v8` low-3-bytes = `f32`,
  so its recognizer must precede the 3-byte scalar `f32` check (same ordering as f32v4
  at `parse_decl.cyr:1404`).
- **`_is_simd256` is lane-width-blind**: it keys on `nslots==4` (`util.cyr:662`), which
  f32v8 and f64v4 **share**, and currently has **zero callers**. Any op keyed on it must
  re-read `GVEC_LANEB` (4 for f32v8 vs 8 for f64v4).
- **The 2-bit param mask is saturated** (codes 0/1/2/3 all used) → value-form f32v8 would
  need a mask widening (the Phase 3b wall). Avoided by shipping pointer-form first.
- **Highest builtin token = 146** (`iv_dp8`). **147+ free.**

## 2. Decisions (user, 2026-07-05)

1. **AVX2 model = real AVX2 + CPUID runtime fallback.** f32v8 emits `vaddps ymm` when
   the CPU has AVX2 (SSE2 is x86-64 baseline; `vaddps ymm` SIGILLs on pre-AVX2), falling
   back to a 2×SSE path when absent. cycc has no f32v8 → the **compiler stays SSE2 and
   self-hosts byte-identical everywhere**; only consumer programs calling f32v8 exercise
   the dispatch.
2. **Lib form = pointer-form first** (`f32v8_add_ptr`/`_make`/`_lane…`); value-form deferred.
3. **Pre-planned 2-release split** (boundary fixed here, not mid-execution): see §5.

## 3. The CPUID runtime fallback — a clone of a shipping pattern (NOT a new subsystem)

Every primitive exists and is battle-tested. **`cpuid` already emits two ways**: the
shipping inline-asm probes `_aes_ni_cpuid_probe` (`lib/sigil.cyr:5989`) and
`_sha_ni_cpuid_probe` (`lib/sigil.cyr:4513`, **already reads CPUID leaf 7 / EBX** — AVX2
is the same leaf, bit 5 instead of 29), AND `cpuid` is a first-class mnemonic
(`emit.cyr:3227` → `0F A2`). The cached-global dispatch idiom is `aes_ni_available()`
(`lib/sigil.cyr:5927`) — `_cache = 2` sentinel + `atomic_cas` (`lib/atomic.cyr:53`)
one-shot latch.

**Decisive architectural fact**: SIMD ops emit *inline*, but every consumer routes
through a **single-call-site lib wrapper** (`lib/simd.cyr:275,302`). Branching inside the
wrapper emits each path exactly **once program-wide — zero per-call-site bloat**:

```
var _avx2_cache = 2;          # 2=uncached 0=no 1=yes   (clone sigil.cyr:5913)
fn _avx2_cpuid_probe(out): i64 {          # clone _sha_ni_cpuid_probe, leaf 7 EBX
    #ifdef CYRIUS_ARCH_X86
    asm { param_load(rdi,0); 0x53; mov eax,7; xor ecx,ecx; cpuid; mov [rdi],rbx; 0x5B; }
    #endif
    return 0;
}
fn simd_has_avx2(): i64 {                 # clone aes_ni_available()
    if (_avx2_cache != 2) { return _avx2_cache; }
    ... atomic_cas one-shot latch; probe; test EBX bit 5 (+ optional xgetbv XCR0 1&2) ...
    return _avx2_cache;
}
fn f32v8_add_ptr(a, b): f32v8 {
    var r: f32v8;
    if (simd_has_avx2() == 1) { f32v8_add(&r, a, b, 8); }   # AVX2 → EMIT_F32V8_LOOP
    else { f32v_add(&r, a, b, 8); }                          # 2×SSE (EMIT_F32V_LOOP, n=8 = 2 iters)
    return r;
}
```

**Only genuinely new**: the 256-bit VEX emit helper, and an optional `xgetbv`
(`0F 01 D0`, XCR0 OS-AVX-state bits 1&2 — the *correct* probe; raw asm bytes work today,
no compiler change). CPUID.7.EBX.5 alone is acceptable on any modern OS (always enables AVX).

**Hosts**: local build/bench box **has AVX2** (`/proc/cpuinfo` avx+avx2) → the AVX2 path
runs locally; force `_avx2_cache=0` to test the SSE path. ecb (macOS/arm64) + pi (aarch64)
can't run AVX2 (they hit the aarch64 stubs); cass (Windows/x86) depends on its CPU.

## 4. f32v4 op template (exact current bytes — the thing f32v8 parallels)

`src/backend/x86/float.cyr`. Shared skeleton: `rcx=n`, `rsi=0`, `cmp rsi,rcx / jge done`,
body, `add rsi,4`, `jmp top`. Base ptr reloaded per operand via `_EMIT_LOAD_RDX_FROM_LOCAL`
(`48 8B 95 <disp32>`, always disp32 — `float.cyr:104`). SIB `0xB2` = `[rdx+rsi*4]`.

- **EMIT_F32V_LOOP** (`float.cyr:167`): `movups xmm0,[rdx+rsi*4]` = `0F 10 04 B2`;
  `movups xmm1` = `0F 10 0C B2`; add/sub/mul = `0F 58/5C/59 C1`; store = `0F 11 04 B2`;
  `add rsi,4` = `48 83 C6 04`. (= the f64 packed loop **minus 66**, SIB B2 not F2, step 4.)
- **EMIT_F32V_FMADD** (`float.cyr:200`, args dst,a,b,c,n): `mulps` then `addps` then store.
  **Footgun (float.cyr:196): over-WRITES up to 3 dst lanes past n** — lib wrappers pin n=4.
- **EMIT_F32V_DOT** (`float.cyr:232`, args a,b,n): `xorps xmm2,xmm2`; loop `mulps`+`addps xmm2`;
  then **two `haddps xmm2,xmm2`** (`F2 0F 7C D2`) + `movd eax,xmm2` (`66 0F 7E D0`).
  **Footgun: over-READS up to 3 lanes past n** (zero-pad).

Wiring: lexer `lex.cyr` (f32v_add=138…f32v_dot=142, iv_*=143-146; klen-masked u64 compare);
`parse_expr.cyr` PARSE_TERM dispatch (`:2076` 141-142, `:2078` 143-146; stmt-form 138-140
inline `:2142`) + PARSE_SIMD_EXT handlers; `parse.cyr` statement range guards; non-x86 stubs
`aarch64/emit.cyr:2308`, `cx/emit.cyr:829`.

## 5. Scoped 2-release plan

### Release 1 — VEX substrate + f32v8 elementwise (pointer-form)
- **Descriptor/type-name**: add `f32v8` (−2153) to `_classify_param_type`/`_classify_return_type`
  bands + the var-decl recognizer (6-byte check before 3-byte `f32`; verify the `klen`
  path for the 9-char `f32v8_add` keyword). `_vec_desc`/`GVEC_*` need no change.
- **VEX encoder** (the one net-new primitive): a helper emitting 2-byte (`C5`) and 3-byte
  (`C4`) VEX via `EB(S,byte)`, packing `R̄X̄B̄`/`vvvv`(1's-comp of src1)/`L`/`pp`/`mmmmm`.
- **decode.cyr**: teach the length-decoder to skip VEX-prefixed instrs so DCE/CFG
  byte-walking stays correct (co-requisite of first VEX emission).
- **Ops** — `EMIT_F32V8_LOOP` mirroring `EMIT_F32V_LOOP`, **stride `rsi += 8`** (SIB stays
  `B2`/scale-4 since index is element count), `vzeroupper` (`C5 F8 77`) before return:
  - `vmovups ymm0/ymm1,[rdx+rsi*4]` = `C5 FC 10 04 B2` / `C5 FC 10 0C B2`; store `C5 FC 11 04 B2`
  - `vaddps/vsubps/vmulps ymm0,ymm0,ymm1` = `C5 FC 58 C1` / `C5 FC 5C C1` / `C5 FC 59 C1`
  - tokens **f32v8_add=147, f32v8_sub=148, f32v8_mul=149**
- **CPUID probe** `simd_has_avx2()` + `_avx2_cpuid_probe` (clone sigil, §3).
- **Lib** `lib/simd.cyr`: `f32v8` type + `f32v8_add_ptr/_sub_ptr/_mul_ptr` + `_make/_splat/_laneN_ptr`,
  **pointer-form only**, each wrapper branching AVX2-vs-SSE. api-surface `--update`.
- **Gates**: a **disassembler gate** proving the VEX bytes decode to the intended `vaddps ymm`
  (mandatory — no in-tree VEX oracle) + `simd_f32v8.tcyr` (value-checking, XFAIL aarch64/cx)
  + `vr01_f32v8_ctor.tcyr`.

### Release 2 — f32v8 fmadd + dot + GEMM bench
- **`f32v8_fmadd`** (token 150) via true **`vfmadd231ps ymm2,ymm0,ymm1` = `C4 E2 7D B8 D1`**
  (0F38 map → 3-byte VEX, single rounding; needs FMA bit — see traps). Recurs the f32v4
  fmadd over-write footgun (tail over-writes up to 7 dst lanes past n) — lib pins n=8.
- **`f32v8_dot`** (token 151): accumulate in ymm2, then the **8-lane reduce** —
  two-`haddps` does NOT cross the 128-bit boundary, so:
  - `vextractf128 xmm1,ymm2,1` = `C4 E3 7D 19 D1 01` (high 128 → xmm1)
  - `vaddps xmm2,xmm2,xmm1` = `C5 E8 58 D1` (**L=0 / 128-bit!** folds high+low)
  - then the f32v4 tail: two `haddps` (`F2 0F 7C D2`) + `movd eax` (`66 0F 7E D0`)
  - (broadcast for splat: `vbroadcastss ymm0,xmm1` = `C4 E2 7D 18 C1`)
- **`bench_f32v8_gemm.bcyr`** mirroring `bench_f32_gemm.bcyr` — proves the AVX2 win (~2× over
  f32v4) vs the "256-bit-in-name-only" trap. `vzeroupper` correctness is what protects this headline.

### Recurring bug-classes to guard (all confirmed live)
1. **−2153 `0 − lt → sid` sites**: struct-guard covers it; verify each *new* site.
2. **retptr-stash rough-scan SIGSEGV**: pointer-form-first dodges (a `: f32v8` value return
   would fall through the pair paths to scalar garbage — do not add value-form return until
   `_classify_return_type` routes −2153 through a real 256-bit emitter).
3. **mask saturation**: pointer-form dodges (value-form f32v8 param would drop lanes 4-7).
4. **`_is_simd256` lane-width-blindness**: any op keyed on it must re-check `GVEC_LANEB`.

## 6. VEX encoding traps (the CLAUDE.md hand-rolled-hex warning)

1. **`vvvv` = 1's-complement of src1** (VEX byte bits 6:3). `ymm0`→1111, `ymm2`→1101 — so
   `vaddps ymm0,ymm0,ymm1` = `C5 **FC** 58 C1` but `vaddps ymm2,ymm2,ymm0` = `C5 **EC** 58 D0`:
   *same opcode*, different prefix byte purely from vvvv. Wrong vvvv = wrong-register math,
   no crash, invisible to self-host (cycc has no f32v8) — catchable **only** by a
   value-checking tcyr. **Assemble every op with llvm-mc and diff the bytes.**
2. **2-byte `C5` vs 3-byte `C4` per-op**: plain add/sub/mul/xor/movups → `C5`; FMA (0F38),
   broadcast (0F38), extractf128 (0F3A) → **must** be `C4`. A `C5` for `vfmadd231ps` is
   un-encodable → desyncs the whole stream → segfault possibly only on the running machine.
3. **L bit in the reduce tail**: `vextractf128` + the fold `vaddps xmm2,xmm2,xmm1` are
   **128-bit (L=0)** even inside a 256-bit routine — `C5 E8`, not `C5 EC`.
4. **`vzeroupper` mandatory, not optional**: omit it before returning to SSE code → silent
   ~70-cycle transition penalty that would evaporate the R2 "2× over f32v4" headline.
5. **FMA is a separate CPUID bit** (leaf-1 ECX bit 12) from AVX2 (leaf-7 EBX bit 5) — present
   on all shipping AVX2 parts, but document/probe accordingly.

## 7. Files to touch
`src/backend/x86/float.cyr` (EMIT_F32V8_*), `src/backend/x86/decode.cyr` (VEX length-decode),
`src/backend/aarch64/emit.cyr` + `src/backend/cx/emit.cyr` (stubs), `src/frontend/lex.cyr`
(tokens 147+), `src/frontend/parse_expr.cyr` (PARSE_TERM + PARSE_SIMD_EXT), `src/frontend/parse.cyr`
(stmt range), `lib/simd.cyr` (f32v8 type + wrappers + `simd_has_avx2`), `tests/tcyr/simd_f32v8*.tcyr`,
`benches/bench_f32v8_gemm.bcyr` (R2), + docs/vidya/memory.
