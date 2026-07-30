---
name: Cyrius Documentation Health
description: Living state of doc currency in the cyrius repo — fresh / stale / archived / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — cyrius

> **Last refresh**: 2026-07-30 (**v6.5.3**). Session-handoff sweep. **state.md was the find**:
> its `cycc` size row was current — the `_doc_stamp_currency_gate` enforces exactly that field —
> while every prose row still described **v6.4.x** (Active minor, In-flight arc, Next up,
> Committed after), three releases stale. That is the precise shape of gate-shaped rot: the
> stamped field stays honest and the unstamped prose beside it drifts, which reads as current
> because the numbers next to it are. Rewritten in full for 6.5.x.
> Also this pass: `handoff.md` rewritten for 6.5.3 (it still announced "v6.5.0 is out");
> `roadmap.md` gained its .3 entry; **`CLAUDE.md`'s `**Version**:` line was stuck at 6.5.0** —
> see the note below, it is a workflow trap, not a one-off; `state.md` now names the **three
> UNVETTED subagent-filed issues** so nobody treats them as triaged. Verified NOT stale: the
> `1,124,968` figures in roadmap.md are historical records of what .0 and .1 shipped, and were
> deliberately left alone.
>
> **Workflow trap worth keeping**: `version-bump.sh` rewrites `CLAUDE.md`, `install.sh` and the
> CHANGELOG header **only on the version-CHANGE path**. Writing `VERSION` by hand and *then*
> running `version-bump.sh <same>` — which is how every release this session was cut — takes the
> same-version path and skips all of them. The 6.5.3 fix made that path fall through to the
> force-rebuild (so binaries stop going stale), but the doc rewrites are still correctly
> change-only. **Let `version-bump.sh` do the bump; do not pre-write VERSION.**
> **Prior refreshes**: 2026-07-29 (**v6.5.1**) · 2026-07-27 (**v6.4.82 — the v6.4.x CLOSEOUT**). The .80/.81/.82 band was dominated by the closeout audit finding live bugs and displacing two releases: **.80** `1 - 2 + 3` == **5** (the `_cfo` rewind class, PEXPR tier, 16 sites; 251/251 tcyr were byte-identical across the fix because the corpus had ZERO coverage of the failing shape). **.81** a **FOURTH** `_cfo` occurrence — `EMIT_OP_DISPATCH` never cleared the flag for `mul`/`div` while `add`/`sub` did, so `p * 3 + 1` compiled to **4**, the operator CALL rewound over — plus **CVE-32/33/34** (three unbounded copies reachable from untrusted source; `include "<31490 chars>"` SIGSEGV'd cycc), the heap map documenting that scratch at an address **no code has ever written** (`0x190500 [256]` vs the live unbounded `0x190400`) so `heapmap.sh` validated a fiction for three minors, `heapmap.sh` blind to **20 MB** of live heap, the Windows PE gates validating a **cycc 5.11.69** binary for the whole v6.x line, value-form SIMD silently dropped on the PE/Mach-O CROSS paths since .31, CVE-35/36, and `_doc_stamp_currency_gate` (a checklist entry is not a gate — .77 fixed this rot class, added a checklist item, and a row went stale again two releases later). **.82** the TS arena moved off a fixed base to `alloc()` (it overlapped `tok_types` by 10,027,008 B, safe only by a temporal invariant) + agnos **#94/#95** (band contiguous #82-#95) + the closeout passes: 11 open issues re-triaged against LIVE code with an explicit `**Status:**` added to each, `docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36; CVE-37/38 REFUTED), the v7-PARKED placement-rule violation corrected, and vidya `gotchas.cyml` refreshed after **30 releases** with no entry. Live stamps: cycc **1,108,368 B** · check.sh **150/0** · **251** .tcyr · **100** heap regions · api-surface **4749** · **11** open issues.
> **Scope**: This repo only (`cyrius`) — the entire `docs/` tree plus root-level files (README, CHANGELOG, CLAUDE.md, VERSION). Per-stdlib-dep docs live in their own repos and are not audited here. Cross-repo cycle / pin / sweep state lives in [`development/state.md`](development/state.md), not here.
>
> **Convention adopted from agnosticos** (2026-05-10): pattern from `agnosticos/docs/doc-health.md`. Per `first-party-documentation.md` codification, smaller repos can adopt the same shape. Cyrius's tree is ~61 markdown files (vs agnosticos's ~265) so the tier structure here is leaner.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change.

---

## At a glance — inventory (bucket counts last fully re-tallied 2026-06-04 at the v6.0.62 sweep; per-tier sections re-anchored to the 2026-06-12 v6.1.41 closeout doc-sync — the rollup counts here lag and are approximate)

