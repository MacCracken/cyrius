# `CYRIUS_POISON=0` (or empty, or any value) turns the poison mode ON — every compiler fork tests only "is it set" — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
2,053,536 B): with the repro, `CYRIUS_POISON=1`, `=0`, `=` (empty) and `=no` all compile the `#ifdef CYRIUS_POISON`
arm (exit 7); only an unset variable gives 0. The aarch64 and cx cross compilers built from the tip give 7 for `=0`
too, and the installed 6.7.7 `cycc` does the same. `CYRIUS_BOUNDS` on the same tip reads `0` as off, empty as no
setting, and refuses `no` by name ("CYRIUS_BOUNDS must be 0 or 1 (or unset): no").
**Placement:** 6.7.11 — repair 1, the tools lane — a High, from 6.7.12 (pulled in at the open: user, 2026-10-13) — never 7.x. Was: 6.7.12 — repair 2 (roadmap.md § *The releases after 6.7.7*; the compiler forks' environment block,
tooling on the hosts) — placed 2026-10-10 — never 7.x (the fix is the user's call, asked at that release's open: what
a build does under `CYRIUS_POISON=0` changes).
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-7 (reported only, `~/.cache/c6/c2/changelog_handoff.md` §
C2-7). Its natural home was C2-8b, which scrubs CYRIUS_POISON in the self-build scripts but did not change the forks'
test.
**Severity:** High — a wrong artifact without a diagnostic: `CYRIUS_POISON=0` builds a poisoned binary (redzones,
poison fill, quarantine-on-free). Only a hand-set environment meets it — cbt only ever injects `CYRIUS_POISON=1`
(`cbt/build.cyr:1299`).
**Affects:** cycc 6.5.29 (the poison mode) – 6.7.8 by the code (`_read_env(..) != 0`); measured on 6.7.7 and the
merged 6.7.8 tip.

## Summary

The poison mode is a compile-time predefine: each of the seven compiler forks reads `CYRIUS_POISON` from the
environment and, when the read returns anything, predefines `CYRIUS_POISON`, which `lib/` reads to build the poisoned
allocator. "Anything" includes `0`, the empty string and any word — so the one spelling that reads as "off"
(`CYRIUS_POISON=0`, the way `CYRIUS_BOUNDS=0` and `CYRIUS_DCE=0` are documented) turns it on. The three switches of the
same family disagree on what their values mean.

## Reproduction

`docs/development/issues/repros/2026-10-10-poison-env-zero-or-empty-turns-mode-on.cyr`:

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 {
    #ifdef CYRIUS_POISON
    return 7;
    #endif
    return 0;
}
var rc = main();
syscall(60, rc);
```

```sh
for v in 1 0 '' no; do CYRIUS_POISON="$v" sh -c 'cat <repro> | build/cycc > /tmp/pz' \
  && chmod +x /tmp/pz && /tmp/pz; echo "CYRIUS_POISON=[$v] -> $?"; done
env -u CYRIUS_POISON sh -c 'cat <repro> | build/cycc > /tmp/pz' && /tmp/pz; echo "unset -> $?"
```

```
expected: 1 -> 7, 0 -> 0, '' -> 0, no -> refused by name, unset -> 0
actual:   1 -> 7, 0 -> 7, '' -> 7, no -> 7,               unset -> 0
```

## Root cause

Each fork's environment block: `var _poison_env_early = _read_env("CYRIUS_POISON");` then
`if (_poison_env_early != 0) { PP_PREDEFINE(S, "CYRIUS_POISON"); }` — `src/main.cyr:1115` / `:1124`,
`src/main_aarch64.cyr:180` / `:189`, `src/main_aarch64_macho.cyr:147` / `:156`, `src/main_aarch64_native.cyr:178` /
`:187`, `src/main_cx.cyr:288` / `:297`, `src/main_win.cyr:250` / `:259`, `src/main_x86_macho.cyr:134` / `:143`.
`_read_env` returns a pointer to the value for any set variable, so only "unset" is off. `CYRIUS_BOUNDS`'s reader
(`_bnd_env_rung`, `src/frontend/lex_pp.cyr:5475`) is the shape the others follow: `1` on, `0` off, unset or empty no
setting, anything else refused by name.

## Proposed fix

Read `CYRIUS_POISON` through one shared helper with `_bnd_env_rung`'s rule (`1` on; `0`, empty or unset off; anything
else refused by name: "CYRIUS_POISON must be 0 or 1 (or unset): no"), called from all seven forks so they cannot
drift. Rows (a gate under `tests/gates/platform/`, the way `cx_compiler_reads_env.sh` checks the cx fork's env): each
value on the native fork and the aarch64 / cx / PE cross compilers; `cyrius fuzz --poison` unchanged (it injects `=1`).
