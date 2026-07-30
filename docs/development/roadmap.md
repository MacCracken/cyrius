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
- **v6.4.17–.32 (summary; per-release detail in [CHANGELOG.md](../../CHANGELOG.md)):** .17–.22 **cx
  portable-target arc** (CLI exposure, f64 arith/compare, cross-OS `.cyx` on all 4 hosts); .23 signed
  sub-i64 global sign-ext; .24 struct-field-name-offset collision; .25 aarch64 `exp2`/`atan` + Payne-Hanek
  range reduction; .26 Windows PE batch (TerminateProcess reroute + capturing closures on PE); .27 agnos
  `O_RDWR` + the folded-stdlib repair campaign; **.28–.30 SIMD Phase 5 aarch64 NEON (f32v4/f32v8/int
  vectors + `iv_dp8` — Phase 5 COMPLETE, last SIMD XFAIL removed)**; **.31 Win64 PE value-form SIMD
  params + returns**; **.32 cx bytecode SIMD codegen** (per-lane emitters + cxvm opcodes 0x66–0x68).
  **.33–.42 async arc 5b — reactor + the 5 tokio-parity primitives + consolidation; .43–.45 the
  IOCP-Windows "W" step (client .43 / timers+subprocess+combinator-parity .44 / AcceptEx server .45,
  all release-gated on real cass); .44 also fixed two pre-existing Win64 ABI bugs (PE-reroute 16-align,
  retptr deep-stack-param homing).** .46 `>>>` arithmetic-shift operator + stdlib folds; .47–.48 UEFI
  Secure Boot signing (`cyrius sign-efi`) + enrollment (`.esl`/`.auth` via sigil 3.11.1); .49 growable
  8 MiB off-heap codebuf; **.50 capacity-warning consolidation (Pin 3 — one shared `_capacity_warnings`
  across all 7 drivers).** **The async arc 5b + UEFI arc (#3) are CLOSED; scalar-float completion (.55/.56), DX
  diagnostics (.60 R1 + .62 R2), and the Intel-Mac x86_64 Mach-O tail (.59) have all SHIPPED.
  .63–.72 ran reactive: agnos GPU band #82–#91 (now contiguous) + lib-freshness (.63/.70/.71/.72),
  **Win64 stack-args P0** (.64, ECALLPOPS 10+-arg corruption), thread-local slot allocator (.65),
  getpeername xlat (.66) + sandhi 1.9.1 getpeername fold (.71), chrono DateTime (.67), agnos
  `sys_reboot` 4-arg (.68), **f64 JSON round-trip** (.69, bayan 1.2.1 Grisu2 + fmt_hex high-bit
  fix), and `cyrius coverage` scoped to project `src/` not vendored stdlib (.72). No arc
  in flight. **SUPERSEDED 2026-07-22:** `public`/`private` visibility is **NO LONGER a 6.4.x arc** —
  it moved to the **v6.5.0 OPENER** with its design **COMMITTED** (a file-level `private` declaration
  flips that file to private-by-default for `fn` *and* `var`; a per-item `public` re-exposes; no
  declaration = everything public; the `_`-prefix convention is explicitly LATER). 6.4.x then ran
  reactive (agnos asks + bugs) through .73–.82. Authoritative:
  [`proposals/2026-07-02-function-visibility-pub-private.md`](proposals/2026-07-02-function-visibility-pub-private.md)
  — **the old hybrid / derive-from-`_` framing is superseded and has been rewritten out of this
  file** (section 4 below).
- **v6.4.73** — **`cyrius audit` + `cyrius capacity` compiled project sources with NO stdlib includes.**
  Neither verb was ever added to `_auto_deps()`'s hard-coded command list — the **third** instance of
  the class (`fuzz` joined at v5.7.21, `soak`/`smoke` at v5.7.38) — so on stiva the same tree that
  `cyrius test` passed 202/0 audited **0 passed, 5 failed**, every failure a wall of `undefined
  function 'alloc'`. It hid in-repo because 250 of our 251 `.tcyr` self-declare their includes.
  `capacity --check` was the more dangerous half — a **green placebo** compounding four defects (no
  prepend, unread child exit status, zero parsed stats lines counted as zero tables over threshold,
  8 KiB stderr cap truncating the stats block); it now hard-fails rather than certify. Plus the
  `CYRIUS_STATS` `code_size` denominator (stale 1 MiB → the 64 MiB growable codebuf of .49, which had
  been publishing **269 %** for a healthy build), the sliced v6.4.72 `lib/fs.cyr` fix **completed**
  across 8 sibling path fns (13 `: Str` params — bare-literal args silently returned 0, and
  `fs.tcyr` passed 13/13 against the broken library because every assert wrapped its args in
  `str_from`), and agnos GPU `#92`/`#93` descriptor-array wrappers. **Filed the fn_table P0** below.
  check.sh 147; cycc 1,103,528 B.
- **v6.4.74** — **module-scope `var X = <computed expr>` read 0 forever in an agnos kernel**
  (consumer-filed). Narrower than the filing: **x86-ELF kmode only** — the deliberate v5.7.19
  multiboot invariant emits `PARSE_PROG` first and the gvar inits after, and agnos's top-level
  program never returns, so that block is dead code. Fixed with a constant folder (`_CF_TRY`)
  widening the static-init path from a bare `= NUM ;` to any foldable integer expression;
  `var A = 512 * 2;` now images byte-identically to `= 1024`. Two traps worth carrying: **cybs
  cannot lex `>>>`** — only `seed-derive-cycc.sh` caught it, the cycc fixpoint does not substitute
  for the seed gate — and **cyrius precedence is not C's**, `&`/`|`/`^` share the `+`/`-` tier
  (pinned by a 42-expression/84-probe differential). Also fixed the **pre-existing `_cfo` re-arm bug
  at 17 `PARSE_TERM`-tier sites** (`100 >>> 1 + 1` == 2 in ordinary fn bodies) and the `kmode emit
  order` gate, which had been passing **vacuously off that very bug**. check.sh 147; cycc 1,103,544 B.
- **v6.4.75** — **P0: `fn_table` growth past 8192 silently corrupted six fn-indexed side tables.**
  The v6.2.0 migration made the 17 `_fnt_*` tables growable (init cap 8192, ×2 to a 32768 ceiling)
  but left six others keyed by the same `fi` at fixed 8192-slot bands packed back-to-back —
  **index 8192 of each is index 0 of its neighbour**, written by `PARSE_FN`'s unconditional per-fn
  reset, with no diagnostic. cycc (~1135 fns) could never reach it; **stiva was at 7443/8192**.
  Fixed on the v6.4.23 `_vsgn_base` precedent — lazy-alloc at the 32768 ceiling, never grow — so the
  six accessors carry the whole change with **no per-fork driver edit and no grow-chain link** (an
  8th link is what desynced cybs for the var family). Plus `REGFN`'s forward-overload write to a
  stale pre-grow base, the DCE `live[4096]`-cleared-1024 mismatch (uninit stack bits kept dead fns
  alive non-deterministically), and the capacity warning re-pointed at the fixed 32768 ceiling — it
  had divided by the *live* cap, so it screamed at 8191 fns and went **silent** the instant the table
  grew, exactly when corruption started. New mutation-proven `_fn_grow_gate`; check.sh 148;
  251/251 byte-identical.
- **v6.4.76** — **identifier pool (`tok_names`) 256 KB → 512 KB, in place** — the companion to the
  .75 P0 (stiva was at 93 % and had already split its test suite **four** times). Constants-only:
  the two LEX thresholds `261872 → 524016`, the capacity divisor, the `CYRIUS_STATS` denominator,
  and the heap-map size line in all 5 forks that carry it. Safe because the band `0xA0000–0x100000`
  is unoccupied in all 7 forks; the pool now ends at `0xE0000`, **128 KB under the `0x100000`
  physical ceiling** above which it overruns the hash/var tables and the compiler *hangs* (that
  ceiling is now documented at the threshold). No region moves → **not a layout change**, no
  two-step bootstrap, byte-identical. New `_idpool_gate` (mutation-proven against .75);
  check.sh 149; cycc unchanged.
- **v6.4.77** — **reserved intrinsic names reported `got unknown` — 67 tokens, not the 3 filed.**
  `IS_KEYWORD_TOK` and `TOKNAME` both stopped at token 111, so every intrinsic above it fell through
  to `"unknown"`, pointing at a syntactically clean identifier and calling it unknown; it cost hisab
  its whole 312-assertion suite, findable only by bisection. New `TOKNAME_BUILTIN` table with
  **`IS_KEYWORD_TOK` deriving from it**, so the "is it reserved" and "what is it called" sets cannot
  drift and a future named intrinsic is reserved automatically. Counting trap: a first pass finds
  **51** — the lexer has two keyword paths and >8-char names are a u64 compare plus `load8` tails.
  Also: tokens **79** and **111** are double-assigned, so the diagnostic actively named the *wrong*
  keyword (`var f64_sqrt = 1;` said `'object'`); `cyrius lib sync` now **refuses to run in this
  repo** (it would silently revert every fold); sandhi re-vendored **1.9.1 → 1.9.3**; and
  `docs/ecosystem.md`'s folded-distlib table was stale on **5 of 11** rows. check.sh 149;
  cycc 1,108,272 B (+4,648 — the 67 name literals, a diagnostic-only path).
- **v6.4.78** — **`cyrius audit` fmt/lint/doc-walked the consumer's VENDORED `lib/`** (stiva-filed):
  the sweep conflated *exists on disk* with *belongs to this project*, so consumers got a permanent
  `FAIL: files need reformatting` for other people's bundles — with a printed remedy that rewrites
  files `cyrius deps` overwrites and breaks `deps --verify` hashes. Now gated on
  `_dep_is_cyrius_source_repo()`; note the filing's preferred `[deps]`-section test **would have
  broken this repo**. The stage now prints its `scope:` and NAMES the failing files
  (`AW_FMT_FAIL_FILES` had been populated since it was written and never printed). Plus `cyrius
  bench` finding `tests/<name>.bcyr`, and the **`PEEKT` EOF clamp** — truncated input went from a
  **166,670-line** error cascade to 5 lines. The hot-path objection that got it filed separately
  evaporated: `PEEKT` already has an `_had_error` guard and the runaway is post-error only, so the
  clamp inside it costs **−0.07 %**. check.sh 149. **RESIDUAL (do not re-file): `cyrius audit`
  still FAILs in the cyrius repo — cycc's `src/` is not cyrfmt-clean by design.**
- **v6.4.79** — **sankoch 2.7.6 fold: batch gzip/deflate corrupted every input over 1 MiB.** Both
  per-block encoders match against the full `src` (cross-block back-refs are what keep the ratio), so
  a match starting just below `block_end` can run up to 258 B past it — and the chunker resumed at
  `block_end` regardless, encoding the overshoot a second time. Nothing errored at compress time; it
  surfaced arbitrarily later as a CRC-32 failure, which for stiva meant **every container image
  larger than ~1 MiB was written to disk corrupt**. **Fixed UPSTREAM first** (a real sankoch 2.7.6
  cut, all 10 dist profiles, full suite) *then* folded, per "fix the SOURCE repo, not the fold";
  cross-validated against GNU `gunzip`. Two subtleties that would each have left a partial fix: the
  lazy-match flush consumes to `sp - 1 + prev_match`, and `BFINAL` is decided *before* the block is
  encoded. The suite missed it for years because every deflate test used input **under** the 1 MiB
  block size. Also filed: `cyrius distlib` has no all-profiles mode — the documented release step
  left all **nine** sub-profiles at 2.7.5 still carrying the buggy encoder. cycc byte-identical.
- **v6.4.80** — **`1 - 2 + 3` evaluated to `5` — the `_cfo` rewind class, THIRD occurrence.** The
  PEXPR tier (`+ - & | ^`) silently discarded its **left operand** whenever a literal subtraction
  produced a negative intermediate (the `cfr >= 0` test fails → the runtime fallback, and the
  fallback was the buggy one): **40 of 400 (10 %)** systematic 3-term constant expressions were
  wrong. Same mechanism .74 fixed one tier down, 16 more sites. **Grep the SHAPE, not the
  operator** — a single `grep "_cfo = 0; E.*PARSE_TERM"` at .74 would have found these eight
  releases earlier. **251/251 tcyr byte-identical is the finding, not the reassurance**: the corpus
  contained zero expressions of the failing shape, so 10 % of constant arithmetic could be wrong
  with every gate green. Coverage 8 → 33 asserts took three rounds (AND/OR/XOR each need a different
  shape; ADD is reachable only via i64 overflow). **Found by a doc-sweep verifier *running* the
  compiler.** check.sh 149; cycc unchanged.
- **v6.4.81** — **a FOURTH `_cfo` occurrence, plus CVE-32/33/34.** Struct operator-overload
  dispatch: `mul`/`div` never cleared `_cfo` where `add`/`sub` did (a 2-of-4 asymmetry in four
  structurally identical lines), so the emitted operator **CALL** was rewound over — `p * 3 + 1`
  compiled to **4**. **Grep for calls that RE-ARM `_cfo`, across every tier**, not just the tier the
  repro landed in. **CVE-32/33/34** = three unbounded copies reachable from untrusted source, which
  cycc compiles by design: `include "<31490 A's>.cyr"` **SIGSEGV'd cycc**, `READFILE`'s
  `CYRIUS_HOME` fallback composed into an unbounded `var fbuf[512]`, and a long `$HOME` overran
  `_cyrius_lib`. CVE-32 survived three minors of heap-map audits because **the map documented a
  region no code has ever written** (`0x190500 [256]`; every use is `0x190400`, unbounded) — the map
  is machine-read, so explanatory prose on a map line is parsed as the size. Also the new
  `_doc_stamp_currency_gate` (born RED on live rot — this file's head was eight releases behind), the
  `src/main.cyr` PE/Mach-O **cross** arms that silently dropped value-form SIMD for the whole minor,
  the two Windows PE gates that had been validating a **cycc 5.11.69** binary since 2026-05-19,
  `tests/heapmap.sh` blind to **20 MB** of live heap (its size regex missed `[16 MB]`-style
  entries — region count 94 → **100**), and CVE-35/36 (23 fixed `/tmp` literals in `cbt/`).
  check.sh **150**; cycc 1,108,328 B.
- **v6.4.82** — **the v6.4.x CLOSEOUT.** The **TS frontend arena moved off its fixed base
  `0x298B000` to `alloc(TS_HEAP_SIZE)`** — it had overlapped `tok_types` **entirely** plus 1.6 MB of
  `tok_values` (10,027,008 B), survivable only by an undocumented temporal invariant
  (`--lex-ts`/`--parse-ts`/`--emit-js` all exit before `LEX`). Taking the arena from the allocator
  sidesteps the ~14.2 MB-contiguous problem that made .81 correctly defer it as a brk/heap-**layout**
  change, and it costs nothing on a normal compile because the region is taken only when a TS mode is
  active. Plus agnos **`#94 gpu_recover_op` / `#95 uptime_us`** wrappers — the band is now contiguous
  **#82–#95** — with the `GpuRecoverArm` enum so consumers stop hand-rolling arm numbers; `#94` is
  `lchown` on x86_64 (arg1 read as a **path**) and **`exit_group` on aarch64**, where a raw
  `syscall(94, arm)` silently terminates the process, which is precisely why the wrapper matters.
  Closeout passes: heap map **100 regions / 0 overlaps**, backlog re-triage, doc sync. Read that 100
  carefully — it is **not** the pre-.75 100 restored. It went 100 → **94** at .75 when six fn-indexed
  side tables went lazy-alloc and their fixed bands were freed, then back to **100** at .81 when the
  auditor's size parser was fixed to see unit-suffixed entries (`[16 MB]`) it had been skipping
  entirely. Same number, different route, six different regions.

**Current head: v6.5.2** — cycc **1,129,272 B** · check.sh **150 passed / 0 failed** · self_compile ~665 ms. **v6.5.1 fixes the overload-suffix dispatch compiler-side** (it was arity-blind, and `PARSE_RETURN`'s tail path skipped it entirely, so `var r = f(s)` and `return f(s)` ran different functions) and folds bayan 1.3.0 / sakshi 2.4.7 / yantra 1.0.2 / sandhi 1.9.7 — two of which had renamed their own functions to escape that defect. **The v6.4.x minor CLOSED at v6.4.86** (closeout ran .80–.85; see the cycle-discipline ledger). **v6.5.0 opens the v6.5.x minor with the `public`/`private` file-scoped visibility arc** — delivered on the `privatefns` branch: file-id substrate + the preprocessor resume-marker repair, `private`/`public` for fns AND global vars, hard-error enforcement across the ordinary/tail/operator call paths and `FINDVAR`, `private` excluded from .dynstr, api-surface visibility-derived, `lib/regex.cyr` adopted. This file still describes the v6.4.x slot table below; the v6.5.x pin sequence is the next doc pass.
**~622 ms** · 251 `.tcyr` · 99 `lib/*.cyr` · api-surface **4749** public fns · heap map **100 regions,
0 overlaps** · **11 open issues + 3 proposals** (273 archived). Verified against live artifacts at the
v6.4.82 closeout. `_doc_stamp_currency_gate` (check.sh, since .81) keys on the `Current head` anchor
that opens this paragraph and checks `VERSION` appears within 240 bytes of it; it **fails loudly** if
the anchor disappears rather than passing on a missing one, so keep the string and keep it unique.

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
| 1 | **Packed SIMD compute** (f32-first, then integer; ML/AI) | **5–7 releases** | No | **✅ COMPLETE on all four backends — x86 SSE+AVX2 (.4–.9), aarch64 NEON (.28–.30), Win64 PE value-form (.31), cx bytecode (.32)** |
| 2 | **Array-typed struct fields** | **3 releases (done)** | No | **✅ DONE — R1 v6.4.11 · R2 v6.4.12 · R3 v6.4.13 (`Vec<T>` fields + `#derive` Vec<primitive>/Vec<struct>)** |
| 3 | **UEFI Secure Boot signing** | **2 releases (was 3–5)** | No | **✅ COMPLETE — signing (`cyrius sign-efi`, v6.4.47) + enrollment (`.esl`/`.auth` via sigil 3.11.1's `efi_sigdb`, v6.4.48). Premise-check shrank it: sigil already shipped the Authenticode crypto core.** |
| 4 | ~~**Function/var visibility** (`public`/`private`)~~ **MOVED to the v6.5.0 OPENER (2026-07-22)** | **4–6 releases** | No | design COMMITTED — file-scoped opt-in, default public; see the [proposal](proposals/2026-07-02-function-visibility-pub-private.md) and the v6.5.x table below |
| 5 | **cx portable bytecode target** (CLI `--target=cx` + `cxvm` run + scalar float + cross-OS `.cyx`) | 5 releases (.17–.20, .22) | No | **✅ DONE. A=CLI, B=f64, .19=f64-compare, C=cross-OS `.cyx` (all 4 hosts), .22=cycc_cx cross-native (macOS/Win). Tail: f32/transcendentals fail loud.** |
| 5b | **Async runtime — reactor + suspend/resume foundation, THEN tokio-parity primitives + IOCP-Windows** (unblocks stiva v3.1 + thoth `--win`) | 6–8 releases (shipped in ~13: .33–.45) | No | **✅ SHIPPED (.33–.45).** FOUNDATION-FIRST (reactor + the 5 tokio-parity primitives, .33–.41) → consolidation (.42) → IOCP-Windows "W" step: client (.43) / timers+subprocess+combinator-parity (.44) / AcceptEx server (.45), all target-agnostic and release-gated on real cass. `async_accept` closes the surface. Mid-body suspend/resume — the "gap 6" of this arc — is **▲ PINNED v6.5.x** as **stackless coroutines** (user, 2026-07-26; it was parked in roadmap-future until stiva filed the consumer requirement), bound to the v6.5.x IR substrate it depends on. `tantu` extraction = RESERVED future-minor deliverable (repo name held) — NOT sequenced. (pinned 2026-07-07, shaped 2026-07-09, shipped 2026-07-10; history: [`issues/archived/2026-07-07-async-runtime-tokio-parity-gaps.md`](issues/archived/2026-07-07-async-runtime-tokio-parity-gaps.md), [`issues/archived/2026-07-08-async-epoll-only-blocks-win-transport.md`](issues/archived/2026-07-08-async-epoll-only-blocks-win-transport.md)) |
| 6 | **Scalar-float completion** (f64 return type + f32 scalar arithmetic + typecheck strictness) | 2–3 releases (done in 2) | No | **✅ COMPLETE — f64 scalar return (v6.4.55) + f32 arith/compare + WARN-only typecheck (v6.4.56)** |
| 7 | **DX: diagnostics** (multi-error reporting + column/excerpt) | 2–4 releases (done in 2) | No | **✅ COMPLETE — R1 column + source-excerpt/caret (v6.4.60) + R2 panic-mode multi-error (v6.4.62)** |
| T | **Intel-Mac (x86_64 Mach-O) toolchain tail** | 2–4 releases (done in 1) | No | **✅ COMPLETE — Intel-Mac x86_64 Mach-O revival (v6.4.59); `ach` now a first-class release-gate host** |

**Opening sequence total: conservatively ~22–35 `.NN` releases** (grown from ~17–26
at the 2026-07-07 horizon session: + cx CLI exposure, scalar-float completion,
diagnostics) — v6.4.x is a **long minor**, per the user's standing preference for
**large minors (~45–99 releases historically), not a theme-per-minor**. **None of the
arcs is a release-blocker.** **Pin 1 landed complete across x86 (v6.4.4–.9),
aarch64 NEON (.28–.30), Win64 PE (.31), and cx (.32)** — the aarch64-NEON remainder shipped;
it is no longer paused (see the Pin 1 completion note). On top of the arcs, **reactive agnos + consumer-filed repairs
interleave throughout** and consume **separate** slots that are **not** counted above (already this
minor: .0's own de-risking, .1 alloc_reset, .2 agnos audio, .3 the f64 SIMD-surface solidification,
and .10 the kernel-blocker + distlib-cap interim fixes) — see *Reactive headroom* below.

---

## 2026-07-07 horizon additions (user-committed, planning session)

Three additions to THIS minor. (The same session also reframed **v6.5.x** as the
**Performance-Quality minor** — absorbing the SIMD register-residency / IR-regalloc
work — set **v6.6.x** as the **Language-Ergonomics minor**, and re-homed **RISC-V
rv64 to v6.7.x/v6.8.x**; see [roadmap_6.md](roadmap_6.md).)

- **cx portable bytecode target — ACTIVE ARC (opened after v6.4.16).** A consumer
  agent hit the **wasm-shaped wall** — the cx backend is built, self-hosting, and
  check.sh-gated but had ZERO user-facing surface. Scoped by a 6-facet code-grounded
  workflow (2026-07-07); **user chose the FULL portable target** (cx as a first-class
  portable `.cyx` distributable across OSes, WASM an explicit non-goal — CYX
  register-bytecode ≠ WASM). Key code facts: cx is a **source FORK** (`src/main_cx.cyr`),
  so `--target=cx` **resolves+execs a `cycc_cx` binary** (cross-compiler dispatch, NOT
  the `--target=js` flag model — a flag merge would be a deep emit-dispatch rewrite);
  `.cyx` = `"CYX\0"` + entry, fixed 4-byte instrs; `cxvm` reads `.cyx` from stdin, exit
  code passes through. **🚩 `EMIT_FLOAT_LIT` (emit.cyr:793) emits GARBAGE** (raw
  rational-pair bits) — any float constant silently miscompiles the moment cx is
  exposed, so float is **hard-errored in A** and implemented in B. cxvm is x86-Linux-only
  (raw syscalls, no ESYSXLAT) + **64 KB code/data caps** — the cross-OS/cap work is arc C.
  **Locked decisions:** FORK model · `cxvm` → `cyrius.cyml` bins (installed) · `cycc_cx`
  → cross_bins (rebuilt-on-demand, gitignored) · `cyrius run foo.cyx` via `.cyx`-extension
  detect + stdin-pipe (`#ifdef` guard for the PE `cyrius` build) · **cx SIMD DEFERRED+filed**
  (scalar-loop in an interpreter = zero speedup, fails ADR-002).
  - **Release A ✅ SHIPPED (v6.4.17)** — `--target=cx` (FORK dispatch via `cycc_cx`
    resolver + JIT/cross_bins) + `cyrius run foo.cyx` (`.cyx`-extension → cxvm stdin) +
    `cxvm` install (bins) + a **versioned `.cyx` header** (CYX_VERSION=1, before the
    format is public) + float **hard-error** (was silent garbage) + `tests/cx_cli.sh`
    end-to-end gate. cycc byte-identical; check.sh 132; cross-OS GREEN incl. cass/PE.
  - **Release B ✅ SHIPPED (v6.4.18)** — cx scalar f64 ARITHMETIC: host-backed f64
    opcodes in cxvm (0x54-0x5F + fneg/fabs) + rewired emitters (`EMIT_FLOAT_LIT`/binop/
    casts/neg/abs). **+ a foundational global-var-collision fix** (fixup-table
    reader/writer address mismatch — all top-level vars collided at addr 0, pre-existing).
    f64 **comparisons deferred** (fail loud): the compare result is F64-typed and misbehaves
    in `if()`/`==` on cx — `issues/archived/2026-07-07-cx-f64-compare-result-typing.md` (the cxvm
    compare opcodes ARE shipped+correct; a one-line SESTYPE fix was tried + rejected —
    churned 10 programs, didn't fix cx). f32/transcendentals still fail loud.
  - **f64-compare follow-up ✅ SHIPPED (v6.4.19)** — root cause was NOT the F64 type; cx's
    flag-less `EJCC` re-compared against a stale r1 on the bare-boolean truthiness path. Fix:
    cx `ETESTAZ` sets r1=0 + `EF64_CMP` re-wired to 0x5A-0x5F (cx-backend-only, cycc byte-id).
    Also fixed a latent bare-int-boolean branch bug. cx now runs real int/float programs
    (arithmetic + comparisons + conditionals). **NEXT: Release C.**
  - **Release C ✅ SHIPPED (v6.4.20)** — portable `.cyx` doing real I/O runs on **all
    four hosts** (x86-Linux/pi/ecb/cass), verified on real hardware (write+exit AND
    file open→read→write→close). **NO C1/C2 split needed** (boundary-set-after-reading
    confirmed it): the scoping premise was wrong — the compiler's `ESYSXLAT`/
    `EMACHO_SYSXLAT` already renumber a runtime (var) syscall number per-host, so the
    real bugs were cxvm-only: the `open` pointer-slot (fixed s3=flags → s2=path) + the
    Windows argc-6 arity-bucket miss (→ arity-correct dispatch: argc4 read/write/open/
    lseek, argc2 close/exit). Caps 64 KB→1 MB + overflow probe. cxvm ships in the
    macOS/Windows tarballs; `cross-os-selfhost.sh` + `cx_cli.sh` gate a portable-`.cyx`
    I/O fixture. cycc byte-identical (cxvm is off the self-host chain).
  - **✅ cycc_cx cross-native — SHIPPED v6.4.22.** The cx **compiler** faulted at runtime
    on macOS/PE (arena used `brk`, absent on XNU/Win32) — fixed with per-target `#ifdef`
    (mmap on macho/PE). Native `cycc_cx` compile→run round-trip verified on ecb + cass;
    re-added to all 3 tarball builders + gated in `cross-os-selfhost.sh`.
  - **Deferred (filed):** cx SIMD (+ the `issues/2026-07-05-...phase5.md` cx-SIMD closure
    note); f32 conversion + transcendentals still fail loud on cx.
  Full stub: [`proposals/2026-07-05-cx-bytecode-cli-exposure.md`](proposals/2026-07-05-cx-bytecode-cli-exposure.md).
- **Async runtime — tokio-parity primitives (arc 5b) — CONSUMER-BLOCKED, scheduled
  right after SIMD Phase 5.** The **stiva v3.1 async port (our Docker project) is
  blocked NOW** on 5 library-level API primitives with no runtime today: async
  subprocess spawn/wait/output, `interval` + `timeout` combinator, a joinable
  `JoinHandle`/`task_join`, async TCP client + `join_all`/`select`, and `async_rwlock`.
  These were surfaced by [`issues/archived/2026-07-07-async-runtime-tokio-parity-gaps.md`](issues/archived/2026-07-07-async-runtime-tokio-parity-gaps.md)
  and were initially triaged toward the roadmap-future watching list — **corrected
  2026-07-07: a real consumer is blocked, so async is NOT parked in v6.8.** It's a
  committed near-term arc, sequenced **immediately after SIMD Phase 5 (Pin 1)** per the
  user's "SIMD first, then async" call — ahead of the order-committed arcs 3/4/6/7. The
  arc's likely home is a `sutra`/`kaal` async-runtime lib the issue proposes (extract →
  vendor back). The 6th gap in the filing — stackless suspend/resume (execution-model,
  not a library primitive) — is now **▲ PINNED v6.5.x** as **stackless coroutines** (user,
  2026-07-26): stiva stopped being a "would-be" consumer and **filed**
  ([`issues/2026-07-25-stiva-stackless-coroutines-interactive-exec.md`](issues/2026-07-25-stiva-stackless-coroutines-interactive-exec.md),
  two blocked v3.1.0 features), which met the unpin condition
  [roadmap-future.md](roadmap-future.md):116 had carried for it. It was NOT a blocker for the
  5 primitives, and it lands with the v6.5.x IR substrate — see the v6.5.x slot table. Final interleave vs arcs 3/4 is the user's call;
  the intent is near-term, not deferred.
  - **ARC-OPEN DECISIONS (2026-07-09, after a code-grounded premise-check — 8-verifier
    workflow).** Arc 5b opens at **v6.4.33**. All 6 gaps confirmed still-missing against v6.4.32
    source (none stale). **The reframe:** the runtime is **not actually an event loop** — the rt
    epoll fd is created+closed but never used to multiplex (`async_run` is a serial linked-list
    sweep, [`lib/async.cyr`](../../lib/async.cyr) 99–122), `TASK_WAITING` is a **dead state**
    (declared, never stored), nothing yields mid-body, `async_sleep_ms` blocks the whole loop,
    the runtime is single-use, and tasks are single-arg with no result slot. So gaps 1/2/4/5
    cannot be **honestly** non-blocking without a **reactor + cooperative suspend/resume**
    substrate first; only **gap 3 (JoinHandle)** is deliverable in today's run-to-completion
    model. Two uncovered categories the 5-item list omits: **async file I/O** and **async DNS**
    (a name-based async client still blocks on `getaddrinfo`). **User calls (2026-07-09):**
    **(1) FOUNDATION-FIRST** — build the reactor + suspend/resume + JoinHandle substrate before
    the primitives (the "one bug ships complete" discipline; a blocking veneer over today's model
    is a semantic dead-end). **(2) IOCP-Windows folded into this arc, sequenced AFTER gap
    coverage** (issue 2026-07-08; `FOUNDATIONAL_DEPENDENT` — epoll has no poller seam and each
    primitive adds inline poll sites, so `async_win.cyr` must MIRROR the frozen surface).
    **(3) Extraction DEFERRED to a later minor** — build in-place in `lib/async.cyr` for now;
    **when extracted+refolded the repo will be named `tantu`** (thread/fiber). The `async`/`await`
    sugar stays compiler-resident (lex tokens 134/135, `_ASYNC_OK` gate in
    [`parse_fn.cyr`](../../src/frontend/parse_fn.cyr) / [`parse_expr.cyr`](../../src/frontend/parse_expr.cyr))
    — only the 13-fn runtime library is ever extractable. **Proposed dependency-ordered shape:**
    F1 reactor → F2 suspend + task substrate (+ JoinHandle, gap 3) → P1 timers (gap 2) → P2
    subprocess (gap 1) → P3 net client + `join_all`/`select` + async DNS (gap 4) → P4 `async_rwlock`
    (gap 5) → W IOCP-Windows mirror. Length grew from ~3–5 to ~6–8 releases (foundation +
    IOCP-mirror + 2 uncovered I/O categories).
- **Scalar-float completion** — ✅ **DONE (v6.4.55 / .56 / .57).** Scalar `f64` as a
  function RETURN type (xmm0 per SysV, sentinel -9) shipped **v6.4.55** — the
  allow-list now admits `f64` (`parse_fn.cyr`), closing §1 of
  [`issues/archived/2026-07-04-agnos-fp-xmm-state-and-f64-scalar-return.md`](issues/archived/2026-07-04-agnos-fp-xmm-state-and-f64-scalar-return.md).
  **f32 scalar arithmetic** + the stricter f64/f32 typecheck shipped **v6.4.56**;
  f64/f32 param arithmetic + float compound-assign + the compare-mix warning
  shipped **v6.4.57**. Retired the i64-boxed-f64 idiom, where a plain `+` on a
  boxed f64 silently integer-added the bit pattern.
  (Stale-shipped through v6.4.64 — this bullet still asserted "today's allow-list
  admits `f64v2`/`f64v4` but not `f64`" in the present tense, ~9 releases after
  v6.4.55 falsified it, which is what kept the linked issue reading as open.)
- **DX: diagnostics — ✅ SHIPPED (R1 v6.4.60 column + source-excerpt/caret, R2 v6.4.62
  panic-mode multi-error).** A maintenance-cost item: consumer-filed misdiagnoses are the
  recurring tax better errors retire. **DWARF debug-info is a separate deliverable and is
  NOT part of this arc** — only the error-reporting layer moved here. It is **6.x-line
  backend work in the potential backlog below**, never 7.x (it emits sections into the
  object file; if it touches codegen it stays in the 6.x cycle).

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
([`issues/archived/2026-07-03-v6345-closeout-audit-backlog.md`](issues/archived/2026-07-03-v6345-closeout-audit-backlog.md)
— L1 pp-flag-table 16-slot silent-corruption cap, L2 `_msx` imm8 ≥128 guard,
R1–R5 parallel-copy consolidations), the decode.cyr no-ModRM-0F mis-length fix,
the SIMD value-form typecheck residual, and an **issue-archive hygiene pass**
(open queue ~21; resolved-in-header entries archive per
[[feedback_issue_hygiene_batch_not_pile]]).

---

## PINNED — immediate work

### Pin 1 — Packed SIMD compute (f32-first, then integer; ML/AI priority) — ~5–7 releases

> **✅ PIN 1 COMPLETE (2026-07-09, v6.4.32): packed SIMD ships on ALL FOUR backends.**
> Phases 0–4 shipped x86 SIMD end-to-end — f32v4 (v6.4.4), f32 matmul (v6.4.5), integer
> vectors (v6.4.6/.7), and f32v8 256-bit AVX2 + FMA/dot (v6.4.8/.9). Phase 5 then completed
> the remaining backends: **aarch64 NEON** (v6.4.28 f32v4/f32v8, .29 f32v8-free via 2×128
> fallback, .30 integer vectors + `iv_dp8` — the **last SIMD XFAIL removed**), **Win64 PE
> value-form params + returns** (v6.4.31), and **cx bytecode per-lane emitters** (v6.4.32,
> cxvm opcodes through 0x68). The break point is **resolved** — no ARM XFAILs remain;
> `simd_f32v4`/`simd_ints`/`simd_f32v8` all pass on aarch64 (NEON) and cx, verified on real
> hardware (pi/ecb/cass). Phase 5 was the mechanical NEON mirror of `EMIT_F64V_*` it was
> premise-checked to be (`.2d`→`.4s`, llvm-mc-sourced; fmul+fadd not fmla to match x86
> rounding). Only the aarch64 *native* 256-bit f32v8 emitters remain return-0 stubs never
> reached at runtime — `lib/simd.cyr` routes f32v8 through native f32v4 NEON, so the verb
> works; native 256-bit stays x86-AVX2-only. Remaining SIMD follow-ons (register residency,
> `i64v2` value-form multiply, cx value-form params) are filed as standalone polish items,
> not blockers.

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
  [`2026-07-04-integer-simd-encoding-design.md`](proposals/archived/2026-07-04-integer-simd-encoding-design.md)):
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
  non-SIMD-returning callee skips the type-check — `issues/archived/2026-07-05-valform-simd-param-typecheck-only-when-simd-return.md`).
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
  f32v8 fmadd + 8-lane dot + GEMM bench — PHASE 4 CLOSES; x86 SIMD COMPLETE** → **(5 ✅ v6.4.28–.32)
  aarch64 NEON (fmul+fadd, not fmla, to match x86 rounding; `smull`/`saddlp` int-dot) + Win64 PE
  value-form (.31) + cx bytecode per-lane (.32) → (6 ✅) `lib/simd.cyr` wrappers + docs → PIN 1 COMPLETE
  on all four backends.** **R1 (v6.4.8):** first VEX/AVX in the toolchain
  (2-byte C5, llvm-mc-verified, disasm-gated); 256-bit value-return ABI generalized to `_is_simd256` (byte-id
  for f64v4); `simd_has_avx2()` CPUID probe + branching wrappers; decode.cyr VEX dropped (pre-existing SYSCALL
  mis-decode, filed). **R2 (v6.4.9):** first 3-byte VEX (C4) — `vfmadd231ps` (FMA3) + the 8-lane `vextractf128`
  dot reduce; `simd_has_fma()` (leaf 1 ECX bit 12) gate; `bench_f32v8_gemm` ~1.48× (256 vs 128-bit). f32 SIMD
  now complete on x86 (f32v4 + f32v8); Phase 5 later landed it on aarch64/PE/cx (the `simd_f32v8` aarch64 XFAIL was removed at v6.4.29).
- **▶ Phase 4 (f32v8 + 256-bit AVX2) — arc-open DECISIONS (user 2026-07-05, after a code-grounded
  premise-check).** Full design + disassembler-verified VEX byte encodings + the CPUID-fallback design
  live in [`proposals/2026-07-05-f32v8-avx2-phase4-design.md`](proposals/archived/2026-07-05-f32v8-avx2-phase4-design.md).
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
    `issues/archived/2026-07-05-decode-len-mislengths-no-modrm-0f-opcodes.md`.) **R2** = `vfmadd231ps` + the 8-lane dot (`vextractf128` + SSE fold — the two-
    `haddps` f32v4 pattern can't cross the 128-bit lane split) + a f32v8 GEMM bench (proves the AVX2 win
    vs the "256-bit-in-name-only" trap). Guard the recurring bug-classes: the `−2153` `0 − lt → sid`
    sites (struct-guard covers it, verify each new site), the retptr-stash rough-scan (pointer-form
    dodges), mask saturation (pointer-form dodges), and `_is_simd256` lane-width-blindness.
  - x86-only *at Phase 4* (aarch64 NEON is 128-bit → 256-bit is 2×V-pairs; cx stubs; PE gated) — all resolved in Phase 5 (.28–.32).
- **Phase 5 cleanup (carried from v6.4.4)** — ✅ **DONE.** aarch64 `EMIT_F32V_LOOP` shipped v6.4.28
  and cx per-lane emitters v6.4.32; the `simd_f32v4`/`simd_ints`/`simd_f32v8` XFAILs were removed at
  v6.4.28–.30, the `vr01_simd_*_neon` + `vr01_simd_cx` cross-OS fixtures are in the release-gate glob,
  and the "x86-only this phase" stub comments are gone. Issue `2026-07-05-aarch64-f32v4-xfail-phase5.md`
  is archived.
- **Risks**: integer-lane semantics (saturating, signed/unsigned per width, widening-madd) have
  no f64 template → sign-ext/truncation surface (cf. v6.3.35/.36); VNNI/sdot/FMA availability
  varies per arch (feature-gated); bench-gated acceptance (a correct-but-slow cut doesn't satisfy
  the consumer). Cross-repo acceptance benches: dense-f32 GEMM + tentib 0.4.1 (separate repos).

### Pin 2 — Array-typed struct fields — ~3–4 releases

> **STATUS (2026-07-06): ✅ COMPLETE — R1 + R2 + R3 SHIPPED.** Representation fork RESOLVED by
> user → a typed **`Vec<T>` HANDLE** (not inline `T[N]`); syntax **`Vec<T>`**; 3-release split, ALL SHIPPED:
> **R1** parse + metadata + access (✅ **v6.4.11**) · **R2** `#derive` Vec<primitive> (✅ **v6.4.12**) · **R3**
> `#derive` Vec<struct> (✅ **v6.4.13**) + svara minor patch. Full design + sentinel encoding + risks:
> [`proposals/2026-07-06-array-typed-struct-fields-design.md`](proposals/archived/2026-07-06-array-typed-struct-fields-design.md).
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

### Pin 3 — End-of-compile capacity-warning consolidation — **✅ SHIPPED v6.4.50**

> **✅ SHIPPED v6.4.50.** Extracted the inline warning block into one shared
> `_capacity_warnings(S, codebuf_cap, codebuf_growable)` in `common/util.cyr` (next to
> `_codebuf_grow`) and wired all 7 drivers; the 5 previously-silent forks
> (`main_aarch64{,_native,_macho}`, `main_x86_macho`, `main_cx`) now warn. Native forks
> pass `(67108864, 1)` — the 64 MiB growable codebuf; cx passes `(524288, 0)` — its fixed
> 512 KiB region. Logic-preserving: cycc self-host + seed-derive + cross-OS (pi/ecb/cass)
> byte-identical, differential 0/0 (default + DCE), dead-code floor unchanged, check.sh 141.
> See CHANGELOG [6.4.50].
>
> **Reactive follow-on from v6.4.49** (the codebuf 8 MiB / growable work). Surfaced there:
> the end-of-compile capacity-warning block — `warning: var_table / fixup_table /
> string_data / code buffer at N% …` — lives ONLY in `main.cyr` (x86-Linux) +
> `main_win.cyr` (Win64), **duplicated inline**. The five other drivers —
> `main_aarch64{,_native,_macho}.cyr`, `main_x86_macho.cyr`, `main_cx.cyr` — emit
> **zero** capacity warnings, so an aarch64 / macOS / cx compile gets no heads-up
> approaching ANY ceiling (this is why thoth's codebuf warning only showed on x86).
> Confirmed 2026-07-10: 6 warning lines in each of main.cyr/main_win.cyr, 0 in the
> other five.

- **Extract the block into ONE shared helper** (`_capacity_warnings(S)` in
  `src/common/util.cyr`, next to `_codebuf_grow`) and call it from every driver's
  end-of-compile path — closes the aarch64/macho/cx gap **and** de-duplicates the
  inline copy in main.cyr + main_win.cyr in one move.
- **Logic-preserving**: thresholds/text don't change, so cycc must stay
  **byte-identical** self-host + seed-derive + cross-OS (ecb/cass/pi); the only new
  behavior is the SAME warnings now firing on the 5 previously-silent drivers. Prove
  with the byte-identical self-host + differential-corpus recipe (refresh stale
  includes first).
- **Watch**: each driver's end-of-compile call site differs — wire carefully. The **cx**
  driver reports against its own **fixed 512 KiB** region (`0x54A000`), NOT the growable
  codebuf, so the codebuf line needs a cx-specific cap (524288) or omission. Keep the
  helper fork-agnostic — read every metric via its accessor (`GSPOS`/`GCP`/…), no
  hardcoded `S+offset`.

### Pin 4 — v6.4.51 reactive consumer-filed fixes — **✅ SHIPPED v6.4.51 + .52 carryover SHIPPED v6.4.52**

> **✅ .52 CARRYOVER SHIPPED v6.4.52** — the dedicated macOS + Windows large-single-allocation
> path landed: `alloc()` serves a >remaining-reserve request with a dedicated unhinted
> `mmap(0,size)` (macOS, overcommit; replaces the hint-grow loop macOS ignored) / dedicated
> `VirtualAlloc` (Windows, eager `MEM_COMMIT`), so `output_buf` is now **1 GiB on ALL platforms**
> (the .51 16 MiB macOS/Windows fallback is gone; a guard hard-errors on true OOM). **Verified on
> real ecb + cass** via `vr01_alloc_1gib` (alloc 1 GiB + touch both ends); cross-OS
> `SELFHOST_OK`+`LIBTEST_OK (22)`. Also, more broadly, unblocks any consumer needing a >256 MiB
> buffer on those OSes. See CHANGELOG [6.4.52].


> **✅ SHIPPED v6.4.51** (2026-07-11) — THREE items (the user added the error-enum lint
> gate at cut time): (1) `signal_ignore(SIGPIPE)` + `Signal` enum + the macOS ESYSXLAT
> `rt_sigaction 134/13→BSD sigaction 46` translation — **verified on real ecb (macOS)**
> via `vr01_signal_ignore` (socketpair SIGPIPE → EPIPE, not process-kill); (2) `output_buf`
> 16 MiB→1 GiB **on Linux** (off-heap `_output_base`; a 19.8 MiB binary compiles) — macOS
> and Windows fall back to the fixed 16 MiB region because their allocators can't produce a
> >256 MiB single region, **carried to v6.4.52** as the dedicated large-alloc path
> ([`issues/archived/2026-07-11-macos-windows-large-single-allocation-path.md`](issues/archived/2026-07-11-macos-windows-large-single-allocation-path.md));
> (3) the `lint_error_enum_namespace` cyrlint note rule (bare `ERR_*` reserved for sakshi).
> cross-OS pi+ecb+cass all `SELFHOST_OK`+`LIBTEST_OK (21)`; check.sh 141; seed-derive OK.
> See CHANGELOG [6.4.51]. Original filing detail below.
>
> Two consumer filings surfaced 2026-07-11 (during the 6.4.50 sandhi fold + thoth
> work); **user pinned BOTH to 6.4.51** (2026-07-11). Neither blocks the 6.4.50 tag.
> Both are cross-OS-affecting, so they share one cross-OS gate run if bundled.

1. **`signal_ignore` / SIGPIPE stdlib gap** —
   [`issues/archived/2026-07-11-sandhi-signal-ignore-stdlib-gap.md`](issues/archived/2026-07-11-sandhi-signal-ignore-stdlib-gap.md).
   `lib/syscalls.cyr` has no `signal_ignore`/`rt_sigaction` and no `SIGPIPE` in the
   `Signal` enum; `lib/net.cyr` `sock_send` is a flagsless `sys_write` (no
   `MSG_NOSIGNAL`) — so any server on `sock_send` dies on SIGPIPE when a peer
   disconnects mid-response (**macOS = High: unauthenticated server DoS, no consumer
   workaround**; sandhi 1.8.x carries a Linux-only raw `rt_sigaction` workaround).
   Premise-checked absent in live lib/ (grep = 0). **Acceptance:** portable
   `signal_ignore(signum)` (Linux `rt_sigaction` x86 13 / aarch64 134; macOS BSD
   `sigaction` + the missing `ESYSXLAT` entry; agnos no-op) + `SIGPIPE`=13 in the
   `Signal` enum; sandhi drops its raw-syscall workaround. New public lib fn → trips
   the 3 stdlib-hygiene gates (lint / api-surface / cyrdoc); **verify on real ecb
   (macOS)** since macOS is the whole point.
2. **`output_buf` 16 MiB → 1024 MiB cap raise** —
   [`issues/archived/2026-07-11-output-buf-16mib-cap-blocks-large-test-binaries.md`](issues/archived/2026-07-11-output-buf-16mib-cap-blocks-large-test-binaries.md).
   The final-image `output_buf` is a **fixed 16 MiB** region (NOT growable, unlike the
   codebuf); `_check_output_cap` ([`runtime.cyr:348`](../../src/backend/common/runtime.cyr))
   hardcodes `16777216`. thoth's single-translation-unit test binary hit it
   (16,781,048 B — 3,832 over). **Acceptance:** raise the two `16777216` literals in
   `_check_output_cap` → `1073741824`, enlarge the `output_buf [16777216]→[1073741824]`
   region (lazy-mapped, like `vsgn_base`), and shift the downstream heap regions / `brk`
   top in **all 5 per-target maps** (`main.cyr`, `main_aarch64_native`,
   `main_aarch64_macho`, `main_x86_macho`, `main_win`) — the coordinated relocation done
   for the 2 MB→16 MB bump at v6.1.27. **HEAP-LAYOUT change → two-step bootstrap +
   cross-OS (ecb/cass/pi).**

---

## Deferral backlog — pinned order (triaged 2026-07-11 @ v6.4.52)

A full sweep of open `issues/` + `proposals/` after the .50–.52 run. **12 open issues + 3
open proposals** remained @v6.4.52; **live at the v6.4.82 closeout re-triage: 11 open
issues + 3 open proposals** (273 archived) — counted against `docs/development/issues/`
itself, not against this file's prior claim, which had drifted (it read "9" from a
2026-07-23 sweep that .73–.82 then overtook). **4 were resolved/shipped and archived in the
.50–.52 pass** — drishti
`>>>` shift (→ .46), EFI enrollment (→ .48), and the UEFI-signing + cx-CLI proposals
(shipped .47/.48 and .17–.22). Order set by the maintainer (2026-07-11).

> **PLACEMENT RULE (hard):** every technical / codegen / runtime item lives in the **6.x
> line** or the **potential backlog** below — **NOTHING codegen-related is EVER pushed to
> 7.x**. 7.x is **language book + legal-for-public-release ONLY**. An item without a
> committed slot goes in the potential backlog (still 6.x-cycle work), not a far-future
> version.

### 6.4.x tail — pinned order

Arc **finish-out** items deferred *during* the SIMD + cx arcs run **FIRST** — they were
done work that got left behind, so they clear soonest. The **function-visibility** arc runs
**LAST** (one of the final arcs of the minor), so the issue queue is clean before it. The
**Intel-Mac** platform revival is scoped **before** function-visibility — it's been lingering
and is the trickiest to bring back, so it gets a hard look ahead of the big arc.

| # | Slot | Absorbs | Sev |
|:-:|---|---|:-:|
| 1 | **SIMD + cx arc finish-out ✅ COMPLETE** — deferred finish-out of the Pin-1 SIMD arc + the cx portable arc. **SIMD half ✅ v6.4.53**: dup-arg `f(v,v)` correctness BUG (tail-call int-reg marshal → normal XMM/q-reg path, all targets) + i64v2 packed multiply (x86/PE pmuludq · NEON extract-mul-insert · cx native). **cx half ✅ v6.4.54**: value-form SIMD params/returns (GP register-pair transport) + the "var-capture" bug — which root-caused to **cx code-stream misalignment** (3-byte x86 DCE stub on a 4-byte VM) + a **triply-broken forward-call resolver** (stale table / byte units / opcode clobber) that had silently corrupted ~⅔ of cx programs (49→99/221 corpus). Both filed issues were misdiagnosed; found by bytecode-level investigation. Follow-ons filed: cx fmt_int/large-immediate, naked-asm realign, retire-stale-0xE92000-table — **all three ✅ v6.4.58** (the "fmt_int digit-shift" was really a broken cx `%`; large-immediate = the missing bits-48-63 movhk chunk), batched with the v6.4.57 Windows atomic-write residuals (O_EXCL→CREATE_NEW + DeleteFileW). | ~~`…valueform-simd-duplicate-arg-x86`~~ ✅ .53, ~~`…i64v2-valueform-packed-multiply`~~ ✅ .53, ~~`…cx-valueform-simd-params-returns`~~ ✅ .54, ~~`…cx-var-capture-after-global-mutation`~~ ✅ .54, ~~cx-fmt-int/large-immediate · naked-asm-realign · retire-0xE92000 · windows-atomic-residuals~~ ✅ .58 | P2 |
| 2 | **Scalar-float completion ✅ COMPLETE** (cyrius-side; agnos XMM-state kernel layer is agnos-side + separate). **f64 scalar RETURN in xmm0 ✅ v6.4.55** (sentinel -9; EMOVQ rax↔xmm0 marshal, no-op on aarch64/cx; §1 closed). **f32 scalar arithmetic + comparison + stricter float typecheck ✅ v6.4.56** (EMIT_F32_BINOP/EF32_CMP on x86/PE/macho·aarch64 NEON·cx widen-op-narrow; warn-level f64/int arithmetic-mix + 2 SESTYPE-normalization bug-fixes). Follow-ons filed: scalar-float param arithmetic + compound-assign, ERR_MSG len over-read, f64/int compare-mix warning (needs literal-0 suppression) | ~~`…agnos-fp-xmm-state-and-f64-scalar-return` §1~~ ✅ .55; `…scalar-float-param-and-compound-assign` (P2), `…parse-fn-retmsg-length-overread` (P3), `…f64-compare-mix-warning-literal-suppression` (P3) | P2 |
| 3 | **Intel-Mac (x86_64 Mach-O) toolchain revival ✅ COMPLETE v6.4.59** — the compiler self-hosted on ach since v6.0.43; this closed the ungated usable-toolchain tail: wrapper arch-default + env(HOME) via r15, cycc `_read_env` un-stub, retire the vestigial `_macho_capture_args`, `_lint_macho_buf` (the Mach-O structural lint bite), `release.yml`→`build-macos-x86-tarball.sh`, and **the systemic fix — `ach` added to `release-gate.sh` + a real install gate**. Verified on real ach; full gate GREEN ecb+ach+cass+pi. | ~~`2026-06-02-macos-x86-release-no-compiler`~~ ✅ .59 (High, open 13mo), ~~`2026-07-07-macho-structural-lint-residual`~~ ✅ .59 | P1 |
| 4 | **DX diagnostics ✅ COMPLETE** — R1 (v6.4.60) column + source-excerpt with a caret on every error; **R2 (v6.4.62) panic-mode multi-error** — cycc reports many errors/compile, no output on error, and NEVER hangs/crashes on hostile stdin (a `PEEKT` anti-hang watchdog broke the fuzz wall that stopped 2 prior attempts; VR-02 `CYCC_FUZZ_ITERS=300` = 0 crashes). Follow-up (non-blocking): convert the 25 inline `SYS_EXIT` errors + a smarter `_sync_skip`. | ~~column/source-excerpt~~ ✅ .60, ~~multi-error recovery core~~ ✅ .62; `2026-07-12-dx-multi-error-reporting` (inline follow-up, P3) | P2 |
| 5 | ~~**Function/var visibility (`public`/`private`)**~~ — **MOVED OUT of 6.4.x to the v6.5.0 OPENER (user, 2026-07-22); design COMMITTED** (file-scoped `private` opt-in, per-item `public`, default public; `_`-prefix LATER). Re-homed in the **v6.5.x table below**. | proposal `2026-07-02-function-visibility-pub-private` (authoritative) | — |

**Fold-in (no dedicated slot):** `2026-06-25-source-level-version-constant` (P3 — build
tooling) rides a convenient minor-cut, per the "cosmetic/tooling fixes fold into adjacent
work" rule.

### v6.5.x — Performance-Quality minor (anchors already framed in roadmap_6.md)

> **v6.5.0 OPENS with `public`/`private` visibility** — moved out of 6.4.x on 2026-07-22 with the
> design COMMITTED. It is the minor's FIRST arc, ahead of the perf work; the perf anchor (IR
> substrate) follows it. Same call is recorded in roadmap_6.md and the proposal.

