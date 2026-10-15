# `lib/audit_walk.cyr`'s Linux lister opens a directory with plain `O_RDONLY` — a FIFO there blocks the walk forever — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 stdlib lane's tree (`d534bd30`, after the
`dir_list` fix), x86_64 Linux.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Severity:** Low. The CLI (`cyrius audit`, `cbt/commands.cyr` ~2600) `is_dir`-checks every root before
it walks, and the walkers descend only into entries whose `d_type` is `DT_DIR`, so a FIFO is reached
only by a caller of the public walkers that hands one in, or by a swap between the CLI's `stat` and
the walker's `open`. A lib/ defect all the same: the same class as
`issues/archived/2026-10-13-dir-list-opens-directory-without-o-directory.md`, met while fixing it — the
`dir_list` issue's filed surface is `lib/fs.cyr` only, so this site was not touched.
**Affects:** `_aw_dir_list_typed` (`lib/audit_walk.cyr`, the Linux x86 / aarch64 arm, ~line 240) — behind
the public `audit_fmt_walk`, `audit_lint_walk` and `audit_doc_walk`. macOS / Windows / agnos route
through `_aw_dir_list_portable` → `dir_list_checked`, which opens with `O_DIRECTORY` since 6.7.11.

## Reproduction

```cyrius
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "lib/audit_walk.cyr"

fn main(): i64 {
    alloc_init();
    var dirs = vec_new();
    vec_push(dirs, str_from("aw_probe_target"));
    var r = audit_fmt_walk("build/cyrfmt", dirs);
    fmt_int(r); println("");
    fmt_int(AW_FMT_ERRORS); println("");
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

Built from the repo root (`cat p.cyr | ./build/cycc > p`), run in a scratch directory:

```
$ mkfifo aw_probe_target && timeout 3 ./p; echo "FIFO rc=$?"
FIFO rc=124
$ rm aw_probe_target; echo x > aw_probe_target; timeout 3 ./p; echo "file rc=$?"
0
1
file rc=0
```

A regular file is reported as an unlistable directory (`AW_FMT_ERRORS` 1); a FIFO never returns.

## Root cause

`_aw_dir_list_typed` opens `sys_open(str_data(path), O_RDONLY, 0)` and only then calls `getdents64`.
`open(2)` of a FIFO with `O_RDONLY` blocks until a writer opens the other end, before `getdents64`
could fail with `ENOTDIR`. (It also hands `str_data(path)` to the kernel, where `lib/fs.cyr`'s
listers copy exactly the Str's bytes through `_fs_cpath` since 6.6.11.)

## Fix

`O_RDONLY | O_DIRECTORY | O_CLOEXEC` at that open, as `lib/fs.cyr`'s two sites take since 6.7.11: a FIFO
or a file fails at once with `-ENOTDIR`, which the walkers already report as an unlistable directory.
A row: `tests/gates/platform/dir_list_fifo_refused.sh`'s shape (a FIFO, `timeout`, an O_RDONLY mutant
that must block) for `audit_fmt_walk`.
