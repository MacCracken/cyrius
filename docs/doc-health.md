---
name: Cyrius Documentation Health
description: Living state of doc currency in the cyrius repo — fresh / stale / archived / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — cyrius

> **Last refresh**: 2026-05-19 (v5.11.69 — v5.x **cycle close** doc sweep + scripts/ audit + docs/guides/ reorg + vidya refresh. cycc = 874,232 B post-.68 heap-map full reorg (was 876,408 at .63 → unchanged-ish via .64-.65 deltas; -2,176 net through .69, well within ±50 KB gate). check.sh 76/76. v6.0-runway absorbed 5 v6.0.0 items across .65-.68 (CVE-05, bridge retirement, build-cycc-verify.sh skeleton, cc3-residue, heap-map full reorg). v5.11.x cycle closed 2026-05-19. Prior refresh: 2026-05-18 v5.11.63 .60-.63 commandress papercut close + full doc-health sweep retiring 7 of 8 🟠 read-through carryovers; 2026-05-17 v5.11.59 iron-boot arc + DCE filter cross-arch; 2026-05-13 v5.11.50 cap-drift + doc-size gates; 2026-05-13 v5.11.42 roadmap reorg.) | **Refresh cadence**: when docs are touched, update the affected row. **Programmatic gates active**: `_doc_size_currency_gate()` flags cycc-size claims outside ±50 KB of actual; `_cap_drift_gate()` cross-checks heap-map comments against inline literal caps; `_cve05_guard_gate()` locks tok_names mangle-path write boundaries (all in `programs/check.cyr`).
> **Scope**: This repo only (`cyrius`) — the entire `docs/` tree plus root-level files (README, CHANGELOG, CLAUDE.md, VERSION). Per-stdlib-dep docs live in their own repos and are not audited here. Cross-repo cycle / pin / sweep state lives in [`development/state.md`](development/state.md), not here.
>
> **Convention adopted from agnosticos** (2026-05-10): pattern from `agnosticos/docs/doc-health.md`. Per `first-party-documentation.md` codification, smaller repos can adopt the same shape. Cyrius's tree is ~61 markdown files (vs agnosticos's ~265) so the tier structure here is leaner.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change.

---

## At a glance — 2026-05-19 inventory (v5.x cycle close)

**~105 markdown files** across the repo (+1 from 2026-05-18: `scripts/shims/README.md` added at v5.11.69 alongside the 3 CLI-shim moves). The 4 guide-shape docs (`tutorial`, `editor-integration`, `faq`, `cyrius-guide`) moved from `docs/` flat → `docs/guides/` subdirectory; no count delta. Bucket counts:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / touched in current cycle** | ~39 | Touched within the v5.10.x → v5.11.x cycle; state.md (v5.11.63) / roadmap.md (v5.11.63) / roadmap-old.md / cycle-discipline.md / CHANGELOG (v5.11.63) / completed-phases (trimmed at .41) / cyrius-guide / tutorial / faq (**cycc-size refreshed 2026-05-17**) / stdlib-reference / benchmarks (**re-pointed at root BENCHMARKS.md 2026-05-18**) / ecosystem / editor-integration / platform-status (**cycc-size refreshed 2026-05-17**) / size-comparisons (**cycc-size refreshed 2026-05-17**) / 6 ADRs / 5 audits / 4 open proposals / dev/process-notes (**historical-frontmatter 2026-05-18**) / dev/module-manifest-design (**cyrius.toml→cyrius.cyml 2026-05-18**) / dev/crash-localization (**cc3→cycc + rename note 2026-05-18**) / dev/benchmarks (**historical-frontmatter 2026-05-18**) / arch/cyrius.md (**doc-currency frontmatter 2026-05-18**) / arch/package-format (**schema refresh + cycc examples 2026-05-18**) / ffi/struct-packing (**verified accurate 2026-05-18**) / threat-model (v5.10.35 refresh) / fncall-abi (v5.10.35 verified) / lib-tls-contract.md / **NEW: `/BENCHMARKS.md` at repo root** (auto-gen by `scripts/bench-history.sh`) |
| 🟡 **Stale — refresh in place** | 0 | None flagged. |
| 🟠 **Read-through outstanding** | 1 | `docs/development/migration-strategy.md` — frozen at v5.7.39 Wave snapshot. Per 2026-05-18 user direction: defer to v6.0.0 cycle-open doc-pass (when the v5.x → v6.x migration story itself needs codification). The other 7 carryovers from prior sweep all retired this pass (3 were minor-refresh, 2 were major-rewrite resolved by `BENCHMARKS.md` auto-gen + historical-frontmatter, 1 was archive-by-design correction, 1 was actually-accurate verified). |
| 🔵 **Probably evergreen** | ~4 | ADR-002/-003/-004 (everything-is-i64, fixed-heap-layout, convention-based-dispatch) + cycle-discipline.md — load-bearing principles; re-read pass quarterly, not weekly. |
| 📦 **Archive — frozen by design** | ~50 | `docs/development/archive/` (6) + `docs/development/issues/archived/` (41 — +1 since 2026-05-17 for commandress papercut filing) + `docs/development/proposals/archived/` (3 — unchanged). Verified — frozen by design. |
| ❓ **Open strategic question** | 0 | None. |