| Slot | Open issues it absorbs |
|---|---|
| **`public`/`private` visibility — the v6.5.0 OPENER** (~4–6 releases). **Committed design:** a top-level `private` declaration flips that FILE to private-by-default (**`fn` *and* `var`**); a per-item `public` moniker re-exposes; **no declaration = today's everything-public**, so the whole ecosystem keeps compiling unchanged on day one and adoption is a per-file decision. The **`_`-prefix convention is explicitly LATER** — nothing is derived from names, which is what retires the 165-cross-file-`_`-call audit as a blocker. The real work is the per-fn **origin-file-id substrate** (`lex_pp.cyr` stamps a file-id, `_fnt_fileid[fi]` across the forks), not the flag or the check; enforcement sits at `PARSE_FNCALL` after `FINDFN` **plus the tail-call path**. Authoritative: [`proposals/2026-07-02-function-visibility-pub-private.md`](proposals/2026-07-02-function-visibility-pub-private.md) | folds `bare-metal-forbidden-module-check` (the `#`-annotation slot) |
| **IR substrate productionization** — the perf anchor; gates the whole perf/regalloc arc | `2026-07-02-ir-regalloc-rewrite-needs-reemit` (P2, L); **`2026-07-02-ir3-fixpoint-cascade-overelimination`** (`CYRIUS_IR=3` correctness — BOUNDED fixable bugs, not a substrate redesign; the perf arc is blocked on this landing here); folds `2026-07-07-v6415-closeout-residuals` (D1/D2 dead IR/decode; its R2 PE prologue already ✅ v6.4.26) + the `_cur_fn_ret_stash` disp↔idx substrate (state.md "Filed follow-on") |
| **Stackless coroutines / mid-body suspend-resume across `await`** — ▲ **PINNED v6.5.x** (user, 2026-07-26). Bound to the IR substrate above: the poll-runtime rework (+ force-once memoization) is the *same* substrate the perf minor opens, so doing it earlier would build that substrate twice. Subsumes the mid-body-suspend "gap 6" of the shipped async "W" arc (v6.3.11 shipped async/await as deferred-then-forced Futures over a run-to-completion epoll runtime, explicitly NOT stackless CPS). | `2026-07-25-stiva-stackless-coroutines-interactive-exec` — **left OPEN deliberately: it is the acceptance record for this pinned arc**, and archiving it would hide the consumer requirement from whoever opens the slot |
| **SIMD register residency** — IR-substrate-gated; a codegen-QUALITY gap (bit-identical, no wrong results), so it can't batch ahead of the substrate | `2026-07-06-simd-f64v-memory-operand-no-register-residency` (P2, L) |
| **macOS-arm64 threading backend** — `lib/thread_macos.cyr` (bsdthread/`__ulock`), mirrors the thread_win split; **distinct from the Intel-Mac x86 tail** and has no consumer blocked yet | `2026-07-03-macos-threading-workers-dont-run` (P2, M) |
| **Missing syscall wrappers — one pass** covering `lchown`/`fchown`/`fchownat` semantics **plus `sys_chdir`** (called at `lib/regression.cyr:658` and defined nowhere). Medium for the stdlib, **High for any consumer that works around it**: a hardcoded `syscall(94, …)` is `lchown` on x86_64 but **`exit_group` on aarch64**, so the workaround silently terminates the process — the same class the v6.4.82 `#94`/`#95` agnos wrappers were added to prevent. Gate with a `vr01_`-named `.tcyr` so the cross-OS leg actually runs it on pi. | `2026-07-26-no-lchown-wrapper-forces-a-hardcoded-x86-64-syscall-number` |

