# A SIGTERM'd `cyrius capacity` leaves `cap_err` in its temp dir and its compiler running — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-6: `cmd_capacity` registers `cap_err` with the kill handler before its fork, and tracks its compiler child; both are dropped once the child is reaped and the capture read. `_dep_wt_run` does the same for `wt_err` and its git child, the issue's named sibling. Met in passing, it now also does so for its stdout captures `wt_out` / `ls_remote` (86ab0dc7). The filed repro now ends `cli rc=143` with no `cyrius-<pid>` dir and the compiler gone, on x86_64 and qemu-aarch64. Before, `cap_err` stayed and the compiler ran on. No decision needed. Rows: `cli_temp_dir_no_leak.sh` axis 7 — the capacity kill row (the k2 stub); a `--local` build killed in `check-ignore` and in `rev-parse`; `cyrius update` killed in `ls-remote` (a stand-in git on PATH). The 6.7.13-open CLI fails 4 of these rows and fc024420's CLI fails 2. The triage's other "met in passing" sites — `_git_run`'s captures and the clone fork — are filed (6.7.14, Low). CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.12 tools lane (l6712-tools @ 88afd900, the CLI built from
`cbt/cyrius.cyr` by the tree's `build/cycc`). Met by the tools lane's review of
2026-10-13-cli-killed-mid-compile-leaves-scratch.md (89d4415d / 19160a54), whose filed surface is check / build /
distlib: those three stop their compiler and leave no dir; `capacity` forks its own compiler outside `compile()` and
is outside that surface, so it is filed, not folded in.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Low — a developer's own Ctrl-C / SIGTERM of a stats run leaves one file in the CLI's private temp dir
(check.sh's reaper removes `cap_err` only if it knows the name) and an orphaned compiler that runs to completion.
**Affects:** `cyrius capacity` since the 6.7.12 kill handler (before it, no verb cleaned up on a signal). The same
class: `_dep_wt_run`'s `wt_err` capture and its git children (cbt/deps.cyr ~2406).

## Reproduction

A stand-in compiler beside a private copy of the CLI (the CLI runs the `cycc` beside it) that records its pid and
sleeps — the shape of `tests/gates/toolchain/cli_temp_dir_no_leak.sh` axis 7's `k2` stub:

```sh
T=$PWD/capk; mkdir -p $T/k2 $T/proj/src $T/tb
cp build/cyrius $T/k2/cyrius
printf '#!/bin/sh\necho $$ > "%s/k2.cc"\ncat > /dev/null\necho partial\nexec sleep 60\n' "$T" > $T/k2/cycc; chmod +x $T/k2/cycc
printf '[project]\nname = "capkill"\nversion = "0.0.1"\n' > $T/proj/cyrius.cyml
printf 'fn main(): i64 { return 0; }\nvar r = main();\n' > $T/proj/src/ok.cyr
cd $T/proj && ( TMPDIR="$T/tb/" sh -c 'echo $$ > "$0"; exec "$@"' $T/cli.pid $T/k2/cyrius capacity src/ok.cyr > $T/out 2>&1; echo "cli rc=$?" > $T/rc ) &
B=$!; while [ ! -s $T/k2.cc ]; do sleep 0.05; done; sleep 1.5
P=$(cat $T/cli.pid); C=$(cat $T/k2.cc); ls -A $T/tb/cyrius-$P
kill -TERM $P; wait $B; cat $T/rc
ls -A $T/tb/cyrius-$P; kill -0 $C 2>/dev/null && echo "compiler $C still running"
kill -KILL $C
```

Output:

```
cap_err
cpp_1907705
cli rc=143
cap_err
compiler 1907706 still running
```

The CLI exits 143 as the handler intends, and the materialized `cpp_<pid>` (tracked by `_materialize_source`) is
gone — but `cap_err` stays in `cyrius-<pid>/` (so the dir stays too), and the compiler keeps running. The same run
under `cyrius check` (axis 7's rows) leaves nothing and stops the compiler.

## Root cause

`cmd_capacity` (`cbt/commands.cyr`, ~2785-2868) forks the compiler itself (`sys_fork` → `/bin/sh` → `cycc` with
`CYRIUS_STATS=1`, stderr into `tmperr`) instead of going through `compile()`. It never calls
`_cbt_child_track(pid, …)` on that fork, so `_cbt_sig_fire` (`cbt/sigclean.cyr`) has no child to stop, and never
`_cbt_scratch_track`s `tmpout` / `tmperr`, so the handler does not unlink `cap_err` and the private dir's rmdir fails.

## Proposed fix

In `cmd_capacity`'s non-PE arm: `_cbt_scratch_track(tmperr)` (and `tmpout`) before the fork, `_cbt_child_track(pid, 0)`
after it (the child execs `/bin/sh`, which execs the compiler — the same shape as `compile()`'s fork at
cbt/build.cyr:1780), and untrack both on the normal path. The same for `_dep_wt_run`'s `wt_err` and its git children.
Gate: `cli_temp_dir_no_leak.sh` axis 7 gains a `capacity` kill row (the `k2` stub: rc 143, no dir under `$TB`, the
compiler gone), RED on the 6.7.12 tools-lane CLI.