**~105 markdown files** across the repo (+1 from 2026-05-18: `scripts/shims/README.md` added at v5.11.69 alongside the 3 CLI-shim moves). The 4 guide-shape docs (`tutorial`, `editor-integration`, `faq`, `cyrius-guide`) moved from `docs/` flat → `docs/guides/` subdirectory; no count delta. **Current-cycle anchors (2026-07-23, v6.4.72)**: check.sh **147 gates** + QEMU boot · cycc x86_64 fixpoint **1,103,512 B** · **251 .tcyr** · **99 lib/*.cyr** · **97 programs** · heap **100 regions** · highest SIMD builtin token **151** (`f32v8_dot`) · SIMD Phase 5 complete on all four backends (x86/aarch64/PE/cx) · cross-OS ecb/cass/pi `SELFHOST_OK` · self_compile ~620 ms. (.63→.72 band: agnos GPU-syscall band **#82–#91** contiguous, bayan 1.2.1 f64 JSON round-trip, sandhi 1.9.1 getpeername fold, `cyrius coverage` project-`src/`-scope fix.) (**Prior anchors, 2026-07-12, v6.4.62**: check.sh 146 · cycc 1,103,568 B · 246 .tcyr · self_compile ~627 ms.) (**Prior anchors, 2026-07-10, v6.4.48**: check.sh 141 · cycc 1,091,000 B · 241 .tcyr · self_compile ~649 ms.) (**Prior anchors, 2026-07-09, v6.4.32**: check.sh 132 · cycc 1,077,592 B · 240 .tcyr · 98 lib/*.cyr · self_compile ~616 ms.) (**Prior anchors, 2026-07-06, v6.4.10**: check.sh 130 · cycc 1,057,568 B · 227 .tcyr · self_compile ~561 ms.) (**Prior anchors, 2026-06-28, v6.3.0**: check.sh **100/100** gates + QEMU boot gate · **192 .tcyr** · **98 lib/*.cyr** modules · cycc x86_64 **1,075,136 B** · cross `cycc_aarch64` 627,376 B / `cycc_win` 851,968 B / `cycc-native-aarch64` 947,280 B · api-surface **4352**.) Bucket counts:

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
| `README.md` | 2026-06-28 | ✅ Fresh | Refreshed to **v6.3.0 / cycc 1,075,136 B** (cross: `cycc_aarch64` 627,376 B / `cycc_win` 851,968 B) in the 2026-06-28 doc-staleness sweep; check.sh 92→**100**, heap 99→**96** regions, mabda fold 3.4.2→**3.4.4**; the Caps+heap section flags fn-tables/fixup_tbl/codebuf **and the var-family** as growable. Prior content (still accurate): LSP size 108,600 B; heap = anonymous-mmap chunk allocator (v6.1.19) + `alloc_init` idempotent (v6.1.23); native TLS 1.3 default backend (since v6.1.21); stdlib category table extracted to [`stdlib-modules.md`](stdlib-modules.md). |
| `CHANGELOG.md` | 2026-06-12 | ✅ Fresh | **Source of truth per CLAUDE.md.** Through **v6.2.0** (Phase-0 growable-region foundation: fixup_tbl/fn-tables/codebuf + `cyrius init` CI/release; see CHANGELOG). Refreshed every release. |
| `CLAUDE.md` | 2026-06-12 | ✅ Fresh | Process + procedures + project-identity. Release rule #6 (benchmark every release); `build/` policy (cc3 dropped early). Version field at `6.2.0` (bumped by `version-bump.sh`). |
| `VERSION` | 2026-06-12 | ✅ Fresh | Single source of truth for version (`6.1.41` at last edit). Bumped via `scripts/version-bump.sh`. |
| `BENCHMARKS.md` (root) | 2026-06-08 | ✅ Fresh | Auto-generated by `scripts/bench-history.sh` (3-tier suite); history in `bench-history.csv`. **Refreshed every-release (v6.1.15)** — self_compile ~**498 ms** (479/503/498 across .13/.14/.15, box noise), cycc 1,038,584 B. **Benchmarking is an every-release gate** (CLAUDE.md Release rule #6), not closeout-only. |
| `docs/guides/cyrius-guide.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 sweep**: false "everything is i64 / no floats" framing corrected (f64 + `f64v2`/`f64v4` are a deliberate ADR-002 exception); octal-literal (`0o755`) **Number Literals** subsection added (verified vs `LEXOCT` in lex.cyr); the AGNOS `include` block (nonexistent sibling-repo paths) rewritten to the real `cyrius.cyml` named-dep mechanism (one defunct kybernet init-block removed); `var buf[256]`="2048 B" claim fixed (N **bytes**, not N i64 slots). |
| `docs/guides/tutorial.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 sweep**: same false i64/no-floats framing corrected; otherwise the early-v5.10.x onboarding content stands. |
| `docs/guides/faq.md` | 2026-06-08 | ✅ Fresh | **Refreshed 2026-06-08 (v6.1.15)**: size/version → ~1.0 MB / v6.1.15; self_compile ~500 ms (drift narrative re-stated as "settled ~480–500 ms", not "drifted up to ~570"); i64/no-floats overclaim fixed; native-TLS + 3-platform-self-host capability present. |
| `docs/stdlib-modules.md` | 2026-06-10 | ✅ Fresh | **New 2026-06-10 (v6.1.24)**: categorized module *inventory* (98 modules, Core/Types/.../GPU) + fold-in lineage + first-party additions, **extracted from the README** (which now keeps a slim summary + link). Cross-links `stdlib-reference.md` (per-fn API) + `ecosystem.md` (live pins). The category table's fold tags are *initial* fold versions, not current pins. Refresh when a `lib/*.cyr` module is added/removed (module count) or a new fold lands. |
| `docs/stdlib-reference.md` | 2026-06-09 | 🟠 Read-through | **Coverage now ~65 of 98 lib modules** (authored 33 → 65 in the v6.1.18 sweep — Concurrency / Math & SIMD / Crypto / Data & Encoding / Networking-TLS&WebSockets incl. the sovereign `tls_native` / Systems & FFI / Testing & Internal Tooling all added; the long-standing 33/90 gap mostly cleared). Remaining undocumented is by-design (folded sibling distfiles + platform sub-includes `*_win`/`*_macos`/`syscalls_*` + generated `agnosys`). Mirrors `docs/api-surface.snapshot` cadence. |
| `docs/benchmarks.md` | 2026-05-18 | ✅ Fresh | **Re-pointed 2026-05-18**: was pointing at `docs/development/benchmarks.md` (frozen v5.6.x narrative); now points at `/BENCHMARKS.md` at repo root (auto-gen by `scripts/bench-history.sh`) as canonical-current. Pointer hub for the three bench surfaces (auto-gen / binary-size / historical perf arc). |
| `docs/ecosystem.md` | 2026-05-06 | ✅ Fresh | Stdlib + downstream-consumer map. Refreshed at niyama-fold ship. |
| `docs/guides/editor-integration.md` | 2026-05-02 | ✅ Fresh | LSP + editor configs. |
| `docs/size-comparisons.md` | 2026-06-08 | ✅ Fresh | **cycc-size refreshed 2026-06-08 (v6.1.15)**: → **1,038,584 B** (cycc) / 593,384 B (cycc_aarch64) / 805,888 B (cycc_win). cycc vs gcc/clang/rustc binary size table (comparison-tool figures still from the 2026-05-03 sweep). |
| `docs/platform-status.md` | 2026-06-08 | ✅ Fresh | **2026-06-08 (v6.1.0)**: size marker → ~931 KB / v6.1.4; **UEFI Application target row added** (PE32+, `_TARGET_EFI_APPLICATION`, OVMF smoke, gate `programs/checks/platform_efi.cyr`). Prior (v6.0.87): AGNOS-userspace row + macOS-x86 (`ach` self-hosts) + Windows COM/Win64 callptr (real cass). |
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
| `state.md` | 2026-06-08 | ✅ Fresh | **Consolidated 2026-06-08 (v6.1.4): pruned 5,809 → ~120 lines.** The 104-entry per-patch session-close log (back to v5.x) + the v6.0.4-frozen structured sections were removed (canonical in CHANGELOG + completed-phases). Now holds the **active cycle** (v6.1.x slot log) + a fresh current-state block (version/sizes/suites/consumers/hosts/bootstrap). The "eventual prune" flagged since v6.0.x is done. |
| `roadmap.md` | 2026-06-08 | ✅ Fresh | **Rewritten 2026-06-08 (v6.1.0 clean cut)** — now the **active minor only** (v6.1.x): PIE codegen (x86→aarch64) + `.gnu.hash` migration + back-compat symlink drop, plus carry-ins (bayan/ganita carve, EADDRA_IMM fix, `_emit_fmt` hoist, DCE consolidation, POSIX `*at()`). References roadmap_6.md + roadmap-future.md. Rotates at every minor cut. |
| `roadmap_6.md` | 2026-06-08 | ✅ Fresh | **New 2026-06-08 (v6.1.0)** — whole-v6.x-cycle reference: framing, per-minor budgeting, v6.2.x → v6.5.x, "what comes after v6.x", + a one-screen **v6.0.x-COMPLETE** summary (the 90+ per-item v6.0.x entries removed; canonical detail = CHANGELOG + completed-phases.md). The cycle-level companion to roadmap.md (active minor) + roadmap-future.md (beyond). |
| `roadmap-future.md` | 2026-05-20 | ✅ Fresh | **New 2026-05-20** — long-term watching list extracted from retired roadmap-old.md. Unpinned language items (Hardware 128-bit div-mod, Phase 3-full varargs, cycc per-block scoping, incremental compilation), speculative type-system work (post-monomorphization generics, effect tracking), ~v7.0 "Cyrius ONE" public-release manuscript pin. Items may pull forward into a v6.x minor when consumer pressure or user direction surfaces. |
| `cycle-discipline.md` | 2026-05-13 | 🔵 Evergreen | **New 2026-05-13** — durable operating principles extracted from accumulated v5.9.x–v5.11.x feedback (slot acceptance, bottom-to-top priority, premise-check at slot entry, cross-host smoke wrapper, cycle-close shape). Referenced from `CLAUDE.md` Key References and `roadmap.md`. Refresh only when a new principle proves durable across at least one subsequent cycle. |
| `completed-phases.md` | 2026-07-06 | ✅ Fresh | Historical release narrative. Trimmed 627 → 95 lines at v5.11.41 per the doc-canonical phase-out track (Phase 0–11 retrospective preserved; v0.9.x → v5.9.x per-version narrative dropped — duplicated by CHANGELOG + vidya + state.md). Per CLAUDE.md, this is where shipped-cycle summaries land at minor closeout. **2026-07-06 (v6.4.10)**: added the **v6.4.x SIMD compute arc** narrative block (f32v4 128-bit .4 → f32v8 256-bit AVX2/Phase-4-close .9, integer vectors + iv_dp8 BitNet dot, the first VEX/AVX the toolchain emits; x86 COMPLETE / aarch64 NEON Phase 5 deferred) + the v6.4.0–.3 openers + the .10 interim items. |
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

**Open question** — the agnosticos doc-health uses ADR-008 to cover its Cyrius pivot. Cyrius's own ADR series is steady at 6; no immediate gap. The originally-pinned v5.12.0 bare-metal kickoff was **retired at the 2026-05-12 tight-close** — bare-metal formalization + RISC-V rv64 moved to v6.2.x (RISC-V later re-homed to v6.6.x, 2026-06-27; bare-metal core shipped .27/.28). Re-evaluate at the v6.0.0 cut (cycc → cyc rename + first capability-expansion minor) if a major architectural decision lands without an ADR.

---

## Tier 5 — Audits (`docs/audit/`)

Periodic audit reports; per-audit timestamped (don't refresh in place — supersede with a new audit doc).

**0 active** + **5 archived** (`docs/audit/archived/`, new dir this 2026-06-09 sweep — all 5 audits archived with completion banners; user-approved). The next periodic security audit (per CLAUDE.md) will land a fresh artifact in `docs/audit/`.
| File (in `archived/`) | Archived | Status |
|---|---|---|
| `2026-04-13-security-audit.md` | 2026-06-09 | ✅ Baseline — P0s + CVE-05/06/07/08 shipped; P2/P3 tail tracked as roadmap/accepted-design. Banner added. |
| `2026-05-01-pre-5.8.0-audit.md` | 2026-06-09 | ✅ RESOLVED — must-fix shipped (v5.7.50/v5.8.0); methodology → CLAUDE.md P(-1) process. Banner added. |
| `2026-04-26-stdlib-fn-collisions.md` | 2026-06-09 | ✅ RESOLVED (v5.7.9) — banner added. |
| `2026-04-27-cx-direct-emit-inventory.md` | 2026-06-09 | ✅ RESOLVED (v5.7.12) — banner added. |
| `2026-05-11-zero-call-stdlib.md` | 2026-06-09 | ✅ RESOLVED (v5.11.21) — banner added. |

Per CLAUDE.md "Security Audit Process": next periodic security audit due before major releases. The v5.10.x close-out audit originally pinned here was **not run as a standalone artifact**; instead v5.11.41 shipped CVE-08 hardening (`cld` before `rep movsb`) per the 2026-04-13 audit's pinned P2 item. Remaining audit-pinned items: track against the v6.0.0 cut as the next natural full-audit boundary (major release, language-spec consolidation, cycc → cyc rename).

---

## Tier 6 — Issues + Proposals (`docs/development/issues/`, `docs/development/proposals/`)

Open issues are tracked artifacts (filed by consumers or internal observation). Archived when resolved.

### Open issues
**Refreshed 2026-06-08 (v6.1.4).** Archived this cycle: `aarch64-eaddra-imm-12bit-mask`
(fixed v6.1.2), `syscalls-at-family-stdlib` proposal (shipped v6.1.3). Current open set
(`ls docs/development/issues/*.md`):

| File | Filed | Status |
|---|---|---|
| `issues/README.md` | varies | 🔵 Evergreen index |
| `issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md` | 2026-06-08 | ✅ Archived — TS/TSX → JS **emit** shipped (Phase D v6.1.10/.11; `cyrius build --target=js` .12; `async` fix .15). 3 adjacent papercuts closed v6.0.5. |
| `issues/2026-06-02-macos-x86-release-no-compiler.md` | 2026-06-02 | 🟡 Open — **HELD** (Apple Intel EOL). x86-macho cycc layer-6 self-compile miscompile; arm64-macOS is the supported macOS target. |
| `issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md` | 2026-06-07 | 🟡 Open — x86-macOS cycc can't compile byte-array literals (same family as macos-x86 above). HELD. |
| `issues/2026-06-08-macho-arm-at-family-darwin-syscall-mappings.md` | 2026-06-08 | 🟡 Open — **NEW (v6.1.3)**: macho-arm `fstatat`/`utimensat`/`linkat`/`renameat` lack Darwin ESYSXLAT mappings (pre-existing; Darwin lacks `utimensat` → needs design). openat/mkdirat/unlinkat/fchmodat work. Own slot. |
| `issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md` | 2026-06-06 | 🟡 Open — non-blocking `connect` not Darwin-ported (macho-arm socket-family x86-num mismatch). |
| `issues/2026-06-04-shipped-broken-functionality-found-by-consumers.md` | 2026-06-04 | 🟡 Open — process/retrospective filing (the "found by ports" class). |
| `issues/2026-06-03-ach-selfhosted-runner.md` | 2026-06-03 | 🟡 Open — ach (Intel-Mac) self-hosted CI runner registration (operator-side). |

Other consumer-filed issues continue to land in consumer repos (sandhi / mabda / kavach / kybernet / bote / daimon / agnosys / agnosticos etc.) and are referenced by absolute path in the cyrius roadmap entry when they pin cyrius slots.

**Repros subdir** (`issues/repros/`) — binary + source repros parked separately from issue-text files. Currently holds: `sankoch-2.0.1-deflate-non-roundtrip.{bin,cyr}`. Treat as a repro storage area, not a tracked-file directory.

### Open proposals
*(2 active after the 2026-06-09 full-sweep archival; see below.)*
| File | Last touched | Status |
|---|---|---|
| `proposals/2026-05-20-syscalls-fsync-stdlib.md` | 2026-05-23 | 🔴 Open — `sys_fsync`/`sys_fdatasync` stdlib wrappers; marked out-of-scope for v5.x (hapi M4 uses raw `syscall(74)`). Decide ship-or-document-as-deferred. |
| `proposals/2026-06-02-fdlopen-helper-trust-for-setuid-consumers.md` | 2026-06-02 | 🔴 Open — `fdlopen_init_trusted()` for setuid consumers; **HIGH-sev** shakti privilege-escalation blocker. NOT shipped as of v6.1.18 (code+doc gap). |

### Archived proposals
**10 files** in `proposals/archived/`. **+5 reclassified this 2026-06-09 full-sweep** (each verified shipped vs CHANGELOG, CI-safe, `git mv`-d from the active dir):
- `2026-05-11-pie-support.md` — shipped **v6.1.6** (x86_64 PIE) + **v6.1.8** (aarch64); kernel-PIE deferred (AGNOS harness).
- `2026-05-17-octal-literal-syntax.md` — shipped **v6.0.62** (`0o755` lexer + gate).
- `2026-05-17-toml-single-bracket-sections.md` — shipped **v6.0.62** (`lib/toml.cyr` single-bracket `[section]`).
- `2026-06-02-struct-field-cap-raise.md` — shipped **v6.0.47** (field cap 32→256, type-table 256→1024).
- `cyrius-lsp-argv0-self-resolution.md` — shipped **v5.11.44** (was mis-filed in the active dir; CHANGELOG already named `archived/` as its home).
- Prior: `2026-05-08-raise-return-cap.md` (v5.10.6), `2026-05-10-raise-compile-source-cap.md` (v5.11.33), `relax-uninitialized-var-or-improve-error.md` (v5.8.42), + 2 more.

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
