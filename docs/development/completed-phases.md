# Completed Phases

Historical record of all completed development phases.
For current work, see [roadmap.md](roadmap.md).
For detailed changes, see [CHANGELOG.md](../../CHANGELOG.md) (source of truth).

---

## Phase 0 — Fork & Understand
Forked rust-lang/rust, built rustc from source, mapped cargo registry codepaths.

## Phase 1 — Registry Sovereignty
Ark as default registry, git/path deps first-class, publish validation relaxed. ADR-001 documented.

## Phase 2 — Assembly Foundation
Seven-stage chain: seed → stage1a → 1b → 1c → 1d → 1e (63 tests) → cyrc (16384 tokens, 256 fns).

## Phase 3 — Self-Hosting Bootstrap
asm.cyr (1110 lines, 43 mnemonics), bootstrap closure, 29KB committed binary. Zero external dependencies. Byte-exact reproducibility.

## Phase 4 — Language Extensions
cc2 modular compiler (7 modules, 182 functions). Structs, pointers, >6 params, load/store 16/32/64, include, inline asm, elif, break/continue, for loops, &&/||, typed pointers, nested structs, global initializers.

## Phase 5 — Prove the Language
46 programs, 157 tests. 10-233x smaller than GNU. wc 2.4x faster.

## Phase 6 — Kernel Prerequisites
All 9 items: typed pointers, nested structs, global inits, for loops, inline asm (18 mnemonics), bare metal ELF, ISR pattern, bitfields, linker control.

## Phase 7 — Kernel (x86_64)
58KB kernel (hardened to 62KB in Phase 10): multiboot1 boot, 32-to-64 shim, serial, GDT, IDT, PIC, PIT timer, keyboard, page tables (16MB), PMM (bitmap), VMM, process table, syscalls.

## Phase 8 — Language Foundations (Tier 1)
7/8 complete: type enforcement (warnings), enums, switch/match, heap allocator, function pointers (&fn_name), argc/argv, String type. Block scoping deferred.
Standard library: 8 libs (string, alloc, str, vec, io, fmt, args, fnptr) — 53 functions.
Comparison-in-args fix: `PARSE_CMP_EXPR` + `setCC` codegen.
`assert.cyr` test framework library.

## Phase 9 — Multi-Architecture (aarch64) — Partial
Done: codegen factored into backends, aarch64 emit (61 fns), cross-compiler builds.
Remaining: instruction correctness, self-hosting on ARM, kernel port, cross-compilation.

## Phase 10 — Audit, Refactor, Stabilize — Partial
Done: kernel audit (23 issues fixed), compiler hardening (fixup + token guards), 17 new edge case tests.
Deferred: error message line numbers, performance pass, block scoping.

## Phase 11 — Prove at Scale (Crate Rewrites)
5 AGNOS crate rewrites in Cyrius:
- **agnostik** — 6 modules (error, types, security, agent, audit, config), 54 tests
- **agnosys** — syscall bindings (50 numbers, 20+ wrappers, sigset, epoll, timerfd)
- **kybernet** — 7 modules (console, signals, reaper, privdrop, mount, cgroup, eventloop), 38 tests
- **nous** — dependency resolver (marketplace + system), 26 tests
- **ark** — package manager CLI (44KB, 8 commands)
- **cyrb** — build tool (29KB, compile/test/self-host)
- Benchmarks and documentation updated
---

## v6.x minors — per-minor summary

Added 2026-07-29, when `roadmap_6.md` was re-scoped to forward-only (v6.6.x+) and its
per-minor narrative for v6.0.x–v6.4.x was removed. That narrative duplicated
[`CHANGELOG.md`](../../CHANGELOG.md), which stays the per-patch source of truth; this is the
one-line-per-minor retrospective index. Close numbers verified against the CHANGELOG's
per-minor max heading, not carried over from the deleted text.

