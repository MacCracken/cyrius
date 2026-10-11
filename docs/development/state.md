# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.9 — in flight** (slot open 2026-10-11; 6.7.8 shipped 2026-10-11, tag `6.7.8` @ `e902f61c`, the store slot refreshed from the tag): **a repair batch** — a lane of quick fixes and a lane of the critical / high issues (user, 2026-10-11). |
| **cycc** | x86 **2,053,536 B** (`.text` **1,840,016**) at 6.7.8 (in flight), +133,136 B over 6.7.7's 1,920,400 B — checked dyn + C2. `build/cycc-native-aarch64` **1,881,144 B** (`cyrius pulsar`, 2026-10-11). Dead-code floor **52 fns / 10,597 B** (x86, unchanged). The pre-commit band is 3 MB since 6.7.8. |
| **Bootstrap / cross-OS** | 6.7.8: ecb · ach · cass · pi `SELFHOST_OK` + `LIBTEST_OK` on REAL hardware through `scripts/release-gate.sh` (on `b50fcf60`). seed **29,024 B** → cybs → cycc byte-identical; `build/cycc-native-aarch64` in lockstep (step 1b). |
| **Gates** | 6.7.8 `release-gate.sh` GREEN on the first run (2026-10-11, 11 min 46 s): check.sh 462 of 462 shell gates, 0 failed, the driver 131 of 131, the 2 named agnos-parity SKIPs. Bench: self_compile 1,768 ms on a loaded box; same-box A/B vs 6.7.7 +0.4 % on 6.7.7's source. |
| **Corpus** | **553** `.tcyr` (**259** in `crossos/`; `tests/tcyr/CORPUS_FLOOR` 503) · **106** `lib/*.cyr` · **85** `programs/*.cyr` · **458** shell gates under `tests/gates/<bucket>/` · api-surface **5,828** (DERIVED 2026-10-11) |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.6 (2026-10-07 → 10-08): A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` · W2 + Break 1. One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | 6.7.9 — choosing the two lanes' issues and the decisions they need. |
| **Next up** | **6.7.9** the repair batch · **6.7.10** B7 + P5-B · **6.7.11 – 6.7.13** Break 2 · **6.7.14** the full security audit + the refactor / optimization review · then what those reviews produce, and the closeout (its number open). Every placement shifted one on 2026-10-11. |
| **Open queue** | **118** open issues (2026-10-11): 6.7.10 2 · 6.7.11 **59** · 6.7.12 23 · 6.7.13 27 · 6.7.14 1 (shifted one 2026-10-11; 6.7.9 takes its lanes from these) · 5 placed arcs (open by design) — the backlog IS `issues/`; grouped in [issues/README.md](issues/README.md) § *Open queue* · **1** open proposal (P5 → 6.7.9). |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their W2 tags, refolded byte-identical in 6.7.6 — `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*. |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident (a stricter anti-downgrade floor; restore only if the old value was deliberate). |
