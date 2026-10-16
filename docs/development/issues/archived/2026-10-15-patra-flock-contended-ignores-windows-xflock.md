# patra on Windows still treats a contended `xflock` as "no lock can be had": `_pt_flock_contended` accepts EAGAIN only on Linux / macOS — RESOLVED

> ✅ **RESOLVED in v6.7.13** (the fold patra 1.16.3, the user's tag @b8722b7, refolded byte-identical in 48a51b60: `_pt_flock_contended` reads a contended `xflock` (-11, `LockFileEx` since cyrius 6.7.12) as contended on Windows too, so a contended `patra_open` defers to WAL recovery instead of judging the header unlocked; the "Windows has no flock" comments are rewritten and `docs/ecosystem.md`'s patra row no longer says recovery never runs on open. patra's CI on the release commit 18 / 18 in an isolated copy; the contended-open rows pass on real cass. The transaction rows' lost writes on Windows were the other half — `xflock` dropping a re-taken lock — fixed in `lib/io.cyr` by this release's LIB-1. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.12 release-docs pass (the windows lane's xflock bite, WN-1, did not
carry patra's side). Since 6.7.12 `xflock` on Windows is `LockFileEx` / `UnlockFileEx` and answers a contended
non-blocking lock with -11, but `lib/patra.cyr`'s `_pt_flock_contended` still recognises EAGAIN only under Linux / macOS,
so a contended `patra_open` on Windows reads -11 as "no lock can be had" and judges the header unlocked (the pre-6.7.12
path). Its comments still say "Windows has no flock and returns -1" (`_pt_flock`, `_pt_flock_contended`, `patra_open`),
and `docs/ecosystem.md`'s patra row says "no flock, so recovery never runs on open".
**Placement:** 6.7.13 — repair 3: struct values (a fold patch: patra 1.16.3, which the user tags before the refold; placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Medium — Windows gets no WAL recovery under contention although the lock now exists.

## Fix

In patra: `_pt_flock_contended` accepts EAGAIN (-11) on Windows too; the three comments say what Windows does since cyrius
6.7.12; a contended-open row on wine / cass. Then refold; the ecosystem row follows.
