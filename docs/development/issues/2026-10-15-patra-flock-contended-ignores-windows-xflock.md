# patra on Windows still treats a contended `xflock` as "no lock can be had": `_pt_flock_contended` accepts EAGAIN only on Linux / macOS — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.12 release-docs pass (the windows lane's xflock bite, WN-1, did not
carry patra's side). Since 6.7.12 `xflock` on Windows is `LockFileEx` / `UnlockFileEx` and answers a contended
non-blocking lock with -11, but `lib/patra.cyr`'s `_pt_flock_contended` still recognises EAGAIN only under Linux / macOS,
so a contended `patra_open` on Windows reads -11 as "no lock can be had" and judges the header unlocked (the pre-6.7.12
path). Its comments still say "Windows has no flock and returns -1" (`_pt_flock`, `_pt_flock_contended`, `patra_open`),
and `docs/ecosystem.md`'s patra row says "no flock, so recovery never runs on open".
**Placement:** 6.7.13 — repair 3: struct values (stdlib (a fold) lane; filed from the 6.7.12 release-docs pass, 2026-10-15) — never 7.x. A fold change: patra's SOURCE repo, a patch release the user tags, then the refold.
**Severity:** Medium — Windows gets no WAL recovery under contention although the lock now exists.

## Fix

In patra: `_pt_flock_contended` accepts EAGAIN (-11) on Windows too; the three comments say what Windows does since cyrius
6.7.12; a contended-open row on wine / cass. Then refold; the ecosystem row follows.
