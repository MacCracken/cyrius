# `syscall_xlat_generated.sh`: the axes that assert SILENCE print `ok` when the compile crashed or the probe source is empty — OPEN

**Status:** 🟡 open — found during 6.6.6 bite 12 (a reviewer ran the gate with `TMPDIR` on a
1 MiB tmpfs); reconfirmed at the bite-12 tree with the repro below. Pre-existing — bite 12 did not
touch these axes.
**Placement:** unpinned — 6.x-line backlog (the next repair batch).
**Discovered:** 2026-09-19
**Severity:** Medium — a gate axis reads green having measured nothing. Today the gate as a whole
still goes RED in the same run (axes 3/7/8/9/10 fail on the same crash), so no false PASS has been
observed; the axes themselves are vacuous, and one refactor away from a green gate.
**Affects:** `tests/gates/platform/syscall_xlat_generated.sh` at 6.6.5 / 6.6.6-dev.

## Summary

Five axes prove a property by the ABSENCE of a diagnostic: axis 2 (`0 false positives on cycc's own
aarch64 source`), the unlabelled fstat(5) row after axis 3, axis 4 (`write=1 stays silent`), axis 5
(`63 stays silent`) and axis 6 (`the x86_64 fork is silent`). Each runs a compiler, greps its stderr
for `raw syscall`, and prints `ok` on zero matches. None checks that the compiler RAN: not its exit
status, not that the probe source was written. A compiler that segfaults, or a probe `printf` that hit
a full disk and left an empty file, produces no diagnostic — and the axis reports success.

## Reproduction

Mount-free (RLIMIT_FSIZE truncates the aarch64 emitter the gate builds, so it segfaults):

```sh
( ulimit -c 0; ulimit -f 600; TMPDIR=$(mktemp -d) sh tests/gates/platform/syscall_xlat_generated.sh )
```

Actual (excerpt):

```
... line 139: Segmentation fault   "$D/cc_a64" < src/main_aarch64.cyr > /dev/null 2> "$D/self.err"
  ok: 0 false positives on cycc's own aarch64 source (was 510 before the exclusions)
... Segmentation fault   "$D/cc_a64" < "$D/fst.cyr" ...
  ok: raw fstat(5) is routed now and stays silent
... Segmentation fault   "$D/cc_a64" < "$D/ok.cyr" ...
  ok: an ESYSXLAT-remapped number (write=1) stays silent
... Segmentation fault   "$D/cc_a64" < "$D/amb.cyr" ...
  ok: an ambiguous number (63 = x86 uname / aarch64 read) stays silent
```

The reviewer's original measurement — `TMPDIR` on a 1 MiB tmpfs (`unshare -rm` +
`mount -t tmpfs -o size=1m`) — shows the same, plus the probe writes failing
(`printf: write error: No space left on device`) and axis 6 printing
`ok: the x86_64 fork is silent` over an EMPTY `$D/x.cyr`.

Expected: each of those axes FAILs ("the compiler crashed (rc=139)" / "could not write the probe"),
exactly as axes 7/8/9 already do for their compiles (`did not build for aarch64 (rc=139)`).

## Root cause

`tests/gates/platform/syscall_xlat_generated.sh`: axis 2 (~line 81), the fstat row (~107), axis 4
(~119), axis 5 (~130) and axis 6 (~264) run `"$D/cc_a64" < probe > /dev/null 2> err` (or
`./build/cycc`) and test only `grep -c 'raw syscall' err`. The same file's axes 7–10 capture `rc` and
fail on non-zero; these five never did. Same family as the 6.6.2 "a check that shares a defect with
the thing it checks reads GREEN" pattern: an assertion of silence needs a positive proof the
speaker was alive.

## Proposed fix

For every silence axis: fail when the probe source is empty (`[ -s ]` after the `printf`, or check
`printf`'s status), and fail when the compile's exit status is not 0 — capture `rc` the way axes 7–9
do. Axis 2 in particular should also require its output binary to be non-empty. Mutation-prove by
running the gate under the `ulimit -f 600` repro: every one of the five must go RED.

## Acceptance criteria

- Under the repro above, none of the five axes prints `ok`; each names the crash or the empty probe.
- A normal run still passes with the same `ok` lines.
- Gate header records the mutation (ulimit repro → five axes RED).