### v6.6.x — Language-Ergonomics minor

- **const-eval / comptime** — proposal `2026-07-05-const-eval-comptime` (P3, L; already homed here).

### Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot yet; pulled into a release the moment a consumer
or priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **Async single-waiter-per-fd multiplex** — `_async_wait_events` uses the epoll `data` slot AS
  the waiter identity, so two tasks parking the SAME fd hit `EPOLL_CTL_ADD` `EEXIST` and one
  starves; needs a real per-fd waiter list. No consumer exercises concurrent same-fd waiters
  today. (**Stackless coroutines / mid-body suspend used to share this bullet — it is no longer
  unscheduled: ▲ PINNED v6.5.x, see the v6.5.x table above.**)
- **DWARF debug-info emission** — **moved here from the "v7-parked" list at the v6.4.82 closeout.**
  It emits debug sections into the object file, i.e. it is backend/codegen work, and the placement
  rule is absolute: nothing that compiles code is ever parked to 7.x. Unscheduled 6.x-line work —
  slot it when a real debugger story is needed. (Distinct from the DX diagnostics arc, which shipped
  at .60/.62 and was only the error-reporting layer.)
- **Incremental compilation** — **also moved here from the "v7-parked" list at the v6.4.82
  closeout** (same reason: it is compiler work). Unpin condition per
  [roadmap-future.md](roadmap-future.md): reconsider when cycc self-host crosses ~2 s — it is
  **~622 ms at v6.4.82**, so the whole-program model is nowhere near the threshold. The v6.5.x
  perf-quality minor and the v6.7/v6.8 RISC-V arcs report first.
