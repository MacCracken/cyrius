# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.13 — slot open 2026-10-15** (6.7.12 tagged at `97abbfec` and pushed by the user, store slot refreshed from the tag). 6.7.12: Break 2 repair 2, the platform release — 57 issues closed in five lanes, the fold bayan 1.6.0 (release gate GREEN on `2a4be9e0`). |
| **cycc** | x86 **2,299,144 B** in flight (6.7.13, both waves merged, 2026-10-16), +54,448 B over 6.7.12's 2,244,696 B. `build/cycc-native-aarch64` **2,151,872 B**. Dead-code floor **52 fns / 10,597 B** (x86, unchanged). |
| **Bootstrap / cross-OS** | 6.7.12: ecb · ach · cass · pi `SELFHOST_OK` + `LIBTEST_OK` on REAL hardware through `scripts/release-gate.sh` (on `2a4be9e0`; ecb / ach / pi now run the full corpus, D8). seed **29,024 B** → cybs → cycc byte-identical. |
| **Gates** | 6.7.12 `release-gate.sh` GREEN (2026-10-15): check.sh 522 of 522 shell gates, the driver 131 of 131, the 2 named agnos-parity SKIPs; ecb / ach / pi on the full corpus. self_compile 1,535 ms (A/B 6.7.11 1,503 → 6.7.12 1,536 ms). |
| **Corpus** | **611** `.tcyr` (**306** in `crossos/`) · **106** `lib/*.cyr` · **518** shell gates under `tests/gates/<bucket>/` · api-surface **5,857**. |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.12 (2026-10-07 → 10-15): A traits · C3 · B1 `const` + C1 · B2 `bool` · B3 · B5 + B8 · W2 + Break 1 (6.7.0 – 6.7.6) · B4 + B6 (6.7.7) · `dyn` + C2 (6.7.8) · the repair batch (6.7.9) · B7 + P5-B (6.7.10) · Break 2 repair 1 (6.7.11) · repair 2, the platform release (6.7.12). One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | **6.7.13** — Break 2, repair 3: struct values (slot opened 2026-10-15): 75 issues; wave 1 structs · multi-value (+ tools, the patra 1.16.3 patch — ⛔ the user tags it before the refold), wave 2 receives + closures · vectors; 45 decisions answered at the open (roadmap.md § 6.7.13). |
| **Next up** | **6.7.14** repair 4: generics, the frontend, infra (the heavier release, 103 placed; the IR arena's two-step) · **6.7.15** repair 5 (added 2026-10-16: what 6.7.14 files) · **6.7.16** the full security audit + the refactor / optimization review · then what those reviews produce, and the closeout (its number open) · the two proposals later in 6.7.x. |
| **Open queue** | **159** open issues (2026-10-15, at the 6.7.13 open: the three consumer / platform filings placed, the package question closed by decision): 6.7.13 75 · 6.7.14 74 · 6.7.15 2 · 5 placed arcs · 3 unplaced (the seed-rotation pair, sigil logging) — [issues/README.md](issues/README.md) § *Open queue* · **2** open proposals — later in the 6.7.x line. |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their tags — 6.7.12 refolded bayan 1.6.0 (6.7.11: sakshi 2.5.10, sankoch 2.8.7, patra 1.16.2), each byte-identical; `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*; patra's flock on Windows (6.7.13). |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | The 6.7.11 changes beyond the decisions' text — confirm or restore each, D10's flip side first ([issue](issues/archived/2026-10-14-6711-behaviour-changes-beyond-the-decisions-text.md)); a repeated global from `= 0` is silent ([issue](issues/archived/2026-10-14-redeclared-global-from-zero-is-silent-and-cross-fold-collisions-invisible.md)). Untracked in the tree since 2026-10-14, not committed by the 6.7.11 close: two consumer filings (`issues/2026-10-14-anuenue-growing-a-large-fn-segfaults-an-earlier-call.md`, `issues/archived/2026-10-14-args-init-truncates-argv-past-2-mib.md`) and a proposal (`proposals/2026-10-14-memmove.md`). The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident (a stricter anti-downgrade floor; restore only if the old value was deliberate). |