| Minor | Theme | Closed at | Notes |
|---|---|---|---|
| **v6.0.x** | Language cleanup + stdlib + native TLS arc | **v6.0.91** | Opened the cycle (2026-05-19). The `cyrc → cybs` / `cc5 → cycc` rename landed here — the last binary-name change ever paid for. |
| **v6.1.x** | Backend codegen multi-arc | **v6.1.41** | PIE codegen x86→aarch64, `.gnu.hash`, TS/TSX→JS emit, bayan/ganita carve-outs. |
| **v6.2.x** | Platform expansion — bare-metal + dependency model | **v6.2.52** | Bare-metal target formalization, growable heap regions, the modules/module-groupings dependency foundation. **Bare-metal deliverable #4 (forbidden-module check) never shipped** — `CHANGELOG [6.3.4]` says so, and its issue was later archived without a resolution banner. Carried as an open question in [roadmap.md](roadmap.md). |
| **v6.3.x** | Language refinements | **v6.3.45** | Closures with lexical capture, monomorphized generics, async/await syntax, native f64/f32 arithmetic. The opt-in bounds-checked memory mode was *designed* here and never shipped (still 0 hits for `CYRIUS_BOUNDS` in `src/`). |
| **v6.4.x** | Staging minor → long reactive minor | **v6.4.86** | 86 releases. Closeout cut at **.85**; **.86** was the post-closeout sandhi fold. The SIMD compute arc and the other v6.4.x sections below cover it in more detail. |
| **v6.5.x** | Performance quality / generated-code | *active* | See [roadmap.md](roadmap.md). |

---

## v6.4.x — SIMD Compute Arc (all four backends)

The one notable cross-release *arc* of the v6.4.x minor worth a single-glance
summary here (per-release detail is canonical in [`CHANGELOG.md`](../../CHANGELOG.md)).
A SIMD build-out that took cyrius from 128-bit f64 vectors to a complete
packed-SIMD stack — f32/f64/integer 128-bit + 256-bit AVX2 — emitting the
**first VEX/AVX instructions the toolchain has ever produced**, then completing
**Phase 5** so every verb runs on all four backends: x86 (SSE + AVX2), aarch64
NEON, Windows PE (value-form params + returns), and cx bytecode (per-lane scalar
loops). Phase 5 elementwise/dot on all four backends completed at v6.4.32 (all
ARM SIMD XFAILs removed at v6.4.30); the **value-form finish-outs** left mid-arc —
a duplicate-arg tail-call correctness fix on all targets + i64v2 packed multiply —
**closed at v6.4.53**.

- **v6.4.4 — Phase 1: f32v4** (128-bit, 4×f32) — the first f32 SIMD. addps/subps/mulps (`EMIT_F32V_LOOP` = the f64 packed loop minus the 66 prefix). Structured-descriptor sentinel −2121 (reserved band ≤ −2048, decoded by `util.cyr` `_vec_desc`). Builtin tokens 138–140. Full value-form ABI + `.field`-OOB / async-token-collision / param-mask review bugs fixed. `lib/simd.cyr` f32v4 wrappers (value + ptr).
- **v6.4.5 — Phase 2: f32 matmul ops** — `f32v_fmadd` (token 141, mulps+addps) + `f32v_dot` (token 142, two haddps horizontal reduce + `movd eax` 32-bit extract). `bench_f32_gemm` ~27× SIMD-vs-scalar.
- **v6.4.6 — Phase 3a: integer vectors** — i8v16 / i16v8 / i32v4 / i64v2 (+ unsigned `u*`) types + packed `iv_add`/`iv_sub`/`iv_mul` (tokens 143–145; 5th arg = compile-time lane-width literal). Descriptor-driven ABI generalization (`_is_simd128`/`_is_simd256`/`_is_simd_any` in `util.cyr`; signed = descriptor bit 1). Return-type rough-scan SIGSEGV closed for all future vectors.
- **v6.4.7 — Phase 3b: value-form typed integer ops** — `i32v4_add(a,b)` etc. + `iv_dp8` (token 146 — u8·i8→i32 widening int8 dot, the BitNet / b1.58 GEMM inner loop; pmaddubsw/pmaddwd/paddd). Param-mask redesign (class 1 = any 16-byte vector). `bench_i8_gemm` 64³ ~30×. **Integer-SIMD arc CLOSED.**
- **v6.4.8 — Phase 4 R1: f32v8** (256-bit, 8×f32) AVX2 elementwise — the **first VEX/AVX** the toolchain ever emits (2-byte C5 VEX). `EMIT_F32V8_LOOP` (vaddps/vsubps/vmulps ymm). Structured-descriptor sentinel −2153. Tokens 147–149. 256-bit value-return ABI generalized to `_is_simd256`. `simd_has_avx2()` CPUID runtime fallback (leaf 7 EBX bit 5 — AVX2 is NOT x86-64 baseline; wrappers branch AVX2-vs-2×SSE).
- **v6.4.9 — Phase 4 R2: f32v8 FMA + dot** — `f32v8_fma` (token 150, vfmadd231ps — the first 3-byte VEX / C4) + `f32v8_dot` (token 151, 8-lane vextractf128 reduce). `simd_has_fma()` (leaf 1 ECX bit 12 — a different CPUID bit than AVX2). `bench_f32v8_gemm` ~1.48× (256-bit vs 128-bit). **Phase 4 CLOSES — f32 SIMD complete on x86** (f32v4 128-bit + f32v8 256-bit, elementwise + FMA + dot).

