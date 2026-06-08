---
name: Cyrius Documentation Health
description: Living state of doc currency in the cyrius repo — fresh / stale / archived / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — cyrius

> **Last refresh**: 2026-06-08 (**v6.1.0** — clean cycle-open cut + full docs sweep). Roadmap split into three tiers: `roadmap.md` is now the **active minor only** (v6.1.x), the new **`roadmap_6.md`** holds the whole-v6.x-cycle reference (framing/budgeting/v6.2.x→v6.5.x + a one-screen v6.0.x-COMPLETE summary — the 90+ per-item v6.0.x entries removed, canonical detail stays in CHANGELOG + completed-phases.md), `roadmap-future.md` unchanged. Docs-sweep fixes: false "everything is i64 / no floats" framing corrected (tutorial / cyrius-guide / faq — f64 + `f64v2`/`f64v4` are a deliberate ADR-002 exception); octal-literal (`0o755`) docs added to the guide; the guide's AGNOS `include` block (nonexistent sibling-repo paths) corrected to the real `cyrius.cyml` named-dep mechanism; a wrong `var buf[256]`="2048 B" claim fixed (`var x[N]` = N **bytes**); 4 dead `regression-*.sh` refs in `architecture/cyrius.md` repointed to `programs/checks/`; UEFI Application row added to `platform-status.md`; `migration-strategy.md` banner-marked as a frozen v5.7.39 historical snapshot; version/size markers (README / size-comparisons / platform-status / faq) → v6.1.0 / cycc 931,864 B. **`BENCHMARKS.md` + `bench-history.csv` refreshed** (stale since ~2026-05-18; benchmarking is now an every-release gate per CLAUDE.md Release rule #6). **Still 🟠 (human-led):** `stdlib-reference.md` covers only ~33 of 90 lib modules (native TLS, SIMD/matrix/linalg, async/thread/atomic, base64/bigint/u128, sha1/keccak, cffi, ws, folded deps undocumented). **Prior**: 2026-06-07 (**v6.0.87** — handoff doc-staleness sweep covering the .84–.87 ships: macOS native-TLS/thread_local repair (.84), Windows install pillar — `cyrius build` works on Windows (.85), Windows DXGI GPU enum + Windows-arc close (.86), AGNOS getenv/envp + cross-build gate verified on the real agnos 1.43.2 kernel under QEMU (.87). cycc 931,072 B, check.sh 85/85, tcyr 167. Multi-agent scan, 24 confirmed edits across 10 files.). **Prior**: 2026-06-06 (**v6.0.83** — handoff doc-staleness sweep, 5-agent scan, ~33 findings, closing the native-TLS arc .74–.83). The arc shipped a complete sovereign TLS client (1.2 + 1.3; ECDSA P-256/P-384 + RSA PSS/PKCS#1 + Ed25519; AES-128/256-GCM + ChaCha20; EMS, ALPN, OS trust-store + SNI verification; server-flight reassembly; live-Cloudflare- + OpenSSL-interop-proven), re-backed `lib/tls.cyr` onto it behind `CYRIUS_TLS_NATIVE` (libssl stays default), added typed verbs `tls_get_alpn_selected`/`tls_get_peer_spki_der`, and rewired sandhi 1.4.2 off libssl. Fixes this sweep: **roadmap.md** Mini-arcs D+E marked ✅ COMPLETE (.72–.83) + execution table + finalized-plan items + stale sigil-3.7.3-fold removed; **lib-tls-contract.md** + **threat-model.md** rewritten for the two-backend model (the 🟠 "predate the native stack" gap is now CLOSED); **state.md** bootstrap chain `cyrc/cc5/bridge.cyr` → `cybs/cycc`; **CLAUDE.md** phantom `cyc`-rename purged + module count 80→81; **ecosystem.md** sandhi 1.4.1→1.4.2 + sigil 3.6.4→3.7.4; **faq.md** +macOS/Windows scope + version/`cc5b` fix; **cyrius-guide.md** the never-happened "v6.0.0 removes legacy io fns" claim corrected; **platform-status.md** version stamp; the shipped-broken issue's TLS Section A annotated RESOLVED; **issues/README.md** template `cc3`→`cycc` + floor v4.8.4→v5.0.0; **completed-phases.md** v5.11.x "in-progress" → closed. cycc ~929 KB (unchanged). check.sh 85/85. **Prior refresh**: 2026-06-06 (**v6.0.73** — targeted staleness sweep after the .71/.72/.73 ships: callptr→real-Win64-callee frame fix (.71, `ECALLPTR_PE` force-16-align + GetModuleHandleA/GetProcAddress PE imports, COM vtable dispatch verified on real cass); **TLS 1.2 AEAD record layer** (.72, `lib/tls_native.cyr` `record_seal_12`/`_open_12`, 13-byte AAD, GCM explicit nonce / ChaCha implicit nonce); **TLS 1.2 PRF + key derivation** (.73, master_secret / key_block / partition / verify_data / iv_len_12). Native TLS arc RESUMES (Mini-arc D, 1.2 backport). README + size-comparisons + platform-status size/version markers → v6.0.73, module count 89 → 90, .tcyr 160 → 162. The prior sweep's `lib/tls_native.cyr` "v6.0.10 SCAFFOLD / NOT_IMPLEMENTED" header finding is RESOLVED — header rewritten in .72. **Structural fixes this sweep**: `adr/003-fixed-heap-layout.md`'s stale "Layout (v2.6)" table corrected against the authoritative `src/main.cyr` HEAP MAP (input_buf 128KB→1MB, tok_names 64KB→256KB, fixup_tbl 128KB→16MB, brk 4.7MB→~77.6MB, token cap 131072→1,048,576, fn cap 1024→4096) + an "src/main.cyr wins" pointer; `architecture/cyrius.md` currency stamp re-stamped v5.11.63→reviewed v6.0.73; the Windows-COM-vtable frame-corruption issue ARCHIVED (resolved .71) + two Windows issues' status lines updated for the 2026-06-06 back-burn re-order. Prior refresh: 2026-06-05 (**v6.0.70** — targeted staleness sweep after the .68/.69/.70 ships: README + size-comparisons + platform-status size/version markers → v6.0.70, module count → 89, .tcyr → 160; .68-.70 capability claims (callptr/IR_CALL_INDIRECT, multi-DLL PE imports, full CommandLineToArgvW, §D1 aarch64 deps); cyrius-guide gained a callptr section). cycc = **929,072 B**. check.sh **85/85**. Prior full multi-agent sweep: 2026-06-04 (v6.0.62, v6.0.3→.62 band). `cybs` 44,496 B; `cycc_aarch64` 590,536 B; `cycc_win` 801,280 B; seed/`asm` 29,016 B; lib/*.cyr = **90** (81 stdlib + 9 vendored deps); programs/*.cyr = **80**; tests/tcyr = **162**; benches = 15; **0 git deps** (mabda folded @ 3.0.1, v6.0.45). **v6.0.x major arcs since .3**: codegen P1s (.3/.4); alloc/vec + return-patch + backend collapse (.5–.8); **native TLS 1.3 client+server** (`lib/tls_native.cyr`, .15–.28); **AGNOS userspace target** (`CYRIUS_TARGET_AGNOS`, .48–.49 + boot-to-prompt .55–.56); cap-raise heap surgery (.47); **full Windows PE** (process creation .51, threading + SRWLOCK + per-thread TLS .61, GetCommandLineW args .54); **macOS Darwin stdlib ports** (BSD sockets .59, getdirentries .60, cyrius-init scaffolding .60); octal literals + `cyrius tests` + macOS install hotfix (.62). **Refreshed in the v6.0.62 sweep (~70 objective fixes across ~20 docs)**: README, all 4 guides, stdlib-reference, ecosystem, architecture/{cyrius,package-format}, ffi/fncall-abi, platform-status, size-comparisons, CLAUDE.md, CONTRIBUTING, SECURITY, ADR-001/-005, crash-localization, process-notes, completed-phases — version/size markers → v6.0.62; binary-name purge (phantom `cyc` rename + `cc5_*`/`cyrc` literals → cycc/cybs); counts (59/68 programs → 80; module counts; gates 79→85); mabda git-dep → folded; broken `docs/guides/` relative-link depths. roadmap.md + state.md rotate every release (state.md = .62 close; roadmap .62 marked shipped). Prior refresh: 2026-05-27 v6.0.3; 2026-05-18 v5.11.63 commandress close. | **Refresh cadence**: when docs are touched, update the affected row. **Programmatic gates active**: `_doc_size_currency_gate()` flags cycc-size claims outside ±50 KB of actual; `_cap_drift_gate()` cross-checks heap-map comments against inline literal caps; `_cve05_guard_gate()` locks tok_names mangle-path write boundaries (all now in `programs/checks/` after the v6.0.90 split — `heap_audit.cyr` + `lint_fmt.cyr`).
> **Scope**: This repo only (`cyrius`) — the entire `docs/` tree plus root-level files (README, CHANGELOG, CLAUDE.md, VERSION). Per-stdlib-dep docs live in their own repos and are not audited here. Cross-repo cycle / pin / sweep state lives in [`development/state.md`](development/state.md), not here.
>
> **Convention adopted from agnosticos** (2026-05-10): pattern from `agnosticos/docs/doc-health.md`. Per `first-party-documentation.md` codification, smaller repos can adopt the same shape. Cyrius's tree is ~61 markdown files (vs agnosticos's ~265) so the tier structure here is leaner.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change.

