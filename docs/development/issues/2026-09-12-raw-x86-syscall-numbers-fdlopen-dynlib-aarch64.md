# fdlopen / dynlib pass raw x86 syscall numbers that aarch64 Linux runs as `setxattr` / `lsetxattr` / `getgroups` — OPEN

**Status:** 🟡 **OPEN** — filed for later repair at the close of the 6.6.2 ecosystem sweep; no fix attempted.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-09-12 while closing the 6.6.2 ecosystem sweep (migration-doc outlier #4), traced under `qemu-aarch64 -strace`.
**Severity:** Medium — a stdlib facility hard-fails on a supported target, and the workaround is to not use it there. Not Critical: every wrong call observed fails closed. Not Low: two of the three wrong calls are **write-class extended-attribute syscalls** aimed at caller data (`setxattr`, `lsetxattr`).
**Affects:** cycc on aarch64 Linux — every release that carries these sites; verified at **6.6.3**.

## Summary

`lib/fdlopen.cyr` and `lib/dynlib.cyr` call `syscall(N, …)` with **raw x86_64 syscall numbers** in
arch-neutral code. aarch64 Linux reaches the kernel through ESYSXLAT, which renumbers x86 numbers
into aarch64 ones — but it has **no Linux-aarch64 entry for 5, 6 or 158**, so those numbers reach the
kernel unchanged and mean something else there:

| site | intended (x86_64) | what aarch64 Linux actually executes |
|---|---|---|
| `lib/fdlopen.cyr:468` `_fdlopen_mmap_elf` | `fstat` (5) | **`setxattr`** |
| `lib/dynlib.cyr:657` `dynlib_open` | `fstat` (5) | **`setxattr`** |
| `lib/fdlopen.cyr:899` `_fdlopen_verify_trusted` | `lstat` (6) | **`lsetxattr`** |
| `lib/dynlib.cyr:899` TLS setup | `arch_prctl(ARCH_SET_FS)` (158) | **`getgroups`** |

Each wrong call returns an error (`EFAULT` / `ERANGE`), so the enclosing function takes its error path:
the ELF load fails, the trust check reports "not trusted", and TLS setup returns 0. Nothing is corrupted,
but the facility is dead on aarch64 Linux, and it is dead by accident rather than by decision.

The same x86-literal class also hits **open flags**, where there is no translation at all — see
*Same class: open flags* below; it reaches patra's WAL path.

Both files are x86_64-Linux facilities in practice. fdlopen's five `CYRIUS_ARCH_AARCH64` branches cover only
the `dl_setjmp` / `dl_longjmp` asm, not the loader; dynlib has none, and its TLS setup (`ARCH_SET_FS`) is
x86-only by design. `_fdlopen_verify_trusted` already **declines deliberately on macOS**. Its own comment
argues that "a security predicate silently misreading mode/uid is strictly worse than one that fails" — but
there is no equivalent decline on aarch64 Linux.

## Reproduction

The authority is what the kernel receives, not the source. One probe, every distinct raw number that appears
unconditionally in an arch-neutral `lib/` file, harmless arguments, `exit` last:

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 {
    var b[256];
    var r = 0;
    r = syscall(0, 0 - 1, &b, 0);
    r = syscall(1, 0 - 1, &b, 0);
    r = syscall(2, "/nonexistent-cyrius-probe", 0, 0);
    r = syscall(3, 0 - 1);
    r = syscall(4, "/nonexistent-cyrius-probe", &b);
    r = syscall(5, 0 - 1, &b);
    r = syscall(6, "/nonexistent-cyrius-probe", &b);
    r = syscall(7, 0, 0, 0);
    r = syscall(9, 0, 4096, 3, 34, 0 - 1, 0);
    r = syscall(10, 0, 0, 0);
    r = syscall(54, 0 - 1, 6, 1, &b, 4);
    r = syscall(228, 1, &b);
    r = syscall(158, 0x1002, 0);
    syscall(60, 0);
    return 0;
}
var e = main();
```

```sh
cat src/main_aarch64.cyr | ./build/cycc > /tmp/cc_a64 && chmod +x /tmp/cc_a64   # x86-hosted, emits aarch64
/tmp/cc_a64 < probe.cyr > probe && chmod +x probe
qemu-aarch64 -strace ./probe 2>&1 | grep -vE 'brk|rt_sig|prlimit|set_tid'
```

Observed at 6.6.3:

| x86 number | intended | aarch64 kernel received | |
|---|---|---|---|
| 0 | read | read | ok |
| 1 | write | write | ok |
| 2 | open | openat | ok |
| 3 | close | close | ok |
| 4 | stat | newfstatat | ok |
| **5** | **fstat** | **setxattr** | **wrong** |
| **6** | **lstat** | **lsetxattr** | **wrong** |
| 7 | poll | ppoll | ok |
| 9 | mmap | mmap | ok |
| 10 | mprotect | mprotect | ok |
| 54 | setsockopt | setsockopt | ok |
| 228 | clock_gettime | clock_gettime | ok |
| **158** | **arch_prctl** | **getgroups** | **wrong** |
| 60 | exit | exit | ok |

## Root cause

- **5 and 6:** there is no ESYSXLAT Linux-aarch64 entry. Number 4 (`stat`) *is* reshaped into
  `newfstatat(AT_FDCWD, path, st, 0)`; 5 and 6 need the same treatment (`fstat` → 80;
  `lstat` → `newfstatat(AT_FDCWD, path, st, AT_SYMLINK_NOFOLLOW)`). *Speculation on the exact
  reshaping — the Cyrius agent verifies.*
- **158:** not a numbering gap. `ARCH_SET_FS` has no aarch64 syscall equivalent; aarch64 sets TLS through
  `TPIDR_EL0`. dynlib's TLS path cannot be fixed by renumbering.

## Proposed fix

Pick per site; this is a decision for the repair, not something this filing settles:

1. **Route through arch-aware calls.** `sys_fstat` already exists (`lib/syscalls_linux_common.cyr`).
   Alternatively, add ESYSXLAT entries for 5 and 6 (with the `newfstatat` reshaping) so every raw use is
   covered at once.
2. **Decline explicitly on aarch64**, the way these files already decline on agnos and macOS, with the same
   reasoning `_fdlopen_verify_trusted` records. This is the honest option for dynlib's TLS setup unless
   someone ports it to `TPIDR_EL0`.

Whichever is chosen, it needs a companion test in `tests/tcyr/crossos/` that asserts the traced behaviour on
real aarch64 hardware. A call that compiles on five targets is not a call that runs on five (see `CLAUDE.md`).

## Same class: open flags — no per-target `O_*` constants, and flag values pass through untranslated

Syscall **numbers** at least have ESYSXLAT. Open **flag values** have nothing. The stdlib defines no
per-target `O_NOFOLLOW` / `O_DIRECTORY`, so libraries hardcode the x86_64 values, and `sys_open` /
`file_open` (`lib/io.cyr:75`) hand them to aarch64 unchanged. Traced on aarch64 at 6.6.3, scratch paths only
(aarch64: `O_DIRECTORY` 0x4000, `O_NOFOLLOW` 0x8000, `O_DIRECT` 0x10000, `O_LARGEFILE` 0x20000):

| consumer site | x86_64 intent | aarch64 kernel received | consequence on aarch64 |
|---|---|---|---|
| patra `src/wal.cyr:262` `wal_start` — `file_open(wal_path, 578 + O_NOFOLLOW, 420)` | `O_RDWR\|O_CREAT\|O_TRUNC\|O_NOFOLLOW` | `O_RDWR\|O_CREAT\|O_LARGEFILE\|O_TRUNC` | **a symlink at the WAL path is followed and its target truncated** — no `O_EXCL` to catch it |
| patra `src/file.cyr:336` `_pt_sync_dir` — `file_open(dir, O_DIRECTORY, 0)` | `O_RDONLY\|O_DIRECTORY` | `O_RDONLY\|O_DIRECT` → `EINVAL` | **the directory is never fsynced on this path** (whether the caller surfaces the failure was not checked) |
| kavach `src/util.cyr:350` `file_write_secure_modal` | `…\|O_EXCL\|O_NOFOLLOW` | `…\|O_EXCL\|O_LARGEFILE` | `O_NOFOLLOW` lost; mitigated at the final component by `O_CREAT\|O_EXCL` |

Same passthrough, not separately traced: patra `src/file.cyr:297` `_pt_file_open` (`2 + O_NOFOLLOW` — no
`O_EXCL`, so it follows a symlink) and `src/wal.cyr:565` `wal_recover` (`O_NOFOLLOW`, read-only). patra's
constants are `src/file.cyr:272` `enum OpenFlag { O_NOFOLLOW = 131072; O_DIRECTORY = 65536; }`.

**The patra WAL row is the most serious item in this file.** O_NOFOLLOW was put there deliberately to stop
exactly this symlink clobber, and on aarch64 it silently does nothing. Exploiting it needs write access to
the database directory, which is why this file stays **Medium** — but reassess that at triage.

**Proposed fix (cyrius side):** define per-target `O_*` flag constants next to the per-target `SYS_*` ones
(`lib/syscalls_x86_64_linux.cyr`, `lib/syscalls_aarch64_linux.cyr`, and the macOS peers) so consumers stop
hardcoding. Then fix patra and kavach **at source** and re-vendor — patra is a folded stdlib, so patching
`lib/patra.cyr` here would evaporate on the next re-vendor.

## Consumer-side workaround

None shipped; none needed today.

- **chakshu** releases aarch64 builds and gates its libssl path on `fdlopen_helper_available()`
  (`src/nolibc.cyr:23-25`). Whether aarch64 chakshu ever reaches `_fdlopen_mmap_elf` is **unverified**.
- **shakti** calls `fdlopen_init_trusted` / `fdlopen_dlopen` (`src/identity.cyr:176-182`) but does not build
  for aarch64; on x86_64 these calls are correct.

## Not affected (verified — do not re-investigate)

- The other 11 raw numbers in the table above translate correctly.
- `lib/io.cyr:442` `syscall(32, fd, op)` is **correct**. It sits inside `#ifdef CYRIUS_ARCH_AARCH64`, 32 is
  native aarch64 `flock`, it passes through untranslated, and the trace shows `flock`. The migration doc's
  outlier #4 listed it as broken; that was wrong.
- sigil's `SYS_GETRANDOM` redefinition (also listed under outlier #4) is gone from the released sigil 3.12.17
  bundle.
- **macOS / Mach-O is untested.** BSD numbering differs (5 is `open` there), so do not assume these sites
  behave on macOS.

## Related

- The same class in a consumer, with a security edge: kavach
  `docs/development/issues/2026-09-12-raw-x86-syscall-numbers-on-aarch64.md` (raw `fchmod` becomes `capset`,
  raw `nanosleep` becomes `unlinkat`, numeric `O_NOFOLLOW` arrives as `O_LARGEFILE`).
- `docs/development/ecosystem-migration-6.6.2.md` — outlier #4.
- patra `src/file.cyr:272`, `src/wal.cyr:262` / `:565`, `src/file.cyr:297` / `:336` — the open-flags rows above
  (no patra-side issue filed).