- **`tantu` runtime extraction** — the async runtime lib → its own repo (repo name reserved;
  a future-**minor** deliverable, still 6.x).

### 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here** — if it compiles code, it's 6.x.

> **Enforcement note (v6.4.82 closeout):** this file was itself violating the rule two sections
> down, parking **DWARF debug-info** and **incremental compilation** at "v7-PARKED". Both are
> compiler work and have been moved into the potential backlog above. A technical item with no
> committed slot goes in the 6.x backlog, never a far-future major — the far-future label is how
> real work stops being scheduled.

---

## Order-committed (length-blocked, not yet pinned)

### 3 — UEFI Secure Boot signing — **✅ COMPLETE (signing v6.4.47 + enrollment v6.4.48)** · NOT a release-blocker

> **✅ v6.4.47 — `cyrius sign-efi` (A) shipped.** A separate `cyrsign-efi` helper (the 14 MB
> crypto stays out of the CLI) wraps sigil's `authenticode_pe_sign`; `cyrius sign-efi` dispatches
> to it. De-risked against a real gnoboot `BOOTX64.EFI`: independent PE-hash recompute + RSA
> verify confirm a real UEFI would accept it (thin-glue, no PE-layout repair tail). Gate:
> `scripts/sign-efi-gate.sh`. **✅ Residual (B) SHIPPED v6.4.48:** `EFI_SIGNATURE_LIST`
> `.esl`/`.auth` enrollment generation (`efi_signature_list_from_cert`/`efi_auth_from_esl`/
> `efi_time`, via folded sigil 3.11.1's `efi_sigdb`) — the PK/KEK/db keychain setup, distinct
> from signing. The whole arc is now COMPLETE. Original framing below (kept for context):

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

### 4 — Function/var visibility (`public`/`private`) — **MOVED to the v6.5.0 OPENER (2026-07-22)** · ~4–6 releases · NOT a release-blocker

**Design COMMITTED (user, 2026-07-22).** Authoritative:
[`proposals/2026-07-02-function-visibility-pub-private.md`](proposals/2026-07-02-function-visibility-pub-private.md).
Sequenced as the v6.5.0 opener — see the v6.5.x slot table above. Still executes
"Phase 2 — `pub` enforcement" of [`module-manifest-design.md`](module-manifest-design.md),
closing the flat-global-namespace bug classes (the `dynlib_*` dead-code corruption,
enum-shadow, slot-collision) and making the api-surface snapshot compiler-enforced.

- **The committed model — file-scoped opt-in, default public:**
  1. a top-level **`private`** declaration in a source file flips that **FILE** to
     private-by-default — every `fn` **and `var`** in it becomes file-private;
  2. inside such a file a per-item **`public`** moniker re-exposes;
  3. **no declaration = today's behaviour, everything public** (unless an item is
     individually declared private);
  4. the **`_`-prefix convention is explicitly LATER** — it may return as a convenience for
     declaring additional items, but **nothing derives from names in this arc**.
  Spelling of the file-level declaration (a `#private`-style directive vs a keyword) is an
  implementation pick, not a design question; note `pub` is already lexer token 73 but **dead**
  (consumed-and-ignored at `parse_fn.cyr:1570`), as is `shared`.
