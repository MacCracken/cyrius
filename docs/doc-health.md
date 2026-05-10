---
name: Cyrius Documentation Health
description: Living state of doc currency in the cyrius repo — fresh / stale / archived / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — cyrius

> **Last refresh**: 2026-05-10 (initial scaffold at v5.10.34; threat-model + fncall-abi spot-review at v5.10.35) | **Refresh cadence**: when docs are touched, update the affected row.
> **Scope**: This repo only (`cyrius`) — the entire `docs/` tree plus root-level files (README, CHANGELOG, CLAUDE.md, VERSION). Per-stdlib-dep docs live in their own repos and are not audited here. Cross-repo cycle / pin / sweep state lives in [`development/state.md`](development/state.md), not here.
>
> **Convention adopted from agnosticos** (2026-05-10): pattern from `agnosticos/docs/doc-health.md`. Per `first-party-documentation.md` codification, smaller repos can adopt the same shape. Cyrius's tree is ~61 markdown files (vs agnosticos's ~265) so the tier structure here is leaner.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change.

---

## At a glance — 2026-05-10 inventory

**~61 markdown files** across the repo. Bucket counts (initial scaffold pass — classification by filename + git dates + spot-checks; full per-tier audit pending):

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / touched in current cycle** | ~27 | Touched within the v5.10.x cycle (2026-04 to 2026-05); state.md / roadmap.md / CHANGELOG / completed-phases / cyrius-guide / tutorial / faq / stdlib-reference / benchmarks / ecosystem / editor-integration / platform-status / 6 ADRs / 4 audits / open-issues + proposals / a few dev/* docs / **threat-model (v5.10.35 refresh)** / **fncall-abi (v5.10.35 verified)** |
| 🟡 **Stale — refresh in place** | 0 | Cleared during scaffold — no known wrong content. (Drift candidates flagged 🟠 below.) |
| 🟠 **Read-through outstanding** | ~13 | Older dev/* docs (process-notes, module-manifest-design, migration-strategy, crash-localization), older architecture docs (package-format), older FFI docs (struct-packing) — all dated 2026-04-08 to 2026-04-30; not known to be wrong, but unreviewed against v5.10.x reality. |
| 🔵 **Probably evergreen** | ~3 | ADR-002/-003/-004 (everything-is-i64, fixed-heap-layout, convention-based-dispatch) — load-bearing principles; re-read pass quarterly, not weekly. |
| 📦 **Archive — frozen by design** | ~18 | `docs/development/archive/` (6) + `docs/development/issues/archived/` (~13). Verified — frozen by design. |
| ❓ **Open strategic question** | 0 | None at scaffold time. |

Numbers approximate; rolls up from the per-tier tables below.

**Why now**: doc-health convention adopted at v5.10.34 alongside the sandhi 1.3.2 TLS unblocker. The cyrius doc tree has been actively maintained (CHANGELOG is canonical per CLAUDE.md, state.md refreshes every release, vidya sync at every minor closeout) but the *aggregate* currency has no surface — this file is that surface.

---

## Tier 1 — Structural docs (root + `/docs` root)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | varies | ✅ Fresh | Top-level project README; refreshed across the v5.10.x cycle. |
| `CHANGELOG.md` | 2026-05-10 | ✅ Fresh | **Source of truth per CLAUDE.md.** New v5.10.33 entry just landed (typed-simd ABI Phase 6 partial). Refreshed every release. |
| `CLAUDE.md` | 2026-05-10 | ✅ Fresh | Process + procedures + project-identity. Volatile state delegated to state.md per its own principle. |
| `VERSION` | 2026-05-10 | ✅ Fresh | Single source of truth for version (`5.10.33` at last edit). Bumped via `scripts/version-bump.sh`. |
| `docs/cyrius-guide.md` | 2026-05-03 | ✅ Fresh | Complete language reference. Last touched in the early-v5.10.x doc-audit pass; spot-check at next minor closeout. |
| `docs/tutorial.md` | 2026-05-03 | ✅ Fresh | User-facing onboarding. Same provenance as cyrius-guide. |
| `docs/faq.md` | 2026-05-05 | ✅ Fresh | Refreshed during v5.10.x cycle. |
| `docs/stdlib-reference.md` | 2026-05-03 | ✅ Fresh | API surface reference. Mirrors `docs/api-surface.snapshot` regeneration cadence. |
| `docs/benchmarks.md` | 2026-05-03 | ✅ Fresh | User-facing benchmarks summary. Matches `docs/development/benchmarks.md` historical baseline. |
| `docs/ecosystem.md` | 2026-05-06 | ✅ Fresh | Stdlib + downstream-consumer map. Refreshed at niyama-fold ship. |
| `docs/editor-integration.md` | 2026-05-02 | ✅ Fresh | LSP + editor configs. |
| `docs/size-comparisons.md` | 2026-05-03 | ✅ Fresh | cc5 vs gcc/clang/rustc binary size table. |
| `docs/platform-status.md` | 2026-05-10 | ✅ Fresh | **Just refreshed** (2026-05-10 cass/ecb anti-confusion sweep). Per-target status table. |
| `docs/api-surface.snapshot` | 2026-05-10 | ✅ Fresh | Generated artifact (not hand-written). Regenerated at every release; gate in `check.sh`. |

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
| `state.md` | 2026-05-10 | ✅ Fresh | **Rotates every release.** v5.10.x cycle state. Just refreshed at v5.10.33 ship. |
| `roadmap.md` | 2026-05-10 | ✅ Fresh | **Rotates every release.** Slot pinning + cascade tracking. Just restructured at v5.10.33 ship: .34–.38 SIMD-deferral pins + .34 TLS early-data + cascaded .39–.45. |
| `completed-phases.md` | 2026-05-08 | ✅ Fresh | Historical release narrative. Per CLAUDE.md, this is where shipped-cycle summaries land at minor closeout. |
| `benchmarks.md` | 2026-04-25 | 🟠 Read-through | Per-release benchmark history. v5.10.x rows pending — refresh at minor closeout (typically lands as the "Post-audit benchmarks" P(-1) step). |
| `process-notes.md` | 2026-04-12 | 🟠 Read-through | Process discipline / agent feedback log. ~4 weeks old; spot-check for stale references. |
| `threat-model.md` | 2026-05-10 | ✅ Fresh | **Refreshed 2026-05-10 (v5.10.35)**: added fdlopen-helper + libssl trust boundaries; CVE-02 path-traversal mitigation note; stdlib TLS surface table (v5.6.37 / v5.10.21 / v5.10.27 / v5.10.34 + security caveats for 0-RTT replay + verify-callback override); "Zero external dependencies" → "Zero external **language** dependencies" (stdlib bridges to libssl/libc via fdlopen). |
| `module-manifest-design.md` | 2026-04-08 | 🟠 Read-through | `[deps]` + `[deps.stdlib]` design. Stable; verify at v5.10.x close. |
| `migration-strategy.md` | 2026-04-30 | 🟠 Read-through | Migration playbook for stdlib changes. Recently touched but pre-v5.10.21 TLS work. |
| `crash-localization.md` | 2026-04-13 | 🟠 Read-through | Crash-debugging playbook. Spot-check for v5.9.x / v5.10.x heap-map references. |

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

**Open question** — the agnosticos doc-health uses ADR-008 to cover its Cyrius pivot. Cyrius's own ADR series is steady at 6; no immediate gap. Re-evaluate at v5.11.0 if a major architectural decision (bare-metal kickoff at v5.12.0?) lands without an ADR.

---

## Tier 5 — Audits (`docs/audit/`)

Periodic audit reports; per-audit timestamped (don't refresh in place — supersede with a new audit doc).

| File | Last touched | Status |
|---|---|---|
| `2026-04-13-security-audit.md` | 2026-04-13 | 🔵 Dated artifact |
| `2026-04-26-stdlib-fn-collisions.md` | 2026-04-26 | 🔵 Dated artifact |
| `2026-04-27-cx-direct-emit-inventory.md` | 2026-04-26 | 🔵 Dated artifact |
| `2026-05-01-pre-5.8.0-audit.md` | 2026-05-01 | 🔵 Dated artifact |

Per CLAUDE.md "Security Audit Process": next periodic security audit due before major releases or significant changes. v5.10.x has had measurable surface change (TLS expansion at .21 + .27 + .34, value-type ABI at .28-.38, doc-health convention at .34). Consider scheduling a v5.10.x close-out security audit before the v5.11.0 cut.

---

## Tier 6 — Issues + Proposals (`docs/development/issues/`, `docs/development/proposals/`)

Open issues are tracked artifacts (filed by consumers or internal observation). Archived when resolved.

### Open issues
| File | Filed | Status |
|---|---|---|
| `issues/2026-05-03-kernel-reserved-word-misleading-diagnostic.md` | 2026-05-03 | 🔴 Open |
| `issues/2026-05-03-parser-cosmetic-limits-bare-return-and-var-bracket.md` | 2026-05-03 | 🔴 Open |
| `issues/2026-05-03-str-split-sep-treated-as-pointer.md` | 2026-05-03 | 🔴 Open |
| `issues/README.md` | varies | 🔵 Evergreen index |

**Note on consumer-filed issues outside this tree**: `sandhi/docs/issues/2026-05-10-stdlib-tls-early-data-status.md` is the v5.10.34 driver — filed in sandhi, not here. Per the v5.10.x convention, consumer filings live in the consumer repo and are referenced by absolute path in the cyrius roadmap entry.

### Open proposals
| File | Last touched | Status |
|---|---|---|
| `proposals/2026-05-08-raise-return-cap.md` | 2026-05-08 | 🔴 Open (relates to v5.10.6 ✅ shipped raise — verify framing) |
| `proposals/cyrius-lsp-argv0-self-resolution.md` | varies | 🔴 Open |
| `proposals/relax-uninitialized-var-or-improve-error.md` | varies | 🔴 Open |

### Archived issues
13 files in `issues/archived/` — verified frozen by design. Each archived alongside the resolution (CHANGELOG entry that closed it).

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
| `docs/development/issues/archived/` | 13 | 📦 Frozen — resolved bugs |

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
| 2 | **Periodic security audit** — full source scan for vulnerable patterns (sys_system / READFILE / bounds-check gaps / etc.) before major releases or after significant surface change. | Before each major release; cycle audit every 2-3 minors | [`CLAUDE.md`](../CLAUDE.md) "Security Audit Process" | Last full audit: 2026-04-13 + 2026-05-01 (pre-5.8.0). Current cycle should produce a v5.10.x close-out audit before v5.11.0. |
| 3 | **API surface snapshot regeneration** — `docs/api-surface.snapshot` regenerated as part of `check.sh`; gate fails if drift. | Every release | `cyrius_api_surface` binary; gate in [`scripts/check.sh`](../scripts/check.sh) | Already automated; included here for visibility. |

---

*Initial scaffold: 2026-05-10 (v5.10.34). Refresh in place when docs are touched.*