Numbers approximate; rolls up from the per-tier tables below.

**Why now**: doc-health convention adopted at v5.10.34 alongside the sandhi 1.3.2 TLS unblocker. The cyrius doc tree has been actively maintained (CHANGELOG is canonical per CLAUDE.md, state.md refreshes every release, vidya sync at every minor closeout) but the *aggregate* currency has no surface — this file is that surface.

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
| `README.md` | 2026-05-06 | ✅ Fresh | Top-level project README; last touched at v5.11.0 cycle open. |
| `CHANGELOG.md` | 2026-05-18 | ✅ Fresh | **Source of truth per CLAUDE.md.** Through v5.11.63 (.60-.63 commandress papercut absorber band CLOSED). Refreshed every release. |
| `CLAUDE.md` | 2026-05-18 | ✅ Fresh | Process + procedures + project-identity. Volatile state delegated to state.md per its own principle. Version field at `5.11.63`. |
| `VERSION` | 2026-05-18 | ✅ Fresh | Single source of truth for version (`5.11.63` at last edit). Bumped via `scripts/version-bump.sh` (v5.11.58 closed the rebuild-staleness bug that froze the wrapper at .25). |
| `BENCHMARKS.md` (root) | 2026-05-18 | ✅ Fresh | **NEW row, 2026-05-18 sweep**. Auto-generated by `scripts/bench-history.sh` (3-tier suite). Run history in `bench-history.csv`. Refreshed at this sweep — caught +65.2 % self_compile regression vs 2026-04-18 baseline (244 ms → 404 ms); to investigate as own slot. Cadence: every release closeout + on-demand. |
| `docs/guides/cyrius-guide.md` | 2026-05-03 | ✅ Fresh | Complete language reference. Last touched in the early-v5.10.x doc-audit pass; spot-check at next minor closeout. |
| `docs/guides/tutorial.md` | 2026-05-03 | ✅ Fresh | User-facing onboarding. Same provenance as cyrius-guide. |
| `docs/guides/faq.md` | 2026-05-17 | ✅ Fresh | **cycc-size claim refreshed 2026-05-17 (v5.11.59)**: ~823 KB → ~875 KB. v5.11.63 cycc at 876,408 B — within ±50 KB tolerance, no refresh needed. |
| `docs/stdlib-reference.md` | 2026-05-03 | ✅ Fresh | API surface reference. Mirrors `docs/api-surface.snapshot` regeneration cadence. |
| `docs/benchmarks.md` | 2026-05-18 | ✅ Fresh | **Re-pointed 2026-05-18**: was pointing at `docs/development/benchmarks.md` (frozen v5.6.x narrative); now points at `/BENCHMARKS.md` at repo root (auto-gen by `scripts/bench-history.sh`) as canonical-current. Pointer hub for the three bench surfaces (auto-gen / binary-size / historical perf arc). |
| `docs/ecosystem.md` | 2026-05-06 | ✅ Fresh | Stdlib + downstream-consumer map. Refreshed at niyama-fold ship. |
| `docs/guides/editor-integration.md` | 2026-05-02 | ✅ Fresh | LSP + editor configs. |
| `docs/size-comparisons.md` | 2026-05-17 | ✅ Fresh | **cycc-size claims refreshed 2026-05-17 (v5.11.59)**: 823,112 B → **875,336 B**. v5.11.63 cycc at 876,408 B — within tolerance. cycc vs gcc/clang/rustc binary size table. |
| `docs/platform-status.md` | 2026-05-17 | ✅ Fresh | **cycc-size claim refreshed 2026-05-17 (v5.11.59)**: ~823 KB → ~875 KB. v5.11.63 at 876,408 B — within tolerance. Per-target status table. |
| `docs/api-surface.snapshot` | 2026-05-11 | ✅ Fresh | Generated artifact (not hand-written). Regenerated at every release; gate in `check.sh`. |

