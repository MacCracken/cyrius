# README.md's list of fold versions is stale for six folds, and no gate ties it to `lib/`'s `# Version:` headers — RESOLVED

> ✅ **RESOLVED in v6.7.12** (LIB-6, `16b81bf2`: README.md's fold-version paragraph is rewritten from the twelve `# Version:` headers — seven pairs were stale by then (sakshi, patra, sigil, yukti, sankoch, bayan, yantra; patra 1.16.2 and sankoch 2.8.7 were folded after the filing) — and `fold_table_matches_vendored.sh` gains axis 4: each `<name> <X.Y.Z>` pair must be a `docs/ecosystem.md` fold row equal to `lib/<name>.cyr`'s header, and every fold row must have a pair. The filing's mutation (sankoch back to 2.8.3) is RED, as are a dropped pair, a non-fold pair, a reworded opening and the slot-open README. No decision needed. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 stdlib lane tree (`338fabc0`) and on `main` (`2fdf66b4`).
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13, the 6.7.11 stdlib lane's review of `923f187f` (the sankoch 2.8.6 refold). The reviewer counted five stale folds. The fix step re-checked all twelve and found a sixth, yantra.
**Severity:** Low — docs only, and nothing compiles from it. But the paragraph says it reports what `lib/` carries, so it misleads anyone choosing a pin from the README.
**Affects:** `README.md`, the § Standard Library paragraph ("The twelve folded sibling libraries, at the versions `lib/` carries (each file's `# Version:` header)", ~line 241–247).

## Summary

The README lists a version for each folded stdlib and says each one comes from that file's
`# Version:` header. Six of the twelve entries no longer match the headers. Four have been stale
since the 6.7.10 folds, and the 6.7.11 folds add two more. `fold_table_matches_vendored` compares
`docs/ecosystem.md` with `lib/` and nothing else, so no gate catches the README drifting.

## Reproduction

```
$ for f in sakshi patra sigil vani yukti sankoch sandhi niyama mabda bayan ganita yantra; do
    printf "%-8s lane=%s main=%s\n" $f "$(sed -n 2p lib/$f.cyr | sed 's/# Version: //')" \
      "$(git show main:lib/$f.cyr | sed -n 2p | sed 's/# Version: //')"; done
sakshi   lane=2.5.9 main=2.5.10
patra    lane=1.16.0 main=1.16.0
sigil    lane=3.13.12 main=3.13.12
vani     lane=1.2.10 main=1.2.10
yukti    lane=2.3.17 main=2.3.17
sankoch  lane=2.8.6 main=2.8.3
sandhi   lane=1.10.9 main=1.10.9
niyama   lane=1.1.0 main=1.1.0
mabda    lane=4.2.0 main=4.2.0
bayan    lane=1.5.14 main=1.5.14
ganita   lane=1.2.15 main=1.2.15
yantra   lane=1.0.11 main=1.0.11
$ sed -n 241,247p README.md
The twelve folded sibling libraries, at the versions `lib/` carries
(each file's `# Version:` header): sakshi 2.5.8 (tracing) · patra 1.16.0
(storage) · sigil 3.13.11 (security / crypto) · vani 1.2.10 (audio) ·
yukti 2.3.16 (hardware) · sankoch 2.8.3 (compression) · sandhi 1.10.9
(HTTP/2, JSON-RPC, TLS policy) · niyama 1.1.0 (regex) · mabda 4.2.0
(GPU / compute) · bayan 1.5.13 (data formats + big-int) · ganita 1.2.15
(linear algebra + advanced math) · yantra 1.0.10 (UI / E2E testing).
```

The stale entries, with what the README says and what `lib/` carries once 6.7.11's folds are
integrated:

| Fold | README says | `lib/` carries |
|---|---|---|
| sakshi | 2.5.8 | 2.5.10 (main, `2fdf66b4`) |
| sigil | 3.13.11 | 3.13.12 |
| yukti | 2.3.16 | 2.3.17 |
| sankoch | 2.8.3 | 2.8.6 (the 6.7.11 stdlib lane, `923f187f`) |
| bayan | 1.5.13 | 1.5.14 |
| yantra | 1.0.10 | 1.0.11 |

## Root cause

The list is maintained by hand, and no fold checklist or gate mentions it. The
fold-table gate (`fold_table_matches_vendored`) checks `docs/ecosystem.md` only.

## Fix

1. Rewrite the paragraph from the twelve `# Version:` headers.
2. Do one of the following, so it cannot drift again:
   - Extend `fold_table_matches_vendored` (or add a sibling row) to parse the README paragraph
     and compare each `<name> <version>` with `lib/<name>.cyr`'s header.
   - Remove the version numbers from the README and point to `docs/ecosystem.md`, which is
     gated.

## Acceptance

- The README matches every fold's `# Version:` header.
- If the gate option is taken: a mutation (the README set back to sankoch 2.8.3) turns that gate
  RED.
