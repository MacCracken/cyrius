# `lib/syscalls_x86_64_agnos.cyr` has no `sys_lstat`#102 peer, so agnos ring 3 cannot name the syscall it now has

**Status:** 🟡 **OPEN** — one enum entry and one three-line wrapper. Additive; nothing existing changes.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — the `SysNrAgnos` enum and a `sys_lstat` beside the
existing `sys_stat`#33 (`sys_readlink`#70 is the closest shape precedent).
**Filed:** 2026-08-30, by agnos. agnos minted the number; cyrius owns the peer.
**Affects:** cyrius **6.5.36**. Every earlier release too, but #102 only exists as of agnos 1.56.53.
**Severity:** **Low as a defect, blocking as a gate.** Nothing is broken — ring 3 can call it by raw
number today. But agnos's `scripts/check.sh` gate *"syscall ABI (kernel/doc/cyrius agree)"* compares
the three number sets and currently reads `kernel 102 · abi-doc 102 · cyrius 101`. It is the one red
gate in the agnos 1.56.53 tree.

## The ask

```
SYS_LSTAT = 102
fn sys_lstat(path, pathlen, statbuf): i64 { return syscall(SYS_LSTAT, path, pathlen, statbuf); }
```

Three arguments, same shape and same return as the existing `sys_stat`#33 — `0` on success, `-1`
otherwise, filling the same 48-byte agnos stat struct. The only kernel-side difference is that the
final path component is **not** followed.

## Why it exists — a real consumer, found on iron rather than predicted

agnos's roadmap carried `lstat` as *"blocked on a consumer (kriya `ln -s`, or ark install layouts)"*
for months. The 2026-08-30 agnos validation burn on real hardware produced a blunter one: **two
entries in the machine's root filesystem that could be listed but neither `stat`'d nor removed.**

`/sl_s` (a slow symlink whose 70-byte target does not exist) and `/lp` (a deliberate
self-referential ELOOP link) are leftover `EXT2_WRITE_SELFTEST` fixtures that a bare production
kernel never cleans up. Every `ls` and every `rm` printed `operation not permitted` — five times in
one capture.

The agnos kernel's `unlink`#30 was never at fault: it resolves the parent and calls
`ext2_unlink(parent, basename)`, which refuses only directories, and the selftest's own cleanup
removes both fixtures happily. What failed is one layer up. **kriya's `rm` is written to never follow
a symlink** and classifies every operand with `fs_lstat_at` first — and on agnos that routes here:

```
# kriya/src/lib/sys.cyr
# ⚠ NOT a true lstat on agnos … agnos has no lstat peer at all, so this routes to path-based
# sys_stat#33 — which FOLLOWS the final symlink … agnos roadmap carries `lstat` as
# unslotted-pending-a-consumer; this is that consumer.
fn k_lstat(path, buf): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return _k_agnos_stat(path, buf);                       # ⚠ FOLLOWS symlinks — see above
```

⇒ A correctly-written no-follow userland could not be correct on agnos, and the user-visible result
was undeletable files. agnos shipped the kernel half at 1.56.53.

## The consumer stopgap (this is not speculative)

kriya calls `k_lstat` today and gets following-`stat` behaviour, with the ⚠ comment above standing in
for the missing primitive. Once the peer lands, that arm becomes `syscall(SYS_LSTAT, path,
strlen(path), buf)` and the comment goes. Until then, callers can use the raw form —
`syscall(102, path, pathlen, buf)` — exactly as hapi did for `readlink`#70 before *its* peer landed.

## Compatibility

None to consider. A new enum constant and a new function; no existing number, signature or behaviour
is touched. FAT/exFAT mounts return `-1` from the kernel arm (symlinks need inodes), matching
`readlink`#70.

## Related

- `sys_readlink`#70 — the closest precedent in this file, and the syscall that introduced the
  no-follow path lookup (`ext2_path_lookup_ex(path, len, follow_last)`) that #102 reuses. Its own
  agnos ABI note anticipated exactly this: *"the no-follow lookup it introduces is exactly what a
  future `lstat` would reuse if a consumer ever needs no-follow."*
- `sys_symlink`#63 — the creation half; also shipped one-sided and was filed the same way.
- agnos `docs/development/agnos-userland-abi.md` row 102 — the authoritative contract for the number.
