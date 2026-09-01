# `lib/syscalls_x86_64_agnos.cyr` has no `sys_statfs`#103 peer, so agnos ring 3 cannot ask how full a disk is

**Status:** 🟡 **OPEN** — one enum entry, one three-line wrapper, and (optionally) a struct accessor set. Additive; nothing existing changes.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — the `SysNrAgnos` enum and a `sys_statfs` beside the existing `sys_stat`#33, whose 3-argument path+buffer shape it mirrors exactly.
**Filed:** 2026-09-01, by agnos. agnos minted the number; cyrius owns the peer.
**Affects:** cyrius **6.5.36**. Every earlier release too, but #103 only exists as of agnos 1.56.56 (ext2) / 1.56.57 (all three filesystems).
**Severity:** **Low as a defect, blocking as a gate and as a feature.** Nothing is broken — ring 3 can call it by raw number today, and agnos's own selftests do. But agnos's `scripts/check.sh` gate *"syscall ABI (kernel/doc/cyrius agree)"* compares the three number sets and currently reads `kernel 104 · abi-doc 104 · cyrius 101`. ⚠ **#103 is the third number in that gap**, alongside `#96 fork` and `#102 lstat`, both already filed here.

## The ask

```
SYS_STATFS = 103
fn sys_statfs(path, pathlen, buf): i64 { return syscall(SYS_STATFS, path, pathlen, buf); }
```

Three arguments, same shape and same return as the existing `sys_stat`#33 — `0` on success, `-1`
otherwise. The buffer is **32 bytes**, not 48.

## The record — 32 bytes, 4× u64 little-endian

Normative definition is agnos [`docs/development/agnos-userland-abi.md`](https://github.com/MacCracken/agnosticos) §4.7.

| Offset | Field | Meaning |
|---|---|---|
| 0 | `f_bsize` | bytes per allocation unit — an ext2 **block**, a FAT or exFAT **cluster** |
| 8 | `f_blocks` | total units in the filesystem |
| 16 | `f_bfree` | free units |
| 24 | `f_bavail` | free units available to a caller (`f_bfree` minus the filesystem's reservation, clamped at 0) |

The kernel reports **units, not bytes** — userland does the multiply, so the record never has to carry
a scale factor. Total bytes = `f_blocks * f_bsize`; free bytes = `f_bfree * f_bsize`.

⛔ **THE RECORD SIZE IS FROZEN ABI, AND UNUSUALLY HARD-FROZEN.** `statfs` is 3-arg with **no length
parameter** — the kernel validates a hardcoded 32 bytes, exactly as `stat`#33 validates a hardcoded 48.
So unlike `uname`#34 / `sysinfo`#35, whose contract is "future fields append at the tail and bump the
minimum `len`", **this record cannot grow**: there is no `len` for a caller to raise and no way for the
kernel to tell an old caller from a new one. A wider record needs a new syscall number. If cyrius adds
a typed accessor set, it should reflect exactly these four fields and no speculative fifth.

## Why it exists — a named consumer that could not draw a UI without it

**crab**'s M6 sidebar has a VOLUMES section with a capacity bar per mount. Everything needed to *draw*
it already shipped — dhancha's `LIST` for the rows, `PROGRESS` (0.9.22) for the bars, `DH_FLAG_INERT`
(0.9.23) for the section headers. What crab could not do was **fill it in**: there was no way to ask
how large a filesystem is, how much is free, or what is mounted.

There is no ring-3 workaround, and that is what made it a syscall rather than a library problem:
`stat` reports a **file**, not the filesystem under it, and walking a tree to sum sizes answers a
different question (what is used *here*) at a cost proportional to the disk.

crab declined to ship a half-populated panel — *"a panel with one working section and three empty
headers is the painted-but-inert failure this stack's own docs keep naming"* — so the row stayed dark
until the kernel could answer.

## What the kernel side already does, so the wrapper does not have to

All three agnos filesystems answer `#103` as of 1.56.57, mount-routed by path:

| backend | `f_bfree` source | cost |
|---|---|---|
| ext2 | `s_free_blocks_count`, maintained live by the block allocator | O(1), no disk read |
| FAT | full scan of the FAT counting raw `0` entries | one block read per FAT sector |
| exFAT | popcount of zero bits in the allocation bitmap | one block read per 512 B of bitmap |

⚠ **`f_bfree` is a live count on every backend, not a mount-time snapshot** — agnos's gates assert it
by writing a file and requiring the count to drop. A wrapper should not cache the result.

⚠ **`f_bavail == f_bfree` on FAT and exFAT** — neither format has a reservation concept. Only ext2's
can differ, and only when `s_r_blocks_count` is non-zero.

⚠ **The call can legitimately return -1**, and a wrapper should pass that through rather than
normalising it: a path that does not resolve is refused (this is deliberate — it is the assertion that
catches an implementation ignoring its path argument), and FAT/exFAT refuse rather than guess when a
FAT or bitmap read fails.

## Precedent

Same kernel-mints-it / cyrius-owns-the-peer split as
[`2026-08-30-agnos-sys-lstat-102-peer.md`](2026-08-30-agnos-sys-lstat-102-peer.md) and
[`2026-08-30-agnos-sys-fork-96-peer.md`](2026-08-30-agnos-sys-fork-96-peer.md). Landing all three
closes the agnos ABI gate; landing any one of them narrows it.
