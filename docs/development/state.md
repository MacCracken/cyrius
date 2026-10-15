# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.12 — slot open 2026-10-15** (6.7.11 tagged at `99c681d2` and pushed by the user, store slot refreshed from the tag). 6.7.11: Break 2 repair 1 — 71 issues closed in seven lanes over two waves, the folds sakshi 2.5.10 / sankoch 2.8.7 / patra 1.16.2 (release gate GREEN on `0601aff4`). |
| **cycc** | x86 **2,223,320 B** (`.text` **2,003,672**) at 6.7.11, +108,944 B over 6.7.10's 2,114,376 B. `build/cycc-native-aarch64` **2,083,752 B**. Dead-code floor **52 fns / 10,597 B** (x86, unchanged). |
| **Bootstrap / cross-OS** | 6.7.11: ecb · ach · cass · pi `SELFHOST_OK` + `LIBTEST_OK` on REAL hardware through `scripts/release-gate.sh` (on `0601aff4`). seed **29,024 B** → cybs → cycc byte-identical. |
| **Gates** | 6.7.11 `release-gate.sh` GREEN (2026-10-14; a first run on `315d5e4a` stopped to fold patra 1.16.2): check.sh 503 of 503 shell gates, the driver 131 of 131, the 2 named agnos-parity SKIPs. self_compile 1,526 ms (A/B 6.7.10 1,437 → 6.7.11 1,514 ms). |
| **Corpus** | **589** `.tcyr` (**291** in `crossos/`) · **106** `lib/*.cyr` · **499** shell gates under `tests/gates/<bucket>/` · api-surface **5,850**. |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.11 (2026-10-07 → 10-14): A traits · C3 · B1 `const` + C1 · B2 `bool` · B3 · B5 + B8 · W2 + Break 1 (6.7.0 – 6.7.6) · B4 + B6 (6.7.7) · `dyn` + C2 (6.7.8) · the repair batch (6.7.9) · B7 + P5-B (6.7.10) · Break 2 repair 1 (6.7.11). One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | **6.7.12** — Break 2, repair 2, the platform release (slot opened 2026-10-15): the open queue re-triaged and re-balanced across 6.7.12 / 6.7.13 at the open; fix first (the user, 2026-10-14): the `WS_*` tie (yantra's `cyrius distlib`), the x86_64 `*V` regression, the changes beyond the 6.7.11 decisions' text. |
| **Next up** | **6.7.12 – 6.7.13** Break 2 (repair) · **6.7.14** the full security audit + the refactor / optimization review · then what those reviews produce, and the closeout (its number open). |
| **Open queue** | **166** open issues (2026-10-14, at the 6.7.11 close: 71 archived, 95 filed): 6.7.12 117 · 6.7.13 31 · 6.7.14 2 · 5 placed arcs (open by design) · 11 unplaced (the user places them) — the backlog IS `issues/`; [issues/README.md](issues/README.md) § *Open queue* · **1** open proposal (adjacent string-literal concatenation, filed 2026-10-13). |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their tags — 6.7.11 refolded sakshi 2.5.10, sankoch 2.8.7 (2.8.6's `_bre_err` was niyama's global too) and patra 1.16.2, each byte-identical; `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*. |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | The 6.7.11 changes beyond the decisions' text — confirm or restore each, D10's flip side first ([issue](issues/2026-10-14-6711-behaviour-changes-beyond-the-decisions-text.md)); a repeated global from `= 0` is silent ([issue](issues/2026-10-14-redeclared-global-from-zero-is-silent-and-cross-fold-collisions-invisible.md)). Untracked in the tree since 2026-10-14, not committed by the 6.7.11 close: two consumer filings (`issues/2026-10-14-anuenue-growing-a-large-fn-segfaults-an-earlier-call.md`, `issues/2026-10-14-args-init-truncates-argv-past-2-mib.md`) and a proposal (`proposals/2026-10-14-memmove.md`). The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident (a stricter anti-downgrade floor; restore only if the old value was deliberate). |