---

## At a glance — inventory (last reviewed 2026-06-04, v6.0.62 sweep)

**~105 markdown files** across the repo (+1 from 2026-05-18: `scripts/shims/README.md` added at v5.11.69 alongside the 3 CLI-shim moves). The 4 guide-shape docs (`tutorial`, `editor-integration`, `faq`, `cyrius-guide`) moved from `docs/` flat → `docs/guides/` subdirectory; no count delta. Bucket counts:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / touched in current cycle** | ~39 | Touched within the v6.x cycle-open + v5.x close; state.md / roadmap.md (rewritten at v6.0.0 cycle-open) / roadmap-future.md (new) / cycle-discipline.md / CHANGELOG / completed-phases (trimmed at .41) / cyrius-guide / tutorial / faq (**cycc-size refreshed 2026-05-17**) / stdlib-reference / benchmarks (**re-pointed at root BENCHMARKS.md 2026-05-18**) / ecosystem / editor-integration / platform-status (**cycc-size refreshed 2026-05-17**) / size-comparisons (**cycc-size refreshed 2026-05-17**) / 6 ADRs / 5 audits / 4 open proposals / dev/process-notes (**historical-frontmatter 2026-05-18**) / dev/module-manifest-design (**cyrius.toml→cyrius.cyml 2026-05-18**) / dev/crash-localization (**cc3→cycc + rename note 2026-05-18**) / dev/benchmarks (**historical-frontmatter 2026-05-18**) / arch/cyrius.md (**doc-currency frontmatter 2026-05-18**) / arch/package-format (**schema refresh + cycc examples 2026-05-18**) / ffi/struct-packing (**verified accurate 2026-05-18**) / threat-model (v5.10.35 refresh) / fncall-abi (v5.10.35 verified) / lib-tls-contract.md / **NEW: `/BENCHMARKS.md` at repo root** (auto-gen by `scripts/bench-history.sh`) |
| 🟡 **Stale — refresh in place** | ~6 | **P2 prose-currency flagged by the 2026-06-04 sweep** (see notes): tutorial.md "Everything is a 64-bit integer / no floats" now false (float + f64v2/f64v4 SIMD shipped); faq.md perf answer pinned to v6.0.3 (needs a bench re-run, not just a size swap); cyrius-guide.md + stdlib-reference.md "v6.0.0 removes legacy io fns" never happened (Result + legacy coexist); octal literals undocumented in the guide; size-comparisons/BENCHMARKS perf tables on a stale baseline. Prose-judgment, deferred to the vidya/follow-up pass. |
| 🟠 **Read-through outstanding** | ~5 | **Structural gaps (P1) flagged 2026-06-04** — human-led re-write needed: `stdlib-reference.md` (native TLS 1.3 + ~40 shipped modules have zero API surface); `cyrius-guide.md` AGNOS include block (~L828-850) references nonexistent files across 3 sibling repos; `architecture/cyrius.md` frozen at a v5.6.43 snapshot + 4 dead `regression-*.sh` refs; `platform-status.md` missing UEFI target row (AGNOS userspace row added v6.0.87); **`migration-strategy.md`** still frozen at v5.7.39 (trigger long passed). (`lib-tls-contract.md` + `threat-model.md` were updated for the two-backend native-TLS model in the v6.0.83 sweep — no longer outstanding.) |
| 🔵 **Probably evergreen** | ~4 | ADR-002/-003/-004 (everything-is-i64, fixed-heap-layout, convention-based-dispatch) + cycle-discipline.md — load-bearing principles; re-read pass quarterly, not weekly. |
| 📦 **Archive — frozen by design** | ~50 | `docs/development/archive/` (6) + `docs/development/issues/archived/` (41 — +1 since 2026-05-17 for commandress papercut filing) + `docs/development/proposals/archived/` (3 — unchanged). Verified — frozen by design. |
| ❓ **Open strategic question** | 0 | None. |

