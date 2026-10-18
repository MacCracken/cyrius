# cxvm's F_GETFL drops O_LARGEFILE off x86_64 Linux: the x86 cxvm answers 0x8001 for fd 1, the aarch64 and macOS ones 0x1 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform, after 0771db778),
cxvm built from the lane's tree: x86_64 Linux (`build/cycc`), aarch64 Linux under qemu-aarch64 (`cycc_aarch64`),
ecb (`CYRIUS_MACHO_ARM=1 cycc_aarch64` + `codesign -s -`), ach (`CYRIUS_MACHO=1 cycc`); the lane measured pi at 1
too (unit P4).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 platform review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — the .cyx ABI is x86_64 Linux's, and one guest program reads a different F_GETFL on different
hosts for the same open. No in-tree cx program tests the bit; no boundary is crossed (no ledger id).
**Found:** the 6.7.15 platform lane's review of the host-dispatch fix
(issues/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md). docs/platform-status.md now says
"off x86_64 Linux and Windows `F_GETFL` reports only the nine mapped bits" (the review fix 0771db778); this issue is
whether that is the contract or a gap.

## Reproduction

`getfl.cyr`, compiled once with `cycc_cx` (no diagnostic), run as `./cxvm < getfl.cyx > /dev/null; echo $?`:

```cyr
# fcntl(1, F_GETFL) on a cx guest: x86_64 Linux's answer carries O_LARGEFILE (0x8000).
var r = syscall(72, 1, 3, 0);
syscall(60, r % 200);
```

```text
x86_64 Linux cxvm      169   # 0x8001 = O_WRONLY | O_LARGEFILE
aarch64 cxvm (qemu)      1
ecb cxvm                 1
ach cxvm                 1
```

## Root cause

programs/cxvm.cyr `_cx_flags_back` (F_GETFL's answer, host bits -> the guest's x86-Linux bits) maps the access mode
and eight flags and drops everything else; on aarch64 Linux the kernel reports O_LARGEFILE as 0x20000 (x86's
O_NOFOLLOW, which is why it is not passed through), and that bit is dropped instead of mapped to x86's 0x8000. On an
x86_64 Linux host `_cx_flags_native()` is 1 and the kernel's word goes back as it is, O_LARGEFILE included.
tests/fixtures/cx_host_dispatch.cyr pins O_APPEND / O_NONBLOCK and "never 0x20000", not 0x8000. (Darwin has no
O_LARGEFILE; x86_64 Linux reports it for every open on a 64-bit kernel.)

## Fix direction

One of, the user's call: (a) map aarch64 Linux's O_LARGEFILE 0x20000 to 0x8000 in `_cx_flags_back` and report
0x8000 on Darwin too (a 64-bit host's every file is large), so F_GETFL answers x86_64 Linux's word on every host; or
(b) keep the nine bits as the contract and mask the x86_64 Linux host to the same nine. Row: the repro answers the
same on every host's cxvm; a fixture row pinning the answer, run by the cross-OS legs.
