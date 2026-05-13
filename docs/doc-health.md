---
name: Cyrius Documentation Health
description: Living state of doc currency in the cyrius repo — fresh / stale / archived / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — cyrius

> **Last refresh**: 2026-05-13 (v5.11.50 — cap-drift + doc-size currency gates landed in `programs/check.cyr`; size-comparisons.md / platform-status.md / faq.md cc5-size claims refreshed from v5.8.x → v5.11.50 (823,112 B / ~823 KB). check.sh 72 → 74. Three new repair-issue filings during the vidya cleanup sweep: build-artifact pre-commit hook, bote nested-call cold-case, cap-drift detector — the last now CLOSED at .50 ship. Prior refresh: 2026-05-13 roadmap reorg at v5.11.42 — `roadmap.md` rewritten as lean current-cycle-only view; prior 1214-line roadmap preserved as `roadmap-old.md`; `cycle-discipline.md` carved as evergreen. Earlier scaffold 2026-05-10 at v5.10.39.) | **Refresh cadence**: when docs are touched, update the affected row. **Programmatic gates added at v5.11.50**: `_doc_size_currency_gate()` flags cc5-size claims outside ±50 KB of actual; `_cap_drift_gate()` cross-checks heap-map comments against inline literal caps.
> **Scope**: This repo only (`cyrius`) — the entire `docs/` tree plus root-level files (README, CHANGELOG, CLAUDE.md, VERSION). Per-stdlib-dep docs live in their own repos and are not audited here. Cross-repo cycle / pin / sweep state lives in [`development/state.md`](development/state.md), not here.
>
> **Convention adopted from agnosticos** (2026-05-10): pattern from `agnosticos/docs/doc-health.md`. Per `first-party-documentation.md` codification, smaller repos can adopt the same shape. Cyrius's tree is ~61 markdown files (vs agnosticos's ~265) so the tier structure here is leaner.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change.

---

## At a glance — 2026-05-13 inventory

