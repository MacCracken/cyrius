# `#104 mountlist` — an AGNOS syscall peer for the mount-table getter

**Status:** ✅ **SHIPPED at v6.5.42 — CLOSED.** `SYS_MOUNTLIST = 104` + `fn sys_mountlist(buf, max)` are in `lib/syscalls_x86_64_agnos.cyr`, in the enum beside `statfs`#103 and with the wrapper beside `proclist`#99 — the other enumeration primitive with the identical `(buf, max) -> count / -1` shape. Verified: compiles clean under `CYRIUS_TARGET_AGNOS=1` into a valid agnos ELF, and correctly does NOT link on Linux (the deliberate honest-gap that `sys_statfs` records — inventing Linux/macOS/aarch64/PE numbers from memory is the defect class v6.5.36 and v6.5.37 spent two releases repairing).

⭐ **This closes the last gap: cyrius's agnos peer is now at FULL parity with the frozen contract — 105 numbers on both sides, 0 disagreements, 0 awaiting a peer.** agnos's `syscall-abi-check.sh`, which this filing records as RED at `kernel 105 · abi-doc 105 · cyrius 104`, should read 105/105/105.

⚠ **Every claim in this filing was verified against the authoritative sources before implementing**, not taken from the filing: the record layout, the `max`-is-a-count semantics and the error cases all match `agnos-userland-abi.md:235` and the kernel arm at `kernel/core/syscall.cyr:9382` exactly. The filing was accurate in every particular — recorded because the last several filings this repo acted on were not.

⭐ **A gate came out of it that outlives this one syscall.** `tests/gates/platform/agnos_abi_doc_parity.sh` mechanizes the per-reactive-window manual diff CLAUDE.md asks for, and enforces the asymmetry this filing itself argues for: a doc-only number is REPORTED and passes (the kernel arm legitimately ships first), while a number that MEANS something different on each side fails loudly. That widen class is precisely what no compile-time check can see — cyrius compiles any `syscall(N, ...)` and the kernel dispatches it.
**Ask:** add `SYS_MOUNTLIST = 104` + `fn sys_mountlist(buf, max)` to `lib/syscalls_x86_64_agnos.cyr`.
**Placement:** 6.x — one enum row and one wrapper, the same shape as `#99 proclist`, `#101 readdir_at`
and `#103 statfs` before it.
**Reporter:** agnos (kernel), on behalf of **crab** (the AGNOS file manager) and **chakshu** (the AGNOS
system monitor) — two independent consumers asked for the same capability on the same day.
**Affects:** cyrius 6.5.41 (current agnos pin). No cyrius defect is being reported here.
**Severity:** Low — nothing is broken; ring 3 can already issue the number raw, which is exactly what
the agnos gate does. This is surface, not a fix.

## What shipped on the agnos side

`mountlist(buf, max) -> count / -1`, agnos **1.56.59**, arm in `kernel/core/syscall.cyr` (`num == 104`).
Copies the live `{prefix -> backend}` mount table to ring 3. **80-byte** records, all-u64 header (the
no-sub-word-fields rule agnos's ABI doc §4.1 already follows, so there is no Cyrius struct-padding
ambiguity to resolve in the wrapper):

```
+0   u64  backend    FsBackend — 1 = ext2 · 2 = FAT · 3 = exFAT (0 = FS_NONE never emitted)
+8   u64  prefixlen  1..64
+16  64B  prefix     NUL-PADDED to the full 64 bytes
```

`max` is a **record count**, not a byte length. Errors: `-1` for a bad pointer, a wrapping `max`, or
`max < 1`.

Boot-proven, not merely compiled: `scripts/harness/mountlist-test.py` boots it under gnoboot + OVMF and
runs `tests/mountlist/mlist.cyr` from ring 3, which asserts the table's SHAPE — backend in range,
prefix NUL-padded past its length, root present, the `max` budget honoured, and a wrapping `max`
refused. Exit 95. Mutation-proven: removing the budget check reddens it with the right message.

## The wrapper we would like

```cyrius
SYS_MOUNTLIST = 104;    # mountlist(buf, max) -> record count / -1   (agnos 1.56.59)

fn sys_mountlist(buf, max): i64 {
    return syscall(SYS_MOUNTLIST, buf, max);
}
```

Two arguments, no pointer the kernel writes through beyond `buf`, no cursor, no flags. Simpler than
`#101 readdir_at`, whose fourth argument was the reason that one needed care.

## ⚠ Two notes that are ours, not asks

**We are not asking you to hurry.** agnos's `syscall-abi-check.sh` gate now reads
`kernel 105 · abi-doc 105 · cyrius 104` and is RED, which is the documented, expected state for a
newly minted number — `symlink`#63 and `readlink`#70 both shipped in exactly this condition and both
peers landed later. agnos's own state.md records the ruling: *do not "fix" that gate by editing
cyrius, and do not weaken the gate.* This filing IS the fix, and it lands on your schedule.

**A raw call is a supported path, deliberately.** `tests/mountlist/mlist.cyr` issues `syscall(104, …)`
directly and will keep doing so after the wrapper lands, for the reason `tests/readdir/rdat.cyr`
already records: it is the ABI exerciser, and routing it through the stdlib wrapper would make it test
the wrapper's agreement with itself rather than the kernel's arm.

## Why the number was minted rather than an existing one widened

`mount` **#11** takes no arguments in agnos's frozen ABI table. Widening it would have been the obvious
move and is the wrong one, for the measured reason `#100` and `#101` both record: unused syscall
argument registers carry **stale values, not zero**, so a widened `#11` would hand every already-shipped
caller an arbitrary pointer. crab's filing asked for a new number on the same grounds.

## Context — why enumeration and not a probe

Recorded here because it is the part a reader is most likely to think is redundant surface. `statfs`
**#103** already answers *"is this string mounted"*. It cannot answer *"are these two the same volume"* —
and agnos's `vfs_mount_init` gives an ext2-less boot the **same backend under both `/` and its
`/mnt/…` prefix**, which its own comment calls "harmless redundant aliases". Harmless to routing; to a
file-manager sidebar they are one volume listed twice, and no probe can tell them apart. The backend id
travelling alongside the prefix is what makes them distinguishable, which is why this is a getter over
the table rather than more probing.
