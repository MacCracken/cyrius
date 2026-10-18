# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.15 — slot open 2026-10-17** (6.7.14 tagged at `f1d6eb0a` and pushed by the user, store slot refreshed from the tag; the CLAUDE.md cross-OS lines 4c9bc5da followed it). 6.7.14: Break 2 repair 4, generics · the frontend · infra — 137 issues closed in nine lanes over three waves, the IR arena, the fold patra 1.16.4 (release gate GREEN on `1b0f84d4`, all four hosts on the full corpus). |
| **cycc** | x86 **2,496,552 B** (`.text` **2,271,944**) in flight at 6.7.15 (wave 1 merged), +63,040 B over 6.7.14's 2,433,512 B. `build/cycc-native-aarch64` **2,689,368 B** (the TypeScript front end on every compiler, D38). Dead-code floor **52 fns / 10,597 B** (x86, unchanged). |
| **Bootstrap / cross-OS** | 6.7.14: ecb · ach · cass · pi `SELFHOST_OK` + `LIBTEST_OK` on the FULL corpus (cass joined `CO_FULL_HOSTS` this release), REAL hardware through `scripts/release-gate.sh` (on `1b0f84d4`). seed **29,024 B** → cybs → cycc byte-identical. |
| **Gates** | 6.7.14 `release-gate.sh` GREEN (2026-10-17, on `1b0f84d4`): check.sh 554 / 554 shell gates, the driver 131 / 131, the 2 named agnos-parity SKIPs; all four hosts on the full corpus. self_compile 1,770 ms (A/B 6.7.13 1,585 → 6.7.14 1,772 ms, +11.8 %; same input +2.0 %). |
| **Corpus** | **642** `.tcyr` (**335** in `crossos/`) · **106** `lib/*.cyr` · **550** shell gates under `tests/gates/<bucket>/` · api-surface **5,891**. |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.14 (2026-10-07 → 10-17): A traits · C3 · B1 `const` + C1 · B2 `bool` · B3 · B5 + B8 · W2 + Break 1 (6.7.0 – 6.7.6) · B4 + B6 (6.7.7) · `dyn` + C2 (6.7.8) · the repair batch (6.7.9) · B7 + P5-B (6.7.10) · Break 2 repair 1 (6.7.11) · repair 2, the platform release (6.7.12) · repair 3, struct values (6.7.13) · repair 4, generics · the frontend · infra (6.7.14). One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | **6.7.15** — Break 2, repair 5 (slot opened 2026-10-17): 111 issues in seven lanes over four waves (wave 0 on main: the check driver's SIGPIPE, the `parse_fn.cyr` split; wave 1 generics · frontend · infra / tools · platform; wave 2 structs · vectors; wave 3 receives); 70 decisions answered at the open, 2026-10-18 (roadmap.md § 6.7.15) — the 6.7.14 changes beyond the decisions' text closed by them; ProtectedRoots re-placed to 6.7.16. |
| **Next up** | **6.7.15** repair 5 (in flight: wave 1 merged, wave 2 running) · **6.7.16** Break 2 repair 6 — what 6.7.15 files (added 2026-10-18, the user) and the ProtectedRoots measurement · **6.7.17** the full security audit + the refactor / optimization review · then what those reviews produce, and the closeout (its number open) · the two proposals later in 6.7.x. |
| **Open queue** | **175** open issues (2026-10-18, at the 6.7.15 wave-1 integration): 6.7.15 113 · 6.7.16 52 · 6.7.17 2 · placed arcs and the unplaced (the seed-rotation pair, sigil logging) — [issues/README.md](issues/README.md) § *Open queue* · **2** open proposals — later in the 6.7.x line. |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their tags — 6.7.14 refolded patra 1.16.4 (6.7.13: patra 1.16.3, bayan 1.9.0, sandhi 1.13.1), each byte-identical; `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*; patra's suite on Windows (its `/dev/null` and `/tmp` fixtures, 6.7.14). |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | ⛔ Tag patra 1.16.5 when the 6.7.15 platform lane's suite patch is ready (before the refold). The Windows ProtectedRoots flag-1 measurement waits on the user's two steps at cass's desktop ([issue](issues/2026-10-15-windows-protectedroots-flag1-user-root-unverified.md), 6.7.16). The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident. |
