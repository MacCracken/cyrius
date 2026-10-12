# Under wine, the PE compiler returns rc 3 at once with empty output; the full output lands later — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 17; CHANGELOG [6.7.9]) closed as **NOT REPRODUCIBLE**, with no code
> change. On this box (wine 11.19), every run of `wine cycc.exe < in > out` in a private prefix returned rc 0 with
> the output complete at return. That covered a fresh prefix, a warm one, six calls racing to create one prefix,
> 16 fresh prefixes in parallel, the PE self-host, binfmt, a pipe, a name without `.exe` and a `wineserver -k` race.
> No probe returned rc 3. No probe left a process writing after the call returned. The gates already judge a wine run
> by rc and content, and tear their prefix down with `wineserver -w`. The investigation is below. If the symptom
> comes back, reopen this issue with the exact command line, the environment, the working directory and `wine --version`.

**Status:** ✅ **RESOLVED — not reproducible** (6.7.9, quick lane bite 17, 2026-10-11). The 2026-10-11 sizing
re-run was negative (fresh, warm, 4 concurrent, a 2.1 MB input). The bite re-ran the filed command and 11 variants
around it; all were negative too (§ *Investigation*). The filing named no trigger, and there is still no known mechanism.
Originally reported 2026-10-09 by the 6.7.7 merge step (`wine cycc.exe < in > out` with a private prefix on this
box). The late output was byte-identical to `CYRIUS_TARGET_WIN=1`.
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** the 6.7.7 merge step (out of scope); filed 2026-10-09.
**Severity:** Low — test-harness hazard: a check of rc or size straight after the call is misled
**Affects:** the PE compiler under wine (this box)

## Summary

`wine cycc.exe < in > out` (the compiler built from `main_win.cyr`) returns rc 3 immediately with stderr and `out`
empty; the output then arrives in full. Anything that reads rc or the file size right after the call — a gate, a
probe loop — sees a failure that is not one (or, worse, reads a half-written file).

## Proposed fix

Find whether it is wine's process model (a detached child) or the PE runtime's exit path; make the gates that drive
wine wait on the real process (`wineserver -w`) and assert the output's content, not rc alone.

## Investigation (6.7.9, 2026-10-11)

**Setup.** wine 11.19 on this box. binfmt_misc registers `DOSWin`: interpreter `/usr/bin/wine`, magic `4d5a`.
`cycc.exe` was cross-built with `CYRIUS_TARGET_WIN=1 build/cycc < src/main_win.cyr` (2,132,992 B, at the quick lane's
tip `981b9e26`). Every probe set its own `WINEPREFIX`, `HOME` and `XDG_CACHE_HOME` under a scratch directory, plus
`WINEDEBUG=-all`. Each probe read rc and the output's size the moment `wine` returned, then read the size again
3–4 s later.

| probe | rc | output at return | later |
|---|---|---|---|
| the filed command, fresh prefix (`wine cycc.exe < tiny.cyr > out.exe`), then twice warm | 0 | 2,560 B, `cmp`-equal to `CYRIUS_TARGET_WIN=1` | same |
| six calls in parallel, all creating ONE fresh prefix | 0 ×6 | complete ×6 | same |
| PE self-host, fresh prefix (`wine cycc.exe < src/main_win.cyr > c2.exe`, 7.4 s) | 0 | `c2.exe == cycc.exe` | same |
| binfmt_misc direct run (`./cycc.exe < tiny.cyr`) | 0 | complete | same |
| stdin from a pipe (`cat tiny.cyr \| wine cycc.exe`) | 0 | complete | same |
| no `.exe` suffix (`wine ./cycc_win`, as the store names the PE compiler) | 0 | complete | same |
| `wineserver -k` (no `-w`), then a call on the same prefix at once | 0 | complete | same |
| an existing empty directory as the prefix | 0 | complete | same |
| 8 fresh prefixes in parallel × 3 calls each, each torn down with `-k` / `-w` | 0 ×24 | complete ×24 | — |

**What did fail: none of it matches the filing.**
- A relative `WINEPREFIX`: rc 1, and wine says "not an absolute path".
- A missing `.exe`: rc 1.
- A truncated `.exe` (also one whose tail was appended 0.05–3 s after wine started): rc 1, `c000007b`.
- A second round of 8 fresh prefixes while the first round's prefixes were still on disk: rc 1 with empty output on
  every call, because they ran the per-user `/tmp` quota out (`usrquota`, about 376 MB a fresh prefix).

None of these returned rc 3, and none left a process that wrote after the call returned.

⚠ A wine gotcha met on the way (not a defect). When wine cannot map the main image, it falls back to `start.exe /exec`
(ShellExecuteEx). That fallback prints "Application could not be started, or no application associated with the
specified file. ShellExecuteEx failed: …" on **stdout**, which lands in the redirected output file (125–241 B). So a
failed wine start does not leave the output empty. A check of `-s out` alone would read it as a success. The gates
pair `-s` with rc (`syscall_wrapper_pass.sh`), or compare content (`cmp` / `grep`).

**A detached child?** Not found. wine waits even for its ShellExecute path. A `.bat` that sleeps 3 s and exits 7
returned rc 7 after 3.98 s, with its output there at return.

**The gates.** Every file under `tests/gates/` that runs wine tears its private prefix down with
`wineserver -k` + `wineserver -w`. The rest only name wine in comments. Derive the split; do not trust a number:
`comm -23 <(grep -rl wine tests/gates | sort) <(grep -rl 'wineserver -w' tests/gates | sort)`. Each of those files
mentions wine only in comment lines. A wine run is judged by rc AND content (`cmp` against the Linux build, a
`grep` of stderr, or `-s` together with rc 0). If the filed signature came back, a gate would go RED with its rc and the
empty output. It could not read as green. A `wineserver -w` after every call would add the server's linger
(measured 3.1–4.1 s) to every wine call in check.sh. That cost was not taken for a symptom nobody can reproduce.
