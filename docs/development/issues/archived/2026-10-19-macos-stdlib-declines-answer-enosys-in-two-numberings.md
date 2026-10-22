# On macOS the stdlib's "no route here" answer is -ENOSYS in two numberings: `sys_prctl` and `sys_gettid` answer -38 (Linux's ENOSYS, Darwin's ENOTSOCK) where the other 52 declined wrappers answer -78 (Darwin's ENOSYS) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PP-5, `610db0b5e` — 6.7.16's D76, the user, 2026-10-20: "-78, Darwin's ENOSYS". `sys_prctl` (`lib/syscalls_linux_common.cyr`) and `sys_gettid` (`lib/sys.cyr`) answer `0 - 78` in their macOS arms, and `sys_sched_kicks` — the triage's third, which had no macOS arm and fell into its off-agnos -38 — gains one; Linux, Windows, agnos and cx are unchanged. The filed enosys_mac prints `-78 -78 -78` on ecb and on ach (was `-38 -38 -78`). Rows: the new census gate `tests/gates/platform/macos_declines_answer_darwin_enosys.sh` (every decline each Mac reaches over the `#ifdef` / `#ifndef` / `#else` / `#ifplat` frames and fn bodies, the per-target peers derived from the include sites, 11 known-verdict controls, floors ≥ 48 reachable -78 declines per Mac — 51 now) and the new `tests/tcyr/crossos/declines_answer_host_enosys.tcyr` (macOS prctl / gettid / sched_kicks / mount -78; Linux the real calls; Windows / cx gettid -38), with `sysinfo_uname.tcyr` and `platform/sandbox_syscalls.tcyr` pinning -78 on macOS — green on ecb, ach, pi, qemu-aarch64, natively and under wine. Mutations each RED: the pre-fix lib (naming exactly the three sites), each arm reverted, `sys_utimensat`'s macOS arm deleted, the arm64 peer's `sys_epoll_wait` decline set to -38, and the two scanner-rule mutants against the controls; the new tcyr on the pre-fix lib reads 3 RED on ecb and ach. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 platform lane (branch l6716-platform, unit P2), probes
built from the lane's tree (`CYRIUS_MACHO=1 cycc` for ach, `CYRIUS_MACHO_ARM=1 cycc_aarch64` + `codesign -s -` for
ecb). The lane does not change these wrappers.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; p16 lane, wave 3, unit PP2) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D76 — -78, Darwin's ENOSYS.
**Severity:** Low — a macOS program that tests a declined call against the host's ENOSYS (`== 0 - 78`, what the
other macOS declines answer) misreads these two, and one that tests `== 0 - 38` reads Darwin's ENOTSOCK as
"not implemented" everywhere else. No boundary is crossed (no ledger id).
**Found:** in passing while fixing issues/archived/2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md (6.7.16 P2):
cxvm now maps a Darwin host's errno back to Linux's, which needs every macOS stdlib answer to be in Darwin's
numbering; a census of the `#ifdef CYRIUS_TARGET_MACOS` arms in lib/ that decline found 52 answering -78 and two
answering -38. Neither of the two is a call cxvm serves, so the cx map is not affected.

## Reproduction

`enosys_mac.cyr`, built for each Mac and run there:

```cyr
include "lib/syscalls.cyr"
include "lib/sys.cyr"
var out[128];
var on = 0;
fn pd(v): i64 {
    if (v < 0) { store8(&out + on, 45); on = on + 1; v = 0 - v; }
    var t[24];
    var n = 0;
    if (v == 0) { store8(&t, 48); n = 1; }
    while (v > 0) { store8(&t + n, 48 + v % 10); v = v / 10; n = n + 1; }
    while (n > 0) { n = n - 1; store8(&out + on, load8(&t + n)); on = on + 1; }
    store8(&out + on, 32); on = on + 1;
    return 0;
}
pd(sys_prctl(3, 0, 0, 0, 0));     # PR_GET_DUMPABLE: no Darwin route
pd(sys_gettid());                 # no Darwin route wired
pd(sys_mount("none", "/nonexistent", "tmpfs", 0, 0));   # no Darwin route: the -78 convention
store8(&out + on, 10); on = on + 1;
syscall(1, 1, &out, on);
syscall(60, 0);
```

```text
ach (x86_64 macOS)   -38 -38 -78
ecb (arm64 macOS)    -38 -38 -78
```

## Root cause

lib/syscalls_linux_common.cyr `sys_prctl` (its `#ifdef CYRIUS_TARGET_MACOS` arm, line ~392: `return 0 - 38;`, the
6.5.15 fix that stopped the raw svc) and lib/sys.cyr `sys_gettid` (its macOS arm, line ~527: `return 0 - 38;   #
ENOSYS — Darwin __thread_selfid not yet wired`) spell -ENOSYS in Linux's number. Every other declining macOS arm
— sys_mount, sys_reboot, the epoll / timerfd / signalfd / inotify wrappers, lib/syscalls_macos.cyr's and
lib/syscalls_aarch64_linux.cyr's own, lib/thread_local.cyr — answers -78, Darwin's ENOSYS, matching what the Mach-O
syscall path answers for a real BSD failure (the negated BSD errno).

## Fix direction

Answer -78 in both macOS arms (the comments already say ENOSYS) — a changed value on macOS, so the user's call —
and a census row (a gate reading the `#ifdef CYRIUS_TARGET_MACOS` arms of lib/ for `return 0 - 38`).
