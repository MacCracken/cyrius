# `xflock` has no Windows route (`LockFileEx` not wired) — patra's crash recovery never runs on Windows (asked by patra) — RESOLVED

> ✅ **RESOLVED in v6.7.12** (WN-1, `163d1a85`: `xflock` on Windows goes through two new kernel32 reroutes, 0xF04C `LockFileEx` and 0xF04D `UnlockFileEx`, and locks ONE sentinel byte at offset 2^63 − 1, length 1 — Windows byte locks are mandatory, so the lock excludes other lockers and leaves every handle's reads and writes of the data alone (the filing's design). The filed repro exits 11 on PE under wine and on cass, where it exited 10 (rc -1); Linux 11 unchanged. A held `LOCK_NB` is -11 (EAGAIN on PE), `LOCK_UN` of a lock not held 0, a bad op -22, any other failure -1, and a compiler without the reroutes fails closed to -1. No decision needed (fixed to the source). patra's open-time WAL recovery now runs on Windows when its `LOCK_EX | LOCK_NB` is granted; its `_pt_flock_contended` still reads a contended -11 as "no lock can be had" on Windows until patra's own release adopts -11 (the fold-side change the filing names). Rows: NEW `crossos/xflock_two_handle.tcyr` (36 rows — two handles, the data readable and writable under the lock, SH ↔ EX on one handle; 36/36 on cass, wine, x86_64, qemu-aarch64, ecb, ach and pi), NEW `tests/gates/platform/pe_lockfileex_reroute.sh` (4 mutants RED — the sentinel-at-0 mutant passes wine's run and fails 5 rows on cass). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: a probe that opens a file and calls
`xflock(fd, LOCK_EX)` gets 0 on Linux (exit 11) and **-1** as a PE32+ under wine (exit 10); `lib/io.cyr:447-449`
still reads `return -1; # Windows: no flock (LockFileEx — not wired)`. Not re-run on cass (real Windows) — the
failing arm is a constant.
**Placement:** 6.7.12 — repair 2: the platform release (windows lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** patra 1.15.0's Windows transaction work (its `_pt_fdatasync` / `_pt_flock` notes); filed 2026-10-08
from roadmap.md.
**Severity:** Medium — no crash, but a fold's durability guarantee is silently absent on one target, with no
fold-side workaround.
**Affects:** cycc ≤ 6.7.6 `lib/io.cyr` (`CYRIUS_TARGET_WIN`).

## Summary

`xflock(fd, op)` (`lib/io.cyr:443`) dispatches advisory whole-file locking per target — Linux `SYS_FLOCK`, both
Macs via 73 → BSD 131, agnos #59 — and returns -1 on Windows. patra takes every lock through it
(`_pt_flock`, `lib/patra.cyr:171`; `patra_lock_ex` / `_sh` / `unlock`, `:204-208`), and its open-time WAL recovery
runs only when the non-blocking exclusive lock is granted (`lib/patra.cyr:5442`). On Windows the lock is never
granted, so recovery never runs: per patra's own note (`lib/patra.cyr:185-188`), the next BEGIN's `O_TRUNC`
discards a crashed transaction's WAL and its partial writes stay applied — transactions work, crash atomicity does
not.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("fl_probe.tmp", O_RDWR | O_CREAT, 420);
var r = xflock(fd, 2);                       # LOCK_EX
syscall(SYS_EXIT, 10 + r + 1);               # Linux 11 (rc 0); Windows 10 (rc -1)
```

```sh
cd /home/macro/Repos/cyrius
./build/cycc < fl.cyr > fl && chmod +x fl && ./fl; echo $?                         # 11
CYRIUS_TARGET_WIN=1 ./build/cycc < fl.cyr > fl.exe && wine ./fl.exe; echo $?        # 10
```

## Root cause

No PE reroute exists for kernel32 `LockFileEx` / `UnlockFileEx` (the reroute table ends at 0xF04B GetLastError —
`src/frontend/parse_expr.cyr:942`), so `xflock`'s Windows arm is a constant.

## Proposed fix

Two new kernel32 reroutes (`LockFileEx`, `UnlockFileEx`) in `src/backend/pe/emit.cyr` + the import table + the
routed-number note, then `xflock`'s Windows arm: `LOCK_EX` → `LOCKFILE_EXCLUSIVE_LOCK` (2), `LOCK_SH` → 0, `+LOCK_NB`
→ `LOCKFILE_FAIL_IMMEDIATELY` (1), `LOCK_UN` → `UnlockFileEx`, with a zeroed `OVERLAPPED` (32 B) and 6 arguments
(stack args under Win64). ⚠ Windows byte-range locks are MANDATORY, not advisory: locking the file's real bytes would
make patra's own reads and writes through a second handle fail. Emulate flock by locking ONE sentinel byte far past
any real offset (e.g. offset 2^63 − 1, length 1), so the lock excludes other lockers only. Map
`ERROR_LOCK_VIOLATION` / `ERROR_IO_PENDING` to -11 (EAGAIN, the `LOCK_NB` contract). Gates: a
`tests/tcyr/crossos/` test (two handles: the second `LOCK_EX | LOCK_NB` is refused, `LOCK_UN` releases it, reads still
work) run on **cass** — under the excluded `C:\cyrius-tests` (Defender) — and on ecb / ach / pi for the other arms.
patra then drops its Windows caveat in its own release.
