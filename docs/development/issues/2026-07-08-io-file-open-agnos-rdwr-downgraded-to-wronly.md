# io: `file_open` agnos flag-map collapses `O_RDWR` → `AO_WRONLY` (reads on an RDWR fd fail)

**Filed:** 2026-07-08 (surfaced porting `sit` + `patra` to agnos; validated under mirshi).
**Severity:** P1 — silent functional miscompile (no `ud2`). Every agnos consumer that opens a
file `O_RDWR` via `file_open` and then *reads* it gets a write-only fd, so the read fails. Affects
any read-modify-write file (databases, WAL, config rewrite, TOFU stores). Linux/macOS unaffected.
**Component:** `lib/io.cyr` `file_open` agnos branch, **line 80** (the `#ifdef CYRIUS_TARGET_AGNOS`
flag translation). Inherited by `xopen` (line 103) and everything built on `file_open`. A duplicate
of the same bug lives in `lib/sakshi.cyr:88` (sakshi's own `_sk_*` agnos open helper — a sakshi
source-repo fix, same root pattern).

## Problem

The agnos flag translation in `file_open` maps the POSIX access mode wrong:

```
# lib/io.cyr:80
if ((flags & 3) != 0) { ao = ao | 0x1; }       # O_WRONLY/O_RDWR -> AO_WRONLY (O_RDONLY=0)
```

Linux and agnos use the **same** low-2-bit access-mode encoding:

| mode    | Linux `O_*` | agnos `AO_*` (`lib/syscalls_x86_64_agnos.cyr:92–94`) |
|---------|-------------|------------------------------------------------------|
| RDONLY  | `0`         | `AO_RDONLY = 0x0` |
| WRONLY  | `1`         | `AO_WRONLY = 0x1` |
| RDWR    | `2`         | `AO_RDWR   = 0x2` |

But line 80 folds **both** `O_WRONLY` (1) *and* `O_RDWR` (2) to `AO_WRONLY` (`0x1`) — it never
emits `AO_RDWR` (`0x2`). So an `O_RDWR` open becomes **write-only** on agnos. Writes still work
(a create+write path is unaffected), but any subsequent `sys_read` on that fd fails — the classic
"first write succeeds, reopen-and-read fails" signature.

### How it surfaced

`sit` (agnos-dev docker image) → object store `patra` `1.12.9`. patra opens its `.patra` B-tree
`O_RDWR` via the correct bridge — `_pt_file_open` = `file_open(path, 2 + O_NOFOLLOW, 0)` — then reads
the header page (`patra_hdr_read`: `if (sys_read(fd, buf, PAGE_SIZE) != PAGE_SIZE) return ERR`).
Under mirshi on the agnos binary:

- `sit add` (**create + write**) → succeeds (write-only is fine for creating and writing).
- `sit status` / `commit` (**reopen `O_RDWR` + read header**) → `patra: cannot read header`,
  because the reopened fd is write-only and the header `sys_read` returns `-1`.

### Not patra, not mirshi

- **patra** is correct — it needs read+write and asks for `O_RDWR` through the stdlib bridge.
- **mirshi** is faithful — `src/translate.cyr:58` does `var o = ao & 3` (AO access mode → host O
  access mode 1:1). It receives `AO_WRONLY` (because `file_open` sent it) and opens host write-only,
  so the host `read` correctly returns `-1`. A real agnos kernel, receiving the same `AO_WRONLY`,
  would reject the read identically — this is **not** a mirshi-only artifact.

The defect is entirely upstream in `file_open`'s translation.

## Fix

The access-mode bits are identical across Linux and agnos, so pass them straight through instead of
forcing write-only:

```
# lib/io.cyr, replace line 80:
    ao = ao | (flags & 3);   # access mode: O_RDONLY/WRONLY/RDWR (0/1/2) == AO_RDONLY/WRONLY/RDWR
```

`O_CREAT`/`O_TRUNC`/`O_APPEND` (lines 81–83) are already mapped correctly and unchanged. Apply the
identical fix to `lib/sakshi.cyr:88` in the **sakshi source repo** (`~/Repos/sakshi`), then re-vendor
its distfile — a `lib/sakshi.cyr`-only edit is transient (materialized).

Grep the tree for the same `if ((flags & 3) != 0) { ao = ao | 0x1; }` shape before closing, in case
other agnos open helpers copied it (found: `io.cyr:80`, `sakshi.cyr:88`; `sankoch.cyr:7157`'s
`(flags & 3)` is an unrelated LZ4 filter-count, not an open flag).

## Acceptance

- On agnos: `file_open(path, O_RDWR, ...)` yields a fd that both writes and **reads** (round-trip:
  create+write, `sys_close`, reopen `O_RDWR`, `sys_read` returns the bytes written).
- `sit` on the agnos binary under mirshi: `init` / `add` / `status` / `commit` round-trip a repo
  with **no** `patra: cannot read header` (patra `1.12.9`, unchanged).
- Linux/macOS builds byte-identical (the `#ifndef CYRIUS_TARGET_AGNOS` branch is untouched; the
  agnos branch previously never emitted `AO_RDWR`, so no correct agnos path regresses).
- A stdlib regression test opening a temp file `O_RDWR` and asserting a read-after-write on agnos
  (guards against re-collapse).
