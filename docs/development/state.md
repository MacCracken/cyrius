# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.10 — release gate GREEN 2026-10-13** (on `5eb7fb3c`; the user tags and pushes, then `sh scripts/install.sh --refresh-only` at the tagged commit): **B7** packed narrow fields + the handle line + size-independent struct copies, **P5-B** execution coverage, the 6.7.9 fold wave refolded. |
| **cycc** | x86 **2,114,376 B** (`.text` **1,900,296**) at 6.7.10, +56,640 B over 6.7.9's 2,057,736 B. `build/cycc-native-aarch64` **1,950,240 B**. Dead-code floor **52 fns / 10,597 B** (x86, unchanged). |
| **Bootstrap / cross-OS** | 6.7.10: ecb · ach · cass · pi `SELFHOST_OK` + `LIBTEST_OK` on REAL hardware through `scripts/release-gate.sh` (on `5eb7fb3c`; cass also ran P5-B's coverage step). seed **29,024 B** → cybs → cycc byte-identical. |
| **Gates** | 6.7.10 `release-gate.sh` GREEN (2026-10-13, the second run — the first went RED on 78 "Disk quota exceeded" writes from the shared per-user `/tmp` quota; re-run with `TMPDIR` on disk): check.sh 478 of 478 shell gates, the driver 131 of 131, the 2 named agnos-parity SKIPs. self_compile 1,529 ms (A/B 6.7.9 1,441 → 6.7.10 1,504 ms). |
| **Corpus** | **573** `.tcyr` (**276** in `crossos/`) · **106** `lib/*.cyr` · **474** shell gates under `tests/gates/<bucket>/` · api-surface **5,838**. |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.6 (2026-10-07 → 10-08): A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` · W2 + Break 1. One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | **6.7.11** — Break 2, repair 1 (slot opened 2026-10-13): the placed 6.7.11 queue, the agnos filings, the newly filed high items, the sankoch 2.8.6 refold. 6.7.10 tagged at `7c97af24`, store slot refreshed from the tag. |
| **Next up** | **6.7.11 – 6.7.13** Break 2 (repair) · **6.7.14** the full security audit + the refactor / optimization review · then what those reviews produce, and the closeout (its number open). |
| **Open queue** | **137** open issues (2026-10-13, after 6.7.10: 6 archived, 42 filed — the doc sweep's verifiers, the refolds, the lanes and their reviews, 8 consumer filings): 6.7.11 60 · 6.7.12 25 · 6.7.13 33 · 6.7.14 2 · 6 placed arcs (open by design) · 11 unplaced (the user places them) — the backlog IS `issues/`; [issues/README.md](issues/README.md) § *Open queue* · **0** open proposals (P5 closed by P5-B). |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their W2 tags, refolded byte-identical in 6.7.6 — `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*. |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident (a stricter anti-downgrade floor; restore only if the old value was deliberate). |