- **Why this replaced the earlier framing (kept because it has re-contradicted itself before).**
  This section used to force a **HYBRID marker** — `_`-prefix default plus a `pub`/`private`
  override — because the arc-open audit found **165 distinct `_`-fns called cross-file** (253
  pairs; sigil alone has 703 `_`-defs), which disproved "derive-from-`_` = zero-churn". The
  committed design **sidesteps that entirely**: nothing is derived from `_`, so the audit result
  **stops being a blocker** rather than forcing a hybrid, and because it is opt-in per file the
  whole ecosystem keeps compiling unchanged on day one. **If you find derive-from-`_` or
  "hybrid" framing anywhere else, it is stale — the proposal wins.**
- **Phases**: (0) lock the declaration spelling → (1) the **per-fn origin-file-id substrate**
  (`lex_pp.cyr` stamps a file-id per included file, `_fnt_fileid` across the `main_*` forks —
  **this is the real work of the arc**, and it is byte-identical) → (2) `fn_flags` **bit 6**
  (bits 0–5 used, 6–63 free) + WARN-mode enforce → (3) per-file adoption where it pays, cyrius
  first → (4) flip to hard-error + feed DCE (file-private with no in-file caller is
  *definitively* dead) + prove the win → (5) docs/close.
- **Risks**: a mis-stamped file-id → silent false-positive rejections; late-ABI repair tail
  (file-id × monomorph instances, use-aliases, `GMOD` mangling — note `GMOD`/`SMOD` is name
  **mangling**, not a scoping boundary); **two enforcement sites** — `PARSE_FNCALL` right after
  `FINDFN`, *and* the tail-call path (`parse_fn.cyr:~381`) — easy to miss one. The
  cross-ecosystem migration risk is much reduced versus the superseded model, since day-one
  behaviour is unchanged and adoption is per-file.