---

## Tier 2 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `cyrius.md` | 2026-05-18 | ✅ Fresh | **2026-05-18 sweep**: doc-currency frontmatter added pointing at state.md/CHANGELOG for current state; cc3 → cycc → cyc binary-rename history clarified. Core architecture narrative (Phases 0-11, principles, bootstrap lineage) is durable reference material. |
| `package-format.md` | 2026-05-18 | ✅ Fresh | **2026-05-18 sweep**: cyrius.toml → cyrius.cyml schema refresh + cycc in build examples + currency frontmatter. `.ark` format unchanged. |

---

## Tier 3 — Operational / Development (`docs/development/`)

> **Important framing**: state.md + roadmap.md + completed-phases.md form the **canonical operational surface**. CLAUDE.md delegates volatile state to state.md, and roadmap.md is the slot-pinning artifact. These three rotate every release; everything else in this tier rotates per-need.

| File | Last touched | Status | Action |
|---|---|---|---|
| `state.md` | 2026-05-18 | ✅ Fresh | **Rotates every release.** v5.11.x cycle state through v5.11.63 (.60-.63 commandress papercut absorber band CLOSED 4/4). Per-release Version section refresh remains current. |
| `roadmap.md` | 2026-05-18 | ✅ Fresh | **Rotates every release.** Through v5.11.63 (commandress band marked shipped). Remaining named slots: .66/.67 (byte-array literal peephole), .68 (heap-map full reorg + CVE-05), .69 (conditional mabda fold). Absorber buffer .64/.65 open. |
| `roadmap-old.md` | 2026-05-13 | ✅ Fresh | **New 2026-05-13** — verbatim copy of the prior 1214-line roadmap, held for cleanout. Source for v6.x items to pull forward into `roadmap.md` at v5.x close; v5.x retrospective material will migrate to `completed-phases.md` under the same archive pattern used for prior cycles. Frozen content — don't edit in place. |
| `cycle-discipline.md` | 2026-05-13 | 🔵 Evergreen | **New 2026-05-13** — durable operating principles extracted from accumulated v5.9.x–v5.11.x feedback (slot acceptance, bottom-to-top priority, premise-check at slot entry, cross-host smoke wrapper, cycle-close shape). Referenced from `CLAUDE.md` Key References and `roadmap.md`. Refresh only when a new principle proves durable across at least one subsequent cycle. |
| `completed-phases.md` | 2026-05-12 | ✅ Fresh | Historical release narrative. Trimmed 627 → 95 lines at v5.11.41 per the doc-canonical phase-out track (Phase 0–11 retrospective preserved; v0.9.x → v5.9.x per-version narrative dropped — duplicated by CHANGELOG + vidya + state.md). Per CLAUDE.md, this is where shipped-cycle summaries land at minor closeout. |
| `benchmarks.md` | 2026-05-18 | ✅ Fresh | **Historical-frontmatter added 2026-05-18**: explicitly bounded to v5.6.x perf miniarc; pointers at `/BENCHMARKS.md` (current) + CHANGELOG (per-arc events). No drift — the page IS frozen by design. |
| `process-notes.md` | 2026-05-18 | ✅ Fresh | **Historical-frontmatter added 2026-05-18**: explicitly bounded to pre-v5.0.0 phases; pointers at CLAUDE.md + cycle-discipline.md + state.md + CHANGELOG for current process / state / shipped work. cc2/cc3 references retained in dated narrative entries. |
| `threat-model.md` | 2026-05-10 | ✅ Fresh | **Refreshed 2026-05-10 (v5.10.35)**: added fdlopen-helper + libssl trust boundaries; CVE-02 path-traversal mitigation note; stdlib TLS surface table (v5.6.37 / v5.10.21 / v5.10.27 / v5.10.34 + security caveats for 0-RTT replay + verify-callback override); "Zero external dependencies" → "Zero external **language** dependencies" (stdlib bridges to libssl/libc via fdlopen). |
| `module-manifest-design.md` | 2026-05-18 | ✅ Fresh | **2026-05-18 sweep**: mechanical `cyrius.toml` → `cyrius.cyml` (11 occurrences) since the v5.5.x manifest rename. `[deps]` + `[deps.stdlib]` design unchanged — schema is still canonical. |
| `migration-strategy.md` | 2026-04-30 | 🟠 Read-through | **Deferred to v6.0.0 doc-pass per 2026-05-18 user direction.** Frozen at v5.7.39 Wave snapshot; most Wave work has shipped piecemeal (niyama fold v5.9.0, sandhi 1.3.3 v5.10.34, bayan/ganita carve in v5.11.x). Right time to rewrite is v6.0.0 cycle-open when the v5.x → v6.x migration story itself needs codification. |
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
| File | Filed | Status |
|---|---|---|
| `issues/README.md` | varies | 🔵 Evergreen index |
| `issues/2026-05-13-bote-nested-call-state-leak-root-cause.md` | 2026-05-13 | 🟡 Open — Low severity, cold case (diagnostic hint shipped v5.11.28; consumer workaround works; underlying state-leak not reproducible). Filed during v5.11.49 vidya cleanup sweep. |
| `issues/2026-05-13-build-artifact-precommit-hook.md` | 2026-05-13 | 🟡 Open — Medium severity. v5.11.45 grep gate is the catch-after-the-fact safety net; pre-commit hook would close the surface entirely. Filed during v5.11.49 vidya cleanup sweep. |

