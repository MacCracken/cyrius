# Windows: port directory listing (getdents64) to FindFirstFileW/FindNextFileW

- **Filed**: 2026-06-09 (v6.1.17, surfaced by the PE-tarball build-blocker fix)
- **Affects**: `lib/fs.cyr` (`dir_list` / `is_dir` / `dir_walk`) on `CYRIUS_TARGET_WIN=1`; the `cyrius` wrapper (`cbt/cyrius.cyr`) which uses these for file/test/dep discovery.
- **Severity**: Medium. Windows directory enumeration is **non-functional** — it returns empty (`-38`) rather than crashing or blocking the build. The "Windows wrapper unported" pillar.
- **Pinned**: **v6.1.18** (the slot immediately after .17, per user — "don't leave it hanging if it can't be cleaned up right after").

## Background

`lib/fs.cyr`'s `dir_list`/`is_dir` enumerate a directory with
`syscall(SYS_GETDENTS64, fd, buf, 4096, basep)` — a **var-number, arity-5**
syscall. There is no Windows route for it (Windows enumerates via
`FindFirstFileW`/`FindNextFileW`, a stateful search-handle API, not a syscall).

v6.1.16's `EPE_SYSCALL_DYNAMIC` made a var-number syscall of an unroutable arity
a **hard compile error**, which made `cbt/cyrius.cyr` refuse to compile and broke
`scripts/build-windows-tarball.sh` (so neither 6.1.16 nor 6.1.17 could ship a
Windows tarball). **v6.1.17 softened that** to an honest stack-balanced
`-38`/`-ENOSYS` + a compile warning, so the build proceeds — but Windows
dir-listing now returns empty. This issue tracks the **complete** fix.

## Goal

Make `dir_list` / `is_dir` / `dir_walk` actually work on Windows.

## Technical sketch

1. **Directory open** — `sys_open(dir, O_RDONLY)` → `EOPEN_PE` currently calls
   `CreateFileW` without `FILE_FLAG_BACKUP_SEMANTICS` (0x02000000), which is
   required to obtain a *directory* handle on Windows. Either teach `EOPEN_PE`
   to set that flag when the target is a directory, or give the dir path its own
   open reroute.
2. **getdents64 emulation (arity-5 PE reroute)** — on the first
   `syscall(SYS_GETDENTS64, fd, buf, 4096, basep)` for a handle, call
   `FindFirstFileW(dir + L"\\*", &WIN32_FIND_DATAW)`; on subsequent calls,
   `FindNextFileW`. Synthesize Linux `dirent` records into `buf` matching the
   layout `dir_list` parses: `reclen`@16, `d_type`@18, `d_name`@19 (NUL-term).
   Convert `cFileName` (UTF-16) → UTF-8. Set `d_type` from
   `FILE_ATTRIBUTE_DIRECTORY`. Return bytes written; 0 at end-of-enumeration.
3. **State** — the hard part: `getdents64` is called repeatedly on the same
   `fd`, but `FindFirstFile` returns a *search HANDLE* that `FindNextFile`
   advances. Need an `fd`↔search-handle map (or stash the `HFIND` in/next to the
   open dir handle), and resume iteration across calls, including the
   buffer-full case (carry the pending `WIN32_FIND_DATAW` to the next call).
4. **`is_dir`** — simpler to implement directly via
   `GetFileAttributesW & FILE_ATTRIBUTE_DIRECTORY` than the getdents64 probe.

## Acceptance

- `dir_list`/`dir_walk` return real entries on real Windows (cass).
- A `tests/win/` program that lists a known directory and asserts its contents,
  wired into the cass leg of `scripts/cross-os-selfhost.sh` (alongside
  `nanosleep_pe.cyr` / `var_syscall_arity_pe.cyr`).
- The `cyrius` wrapper's file/test discovery works on Windows.

## Notes

- The v6.1.17 `tests/win/var_syscall_arity_pe.cyr` regression (unroutable-arity →
  `-38`, stack-balanced) should keep passing — this issue *adds* an arity-5
  route; it doesn't remove the softened fallback for genuinely-unroutable arities.
- Cross-reference: `2026-06-04-shipped-broken-functionality-found-by-consumers.md`
  item D2 ("Windows wrapper unported").