**Phase 5 — the remaining three backends (v6.4.28–.32):**
- **v6.4.28 — aarch64 NEON f32v4** (`EMIT_F32V_LOOP`/`FMADD`/`DOT`, mirroring the f64 packed loop: `.2d`→`.4s`, `lsl #3`→`lsl #2`, +2→+4; **fmul+fadd, NOT fused fmla**, to match x86 rounding bit-for-bit; every hand-encoding llvm-mc-verified). Flips the `simd_f32v4` ARM XFAIL.
- **v6.4.29 — f32v8 came free** — the 256-bit wrappers fall through to the 128-bit `EMIT_F32V_LOOP` on ARM (2×128), so the `simd_f32v8` XFAIL was removed with no new emitter.
- **v6.4.30 — aarch64 NEON integer vectors** (`EMIT_IVEC_BINOP` width-dispatched add/sub/mul + `EMIT_IVEC_DP8` uxtl/sxtl+smlal int8 dot). The blocker was actually a *compile* failure (value-form 128-bit vector returns past the STUR/LDUR Q imm9 ±256 range), fixed with the `_EFP_ADDR_X9` fallback. **Removes the LAST SIMD XFAIL — Phase 5 aarch64 COMPLETE.**
- **v6.4.31 — Win64 PE value-form SIMD params + returns** (MS x64 by-pointer copy-in `ESTOREPARM_SIMD_WIN64` + retptr return); `simd_f32v4` 13/13 + `simd_ints` 21/21 on real cass. Also fixed a SIMD-return-convention regression on PE (since v6.4.6) and a regalloc disp↔index off-by-one.
- **v6.4.32 — cx bytecode SIMD codegen** — per-lane scalar loops for every flat-array verb (`_CX_VLOOP_BIN`) + new cxvm opcodes `f32widen` 0x66 / `f32narrow` 0x67 / `fsqrt` 0x68. Fixed two pre-existing cx local-addressing bugs the SIMD stash exposed (`ELOAD_LOCAL_ADDR` return-0 stub → `&local` aliased; scalar load/store disp missed the regalloc reservation `EFLADDR` had). Portable `.cyx` is now a byte-exact SIMD correctness oracle; cross-OS fixture runs SIMD on real hardware.
- **v6.4.53 — value-form SIMD finish-outs** (arc cleanup, deferred mid-Phase-5): the duplicate-arg `f(v,v)` tail-call path had no XMM second pass and returned garbage on ALL targets (the v6.4.31 guard covered only `_TARGET_PE`) — fixed everywhere; plus i64v2 packed multiply, the one integer op the "arc CLOSED" line at v6.4.7 had left unbuilt.

Only caveat: the aarch64 *native* 256-bit f32v8 emitters remain return-0 stubs never reached at runtime — `lib/simd.cyr` routes f32v8 through native f32v4 NEON, so the verb works; native 256-bit stays x86-AVX2-only.

## v6.4.x — other releases

Openers and interim work outside the SIMD arc:

