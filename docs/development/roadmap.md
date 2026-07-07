# Cyrius Development Roadmap — v6.4.x (active minor)

**Scope** — the **current active minor only** (v6.4.x). This is the
slot-pinning working artifact: the committed opening sequence + a **conservative,
code-grounded length map** for each remaining arc. The fuller per-arc design, the
rest of the cycle (v6.5.x → v6.8.x), and the closed-minor summaries live in
[roadmap_6.md](roadmap_6.md); everything beyond v6.x is in
[roadmap-future.md](roadmap-future.md).

> **Reading order**: this file (active-minor pins + length map) →
> [roadmap_6.md](roadmap_6.md) (full v6.x cycle + fuller per-arc design) →
> [roadmap-future.md](roadmap-future.md) (v7+ watching list).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** (framing, per-arc
  design, the closed v6.0.x/v6.1.x/v6.2.x/v6.3.x summaries).
- [roadmap-future.md](roadmap-future.md) — long-term / v7+ watching list.
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles
  (slot acceptance, premise-check at slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size, in-flight slot).
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.4.x — ABI / Language-Features arc

**Opened** at the v6.3.45 → v6.4.0 cut (2026-07-03). The v6.3.x language-refinement
minor (closures / generics / async / native-float, plus the deps-model, bare-metal,
perf, and cross-OS-hardening arcs) **closed at v6.3.45** — its whole slot table is
canonical in [CHANGELOG.md](../../CHANGELOG.md) and summarized in
[roadmap_6.md](roadmap_6.md); it is intentionally not repeated here.

**Shipped so far in v6.4.x:**

- **v6.4.0** — `CYRIUS_MONOMORPH` **default-on flip**: generics are now a default-on
  language feature (`CYRIUS_MONOMORPH=0` opts out). Byte-identical (cycc has no
  generic fns); needed the `_INLINE_OK` decouple + the GFTP-gated frame-trim.
- **v6.4.1** — `alloc_reset()` **zero-on-reset**: closed a CVE-2026-34988-class
  memory-reuse info-leak in all four allocator backends.
