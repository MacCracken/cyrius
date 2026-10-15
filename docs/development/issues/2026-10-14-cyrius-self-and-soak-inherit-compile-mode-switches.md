# `cyrius self` and `cyrius soak` self-host the compiler under an inherited CYRIUS_POISON / CYRIUS_BOUNDS / CYRIUS_COVERAGE — their verdict is about a mode build, not the default compiler — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 tools lane (l6711-tools @ b6d970d5). 6.7.11 scrubbed the
four compile-mode switches (CYRIUS_POISON, CYRIUS_BOUNDS, CYRIUS_COVERAGE, CYRIUS_COVERAGE_FILE) from the CLI's
self-builds that KEEP their output — `cyrius pulsar` and the cx arc's on-demand cycc_cx / cxvm builds
(issues/archived/2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md, cbt/core.cyr `_envp_self_build`). The two self-host
VERIFIERS were outside that filing's surface and still pass the CLI's whole environment: `cyrius self` and
`cyrius soak` both step through `_self_host_step` -> `_pulsar_raw_compile`, whose POSIX child execs with `_envp`.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 tools lane) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 tools lane (unit T4), reading every caller of `_pulsar_raw_compile` while
fixing the pulsar site.
**Severity:** Low — no artifact is kept (both verbs stage into the CLI's private temp dir and delete it), but the
verdict is about the wrong compiler: under an inherited `CYRIUS_POISON=1` `cyrius self` prints
`PASS: cycc==cycc byte-identical` for two POISON-MODE compilers, and since 6.7.11 an inherited `CYRIUS_POISON=no`
(now refused by the compiler) makes it report a self-host step failure that is about the shell, not the compiler.
The self-build SCRIPTS (6.7.9 / 6.7.10) and pulsar (6.7.11) unset the four; these two verbs are the remaining
self-build sites in the CLI.
**Affects:** `CYRIUS_POISON` since 6.5.29, `CYRIUS_BOUNDS` since 6.7.8, `CYRIUS_COVERAGE` since 6.7.10, through the
6.7.11 tools lane.

## Reproduction

Run from the cyrius repo root with `sh <file>` (read-only for the tree: the CLI is built into a mktemp dir and runs in
a scratch "repo" whose `build/cycc` is a stub that logs what it sees and emits itself):

```sh
#!/bin/sh
set -u
[ -x build/cycc ] && [ -f cbt/cyrius.cyr ] || { echo "run from the cyrius repo root"; exit 2; }
T=$(mktemp -d) && [ -d "$T" ] || exit 1
trap 'rm -rf "$T"' EXIT
build/cycc < cbt/cyrius.cyr > "$T/cyrius" 2> /dev/null && chmod +x "$T/cyrius" || { echo "cbt/cyrius.cyr did not build"; exit 1; }
mkdir -p "$T/p/build" "$T/p/src" "$T/home"
printf '#!/bin/sh\necho "  $STUBWHAT: POISON=${CYRIUS_POISON-unset} BOUNDS=${CYRIUS_BOUNDS-unset} COVERAGE=${CYRIUS_COVERAGE-unset}" >> "$STUBLOG"\ncat > /dev/null\ncat "$0"\n' > "$T/p/build/cycc"
chmod +x "$T/p/build/cycc"
echo 'var x = 1;' > "$T/p/src/main.cyr"
for verb in self "soak 1"; do
    (cd "$T/p" && STUBWHAT="cyrius $verb" STUBLOG="$T/log" CYRIUS_POISON=1 CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 \
        HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" "$T/cyrius" $verb > "$T/out" 2>&1; echo "  (cyrius $verb exit $?: $(grep -m1 -E 'PASS|FAIL|OK|error' "$T/out"))")
done
echo "what each self-host step saw (CYRIUS_POISON=1 CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 inherited):"
cat "$T/log"
```

Output (measured, 6.7.11 tools lane @ b6d970d5):

```
  (cyrius self exit 0:   PASS: cycc==cycc byte-identical)
  (cyrius soak 1 exit 0: )
what each self-host step saw (CYRIUS_POISON=1 CYRIUS_BOUNDS=1 CYRIUS_COVERAGE=1 inherited):
  cyrius self: POISON=1 BOUNDS=1 COVERAGE=1
  cyrius self: POISON=1 BOUNDS=1 COVERAGE=1
  cyrius soak 1: POISON=1 BOUNDS=1 COVERAGE=1
  cyrius soak 1: POISON=1 BOUNDS=1 COVERAGE=1
```

Expected: every self-host step reads `POISON=unset BOUNDS=unset COVERAGE=unset` (as `cyrius pulsar` does since
6.7.11), so the verdict is about the default compiler.

## Root cause

`cmd_self` (cbt/commands.cyr) and `cmd_soak` (cbt/commands.cyr) run both stages through `_self_host_step`
(cbt/build.cyr) -> `_pulsar_raw_compile` (cbt/pulsar.cyr), whose child is `sys_execve(cc, &argv, _envp)`. 6.7.11 made
`cmd_pulsar` set `_envp = _envp_self_build()` at entry; these two verbs never do. The Windows arm (`_win_cmd_self`,
and `_pulsar_raw_compile`'s `_win_compile_spawn` arm) inherits the process environment the same way.

## Proposed fix

The pulsar shape: `cmd_self` and `cmd_soak` set `_envp = _envp_self_build()` at entry (after their own checks), and
their Windows arms clear / restore the four around the spawns (`_win_mode_switches_clear` / `_restore`, cbt/build.cyr).
Rows: extend tests/gates/toolchain/cbt_self_builds_scrub_env.sh with an S axis (both verbs, all four unset on every
step; a mutation per verb RED).
