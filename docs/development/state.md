# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.6 — SHIPPED 2026-10-08** (tag `6.7.6` @ `722bba93`; the store slot matches the tag): **Break 1** — the W2 refold (all twelve folds at their W2 tags), the high / critical backlog, `cyrius.cyml` git first + the test scope, `cyrius test <file\|dir>`, cybs stack arguments. |
| **cycc** | x86 **1,806,240 B** (`.text` **1,612,016**) at 6.7.6, +46,416 B over 6.7.5's 1,759,824 B. `build/cycc-native-aarch64` **1,601,032 B**. Dead-code floor **52 fns / 10,597 B** (x86). |
| **Bootstrap / cross-OS** | 6.7.6: ecb · ach · cass · pi `SELFHOST_OK` + `LIBTEST_OK` on REAL hardware through `scripts/release-gate.sh` (on `cd8e5b49`). seed **29,024 B** → cybs → cycc byte-identical; `build/cycc-native-aarch64` in lockstep (step 1b). |
| **Gates** | 6.7.6 `release-gate.sh` GREEN (2026-10-08, 9 min 21 s): check.sh 445 of 445 shell gates, 0 failed, the 2 named agnos-parity SKIPs. The first run was RED on ach alone (`crossos/regression_terminate_children.tcyr` timing — fixed in 6.7.7). Bench: self_compile 1,175 ms; same-box A/B vs 6.7.5 1,130 → 1,134 ms (+0.3 %). ⚠ With `TMPDIR` on tmpfs, check.sh is 444 / 445: `distlib_sidecar_host_independent.sh` axis 3 fails every run (pre-existing at the tag; passes with `TMPDIR` on disk) — fixed in 6.7.7. |
| **Corpus** | **537** `.tcyr` (**243** in `crossos/`; `tests/tcyr/CORPUS_FLOOR` 503) · **106** `lib/*.cyr` · **85** `programs/*.cyr` · **441** shell gates under `tests/gates/<bucket>/` · api-surface **5,828** (DERIVED 2026-10-08) |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.6 (2026-10-07 → 10-08): A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` · W2 + Break 1. One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | — |
| **Next up** | The remaining features — B4 tuples · B6 default / named arguments · B7 narrow struct fields · C2 bounds mode · checked `dyn` — then Break 2 and the closeout. |
| **Open queue** | **68** open issues (73 filed 2026-10-08; the five the merged 6.7.7 fixes closed are archived) — the backlog IS `issues/` since 2026-10-08 (the whole former roadmap backlog, premise-checked, plus what the 6.7.7 lanes found); grouped in [issues/README.md](issues/README.md) § *Open queue* · **1** open proposal (P5's execution half → C2). |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their W2 tags, refolded byte-identical in 6.7.6 — `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*. |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident (a stricter anti-downgrade floor; restore only if the old value was deliberate). |