### T — Intel-Mac (x86_64 Mach-O) usable-toolchain tail — **✅ COMPLETE (v6.4.59)** · NOT a blocker

Ran at the **v6.4.x tail** (moved 2026-07-03). Phase 1 (argv prologue) shipped
v6.1.30; the remaining `ach`-gated layers all landed at **v6.4.59** (Intel-Mac
x86_64 Mach-O revival): wrapper arch/env (`HOME` via r15, macOS arch-default),
cycc `_read_env` un-stub, `_lint_macho_buf` structural lint, x86 release tarball
in release.yml, and **`ach` added to the release gate** as a first-class host —
closing the 13-month "macOS x86 release, no compiler" issue. The toolchain
self-hosts on real `ach`.
[`issues/archived/2026-06-02-macos-x86-release-no-compiler.md`](issues/archived/2026-06-02-macos-x86-release-no-compiler.md).

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

> Re-reconciled at the **v6.4.82 closeout**: all **11** open issues have a roadmap home and
> each carries a matching `**Placement:**` line in its own file (the 2026-07-23 reconciliation
> predates the .73–.82 run, which both cleared and added filings). Release ORDER within each
> bucket is the user's to set; severity is the sort hint.

- **🔴 Correctness bugs — near-term patch slots:**
  - ~~**P1 struct-field-name-offset collision**~~ — ✅ **SHIPPED v6.4.24.** Root cause was NOT
    the filed two-struct collision (nor a buffer overflow): the `X.Y` disambiguation loaded
    a global var whenever the FIELD name was a global var, ignoring base X. Fix: if X is a
    known var, `X.Y` is a field access ([`issues/2026-07-07-struct-field-name-offset-collision.md`](issues/archived/2026-07-07-struct-field-name-offset-collision.md)).
  - ~~**P2 signed sub-i64 GLOBAL scalar sign-extension**~~ — ✅ **SHIPPED v6.4.23** (new 8th
    per-var `_vsgn_base` table, max-sized/no-grow to keep the cybs seed-chain intact; x86 +
    aarch64 backends).
  - ~~**SIMD intrinsic shadows a var name**~~ — ✅ **SHIPPED v6.4.77** (archived). The filing named
    3 intrinsics; the real surface was **67 reserved tokens** reporting `got unknown`, fixed via
    `TOKNAME_BUILTIN` with `IS_KEYWORD_TOK` deriving from it
    ([`iv-simd-intrinsic-shadows-var-name`](issues/archived/2026-07-17-iv-simd-intrinsic-shadows-var-name.md)).
    The names are still reserved by design — they now name themselves in the diagnostic.
