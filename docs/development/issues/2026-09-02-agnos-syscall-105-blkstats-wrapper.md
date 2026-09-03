# `#105 blkstats` — an AGNOS syscall peer for per-device disk I/O counters

**Status:** 🟠 **OPEN — kernel arm SHIPPED; the cyrius peer is the only missing half.**
**Ask:** add `SYS_BLKSTATS = 105` + `fn sys_blkstats(tag, field)` to `lib/syscalls_x86_64_agnos.cyr`.
**Placement:** 6.x — one enum row and one wrapper. Same shape as `#104 mountlist` (which you shipped in
6.5.43 the same day it was filed — thank you, that closed inside a single agnos cut).
**Reporter:** agnos (kernel), on behalf of **chakshu** (the AGNOS system monitor), filing §3 of
`agnos/docs/development/issues/2026-09-02-monitor-telemetry-gaps.md`.
**Affects:** cyrius 6.5.43 (current agnos pin). No cyrius defect is being reported.
**Severity:** Low — nothing is broken; ring 3 can issue the number raw, which is what the agnos gate
does. This is surface, not a fix.

## What shipped on the agnos side

`blkstats(tag, field) -> cumulative sector count / -1`, agnos **1.56.59**, arm in
`kernel/core/syscall.cyr` (`num == 105`).

```
tag    a BLK_* device tag — 1 virtio · 2 nvme · 3 ahci · 4 usb-ms · 5 ramdisk
       (the SAME identity blk_enum#75 hands out, so a consumer enumerates with #75
        and reads each device's traffic here — no second naming scheme)
field  0 = sectors READ · 1 = sectors WRITTEN
       -1 for a tag outside 1..5 or an unknown field
```

Counted at `blk_read_on` / `blk_write_on` (`kernel/core/block.cyr`) — the one place every backend
passes through — and **only on a completed transfer**. Monotonic since boot and never reset.

## The wrapper we would like

```cyrius
SYS_BLKSTATS = 105;    # blkstats(tag, field) -> cumulative sectors / -1   (agnos 1.56.59)

fn sys_blkstats(tag, field): i64 {
    return syscall(SYS_BLKSTATS, tag, field);
}
```

Two scalar arguments, an integer return, no buffer — so there is no pointer for the wrapper to
validate and nothing about it that can be got subtly wrong. Simpler than `#104`.

## Two design notes, recorded so they are not re-derived

**Sectors, not bytes, and that is deliberate.** This layer transfers exactly one sector per call. A
byte count would have to multiply by the per-device LBA size, which can be **4096** — agnos's own
`blk_lba_bytes_ok` admits it — so a byte figure computed in the kernel would be wrong the moment a 4Kn
device appears. A consumer wanting bytes multiplies by `blk_info`#79's reported LBA size, which it
already has.

**A new number rather than widening `blk_info`#79.** #79 fills a fixed struct with no length argument,
so extending its record is an ABI break for every shipped caller. The consumer filing says as much.

## ⚠ Not urgent, and the gate is expected to be red meanwhile

agnos's `syscall-abi-check.sh` will read `kernel 106 · abi-doc 106 · cyrius 105` and be RED until this
lands. That is the documented, intended state between minting and the peer — `symlink`#63,
`readlink`#70 and `#104` all shipped in it. agnos's own ruling is *do not "fix" that gate by editing
cyrius, and do not weaken the gate*. This filing is the fix, on your schedule.
