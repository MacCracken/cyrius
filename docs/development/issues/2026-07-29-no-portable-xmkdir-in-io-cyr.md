# No portable `xmkdir` in `lib/io.cyr` — `sys_mkdir`'s second argument means `mode` on Linux and `pathlen` on agnos

**Status:** 🟡 **OPEN** — filed 2026-07-29. Verified against live code: `lib/syscalls_x86_64_linux.cyr:350`
declares `fn sys_mkdir(path, mode)`, `lib/syscalls_x86_64_agnos.cyr:468` declares
`fn sys_mkdir(path, pathlen)`. Same name, incompatible second parameter, no wrapper between them —
`lib/io.cyr`'s `x*` set is `xopen, xunlink, xfsync, xstat, xgetdents, xlseek, xflock` and has no
`xmkdir`. `lib/kavach.cyr` calls the unguarded form at eight sites.
**Placement:** unpinned — 6.x-line backlog. Additive: one wrapper in `lib/io.cyr`, no signature or
ABI change to anything existing.
**Discovered:** 2026-07-29 while porting agnosai's `orchestrator/durable_state`, which needs a
recursive `mkdir -p`.
**Severity:** Medium — compiles clean on every target and is silently wrong on one of them. There is
a workaround (hand-rolled `#ifdef`), which is exactly what the `x*` set exists to stop consumers
having to do.
**Affects:** cycc 6.5.1 and every earlier version with the `x*` wrapper set. Wrong behaviour only on
`CYRIUS_TARGET_AGNOS`; harmless elsewhere.

## Summary

`lib/io.cyr` carries a set of `x*` wrappers whose entire purpose is to absorb per-target syscall
divergence so consumers can write one call. `xopen` is the model — it translates `O_*` flags to
agnos's `AO_*` bits and converts the `(path)` form to agnos's `(path, namelen)` form:

```cyrius
fn file_open(path: cstring, flags, mode): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    var namelen = 0;
    while (load8(path + namelen) != 0) { namelen = namelen + 1; }
    ...
    return sys_open(path, namelen, ao);
    #endif
    #ifndef CYRIUS_TARGET_AGNOS
    return sys_open(path, flags, mode);
    #endif
}
```

**`mkdir` has the same divergence and no wrapper.** The two declarations are:

| target | declaration | second argument means |
|---|---|---|
| Linux x86_64 (`syscalls_x86_64_linux.cyr:350`) | `fn sys_mkdir(path, mode)` | permission bits |
| Linux aarch64 (`syscalls_aarch64_linux.cyr:455`) | `fn sys_mkdir(path, mode)` | permission bits |
| macOS (`syscalls_macos.cyr:326`) | `fn sys_mkdir(path, mode)` | permission bits |
| Windows (`syscalls_windows.cyr:184`) | `fn sys_mkdir(path, mode)` | permission bits |
| **agnos (`syscalls_x86_64_agnos.cyr:468`)** | **`fn sys_mkdir(path, pathlen)`** | **path length** |

Because the name and arity match, `sys_mkdir(path, 0x1FF)` compiles without a warning on all five and
means "create with mode 0777" on four of them and "the path is 511 bytes long" on the fifth. The
failure is not a compile error, not a runtime error at the call, and not visibly a mkdir problem — it
is a wrong path length handed to the kernel.

`sys_rmdir` and `sys_unlink` have the identical split (`(path)` vs `(path, pathlen)`); `unlink` is
covered by `xunlink`, `rmdir` is not covered by anything.

## Reproduction

There is no runnable repro, because reproducing it requires an agnos target and the bug is that both
targets compile. The evidence is the five declarations above — read them side by side:

```sh
grep -n "fn sys_mkdir" lib/syscalls_*.cyr
grep -oE '^fn x[a-z_]+' lib/io.cyr        # xopen xunlink xfsync xstat xgetdents xlseek xflock
```

The second command is the whole issue: `mkdir` is absent from a list whose other members exist
specifically to paper over this class of difference.

For an existing instance in first-party code:

```sh
grep -n "sys_mkdir" lib/kavach.cyr        # eight sites, all sys_mkdir(path, 448)
```

`448` is `0700`. On agnos every one of those is a 448-byte path length. kavach's cgroup and runc paths
are Linux-only in practice, so nothing is broken today — but the calls carry no guard saying so, and
that is how the next consumer copies the pattern.

## Root cause

The `x*` set was grown as needed rather than derived from the full divergent-syscall list, so
`mkdir` (and `rmdir`) were never added. `lib/io.cyr` has 35 verbs and none of them create a
directory, which is presumably why nobody hit it: a consumer that wants `mkdir` has to reach past
`io.cyr` to `sys_mkdir` directly, and at that point the per-target difference is theirs to know about.

## Proposed fix

Add `xmkdir` to `lib/io.cyr` next to `xunlink`, in `xopen`'s shape:

```cyrius
# Create one directory. `mode` is honoured on Linux/macOS/Windows; agnos's mkdir
# takes a path LENGTH in the second slot and has no mode, so the mode is dropped
# there rather than being silently reinterpreted as a length.
fn xmkdir(path: cstring, mode): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    var namelen = 0;
    while (load8(path + namelen) != 0) { namelen = namelen + 1; }
    return sys_mkdir(path, namelen);
    #endif
    #ifndef CYRIUS_TARGET_AGNOS
    return sys_mkdir(path, mode);
    #endif
}
```

`xrmdir(path)` deserves the same treatment for the same reason, and is a one-liner.

Two things worth considering beyond the wrapper, both cheap and both preventive rather than
corrective:

1. **A recursive `xmkdir_p`.** Every consumer that persists anything needs `mkdir -p`, and the
   stdlib has no recursive form at all — `grep -iE 'mkdir|create_dir|mkpath|ensure_dir'` across
   `lib/*.cyr` returns only `sys_mkdir` and `sys_mkdirat`. agnosai now carries ~45 lines of it. It is
   the kind of thing that will be re-rolled per consumer, slightly differently each time; note that
   the obvious implementation is also the slow one (see the workaround below).
2. **Renaming the agnos declaration.** If the divergent form were `sys_mkdir_n(path, pathlen)`, a
   consumer calling `sys_mkdir(path, mode)` on agnos would get an undefined-function error instead of
   silently wrong behaviour. That is a breaking change for anything already calling it, so it is a
   judgement call — but the current arrangement is a same-name-different-meaning trap, and those are
   worth more than the churn to remove.

## Consumer-side workaround

agnosai wraps it locally in `src/orch_durable_state.cyr`:

```cyrius
fn _agnosai_mkdir_one(cpath): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    var n = 0;
    while (load8(cpath + n) != 0) { n = n + 1; }
    return sys_mkdir(cpath, n);
    #endif
    #ifndef CYRIUS_TARGET_AGNOS
    return sys_mkdir(cpath, 0x1FF);
    #endif
}
```

plus a `_agnosai_mkdir_p` on top of it. One note in case `xmkdir_p` gets built: the naive recursive
version — walk every component, `mkdir` each, accept `-EEXIST` — costs two syscalls per component
*every time*, including the overwhelmingly common case where the whole tree already exists. Measured
on a four-deep existing path it was **43 µs**, more than the fsync'd atomic file write that followed
it. Rust's `std::fs::create_dir_all` tries `mkdir` on the **full path first** and only walks parents
on `ENOENT`; adopting that ordering took the same call to **6.0 µs**, an 86% cut. Worth having in the
stdlib version from the start.
