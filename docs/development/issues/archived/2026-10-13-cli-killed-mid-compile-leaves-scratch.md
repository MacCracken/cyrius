# A `cyrius` run killed mid-compile still leaves `cpp_<pid>`, `cc_err` and `<out>.tmp.<pid>` in its temp dir — only check.sh's reaper removes them — RESOLVED

> ✅ **RESOLVED in v6.7.12** (TL-24: a SIGTERM / SIGINT / SIGHUP handler (cbt/sigclean.cyr; Linux rt_sigaction, macOS BSD sigaction with the handler as its own trampoline) stops the compiler the CLI started (a distlib verify forwards the signal to its per-target children), unlinks the in-flight `cpp_<pid>`, `cc_err`, `<out>.tmp.<pid>`, a check's output and distlib's `dlverify*`, removes its private dir and exits 128+N — the repro leaves no `cyrius-<pid>` dir and no running compiler, measured on x86_64 Linux, qemu-aarch64, pi, ecb and ach for check and build × TERM / INT / HUP. A signal ignored at start stays ignored; SIGKILL remains the reaper's; Windows catches nothing. The issue's handler option (no user decision). Rows: `cli_temp_dir_no_leak.sh` axis 7, crossos `cli_kill_handler.tcyr`; mutations RED. Not covered, filed (6.7.13): a killed distlib verify's `dist/.dlverify-<pid>/` mirror, and a killed `cyrius capacity`'s `cap_err` and compiler (the same class: `_dep_wt_run`'s `wt_err` and git children); the few instructions between fork and track stay a stated residual. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-13 on the 6.7.11 tools lane (l6711-tools). 6.7.11 made check.sh's reaper
remove a dead pid's `cyrius-<pid>` dir that holds only compile scratch (user decision 2026-10-13, issue
2026-10-08-killed-cli-leaves-nonempty-tmp-dirs.md). That decision also expected "cpp_ and the .tmp.<pid> outputs are
unlinked on every compile failure path, so most kills leave an empty dir". Every compile FAILURE path already unlinks
them (6.5.19 / 6.6.6 / 6.6.20 — measured, now pinned by tests/gates/toolchain/cli_temp_dir_no_leak.sh axis 7), so no
code was missing there; the leftovers come from the CLI itself being KILLED while the compiler runs, and an unlink on
a failure path cannot reach that case.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13, the 6.7.11 tools lane (killed-tmp unit).
**Severity:** Low — disk litter in the private 0700 dir (up to ~1 MB of `cpp_` per kill); a box that runs check.sh
reaps it after `CYRIUS_CHECK_REAP_MINS` (240); a box that never runs check.sh keeps it.
**Affects:** every CLI since the private temp dir (v6.4.81).

## Reproduction

```sh
# (run with sh, from the cyrius checkout) a stand-in compiler beside a copy of the CLI, so the
# compile is still running when the CLI is killed
mkdir -p k p/src tb && cp build/cyrius k/cyrius
printf '#!/bin/sh\ncat > /dev/null\necho partial\nexec sleep 60\n' > k/cycc && chmod +x k/cycc
printf 'fn h(): i64 { return 0; }\n' > p/src/h.cyr
printf 'include "h.cyr"\nfn main(): i64 { return h(); }\nvar r = main();\n' > p/src/ok.cyr
( cd p && TMPDIR=$PWD/../tb exec ../k/cyrius check src/ok.cyr ) & pid=$!
sleep 1.5; kill -TERM $pid; sleep 0.3; pkill -f '^sleep 60'
ls tb/cyrius-*
```

Output (6.7.11, measured):

```
cc_err
check_2128448.tmp.2128448
cpp_2128448
```

Measured too: the same three for SIGKILL; a SIGTERM'd `cyrius build` leaves `cc_err` and `cpp_<pid>` (its
`.tmp` sits beside the output). On 2026-10-13 /tmp on the dev box held 485 dead-pid dirs of scratch only — 443 of
them 6.7.10's normal-exit `wt_err` leak (fixed there), 40 of this shape, and a killed distlib verify's
`dlverifyerr<t>` / `dlverifyout<t>.tmp.<pid>` beside four `cpp_<pid>` (its per-target children's) — and 3
post-mortems (`test_bin` + `test_out`).

## Root cause

The scratch is live for exactly the compile: `_materialize_source` writes `cpp_<pid>` and the compiler child opens it
by name; `_cc_own_err_begin` creates `cc_err` and the child opens it by name; the child writes `<out>.tmp.<pid>`, renamed
over the output on success. The CLI installs no handler for SIGTERM / SIGINT / SIGHUP, so a kill in that window skips
every unlink.

## Options (not decided)

- Open `cpp_<pid>` in the parent before the fork, unlink it, and hand the child the descriptor as stdin (POSIX arm);
  the same for `cc_err` (open read-write, unlink, the child dup2s it, the parent reads it back through the descriptor —
  `_cc_undef_hints` takes a path today). `<out>.tmp.<pid>` cannot be unlinked before its rename, so a kill still leaves
  that one file.
- A SIGTERM / SIGINT / SIGHUP handler that unlinks the in-flight names and exits 128+N (Linux and macOS; nothing on
  Windows). SIGKILL stays the reaper's.

## Acceptance

- The reproduction's SIGTERM leaves an empty `cyrius-<pid>` dir (or none).
- cli_temp_dir_no_leak.sh axis 7's kill row asserts that, instead of "only reapable scratch".
