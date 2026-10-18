# cli_temp_dir_no_leak.sh axis 7's SIGHUP rows go RED when the gate runs with SIGHUP ignored (`nohup sh scripts/check.sh`) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (TL-5, `27eb2ae65`: the launcher this filing suggested, with its named-SKIP fallback. No decision needed. Axis 7 reads SIGHUP's inherited disposition (SigIgn bit 0 of /proc/self/status). When SIGHUP is ignored or unknown, the HUP rows run the CLI through k7hup, a launcher the gate compiles into its mktemp dir with the tree's cycc; it resets SIGHUP to SIG_DFL and execs, keeping the pid and the environment. A k7hup that does not build SKIPs the HUP rows by name (exit 77). The filed `nohup sh tests/gates/toolchain/cli_temp_dir_no_leak.sh` now PASSes (it gave 3 FAIL), and so does a plain run. Rows: k7hup's own pair on every run (an inherited ignore lives, rc 0; under k7hup the same shell dies, rc 129); mutations: no `signal_default(1)` turns 1 row RED plain and 4 under nohup, and an unbuildable k7hup gives a named SKIP. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — met 2026-10-15 by the 6.7.13 tools lane (unit T1): `nohup sh scripts/check.sh` on the lane's
tree (l6713-tools @ 63bbec3f, cbt-only changes that do not touch cbt/sigclean.cyr) reported `FAIL
tests/gates/toolchain/cli_temp_dir_no_leak.sh` — 3 rows; the same gate run from a plain shell on the same tree a minute
later: PASS.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (tools lane, wave 1, unit T3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a gate defect, not a CLI one: a release-gate or check.sh run started under `nohup` (or from any
parent that ignores SIGHUP) goes RED with no defect behind it, and the row text points at the kill handler, which is
where a diagnosis would go first.
**Affects:** tests/gates/toolchain/cli_temp_dir_no_leak.sh axis 7 (the `for k7s in TERM INT HUP` rows, 6.7.12).

## Reproduction

```sh
cd <tree> && nohup sh tests/gates/toolchain/cli_temp_dir_no_leak.sh > g.log 2>&1; grep FAIL g.log
```

```
  FAIL:   …the CLI exits 128+1 — expected 129, got 0                   (check SIGHUP mid-compile)
  FAIL:   …the CLI exits 128+1 — expected 129, got 0                   (build SIGHUP mid-compile)
  FAIL:   …and no k7out.tmp.<pid> beside the output — expected 0, got 1
FAIL: cli-temp-dir-no-leak — 3 assertion(s) failed
```

(`nohup sh -c 'grep SigIgn /proc/self/status'` → `SigIgn: 0000000000000001`: SIGHUP ignored, inherited by every child.)

## Root cause

The CLI keeps an ignore it inherits — the gate's own "SIGHUP ignored at start stays ignored" row is that contract —
so under `nohup` the HUP rows' kill never reaches a handler: the CLI finishes its compile and exits 0, and the build's
`.tmp.<pid>` is still in flight when the row looks. The rows assume the default SIGHUP disposition and never check it.

## Proposed fix

Before the HUP iteration, read the disposition the gate's children inherit (SigIgn bit 0 of /proc/self/status on
Linux) and, when SIGHUP is ignored, SKIP the HUP rows by name ("SIGHUP is ignored in this shell (nohup?)") and count
the skip (exit 77) — a POSIX sh cannot reset an ignore it inherited at entry, so restoring the default would need a
helper program (e.g. a tiny cyrius launcher that resets the disposition before exec). Never a silent RED or a silent
pass. Row: the gate itself under `nohup` (GREEN or named SKIP) and from a plain shell (GREEN).
