# `tests/win/async_iocp_pe.cyr` returns 1 at step 2 (`async_with_timeout`) on cass under a plain `cmd /c` — OPEN

**Status:** 🟡 **OPEN** — not re-verified on hardware (needs cass). 2026-10-08 against 6.7.6 @ 2fb6ad8b under wine on
this Linux box (private `WINEPREFIX`, the test cross-built by the tree's `build/cycc` with `CYRIUS_TARGET_WIN=1`): it
exits 42 run directly and under `wine cmd /c aip.exe` — wine does not reproduce it (as with the v6.4.44 misaligned-stack
fault this test also guards, which only real Windows showed).
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** 6.6.17 slot open (2026-10-05): on cass, `cmd /c "cd /d … && aip.exe"` returned 1, 3 of 3, while the
release gate's `cmd /v /c "…& …"` form exits 42; filed 2026-10-08 from roadmap.md.
**Severity:** Medium — the Windows IOCP runtime's `async_with_timeout` reports a deadline miss for a task that
finishes at once, depending on how the process is launched; the release gate's launch form hides it.
**Affects:** observed at 6.6.17; not narrowed further.

## Summary

The test drives `lib/async_win.cyr` end to end and folds its results to 42. Step 2 spawns a task that returns 5
immediately and awaits it with a 1 s deadline:

```cyr
var fast = async_spawn(rt, &work, 0);
if (async_with_timeout(rt, fast, 1000) != 1) { return 1; }     # tests/win/async_iocp_pe.cyr:59-60
```

Under the release gate's launch (`scripts/cross-os-selfhost.sh:460`: `cmd /v /c "cd /d C:\cyrius-tests\<dir> &&
c2.exe < tests\win\async_iocp_pe.cyr > aip.exe && aip.exe & if !errorlevel! NEQ 42 (exit 1) else (exit 0)"`) it
exits 42. Under `cmd /c "cd /d … && aip.exe"` it exits 1 — the timeout sentinel "won" (or the task was not seen
DONE), so either the deadline fired early or the completion is lost in that launch context. The exit code is real
(1 ≠ the `%errorlevel%`-reads-0 trap).

## Reproduction

On cass, in `C:\cyrius-tests\<dir>` with the native `c2.exe`:

```bat
c2.exe < tests\win\async_iocp_pe.cyr > aip.exe
rem from a .bat (a %errorlevel% read inside one cmd line is the known false 0):
cmd /c "cd /d C:\cyrius-tests\<dir> && aip.exe"
echo %errorlevel%
cmd /v /c "cd /d C:\cyrius-tests\<dir> && aip.exe & echo !errorlevel!"
```

Expected: 42 both ways. Recorded at 6.6.17: 1, then 42.

## Root cause

Unknown — speculation only. `async_with_timeout` (`lib/async_win.cyr:628-648`) races the task against a sentinel
task (`_async_timeout_sentinel`) whose one-shot manual-reset waitable timer is waited on through
`RegisterWaitForSingleObject` and posts a completion; `_async_pump(rt, handle, sentinel)` returns on whichever
completes first. Candidates: the sentinel's relative due time (`ms * 10000` 100-ns units, negative) or the timer's
creation failing into an immediate "deadline" path in that process context; the spawned task's completion not being
posted before the sentinel's when the console / job differs between the two launch forms. Step 1 (`async_interval`)
passes in both, so the reactor itself runs.

## Proposed fix

Instrument on cass first: return a distinct code for "sentinel fired" vs "task not DONE", and log the timer
create / set results under both launch forms; fix what that shows. Then run `aip.exe` in the release gate under BOTH
launch forms so the launch context is covered.
