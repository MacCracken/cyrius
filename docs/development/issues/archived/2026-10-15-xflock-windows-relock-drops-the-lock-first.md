# Windows `xflock`: re-taking a lock the handle already holds drops it first, so a waiting handle gets in — a patra transaction's writes from another handle return OK and are lost — RESOLVED

> ✅ **RESOLVED in v6.7.13** (LIB-1, `5f430337`, with the review fix LIB-1r, `c99ea1e3`: on Windows a `LOCK_SH` / `LOCK_EX` to the mode the handle already holds is a no-op returning 0 that never lets go of the sentinel byte, as under `flock(2)`. The held mode is recorded in the kernel as a lock on one more byte beside the sentinel (2^63 − 2 for `LOCK_EX`, 2^63 − 3 for `LOCK_SH`), probed with `UnlockFileEx` before the sentinel is touched, so it dies with the handle and a reused handle value inherits nothing; `LOCK_UN` drops the mode bytes and the sentinel; SH ↔ EX keeps flock's non-atomic conversion; other targets unchanged. The filed repro, patra 1.16.3's suite on cass: `test_no_mutex_flock_deadlock` 40 / 60 rows (reproduced) → 60 / 60 on 3 of 3 runs (1556 passed, 9 failed → 1557, 8; the 8 left are identical before and after and unrelated — 6 a PE failed seek answered as 0, 2 patra's `/dev/null` fixture — filed). The filed probe's shape (A re-takes the lock while B waits for it) is the new `.tcyr`'s three threaded rows: RED on cass with the 6.7.12 arm on 4 of 4 runs, 62 / 62 on 5 of 5 after. No decision needed (`flock(2)`'s contract, which `xflock` documents and patra relies on). ⚠ The filing's "wine does not reproduce": under wine those rows failed with the 6.7.12 arm on 1 of 4 runs — wine shows the gap only sometimes, so cass is the verdict. Rows: NEW `crossos/xflock_relock_keeps_lock.tcyr` (62 rows; 62 / 62 on cass, wine, x86_64, qemu-aarch64, pi, ecb and ach), `tests/gates/platform/pe_lockfileex_reroute.sh` axis 6 (static: the probe and its `return 0` before the first release, the mode bytes never the sentinel, the mode recorded after the sentinel, the release order) + axis 4's pin on `_xflock_win_unlock`'s answers (0 held / 1 not held) + the new `.tcyr` under wine, bounded; 5 mutants RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🔴 **OPEN** — found 2026-10-15 on real cass (Windows 11) while verifying patra 1.16.3 (the agent's cass run,
suite built by cyrius 6.7.12). cyrius 6.7.12's `_xflock_win` (`lib/io.cyr`; the windows lane's `xflock` through
`LockFileEx` / `UnlockFileEx` on one sentinel byte at 2^63 − 1) UNLOCKS the handle's byte before it locks again, also
when the handle already holds the same mode. Under `flock(2)` a same-mode re-lock on the fd that holds it is a no-op;
patra relies on that: every statement inside a transaction re-takes `LOCK_EX` on its own handle (`_db_lock_ex`).
On Windows a handle blocked waiting for the lock acquires it in that gap.
**Placement:** 6.7.13 — repair 3: struct values (stdlib lane, wave 2; a `lib/` defect — fixed at high priority, the user's
2026-10-09 rule; placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** High — silent data loss on Windows: in patra's `test_no_mutex_flock_deadlock` the second handle's 20
INSERTs all return `PATRA_OK` and are gone (40 of 60 rows kept). wine does not show it (it does not race the gap the
same way); real Windows does.
**Affects:** cyrius 6.7.12 (Windows `xflock` became real there; before it was -1, no lock at all).

## Reproduction (cass)

patra 1.16.3's suite (`tests/patra.tcyr`, `test_no_mutex_flock_deadlock`), built by cyrius 6.7.12 for Windows and run
under `C:\cyrius-tests`: 40 / 60 rows. Probe: thread A holds `xflock(fd_a, LOCK_EX)`; thread B blocks in
`xflock(fd_b, LOCK_EX)`; A calls `xflock(fd_a, LOCK_EX)` again → B acquires and releases the lock while A's re-lock is
in progress. A blocking lock otherwise waits correctly, and sequential two-handle writes are fine.

## Fix

`_xflock_win` keeps the mode each handle holds (a small per-handle table, or the sentinel's state), and a re-lock to the
mode the handle already holds is a no-op returning 0; a mode change (SH ↔ EX) keeps flock's non-atomic conversion
(unlock, then lock — documented). `LOCK_UN` clears the record. A row in a Windows crossos test: two handles, the holder
re-locks while the other waits — the waiter must still be waiting (or a non-blocking try fails -11) after the re-lock;
verified on cass (wine does not reproduce).