**~81 markdown files** across the repo (+20 since scaffold — mostly archived issue resolutions during v5.11.x consumer-filed wave). Bucket counts:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / touched in current cycle** | ~30 | Touched within the v5.10.x → v5.11.x cycle (2026-04 to 2026-05); state.md / **roadmap.md (lean rewrite 2026-05-13)** / **roadmap-old.md (carved 2026-05-13)** / **cycle-discipline.md (new 2026-05-13)** / CHANGELOG (v5.11.42) / completed-phases (trimmed at .41) / cyrius-guide / tutorial / faq / stdlib-reference / benchmarks / ecosystem / editor-integration / platform-status / 6 ADRs / 5 audits / 5 open proposals / a few dev/* docs / **threat-model (v5.10.35 refresh)** / **fncall-abi (v5.10.35 verified)** / **lib-tls-contract.md** |
| 🟡 **Stale — refresh in place** | 0 | None flagged. (Drift candidates flagged 🟠 below.) |
| 🟠 **Read-through outstanding** | ~10 | Older dev/* docs (process-notes, module-manifest-design, migration-strategy, crash-localization), older architecture docs (package-format), older FFI docs (struct-packing) — all dated 2026-04-08 to 2026-04-30; not known to be wrong, but unreviewed against v5.11.x reality. |
| 🔵 **Probably evergreen** | ~4 | ADR-002/-003/-004 (everything-is-i64, fixed-heap-layout, convention-based-dispatch) + **cycle-discipline.md (new 2026-05-13)** — load-bearing principles; re-read pass quarterly, not weekly. |
| 📦 **Archive — frozen by design** | ~41 | `docs/development/archive/` (6) + `docs/development/issues/archived/` (32 — grew from 13 during v5.11.x consumer-filed wave + ELF/CVE/PP-cap cleanup) + `docs/development/proposals/archived/` (3 — new subdir 2026-05-13). Verified — frozen by design. |
| ❓ **Open strategic question** | 0 | None at scaffold time. |

Numbers approximate; rolls up from the per-tier tables below.

**Why now**: doc-health convention adopted at v5.10.34 alongside the sandhi 1.3.2 TLS unblocker. The cyrius doc tree has been actively maintained (CHANGELOG is canonical per CLAUDE.md, state.md refreshes every release, vidya sync at every minor closeout) but the *aggregate* currency has no surface — this file is that surface.

**2026-05-13 sweep notes**: ledger lagged ~13 patches behind reality (last meaningful refresh at v5.10.39; this sweep brings rows current to v5.11.42). The 3 ledger-"open" issues from 2026-05-03 all resolved during v5.11.x and are now in `issues/archived/`. New surface area added: `docs/development/cycle-discipline.md` (evergreen), `docs/development/roadmap-old.md` (frozen verbatim), `docs/audit/2026-05-11-zero-call-stdlib.md` (dated artifact), 2 new proposals (raise-compile-source-cap, pie-support), `docs/development/lib-tls-contract.md` (never tracked — caught in this sweep), `docs/development/issues/repros/` (binary repro storage).

---

## Tier 1 — Structural docs (root + `/docs` root)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-05-06 | ✅ Fresh | Top-level project README; last touched at v5.11.0 cycle open. |
| `CHANGELOG.md` | 2026-05-13 | ✅ Fresh | **Source of truth per CLAUDE.md.** Through v5.11.42 (LSP semantic-tokens legend extension + roadmap sweep finale). Refreshed every release. |
| `CLAUDE.md` | 2026-05-13 | ✅ Fresh | Process + procedures + project-identity. Volatile state delegated to state.md per its own principle. Key References block split 2026-05-13 to surface roadmap-old.md + cycle-discipline.md. |
| `VERSION` | 2026-05-13 | ✅ Fresh | Single source of truth for version (`5.11.42` at last edit). Bumped via `scripts/version-bump.sh`. |
| `docs/cyrius-guide.md` | 2026-05-03 | ✅ Fresh | Complete language reference. Last touched in the early-v5.10.x doc-audit pass; spot-check at next minor closeout. |
| `docs/tutorial.md` | 2026-05-03 | ✅ Fresh | User-facing onboarding. Same provenance as cyrius-guide. |
| `docs/faq.md` | 2026-05-05 | ✅ Fresh | Refreshed during v5.10.x cycle. |
| `docs/stdlib-reference.md` | 2026-05-03 | ✅ Fresh | API surface reference. Mirrors `docs/api-surface.snapshot` regeneration cadence. |
| `docs/benchmarks.md` | 2026-05-03 | ✅ Fresh | User-facing benchmarks summary. Matches `docs/development/benchmarks.md` historical baseline. |
| `docs/ecosystem.md` | 2026-05-06 | ✅ Fresh | Stdlib + downstream-consumer map. Refreshed at niyama-fold ship. |
| `docs/editor-integration.md` | 2026-05-02 | ✅ Fresh | LSP + editor configs. |
| `docs/size-comparisons.md` | 2026-05-03 | ✅ Fresh | cc5 vs gcc/clang/rustc binary size table. |
| `docs/platform-status.md` | 2026-05-10 | ✅ Fresh | **Just refreshed** (2026-05-10 cass/ecb anti-confusion sweep). Per-target status table. |
| `docs/api-surface.snapshot` | 2026-05-11 | ✅ Fresh | Generated artifact (not hand-written). Regenerated at every release; gate in `check.sh`. |

---

## Tier 2 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `cyrius.md` | 2026-04-25 | 🟠 Read-through | Architecture overview. Three weeks old; v5.10.x has shipped multiple ABI changes (typed-simd Phases 1-6, REAL TYPE SYSTEM arc) that may warrant entry-doc refresh. Verify at next minor closeout. |
| `package-format.md` | 2026-04-09 | 🟠 Read-through | `.ark` package format spec. Roughly stable since shipping; verify once at v5.10.x close. |

---

## Tier 3 — Operational / Development (`docs/development/`)

> **Important framing**: state.md + roadmap.md + completed-phases.md form the **canonical operational surface**. CLAUDE.md delegates volatile state to state.md, and roadmap.md is the slot-pinning artifact. These three rotate every release; everything else in this tier rotates per-need.

| File | Last touched | Status | Action |
|---|---|---|---|
| `state.md` | 2026-05-13 | ✅ Fresh | **Rotates every release.** v5.11.x cycle state through v5.11.42 (LSP semantic-tokens + roadmap sweep). Per-release Version section refresh remains current. Pre-v5.11.x slot blocks largely cleared during the .41/.42 sweep (1258 lines removed across .41-.42); residual older blocks acceptable. |
| `roadmap.md` | 2026-05-13 | ✅ Fresh | **Rotates every release.** Reorganized at v5.11.42 into a **lean current-cycle-only view** (~185 lines); only v5.11.x remaining work (bayan+ganita carve, sovereignty/polish buffer, mabda 3.0 conditional, .68 heap-map reorg, .69 fold-applied tag). Pointers out to `cycle-discipline.md`, `state.md`, `roadmap-old.md`, `completed-phases.md`, `CHANGELOG.md`. |
| `roadmap-old.md` | 2026-05-13 | ✅ Fresh | **New 2026-05-13** — verbatim copy of the prior 1214-line roadmap, held for cleanout. Source for v6.x items to pull forward into `roadmap.md` at v5.x close; v5.x retrospective material will migrate to `completed-phases.md` under the same archive pattern used for prior cycles. Frozen content — don't edit in place. |
| `cycle-discipline.md` | 2026-05-13 | 🔵 Evergreen | **New 2026-05-13** — durable operating principles extracted from accumulated v5.9.x–v5.11.x feedback (slot acceptance, bottom-to-top priority, premise-check at slot entry, cross-host smoke wrapper, cycle-close shape). Referenced from `CLAUDE.md` Key References and `roadmap.md`. Refresh only when a new principle proves durable across at least one subsequent cycle. |
| `completed-phases.md` | 2026-05-12 | ✅ Fresh | Historical release narrative. Trimmed 627 → 95 lines at v5.11.41 per the doc-canonical phase-out track (Phase 0–11 retrospective preserved; v0.9.x → v5.9.x per-version narrative dropped — duplicated by CHANGELOG + vidya + state.md). Per CLAUDE.md, this is where shipped-cycle summaries land at minor closeout. |
| `benchmarks.md` | 2026-04-25 | 🟠 Read-through | Per-release benchmark history. v5.10.x rows pending — refresh at minor closeout (typically lands as the "Post-audit benchmarks" P(-1) step). |
| `process-notes.md` | 2026-04-12 | 🟠 Read-through | Process discipline / agent feedback log. ~4 weeks old; spot-check for stale references. |
| `threat-model.md` | 2026-05-10 | ✅ Fresh | **Refreshed 2026-05-10 (v5.10.35)**: added fdlopen-helper + libssl trust boundaries; CVE-02 path-traversal mitigation note; stdlib TLS surface table (v5.6.37 / v5.10.21 / v5.10.27 / v5.10.34 + security caveats for 0-RTT replay + verify-callback override); "Zero external dependencies" → "Zero external **language** dependencies" (stdlib bridges to libssl/libc via fdlopen). |
| `module-manifest-design.md` | 2026-04-08 | 🟠 Read-through | `[deps]` + `[deps.stdlib]` design. Stable; verify at v5.10.x close. |
| `migration-strategy.md` | 2026-04-30 | 🟠 Read-through | Migration playbook for stdlib changes. Recently touched but pre-v5.10.21 TLS work. |
| `crash-localization.md` | 2026-04-13 | 🟠 Read-through | Crash-debugging playbook. Spot-check for v5.9.x / v5.10.x heap-map references. |
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

**Open question** — the agnosticos doc-health uses ADR-008 to cover its Cyrius pivot. Cyrius's own ADR series is steady at 6; no immediate gap. The originally-pinned v5.12.0 bare-metal kickoff was **retired at the 2026-05-12 tight-close** — bare-metal formalization + RISC-V rv64 moved to v6.2.x. Re-evaluate at the v6.0.0 cut (cc5 → cyc rename + first capability-expansion minor) if a major architectural decision lands without an ADR.

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

Per CLAUDE.md "Security Audit Process": next periodic security audit due before major releases. The v5.10.x close-out audit originally pinned here was **not run as a standalone artifact**; instead v5.11.41 shipped CVE-08 hardening (`cld` before `rep movsb`) per the 2026-04-13 audit's pinned P2 item. Remaining audit-pinned items: track against the v6.0.0 cut as the next natural full-audit boundary (major release, language-spec consolidation, cc5 → cyc rename).

---

## Tier 6 — Issues + Proposals (`docs/development/issues/`, `docs/development/proposals/`)

Open issues are tracked artifacts (filed by consumers or internal observation). Archived when resolved.

### Open issues
| File | Filed | Status |
|---|---|---|
| `issues/README.md` | varies | 🔵 Evergreen index |

**None currently open** — all 3 prior ledger-"open" issues (kernel-reserved-word / parser-cosmetic-limits / str-split-sep, all filed 2026-05-03) resolved during v5.11.x and `git mv`'d to `issues/archived/` per the close-to-archive memory pin. Consumer-filed issues continue to land in consumer repos (sandhi / mabda / kavach / kybernet / bote / daimon / agnosys etc.) and are referenced by absolute path in the cyrius roadmap entry.

**Repros subdir** (`issues/repros/`) — new during v5.11.x; binary + source repros parked separately from issue-text files. Currently holds: `sankoch-2.0.1-deflate-non-roundtrip.{bin,cyr}`. Treat as a repro storage area, not a tracked-file directory.

### Open proposals
| File | Last touched | Status |
|---|---|---|
| `proposals/2026-05-11-pie-support.md` | 2026-05-11 | 🔴 Open — pinned v6.1.x PIE codegen (in proposal body + roadmap-old.md v6.1.x section) |
| `proposals/cyrius-lsp-argv0-self-resolution.md` | 2026-05-02 | 🔴 Open — unpinned |

### Archived proposals
3 files in `proposals/archived/` (new subdir 2026-05-13 — caught during the same sweep; mirrors the `issues/archived/` close-to-archive pattern). All three were "shipped beyond what was asked":
- `2026-05-08-raise-return-cap.md` — shipped **v5.10.6** as 64 → 256 (proposal asked 64 → 128; Option B do-it-once).
- `2026-05-10-raise-compile-source-cap.md` — shipped **v5.11.33** as 2 MB → 8 MB (proposal asked 2 MB → 4 MB; sized for sandhi headroom into v6.x).
- `relax-uninitialized-var-or-improve-error.md` — shipped **v5.8.42** half (b) (mabda C1; improve-error option from the proposal; relax-parser option deliberately not taken).

### Archived issues
32 files in `issues/archived/` (+19 since scaffold). Verified frozen by design — each archived alongside its resolution (CHANGELOG entry that closed it). Growth driver: v5.11.x consumer-filed wave (bote/daimon/kavach/kybernet/mabda) + ELF user-bin cleanup at .32/.34 + CVE-08 hardening at .41 + PP cap raise at .33. Per the `feedback_close_to_archive_issues` memory pin: re-opens are a `git mv` back, not a re-file.

---

## Tier 7 — FFI / Reference (`docs/ffi/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `fncall-abi.md` | 2026-04-25 | ✅ Fresh (verified 2026-05-10) | Spot-verified at v5.10.35 — content scoped to `fncallN` (int-class scalar calls); the v5.10.28-32 typed-simd ABI (`fn f(): f64v2`) is a separate codegen path not invoked via `fncallN`, so no update needed here. (Future: a sibling `docs/ffi/typed-simd-abi.md` may earn its own slot if consumers need a reference.) |
| `struct-packing.md` | 2026-04-19 | 🟠 Read-through | Struct layout. Older; verify against current `parse_decl` struct emit. |

---

## Tier 8 — Archive (`docs/development/archive/`, `docs/development/issues/archived/`)

| Path | Count | Status |
|---|---|---|
| `docs/development/archive/` | 6 | 📦 Frozen — historical (cyml-format, handoff doc, v5.3.0 emitter, 2026-04 benchmarks/aarch64 stdlib, lsp-claude consolidation) |
| `docs/development/issues/archived/` | 32 | 📦 Frozen — resolved bugs (+19 since scaffold during v5.11.x consumer-filed wave + ELF/CVE/PP-cap cleanup) |
| `docs/development/proposals/archived/` | 3 | 📦 Frozen — shipped proposals (new dir 2026-05-13; raise-return-cap v5.10.6, raise-compile-source-cap v5.11.33, uninitialized-var error v5.8.42) |

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
| 1 | **Vidya sync per minor closeout** — `vidya/content/cyrius/*.cyml` (language, field_notes/{compiler,language}, implementation, types, dependencies, ecosystem) refreshed at every minor closeout per CLAUDE.md "Closeout Pass" step 11. Vidya entries reference cc-binary-name + version + non-obvious gotchas surfaced in the minor. | Every minor closeout | [`CLAUDE.md`](../CLAUDE.md) "Closeout Pass" §11 | Manual — `version-bump.sh` doesn't touch vidya. Cross-check version refs every closeout: vidya files saying `cc3 4.8.5` / `cc5 5.4.x` should match current VERSION. |
| 2 | **Periodic security audit** — full source scan for vulnerable patterns (sys_system / READFILE / bounds-check gaps / etc.) before major releases or after significant surface change. | Before each major release; cycle audit every 2-3 minors | [`CLAUDE.md`](../CLAUDE.md) "Security Audit Process" | Last full audit: 2026-04-13 + 2026-05-01 (pre-5.8.0). v5.11.41 shipped CVE-08 hardening piecemeal from the 2026-04-13 audit's P2 list. Next full audit pin: **before the v6.0.0 cut** (major release, cc5 → cyc rename, capability-expansion boundary). |
| 3 | **API surface snapshot regeneration** — `docs/api-surface.snapshot` regenerated as part of `check.sh`; gate fails if drift. | Every release | `cyrius_api_surface` binary; gate in [`scripts/check.sh`](../scripts/check.sh) | Already automated; included here for visibility. |

---

*Initial scaffold: 2026-05-10 (v5.10.34). First full stale sweep: 2026-05-13 (v5.11.42 — caught 13 patches of drift, 3 archived issues miscategorized as open, 2 untracked proposals, 1 untracked doc, 1 new audit, +19 archived issues, retired v5.12.x ADR-008 reference, v6.0.0 audit re-pin) + proposals-archive pass (caught 3 already-shipped proposals miscategorized as open: raise-return-cap v5.10.6, raise-compile-source-cap v5.11.33, uninitialized-var-error v5.8.42; created `proposals/archived/` subdir mirroring `issues/archived/`). Refresh in place when docs are touched.*
