# Converge (or retire) cycc's `_check_shadow_lib` sentinel note — now redundant, and silently wrong — RESOLVED

**Status:** ✅ **RESOLVED in v6.4.66** (option **(a) retire**; CHANGELOG [6.4.66]). **Filed:** 2026-07-14 (v6.4.63 slot close).
**Severity:** Low (correctness of a diagnostic, not of codegen). **Owner surface:** `src/frontend/lex.cyr`.

> **RESOLVED v6.4.66 — retired (option a).** Removed `_check_shadow_lib` + `_file_size`
> (~80 lines) from `src/frontend/lex.cyr`; the CLI wrapper's `_check_lib_freshness`
> (cbt/, v6.4.63) supersedes it. cycc self-host fixpoint + seed-derive green; differential
> codegen-diff 0; `CYRIUS_NO_WARN_SHADOW_LIB` still honored by the wrapper; cycc −88 B net
> (with the getpeername reroute in the same release).

## Context

v6.4.63 added a version-aware lib-freshness check to the CLI wrapper (`cbt/commands.cyr`
`_check_lib_freshness`), which names per-lib version skew and fires on every
`cyrius build|run|test|bench|check`. That supersedes cycc's older note for the sanctioned
consumer path. The old note was deliberately left in place for that release — it lives in
`src/frontend/lex.cyr`, so touching it changes cycc's bytes and pulls in the seed-derive +
cross-OS gates for what is a cosmetic cleanup. v6.4.63 kept cycc **byte-identical**.

## What's wrong with the note as it stands

`_check_shadow_lib` (`src/frontend/lex.cyr:361-441`) + `_file_size` (`:446`):

1. **Silent false negative.** It byte-SIZE-compares ONE hardcoded sentinel (`lib/alloc.cyr`)
   and `return 0`s when the sizes match (`:434`). A `lib/` whose sigil is three minor versions
   stale but whose `alloc.cyr` happens to be unchanged produces **no note at all**. Reproduced
   by forging that state. The sentinel and the risk are uncorrelated: `alloc.cyr` is stable core
   cyrius, while the folded deps version independently (sigil went 3.10.0→3.11.1 *within* 6.4.x).
   The v5.11.57 trade-off (CHANGELOG:16955-16988) called this corner case "rare enough to accept";
   it is the exact case the yeo-cy-test filing was about.
2. **Names nothing.** When it does fire it reports only the path, and advises "delete ./lib/" —
   which is not the remedy (`cyrius lib sync --full` is).
3. **Linux-HOST-only.** The `#ifdef CYRIUS_TARGET_LINUX` keys on the compiler's *host* OS, not
   the emit target — so it is compiled out of macOS-/Windows-/agnos-hosted cycc entirely, and
   present in Linux-hosted `cycc_cx` regardless of target.
4. **Redundant + contradictory** with the wrapper's warning for anyone using `cyrius build`:
   two messages about one condition, one of which is vague and sometimes absent.

## Options (decide at pickup)

- **(a) Retire it.** Delete `_check_shadow_lib` + `_file_size` (sole caller is
  `_init_cyrius_lib`; confirm `_file_size` has no other user). Removes ~80 lines from cycc's
  frontend, shrinks the binary, and kills a cybs-ceiling liability (the fn is already ~80 lines
  with heavy global/call refs). Cost: raw `cycc` invocations lose the signal — acceptable per
  CLAUDE.md ("never raw `cat | cycc` for projects"; it is for compiler-internal self-host).
- **(b) Converge it.** Keep a note in cycc but make it version-aware — needs inline
  `getdents64` + a header parser in the frontend, and 3 more per-OS enumerations to close the
  host gap. Materially more work for a diagnostic the wrapper already emits better.

**Recommendation: (a).** The wrapper is the consumer entry point and now covers all four hosts.

## Acceptance criteria

- cycc emits no shadow-lib note; `_check_shadow_lib`/`_file_size` gone (or converged per (b)).
- `CYRIUS_NO_WARN_SHADOW_LIB` still honored by the wrapper check (it is, `cbt/`) — and the
  `scripts/agnos-crossbuild-gate.sh` agnoshi leg, which sets it, stays green.
- cycc self-host fixpoint + **seed-derive** (`seed → cybs → cycc`) green — this is a `src/`
  change, so seed-derive is MANDATORY (cybs fails silently on too many global/call refs).
- Cross-OS self-host byte-identical on ecb/ach/cass/pi.
- `tests/lib_freshness.sh` still green (it asserts the wrapper's behavior, not cycc's).

## Suggested home

A 6.4.x absorber/cleanup bite — it is non-blocking and folds into adjacent work per the
"non-blocking cosmetic/tooling fixes fold into adjacent work, no dedicated slots" rule. Do NOT
park to 7.x (7.x = language book + legal only).
