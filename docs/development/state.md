# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.
>
> **Consolidated 2026-06-08 (v6.1.4):** the per-patch session-close log
> (104 entries, ~5,600 lines back to v5.x) + the stale v6.0.4-frozen
> structured sections were pruned — that detail is canonical in
> [`CHANGELOG.md`](../../CHANGELOG.md) (per-patch) and
> [`completed-phases.md`](completed-phases.md) (arc retrospective). This file
> now holds only the **active cycle** + current state.

## Current state

| | |
|---|---|
| **Version** | **6.2.43** (v6.2.x cycle — **Platform Expansion**; **stdlib-refold arc close — agnos clock + ERR_* collision namespacing + agnos landmine gates**. Closes the two remaining refold issues: (1) **sakshi 2.4.2** fold — agnos reads `uptime_ms` (#40) directly (was running the x86 TSC path's `syscall(228)`/`syscall(35)` → garbage on agnos); (2) **sigil 3.9.4** (`SIGIL_ERR_*`, 15) + **yukti 2.2.7** (`YUKTI_ERR_*`, 16) — namespaced the bare `ERR_*` (sigil `ERR_IO=6` vs yukti `ERR_IO=14`) collision (patra `SQLT_*`/net `NSYS_*` already done; CHKDUPVAL guardrail shipped .11); (3) native **agnos landmine gates** — `#ifdef CYRIUS_TARGET_AGNOS` fail-closed on `lib/{mmap,dynlib,fdlopen}.cyr` raw Linux syscalls. **lib-only → `src/` untouched → cycc byte-identical 1,073,560 B; check.sh 92/92 + boot; agnos compiles clean (no mis-dispatch); 4-host self-host green (ecb/cass/pi SELFHOST_OK).** cyrius references neither lib's ERR_* directly so the fold is non-breaking here. Closes `2026-06-23-agnos-portability-sweep-residuals` + `2026-06-14-stdlib-constant-value-collisions` → 9 active issues. PRIOR: **6.2.42** sigil 3.9.3 fold — certpin `run_capture` signature fix. First of the stdlib-refold issues the v6.2.41 arity check surfaced: sigil's `certpin_compute_spki_pin` called the obsolete 2-arg `run_capture(cmd,argv)` (vs the 5-arg API) → cert-pin-via-openssl silently broken. Fixed upstream in **sigil 3.9.3** (released + tagged), folded byte-identical into `lib/sigil.cyr`. **lib-only → `src/` untouched → cycc byte-identical 1,073,560 B; check.sh 92/92 + boot; fold compiles arity-clean + cross-compiles PE/aarch64; 4-host self-host green (ecb/cass/pi SELFHOST_OK).** Closes `2026-06-24-sigil-certpin-run-capture-signature-mismatch`; sakshi agnos-clock + ERR_*/SYS_* collision namespacing scoped to v6.2.43. 11 active issues. PRIOR: **6.2.41** silent-correctness hardening — call-site arity check + IEEE-754 NaN comparison fix. Two "compiles clean, wrong result, no diagnostic" bugs fixed together. (1) **Arity check** (roadmap-pinned, tentib M3c `2026-06-23-call-arity-no-check` RESOLVED): non-fatal `warning: 'f' expects N arguments, got M` via a shared `_CHECK_ARITY` helper across all three call-emit paths (normal `PARSE_FNCALL` + `return f(args);` tail-call + inline-replay) — broader than the pinned PARSE_FNCALL-only scope (which alone misses inlined + every `return f()`). Carve-outs: backward-refs-only (`_fnt_offsets>=0`; inline path trusts `pc`), variadics (new `GFVA` getter), syscall/`fncallN` exempt, variant ctors register real arity. Surfaced+fixed in-slot: `ESUBRSP` 2-vs-1 (cycc self-compiles arity-clean) + `cyml.tcyr`/`v5104_inference.tcyr` test bugs. (2) **f64 NaN** (prajna `2026-06-24-f64-le-nan-comparison` RESOLVED): premise-check found it broader than filed — x86 `setb`/`sete`/`setbe`/`setne` ignored the parity/unordered flag, so `f64_lt`/`f64_eq` builtins + `f64_le`/`f64_ge` + `<`/`<=`/`==`/`!=` were all wrong on NaN; `EF64_CMP` now folds `setnp`/`setp` (x86) + `cset le`→`ls` (aarch64). New `float_nan_compare.tcyr` 41/41 on x86 AND real ARM (pi). **codegen+frontend changed → cycc 1,071,936→1,073,560 B; self-hosts byte-identical; check.sh 92/92 + boot; 4-host byte-identical self-host (x86+ecb+cass+pi); bench-history.sh self_compile 505→519 ms (+3.9%; manual median 507 ms, in the 500–549 jitter band; per-call-site arity-check growth-tax, not a regression).** The arity check also surfaced a real (already-broken) sigil certpin `run_capture` 2-vs-5 signature bug → filed `2026-06-24-sigil-certpin-run-capture-signature-mismatch` as a follow-up. Also archived 2 stale-resolved issues (trust-chain CVE-20/21, roadmap-drift) as housekeeping → 12 active issues. See CHANGELOG [6.2.41]; PRIOR: **6.2.40** `cyrius init`+`port` go FULLY native — both bash shims deleted. Completes the half-done v5.9.28 port (which slid the easy path into `programs/cyrius-init.cyr` + punted in-place/flag-matrix/all-of-port back to bash, and wasn't even in `[release].bins`). One native scaffolder serves the whole surface; `scripts/shims/cyrius-{init,port}.sh` `git rm`'d, no fallback. Packed: **sandhi 1.6.13** fold + **`cyrius lib sync` scopes to declared `[deps].stdlib`** (thoth filing RESOLVED; `--full` opt-in + dry-run counter fix) + a **found-by-ports** Apple-Silicon `sys_rename` fix (`AT_FDCWD` is −2 on Darwin, not Linux's −100 — arm64 port-move was a no-op on ecb). **`src/` untouched → cycc byte-identical 1,071,936 B; check.sh 92/92 + boot; `cyrius init`+`port` verified on REAL Darwin arm64 (ecb); api-surface unchanged (init/port are programs + cbt, not lib/src).** See CHANGELOG [6.2.40]; PRIOR: **6.2.39** agnos syscall-peer wrappers + fail-OPEN safety fix. Bottom-priority agnos batch, kernel-verified vs `agnos/kernel/core/syscall.cyr`: net_config #61 (`sys_net_config` + 4 getters; unblocks taar/yo/whirl/dig) + **winsize #60** (`sys_winsize`; agnsh/darshana/kii/desktop) + signal constants/sigset wrappers (`SIGHUP…SIGPWR`, `1<<sig` agnos convention; unblocks thoth/t-ron `--agnos` link). **Plus the sweep's real find:** `result`/`bounds`/`overflow` aborted via unguarded `syscall(60)` → no-op'd on agnos → core safety checks silently **fail-OPEN**; now target-aware guarded. **Gate fix (not feature drop):** #60==Linux-exit number false-positived `_agnos_emit_gate` — fixed by making its emit probe peer-independent (no syscall-peer include) so the compiler EEXIT is the sole `mov eax,60` source. **lib + gate only — `src/` untouched → cycc byte-identical; api-surface 4334→4343 (+9, non-breaking).** See CHANGELOG [6.2.39]) |
| **cycc** (x86_64 ELF) | **1,073,560 B** (+1,624 B @ 6.2.41 — `src/` codegen+frontend changed: `EF64_CMP` parity-flag NaN fix (x86) + the `_CHECK_ARITY` helper wired into 3 call-emit paths + the `GFVA` getter; self-hosts byte-identical fixpoint, seed-derivable from `bootstrap/asm`) |
| **cycc_aarch64** (x86-host cross, emits aarch64) | **624,552 B** (rebuilt @ 6.2.30 version-bump — version-string stamp only; backend untouched; pi SELFHOST_OK) |
| **cycc-native-aarch64** (aarch64-native, tracked) | 787,248 B (refreshed @ 6.1.8 — PIE-enabled; **NOTE: predates the 6.2.10–.32 compiler changes (incl. the .29 aarch64 fixes) — refresh via `cyrius pulsar` when next on ARM hw; not a gate, the pi self-host rebuilds from source (✅ SELFHOST_OK @ .32)**) |
| **cycc_win** (PE32+ cross) | **845,824 B** (rebuilt @ 6.2.30 version-bump — version-string stamp only; PE backend untouched; cass SELFHOST_OK) |
| **cyrius-lsp** (language server) | 531,688 B |
| **cc5** (prior-major v5.11.69, tracked) | 874,232 B |
| **cybs** (bootstrap compiler) | **21,066 B** (@2026-06-20 — grew from 12,344 B to compile ALL of `src/main.cyr`; **seed→cybs→cycc now reproduces build/cycc byte-identical** — the CVE-20 self-host restoration. cybs(main.cyr)=gen1, gen1(main.cyr)=gen2=build/cycc, fixpoint holds) |
| **seed** (`bootstrap/asm`, root of trust) | **29,024 B** (@2026-06-20 — +8 B from the cybs string-lexer NUL-terminator fix that completed the self-host; regenerated as cybs(asm.cyr), Rust-seed-verified via `bootstrap/verify.sh`, `bootstrap/SHA256SUMS` updated) |
| check.sh gates | **92/92 + the D7 boot gate** (+2 @.29 — `_cli_cross_compile_gate` (CLI cbt/cyrius.cyr → PE/Mach-O/aarch64, the .25-class gate) + `_fuzz_harness_gate` (cyrius fuzz → exit 0 + "0 failed"); both also per-PR ci.yml steps. + the D7 boot gate post-step @.28) |
| aarch64 native tcyr | **189 pass / 0 fail / 0 xfail / 1 skip** (@.29 VR-01 — the aarch64-native CI job runs the FULL tcyr corpus on real arm64. It surfaced a stale-native-fork + 9-bug debt; **all fixed in-slot** (`2026-06-19-aarch64-tcyr-failures.md` RESOLVED), gate HARD + GREEN. `math_pack_integration` skip = x86-only f64_sin; pi-verified) |
| sigil fold | **3.9.4** (@6.2.43 — `ERR_*` → `SIGIL_ERR_*` namespacing, 15 consts, drops bare names that collided with yukti's `ERR_IO`; @6.2.42 — certpin `run_capture(cmd,argv)` → 5-arg API + output buffer; @6.2.31 — luks raw `getrandom` → `_sigil_random_fill` portable boundary) |
| stdlib fold | ~~agnosys~~ **RETIRED @.37** (the stale pre-decomposition 1.4.3 snapshot deleted — its surviving uname/sysinfo role is native in `lib/sys.cyr`; the rest decomposed → agnodrm/sigil/kavach/aegis/sakshi) · **sandhi 1.6.13** · sankoch 2.4.4 · niyama 1.0.5 · **bayan 1.0.3** · ganita 1.0.1 · **patra 1.12.4** · **yukti 2.2.7** · vani 0.9.5 · **sigil 3.9.4** · **mabda 3.4.2** · **sakshi 2.4.2** · **yantra 1.0.0** (**@.43 — refold arc: sakshi 2.4.1→2.4.2 (agnos `uptime_ms` clock), sigil 3.9.3→3.9.4 (`SIGIL_ERR_*`), yukti 2.2.6→2.2.7 (`YUKTI_ERR_*`); + native agnos gates on mmap/dynlib/fdlopen; all lib-only, cycc byte-identical**; **@.38 — patra 1.12.3→1.12.4 (Win `_wal_gen_salts` getrandom ABI), sandhi 1.6.8→1.6.12 (per-call reqctx thread-safety + tls.cyr-contract server handshake + 2-socket mDNS), bayan 1.0.2→1.0.3 (reentrant JSON value+streaming parsers, +5 public `_ctx` fns) — all non-breaking; @.30 — mabda 3.3.0→3.4.2 (array textures + cubemaps, BC tiled arrays, F64_*→MABDA_F64_* math-collision fix, render-target 64 KiB VA-map align + per-context RT VA bump); @.26 — mabda 3.2.14→3.3.0 (asset/png + native/wgpu backends); + yantra 1.0.0 NEW fold — UI/E2E testing (WebDriver/Appium/CDP), OPT-IN, requires net/ws/bayan/sandhi/tls/sakshi/sigil dep chain**) |
| tests | **192** `.tcyr` (+`float_nan_compare` @.41 — IEEE-754 unordered semantics: builtins/`f64_le`/`f64_ge`/operators on NaN/±Inf + ordered regression, 41 assertions; +`assert_fatal` @.38) · 15 `.bcyr` · 5 `.fcyr` |
| stdlib | **98** `lib/*.cyr` (−1 @.37 — `agnosys.cyr` retired) · 79 programs · api-surface **4343 fns** (+9 @.39 — agnos peer `sigset_new/add/has` + `sys_net_config` + 4 net getters + `sys_winsize`; +7 @.38 — `panic`/`assert_fatal` + bayan reentrant; all non-breaking, 0 removals) |
| heap | `output_buf` 16 MB @ `S+0x4D9D000` (relocated heap-top, 2MB→16MB @ .27); `file_map` relocated to freed `0x71A000` band @ .35; 4 per-fn local tables relocated to heap-top `0x5D9D000`+ (4×128 KB, 16384 slots) @ .40 (CVE-24); brk-final `0x5E1D000` (~94.1 MB virtual, +512 KB @ .40) |
| agnos gate | **9/9** (+probe **1h** @.39 — signal constants + sigset wrappers (`1<<sig`) + `net_config` #61 + `winsize` #60: asserts all *defined* (not ud2 stubs) + `SYS_NET_CONFIG==61`/`0x3d` + `SYS_WINSIZE==60`/`0x3c` emitted + `SIGCHLD==17`; `_agnos_emit_gate` reworked peer-independent so #60 doesn't false-positive; +probe **1g** @.36 — `io.cyr` file-lock helpers via `xflock` (`SYS_FLOCK` #59); +probe **1f** @.35 — `sync.cyr` no-op mutex + `sys_access` stub; +probe **x*** @.26 — io.cyr emit-inspect getdents #29; +probe 1e @.23 — fs dir-listing AO_DIRECTORY 0x800) |
| bench (every-release gate) | self_compile @ 6.2.43 (bench-history.sh; cycc is **byte-identical** to .41/.42 — lib-only refold, so self_compile measures the same binary; single-run history band 500–549 ms jitter); x86 cycc **1,073,560 B** (unchanged) |

> **Handoff (2026-06-25):** **v6.2.43 CUT — stdlib-refold arc close: agnos
> clock + ERR_* collision namespacing + agnos landmine gates.** Closes the two
> remaining stdlib-refold issues (the v6.2.41 arity check / v6.2.39 agnos sweep
> surfaced these; user scoped them to .43). **Workflow honored:** patched +
> bumped all three upstream repos, **paused for the user to release+tag all
> three** (sakshi 2.4.2 / sigil 3.9.4 / yukti 2.2.7 — confirmed), then folded
> byte-identical + added the native gates. **(1) sakshi 2.4.2** — `clock.cyr`
> ran the x86 TSC calibration on agnos (`CYRIUS_ARCH_X86` predefined there) via
> `syscall(228)`/`syscall(35)` (undefined / = sysinfo on agnos → garbage freq);
> now reads `uptime_ms` (#40) directly, skipping the rdtsc TSC (10 ms-coarse
> uptime can't calibrate a GHz counter) — mirrors `chrono.cyr`. **(2) sigil
> 3.9.4 + yukti 2.2.7** — namespaced the bare `ERR_*` collision (sigil
> `ERR_IO=6` vs yukti `ERR_IO=14`) → `SIGIL_ERR_*` (15) / `YUKTI_ERR_*` (16),
> bare names dropped (no compat alias — it would re-introduce the colliding
> name). **CI catch:** the first sigil push failed fuzz CI — my rename's `find`
> missed the `.fcyr` extension, leaving `fuzz_revocation.fcyr` on bare
> `ERR_INVALID_INPUT` (COMPILE FAIL); fixed + re-scanned every extension in both
> repos. **(3) native agnos gates** — `#ifdef CYRIUS_TARGET_AGNOS` fail-closed
> on `lib/{mmap,dynlib,fdlopen}.cyr` raw Linux syscalls (mmap #9 → mkdir
> mis-dispatch class); LOW/defensive, not agnos-reachable, purely additive.
> patra `TK_*`→`SQLT_*` + net `SYS_*`→`NSYS_*` were already resolved (the latter
> deliberately, for ESYSXLAT — left alone). **VERIFIED:** `src/` untouched →
> cycc byte-identical **1,073,560 B** + self-host fixpoint · check.sh **92/92** +
> boot gate · the agnos gates + folds compile clean on agnos (no mis-dispatch)
> and x86 byte-identical · **4-host self-host: ecb + cass + pi all SELFHOST_OK**
> (ran per `feedback_cross_os_verify_always_even_lib` even though lib-only —
> cycc byte-identical so it reconfirms the .42 compiler). cyrius references
> neither lib's `ERR_*` directly (uses them as opaque libs) so the breaking
> rename doesn't touch cyrius; downstream consumers update per each lib's
> CHANGELOG. Both issues RESOLVED+archived → **9 active issues**. User
> pushes/tags after CI. **The v6.2.x stdlib-refold arc (.41→.42→.43) is now
> complete.**
>
> **Handoff (2026-06-25):** **v6.2.42 CUT — sigil 3.9.3 fold: certpin
> `run_capture` signature fix.** First of the stdlib-refold issues the v6.2.41
> arity check surfaced. sigil's `certpin_compute_spki_pin` called the obsolete
> 2-arg `run_capture(cmd, argv)` (mis-binding 2 of 5 args + treating
> `Ok(bytes_read)` as an output ptr) → openssl SPKI-pin computation silently
> broken. **Workflow honored (user 2026-06-25):** patched upstream in
> `~/Repos/sigil` (5-arg `run_capture(cmd, arg1, arg2, buf, buflen)` + dedicated
> output buffer), bumped sigil 3.9.2→**3.9.3**, **paused for the user to release
> it** (tag `3.9.3` confirmed), THEN folded byte-identical into `lib/sigil.cyr`
> (sole delta = the certpin fn; verified via diff). **VERIFIED:** `src/`
> untouched → cycc byte-identical **1,073,560 B** + self-host fixpoint · the fold
> compiles **arity-clean** (the `run_capture` 2-vs-5 warning is gone) +
> cross-compiles to PE + aarch64 · check.sh **92/92** + boot gate · **4-host
> self-host: ecb + cass + pi all SELFHOST_OK** (ran the dedicated cross-OS gate
> per `feedback_cross_os_verify_always_even_lib`, even though lib-only — cycc is
> byte-identical so it reconfirms the .41-verified compiler on each target).
> macho-sigil compile NOT re-run on ecb (the macho fork compiler can't run on
> Linux, and ecb's checkout is stale 6.0.1) — covered by the fix's portability
> (run_capture/alloc/store8, zero macho-specific code), the 3 verified backends,
> and sigil's own 3.9.3 CI. Issue `2026-06-24-sigil-certpin-...` RESOLVED+archived
> → **11 active issues**. **Remaining stdlib-refold arc:** sakshi agnos-clock
> guard + ERR_*/SYS_* constant-collision namespacing → **v6.2.43**. User
> pushes/tags after CI.
>
> **Handoff (2026-06-24):** **v6.2.41 CUT — silent-correctness hardening:
> call-site arity check + IEEE-754 NaN comparison fix.** Two
> "compiles-clean / wrong-result / no-diagnostic" bugs packed together.
> **(1) Arity check** (roadmap-pinned, tentib M3c
> `2026-06-23-call-arity-no-check` RESOLVED+archived): a shared
> `_CHECK_ARITY` helper emits `warning: 'f' expects N arguments, got M` from
> ALL THREE call-emit paths — normal `PARSE_FNCALL`, the `return f(args);`
> tail-call path, and the inline-replay path. The originally-pinned
> PARSE_FNCALL-only scope would have silently missed inlined callees (e.g.
> `ESUBRSP`) and every `return f()`; covering all three is the complete fix.
> Carve-outs: backward-refs-only (`_fnt_offsets>=0` — avoids 556 FPs building
> main.cyr; the inline path skips the gate since `pc` is reliable there),
> variadics (new `GFVA` getter for the write-only `SFVA` flag),
> syscall/`fncallN` structurally exempt, variant ctors register their REAL
> arity (`parse_types.cyr`; the old `1` sentinel's only reader was the inline
> path ctors never take → byte-identical). Surfaced+fixed in-slot: `ESUBRSP`
> 2-vs-1 (cycc self-compiles arity-clean) + `cyml.tcyr` (11 `assert_eq`
> name-arg) + `v5104_inference.tcyr` (`str_builder_new(64)`→`()`).
> **(2) f64 NaN** (prajna `2026-06-24-f64-le-nan-comparison` RESOLVED+archived):
> premise-checking the MECHANISM found it far broader than filed — x86
> `setb`/`sete`/`setbe`/`setne` read CF/ZF without the parity (unordered) flag,
> so `f64_lt`/`f64_eq` builtins, the `f64_le`/`f64_ge` helpers built from them
> (whose "NaN-correct by construction" comment was FALSE), and the
> `<`/`<=`/`==`/`!=` operator sugar were ALL wrong on NaN; only `>`/`>=`
> (`seta`/`setae`) were already correct. `EF64_CMP` now folds `setnp`/`setp`
> (x86, ordered AND `!PF`; `!=` ORs `PF`) + `<=` `cset le`→`cset ls` (aarch64,
> its only unordered-unsafe condition). New `tests/tcyr/float_nan_compare.tcyr`
> (41 assertions) passes on x86 AND real ARM (pi). **VERIFIED:** cycc
> 1,071,936→**1,073,560 B** + self-host byte-identical fixpoint · check.sh
> **92/92** + boot gate · **4-host byte-identical self-host: x86 + ecb (macOS
> arm64) + cass (Windows PE) + pi (aarch64) all SELFHOST_OK** (backend codegen
> changed → ran the dedicated `cross-os-selfhost.sh` per host sequentially) ·
> NaN probe 41/41 on x86 and pi · closure codegen byte-identical (ESUBRSP fix
> output-preserving) · bench-history.sh self_compile 505→**519 ms** (+3.9%;
> manual median-of-5 = 507 ms, within the 500–549 single-run jitter band; the
> per-call-site arity check is expected growth-tax, not a regression). **The arity check earned its keep:** it surfaced a real,
> already-broken (security-adjacent) sigil `certpin_core` `run_capture(cmd,
> argv)` 2-vs-5 signature mismatch (calls an old argv-array API; cert-pinning
> via openssl is broken against the shipped 5-arg `run_capture`) → filed
> `2026-06-24-sigil-certpin-run-capture-signature-mismatch` as a follow-up
> (needs sigil-domain rework + refold; user-chosen not to bundle here). Also
> archived 2 stale-already-resolved issues as housekeeping (trust-chain
> CVE-20/21, roadmap-drift RM-01…05) → **12 active issues remain**. vidya
> field-note for the NaN-parity codegen gotcha deferred to the v6.3.0 closeout
> vidya sync. User pushes/tags after CI.

**Prior v6.2.x handoffs (.40 ← .6) trimmed 2026-06-25** — per-slot narrative is
canonical in [CHANGELOG.md](../../CHANGELOG.md); arc retrospectives in
[completed-phases.md](completed-phases.md). state.md keeps only the active head
(the 3 most recent slots above) per the canonical-source discipline.

## Open carry-ins

Tracked in [roadmap.md](roadmap.md) (active) / [roadmap-future.md](roadmap-future.md)
(watching) / `issues/`; surfaced here so the active head doesn't bury them:

- **x86-macOS usable-toolchain tail** — argv shipped (.30); env / arch-detect /
  cycc-finding / packaging remain; x86-macho cycc self-compile HELD (Intel EOL).
- **Kernel-PIE boot test** — the v6.1.7 ET_DYN wrapper needs an AGNOS `--pie` boot
  harness; aarch64 kernel-PIE is the consumer-gated follow-on.
- **var-syscall `ERR_*`/`SYS_*` namespace** — per-lib source cleanup (yukti/sakshi
  unrouted clock sites HELD / EOL-documented).
- **`2026-06-18-stdlib-native-agnos-abi-fs`** — `xopen` wrappers + cyrlint rule +
  ~58 raw `sys_open` sites (incl. sigil luks); issue active (from the .23 handoff).
- **`stdlib-reference.md`** — ~65/95 lib modules documented (human-led).
- **Windows/AGNOS real CSPRNG** — `issues/2026-06-11-windows-entropy-primitive.md`.
- **agnosys retirement — consumer rewire** (@.37) — chakshu/mihi → `lib/sys.cyr`;
  tracked in **agnodrm** `issues/2026-06-22-cyrius-agnosys-retired-consumer-rewire.md`
  (the decomposition's home repo, not cyrius); chakshu's `cyrius deps` is broken
  until it drops the stdlib entry.
- **`lib/sys.cyr` per-system separation** (watching, user 2026-06-22) — split the
  cross-target `lib/sys.cyr` into `lib/sys/agnos.cyr` etc. **once the other module
  fixes are in.** The natural continuation of the agnosys→`lib/sys.cyr` carve.
- **vidya agnosys knowledge-base cleanup** (v6.3.0 closeout) — `agnosys_patterns`
  entry + ecosystem `agnosys (20 modules)` listing in `vidya/.../ecosystem.cyml`
  are stale post-retirement; refresh at the next minor's vidya sync.

## v6.1.x — CLOSED (Backend Codegen Multi-Arc)

Closed at v6.1.41; v6.2.x is the active cycle (see *Current state* above).
Per-release detail is canonical in [CHANGELOG.md](../../CHANGELOG.md) +
[completed-phases.md](completed-phases.md); the whole-cycle frame is
[roadmap_6.md](roadmap_6.md). (The .0–.41 shipped list was trimmed to this
pointer 2026-06-19.)

## Consumers

AGNOS kernel, agnostik (58 tests), agnodrm (device/DRM core, ex-agnosys), argonaut (424
tests), sakshi, sigil (206 tests), libro (240 tests), shravan (audio),
cyrius-doom, bsp, mabda, kybernet (140 tests), hadara (329 tests),
ai-hwaccel (491 tests). All AGNOS ecosystem projects depend on the compiler
and stdlib.

## Verification hosts

- `ssh pi` — Pi 4 (Linux aarch64 native runtime)
- `ssh ecb` — Apple Silicon MBP (Mach-O arm64 runtime)
- `ssh ach` — Intel Mac (Mach-O x86_64 runtime, Apple EOL-track; self-hosts byte-identical)
- `ssh cass` — Windows 11 24H2 (PE32+ runtime)

> **Note (2026-06-08):** ecb's repo checkout is stale (main @ v6.0.1, committed
> x86 `build/cycc` — only its installed `~/.cyrius/bin/cycc` runs there). Live
> ecb self-host needs that checkout updated; cross-emitted-binary runs verify it
> meanwhile. pi has no repo checkout (the self-host gate ships source over SSH).

## Bootstrap chain

```
bootstrap/asm (29,024 B committed binary — root of trust)
  → cybs (bootstrap compiler; formerly cyrc, renamed v6.0.0)
    → cycc (modular compiler + IR; formerly cc5, renamed v6.0.0)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win (Windows PE32+ cross-compiler)

(bridge.cyr — the old intermediate stage — was retired at v5.11.66.)
seed→cybs→cycc reproduces build/cycc BYTE-IDENTICAL (2026-06-20, CVE-20
resolved, no bridge rung). Enforced: scripts/seed-derive-cycc.sh.
No Rust* . No LLVM. No Python. Just sh + Linux x86_64.
  (* Rust seed in archive/seed/ rebuilds the asm seed itself — one-time
     deep verification via bootstrap/verify.sh; not on the build path.)
Build: sh bootstrap/bootstrap.sh
```
