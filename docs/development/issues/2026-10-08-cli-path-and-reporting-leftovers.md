# CLI leftovers from the 6.7.6 review — path resolution (Windows, symlinked cwd, git ceiling), error counts, `lib sync --dry-run`, `update`, the lock under wine — OPEN

**Status:** 🟡 **OPEN** — 2026-10-08 against 6.7.6 @ 2fb6ad8b, with the CLI built from `cbt/cyrius.cyr` by the tree's
`build/cycc` (byte-identical to `build/cyrius`) and a throwaway `HOME` / `CYRIUS_HOME` in a scratch dir: items 2, 4, 5,
6 and 7 reproduced on Linux; item 8 reproduced under wine (private `WINEPREFIX`) with the PE CLI cross-built from
`src/main_win.cyr`; item 1 verified from that PE build's own warning and the code — not re-verified on hardware (needs
cass); item 3 verified by reading.
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.6 review (2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Medium for items 2 and 7 (a unit silently loses its `test.cyml`; another repository's HEAD is reported as
a local dep's state); Low for the rest.
**Affects:** the `cyrius` CLI through 6.7.6.

## Summary and reproduction

1. **Windows: `_abs_path` is the identity.** `cbt/deps.cyr:151` treats only a leading `/` as absolute and gets the
   cwd from `syscall(79)` (`:170`), which the PE build does not route: cross-building `cbt/cyrius.cyr` with a
   `src/main_win.cyr` compiler prints `warning:cbt/deps.cyr:170:13: syscall 79 with 2 argument(s) is not routed on
   CYRIUS_TARGET_WIN=1; it returns -38` (and `lib/syscalls_windows.cyr:436:12` for `brk`). So on cyrius.exe an absolute
   in-project unit path is "outside the project" for `test.cyml` (`_tc_unit_dir`, `cbt/manifest.cyr:2010` — its own
   comment says so) and `CYRIUS_TEST_FILE` / `CYRIUS_TEST_DIR` are exported relative (`_tc_run_env`,
   `cbt/manifest.cyr:2354`).
2. **A symlinked working directory spelled with the logical `$PWD` does not match the physical cwd.** Project with
   `tests/sub/test.cyml` = `[test] defines = ["FOO"]` and `tests/sub/x.tcyr` that exits 0 under `#ifdef FOO`, else 1;
   `ln -s <proj> <link>`:
   ```
   cd <proj>; cyrius test <proj>/tests/sub/x.tcyr   # rc 0
   cd <link>; cyrius test tests/sub/x.tcyr          # rc 0
   cd <link>; cyrius test $PWD/tests/sub/x.tcyr     # FAIL: …/link/tests/sub/x.tcyr (exit 1)
   ```
   `_tc_unit_dir` compares the unit path with `getcwd`'s PHYSICAL path byte for byte (`cbt/manifest.cyr:2025-2032`);
   the logical spelling misses, the unit is treated as outside the project and gets no `test.cyml`.
3. **`_abs_path(".")` returns `<cwd>/.`** (`cbt/deps.cyr:175-195` joins `cwd + "/" + src` with no `.` case). Only
   `_tc_unit_dir` strips it (`cbt/manifest.cyr:2027-2028`); `_consumer_dir` (`cbt/deps.cyr:3977`) and the local-mode
   walks (`:3709`, `:3719`) carry the `/.` into every path joined to them.
4. **`_process_named_deps` reports one error per manifest walk.** A manifest with `[deps.]` and `[deps..y]`:
   ```
   error: [deps.] is not a usable dep name (…) — section refused
   error: [deps..y] is not a usable dep name (…) — section refused
   0 deps resolved, 1 errors
   ```
   The v6.5.37 clamp `if (errors > 0) { return 1; }` (`cbt/deps.cyr:3590`, correct for an exit status) is what the
   callers SUM into the printed count (`:4078`, `:4143`, `:4302`).
5. **`cyrius lib sync --dry-run` prints pointers.** `[deps] stdlib = ["string", "alloc"]` →
   `  would sync: 139769124333272` (six lines), then `dry-run: would sync 6 .cyr files …`.
   `cbt/commands.cyr:1799` `println(vec_get(pd, wi))` — an `i64` argument, so overload dispatch picks `println_int`.
6. **`cyrius update` copies the whole stdlib snapshot.** Same project, `$CYRIUS_HOME/current` = `6.7.6`:
   `updated lib/ from …/versions/6.7.6/lib (113 files)` — all 113 `.cyr` files, whatever `[deps] stdlib` declares.
   `cmd_update` (`cbt/deps.cyr:4477`) walks `versions/<current>/lib` (`_update_walk`, `:4427`); it reads
   `$CYRIUS_HOME/current` (`:4481`), not the manifest's `cyrius` pin, and never consults `[deps] stdlib`.
7. **`_dep_local_state`'s `GIT_CEILING_DIRECTORIES` is computed lexically, not from the resolved directory.**
   `_dep_wt_run` (`cbt/deps.cyr:2309-2321`) takes the parent of `_abs_path(dir)`'s spelling. A local dep reached
   through a symlink gets the LINK's parent as ceiling, and git, starting in the physical target, walks up into an
   enclosing repository. `mono/` a git repo, `mono/libs/foo` not a checkout, `proj/links/foo -> mono/libs/foo`,
   `[deps.foo] git/tag/path`, `cyrius deps --local`:
   ```
   path = "links/foo"        -> local: foo <- links/foo @07aac49, tag 1.0.0 is not in this checkout, dirty
   path = "../mono/libs/foo" -> local: foo <- ../mono/libs/foo (not a git checkout)
   ```
   One directory, two answers; the first reports `mono`'s HEAD and working-tree state as the dep's.
8. **Under wine the PE CLI cannot hash, so it writes no lock.** `wine cyrius.exe deps` on a `[deps] stdlib =
   ["string"]` project: `warning: cyrius.lock NOT written — cannot hash lib/alloc.cyr (and 15 more): the hasher could
   not read it.` (rc 0). `_sha256sum_file` (`cbt/deps.cyr:4779`) spawns System32 `certutil.exe`, which wine lacks.

## Proposed fix

1. Route the cwd query on PE (`GetCurrentDirectoryW`, or the stdlib wrapper if one exists) and treat a drive-rooted
   path as absolute in `_abs_path`; keep the drive-relative refusal `_tc_unit_dir` documents.
2. Compare canonical forms: resolve the unit's directory (or compare `stat` dev/ino of the cwd against each prefix of
   the given path) instead of a byte prefix against `getcwd`.
3. Return the cwd itself for `"."` (and strip a trailing `/.`) in `_abs_path`, then drop the special case in
   `_tc_unit_dir`.
4. Return the count from `_process_named_deps` and clamp only where it becomes an exit status.
5. `println_str` / `sys_write` the cstr (or cast) at `cbt/commands.cyr:1799`.
6. Make `update` honour `[deps] stdlib` (as `lib sync` does, with `--full` for the whole snapshot) and the manifest pin.
7. Put the ceiling at the parent of the dep directory's PHYSICAL path (resolve it — e.g. `git -C dir rev-parse
   --show-toplevel` compared with the physical dir, or chdir + getcwd in the child) so both spellings agree.
8. Hash in-process (a SHA-256 in the CLI) instead of spawning `sha256sum` / `certutil`, which also removes the external
   binary from the lock's trust path.

## Also (found 2026-10-08 while filing)

- `_git_run` (`cbt/deps.cyr:5205-5217`) computes its clone-cache `GIT_CEILING_DIRECTORIES` lexically, as
  `_dep_wt_run` does. No failure measured: it bites only if the `<tag>` cache dir is itself a symlink.
