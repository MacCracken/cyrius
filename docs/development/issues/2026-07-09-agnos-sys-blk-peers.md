# agnos raw block-device `#75-80` has no `sys_blk_*` peer — the installer + mkfs tools hardcode raw syscall numbers

**Filed:** 2026-07-09 (agnos 1.53.10 — the native-install primitive; kernel half shipped + QEMU-proven).
**Severity:** **P3 — ABI-completeness / stdlib surface.** A raw-syscall stopgap works and is proven
(`blk-test/blkprobe.cyr` + `blkwr.cyr` call `syscall(75..80)` directly), so nothing is *blocked* — but
without the named wrappers the band is invisible to every other program and to the ABI doc, so the
native-install primitive doesn't trickle out to its real consumers (agnova, a sovereign mkfs/partition tool).
**Component:** `lib/syscalls_x86_64_agnos.cyr` — the agnos syscall wrapper bands. The socket/file peers
end at `SYS_READLINK = 70`, then the shm band `#71-74` (just landed, v6.4.34); there is **no `sys_blk_*` band**.

## The gap

agnos 1.53.10 added **ring-3 raw block-device syscalls** so a native installer can enumerate, read, and
(deliberately, gated) WRITE raw disk sectors — the primitive agnova needs to partition + format a target
disk with no Linux `parted`/`mkfs`. Design decision: the kernel exposes raw sector I/O; **userland builds
the GPT table + `mkfs` structures** (as every OS does). Both paths are QEMU-proven from ring 3 against a
real NVMe/GPT disk (`blk-ring3-smoke.sh` exit 95, `blk-write-smoke.sh` exit 96).

The proof tools drive it today with **bare `syscall(75..80)` literals**:

```cyrius
# blk-test/blkprobe.cyr / blkwr.cyr — the current stopgap (works, hardcodes the numbers)
var n = syscall(75, &ebuf, 192);        # blk_enum
var h = syscall(76, tag, 0);            # blk_open(tag, RO)
var r = syscall(77, h, 1, &sec, 1);     # blk_read(h, lba, buf, nsec)  — 4-arg (nsec rides r10)
        syscall(78, h, lba, &sec, 1);   # blk_write(h, lba, buf, nsec) — GATED
        syscall(79, h, &ibuf);          # blk_info
        syscall(80, h);                 # blk_close
```

The next consumer (agnova's executor port, a sovereign mkfs) would have to re-derive `75..80` from the
kernel source. The named wrappers are where the numbers get documented + reused.

## The kernel ABI to wire against (verified from agnos `kernel/core/syscall.cyr`, QEMU-proven 1.53.10)

Handle = the backend tag (`BLK_VIRTIO..BLK_RAMDISK`, 1..5), validated against `blk_registered`.
`blk_read`/`blk_write` are **4-arg** — `nsec` rides `a4=r10` (like `readlink`#70), so the wrappers pass 4 args.

```
blk_enum (buf=a1, cap=a2)                     -> registered-device count / -1   # #75  writes {tag,capacity_lbas,lba_bytes}*count (24 B/entry)
blk_open (tag=a1, mode=a2)                    -> handle(=tag) / arm-ack(0) / -1 # #76  mode 0=RO; 1=RW (gated); == BLK_RW_ARM_MAGIC arms
blk_read (h=a1, lba=a2, buf=a3, nsec=a4)      -> nsec / -1                      # #77  raw sector read (bounds-checked)
blk_write(h=a1, lba=a2, buf=a3, nsec=a4)      -> nsec / -1                      # #78  raw sector write + flush — GATED on the arm
blk_info (h=a1, out=a2)                        -> 0 / -1                        # #79  writes {capacity_lbas, lba_bytes}
blk_close(h=a1)                                -> 0 / -1                        # #80
```

**Capability gate (important):** raw WRITE (and RW-open) is OFF by default; enabled only by a deliberate arm
`blk_open(_, BLK_RW_ARM_MAGIC = 0x424C4B5F5257)` — the kernel enforces this, the wrappers only marshal.
Numbers `#75-80` = the next free agnos band after shm `#74`.

## The peers to add (mirror the `sys_shm_*` band, agnos-only)

```cyrius
# in the agnos Sys enum, after SYS_SHM_FREE = 74:
    SYS_BLK_ENUM  = 75;   # blk_enum(buf, cap) → count / -1
    SYS_BLK_OPEN  = 76;   # blk_open(tag, mode) → handle / arm-ack(0) / -1  (mode 1=RW is capability-gated)
    SYS_BLK_READ  = 77;   # blk_read(h, lba, buf, nsec) → nsec / -1
    SYS_BLK_WRITE = 78;   # blk_write(h, lba, buf, nsec) → nsec / -1  (GATED: arm via blk_open(_, magic))
    SYS_BLK_INFO  = 79;   # blk_info(h, out) → 0 / -1
    SYS_BLK_CLOSE = 80;   # blk_close(h) → 0 / -1

# Raw block-device access (agnos 1.53.10) — the native-install primitive. RW is capability-gated
# kernel-side; these wrappers only marshal. blk_read/blk_write are the a4=r10 5-reg calls (like readlink#70).
fn sys_blk_enum(buf, cap): i64           { return syscall(SYS_BLK_ENUM, buf, cap); }
fn sys_blk_open(tag, mode): i64          { return syscall(SYS_BLK_OPEN, tag, mode); }
fn sys_blk_read(h, lba, buf, nsec): i64  { return syscall(SYS_BLK_READ, h, lba, buf, nsec); }
fn sys_blk_write(h, lba, buf, nsec): i64 { return syscall(SYS_BLK_WRITE, h, lba, buf, nsec); }
fn sys_blk_info(h, out): i64             { return syscall(SYS_BLK_INFO, h, out); }
fn sys_blk_close(h): i64                 { return syscall(SYS_BLK_CLOSE, h); }
```

No Linux/Windows/mac twin — the band is agnos-kernel-only (host installers use `/dev` + `parted`/`mkfs`, a
different world). A consumer that wants a portable abstraction keeps its own per-target split; these
wrappers are the agnos leg. `_agnos`-guarded like the rest of the file, so a Linux build never sees them.

## Done-criteria

`sys_blk_enum/open/read/write/info/close` are in `lib/syscalls_x86_64_agnos.cyr` after the `sys_shm_*` band,
agnos-target compile verified, default cycc byte-identical, api-surface snapshot regenerated. On landing,
consumers (agnova executor port, sovereign mkfs) call the native `sys_blk_*` wrappers instead of raw literals.

## Cross-refs

- agnos-side mirror of this ticket: `agnos/docs/development/issues/2026-07-09-cyrius-block-device-wrappers.md`
- agnos kernel: `kernel/core/syscall.cyr` (the `blk_*_sys` helpers + `#75-80` dispatch + the `blk_rw_armed` gate), CHANGELOG `[1.53.10]`
- design: `agnos/docs/development/issues/2026-07-09-ring3-block-device-syscalls-for-install.md`
- consumers: agnova (native installer, the executor port), a future sovereign mkfs/partition tool
- precedent: the just-landed `sys_shm_*` #71-74 band (`2026-07-09-agnos-sys-shm-peers.md`) — same "kernel half shipped, wrapper missing" shape
