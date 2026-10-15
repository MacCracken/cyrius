# `dir_list` / `dir_list_into` open the directory with a plain `O_RDONLY` — a FIFO there blocks forever — RESOLVED

> ✅ **RESOLVED in v6.7.11** (LIB-2, `d534bd30`: `dir_list` / `dir_list_checked` / `dir_list_into` open with `O_RDONLY | O_DIRECTORY | O_CLOEXEC` on Linux and macOS, so the filed repro — `dir_list_into` on a `mkfifo` path — returns -1 at once instead of blocking in `open(2)`; `dir_list_checked` is -20 (`-ENOTDIR`), `dir_list` an empty vec, a dangling link -2. Measured on x86_64, qemu-aarch64, pi, ecb and ach: Darwin checks `O_DIRECTORY` before the FIFO open, and a macOS regular file now reads -20 where it read -22. agnos (`AO_DIRECTORY`) and Windows are unchanged. No decision needed (fixed to the source). Rows: `crossos/fs_dirlist.tcyr` +6 (the FIFO listers in a forked child the parent kills at 5 s), NEW `tests/gates/platform/dir_list_fifo_refused.sh` (x86 + qemu-aarch64; a built-in `O_RDONLY` mutant must block). The same class in `lib/audit_walk.cyr`'s Linux lister is filed separately (`2026-10-13-audit-walk-linux-lister-opens-without-o-directory.md`, 6.7.12). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 against 6.7.9 (agora's pin) and read unchanged at 6.7.10 (`7c97af24`).
**Placement:** 6.7.11 — repair 1, the stdlib lane — a lib/ defect, high priority by the standing rule (pulled in at the open: user, 2026-10-13) — never 7.x. Was: unplaced.
**Discovered:** agora 1.9.1 (its `docs/examples/32-store-hardening.py`, section B; agora ADR 0025's directory half).
**Severity:** Medium for a server — anyone who can create a FIFO where a program will list a directory freezes that
program (under a single-process server, every client). Low for a CLI.
**Affects:** the Linux / macOS arms of `dir_list_into` (`lib/fs.cyr:363`) and of `_dir_list_into_vec`
(`lib/fs.cyr:195`, behind `dir_list` / `dir_list_checked`). The agnos arms open with `AO_DIRECTORY` and are not
affected; nor is `is_dir`, which `stat`s.

## Summary

Both Linux arms open the path with `sys_open(&cpath, O_RDONLY, 0)` and only then call `getdents64`. If the name is a
**FIFO**, `open(2)` with `O_RDONLY` blocks until a writer opens the other end — before `getdents64` could fail with
`ENOTDIR` — so the call never returns. `O_DIRECTORY` makes the kernel refuse a non-directory at path resolution
(`ENOTDIR`), before any FIFO open semantics apply.

## Reproduction

```sh
mkfifo /tmp/notadir
# a program that does: dir_list_into(str_from("/tmp/notadir"), ...)
# → blocks in open(2) for good (strace: openat(AT_FDCWD, "/tmp/notadir", O_RDONLY) and nothing after)
```

In agora 1.9.0: replace a store's `.users/` with a FIFO, start `AGORA_SERVE=poll agora serve`, send `login x` — the
handle scan (`store_dir_scan` → `dir_list_into`) blocks the poll loop, and a second client is never greeted.

## Root cause

`O_RDONLY` alone does not say "this must be a directory". The agnos arms pass `AO_DIRECTORY`; the POSIX arms do not
pass `O_DIRECTORY` (since 6.6.4 a per-target public constant, so it is spellable on every arm).

## Fix

Open with `O_RDONLY | O_DIRECTORY` (and `O_CLOEXEC`) in both POSIX arms. A FIFO, a regular file or a dangling link
then fails at once with `-ENOTDIR` / `-ENOENT`, which both functions already return as an error. No caller can want
to `getdents64` a non-directory.

## Consumer workaround (agora 1.9.1)

`store_dir_scan` `stat`s the path first and refuses anything that is not `S_IFDIR` (`src/board.cyr`
`store_is_dir`). A swap between the `stat` and the `open` remains possible; this fix closes it.
