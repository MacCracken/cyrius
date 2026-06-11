# `cyrius lib sync` ignores `[deps].stdlib` — copies the full pin snapshot into `./lib/` — OPEN

- **Filed**: 2026-06-11
- **Reporter**: thoth (downstream consumer; sovereign agentic coding TUI). Surfaced while vendoring the avatara dist bundle (roadmap M5), which added exactly one new stdlib dep (`math`).
- **Affects**: `cyrius lib sync` — `cmd_lib_sync`, `cbt/commands.cyr:419-481`. Current cycc **6.1.34**; the command has copied the full snapshot unconditionally since its introduction (v5.11.58), so this is long-standing, not a recent regression.
- **Severity**: **Low** (design gap / ergonomics — no build failure; the extra files are inert on disk). But the declared-deps contract is *silently ineffective* for the vendored-lib path, and the workaround is manual and easy to forget, so it quietly bloats committed trees.
- **Status (2026-06-11): OPEN.**
- **Discovered:** 2026-06-11 during thoth M5 (the avatara seam), adding `math` to `[deps].stdlib` and running `cyrius lib sync` to pull it.

## Summary

`cyrius lib sync` is documented as "copy snapshot `lib/*.cyr` → `./lib/` (sync to
pin)" — the shadow-lib-warning remediation that keeps a project's vendored
`./lib/` in step with the pinned toolchain. But it copies **every** `.cyr` file
from the pin snapshot, with **no reference to the project's `[deps].stdlib`
declaration**. A project that deliberately vendors only its declared stdlib
subset (the committed convention in both thoth and patra) has that curated subset
silently blown up to the full ~88-module snapshot on every sync — pulling in
dozens of modules it neither declares nor uses (`pam`, `shadow`, `dxgi`, `simd`,
`vani`, `yukti`, `sha1`, `grp`, `pwd`, …), including OS-specific modules for
targets it never builds. The declared `[deps].stdlib` list — which *is*
authoritative for compile-time include/auto-prepend resolution — has zero effect
on what `lib sync` vendors. So declaring the stdlib set does not control the
vendored set, which is surprising and defeats the point of the declaration for
any project that commits `./lib/`.

## Reproduction

thoth at pin 6.1.34, with a curated, committed `./lib/` (56 files = the 40
declared `[deps].stdlib` modules expanded to their per-OS peers):

```
$ git -C thoth ls-files lib/ | wc -l
56
# cyrius.cyml [deps].stdlib declares 40 modules

$ cyrius lib sync
synced from ~/.cyrius/versions/6.1.34/lib — copied 88 .cyr files

$ git -C thoth status --porcelain lib/ | grep '^??' | wc -l
31
# 31 undeclared modules added on top of the wanted `math`:
#   agnosys audit_walk bounds callback cffi dxgi flags ganita grp hashmap_fast
#   log mabda niyama overflow pam pwd regression sankoch security sha1 shadow
#   simd sync sync_macos sync_windows sys test trait vani ws_server yukti
```

Cross-repo confirmation: **patra** declares **9** stdlib modules in
`[deps].stdlib` yet carries **83** files in `lib/` — the same full-snapshot
bloat, independent of the declared list.

Secondary cosmetic bug in the same function: `--dry-run` always prints
`dry-run: would sync 0 .cyr files`. `copied` is only incremented inside the
non-dry-run branch (`cbt/commands.cyr:466`, in the `else`), so the summary count
is always 0 under `--dry-run` even though the per-file `would sync: <path>` lines
are emitted correctly.

## Root cause

`cmd_lib_sync` — `cbt/commands.cyr:419-481`. It resolves the source as
`<home>/versions/<pin>/lib`, `dir_list`s it, and copies every `*.cyr` entry to
`./lib/<name>`:

```cyrius
var entries = dir_list(str_from(src_dir));
...
while (li < vec_len(entries)) {
    ...                                  # is_cyr check on the filename suffix
    if (is_cyr == 1) {
        var src_path = make_path(src_dir, name);
        var dst_path = make_path("lib", name);
        ...
        _dep_copy_file(src_path, dst_path);   # unconditional — no manifest check
        copied = copied + 1;
    }
    li = li + 1;
}
```

There is no read of `[deps].stdlib`. Contrast `cmd_deps`, which *does* parse the
manifest's `[deps.*]` blocks — `lib sync` simply has no manifest awareness. A
naive "copy only the names in `[deps].stdlib`" filter would be wrong, though,
because it would drop the per-OS / variant peers the build selects at target
time — which is almost certainly why the command copies wholesale instead.

## Proposed fix

1. **Scope the sync to the declared surface**, expanded to its **per-OS / variant
   peer closure**. Declaring `alloc` must pull `alloc_agnos` / `alloc_macos` /
   `alloc_windows`; `syscalls` → `syscalls_x86_64_agnos` /
   `syscalls_x86_64_linux` / `syscalls_aarch64_linux` / `syscalls_linux_common`
   / `syscalls_macos` / `syscalls_windows`; `args` → `args_agnos` / `args_macos`
   / `args_win`; `process` → `process_agnos` / `process_win`; `tls` →
   `tls_native`; `fs` → `fs_win`; `thread` → `thread_win`. The peer map is the
   non-trivial part; the compiler already knows these peer relationships for
   per-OS dispatch, so the mapping exists somewhere reusable. (thoth's committed
   56-file `lib/` = the declared 40 expanded to peers — exactly the target set a
   scoped sync should produce.)
2. **Preserve full-mirror as an explicit opt-in.** The documented shadow-lib
   remediation (make `./lib/` exactly equal the pin) is still useful, so keep it
   behind `cyrius lib sync --full`; make the **default** honor `[deps].stdlib`.
   (Or invert — default full, `--declared` to scope — but the consumer
   expectation is that *declaring* the stdlib set should govern what gets
   vendored.)
3. **Fix the `--dry-run` counter**: increment `copied` outside the
   dry-run/real branch (or in both) so the summary reflects the listed files.

## Consumer-side workaround

After `cyrius lib sync`, manually prune `./lib/` back to the declared+peer set.
thoth (M5, 0.4.0) ran the sync purely to pick up one new module (`math`), then
removed the 31 undeclared additions, keeping only `lib/math.cyr` — restoring the
committed 56→57-file convention. It works, but it's manual, easy to forget, and
silently bloats the committed tree (and misrepresents the project's real
dependency surface to anyone reading `lib/`) if skipped.