Numbers approximate; rolls up from the per-tier tables below.

**Why now**: doc-health convention adopted at v5.10.34 alongside the sandhi 1.3.2 TLS unblocker. The cyrius doc tree has been actively maintained (CHANGELOG is canonical per CLAUDE.md, state.md refreshes every release, vidya sync at every minor closeout) but the *aggregate* currency has no surface — this file is that surface.

**2026-06-04 sweep notes** (v6.0.62, multi-agent): 8 parallel auditors swept the user-facing + reference tiers (point-in-time docs — issues / proposals / audit / archive / CHANGELOG / state.md — excluded by design). **~70 objective currency fixes landed** across ~20 docs (versions/sizes → v6.0.62 / 906 KB; binary-name purge; counts: programs 59/68 → 80, gates 79 → 85, .tcyr → 157, module counts; mabda git-dep → folded; 6 broken `docs/guides/` relative links). Two empirically-disproven "Known Limitations" removed from the guide (negative literals + mixed `&&`/`||` — both verified to compile/evaluate). **Cross-cutting pattern**: the phantom `cycc → cyc` rename (never happened — `cycc` is permanent) + the wrong `cc3 → cycc @ v5.0.0` chain (correct: `cc3 → cc5 @ v5.0.0`, `cc5 → cycc @ v6.0.0`) appeared in 7+ files — all corrected; forbidden literal `cc5_*` binary names purged. The P1 structural gaps + P2 prose items (see the 🟠/🟡 buckets) are **FLAGGED, not edited** — they need human-led rewrites or a benchmark re-run, routed to the vidya/follow-up pass. **Source-level finding (out of doc scope, surfaced for fixing) — RESOLVED .72**: `lib/tls_native.cyr`'s header previously said "v6.0.10 SCAFFOLD / every fn returns NOT_IMPLEMENTED" despite being a real client+server implementation. The header was corrected 2026-06-04 and rewritten again in .72 to describe the IMPLEMENTED 1.3 stack, the three KNOWN-HOLE public fns, and the IN-PROGRESS 1.2 backport (record layer .72, PRF/key schedule .73). No longer a misleading comment.

**2026-05-18 sweep notes**: dedicated doc-health pass (not a normal release-bump touch) explicitly read-through of the 8 🟠 carryovers from the 2026-05-17 sweep + verification of bench infrastructure shape. Sweep retired 7 of 8 carryovers (the 8th, migration-strategy.md, deferred to v6.0.0 doc-pass per user direction). Three classes of finding:

1. **Mostly accurate, needed naming refresh** (4 docs): `process-notes.md` / `crash-localization.md` / `architecture/cyrius.md` / `architecture/package-format.md` had `cc3` / `cyrius.toml` references that pre-date the v5.0.0 binary rename and the v5.5.x manifest rename. Light frontmatter notes added documenting the renames + pointer at canonical-current docs. `module-manifest-design.md` got mechanical `cyrius.toml` → `cyrius.cyml` sed across 11 occurrences; rest of the doc remains canonical schema reference.

