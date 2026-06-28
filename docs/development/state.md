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
| **Version** | **6.3.2** (v6.3.x cycle — **Language Refinements**; **undefined-fn reachable-call hard-error, default-on** — a reachable undef call now hard-errors at compile time (was `--strict`-only); `--allow-undef`/`--al` downgrades. Fixup gates flip `_strict_mode`→`_allow_undef` (x86+aarch64); all 6 forks declare `_allow_undef`, 5 parse `--al`. **Full blast radius cleaned with ZERO `--allow-undef` in repo builds**: 18 stdlib include-gap tcyr completed + 3 `mabda` tcyr via **mabda-3.4.5 source-gating** (`#ifdef MABDA_LOGIND`/`MABDA_PNG`, re-folded) + cx fork 47 `*_PE`/`*_ARM` cross-arch stubs (`backend/cx/emit.cyr`) + CLI→PE 11 POSIX stubs (`lib/syscalls_windows.cyr`) + ark `nous` stubs (`programs/nous_stub.cyr`) + TLS-probe/hmtest/bench/fuzz includes. + **cx annotation-desync fold (F)**: `main_cx.cyr` pass-1 was the one fork missing the annotation-token consume (109/122/124-127/133) → a top-level `#pure fn` hit `else{scan=0}` (v6.2.2-class desync); fixed + cx-gate regression added. **cycc 1,075,136→1,075,616 B; self-host + seed→cybs→cycc byte-identical; check.sh 101/101; ecb+cass+pi SELFHOST_OK; cycc-native-aarch64 regenerated 913,920 B + pi own-fixpoint OK; bench self_compile 505 ms.** LESSON: the undef-flip blast radius is **everything that compiles** (forks/cross-arch/aspirational tools), not just the tcyr corpus; the "switch harness to `cyrius build`" idea was non-trivial (repo-relative includes) → stub/guard instead. See CHANGELOG [6.3.2].) PRIOR: **6.3.1** (v6.3.x cycle — **Language / Required-Optional Deps**; **dependency-model lever 2** — required vs optional deps: `optional = true` on `[deps.<name>]`, a Cargo-style `[features]` table (`default` + named feature→dep/feature lists, recursively expanded, cycle-guarded), `cyrius build --features <list>` / `--no-default-features`, and a platform-conditional `target = "<arch|os>"` key. Axes COMBINE — gated out on inactive-feature OR mismatched-target → skipped entirely (no clone/requires-pull/copy/include-push); absent keys → byte-identical resolve (the lever-1 deps gates are the regression wall). **100% cbt-side (`cbt/deps.cyr` + `cbt/core.cyr` + `cbt/cyrius.cyr`) → cycc byte-identical 1,075,136 B; self-host + seed-derive trivially hold; check.sh 100→101 (`_deps_features_gate`); ecb+cass+pi SELFHOST_OK; bench self_compile 508 ms.** GOTCHA (the ordering hazard): the resolver `_auto_deps` fires BEFORE each subcommand's own flag loop → `--features`/target flags are parsed in a PRE-SCAN ahead of resolution. The roadmap's `programs/cyrius_*.cyr` "touched surfaces" paths were STALE — real code = `cbt/`. **B (undefined-fn reachable-call hard-error) UN-BUNDLED → its own slot v6.3.2** (user 2026-06-28): blast radius MEASURED at A's close = **21/192 tcyr** under the flip — 18 stdlib include-gaps (surgical per-tcyr include completion) + 3 `lib/mabda.cyr`→external `samvada_*`/`chitra_*` (fixed at mabda's SOURCE: optional-gate + re-fold). See CHANGELOG [6.3.1].) PRIOR: **6.3.0** (the **var-family growable migration** (Phase-0 tail — the last fixed compile-time cap). Premise-check found the var tables aren't 3 but a **FAMILY of SEVEN** vcnt-indexed 8 B/slot tables — var_noffs (0x11A000), var_sizes (0x12A000), var_types (0x13A000), gvar_byte_off (0x1B0000), enum_const_val (0x1D8000), gvar_initval (0x1EC000), var_enum_id (0x204000) — all 8192-capped, that must grow in LOCKSTEP (any unmigrated one silently overflows past 8192). All 7 → relocatable bases behind `_var_cap`; `SVCNT` grows the family 2× past the cap (ceiling 1 048 576), ending the last fixed compile-time cap (closes the v6.2.0 Phase-0 / AR-03 arc). `src/common/util.cyr` `_var_grow` + ~60 inline-access sites swept to `_base` + per-fork init in all 7 drivers. **Codegen change → cycc 1,073,672→1,075,136 B (var `_base` global-load indirection + chained grow helpers); byte-identical UNDER the cap → self-hosts byte-identical AND seed→cybs→cycc derivation byte-identical (`seed-derive-cycc.sh`); check.sh 100/100 (8300-var grow gate compiles+RUNS); all 6 forks compile; ecb+cass+pi SELFHOST_OK; heapmap 96 PASS; bench self_compile 511 ms.** **SEED BREAK + FIX (2026-06-28, user FURIOUS — CI caught it, I'd only run the cycc fixpoint not seed-derive):** the first cut grew all 7 tables INLINE in one `_var_grow` → cybs (the seed's hand-asm bootstrap compiler) silently mis-compiles fns with too many global/call refs (→SIGSEGV) + tail calls (→SIGILL) → gen1 broke the seed chain. Fix: grow CHAINED `_grow_g1.._grow_g7` (1 table/fn, regular calls, no tail call); per-fork init one-stmt-per-line. **gen1 being ~72KB < build/cycc is NORMAL (red herring — only gen2==build/cycc matters). RUN seed-derive after EVERY src/ compiler change.** See `feedback_seed_derive_mandatory_cybs_limits`. See CHANGELOG [6.3.0].) PRIOR: **6.2.52** (v6.2.x cycle — **Platform Expansion**; **closeout-deferred cleanup** — the v6.2.51 audit's filed items, minus the var-table migration (→ v6.3.0). Three CLI-only distlib-hardening fixes: (1) `distlib --modular` fails loud on a DUPLICATE module basename (two `[lib].modules` in different `src/` subdirs → same `dist/<pkg>/<base>.cyr` overwrite + dup index keys → resolver first-match-wins lost deps); (2) distlib fails loud on a MISSING `modules=` entry, BOTH flat + `--modular` (user 2026-06-28 "make it fail-loud" — was warn+exit 0, a producer/consumer exit-code asymmetry since `cyrius deps` is fail-loud); (3) bounded the `[deps.`/`name` manifest prefix scans (`ndi+6<=mlen`/`pi+4<=mlen` — cosmetic tail over-read, bump-arena never faulted). New `_distlib_failloud_gate`. **var-table growable migration → v6.3.0 opener** (last fixed compile-time table; changes codegen → not closeout-safe; user 2026-06-28). **CLI-only (`cbt/commands.cyr`); `src/` untouched → cycc byte-identical 1,073,672 B; self-host fixpoint; check.sh 98/98→**99/99** (+`_distlib_failloud_gate`); ecb+cass SELFHOST_OK; bench 517 ms (jitter).** See CHANGELOG [6.2.52].) **Earlier releases (6.2.51 back to v5.x): see CHANGELOG.md** — the per-slot history was trimmed from here 2026-06-28 (it duplicated CHANGELOG; state.md is current-cycle volatile only). |
| **cycc** (x86_64 ELF) | **1,075,616 B** (@6.3.2 — +480 B for B1's `_allow_undef` decls + `--al` parse across the forks (src/ changed); self-hosts byte-identical + **seed→cybs→cycc derivable**. Was 1,075,136 B @6.3.0–.1. Size set @6.3.0 var-family growable migration: `_base` global-load indirection + chained grow helpers; self-hosts byte-identical AND **seed→cybs→cycc derivable byte-identical**. Was 1,073,672 B @ 6.2.46–.52.) |
| **cycc_aarch64** (x86-host cross, emits aarch64) | **627,376 B** (rebuilt @ 6.3.0 version-bump; pi SELFHOST_OK) |
| **cycc-native-aarch64** (aarch64-native, tracked) | **913,920 B** (regenerated @ 6.3.2 — +608 B for B1's `_allow_undef`/`--al` in `main_aarch64_native.cyr`; **own-fixpoint verified on REAL pi** (`ssh pi`); was 913,312 B @ 6.3.1 via `cyrius pulsar` — `main_aarch64_native.cyr` cross-built through `cycc_aarch64`; **verified on REAL pi (`ssh pi`): self-hosts byte-identical AND own-fixpoint (binary == its own self-host output, 913,312 B)**. ⚠ **was a stale 947,280 B @ 6.3.0** — a DIFFERENT source fork (`main_aarch64.cyr`): the tracked binary had drifted from what `cyrius pulsar` actually generates. Both forks self-host on pi; aligned the tracked artifact to the canonical `cyrius pulsar` generator. RECIPE INCONSISTENCY to reconcile next ARM-touch: `cbt/pulsar.cyr` builds this from `main_aarch64_native.cyr` (913 KB) but `scripts/cross-os-selfhost.sh pi` + the old state-doc verified `main_aarch64.cyr` (947 KB) — same role, different fork.) |
| **cycc_win** (PE32+ cross) | **851,968 B** (rebuilt @ 6.3.0 version-bump; cass SELFHOST_OK) |
| **cyrius-lsp** (language server) | **108,600 B** (@.43 — corrected from a long-stale 531,688 B doc value; rebuilt from `programs/cyrius-lsp.cyr` with the current cycc) |
| **cc5** (prior-major v5.11.69, tracked) | 874,232 B |
| **cybs** (bootstrap compiler) | **21,066 B** (@2026-06-20 — grew from 12,344 B to compile ALL of `src/main.cyr`; **seed→cybs→cycc now reproduces build/cycc byte-identical** — the CVE-20 self-host restoration. cybs(main.cyr)=gen1, gen1(main.cyr)=gen2=build/cycc, fixpoint holds) |
| **seed** (`bootstrap/asm`, root of trust) | **29,024 B** (@2026-06-20 — +8 B from the cybs string-lexer NUL-terminator fix that completed the self-host; regenerated as cybs(asm.cyr), Rust-seed-verified via `bootstrap/verify.sh`, `bootstrap/SHA256SUMS` updated) |
| check.sh gates | **101/101 + the D7 boot gate** (+1 @6.3.1 — `_deps_features_gate`: lever-2 — an `optional` dep skips with no active feature + activates via `--features` (direct or transitively-named), `target="windows"` skips on linux + resolves under `--win`, axes independent; +1 @6.3.0 — `_var_grow_gate`: an 8300-global program compiles + RUNS, exercising the var-family grow past the old fixed 8192 cap; +1 @.52 — `_distlib_failloud_gate`: `distlib --modular` exits non-zero on a duplicate module basename + on a missing `modules=` entry (was warn+exit 0); +1 @.51 — `_deps_modular_traversal_gate`: CVE-32 — a malicious `dist/<pkg>/index.cyml` sibling with `/`/`..` is rejected (deps non-zero) before any fs op, no arbitrary `.cyr` delete; +1 @.50 — `_deps_modular_gate`: distlib `--modular` per-module dist + index.cyml dep graph, consumer `modular=[...]` pulls EXACT sub-modules + transitive deps (sibling + leaves), excludes the independent module; +1 @.49 — `_deps_groups_gate`: `[groups]` expands in `[deps].stdlib` (nested + cycle-guarded → members resolve); +1 @.47 — `_deps_sidecar_gate`: distlib `dist/<pkg>.deps` sidecar emit (lib/ leaves only) + consumer auto-resolve end-to-end; +1 @.46 — `_deps_requires_gate`: `requires` transitive auto-resolve + dedup + fail-loud-on-missing, hermetic leaf-only fixture; +1 @.45 — `_kernel_pie_struct_gate`: `kernel; --pie` → ET_DYN + PT_LOAD `p_vaddr=0`, structural-only (live boot consumer-gated); +2 @.29 — `_cli_cross_compile_gate` (CLI cbt/cyrius.cyr → PE/Mach-O/aarch64) + `_fuzz_harness_gate`; both also per-PR ci.yml steps. + the D7 boot gate post-step @.28) |
| aarch64 native tcyr | **189 pass / 0 fail / 0 xfail / 1 skip** (@.29 VR-01 — the aarch64-native CI job runs the FULL tcyr corpus on real arm64. It surfaced a stale-native-fork + 9-bug debt; **all fixed in-slot** (`2026-06-19-aarch64-tcyr-failures.md` RESOLVED), gate HARD + GREEN. `math_pack_integration` skip = x86-only f64_sin; pi-verified) |
| sigil fold | **3.9.4** (@6.2.43 — `ERR_*` → `SIGIL_ERR_*` namespacing, 15 consts, drops bare names that collided with yukti's `ERR_IO`; @6.2.42 — certpin `run_capture(cmd,argv)` → 5-arg API + output buffer; @6.2.31 — luks raw `getrandom` → `_sigil_random_fill` portable boundary) |
| stdlib fold | ~~agnosys~~ **RETIRED @.37** (the stale pre-decomposition 1.4.3 snapshot deleted — its surviving uname/sysinfo role is native in `lib/sys.cyr`; the rest decomposed → agnodrm/sigil/kavach/aegis/sakshi) · **sandhi 1.6.13** · sankoch 2.4.4 · niyama 1.0.5 · **bayan 1.0.3** · ganita 1.0.1 · **patra 1.12.4** · **yukti 2.2.7** · vani 0.9.5 · **sigil 3.9.4** · **mabda 3.4.5** · **sakshi 2.4.2** · **yantra 1.0.0** (**@6.3.2 — mabda 3.4.2→3.4.5: gate the optional samvada/logind + chitra/PNG calls behind `#ifdef MABDA_LOGIND`/`MABDA_PNG` so a fold-without-those-deps has no undefined-fn ref (enables the v6.3.2 undef-hard-error); re-folded into `lib/mabda.cyr`**; **@.43 — refold arc: sakshi 2.4.1→2.4.2 (agnos `uptime_ms` clock), sigil 3.9.3→3.9.4 (`SIGIL_ERR_*`), yukti 2.2.6→2.2.7 (`YUKTI_ERR_*`); + native agnos gates on mmap/dynlib/fdlopen; all lib-only, cycc byte-identical**; **@.38 — patra 1.12.3→1.12.4 (Win `_wal_gen_salts` getrandom ABI), sandhi 1.6.8→1.6.12 (per-call reqctx thread-safety + tls.cyr-contract server handshake + 2-socket mDNS), bayan 1.0.2→1.0.3 (reentrant JSON value+streaming parsers, +5 public `_ctx` fns) — all non-breaking; @.30 — mabda 3.3.0→3.4.2 (array textures + cubemaps, BC tiled arrays, F64_*→MABDA_F64_* math-collision fix, render-target 64 KiB VA-map align + per-context RT VA bump); @.26 — mabda 3.2.14→3.3.0 (asset/png + native/wgpu backends); + yantra 1.0.0 NEW fold — UI/E2E testing (WebDriver/Appium/CDP), OPT-IN, requires net/ws/bayan/sandhi/tls/sakshi/sigil dep chain**) |
| tests | **192** `.tcyr` (+`float_nan_compare` @.41 — IEEE-754 unordered semantics: builtins/`f64_le`/`f64_ge`/operators on NaN/±Inf + ordered regression, 41 assertions; +`assert_fatal` @.38) · 15 `.bcyr` · 5 `.fcyr` |
| stdlib | **98** `lib/*.cyr` (−1 @.37 — `agnosys.cyr` retired) · 79 programs · api-surface **4352 fns** (+8 @.45 — sankoch ratio-cap (6) + `patra::patra_insert_row_or_ignore` + `mabda::rg_to_dot`, all non-breaking fold additions; +1 @.44 — `main_aarch64_native::EMITMACHO_ARM64/1` native-fork stub; +9 @.39 — agnos peer `sigset_new/add/has` + `sys_net_config` + 4 net getters + `sys_winsize`; all non-breaking, 0 removals) |
| heap | `output_buf` 16 MB @ `S+0x4D9D000` (relocated heap-top, 2MB→16MB @ .27); `file_map` relocated to freed `0x71A000` band @ .35; 4 per-fn local tables relocated to heap-top `0x5D9D000`+ (4×128 KB, 16384 slots) @ .40 (CVE-24); brk-final `0x5E1D000` (~94.1 MB virtual, +512 KB @ .40) |
| agnos gate | **9/9** (+probe **1h** @.39 — signal constants + sigset wrappers (`1<<sig`) + `net_config` #61 + `winsize` #60: asserts all *defined* (not ud2 stubs) + `SYS_NET_CONFIG==61`/`0x3d` + `SYS_WINSIZE==60`/`0x3c` emitted + `SIGCHLD==17`; `_agnos_emit_gate` reworked peer-independent so #60 doesn't false-positive; +probe **1g** @.36 — `io.cyr` file-lock helpers via `xflock` (`SYS_FLOCK` #59); +probe **1f** @.35 — `sync.cyr` no-op mutex + `sys_access` stub; +probe **x*** @.26 — io.cyr emit-inspect getdents #29; +probe 1e @.23 — fs dir-listing AO_DIRECTORY 0x800) |
| bench (every-release gate) | self_compile **505 ms** @ 6.3.2 (bench-history.sh; within the 500–549 ms jitter band; no regression from the B1 fixup-gate flip — undef-check isn't hot); x86 cycc **1,075,616 B** @6.3.2 (was 508 ms / 1,075,136 B @6.3.1; v6.3.1 was cbt-only so cycc is untouched — no codegen delta); x86 cycc **1,075,136 B** (unchanged @6.3.1 — cbt-only; the size set @6.3.0 var-family migration, was 1,073,672 B @ 6.2.46–.52) |

> **Handoff (2026-06-28):** **v6.3.2 CUT — undefined-fn reachable-call hard-error (default-on)
> + cx annotation-desync fold.** A reachable undef call now hard-errors at compile time by default
> (`--allow-undef`/`--al` downgrades); fixup gates flip `_strict_mode`→`_allow_undef` (x86+aarch64),
> all 6 forks wired. Premise-checked the blast radius at slot entry (21/192 tcyr) but the flip's
> REAL reach is **everything that compiles** — the cx compiler fork (47 `*_PE`/`*_ARM` cross-arch
> refs), the CLI→PE cross-build (11 POSIX refs), the TLS-live probe, the `ark` aspirational tool, a
> bench + a fuzz harness. **User chose the COMPLETE treatment: ZERO `--allow-undef` in repo builds.**
> So: 18 tcyr include-completed; 3 `mabda` tcyr via **mabda-3.4.5** source-gating (`#ifdef
> MABDA_LOGIND`/`MABDA_PNG` on the samvada/chitra calls, re-folded — mabda is independently
> releasable, see its CHANGELOG); cx 47 stubs (`backend/cx/emit.cyr`); PE 11 stubs
> (`lib/syscalls_windows.cyr`, cyrdoc'd + api-surface +11); ark `nous`/`pkg` stubs
> (`programs/nous_stub.cyr`); TLS-probe/hmtest/bench/fuzz includes. F = `main_cx.cyr` pass-1 gained
> the annotation-token consume + a cx-gate regression. **VERIFIED:** release-gate.sh GREEN —
> self-host + seed-derive byte-identical, check.sh 101/101 (incl. cx-annotation regression),
> ecb+cass+pi SELFHOST_OK, bench 505 ms; cycc-native-aarch64 regenerated (913,920 B) + pi
> own-fixpoint OK. To commit: src/backend/*/fixup.cyr + 6 fork mains + backend/cx/emit.cyr +
> main_cx.cyr + lib/{syscalls_windows,mabda}.cyr + programs/{ark,nous_stub,checks/*} + tests/tcyr/* +
> benches/fuzz + docs (CHANGELOG/roadmap/state/issue/api-surface.snapshot) + ci.yml (reverted) +
> version-bump artifacts (cycc, cycc-native-aarch64). User pushes/tags after CI; **mabda 3.4.5 tags
> separately**. **NEXT: v6.3.3–.4 = bare-metal #5+#6 (`[sections]` + inline-asm primitives) then #7
> (kernel-freestanding TLS link).** Then Phase-0 substrate (.5) → the language trio (.6–.8).
>
> **Handoff (2026-06-28):** **v6.3.1 CUT — dependency-model lever 2 (required vs optional
> deps).** User decision: ship the deps lever-2 (A) as v6.3.1 on its own; **un-bundle** the
> undefined-fn hard-error (B) into its own slot v6.3.2. Lever 2 adds `optional = true`, a
> `[features]` table, `--features`/`--no-default-features`, and a `target = "<arch|os>"`
> key (axes combine; absent keys → byte-identical resolve). **100% cbt-side → cycc
> byte-identical 1,075,136 B.** Slot opened with a 5-subsystem premise-check **workflow**
> that corrected the roadmap's stale `programs/cyrius_*.cyr` paths (real code = `cbt/`) and
> surfaced the ordering hazard (`_auto_deps` fires before the subcommand flag loop → a
> PRE-SCAN parses the resolver-affecting flags ahead of resolution). **VERIFIED:** full
> `release-gate.sh` GREEN — self-host byte-identical, seed-derive OK, check.sh 100→101
> (`_deps_features_gate`), ecb+cass+pi SELFHOST_OK, bench 508 ms. **B's blast radius was
> measured at A's close** (`cat tcyr | cycc --strict` from the repo root): **21/192** fail —
> 18 stdlib include-gaps (surgical per-tcyr include completion) + 3 `lib/mabda.cyr`→external
> `samvada_*`/`chitra_*` (fix at mabda's SOURCE: optional-gate + re-fold; user 2026-06-28).
> To commit: `cbt/*` + `programs/checks/*` + docs (CHANGELOG/roadmap/state/issue) + vidya +
> version-bump artifacts (`build/cycc` rebuilt for the version string; install snapshot) +
> **`build/cycc-native-aarch64`** (regenerated via `cyrius pulsar`, **verified self-host
> fixpoint on real pi** — `ssh pi`; this also CORRECTED a stale fork drift: the committed
> binary was 947 KB from `main_aarch64.cyr`, pulsar canonically produces 913 KB from
> `main_aarch64_native.cyr` — see the cycc-native-aarch64 cell for the recipe inconsistency
> to reconcile). User pushes/tags after CI. **NEXT: v6.3.2 = undefined-fn reachable-call hard-error (B),
> default-on** — flip the x86/aarch64 fixup gate `_strict_mode`→`_allow_undef` + `--al` on the
> 5 argv forks (seed-derive after the `src/` edits), land the 21-file corpus cleanup above,
> fold the cx annotation-desync fix. Then **v6.3.3–.4 = bare-metal #5+#6 / #7.**
>
> **Handoff (2026-06-28):** **v6.3.0 CUT — var-family growable migration (opens v6.3.x);
> + a SEED BREAK + FIX + a release-gate consolidation.** The migration (7-table
> vcnt-indexed family → growable; detail in the Version cell + CHANGELOG [6.3.0]) is
> shipped + verified (seed-derive, check.sh 100/100, ecb+cass+pi, native ARM binary
> regenerated). **The drama:** the first cut grew all 7 tables INLINE in one `_var_grow`
> → cybs (the seed's hand-asm bootstrap compiler) silently mis-compiles fns with too many
> global/call refs (→SIGSEGV) + tail calls (→SIGILL) → broke the seed→cybs→cycc chain. I'd
> run only the cycc self-host fixpoint, NOT `seed-derive-cycc.sh` (CI caught it, not me).
> Fix: CHAINED `_grow_g1.._grow_g7` (1 table/fn, regular calls). **Process hardening so it
> can't recur:** `scripts/release-gate.sh` (the single fail-fast pre-tag gate: self-host +
> seed-derive + check.sh + cross-OS + bench), `version-bump.sh` runs seed-derive after its
> rebuild (safety net), CLAUDE.md "## Release Gate" section. KEY: the cycc fixpoint does NOT
> cover the seed chain — `feedback_seed_derive_mandatory_cybs_limits`. **To commit:** the
> seed fix (util.cyr + 7 fork inits + build/cycc + cycc-native-aarch64) + the gate tooling +
> CHANGELOG/state. VERSION stays 6.3.0 (completes the broken committed a9d031bd). **NEXT:
> v6.3.x = lever-2 (Required/Optional deps: features/profiles/target scoping) + the
> undefined-fn hard-error (bundled, safe there) + bare-metal D5-7.**
>
> **Handoff (2026-06-28):** **v6.2.52 CUT — closeout-deferred cleanup.** User: "complete
> deferred as 6.2.52 and with var-table being 6.3.0." Landed the v6.2.51 audit's filed
> items EXCEPT the var-table migration: (1) `_distlib_modular_emit` fails loud on a
> duplicate module basename (`seen_bases` + `_dep_list_has` → `_err_ctx` + return 1); (2)
> distlib fails loud on a missing `modules=` entry, BOTH flat + `--modular` paths (user
> mid-slot answered the open exit-code Q: "make it fail-loud" — was warn+exit 0); (3)
> bounded the `[deps.`/`name` manifest prefix scans (`ndi+6<=mlen`/`pi+4<=mlen`). New
> `_distlib_failloud_gate` (check.sh 98→99). **VERIFIED:** cycc byte-identical 1,073,672 B
> (CLI-only); self-host fixpoint; check.sh 99/99; ecb+cass SELFHOST_OK; bench 517 ms. User
> pushes/tags after CI. **var-table growable migration RE-PINNED → v6.3.0** (the minor
> opener — last fixed compile-time table `var_noffs`/`var_sizes`/`var_types`, SVCNT cap 8192
> @ src/common/util.cyr; changes codegen → breaks byte-identical, can't be a closeout patch;
> roadmap_6.md + `2026-06-27-v62x-closeout-deferred` both pin it). **NEXT: v6.3.0 = var-table
> migration (verify byte-identical ecb/cass/pi per the v6.0.7 ret_patches recipe), THEN the
> rest of v6.3.x (lever-2 optional deps + undefined-fn hard-error + bare-metal D5-7) — user:
> "we will worry about the 6.3.x work after those are done."**
>
> **Handoff (2026-06-27):** **v6.2.51 CUT — v6.2.x END-OF-MINOR CLOSEOUT (pre-v6.3.0).**
> User: "lets do its own patch please." Mechanical gates all green (self-host
> byte-identical; bootstrap closure seed→cybs→cycc byte-identical via
> `seed-derive-cycc.sh`; check.sh; ecb+cass+pi SELFHOST_OK). Judgment passes run as a
> 6-dimension **workflow** (heap/dead-code/refactor/code-review/cleanup/security) — NOTE
> 3 of 6 dims returned stub payloads (flaky), so dead-code/refactor/cleanup were redone
> INLINE (more reliable than re-spawning). **The real find: CVE-32 (P1) — a path
> traversal I introduced in .50**: `_dep_pull_submodule` (cbt/deps.cyr) `sys_unlink`'d
> `lib/<pkg>_<submod>.cyr` on a dep-/index-controlled unsanitized name BEFORE
> `_dep_copy_file`'s CVE-04 guard → a malicious `dist/<pkg>/index.cyml` sibling
> (`a/../../../x`) could delete an arbitrary `.cyr` during automatic `cyrius deps`. Fixed
> with a shared `_dep_reject_unsafe_name` (reject `/`+`..`) at ALL ingestion points
> (submod top-of-fn before any fs op, index `lib:<leaf>`, producer `pkg_name`) +
> `_deps_modular_traversal_gate` (check.sh 97→98). Also landed: distlib >256KB truncation
> loud-fail (both flat+modular reads, cbt/commands.cyr); `_distlib_named_deps` refactor
> (dedup the named-dep scan); heap-doc refresh (84→96 regions; ZERO new fixed regions this
> minor). Dead-code floor 62/26001 (cross-arch/CLI, not removable). **VERIFIED:** cycc
> byte-identical 1,073,672 B (only src/ touch = a comment, proven inert); self-host
> fixpoint; check.sh 98/98; ecb+cass+pi SELFHOST_OK. User pushes/tags after CI.
> **DEFERRED → v6.3.x** (`2026-06-27-v62x-closeout-deferred`): var-table growable
> migration (breaks byte-identical), `--modular` basename-collision guard, prefix-scan
> over-read. **OPEN Q TO USER (not yet decided): should `distlib` exit non-zero on a
> missing `modules=` entry** (producer/consumer exit-code asymmetry — CI-behavior change).
> **NEXT: v6.3.x = lever-2 (Required vs Optional deps: features/profiles/target scoping)
> + the undefined-fn hard-error default-on (bundled, fully safe there) + bare-metal D5-7.**

**Older handoffs trimmed** (.50 ← v6.2.6 on 2026-06-28; .40 ← .6 earlier) — per-slot
narrative is canonical in [CHANGELOG.md](../../CHANGELOG.md); arc retrospectives in
[completed-phases.md](completed-phases.md). state.md keeps only the **active head**
(the 3 most recent slots above) per the canonical-source discipline — when this grows
past ~3 handoffs (or the version cell past ~1 prior), trim again; it's a booklet smell.

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
