# Cyrius — Current State

> **State** (volatile): a snapshot of where the project is, refreshed **by hand** at every release
> (`version-bump.sh` does not touch this file; its closing summary names the rows to update). No per-release narrative
> (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)), no backlog ([`roadmap.md`](roadmap.md); the minors after it in
> [`roadmap_6.md`](roadmap_6.md); unpinned items in [`roadmap-future.md`](roadmap-future.md)). [`CLAUDE.md`](../../CLAUDE.md)
> holds the durable rules and procedures.

## Current state

| | |
|---|---|
| **Version** | **6.7.14 — slot open 2026-10-16** (6.7.13 tagged at `19a7ae21` and pushed by the user, store slot refreshed from the tag). 6.7.13: Break 2 repair 3, struct values — 76 issues closed in six lanes over two waves, the folds patra 1.16.3 / bayan 1.9.0 / sandhi 1.13.1 (release gate GREEN on `29e4f0a9`). |
| **cycc** | x86 **2,416,968 B** in flight (6.7.14, waves 1 and 2 merged, 2026-10-17), +117,824 B over 6.7.13's 2,299,144 B. `build/cycc-native-aarch64` **2,285,760 B**. Dead-code floor **52 fns / 10,597 B** (x86, unchanged). |
| **Bootstrap / cross-OS** | 6.7.13: ecb · ach · pi `SELFHOST_OK` + `LIBTEST_OK` on the full corpus, cass on `tests/tcyr/crossos`, REAL hardware through `scripts/release-gate.sh` (on `29e4f0a9`). seed **29,024 B** → cybs → cycc byte-identical. |
| **Gates** | 6.7.13 `release-gate.sh` GREEN (2026-10-16, on `29e4f0a9`): check.sh 527 / 527 shell gates, the driver 131 / 131, the 2 named agnos-parity SKIPs; ecb / ach / pi on the full corpus. self_compile 1,600 ms (A/B 6.7.12 1,524 → 6.7.13 1,603 ms; same input +1.1 %). |
| **Corpus** | **624** `.tcyr` (**318** in `crossos/`) · **106** `lib/*.cyr` · **523** shell gates under `tests/gates/<bucket>/` · api-surface **5,888**. |
| **Active minor** | **v6.7.x** — the LANGUAGE minor (opened 6.7.0, 2026-10-07; v6.6.x closed at 6.6.20). Spec and sequence: [roadmap.md](roadmap.md). |
| **Shipped this minor** | 6.7.0 – 6.7.13 (2026-10-07 → 10-16): A traits · C3 · B1 `const` + C1 · B2 `bool` · B3 · B5 + B8 · W2 + Break 1 (6.7.0 – 6.7.6) · B4 + B6 (6.7.7) · `dyn` + C2 (6.7.8) · the repair batch (6.7.9) · B7 + P5-B (6.7.10) · Break 2 repair 1 (6.7.11) · repair 2, the platform release (6.7.12) · repair 3, struct values (6.7.13). One line each: [completed-phases.md](completed-phases.md) § *v6.7.x*. |
| **In-flight** | **6.7.14** — Break 2, repair 4: generics, the frontend, infra — the heavier release (slot opened 2026-10-16): 137 issues in nine lanes over three waves (wave 1 infra — the IR arena first — · generics · frontend · tools · platform; wave 2 structs · receives + multi-value · stdlib; wave 3 vectors); 61 decisions answered at the open (roadmap.md § 6.7.14); ProtectedRoots moved to 6.7.15 (the cass desktop step); ⛔ patra 1.16.4 for the user to tag mid-release. |
| **Next up** | **6.7.14** repair 4: generics, the frontend, infra — the heavier release (139 placed: its own, what 6.7.12 and 6.7.13 filed; the IR arena's two-step; the seven 6.7.13 changes beyond the decisions' text asked at its open) · **6.7.15** repair 5 (what 6.7.14 files) · **6.7.16** the full security audit + the refactor / optimization review · then what those reviews produce, and the closeout (its number open) · the two proposals later in 6.7.x. |
| **Open queue** | **149** open issues (2026-10-16, at the 6.7.13 close): 6.7.14 139 · 6.7.15 0 · 6.7.16 2 · placed arcs and the unplaced (the seed-rotation pair, sigil logging) — [issues/README.md](issues/README.md) § *Open queue* · **2** open proposals — later in the 6.7.x line. |
| **Security ledger** | `docs/audit/2026-10-08-security-ledger.md`; the next id is **CYRIUS-2026-0036** (spent only for an actual security vulnerability, in the commit that records it). Last full audit: `docs/audit/2026-09-03-security-audit.md` (cycc 6.5.45). |
| **Folded stdlibs** | All twelve at their tags — 6.7.13 refolded patra 1.16.3, bayan 1.9.0 and sandhi 1.13.1 (6.7.12: bayan 1.6.0), each byte-identical; `docs/ecosystem.md`'s fold rows name each tag. Open follow-ups: roadmap.md § *Folded-stdlib follow-ups*; patra's suite on Windows (its `/dev/null` and `/tmp` fixtures, 6.7.14). |
| **Consumers** | Not tracked here (CLAUDE.md top rule). A consumer adopts a release at its own pin bump through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md); its follow-ups live in its own roadmap (the last ones cyrius carried were moved there 2026-10-08). |
| **Open decisions for the user** | The Windows ProtectedRoots flag-1 measurement waits on the user's interactive step at cass's desktop ([issue](issues/2026-10-15-windows-protectedroots-flag1-user-root-unverified.md), 6.7.15). The self_compile budget and the growth-tax audit (the later performance track; roadmap.md *Open questions*). The 16 store slots with a stale `bin/cybs` (`verify-store.sh --restore <v>` writes the live store). `~/.cyrius/signed-since` reads 6.6.10 since the 6.6.12 installer incident (a stricter anti-downgrade floor; restore only if the old value was deliberate). |
