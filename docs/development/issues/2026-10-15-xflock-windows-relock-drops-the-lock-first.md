# Windows `xflock`: re-taking a lock the handle already holds drops it first, so a waiting handle gets in — a patra transaction's writes from another handle return OK and are lost — OPEN

**Status:** 🔴 **OPEN** — found 2026-10-15 on real cass (Windows 11) while verifying patra 1.16.3 (the agent's cass run,
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