- **🟠 Consumer-blocked (near-term):**
  - ~~**P2 LEXID dedup cap** (16384)~~ — ✅ **SHIPPED v6.4.21** (raised to 65536; `lexid_entries`
    relocated to arena-top + all forks' arenas extended). Unblocks the stiva port.
  - ~~**thread-local slot allocator + sandhi OOB**~~ — ✅ **SHIPPED v6.4.65**
    (`thread_local_alloc()` based at 16, `TLOCAL_MAX_SLOTS` 16→128; sigil 3.12.1/patra 1.12.12
    migrated — sandhi does not use this namespace):
    [`thread-local-slot-namespace`](issues/archived/2026-07-01-thread-local-slot-namespace-no-allocator.md)
    + [`sandhi-rpc-policy-tls-slot-oob`](issues/archived/2026-07-01-sandhi-rpc-policy-tls-slot-oob.md).
  - cyim regex unblock (lands when cyim re-tests against v6.x).
- **🟡 Deferred prerequisites (land WHEN their arc opens):**
  - ~~`tls13-server-get-version-zero`~~ — ✅ **SHIPPED v6.4.21** (server `respond_hello` stores the negotiated 1.3 version).
  - `bare-metal-forbidden-module-check` → folds into the `#`-annotation slot of the
    `public`/`private` visibility arc — now the **v6.5.0 opener**, not a 6.4.x arc.
  - `macho-structural-lint-residual` → Intel-Mac tail (slot T).
  - `sigil-authenticode-pe-hash-oob-read` → UEFI Secure Boot arc (slot 3).
  - ~~`capturing-closures-windows-pe`~~ — ✅ **SHIPPED v6.4.26** (route through `ECALLPTR_PE`;
    guard removed; verified wine + cass).
  - `v6415-closeout-residuals` — **R2 (PE prologue) ✅ SHIPPED v6.4.26** (`_pe_fd_to_handle_rcx`
    extracted; cass-verified). D1/D2 (dead IR/decode) REMAIN → v6.5.x IR substrate.
  - ~~`windows-pe-surface-no-terminateprocess`~~ — ✅ **SHIPPED v6.4.26** (0xF01D TerminateProcess
    + `_win_terminate`/`_win_wait_timeout`; unblocks thoth's Windows timeout-kill).
- **🟢 SIMD polish (standalone; Pin 1 is closed, these are follow-ons not blockers):**
  ~~`i64v2-valueform-packed-multiply`~~ ✅ **SHIPPED v6.4.53**, ~~the x86/aarch64 `f(v,v)` dup-arg
  bug~~ ✅ **SHIPPED v6.4.53** (both archived); ~~cx value-form SIMD params/returns~~
  ✅ **SHIPPED v6.4.54** (`issues/archived/2026-07-09-cx-valueform-simd-params-returns.md`); still
  open: SIMD register-residency
  (`issues/2026-07-06-simd-f64v-memory-operand-no-register-residency.md`, a v6.5.x IR-substrate item).
  - ~~`aarch64-f64-exp2-atan-hard-error`~~ — ✅ **SHIPPED v6.4.25** (polyfill-dispatch +
    `_f64_exp2_polyfill`/`_f64_atan_polyfill`). Unblocked `ganita` inverse-trig →
    [`aarch64-ganita-inverse-trig-unguard`](issues/archived/2026-07-08-aarch64-ganita-inverse-trig-unguard.md) (open follow-on).
  - ~~`aarch64-trig-payne-hanek-range-reduction`~~ — ✅ **SHIPPED v6.4.25** (double-double
    dd reduction for |x| ≥ 8192; small-angle path byte-identical).
- **🔧 Tooling / gate hardening (fold into an adjacent slot):**
  - release-gate's cross-OS self-host step runs only the `vr01_` glob, not the full corpus, on
    the remote hosts
    ([`release-gate-cross-os-runs-only-vr01-glob`](issues/2026-07-14-release-gate-cross-os-runs-only-vr01-glob.md)).
  - `cyrius distlib` has **no all-profiles mode** — it regenerates one bundle per invocation, so a
    multi-profile repo ships stale sub-bundles under a fresh version string (the .79 sankoch cut left
    all nine sub-profiles carrying the buggy encoder; 36 sub-profiles across 6 repos are exposed, and
    both hand-rolled CI loops have already drifted from their manifests)
    ([`distlib-has-no-all-profiles-mode`](issues/2026-07-26-distlib-has-no-all-profiles-mode.md)).
  - the `dx-multi-error-reporting` inline follow-up (convert the 25 remaining inline `SYS_EXIT`
    errors + a smarter `_sync_skip`) — P3, rides an adjacent slot
    ([`dx-multi-error-reporting`](issues/2026-07-12-dx-multi-error-reporting.md)).
- **📚 Stdlib backlog (6.x line, unpinned):** `lib/fs.cyr` `dir_list` allocates its whole working set
  per call (`vec_new` + `alloc(4096)` + per-entry `str_from_buf`), with no caller-owned-buffer
  variant — the last unbounded path in a long-running consumer; `dir_list_full` / `dir_walk` /
  `find_files` / the `_with_prunes` pair share the shape
  ([`agora-fs-dir-list-per-call-alloc`](issues/2026-07-26-agora-fs-dir-list-per-call-alloc.md)).
- **Downstream-repo (their timeline):** ~~`yukti-udev-src-len-undersized-array-local`~~ —
  ✅ **SHIPPED v6.4.27** (fixed upstream, released as yukti 2.2.9, re-vendored).
- **v5.x-era substrate (v6.5.x):** `ir-regalloc-rewrite-needs-reemit` (perf passes) +
  `ir3-fixpoint-cascade-overelimination` (`CYRIUS_IR=3` correctness — BOUNDED fixable bugs, not a
  redesign) — **both now named in this file's v6.5.x "IR substrate productionization" row**, as well
  as in the v6.5.x Performance-Quality entry in [roadmap_6.md](roadmap_6.md).
- **7.x — language book + legal ONLY (NOT near-term)** — LEGAL-01 licensing
  (`unreviewed-dimensions`), stdlib-reference docs, the public-release decision. These stay in
  [roadmap-future.md](roadmap-future.md). **Corrected at the v6.4.82 closeout: DWARF debug-info
  and incremental compilation were listed here and are NOT 7.x items** — both are compiler /
  backend work, so per the placement rule above they moved to the *Potential backlog — 6.x-cycle,
  unscheduled* section. (**Diagnostics** was pulled INTO v6.4.x at the 2026-07-07 horizon session
  and SHIPPED at .60/.62; DWARF was never part of that arc.)

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
