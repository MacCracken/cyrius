# A SIGTERM'd `cyrius deps` waits without limit for a forwarded git (fwd 1) that does not die on the signal — OPEN

**Status:** 🟡 **OPEN** — met 2026-10-16 by the 6.7.14 tools lane's review of 69cc8b31b (the fix for
issues/archived/2026-10-15-git-run-and-clone-children-untracked-by-the-kill-handler.md) and reproduced by the lane's fix step
(l6714-tools @ 69c72ca09, the CLI built from `cbt/cyrius.cyr` by the tree's `build/cycc`). The lane introduced it:
the 2600f67f CLI does not wait for git at all (it leaves git running, the bug 69cc8b31b fixed).
**Placement:** 6.7.15 — repair 5 (tools lane; filed from the 6.7.14 tools review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — it needs a git, or a `git` wrapper first on PATH, that ignores or delays SIGTERM / SIGINT / SIGHUP.
Real git dies on all three (it cleans up and re-raises). With such a git, the developer's Ctrl-C / SIGTERM of a
resolve hangs until git exits on its own. A second Ctrl-C does nothing, because the handler runs with HUP / INT / TERM
blocked (sa_mask), so only SIGKILL gets the user out.
**Affects:** every POSIX CLI from 6.7.14 on: `_git_run` and the clone fork in `cbt/deps.cyr`, both
`_cbt_fork_tracked(1)`.

## Reproduction

```sh
# r1.sh <cyrius CLI> <workdir>: a git dep whose clone runs a git that ignores SIGTERM
CLI=$1; W=$2
rm -rf "$W"; mkdir -p "$W/o/sib/dist" "$W/p" "$W/bin" "$W/home/deps" "$W/tmp"
REALGIT=$(command -v git)
printf '[user]\n\tname = r\n\temail = r@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$W/gitconfig"
printf 'fn sib_v(): i64 { return 1; }\n' > "$W/o/sib/dist/sib.cyr"
( cd "$W/o/sib" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" git init -q . && git add -A && git commit -qm v1 && git tag v1.0.0 ) > /dev/null 2>&1
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[deps.sib]\ngit = "file://%s/o/sib"\ntag = "v1.0.0"\nmodules = ["dist/sib.cyr"]\n' "$W" > "$W/p/cyrius.cyml"
cat > "$W/bin/git" <<G
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = clone ]; then echo \$\$ > "$W/git.pid"; trap '' TERM; sleep 8; exit 0; fi
done
exec "$REALGIT" "\$@"
G
chmod +x "$W/bin/git"
( cd "$W/p" && HOME="$W/nohome" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 GIT_CONFIG_NOSYSTEM=1 \
  GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file PATH="$W/bin:$PATH" TMPDIR="$W/tmp/" \
  exec "$CLI" deps > "$W/out" 2>&1 ) &
P=$!
while [ ! -s "$W/git.pid" ]; do sleep 0.05; done
sleep 0.2
t0=$(date +%s%N); kill -TERM $P; wait $P; rc=$?; t1=$(date +%s%N)
echo "cli rc=$rc, exited $(( (t1 - t0) / 1000000 )) ms after SIGTERM"
G=$(cat "$W/git.pid"); if kill -0 "$G" 2>/dev/null; then echo "git: still running"; kill -KILL "$G"; else echo "git: gone"; fi
```

```
HEAD (69c72ca09):
cli rc=143, exited 7752 ms after SIGTERM
git: gone
2600f67f:
cli rc=143, exited 1 ms after SIGTERM
git: still running
```

With `kill -TERM $P; sleep 0.5; kill -INT $P; kill -TERM $P` in place of the single kill, HEAD still exits after
7,751 ms, so the second and third signals are held. (The review measured 7,950 ms against 1 ms for the same shape.)

## Root cause

`_cbt_fork_tracked(fwd)` (cbt/sigclean.cyr) records `fwd` for the kill handler. On a signal, `_cbt_sig_fire` calls
`_cbt_sig_stop(c, fwd, n)`. With fwd 1 that sends the caught signal `n`, then does a blocking `sys_waitpid(c, &st, 0)`,
looping on EINTR, with no time limit. fwd 1 was designed for forked copies of the CLI, whose own handler always exits.
6.7.14 (69cc8b31b) applied it to an exec'd external program, `/usr/bin/env git`, in `_git_run` and the clone fork
(cbt/deps.cyr), so that git runs its own cleanup: its index.lock, and a clone's partial directory. An external program
is under no such contract. If it ignores, blocks or delays the signal, the handler waits for as long as it runs. The
handler runs with HUP / INT / TERM in sa_mask, so a second signal does not interrupt it.

## Proposed fix

For a forwarded child that is an exec'd program (a third tracking mode, or fwd 1 with a bound), the handler sends the
signal and then polls `waitpid(c, WNOHANG)` for a bounded grace period (a few hundred ms to ~2 s; git's own cleanup
of a partial clone finishes well within it). If the child has not exited by then, it gets SIGKILL and is reaped.
Forked copies of the CLI keep the plain fwd 1 wait.

Rows: `tests/gates/toolchain/cli_temp_dir_no_leak.sh` axis 7 with the TERM-ignoring stand-in above. The CLI exits
143 within the grace period plus a margin, and the stand-in is gone (SIGKILLed). The existing rows stay green: a
cooperating git still records TERM, and the real ext:: clone still removes its partial cache directory.
