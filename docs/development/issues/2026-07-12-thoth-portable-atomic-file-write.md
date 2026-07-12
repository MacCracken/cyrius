# Portable atomic file write (`file_rename` / `file_write_atomic`) + AGNOS `O_EXCL` — needed for thoth's model file-write tools

**Discovered:** 2026-07-12 during thoth 0.31.0–0.31.3 (the model `edit` / `create_file` tools — a jailed, gated, agentic file editor)
**Severity:** Medium (correctness: a model-driven write can corrupt a user's source on a short/failed write; there is no portable crash-safe write in `lib/io.cyr`)
**Affects:** cycc / `lib/io.cyr` at 6.4.55 (and back — `lib/io.cyr` has never had a portable rename)

## Summary

thoth's `edit(path, old, new)` and `create_file(path, content)` tools rewrite project files on the user's behalf. The only portable "write these bytes to this path" primitive is `file_write_all` (`lib/io.cyr:231`), which opens `O_WRONLY | O_CREAT | O_TRUNC` and does a **single** non-looping `file_write`. That is **not crash-safe**: `O_TRUNC` empties the file at `open`, so a short write (ENOSPC / EDQUOT / EINTR-after-partial) or a crash between open and the write leaves the user's file **truncated / half-written**, with the original gone. `edit` only ever *overwrites existing source*, so the blast radius is real.

The standard fix — write to a sibling temp file, `fsync`, then `rename()` over the target (atomic replace on the same filesystem) — is **not expressible portably today**, because:

1. **There is no portable rename in `lib/io.cyr`.** `xunlink` (`lib/io.cyr:108`) bridges `sys_unlink` across targets, but there is no `file_rename` / `xrename` sibling. Calling `sys_rename` directly is non-portable: it is **2-arg** on POSIX (`sys_rename(oldpath, newpath)` — `syscalls_x86_64_linux.cyr:391`, `syscalls_aarch64_linux.cyr:496`, `syscalls_macos.cyr:350`) but **4-arg** on AGNOS (`sys_rename(old, oldlen, new, newlen)` — `syscalls_x86_64_agnos.cyr:475`, since AGNOS syscalls take name+namelen). A consumer that writes `sys_rename(old, new)` compiles but mis-passes args on AGNOS. This is exactly the ABI-bridging that `file_open` already does for `sys_open` (`lib/io.cyr:68-88`) — rename just never got the same treatment.

2. **AGNOS `O_EXCL` is a silent no-op.** thoth's `create_file` is create-only (must refuse an existing path so it can't clobber). `file_exists` alone is insufficient — it's an `O_RDONLY` readability probe, so a writable-but-unreadable file (mode `0200`) reads as absent. The correct guard is `O_CREAT | O_EXCL`, and it works on Linux/macOS/Windows — but `file_open` deliberately does **not** map `O_EXCL` to an AGNOS `AO_*` bit ("agnos has no exclusive-create AO_* bit … the exclusive semantic degrades to a plain create", `lib/io.cyr:47-52`). So on AGNOS a create-exclusive is not enforceable at the kernel, and a write-only existing file could be clobbered.

## Reproduction

Consumer code (thoth `src/edit.cyr`), reduced:

```cyrius
# want: atomic replace of an existing file so a short write never truncates the original
var fd = file_open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0x1A4);   # tmp = path + ".thoth-tmp"
file_write(fd, buf, len);                                       # verify == len
file_close(fd);
# ... then atomically move tmp -> path:
file_rename(tmp, path);   # <-- DOES NOT EXIST. sys_rename is 2-arg POSIX / 4-arg AGNOS; no portable bridge.
```

There is no `file_rename` to call; and hand-writing the AGNOS 4-arg / POSIX 2-arg split in consumer code would fork the very substrate `lib/io.cyr` is supposed to own.

## Root cause (if known)

`lib/io.cyr` never grew a portable `rename` wrapper (only `open`/`read`/`write`/`close`/`unlink`/`stat`-family are bridged). The AGNOS `sys_rename` signature diverged (name+namelen, like all AGNOS name syscalls) with no `file_open`-style bridge to hide it. Separately, AGNOS's `AO_*` set has no exclusive-create bit, so `file_open` drops `O_EXCL` (documented, `lib/io.cyr:49-52`).

## Proposed fix

Requesting for the **next release**. Full surface thoth needs, smallest-first:

1. **`file_rename(oldpath, newpath): i64`** in `lib/io.cyr` — a portable same-filesystem rename that bridges the per-target `sys_rename` arity exactly as `file_open` bridges `sys_open` (compute namelens on AGNOS, pass through on POSIX). Returns 0 / negative errno. This alone unblocks a temp-file + rename atomic replace in consumers.
2. **`file_write_atomic(path, buf, len): i64`** (convenience, built on #1) — create a unique sibling temp, write all `len` bytes (loop the `write`), `fsync`, `file_rename` over `path`; on any failure unlink the temp and leave the original intact. This is the primitive thoth (and `/write`, and any config/state writer) actually wants; several consumers will re-roll it otherwise.
3. **AGNOS `AO_EXCL`** (or equivalent) so `O_CREAT | O_EXCL` is enforceable on AGNOS — for create-only file tools. If AGNOS genuinely can't do exclusive-create atomically, documenting that + a `file_create_exclusive(path, mode): i64` that returns the fd or `-EEXIST` (however AGNOS can best approximate it) would at least give consumers a single honest entry point.

#1 is the must-have; #2 is the ergonomic win; #3 closes the create-only gap on AGNOS.

## Consumer-side workaround (if any)

Shipped in thoth 0.31.0–0.31.3, documented in [ADR-0017](https://github.com/MacCracken/…/blob/main/docs/adr/0017-model-edit-tool-jailed-gated-opt-in.md):

- **Never report success on a short write:** `edit`/`create` require `file_write_all`/`file_write` to return the full byte count (`wr == len`), so a partial write is surfaced as a failure — but the file is still left truncated (can't prevent it without an atomic rename).
- **`create_file` uses `O_WRONLY | O_CREAT | O_EXCL`** for a true no-clobber check (independent of read permission), with a `file_exists` pre-check for a friendly message. This is correct on Linux/macOS/Windows; on AGNOS `O_EXCL` degrades to a plain create, so the `file_exists` pre-check is the only guard there (a documented AGNOS residual).

Both residuals close once `lib/io.cyr` has a portable atomic write (#1/#2) and AGNOS gains exclusive-create (#3).
