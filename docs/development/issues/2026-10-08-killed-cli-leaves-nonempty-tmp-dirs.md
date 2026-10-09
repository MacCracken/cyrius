# A killed `cyrius` run leaves a NON-EMPTY `cyrius-<pid>` temp dir that nothing reaps — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-08 on this dev box (6.7.6 @ 2fb6ad8b, `TMPDIR` unset): 202
`/tmp/cyrius-<pid>` dirs, 197 of them non-empty with a dead pid, 142 MB in all, dated 2026-10-06 → 2026-10-08; their
contents are a killed compile's temporaries — 180 hold `cpp_<pid>` (the preprocessed unit, up to ~1 MB), 179
`cc_err`, 179 `check_<pid>.tmp.<pid>`, 17 `wt_err`; none holds a `test_bin`. check.sh's reaper (CLN-03) removes only
EMPTY ones, by design. Read only — nothing was deleted.
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** 6.6.20 closeout (2026-10-06: 49 dead-pid dirs back the same evening, 33 non-empty); filed 2026-10-08
from roadmap.md.
**Severity:** Low — disk litter in a shared temp directory (the dirs are 0700 and private; nothing reads them back).
**Affects:** every CLI since the private temp dir (v6.4.81); 6.6.6's cleanup runs on a normal exit only.

## Summary

`cyrius` creates `$TMPDIR/cyrius-<pid>[-t<nonce>][-<n>]` on first use and `rmdir`s it at its one normal exit
(`cbt/cyrius.cyr:1370`, `_cbt_tmpdir_cleanup`, `cbt/build.cyr:1191-1196`) — deliberately `rmdir`, never a recursive
delete, because a non-empty dir can be a post-mortem the user was told to keep (a SIGKILLed `cyrius test`'s
`test_bin`; the `cyrius lsp` build). A signal death skips the cleanup. check.sh's `_chk_reap_dead_cli_tmpdirs`
(`scripts/check.sh:473-495`, 6.6.20) removes dead-pid dirs older than `CYRIUS_CHECK_REAP_MINS` — again `rmdir` only,
so every non-empty one stays for ever. The leftovers measured here are not post-mortems: they are a compile's scratch
(`_cc_own_err_begin`'s `cc_err`, `cbt/build.cyr:1111-1120`; the `cpp_` preprocessor output, `:711`; `cyrius
check`'s `check_<pid>` output, `cbt/commands.cyr:1209`, as its `.tmp.<pid>`) from runs killed mid-compile.

## Reproduction

```sh
n=0; for d in /tmp/cyrius-[0-9]*; do [ -d "$d" ] && [ -n "$(ls -A "$d")" ] \
  && ! kill -0 "$(basename "$d" | sed 's/^cyrius-\([0-9]*\).*/\1/')" 2>/dev/null && n=$((n+1)); done; echo $n
```

Expected after a check.sh run: 0 dead-pid dirs older than the reap age. Actual: 197 non-empty, every pid dead.

## Root cause

`_cbt_tmpdir_cleanup` (`cbt/build.cyr:1191`) is reached only from a normal exit; the CLI installs no handler for
SIGTERM / SIGINT / SIGHUP / SIGPIPE, and `_chk_reap_dead_cli_tmpdirs` never removes a non-empty dir. Open, from the
roadmap: **which runs land in `/tmp` although `TMPDIR` is exported** — the live CLI honours an absolute `TMPDIR`
(`_cbt_tmpbase`, `cbt/build.cyr:939-962`), so the candidates are pre-6.6.9 installed CLIs (literal `/tmp`) and
children started with a scrubbed environment (speculation; not traced — this box has `TMPDIR` unset).

## Proposed fix

The user's call on the first half, since it narrows the post-mortem contract:
1. **Reap by contents, not just emptiness**: a dead-pid dir past the age bound that holds ONLY compile scratch
   (`cpp_*`, `cc_err`, `wt_err`, `*.tmp.<pid>`) is removed whole; one holding `test_bin` or an lsp build stays.
2. **Delete scratch as soon as it is used**: `cpp_<pid>` and the `.tmp.<pid>` output are unlinked on the compile's
   failure paths too, so a kill between compiles leaves an empty dir CLN-03 already reaps.
3. Trace and fix the runs that ignore `TMPDIR`.
