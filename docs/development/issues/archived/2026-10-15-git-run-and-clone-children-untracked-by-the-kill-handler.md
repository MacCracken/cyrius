# A SIGTERM'd `cyrius deps` leaves `_git_run`'s captures (`git_err`, `git_rev_out`, `dep_verify_out`) and its git child, and a mid-clone kill leaves `git clone` running — RESOLVED

> ✅ **RESOLVED in v6.7.14** (TL-6, `69cc8b31b`: a SIGTERM'd `cyrius deps` stops its git and leaves no git capture. No decision needed: the triage's plan. Forwarding the signal answered this filing's design question about the partial clone without a decision, where the filing proposed stopping the child (fwd 0). `_git_run` and the clone fork go through `_cbt_fork_tracked(1)`: git is sent the signal and waited for, so its own cleanup runs (a killed `git clone` removes its partial cache directory; SIGKILLed, it leaves it). `outf`, the per-process `git_err`, dep_verify_paths, and the verify's private index and its lock are tracked before they exist and dropped by their callers. `_cbt_scratch_track` de-duplicates by pointer, so the reused git_err holds one slot. The filed repro (clone, fsck, rev-parse) now exits 143 with no cyrius-<pid> dir and git gone, on x86_64 and with the native CLIs on ecb, ach and pi; it left `git_err` / `git_rev_out` / `dep_verify_out` and git running. Rows: `cli_temp_dir_no_leak.sh` axis 7 (a stand-in git in fsck, rev-parse, ls-files and clone, each recording TERM; a real clone on an `ext::` remote whose partial dir is removed; 10 RED on the 6.7.14-open CLI), `crossos/cli_kill_handler.tcyr` (the dedupe). Filed from the review, 6.7.15: the forwarded wait has no bound, so a git that ignores SIGTERM holds the CLI (7,752 ms measured). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-15 on the 6.7.13 tools lane (l6713-tools @ 86ab0dc7, the CLI built from
`cbt/cyrius.cyr` by the tree's `build/cycc`). Met while fixing
archived/2026-10-15-capacity-killed-leaves-cap-err-and-its-compiler-running.md, which tracked `cmd_capacity`'s compiler and
`_dep_wt_run`'s git child and captures (and, as a quick repair, `_dep_wt_run`'s stdout capture). The triage named
these two sites "outside the filed surface, met in passing"; they are the same untracked-child class.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane, wave 1, unit T3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a developer's own Ctrl-C / SIGTERM of a resolve leaves capture files in the CLI's private temp
dir (every name is in check.sh's reaper vocabulary, so the reaper removes the dead pid's dir) and an orphaned git
that runs to completion; an orphaned `git clone` goes on to create the dep cache after the CLI died.
**Affects:** every POSIX CLI since the 6.7.12 kill handler (before it no verb cleaned up on a signal).

## Reproduction

```sh
# (sh; CLI = build/cyrius built from cbt/; SUB = the git subcommand the stand-in sleeps on)
W=$PWD/gr; rm -rf $W; mkdir -p $W/o/sib/dist $W/p $W/tb $W/bin $W/home/deps
REAL=$(command -v git)
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$W/gitconfig GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = g\n\temail = g@example.invalid\n[init]\n\tdefaultBranch = main\n' > $W/gitconfig
printf 'fn sib_v(): i64 { return 1; }\n' > $W/o/sib/dist/sib.cyr
( cd $W/o/sib && git init -q . && git add -A && git commit -qm v1 && git tag v1.0.0 )
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[deps.sib]\ngit = "file://%s/o/sib"\ntag = "v1.0.0"\nmodules = ["dist/sib.cyr"]\n' $W > $W/p/cyrius.cyml
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "%s" ] && { echo $$ > "%s/g.cc"; exec sleep 60; }; done\nexec "%s" "$@"\n' "$SUB" $W "$REAL" > $W/bin/git; chmod +x $W/bin/git
( cd $W/p && HOME=$W/nohome CYRIUS_HOME=$W/home CYRIUS_RESOLVED=1 PATH="$W/bin:$PATH" TMPDIR="$W/tb/" sh -c 'echo $$ > "$0"; exec "$@"' $W/cli.pid $CLI deps > $W/out 2>&1; echo "cli rc=$?" > $W/rc ) &
B=$!; while [ ! -s $W/g.cc ]; do sleep 0.05; done
P=$(cat $W/cli.pid); C=$(cat $W/g.cc); echo "in flight: $(ls -A $W/tb/cyrius-$P | tr '\n' ' ')"
kill -TERM $P; wait $B; cat $W/rc
echo "after: $(ls -A $W/tb/cyrius-$P 2>&1 | tr '\n' ' ')"; kill -0 $C 2>/dev/null && echo "git $C ($SUB) still running"
kill -KILL $C
```

Output, SUB = clone / fsck / rev-parse:

```
== clone
in flight:
cli rc=143
after: ls: cannot access '…/gr/tb/cyrius-837554': No such file or directory
git 837555 (clone) still running
== fsck
in flight: dep_verify_out git_err
cli rc=143
after: dep_verify_out git_err
git 837604 (fsck) still running
== rev-parse
in flight: git_err git_rev_out
cli rc=143
after: git_err git_rev_out
git 837636 (rev-parse) still running
```

Expected (the 6.7.12 handler's contract, as `cyrius check` / `build` / `capacity` meet it): exit 143, no
`cyrius-<pid>` dir under `$TMPDIR`, the git child stopped.

## Root cause

`_git_run` (cbt/deps.cyr ~5470) forks git without `_cbt_child_track`, and neither its stderr capture
(`_git_errfile()`, the per-process `git_err`, created by the child and unlinked by `_git_err_clear`) nor its stdout
capture (`outf`: `git_rev_out`, `dep_verify_out`, …, opened by the parent and unlinked by each caller) is
registered with `_cbt_scratch_track`. The clone fork (cbt/deps.cyr ~3249, `git clone --depth 1 … <clone_dir>`) is not
tracked either, so `_cbt_sig_fire` never stops it.

Why it is not a two-line fix: `git_err` is ONE path reused by every `_git_run` of the process (`_git_err_path`), and
`_cbt_scratch_track` does not de-duplicate, so tracking it per call fills the 32-slot table; it needs a
track-once rule (or a dedupe in `_cbt_scratch_track`) and `_git_err_clear` turned into a drop. Each `_git_run` caller
that passes an `outf` unlinks it itself (several sites), so the stdout capture needs the drop at each. And a killed
clone leaves a partial `clone_dir` in the dep cache (`$CYRIUS_HOME/deps/…`), which a stopped child does not remove:
whether the handler should also remove a clone it started is a design question of its own.

## Proposed fix

`_git_run`: `_cbt_child_track(pid, 0)` after its fork and `_cbt_child_untrack` after the wait; register `git_err` once
(when `_git_errfile` creates the path, re-registered after `_git_err_clear` drops it) and each `outf` before its open,
with the callers' unlinks turned into `_cbt_scratch_drop`. The clone fork: tracked the same way (it inherits stderr,
so it has no capture); the partial `clone_dir` decided separately. Rows: cli_temp_dir_no_leak.sh axis 7, a stand-in
git sleeping in `fsck`, `rev-parse` and `clone` (the shape of its `g7_run` rows): rc 143, no dir, git gone.