- **v6.4.0** — `CYRIUS_MONOMORPH` default-on flip (generics default-on; `CYRIUS_MONOMORPH=0` opts out).
- **v6.4.1** — `alloc_reset()` zero-on-reset: closes a CVE-class memory-reuse info-leak across all four allocator backends.
- **v6.4.2** — agnos `sys_snd_*` audio syscall band (#64–#69) mirrored into `lib/syscalls_x86_64_agnos.cyr`.
- **v6.4.3** — f64v2/f64v4 value constructors + splat / lane-extract (pre-SIMD-arc surface solidification).
- **v6.4.10** — interim items after the SIMD break point: (1) P1 kernel-blocker fix — a bare top-level `var X[N]` was silently 8× under-sized when declared after the first bare top-level statement (`parse_decl.cyr`; needed a two-step bootstrap since cycc's own arrays were affected); (2) cyrius distlib per-module read cap 256 KB → 1 MB (matching cycc's `input_buf`).
- **v6.4.11–.13** — **array-typed struct fields** (`Vec<T>` fields + `#derive` Vec<primitive>/Vec<struct>) — the Pin 2 arc.
- **v6.4.14** — struct-field-name→offset collision fix (folded f64v2/v4 into the descriptor band; migrate all producers in lockstep).
- **v6.4.15** — absorber-band cleanup (the v6.3.45 closeout-audit backlog: guards + consolidations + DECODE DCE rebaseline).
- **v6.4.16** — aarch64 `f64_sin`/`f64_cos` polyfill (reactive arch-parity repair).
- **v6.4.17–.22** — **cx portable-target arc**: CLI exposure (.17), f64 arith (.18) + compare (.19), cross-OS `.cyx` running on all four hosts (.20), and the cxvm cap/dispatch hardening (.21/.22). A portable `.cyx` doing I/O now runs on Linux, macOS, Windows, and aarch64.
- **v6.4.23** — signed sub-i64 global sign-extension (8th var-family table).
- **v6.4.24** — struct-field-name-offset deep-dive + fix (`parse.cyr` line 501 collision class).
- **v6.4.25** — aarch64 `exp2`/`atan` polyfills + Payne-Hanek trig range reduction (closes the last aarch64 transcendental gaps).
- **v6.4.26** — Windows PE batch: `TerminateProcess` reroute (0xF01D) + capturing closures on PE (`ECALLPTR_PE` push-order) + R2 PE-prologue extract.
- **v6.4.27** — agnos `O_RDWR` flag-map fix + the **folded-stdlib repair campaign** (fixed-at-source + released + re-vendored sakshi 2.4.5 / sigil 3.10.1 / ganita 1.0.3 / yukti 2.2.9).
- **v6.4.33–.45** — **async wrap-up + IOCP-Windows arc** (CLOSED): client/timers/subprocess/combinators/AcceptEx on all hosts; the .42 consolidation also cleared 8 lib bugs + the real-pi-only aarch64 epoll bug (ESYSXLAT `epoll_pwait`↔`pipe` collision + `event.data` offset).
- **v6.4.54** — cx finish-outs: both filed cx bugs were misdiagnosed (code-stream misalignment + forward-call resolver); ~doubled cx correctness.
- **v6.4.55/.56** — **scalar-float arc**: f64 as a fn *return* (.55, xmm0 sentinel) then f32 scalar arith/compare + WARN-only typecheck (.56).
- **v6.4.57** — atomic-write follow-ons: `file_rename` / `write_atomic` / `xfsync` / `create_exclusive` (Windows `MoveFileExW`, macOS BSD `SYS_FSYNC`).
- **v6.4.58** — cx hardening + Windows finish-out: cx `%` fixed for every modulo + 64-bit immediates (cxvm `movhk`); `O_EXCL`→`CREATE_NEW`; `xunlink`→`DeleteFileW`.
- **v6.4.59** — **Intel-Mac x86_64 Mach-O revival**: the compiler self-hosted since v6.0.43 but the *toolchain* had rotted ungated ~2.5 minors; wrapper arch/env + cycc un-stubs + macho linter + ach added to the release gate. Closed a 13-month High issue.
- **v6.4.60–.62** — **DX diagnostics arc**: column + source-excerpt/caret on every error (.60, token byte-offset packed into `tok_lines` high bits); net-sock per-poll leak fix + EOF-hardened skip loops (.61); multi-error panic-mode recovery — many errors/compile, never hangs on hostile stdin, bounded by a `PEEKT` watchdog (.62).
- **v6.4.63** — agnos GPU syscall band openers (#82/#83 = `rename`/`mkdir`) + version-aware lib-freshness skew check in `cbt/` + sigil 3.12.0 / patra 1.12.10 / mabda 4.0.5 fold-in.
- **v6.4.64** — **Win64 stack-args P0**: `ECALLPOPS`' PE branch shuttled stack args through a fixed 5-register table with no path past `nextra==5`, silently corrupting arg 1 for calls with 10+ args (5–9 were fine); mirrored the SysV rsp-relative fix. Gated by `vr01_win64_stack_args.tcyr` on real cass.
- **v6.4.65–.68** — reactive stdlib/agnos band: `thread_local_alloc` (.65), `getpeername` syscall xlat (.66), chrono `DateTime` (.67), agnos `sys_reboot` 4-arg (.68).
- **v6.4.69** — **f64 JSON round-trip**: Grisu2 shortest-float formatter + a correctly-rounded, DoS-safe parser (bayan 1.2.1); `fmt_hex` high-bit fix; `#derive` rewired to the bayan codec.
- **v6.4.70–.72** — agnos GPU syscall band completion (#84–#91; band now contiguous #82–#91) + a placebo agnos-gate repair (.70) + sandhi 1.9.1 `getpeername` fold (.71) + `cyrius coverage` fixed to report project `src/` not vendored stdlib (.72).

> The v6.4.x minor is still **OPEN** (head v6.4.72, held open for reactive agnos
> asks + bug repairs). The bullets above are single-glance hooks; per-release
> detail is canonical in [`CHANGELOG.md`](../../CHANGELOG.md). Full arc write-ups
> land at minor close.

---

## v0.9.x → v5.x — per-version detail

Per-version slot history (every `## [x.y.z]` block) lives in
[`CHANGELOG.md`](../../CHANGELOG.md) — the **source of truth**
for what shipped when.

Durable cycle retrospectives + field-note narratives live in
[`vidya`](https://github.com/MacCracken/vidya) under
`content/cyrius/field_notes/compiler/retros/`:

| Vidya retro | Covers |
|-------------|--------|
| `pre_v3.cyml` | Phase 8 → v2.x (early language + multi-arch foundation) |
| `v3.cyml` | v3.0 → v3.4.x (compiler maturity arc) |
| `v4.cyml` | v4.x (language vocabulary + closeout) |
| `v5_chronicle.cyml` | v5.x release-arc chronology (per-cycle feature lists) |
| `v58x_back_half.cyml` + `v58x_agent_perspective.cyml` | v5.8.x retrospective (longest minor by patch count at the time, 65 patches) |
| `v59x.cyml` | v5.9.x cleanup-and-lib-improvement cycle (43 patches) |
| `v510x.cyml` | v5.10.x typed-simd / REAL TYPE SYSTEM / struct-by-value arcs (50 patches) |
| `v511x.cyml` | v5.11.x close arc (closed; final 5.x minor) |
| `foldin_arc_v57_v59.cyml` | sandhi-pattern fold-in arc spanning v5.7.0–v5.9.0 |

Volatile current-cycle state (current version, cycc size, in-flight
slots, recent shipped patches) lives in
[`state.md`](state.md) — refreshed every release via
`scripts/version-bump.sh`'s post-hook.

This file (`completed-phases.md`) is on a documented phase-out
track — its prior per-version v0.x → v5.9.x narrative
duplicated CHANGELOG entries + vidya retros without unique
value. v5.11.41 trimmed those redundant sections (572 lines
removed); the Phase 0–11 retrospective above stays because
it's the only single-glance summary of cyrius's pre-cycle
foundation arcs and isn't structured the same way in vidya
or CHANGELOG.

When Phase 0-11 itself gets fully captured in vidya (likely
during the v6.x doc reorg), this file can retire entirely.