- **v6.4.2** — agnos **`sys_snd_*` audio syscall band (#64–#69)**: the ring-3 half of
  the agnos 1.52.x Gate-2 audio freeze (unblocks vani + cyrius-doom).
- **v6.4.3** — **pre-SIMD f64v2/f64v4 surface solidification** (agnos FP issue §2):
  the `f64v2(a,b)`/`f64v4(...)` intrinsic constructor syntax (FINDFN → `_make`) +
  `f64v2_splat`/`f64v4_splat`; XMM-state prerequisite noted; + vani 0.9.8 / yukti 2.2.8
  folds. Reactive slot — finishes the f64 SIMD ergonomics before the SIMD arc builds on it.
- **v6.4.4** — **SIMD arc Phase 1: `f32v4` end-to-end on x86** — 128-bit packed single-precision
  (descriptor −2121 + `_vec_desc`, full value-form ABI, `addps`/`subps`/`mulps`, lib wrappers).
  Adversarial review caught + fixed 3 latent bugs (token/`await` collision, a `.field` OOB
  struct-table escape, f32v4/f64v2 param mask conflation). check.sh 129; fixpoint (cycc has no f32v4).
- **v6.4.5** — **SIMD arc Phase 2: f32 matmul op set** — `f32v_fmadd` + `f32v_dot` (tokens 141/142,
  the packed-single FMA + 4-lane `haddps` horizontal-dot), `lib/simd.cyr` `f32v4_fmadd`/`_dot`
  wrappers, and `bench_f32_gemm.bcyr` (48³ dense GEMM, ~27× SIMD-vs-scalar). Fixpoint; x86-only phase.
- **v6.4.6** — **SIMD arc Phase 3a: integer vector types + packed ops** — descriptor-driven ABI
  generalization (differential 0/328) + `i8v16`/`i16v8`/`i32v4`/`i64v2` (+`u*`) + `iv_add`/`iv_sub`/
  `iv_mul` (paddb/w/d/q…) + pointer-form lib wrappers. Fixed a rough-scan retptr SIGSEGV (Phase-1
  bug class, closed descriptor-driven). Value-form typed int ops + widening-MAC + b1.58 → 3b.
- **v6.4.7** — **SIMD arc Phase 3b: value-form typed integer ops + int8 widening dot** — the
  param-mask redesign (class 1 = any 16-byte vector routes through XMM; caller class-1 type-check
  relaxed to `_is_simd128`, f32v4 stays strict; differential 0/331) unblocks `i32v4_add(a,b)` value
  ops (i32v4/i16v8/i8v16/i64v2) + `i32v4_lane*(v)`. `iv_dp8` (u8·i8 → i32 widening dot,
  pmaddubsw→pmaddwd→paddd, movsxd sign-extend) = the b1.58 GEMM inner loop; `bench_i8_gemm.bcyr`
  (64³, ~30×). simd_ints 11→21 asserts. Fixpoint; x86-only phase. **Integer-SIMD arc CLOSES.**
- **v6.4.8** — **SIMD arc Phase 4 R1: `f32v8` 256-bit AVX2 elementwise** — the **first VEX/AVX the
  toolchain ever emits** (2-byte C5 VEX; `EMIT_F32V8_LOOP` = `vaddps`/`vsubps`/`vmulps ymm` +
  `vmovups`), descriptor sentinel −2153, tokens 147–149; the 256-bit value-return ABI generalized
  from the exact f64v4 sentinel to `_is_simd256`. `simd_has_avx2()` **CPUID runtime fallback** (leaf 7
  EBX bit 5 — AVX2 is NOT x86-64 baseline) so wrappers branch AVX2-vs-2×SSE. Disassembler-gated (no
  in-tree VEX oracle). `decode.cyr` VEX length-decode dropped (collided with a pre-existing
  SYSCALL/CPUID mis-decode; filed). Pointer-form lib first. Fixpoint (cycc has no f32v8).
- **v6.4.9** — **SIMD arc Phase 4 R2: `f32v8` FMA + 8-lane dot** — `f32v8_fma` (token 150,
  `vfmadd231ps` = the **first 3-byte VEX / C4** the toolchain emits) + `f32v8_dot` (token 151,
  8-lane `vextractf128` reduce — the two-`haddps` f32v4 fold can't cross the 128-bit lane split).
  `simd_has_fma()` (leaf 1 ECX bit 12 — a **different** CPUID bit than AVX2). `bench_f32v8_gemm.bcyr`
  (~1.48× 256-bit vs 128-bit). **Phase 4 CLOSES — f32 SIMD complete on x86** (f32v4 128-bit + f32v8
  256-bit, elementwise + FMA + dot). Fixpoint; x86-only phase.
- **v6.4.10** — **first interim items after the SIMD x86 break point** (aarch64 NEON deferred).
  (1) **P1 kernel-blocker fix** — a bare top-level `var X[N]` was silently **8× under-sized** when
  declared *after* the first bare top-level statement (pass-2 `PARSE_ARRAY` used the fn-local N-byte
  default instead of `PARSE_GVAR_ARR`'s N×8); fixed in `parse_decl.cyr` (~61) to size a bare non-fn-
  local array N×8. cycc's own top-level arrays were affected → **two-step bootstrap** (fixpoint
  1,057,568 B; differential codegen-diff = 31 / status-diff = 0 — 31 programs' arrays correctly grow).
  (2) `cyrius distlib` **per-module read cap 256 KB → 1 MB** (`cbt/commands.cyr`, matching cycc's
  `input_buf[1 MB]`) — distlib was rejecting modules cycc compiles fine. check.sh 130; ecb+cass+pi
  `SELFHOST_OK`; self_compile 556 ms.
- **v6.4.11** — **array-typed struct fields R1: `Vec<T>` handle fields** (Pin 2 opens). Struct/union
  fields can be declared `Vec<T>` — an 8-byte handle slot; element type T in a far-negative ftype
  sentinel (`MKVEC = (0-0x50000)-elem`, decoded by `IS_VEC_FIELD` before any `ft>0`/`ft<0` path;
  **OOB-safe by construction** per an adversarial 9-site `GETFTYPE` guard-audit — 0 guards needed).
  Parse (struct + union) + field load/store + struct-literal init (local + global); the negative
  sentinel needs **no `PARSE_STRUCT_INIT` edit** (flows through `else`→`FIELDSZ`→8, unlike Str's
  positive-sid flatten). Fixed a bare `.field` load truncating the 8-byte handle to 32 bits (the
  `-width` sign-extend fired on the sentinel → `movsxd`; audit-found, the happy-path test used raw
  `load64`). Syntax `Vec<T>` (not `T[]`) survives the `#derive` pre-parser for R2/R3. cycc byte-id
  (size unchanged); check.sh 130; seed-derive OK; ecb+cass+pi `SELFHOST_OK`; self_compile 574 ms;
  test `vec_struct_field.tcyr` (14, proven fail-on-bug). **NEXT: R2 = `#derive` Vec<primitive>.**
- **v6.4.12** — **array-typed struct fields R2: `#derive` Serialize/Deserialize for `Vec<primitive>`**.
  `#derive(Serialize)` structs can hold `Vec<i8/i16/i32/i64>` / `Vec<f64>` fields — serialize to a JSON
  array + round-trip via both `from_json_str` (svara's path) and the pairs-form `from_json`. Encode inline
  (`vec_len`/`vec_get`, null-guard → `[]`); decode via one emitted-once helper per kind (`_cy_vecdec_int`/
  `_f64`). Frontend-only → self-hosts, **+9.7 KB** from the generator code (emitted-string codecs are real
  compiler surface). **Adversarial review caught + fixed 2 P1 crashes** (both decoders infinite-looped →
  allocator abort on a malformed array byte; forward-progress guard added) + a `Vec<struct>`/`Vec<Str>`
  honest-diagnostic (kind-201, R3). Folded **bayan 1.0.4 → 1.1.0** (JSON API byte-identical; cycc byte-id).
  check.sh 130; seed-derive OK; test `derive_vec_primitive.tcyr` (33). **NEXT: R3 = `#derive` Vec<struct>
  + svara minor patch.**
- **v6.4.13** — **array-typed struct fields R3: `#derive` for `Vec<#derive-struct>`** — **the arc CLOSES**.
  `#derive(Serialize)` structs can hold `Vec<T>` where T is itself a `#derive` struct — serialize to a JSON
  array of objects + decode via a recursive **string-aware object-scan** in the single-pass `from_json_str`
  (the first recursive value-parse there). Encode `<T>_to_json(vec_get(...), sb)`; decode calls
  `<T>_from_json_str` per `{...}` element + a bracket-depth `}`-skip (a `}`/`{` inside a string doesn't
  count, via `_cy_json_skipval`). **Adversarial review caught + fixed 3 bugs** (non-array value ate
  siblings; lowercase-i/f element names mis-rejected; escaped-quote Str truncation — now escape-aware +
  un-escaping, fixing ALL #derive Str decode) + hardening (trailing-`\` NUL, 31-char type-name cap,
  embedded-`]`). Vec<Str>/nested-element-struct = clear-diagnostic/documented boundaries. cycc self-hosts
  (+6 KB → 1,073,544 B); check.sh 130; seed-derive OK; ecb+cass+pi `SELFHOST_OK`; test
  `derive_vec_struct.tcyr` (22). **Array-typed struct fields (Pin 2) is DONE.**
- **v6.4.14** — **struct-id 20/21 ↔ f64v2/f64v4 SIMD-sentinel collision fix** (consumer-filed P1,
  found porting stiva) + **cross-OS gate hardening**. A struct-typed local's `SLTYPE = (0 - sid)`
  collided with the flat f64v2 `-20` / f64v4 `-21` sentinels → `.field` on the 20th/21st struct
  hard-errored *"SIMD vector has no named fields"* (data-dependent: stdlib/dep structs shift the
  numbering). Fix (Option 1): fold f64v2/f64v4 into the `≤ -2048` descriptor band (f64v2 → -2093,
  f64v4 → -2125), retire the flat codes → guards collapse to `lt <= -2048`; struct-ids collision-free
  through 2047. All producers migrated in lockstep (`_classify_return_type`, var-decl, value-form
  param `pt_simd_sid`); differential vs .13 **0/0** over 338 inputs. Gate: fixed the cass-leg `set -e`
  `&&`-chain **false-pass** (a failed Windows self-host reported `SELFHOST_OK`) + moved the cass work
  dir to the Defender-excluded `C:\cyrius-tests` (Defender's `Bearfoos.A!ml` ML classifier quarantines
  the unsigned cycc.exe → false FAIL). cycc byte-identical (1,073,544 B); check.sh 130; seed-derive OK;
  ecb+cass+pi `SELFHOST_OK`; test `struct_sid_20_21_field.tcyr`. **NEXT: SIMD Pin 1 aarch64 NEON (Phase 5).**
- **v6.4.15** — **absorber-band cleanup** (the v6.3.45 closeout-audit backlog + two deferred
  correctness residuals, one release). Two byte-identical latent-bug guards: **L1** lex_pp
  `#define`/`#ifdef` flag-table 16-slot silent-corruption cap (+ `tests/pp_flag_cap.sh`); **L2**
  `_msx` Mach-O syscall-xlat imm8 ≥128 sign-ext → auto-dispatch to `_msx32`. Four parallel-copy
  consolidations (the ".44 repeat-fix" bug class), all differential 0/0: **R1**
  `_resolve_field_base_addr` + `_resolve_leaf_field`; **R3 (narrow slice)** `_scalar_name_width`
  at the 6 pure-4-way sites (**−4 KB**); **R4** `_EMIT_NLOAD_RCX` (x86) + `_EMIT_NLOAD_X1_POS`
  (aarch64, qemu-verified output-equivalent); **R5** `_emit_struct_positional_init`. **DECODE**
  no-ModR/M `0F` fixed-length (SYSCALL/CPUID/…): default codegen byte-identical, opt-in
  `CYRIUS_DCE=1` torture deliberately re-baselined (278 inputs, all NOP-fill of dead
  syscall/cpuid fns). **SIMD_TC** value-form SIMD-arg type mismatch now rejected in tail-call
  position (`return simdfn(local)`; the filed root-cause was wrong — real hole is `PARSE_RETURN`'s
  tail path; reject-only, byte-identical; `simd_vec_reject.sh` Guard 3). Issue hygiene: queue
  20→17 (2 resolved archived, 2 lint gates consolidated to roadmap-future). **R2 DEFERRED** —
  premise-check disproved byte-identity (EWRITE_PE/EREAD_PE prologues diverge 5 bytes → PE-codegen
  change, doesn't fit a byte-identical slot). cycc 1,069,552 B; check.sh 131; seed-derive OK;
  ecb+cass+pi `SELFHOST_OK`+`LIBTEST_OK`; self_compile 587 ms. **NEXT: cx backend CLI exposure,
  then Phase 5 NEON** (user-set order 2026-07-07).
- **v6.4.16** — **aarch64 `f64_sin` / `f64_cos` polyfill** (reactive consumer repair — attn11 P2
  arch-parity; hearing lane broke the aarch64 CI leg). `_f64_sin_polyfill` / `_f64_cos_polyfill`
  in core `lib/math.cyr` (range-reduce x = k·(π/2)+r, quadrant `q = k&3`, shared Horner Taylor
  `_core` helpers through 1/15!/1/14!) + `EF64_SIN`/`EF64_COS` aarch64 dispatch (v5.7.31 exp/ln
  pattern; `exp2`/`atan` stay hard-errors — `tan` = sin/cos at the lib level). Accuracy tier-1
  (worst < 1e-14 vs x87, all quadrants); aarch64 qemu end-to-end (compile + `sin²+cos²=1` +
  anchors); x86 cycc byte-identical; aarch64 self-host fixpoint byte-identical under qemu.
  **Cut together with .15** (.15 not separately pushed). Test `tests/tcyr/vr01_trig_polyfill.tcyr`
  (31 asserts, ran in the cross-OS gate on real ecb + pi). check.sh 131; self_compile 577 ms.

**The committed opening sequence** (ORDER fixed by user 2026-07-03; the design
decisions *inside* each arc are chosen at arc-open — only the order is committed):
**integer SIMD → array-typed struct fields → UEFI Secure Boot signing → function
visibility**, with the **Intel-Mac (x86_64 Mach-O) toolchain arc** at the tail.

---

## Conservative length map (arc-scoped against the code, 2026-07-04)

Each arc was scoped against the actual tree (not the proposal's optimistic framing).
The estimates lean **high** — a feature touching the type system / codegen / ABI is
multi-release and grows a repair tail (the generics precedent: .9 → .39 + the .0
flip, with deep-ABI repairs still surfacing at .37/.38/.39). **Sizes are `.NN`
releases, each bundling several bites. Minors flex long.**

| # | Arc | Conservative length | Release-blocker? | Status |
|---|-----|--------------------:|:----------------:|--------|
| 1 | **Packed SIMD compute** (f32-first, then integer; ML/AI) | **5–7 releases** | No | **x86 portion COMPLETE (v6.4.4–.9, 6 releases); ⏸ aarch64 NEON (Phase 5) deferred** |
| 2 | **Array-typed struct fields** | **3 releases (done)** | No | **✅ DONE — R1 v6.4.11 · R2 v6.4.12 · R3 v6.4.13 (`Vec<T>` fields + `#derive` Vec<primitive>/Vec<struct>)** |
| 3 | **UEFI Secure Boot signing** | **3–5 releases** | No | order-committed |
| 4 | **Function visibility** (`pub`/`private`) | **4–6 releases** | No | order-committed |
| 5 | **DX: cx bytecode backend CLI exposure** (`--target=cx` + `cxvm` install + `.cyx` run path) | **1–2 releases** | No | **pinned 2026-07-07 — PRIORITIZED interim (consumer hit the wall)** |
| 6 | **Scalar-float completion** (f64 return type + f32 scalar arithmetic + typecheck strictness) | **2–3 releases** | No | pinned 2026-07-07 — later 6.4.x |
| 7 | **DX: diagnostics** (multi-error reporting + column/excerpt) | **2–4 releases** | No | pinned 2026-07-07 — later 6.4.x |
| T | **Intel-Mac (x86_64 Mach-O) toolchain tail** | **2–4 releases** | No | committed tail |

**Opening sequence total: conservatively ~22–35 `.NN` releases** (grown from ~17–26
at the 2026-07-07 horizon session: + cx CLI exposure, scalar-float completion,
diagnostics) — v6.4.x is a **long minor**, per the user's standing preference for
**large minors (~45–99 releases historically), not a theme-per-minor**. **None of the
arcs is a release-blocker.** **Pin 1's x86 portion landed at 6 releases
(v6.4.4–.9), inside the 5–7 budget** — the aarch64-NEON remainder (Phase 5) is intentionally paused
(see the break-point note under Pin 1). On top of the arcs, **reactive agnos + consumer-filed repairs
interleave throughout** and consume **separate** slots that are **not** counted above (already this
minor: .0's own de-risking, .1 alloc_reset, .2 agnos audio, .3 the f64 SIMD-surface solidification,
and .10 the kernel-blocker + distlib-cap interim fixes) — see *Reactive headroom* below.

---

## 2026-07-07 horizon additions (user-committed, planning session)

Three additions to THIS minor. (The same session also reframed **v6.5.x** as the
**Performance-Quality minor** — absorbing the SIMD register-residency / IR-regalloc
work — set **v6.6.x** as the **Language-Ergonomics minor**, and re-homed **RISC-V
rv64 to v6.7.x/v6.8.x**; see [roadmap_6.md](roadmap_6.md).)

- **DX: cx bytecode backend CLI exposure — PRIORITIZED, sooner-than-later.** User
  reasoning: a consumer agent's project needed wasm-shaped output and **hit the
  wall** — the backend is fully built, self-hosting, and check.sh-gated but has
  ZERO user-facing surface. Scope (pulled forward from roadmap-future.md):
  `cyrius build --target=cx` routed to the cx emit path (mirror `--target=js`),
  install `cxvm` + a `.cyx` run path, finish cx float ops, decide SIMD-on-cx.
  Land as the next interim slot(s) — this does NOT displace the committed arc
  order (interim slots interleave by design; Phase 5 NEON remains the next arc).
  Full stub: [`proposals/2026-07-05-cx-bytecode-cli-exposure.md`](proposals/2026-07-05-cx-bytecode-cli-exposure.md).
- **Scalar-float completion — later 6.4.x.** Scalar `f64` as a function RETURN
  type (returned in xmm0 per SysV — today's allow-list admits `f64v2`/`f64v4` but
  not `f64`; [`issues/2026-07-04-agnos-fp-xmm-state-and-f64-scalar-return.md`](issues/2026-07-04-agnos-fp-xmm-state-and-f64-scalar-return.md) §1),
  **f32 scalar arithmetic** (the native-float Tier A tail, pulled from
  roadmap-future.md), and stricter f64/f32 typecheck. Retires the i64-boxed-f64
  idiom, where a plain `+` on a boxed f64 silently integer-adds the bit pattern —
  the ergonomic face of the same numeric push v6.5.x anchors.
- **DX: diagnostics — later 6.4.x.** Multi-error reporting (today:
  first-error-exit) + column + source-excerpt in errors. A maintenance-cost item:
  consumer-filed misdiagnoses are the recurring tax better errors retire. DWARF
  debug-info stays v7-parked (only the error-reporting layer moves here).

**SIMD sequencing amendment (user, same session):** the intended order inside the
SIMD focus is **Phase 5 NEON first, then circle back to the register-residency /
memory-store proposal** (the ml-ai-arc consumer filing,
[`issues/2026-07-06-simd-f64v-memory-operand-no-register-residency.md`](issues/2026-07-06-simd-f64v-memory-operand-no-register-residency.md)).
Because the kernel + ecosystem AI release arc makes SIMD the primary focus of
v6.4.x, **SIMD-adjacent work — the register-residency piece included — is expected
to get pulled INTO v6.4.x** rather than waiting for v6.5.x, alongside high-priority
bug fixes as they surface. v6.5.x remains the home for the full IR/regalloc
substrate + the deferred passes; how much register residency can land ahead of that
substrate (wrapper inlining + chain-local residency vs. full vector-class regalloc)
is a premise-check at slot entry.

**Absorber-band (rides between arcs, uncounted):** the v6.3.45 closeout backlog
([`issues/2026-07-03-v6345-closeout-audit-backlog.md`](issues/2026-07-03-v6345-closeout-audit-backlog.md)
— L1 pp-flag-table 16-slot silent-corruption cap, L2 `_msx` imm8 ≥128 guard,
R1–R5 parallel-copy consolidations), the decode.cyr no-ModRM-0F mis-length fix,
the SIMD value-form typecheck residual, and an **issue-archive hygiene pass**
(open queue ~21; resolved-in-header entries archive per
[[feedback_issue_hygiene_batch_not_pile]]).

---

## PINNED — immediate work

### Pin 1 — Packed SIMD compute (f32-first, then integer; ML/AI priority) — ~5–7 releases

> **⏸ BREAK POINT (user 2026-07-05): the x86 portion of Pin 1 is COMPLETE and the arc is
> intentionally paused here.** Phases 0–4 shipped x86 SIMD end-to-end — f32v4 (v6.4.4), f32
> matmul (v6.4.5), integer vectors (v6.4.6/.7), and f32v8 256-bit AVX2 + FMA/dot (v6.4.8/.9) —
> **6 releases, within the 5–7 budget**. The **aarch64 NEON remainder (Phase 5+)** is
> **DEFERRED, to be resumed properly later in 6.4.x** after some other items. It is NOT
> cancelled — `simd_f32v4`/`simd_ints`/`simd_f32v8` stay XFAIL on ARM until then. Premise-check
> done (2026-07-05): Phase 5 is a **mechanical NEON mirror** of the existing `EMIT_F64V_*` code
> (`.2d`→`.4s`, llvm-mc-sourced), a planned 2-release split — **5a** f32 NEON (fadd/fmul/fmla/dot;
> the f32v8 wrappers fall through to the f32v_ path on ARM, so 5a un-XFAILs BOTH simd_f32v4 +
> simd_f32v8) and **5b** integer NEON + `iv_dp8` (the one design point: `sdot` needs the optional
> `FEAT_DotProd`, so a runtime feature-gate or `smull`/`saddlp` fallback — the aarch64 analog of
> the x86 FMA gate). cx/PE SIMD + the `lib/simd.cyr` doc pass are the Phase-6/7 tail.

**Sequence pivot (user 2026-07-04): f32 SIMD compute FIRST, then the lower-int lanes** — model
testing shows f32+SIMD is the primary throughput lever, with int8/quantized as the optimization
layer on top. Cyrius SIMD is **f64-only** today (`lib/simd.cyr` = `f64v2`/`f64v4`); **f32 is
storage-only (no arithmetic — routes through f64) and there is no f32 or integer SIMD at all**,
capping dense-f32 matmul/attention AND every int/quantized kernel at scalar/f64 speed. f32v4
**rides the existing f64 SSE packed path minus the `66` prefix** (`mulps`=`0F 59` vs
`mulpd`=`66 0F 59`) — the lowest-risk first lane. Then integer lanes (i8/i16/i32/i64) ride the
same op-table for the quantized frontier (tentib b1.58, attn11/tarka, sankoch, edge/Pi tok-s).
Extends the **i64-oracle / free-type-movement** model: vectors are views entered by
broadcast/load and returned to i64 by extract/reduce.

- **▶ PHASE 0 DONE — encoding PINNED** (design doc
  [`2026-07-04-integer-simd-encoding-design.md`](proposals/2026-07-04-integer-simd-encoding-design.md)):
  a **structured SIMD descriptor** in a reserved SLTYPE sentinel band **below −2048**
  (collision-free — struct sids cap at 1024), decoded by one `_vec_desc()`; f64v2/f64v4 keep
  their legacy −20/−21 (byte-identity); the 2-bit param mask stays coarse (route-to-vec-reg) with
  the full descriptor in the param's SLTYPE; dispatch collapses to one `EMIT_ISIMD` op-table per
  backend (lifting the `EMIT_F64V` pattern). Release-1 op set = the **dense-f32 matmul inner
  loop** (f32v4 load/store/broadcast + `addps`/`mulps` + FMA + horizontal-dot).
- **▶ PHASE 1 DONE (v6.4.4) — `f32v4` end-to-end on x86**: descriptor sentinel −2121 + `_vec_desc`
  + var-decl/return/receive/value-form-param plumbing + `addps`/`subps`/`mulps` (`EMIT_F32V_LOOP`) +
  `lib/simd.cyr` value+pointer wrappers + `simd_f32v4.tcyr`. Self-host is a fixpoint (cycc has no
  f32v4). Adversarial review caught + fixed 3 latent bugs (token/`await` collision → 138–140; the
  −2121 `.field` OOB struct-table escape; the f32v4/f64v2 param mask conflation → 3-state mask +
  `tests/simd_vec_reject.sh`). Filed one pre-existing residual (value-form SIMD param on a
  non-SIMD-returning callee skips the type-check — `issues/2026-07-05-valform-simd-param-typecheck-only-when-simd-return.md`).
- **▶ PHASE 2 DONE (v6.4.5) — f32 matmul op set**: `f32v_fmadd` (token 141, `EMIT_F32V_FMADD` =
  the f64 FMADD minus the 66 prefix) + `f32v_dot` (token 142, `EMIT_F32V_DOT` = mulps/addps
  accumulate → two `haddps` fold 4 lanes → `movd eax`), both mirroring the f64 handlers in
  `PARSE_SIMD_EXT`; `lib/simd.cyr` `f32v4_fmadd`/`_dot` (value+ptr) wrappers; `bench_f32_gemm.bcyr`
  (48³ dense GEMM, ~27× SIMD-vs-scalar); `simd_f32v4.tcyr` 8→13 asserts. Fixpoint (cycc has no
  f32v_). aarch64/cx stubbed → x86-only this phase (`simd_f32v4` stays XFAIL until Phase 5).
- **Phase 3 — integer SIMD lanes, a PLANNED 2-release split** (the encoding is pinned;
  the size — an ABI-generalization refactor + novel signed/saturating/widening int semantics +
  a b1.58 bench — makes 3a/3b the intentional packing, decided up front, not mid-execution):
  - **✅ Phase 3a (v6.4.6) — ABI generalization + integer types + basic packed ops.** Generalized
    the ~21 f32v4-hardcoded `−2121` value-form ABI sites (return / receive / struct-arg / inline-
    exclude) to **descriptor-driven** (`_is_simd128`/`_is_simd256`/`_is_simd_any`), byte-identical
    for f32v4/f64v2 (differential 0/328). Integer types `i8v16`/`i16v8`/`i32v4`/`i64v2` + `u*`
    (signedness = desc bit 1). Packed `iv_add`/`iv_sub`/`iv_mul(dst,a,b,n,w)` → one `EMIT_IVEC_BINOP`
    (paddb/w/d/q, psubb/w/d/q, pmullw/pmulld); pointer-form lib wrappers; `simd_ints.tcyr` +
    `vr01_ints_ctor.tcyr`. Fixed a return-type-rough-scan retptr SIGSEGV **descriptor-driven**
    (closes the Phase-1 f32v4 bug class for all future vector types).
  - **✅ Phase 3b (v6.4.7) — value-form typed integer ops + int8 widening dot + b1.58 bench.** The
    **value-form param-mask redesign**: `_classify_param_type`/`_classify_return_type` gained integer
    arms, the def-fold/prescan set `_fnt_simdmask` class 1 for **any** `≤ −2048` vector param, and the
    caller class-1 arg type-check was relaxed from the exact f64v2 sentinel to `_is_simd128` (any
    16-byte vector) — f32v4 (mask code 3) stays strict so `simd_vec_reject` holds. Byte-identical
    (differential 0/331: the only class-1 params were f64v2-with-f64v2-args, so widening the accepted
    set changes no existing codegen). Value-form `i32v4_add`/`_sub`/`_mul` + `_lane{0..3}`,
    `i16v8`/`i8v16`/`i64v2` add/sub(/mul). The widening MAC shipped as **`iv_dp8`** (u8·i8→i32:
    `pmaddubsw`→`pmaddwd`→`paddd` accumulate + `phaddd`×2 + **`movsxd` sign-extend**) — the b1.58 GEMM
    inner loop; `bench_i8_gemm.bcyr` (64³, ~30× vs scalar). `simd_ints.tcyr` 11→21 asserts. **The
    integer-SIMD arc CLOSES here.**
- **Phases**: (0 ✅) encoding → (1 ✅ v6.4.4) f32v4 end-to-end x86 → (2 ✅ v6.4.5) f32 matmul op set +
  GEMM bench → (3a ✅ v6.4.6) int types + packed ops → (3b ✅ v6.4.7) int widening-MAC + b1.58 bench →
  **(4 R1 ✅ v6.4.8) f32v8 256-bit AVX2 elementwise + VEX substrate + CPUID runtime fallback → (4 R2 ✅ v6.4.9)
  f32v8 fmadd + 8-lane dot + GEMM bench — PHASE 4 CLOSES; x86 SIMD COMPLETE** → **⏸ BREAK POINT (user
  2026-07-05: park the arc, do other items first)** → (5 — deferred, resume later in 6.4.x) aarch64 NEON
  (`fmla`/`sdot`) + cx/PE → (6) `lib/simd.cyr` wrappers + docs → (7) repair tail. **R1 (v6.4.8):** first VEX/AVX in the toolchain
  (2-byte C5, llvm-mc-verified, disasm-gated); 256-bit value-return ABI generalized to `_is_simd256` (byte-id
  for f64v4); `simd_has_avx2()` CPUID probe + branching wrappers; decode.cyr VEX dropped (pre-existing SYSCALL
  mis-decode, filed). **R2 (v6.4.9):** first 3-byte VEX (C4) — `vfmadd231ps` (FMA3) + the 8-lane `vextractf128`
  dot reduce; `simd_has_fma()` (leaf 1 ECX bit 12) gate; `bench_f32v8_gemm` ~1.48× (256 vs 128-bit). f32 SIMD
  now complete on x86 (f32v4 + f32v8). `simd_f32v8` XFAIL aarch64 until Phase 5.
- **▶ Phase 4 (f32v8 + 256-bit AVX2) — arc-open DECISIONS (user 2026-07-05, after a code-grounded
  premise-check).** Full design + disassembler-verified VEX byte encodings + the CPUID-fallback design
  live in [`proposals/2026-07-05-f32v8-avx2-phase4-design.md`](proposals/2026-07-05-f32v8-avx2-phase4-design.md).
  Premise-check ground truth: **no 256-bit AVX exists** — `f64v4` is a count-driven
  128-bit SSE2 loop (`EMIT_F64V_LOOP`, `rsi += 2`), and a full `src/` scan finds **zero VEX/AVX/ymm**
  emission (only a "no AVX/VEX" comment in `decode.cyr`). So VEX encoding is **fully greenfield**. The
  descriptor already fits f32v8 cleanly (**sentinel −2153**, 32B/4-slot/lane-width-4 decode, no
  name/struct-guard change), but `_is_simd256` keys on `nslots==4` — **shared with f64v4** → lane-width-
  blind; any op keyed on it must re-read `GVEC_LANEB`. The 2-bit param mask is **saturated** (0/1/2/3).
  **Decisions:**
  - **AVX2 model = real AVX2 + CPUID runtime fallback.** f32v8 emits `vaddps ymm` etc. when the CPU has
    AVX2, falling back to a 2×SSE path when absent (probed at runtime — SSE2 is x86-64 baseline; `vaddps
    ymm` SIGILLs on pre-AVX2). cycc itself has no f32v8 → the **compiler stays SSE2/portable and
    self-hosts byte-identical everywhere**; only consumer programs calling f32v8 exercise the dispatch.
    (Fallback-mechanism design pending the CPUID-scaffolding read — cpuid `0F A2`, EAX=7 → EBX bit 5.)
  - **Lib form = pointer-form first** (`f32v8_add_ptr`/`_make`/`_lane…`); value-form deferred (it would
    force widening the saturated 2-bit mask to 3 bits — the Phase 3b wall — plus a single-ymm return
    ABI). Matches every prior phase's first bite and dodges the retptr-stash return SIGSEGV.
  - **Pre-planned 2-release split** (boundary fixed now, not mid-execution): **R1** = VEX encoder +
    elementwise `vaddps/vsubps/vmulps ymm` + `vmovups` + the CPUID probe + pointer-form lib + a
    **disassembler gate** (mandatory — no in-tree VEX oracle) + `simd_f32v8.tcyr` (XFAIL aarch64/cx).
    (The planned `decode.cyr` VEX length-decode was **dropped** — not needed, DCE fail-safe-refuses
    dead f32v8 wrappers; and it broke DCE-mode byte-identity via a pre-existing SYSCALL/CPUID mis-decode:
    `issues/2026-07-05-decode-len-mislengths-no-modrm-0f-opcodes.md`.) **R2** = `vfmadd231ps` + the 8-lane dot (`vextractf128` + SSE fold — the two-
    `haddps` f32v4 pattern can't cross the 128-bit lane split) + a f32v8 GEMM bench (proves the AVX2 win
    vs the "256-bit-in-name-only" trap). Guard the recurring bug-classes: the `−2153` `0 − lt → sid`
    sites (struct-guard covers it, verify each new site), the retptr-stash rough-scan (pointer-form
    dodges), mask saturation (pointer-form dodges), and `_is_simd256` lane-width-blindness.
  - x86-only (aarch64 NEON is 128-bit → 256-bit is 2×V-pairs, a Phase-5 concern; cx stubs; PE gated).
- **Phase 5 cleanup (carried from v6.4.4)** — when aarch64 (and cx) `EMIT_F32V_LOOP` gets a real
  implementation, **remove the `simd_f32v4` XFAIL** from the aarch64-native CI corpus (`ci.yml`),
  promote `simd_f32v4.tcyr` into the `vr01_` cross-OS LIBTEST glob so the release gate covers it,
  and drop the "x86-only this phase" stub comments. Tracked:
  `issues/2026-07-05-aarch64-f32v4-xfail-phase5.md` (CI surfaces it via `XPASS` once it passes).
- **Risks**: integer-lane semantics (saturating, signed/unsigned per width, widening-madd) have
  no f64 template → sign-ext/truncation surface (cf. v6.3.35/.36); VNNI/sdot/FMA availability
  varies per arch (feature-gated); bench-gated acceptance (a correct-but-slow cut doesn't satisfy
  the consumer). Cross-repo acceptance benches: dense-f32 GEMM + tentib 0.4.1 (separate repos).

### Pin 2 — Array-typed struct fields — ~3–4 releases

> **STATUS (2026-07-06): ✅ COMPLETE — R1 + R2 + R3 SHIPPED.** Representation fork RESOLVED by
> user → a typed **`Vec<T>` HANDLE** (not inline `T[N]`); syntax **`Vec<T>`**; 3-release split, ALL SHIPPED:
> **R1** parse + metadata + access (✅ **v6.4.11**) · **R2** `#derive` Vec<primitive> (✅ **v6.4.12**) · **R3**
> `#derive` Vec<struct> (✅ **v6.4.13**) + svara minor patch. Full design + sentinel encoding + risks:
> [`proposals/2026-07-06-array-typed-struct-fields-design.md`](proposals/2026-07-06-array-typed-struct-fields-design.md).
> The representation discussion below predates the fork resolution — kept for context.

Make `struct { field: T[]; }` / `field: T[N]` **parse, represent, access, and
derive-serialize**. Today it's a hard parse error ("expected identifier, got `[`");
variable-length data is an untyped `Vec` (i64-only). This is the "array half" of the
`#derive(Serialize)` codec (the f64 *scalar* half shipped v6.3.40) and unblocks
tables/lists in structs generally.

- **▶ IMMEDIATE FIRST STEP (the pin): decide the field REPRESENTATION —
  inline-fixed-array `T[N]` vs a typed `Vec<T>` handle — FIRST.** That fork drives
  everything downstream (layout, `struct_ftypes` widening, field-access codegen, the
  derive). **Hold dynamic `Vec<T>` element-typing OUT of the initial pin** (Vec is
  i64-only today; typing its elements is its own multi-release generics sub-arc) —
  keeping it out is what holds this arc to 3–4.
- **Phases**: (1) struct-field parser accepts `field: T[]`/`T[N]` → (2) the
  representation + layout (`struct_ftypes` needs element-type + count, likely a new
  metadata table across all `main_*` forks) → (3) field-access codegen, cross-arch →
  (4) the `#derive(Serialize)` array codegen across the 3 codec fns.
- **Consumers**: svara (~40 serde types + a 101-row phoneme table) is blocked on this;
  naad/vidya dropped round-trip tests. Tier B (`toml_v_*` typed DOM in bayan) is a
  **separate stdlib** item, not part of this arc.

---

## Order-committed (length-blocked, not yet pinned)

### 3 — UEFI Secure Boot signing — ~3–5 releases · NOT a release-blocker

Give the sovereign toolchain a **`cyrius sign-efi`** path (Authenticode-sign a
`CYRIUS_TARGET_EFI` PE) + EFI key-enrollment artifacts. Consumer-filed by **gnoboot**
(the sovereign UEFI bootloader). **Premise-check first — much already exists:** the
RSA/X.509/SHA-256 crypto floor **and** the PKCS#7/CMS + Authenticode PE-hash +
attr-cert-embed packaging are **already shipped in sigil 3.10.0** (`src/authenticode.cyr`,
KAT-tested, already folded into `lib/sigil.cyr`) — the proposal's "packaging is
missing" framing is stale.

- **Real gaps**: (A) **cyrius side** — the entire driver surface is net-new
  (`sign-efi`/`efi-keys`/`efi-sigdb` in `cbt/cyrius.cyr`, or a standalone
  `cyrsign-efi`): a thin glue over the shipped sigil core. (B) **sigil side** — P3
  (`EFI_SIGNATURE_LIST` `.esl` + `.auth` generation) is 0 files; P4 (Authenticode
  *verify*) is mostly re-assembly; X.509 *issuance* for `efi-keys` may be genuinely new.
- **▶ First step**: pin driver-subcommand-vs-standalone, then **confirm P1 round-trips
  against a real `OVMF_CODE.secboot.fd` boot** (not just the openssl KAT) — that one
  experiment says whether P1 is a thin-glue release or hides a PE-layout repair tail.
- **Notably cheap tail**: this arc touches **zero compiler codegen/ABI** → no
  cross-arch propagation cost and no deep-ABI repair tail (the 4-host self-host +
  seed-derive still run, but changes are lib/CLI-only, cycc byte-identical). Cross-repo:
  split cyrius (driver) + sigil (P3/P4/keygen, each folded back via `cyrius deps` +
  api-surface regen). Downstream gnoboot/agnova Secure Boot is post-v1.0 → not a blocker.

### 4 — Function visibility (`pub`/`private`) — ~4–6 releases · NOT a release-blocker

Execute "Phase 2 — `pub` enforcement" of
[`module-manifest-design.md`](module-manifest-design.md): close the flat-global-namespace
bug classes (the `dynlib_*` dead-code corruption, enum-shadow, slot-collision) and make
the api-surface snapshot compiler-enforced. Runs long because it's a **retrofit onto a
flat namespace + a real cross-ecosystem migration**.

- **▶ First step (the arc-open gate): the `_`-prefix cross-file-call audit.** Already
  run for cyrius-internal here — **165 distinct `_`-fns are called cross-file** (253
  pairs; 52 in `lib/` are cohesive-subsystem internals like `_tn_*`/`_uc_*`/`_alloc_*`),
  and sigil alone has 703 `_`-defs. **This DISPROVES "derive-from-`_` = zero-churn"** →
  the forced decision: a **HYBRID marker** (`_` default + explicit `pub`/`private`
  override) and **default = PUBLIC** (additive/byte-identical; reject default-private).
- **Phases**: (0) `_`-audit + decision lock → (1) the **per-fn file-id substrate** (new
  preprocessor infra + `_fnt_fileid` across all 7 `main_*` forks — the real work,
  byte-identical) → (2) `fn_flags` bit-6 + WARN-mode enforce → (3) the ecosystem
  migration (add `pub`/rename cross-file `_`-callees; cyrius first, then 14 downstream
  repos via `cyrius deps`, sigil heaviest) → (4) flip to hard-error + feed DCE + prove
  the win → (5) docs/close.
- **Risks**: HIGH-churn — subsystem-spanning `_` helpers (tls-native, unicode,
  alloc-backends) mean file=module is too fine a unit; a mis-stamped file-id → silent
  false-positive rejections; late-ABI repair tail (file-id × monomorph instances,
  use-aliases, `GMOD` mangling); two enforcement sites (`PARSE_FNCALL` + the tail-call
  path — easy to miss one). Cross-repo migration is a big part of why it runs long.

### T — Intel-Mac (x86_64 Mach-O) usable-toolchain tail — ~2–4 releases · NOT a blocker

Runs at the **v6.4.x tail** (moved 2026-07-03). Phase 1 (argv prologue) shipped
v6.1.30; remaining `ach`-gated layers: env reading (`HOME`/uname), wrapper macOS
arch-default, cycc-finding, the layer-6 native self-compile miscompile (tools ship
cross-built until fixed), packaging. `ach` is the supported macOS-x86 verify host.
[`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md).

---

## Reactive headroom — agnos + consumer repairs (interleave throughout)

Agnos ABI mirrors + consumer-filed repairs land as **separate slots between/alongside
the arcs** — they are **not** counted in the arc lengths above, and they follow the
bare-metal open-window pattern ([[feedback_bare_metal_open_reactive_window]]). This
minor has already absorbed three (`.0` de-risk, `.1` alloc_reset, `.2` agnos audio),
and **more agnos work is expected**: the audio consumers (vani's agnos backend,
cyrius-doom's `audio_write` retarget) will surface follow-ons, and the syscall-peer /
freelist-agnos / thread-backend pattern (v6.3.31, v6.4.2) continues as agnos 1.5x lands
kernel features. Budget for it; don't wedge it into an arc. **Only the user re-scopes
or re-prioritizes** ([[feedback_no_unilateral_scope_decisions]]); findings are surfaced,
never unilaterally deferred or redirected.

## Carry-in / watching (open, not in the committed sequence)

- **VR-03/04 differential + platform-lint residuals** — as surfaced (the VR-01 LIBTEST
  gate is now standing on ecb/cass/pi).
- **Consumer-gated**: cyim regex unblock (lands when cyim re-tests against v6.x);
  sandhi RPC-policy TLS-slot OOB
  ([`issues/2026-07-01-sandhi-rpc-policy-tls-slot-oob.md`](issues/2026-07-01-sandhi-rpc-policy-tls-slot-oob.md));
  the `thread_local_alloc()` allocator follow-up.
- **v7-PARKED (NOT near-term)** — LEGAL-01 licensing, DWARF debug-info,
  stdlib-reference docs, incremental compilation, the public-release decision. These
  stay in [roadmap-future.md](roadmap-future.md). (**Diagnostics** — multi-error +
  column/excerpt — **was pulled INTO v6.4.x at the 2026-07-07 horizon session**;
  DWARF itself stays parked.)

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

Premise-check each arc at slot entry ([[feedback_premise_check_at_slot_entry]]) — the
UEFI arc is the live example (crypto already shipped in sigil). Cross-arch propagation
is mandatory for any compiler-emit change ([[feedback_cross_arch_propagation_mandatory]]);
4-host cross-OS self-host verify before **every** cut, even lib-only
([[feedback_cross_os_verify_always_even_lib]], [[reference_verification_hosts_ssh]]);
seed-derive after any `src/` change ([[feedback_seed_derive_mandatory_cybs_limits]]);
benchmark every release ([[feedback_benchmark_every_release]]); one bug ships complete
([[feedback_one_bug_one_complete_fix]]). The minor window is open to change
([[feedback_minor_window_at_arc_open]]) — minors flex long, and this one especially.
