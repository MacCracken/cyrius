# Three crossos `.tcyr` files read red on a local emulated target that no runner covers — ns_rootfs_syscalls under qemu-aarch64 (5 rows, process_vm_readv / writev -38) and on the x86_64 cxvm (14 rows, calls cxvm refuses), tls_system_trust_store's PE build under wine (77 rows, the system set does not load) — with no named not-run, so a local reproduction reads them as defects — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 by the 6.7.16 platform lane's gate (the per-file exit-code loop
over the lane's .tcyr on x86_64, qemu-aarch64, the x86_64 cxvm and wine), and proved PRE-EXISTING at the lane base
480de63eb (a `git archive` of it with its own build/cycc, the cx / aarch64 / PE compilers and cxvm built from it).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — no runner runs these files there (check.sh's corpus gates run x86_64; the cross-OS legs run the
corpus natively on pi / ecb / ach / cass, where all three are green; the cx crossos leg runs four other files), so
no gate is red. The cost is a misread local reproduction: CLAUDE.md sends aarch64 repros to qemu-aarch64, and the
6.7.16 D28 shape (a row whose call the target lacks prints `not run: …`) exists only for a Windows host's cxvm.
No boundary is crossed (no ledger id).

## Reproduction (from the repo root; each run in its own empty directory)

```sh
build/cycc_aarch64 < tests/tcyr/crossos/ns_rootfs_syscalls.tcyr > ns.a64 && qemu-aarch64 ./ns.a64
build/cycc_cx < tests/tcyr/crossos/ns_rootfs_syscalls.tcyr > ns.cyx && build/cxvm < ns.cyx
build/cycc_win_cross < tests/tcyr/crossos/tls_system_trust_store.tcyr > ts.exe && WINEPREFIX=<fresh> wine ts.exe
```

```text
                                       lane base 480de63eb          lane l6716-platform (2b89c707d+)
ns_rootfs_syscalls, qemu-aarch64       14 passed, 5 failed (rc 5)   14 passed, 5 failed (rc 5)
ns_rootfs_syscalls, x86_64 cxvm         1 passed, 17 failed (rc 17)  4 passed, 14 failed (rc 14)
tls_system_trust_store, wine 11.20    143 passed, 77 failed (rc 77) 170 passed, 77 failed (rc 77)
(real hardware: pi 19 / 19; cass 301 / 301 — green)
```

- qemu-aarch64 (11.1.2): `FAIL: process_vm_readv copied 16 bytes (got -38, expected 16)` and its four followers —
  qemu-user does not implement process_vm_readv / process_vm_writev (pi, real hardware, passes them).
- x86_64 cxvm: chroot, capget, capset, process_vm_readv / writev and unlinkat (263) answer cxvm's -38 (6.7.14's
  D55: an unlisted number never reaches the host), and pivot_root's row reads 0; the lane's mknodat route turned the
  FIFO's make / stat rows green (17 → 14), and `the FIFO unlinks` still fails because the row calls
  `sys_unlinkat`, which cxvm does not serve (`sys_unlink`, 87, it does). No lib/ caller of `sys_unlinkat` exists.
- wine (a fresh private prefix): `set_ca_system rc -12, 0 roots installed` — the prefix's ROOT store holds no
  certificates, so every row needing the system set fails; the same 77 at the base.

## Root cause

Each target lacks the call (qemu-user, cxvm by design) or the data (a fresh wine prefix's ROOT store); the files
assert the call's Linux / Windows answer unconditionally on every build.

## Fix direction

Either name these as not run on that target (the D28 shape: on -38 from a call the target lacks, print
`not run: …` instead of failing; the wine store as "no system roots in this prefix"), or record them in
docs/development/dev-tools-linux.md beside the binfmt note as known emulator gaps. Which is the user's call.