2. **Bench infrastructure orphan** (2 docs): `docs/benchmarks.md` and `docs/development/benchmarks.md` were pointing at each other as authoritative — but the actual auto-gen 3-tier bench system (`scripts/bench-history.sh` + `BENCHMARKS.md` at repo root + `bench-history.csv` history) had been live since v5.7.x with the doc pointers never updated. Fix: `docs/benchmarks.md` now points at `/BENCHMARKS.md` as canonical-current; `docs/development/benchmarks.md` got a historical-frontmatter clarifying it's bounded to the v5.6.x perf arc only. Re-ran `bench-history.sh` to refresh the auto-gen file against v5.11.63 — and the new run caught a **+65.2 % self_compile regression vs 2026-04-18 baseline** (244 ms → 404 ms). To investigate as its own slot.

3. **Accurate-as-is** (1 doc): `ffi/struct-packing.md` — agent-assessed STILL-ACCURATE and grep-verified (fncallN ABI unchanged since v5.4.13 landing).

4. **Defer-to-v6.0.0** (1 doc): `docs/development/migration-strategy.md` — frozen at v5.7.39 Wave snapshot; most Wave work has shipped piecemeal (niyama fold v5.9.0, sandhi 1.3.3 v5.10.34, bayan/ganita carve in flight). User direction: refresh at v6.0.0 cycle-open when v5.x → v6.x migration story itself needs codification, not in this sweep.

Also closed: 1 issue filing (commandress papercut → archived) from the .60-.63 ship arc.

**Prior sweep (2026-05-17, v5.11.59)**: ledger lagged 9 patches behind reality; brought rows current to v5.11.59. Iron-boot papercut 4-slot arc fully closed (.56-.59) + DCE-aware reachability filter cross-arch (aarch64 gained full DCE for the first time). cycc-size claims refreshed 823 KB → 875 KB.

**Prior sweep (2026-05-13, v5.11.42 → v5.11.50)**: ledger lagged 13 patches behind reality; brought rows current to v5.11.42 + caught proposals/archived/ miscategorization. v5.11.50 added cap-drift + doc-size programmatic gates.

---