Two issues stayed open across the .50-.59 ship arc — both Low/Medium severity, neither blocks consumer work. Other consumer-filed issues continue to land in consumer repos (sandhi / mabda / kavach / kybernet / bote / daimon / agnosys / agnosticos etc.) and are referenced by absolute path in the cyrius roadmap entry when they pin cyrius slots.

**Repros subdir** (`issues/repros/`) — binary + source repros parked separately from issue-text files. Currently holds: `sankoch-2.0.1-deflate-non-roundtrip.{bin,cyr}`. Treat as a repro storage area, not a tracked-file directory.

### Open proposals
| File | Last touched | Status |
|---|---|---|
| `proposals/2026-05-11-pie-support.md` | 2026-05-11 | 🔴 Open — pinned v6.1.x PIE codegen (in proposal body + roadmap-old.md v6.1.x section) |
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
| 2 | **Periodic security audit** — full source scan for vulnerable patterns (sys_system / READFILE / bounds-check gaps / etc.) before major releases or after significant surface change. | Before each major release; cycle audit every 2-3 minors | [`CLAUDE.md`](../CLAUDE.md) "Security Audit Process" | Last full audit: 2026-04-13 + 2026-05-01 (pre-5.8.0). v5.11.41 shipped CVE-08 hardening piecemeal from the 2026-04-13 audit's P2 list. Next full audit pin: **before the v6.0.0 cut** (major release, cycc → cyc rename, capability-expansion boundary). |
| 3 | **API surface snapshot regeneration** — `docs/api-surface.snapshot` regenerated as part of `check.sh`; gate fails if drift. | Every release | `cyrius_api_surface` binary; gate in [`scripts/check.sh`](../scripts/check.sh) | Already automated; included here for visibility. |

---

*Initial scaffold: 2026-05-10 (v5.10.34). First full stale sweep: 2026-05-13 (v5.11.42 — caught 13 patches of drift, 3 archived issues miscategorized as open, 2 untracked proposals, 1 untracked doc, 1 new audit, +19 archived issues, retired v5.12.x ADR-008 reference, v6.0.0 audit re-pin) + proposals-archive pass (caught 3 already-shipped proposals miscategorized as open). Second sweep: 2026-05-13 (v5.11.50 — doc-currency programmatic gates landed). Third sweep: 2026-05-17 (v5.11.59 — iron-boot 4-slot arc fully closed; +8 archived issues; +2 open proposals (kriya M2 v6.x targets); cycc-size refresh 823 KB → 875 KB across Tier 1 docs after the +52 KB drift past the ±50 KB currency gate). Fourth sweep: 2026-05-18 (v5.11.63 — .60-.63 commandress papercut absorber band CLOSED + dedicated doc-health read-through retiring 7 of 8 🟠 carryovers; bench-infrastructure orphan finding: `BENCHMARKS.md` auto-gen system was live since v5.7.x but doc pointers sent readers at frozen v5.6.x narrative instead; pointers fixed + fresh bench run caught +65 % self_compile regression vs 2026-04-18 to investigate; only `migration-strategy.md` remains 🟠 (deferred to v6.0.0 doc-pass per user direction)). Refresh in place when docs are touched.*
