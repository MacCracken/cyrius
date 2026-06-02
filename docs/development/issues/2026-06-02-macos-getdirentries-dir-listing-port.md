# 2026-06-02 — macOS: directory-listing surface (`getdents64`) unported to Darwin

**Discovered:** 2026-06-02 while pinning the arm64-macOS `[deps] stdlib`
SIGSYS ([`2026-06-02-macos-arm64-deps-stdlib-pin-check.md`](./2026-06-02-macos-arm64-deps-stdlib-pin-check.md)).
**Severity:** Medium — **no consumer currently blocked**. Affects only
`cyrius update` and named/git-dep lock writing on macOS, not `[deps]
stdlib` resolution (which copies by name).
**Affects:** cycc/cyrius arm64 Mach-O (ecb) and — by inspection — x86_64
Mach-O. The directory-enumeration surface has never run on Darwin.

## Summary

`lib/fs.cyr`'s `is_dir` and `dir_list` are implemented with **`getdents64`**
— Linux syscall **217** (x86) / **61** (aarch64). The arm64-macho
`ESYSXLAT` (src/backend/aarch64/emit.cyr) does not translate it, and
**Darwin has no `getdents64`** anyway — it uses `getdirentries` (196) /
`getdirentries64` (344) with a **different `dirent` on-disk layout**.

On Darwin today the untranslated `getdents64` falls through to a stale
`x16` and returns negative, so `is_dir`/`dir_list` **return empty/false
rather than crashing** — degraded, not fatal. The one prior real symptom
(`[deps]` install-probe false-negative via `is_dir`) was fixed in v6.0.40
by switching that probe to `file_exists` (open-based). No remaining caller
on the `[deps]` path uses dir enumeration.

## Where it bites (and where it doesn't)

- **Does NOT affect `[deps] stdlib` resolution** — modules are copied by
  name (`_dep_copy_file` + `_dep_stdlib_seen`), no `dir_list`. Verified:
  the dep lock is not written for stdlib-only manifests on *any* platform,
  so the absent lock on macOS is normal, not this bug.
- **DOES affect (on macOS):**
  - `cyrius update` walk (`_update_walk`, cbt/deps.cyr ~L1078) — `dir_list`.
  - named/git-dep lock writing (`cmd_deps_lock` → `_deps_lock_dir`,
    cbt/deps.cyr ~L1310) — `dir_list` over `lib/`.
  - `_process_named_deps` `is_dir` checks for path/git deps (~L579/617).
  - any tool dir-walking (lint/doc over a tree, etc.).

## Fix sketch

1. **arm64 macho `ESYSXLAT`** (src/backend/aarch64/emit.cyr): translate the
   dir-enum syscall to Darwin `getdirentries` (196) or `getdirentries64`
   (344). Note arg/ABI shape: `getdirentries(int fd, char *buf, int nbytes,
   long *basep)` — there's a 4th `basep` out-param the Linux call lacks.
2. **`lib/fs.cyr`** `dir_list` (and `is_dir`): parse the **Darwin `dirent`**
   layout, which differs from the Linux one the current code assumes
   (Linux: reclen@16, dtype@18, name@19). Darwin `struct dirent`:
   `d_ino` (u64) @0, `d_seekoff` (u64) @8, `d_reclen` (u16) @16,
   `d_namlen` (u16) @18, `d_type` (u8) @20, `d_name` @21 — *verify on
   hardware*, do not trust this from memory.
3. Likely needs a `#ifdef CYRIUS_TARGET_MACOS` branch in `dir_list`/`is_dir`
   for the layout, the way `_file_size` / `_abs_path` were done in the
   `[deps]` fix.

## ABI caution (from the [deps] dig)

A raw `getdirentries` probe (syscalls 344 and 196) returned **EFAULT (14)**
from a minimal standalone macho test on ecb; a heap-buffer variant SIGSEGV'd.
The ABI did not crack quickly in the finicky standalone test env. The
**reliable method** (proven on the `stat` struct in the `[deps]` fix) is to
instrument the real wrapper, dump the returned buffer/`basep` bytes on ecb,
and read the layout empirically rather than trusting headers — the raw
Darwin syscalls fill legacy (non-`*64`/non-INODE64) structs whose offsets
differ from the SDK's userspace structs (e.g. raw `stat` st_size was at
byte 72, not the SDK's 96).

## Verification

Port, then on ecb (arm64) and ach (x86_64): a program that `dir_list`s a
known directory must enumerate it correctly; `cyrius update` must walk;
named-dep lock must write. Add a dir-listing case to the macOS real-install
gate so this can't rot silently again.