## Tier 1 — Structural docs (root + `/docs` root)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-06-08 | ✅ Fresh | **Refreshed 2026-06-08 (v6.1.0)**: current-state metrics → cycc 931,864 B at v6.1.0 (cross-compilers `cycc_aarch64` 591,856 B / `cycc_win` 804,864 B). Prior (2026-06-07, v6.0.87): 85 check.sh gates, 167 .tcyr, 90 modules. Historical "as of v5.11.x" feature-landing markers retained. |
| `CHANGELOG.md` | 2026-06-08 | ✅ Fresh | **Source of truth per CLAUDE.md.** Through **v6.1.0** (clean cycle-open cut). Refreshed every release. |
| `CLAUDE.md` | 2026-06-08 | ✅ Fresh | Process + procedures + project-identity. **2026-06-08**: Release rule #6 (benchmark every release) added; `build/` policy rewritten (cc3 dropped early). Version field at `6.1.0` (bumped by `version-bump.sh`). |
| `VERSION` | 2026-06-08 | ✅ Fresh | Single source of truth for version (`6.1.0` at last edit). Bumped via `scripts/version-bump.sh`. |
| `BENCHMARKS.md` (root) | 2026-06-08 | ✅ Fresh | Auto-generated by `scripts/bench-history.sh` (3-tier suite); history in `bench-history.csv`. **Refreshed 2026-06-08 (v6.1.0)** after going stale since ~2026-05-18 — self_compile **463 ms**, cycc 931,864 B. **Benchmarking is now an every-release gate** (CLAUDE.md Release rule #6), not closeout-only. |
| `docs/guides/cyrius-guide.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 sweep**: false "everything is i64 / no floats" framing corrected (f64 + `f64v2`/`f64v4` are a deliberate ADR-002 exception); octal-literal (`0o755`) **Number Literals** subsection added (verified vs `LEXOCT` in lex.cyr); the AGNOS `include` block (nonexistent sibling-repo paths) rewritten to the real `cyrius.cyml` named-dep mechanism (one defunct kybernet init-block removed); `var buf[256]`="2048 B" claim fixed (N **bytes**, not N i64 slots). |
| `docs/guides/tutorial.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 sweep**: same false i64/no-floats framing corrected; otherwise the early-v5.10.x onboarding content stands. |
| `docs/guides/faq.md` | 2026-06-08 | ✅ Fresh | **Refreshed 2026-06-08 (v6.1.0)**: size/version markers → ~931 KB / v6.1.0; self_compile figure reconciled to the every-release bench (~463 ms, growth-tax over v6.0.x); i64/no-floats overclaim fixed; native-TLS + 3-platform-self-host capability added. No longer stale. |
| `docs/stdlib-reference.md` | 2026-06-08 | 🟠 Read-through | **Structural gap confirmed 2026-06-08**: covers only ~33 of 90 lib modules. The native TLS stack (`tls_native`), SIMD / matrix / linalg, async/thread/atomic, base64/bigint/u128, sha1/keccak, cffi, ws, and folded deps have **no API surface**. The closing coverage note was rewritten to enumerate the gap honestly + a stale `audio` ref removed; the full per-module reference is a human-led job (not auto-fabricated). Mirrors `docs/api-surface.snapshot` cadence. |
| `docs/benchmarks.md` | 2026-05-18 | ✅ Fresh | **Re-pointed 2026-05-18**: was pointing at `docs/development/benchmarks.md` (frozen v5.6.x narrative); now points at `/BENCHMARKS.md` at repo root (auto-gen by `scripts/bench-history.sh`) as canonical-current. Pointer hub for the three bench surfaces (auto-gen / binary-size / historical perf arc). |
| `docs/ecosystem.md` | 2026-05-06 | ✅ Fresh | Stdlib + downstream-consumer map. Refreshed at niyama-fold ship. |
| `docs/guides/editor-integration.md` | 2026-05-02 | ✅ Fresh | LSP + editor configs. |
| `docs/size-comparisons.md` | 2026-06-08 | ✅ Fresh | **cycc-size refreshed 2026-06-08 (v6.1.0)**: → **931,864 B** (cycc) / 591,856 B (cycc_aarch64) / 804,864 B (cycc_win). cycc vs gcc/clang/rustc binary size table (comparison-tool figures still from the 2026-05-03 sweep). |
| `docs/platform-status.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 (v6.1.0)**: size marker → ~931 KB / v6.1.0; **UEFI Application target row added** (PE32+, `_TARGET_EFI_APPLICATION`, OVMF smoke, gate `programs/checks/platform_efi.cyr`). Prior (v6.0.87): AGNOS-userspace row + macOS-x86 (`ach` self-hosts) + Windows COM/Win64 callptr (real cass). |
| `docs/api-surface.snapshot` | 2026-05-11 | ✅ Fresh | Generated artifact (not hand-written). Regenerated at every release; gate in `check.sh`. |

---

## Tier 2 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `cyrius.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 sweep**: the 4 dead `regression-*.sh` references (aarch64-syscalls / aarch64-native-selfhost / macho-exit / pe-exit — all deleted scripts) repointed to the current `programs/checks/` gates run via `scripts/check.sh`. Prior (**2026-05-18**): doc-currency frontmatter + binary-rename history. Core architecture narrative (Phases 0-11, principles, bootstrap lineage) is durable reference material. |
| `package-format.md` | 2026-05-18 | ✅ Fresh | **2026-05-18 sweep**: cyrius.toml → cyrius.cyml schema refresh + cycc in build examples + currency frontmatter. `.ark` format unchanged. |

---

## Tier 3 — Operational / Development (`docs/development/`)

> **Important framing**: state.md + roadmap.md + completed-phases.md form the **canonical operational surface**. CLAUDE.md delegates volatile state to state.md, and roadmap.md is the slot-pinning artifact. These three rotate every release; everything else in this tier rotates per-need.

| File | Last touched | Status | Action |
|---|---|---|---|
| `state.md` | 2026-05-27 | ✅ Fresh | **Rotates every release.** v6.0.x cycle state through **v6.0.3** (str_from overload fix). Version section leads with 6.0.3; historical 5.11.x cascade retained below a comment marker (pre-existing, flagged for the eventual prune). |
| `roadmap.md` | 2026-06-08 | ✅ Fresh | **Rewritten 2026-06-08 (v6.1.0 clean cut)** — now the **active minor only** (v6.1.x): PIE codegen (x86→aarch64) + `.gnu.hash` migration + back-compat symlink drop, plus carry-ins (bayan/ganita carve, EADDRA_IMM fix, `_emit_fmt` hoist, DCE consolidation, POSIX `*at()`). References roadmap_6.md + roadmap-future.md. Rotates at every minor cut. |
| `roadmap_6.md` | 2026-06-08 | ✅ Fresh | **New 2026-06-08 (v6.1.0)** — whole-v6.x-cycle reference: framing, per-minor budgeting, v6.2.x → v6.5.x, "what comes after v6.x", + a one-screen **v6.0.x-COMPLETE** summary (the 90+ per-item v6.0.x entries removed; canonical detail = CHANGELOG + completed-phases.md). The cycle-level companion to roadmap.md (active minor) + roadmap-future.md (beyond). |
| `roadmap-future.md` | 2026-05-20 | ✅ Fresh | **New 2026-05-20** — long-term watching list extracted from retired roadmap-old.md. Unpinned language items (Hardware 128-bit div-mod, Phase 3-full varargs, cycc per-block scoping, incremental compilation), speculative type-system work (post-monomorphization generics, effect tracking), ~v7.0 "Cyrius ONE" public-release manuscript pin. Items may pull forward into a v6.x minor when consumer pressure or user direction surfaces. |
| `cycle-discipline.md` | 2026-05-13 | 🔵 Evergreen | **New 2026-05-13** — durable operating principles extracted from accumulated v5.9.x–v5.11.x feedback (slot acceptance, bottom-to-top priority, premise-check at slot entry, cross-host smoke wrapper, cycle-close shape). Referenced from `CLAUDE.md` Key References and `roadmap.md`. Refresh only when a new principle proves durable across at least one subsequent cycle. |
| `completed-phases.md` | 2026-05-12 | ✅ Fresh | Historical release narrative. Trimmed 627 → 95 lines at v5.11.41 per the doc-canonical phase-out track (Phase 0–11 retrospective preserved; v0.9.x → v5.9.x per-version narrative dropped — duplicated by CHANGELOG + vidya + state.md). Per CLAUDE.md, this is where shipped-cycle summaries land at minor closeout. |
| `benchmarks.md` | 2026-05-18 | ✅ Fresh | **Historical-frontmatter added 2026-05-18**: explicitly bounded to v5.6.x perf miniarc; pointers at `/BENCHMARKS.md` (current) + CHANGELOG (per-arc events). No drift — the page IS frozen by design. |
| `process-notes.md` | 2026-05-18 | ✅ Fresh | **Historical-frontmatter added 2026-05-18**: explicitly bounded to pre-v5.0.0 phases; pointers at CLAUDE.md + cycle-discipline.md + state.md + CHANGELOG for current process / state / shipped work. cc2/cc3 references retained in dated narrative entries. |
| `threat-model.md` | 2026-05-10 | ✅ Fresh | **Refreshed 2026-05-10 (v5.10.35)**: added fdlopen-helper + libssl trust boundaries; CVE-02 path-traversal mitigation note; stdlib TLS surface table (v5.6.37 / v5.10.21 / v5.10.27 / v5.10.34 + security caveats for 0-RTT replay + verify-callback override); "Zero external dependencies" → "Zero external **language** dependencies" (stdlib bridges to libssl/libc via fdlopen). |
| `module-manifest-design.md` | 2026-05-18 | ✅ Fresh | **2026-05-18 sweep**: mechanical `cyrius.toml` → `cyrius.cyml` (11 occurrences) since the v5.5.x manifest rename. `[deps]` + `[deps.stdlib]` design unchanged — schema is still canonical. |
| `migration-strategy.md` | 2026-06-08 | 📦 Historical | **Resolved 2026-06-08 (v6.1.0 sweep)** — banner-marked at the top as a frozen v5.7.39 historical snapshot (superseded, not maintained), pointing readers at `ecosystem.md` / `state.md` / `completed-phases.md` / CHANGELOG for current state. Kept in place (not deleted) as a record of the original migration framing. The long-standing 🟠 read-through is now closed by the banner. |
| `crash-localization.md` | 2026-05-18 | ✅ Fresh | **2026-05-18 sweep**: cc3 → cycc in usage examples + binary-rename note (cc3 → cycc at v5.0.0; → cyc at v6.0.0 per CLAUDE.md). CYRIUS_SYMS mechanism itself stable since v4.3.1. Open-bugs section trimmed (libro Heisenbug from v3.4.8+ resolved). |
| `lib-tls-contract.md` | 2026-04-30 | ✅ Fresh | Stdlib TLS contract spec (caught by 2026-05-13 sweep — never tracked before). Sister doc to `threat-model.md`'s TLS surface table; references the v5.6.37 / v5.10.21 / v5.10.27 / v5.10.34 expansion arc. Verify at next minor closeout. |

---

## Tier 4 — ADRs (`docs/adr/`)

6 ADRs. Re-read pass quarterly; ADRs document decisions, not status.

| File | Last touched | Status | Notes |
|---|---|---|---|
| `001-assembly-cornerstone.md` | 2026-04-12 | 🔵 Evergreen | Foundational principle. |
| `002-everything-is-i64.md` | 2026-04-05 | 🔵 Evergreen | Foundational; **note**: the v5.10.28+ typed-simd arc adds `f64v2` / `f64v4` as 16/32-byte primitive types — value-type ABI is the first formal break from pure i64. ADR text should reflect this distinction at next minor closeout. |
| `003-fixed-heap-layout.md` | 2026-04-09 | 🔵 Evergreen | Foundational; layout itself rotates (heap map in main.cyr) but the fixed-heap *principle* is durable. |
| `004-convention-based-dispatch.md` | 2026-04-05 | 🔵 Evergreen | Foundational. |
| `005-two-step-bootstrap.md` | 2026-04-09 | 🔵 Evergreen | Bootstrap chain principle. |
| `006-registry-sovereignty.md` | 2026-05-05 | ✅ Fresh | Just refreshed during the niyama-fold-in cycle. Sovereignty pattern. |

**Open question** — the agnosticos doc-health uses ADR-008 to cover its Cyrius pivot. Cyrius's own ADR series is steady at 6; no immediate gap. The originally-pinned v5.12.0 bare-metal kickoff was **retired at the 2026-05-12 tight-close** — bare-metal formalization + RISC-V rv64 moved to v6.2.x. Re-evaluate at the v6.0.0 cut (cycc → cyc rename + first capability-expansion minor) if a major architectural decision lands without an ADR.

---

## Tier 5 — Audits (`docs/audit/`)

Periodic audit reports; per-audit timestamped (don't refresh in place — supersede with a new audit doc).

| File | Last touched | Status |
|---|---|---|
| `2026-04-13-security-audit.md` | 2026-04-13 | 🔵 Dated artifact |
| `2026-04-26-stdlib-fn-collisions.md` | 2026-04-26 | 🔵 Dated artifact |
| `2026-04-27-cx-direct-emit-inventory.md` | 2026-04-26 | 🔵 Dated artifact |
| `2026-05-01-pre-5.8.0-audit.md` | 2026-05-01 | 🔵 Dated artifact |
| `2026-05-11-zero-call-stdlib.md` | 2026-05-11 | 🔵 Dated artifact (added 2026-05-13 sweep) |

Per CLAUDE.md "Security Audit Process": next periodic security audit due before major releases. The v5.10.x close-out audit originally pinned here was **not run as a standalone artifact**; instead v5.11.41 shipped CVE-08 hardening (`cld` before `rep movsb`) per the 2026-04-13 audit's pinned P2 item. Remaining audit-pinned items: track against the v6.0.0 cut as the next natural full-audit boundary (major release, language-spec consolidation, cycc → cyc rename).

---

## Tier 6 — Issues + Proposals (`docs/development/issues/`, `docs/development/proposals/`)

Open issues are tracked artifacts (filed by consumers or internal observation). Archived when resolved.

### Open issues
**Refreshed 2026-06-08 (v6.1.0).** The two issues this table previously listed as open
(`build-artifact-precommit-hook`, `kybernet-cycc_aarch64-codegen-hang`) shipped and are now in
`issues/archived/` — table corrected. Current open set (`ls docs/development/issues/*.md`):

| File | Filed | Status |
|---|---|---|
| `issues/README.md` | varies | 🔵 Evergreen index |
| `issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md` | 2026-05-27 | 🟡 Open — TS/TSX → JS **emit** stage missing (front-end parses, no codegen). Own arc, v6.1.x+ (see roadmap.md carry-ins + roadmap-future.md). |
| `issues/2026-06-02-macos-x86-release-no-compiler.md` | 2026-06-02 | 🟡 Open — **HELD** (Apple Intel EOL). x86-macho cycc layer-6 self-compile miscompile; arm64-macOS is the supported macOS target. Revisited as a v6.1.x working item, not a blocker. |
| `issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md` | 2026-06-07 | 🟡 Open — x86-macOS cycc can't compile byte-array literals (invisible to self-host; same family as the macos-x86 item above). v6.1.x. |
| `issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md` | 2026-06-07 | 🟡 Open — latent, pre-existing: `add x0,x0,#imm12` masks to 12 bits → byte-array literal > 4096 corrupts. Doesn't bite in-tree. v6.1.x carry-in. |
| `issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md` | 2026-06-06 | 🟡 Open — non-blocking `connect` not Darwin-ported (macho-arm socket-family x86-num mismatch noted at .91 closeout). |
| `issues/2026-06-04-shipped-broken-functionality-found-by-consumers.md` | 2026-06-04 | 🟡 Open — process/retrospective filing (the "found by ports" class). |
| `issues/2026-06-03-ach-selfhosted-runner.md` | 2026-06-03 | 🟡 Open — ach (Intel-Mac) self-hosted CI runner registration (operator-side). |

Other consumer-filed issues continue to land in consumer repos (sandhi / mabda / kavach / kybernet / bote / daimon / agnosys / agnosticos etc.) and are referenced by absolute path in the cyrius roadmap entry when they pin cyrius slots.

**Repros subdir** (`issues/repros/`) — binary + source repros parked separately from issue-text files. Currently holds: `sankoch-2.0.1-deflate-non-roundtrip.{bin,cyr}`. Treat as a repro storage area, not a tracked-file directory.

### Open proposals
| File | Last touched | Status |
|---|---|---|
| `proposals/2026-05-11-pie-support.md` | 2026-05-11 | 🔴 Open — pinned v6.1.x PIE codegen (in proposal body + roadmap.md v6.1.x section) |
| `proposals/2026-05-17-octal-literal-syntax.md` | 2026-05-17 | 🔴 Open — pinned **v6.x** per [[project_kriya_low_level_v6x_syscall_arc]]. Filed during kriya M2 (mkdir); `0o755` lexer addition (~30 LoC). Six first-party consumers paying the comment-rot tax today (kriya, agnos, agnoshi, owl, sit, cyim). |
| `proposals/2026-05-17-syscalls-at-family-stdlib.md` | 2026-05-17 | 🔴 Open — pinned **v6.x** per [[project_kriya_low_level_v6x_syscall_arc]]. Filed during kriya M2 (touch/ln); POSIX `*at()` family + symlink-aware peers. Bundles with the v6.x syscall-stdlib expansion arc (agnos likely co-consumer). |
| `proposals/cyrius-lsp-argv0-self-resolution.md` | 2026-05-02 | 🔴 Open — unpinned |

### Archived proposals
3 files in `proposals/archived/` (unchanged since 2026-05-13 — no new shipped-proposals reclassifications this sweep). All three were "shipped beyond what was asked":
- `2026-05-08-raise-return-cap.md` — shipped **v5.10.6** as 64 → 256 (proposal asked 64 → 128; Option B do-it-once).
- `2026-05-10-raise-compile-source-cap.md` — shipped **v5.11.33** as 2 MB → 8 MB (proposal asked 2 MB → 4 MB; sized for sandhi headroom into v6.x).
- `relax-uninitialized-var-or-improve-error.md` — shipped **v5.8.42** half (b) (mabda C1; improve-error option from the proposal; relax-parser option deliberately not taken).

### Archived issues
**41 files** in `issues/archived/` (+1 since 2026-05-17 for the .60-.63 ship arc closeout). Verified frozen by design — each archived alongside its resolution (CHANGELOG entry that closed it). 2026-05-18 growth driver:
- `2026-05-17-commandress-stdlib-papercuts.md` → 5 items resolved across .60-.63: Items 6+7 → .60 (`lib/process.cyr` `_exec3` byte-contract + stderr dup2); Item 2 → .61 (`lib/toml.cyr` heap-alloc, −256 KB bss); Items 1+5 → .62 (cyrius init scaffold + dead-fn `.bss` attribution hint); aarch64 `_strict_mode` parity → .63. Items 3+4+8 deferred to v6.x as own filings/arcs.

Per the `feedback_close_to_archive_issues` memory pin: re-opens are a `git mv` back, not a re-file.

---

## Tier 7 — FFI / Reference (`docs/ffi/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `fncall-abi.md` | 2026-04-25 | ✅ Fresh (verified 2026-05-10) | Spot-verified at v5.10.35 — content scoped to `fncallN` (int-class scalar calls); the v5.10.28-32 typed-simd ABI (`fn f(): f64v2`) is a separate codegen path not invoked via `fncallN`, so no update needed here. (Future: a sibling `docs/ffi/typed-simd-abi.md` may earn its own slot if consumers need a reference.) |
| `struct-packing.md` | 2026-04-19 | ✅ Fresh (verified 2026-05-18) | **2026-05-18 sweep verified**: `fncallN` ABI for struct-by-value shims unchanged since v5.4.13 landing; `fncall2(shim_fp, ...)` pattern still canonical. mabda examples remain real. No update needed. |

---

## Tier 8 — Archive (`docs/development/archive/`, `docs/development/issues/archived/`)

| Path | Count | Status |
|---|---|---|
| `docs/development/archive/` | 6 | 📦 Frozen — historical (cyml-format, handoff doc, v5.3.0 emitter, 2026-04 benchmarks/aarch64 stdlib, lsp-claude consolidation) |
| `docs/development/issues/archived/` | 41 | 📦 Frozen — resolved bugs (+1 since 2026-05-17 for the .60-.63 commandress papercut close listed above) |
| `docs/development/proposals/archived/` | 3 | 📦 Frozen — shipped proposals (raise-return-cap v5.10.6, raise-compile-source-cap v5.11.33, uninitialized-var error v5.8.42) |

Leave alone unless they need re-classification (e.g., something archived prematurely surfaces again).

---

## Refresh procedure

When docs are touched:

1. Find the affected row in the relevant tier table.
2. Update **Last touched** to the new date.
3. Update **Status** if the bucket changed.
4. Update **Action** if the next step changed.
5. If a doc moved or was archived, update its row.
6. Re-anchor "Last refresh" date in the header.

When the bucket counts at the top drift by more than ~3 in any cell, refresh the at-a-glance table.

This file's refresh cadence is **opportunistic** (touched when other docs are touched), not periodic.

---

## What this file is NOT

- Not a substitute for [`development/state.md`](development/state.md) (which holds cross-repo cycle / pin / sweep state).
- Not a CHANGELOG (which records what shipped, not what's stale).
- Not a TODO list (open work for the project lives in [`development/roadmap.md`](development/roadmap.md)).
- Not a per-doc review log (this is the ledger of where each doc stands, not the per-doc reasoning).

---

## Forward doc-policy commitments

Items that are *scheduled* doc decisions, not stale state. Surfaced here so they aren't forgotten when the trigger date arrives.

| # | Commitment | Trigger | Source | Notes |
|---|---|---|---|---|
| 1 | **Vidya sync per minor closeout** — `vidya/content/cyrius/*.cyml` (language, field_notes/{compiler,language}, implementation, types, dependencies, ecosystem) refreshed at every minor closeout per CLAUDE.md "Closeout Pass" step 11. Vidya entries reference cc-binary-name + version + non-obvious gotchas surfaced in the minor. | Every minor closeout | [`CLAUDE.md`](../CLAUDE.md) "Closeout Pass" §11 | Manual — `version-bump.sh` doesn't touch vidya. Cross-check version refs every closeout: vidya files saying `cycc 5.4.x` / `cycc 5.8.x` should match current VERSION (the historical `cc3 4.8.5`-style refs hold pre-v5.0.0 anchor context). |
| 2 | **Periodic security audit** — full source scan for vulnerable patterns (sys_system / READFILE / bounds-check gaps / etc.) before major releases or after significant surface change. | Before each major release; cycle audit every 2-3 minors | [`CLAUDE.md`](../CLAUDE.md) "Security Audit Process" | Last full audit: 2026-04-13 + 2026-05-01 (pre-5.8.0). v5.11.41 shipped CVE-08 hardening + v5.11.65 CVE-05 mangle-path guard piecemeal. **TRIGGER PASSED**: the pinned "before the v6.0.0 cut" full audit did NOT run as a standalone artifact — v6.0.0→.3 shipped (rename + two codegen P1s + deps-lock fix) without it. **RESOLVED (leader, ~late May 2026):** the full audit WAS run ~2 weeks before the 2026-06-07 closeout — the prior "overdue / never ran" note here was stale (the artifact is not under cyrius's own `docs/audit/`, so it was filed at the ecosystem level, not this repo). The v6.0.91 closeout ran only the §9 *quick* re-scan (clean: no new vulnerability class in .88–.90; byte-array peephole bounds-checked — pass-1 cap + per-arch disp caps), which is all the closeout calls for. NOT overdue. **Separate, still open:** vidya `dependencies.cyml` dep catalog is stale beyond this cycle (sigil listed 2.9.3 vs current 3.7.7) — a fuller vidya refresh than the per-closeout gotchas add is its own task. |
| 3 | **API surface snapshot regeneration** — `docs/api-surface.snapshot` regenerated as part of `check.sh`; gate fails if drift. | Every release | `cyrius_api_surface` binary; gate in [`scripts/check.sh`](../scripts/check.sh) | Already automated; included here for visibility. |

---

*Initial scaffold: 2026-05-10 (v5.10.34). First full stale sweep: 2026-05-13 (v5.11.42 — caught 13 patches of drift, 3 archived issues miscategorized as open, 2 untracked proposals, 1 untracked doc, 1 new audit, +19 archived issues, retired v5.12.x ADR-008 reference, v6.0.0 audit re-pin) + proposals-archive pass (caught 3 already-shipped proposals miscategorized as open). Second sweep: 2026-05-13 (v5.11.50 — doc-currency programmatic gates landed). Third sweep: 2026-05-17 (v5.11.59 — iron-boot 4-slot arc fully closed; +8 archived issues; +2 open proposals (kriya M2 v6.x targets); cycc-size refresh 823 KB → 875 KB across Tier 1 docs after the +52 KB drift past the ±50 KB currency gate). Fourth sweep: 2026-05-18 (v5.11.63 — .60-.63 commandress papercut absorber band CLOSED + dedicated doc-health read-through retiring 7 of 8 🟠 carryovers; bench-infrastructure orphan finding: `BENCHMARKS.md` auto-gen system was live since v5.7.x but doc pointers sent readers at frozen v5.6.x narrative instead; pointers fixed + fresh bench run caught +65 % self_compile regression vs 2026-04-18 to investigate; only `migration-strategy.md` remains 🟠 (deferred to v6.0.0 doc-pass per user direction)). Refresh in place when docs are touched.*
