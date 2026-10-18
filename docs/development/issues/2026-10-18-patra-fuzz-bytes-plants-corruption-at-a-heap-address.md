# patra `fuzz/fuzz_bytes.fcyr` plants its chain corruption at a heap address used as a page number — it has tested nothing since patra 1.12.8, and on Windows hardware it writes a ~50 GB non-sparse file — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 platform lane (unit P6, the patra 1.16.5 fold patch
for issues/2026-10-17-patra-other-suites-open-tmp-paths-on-windows.md), on patra's working tree with that patch (the
harness's `/tmp` path now relative on Windows, so it gets past its first open there for the first time), built by the
6.7.15 platform lane tree (`CYRIUS_TARGET_WIN=1 build/cycc_win_cross`, `build/cycc`).
**Placement:** 6.7.15 — repair 5 (libfix lane, wave 2, unit L2 — a fix in patra folded into the untagged patra 1.16.5; placed at the wave-1 integration, 2026-10-18: a fold defect is always fixed) — never 7.x. A fold defect: the fix
is a patra patch (fix the source repo, then re-vendor).
**Severity:** Medium — a folded stdlib's fuzz harness: since patra 1.12.8 (2026-07-03) none of its five mutations
reaches the BYTES chain it means to corrupt on any target, so the read path's handling of a bad `BY_TYPE`, an
oversized / negative `BY_LEN` and a cyclic / out-of-file `BY_NEXT` is untested while CI reads it green. On Windows
hardware a run fills ~50 GB of disk and blocks for ~17 minutes in one uninterruptible write. Not a security issue (the
developer's own harness on the developer's own machine).
**Found:** in passing, running every patra harness on cass for the 1.16.5 patch (not part of that issue's filed rows).

## Reproduction

patra's `fuzz/fuzz_bytes.fcyr` as patched for 1.16.5 (only its `include "tests/scratch_path.cyr"` and `_scr(...)` path
differ from 1.16.4's), built for Windows from a scratch copy of patra whose `lib/` is the cyrius lane tree's:

```
cat fuzz/fuzz_bytes.fcyr | CYRIUS_TARGET_WIN=1 build/cycc_win_cross > fuzz_bytes.exe
```

run on cass from `C:\cyrius-tests\p6plat_6715\run_new` (started 09:51:18):

```
PS> Get-Process -Id 9172      # 9 minutes in
  Id ProcessName      CPU   (threads=1, ThreadState Wait, WaitReason Executive; user 0.06 s, privileged 43.9 s)
9172 fuzz_bytes  33.828125
PS> Get-Item run_new\patra_fuzz_bytes.patra
len=45365616640 write=10/18/2026 10:00:41
PS> (Get-PSDrive C).Free      # 191,048,237,056 before the run
140380815360
> taskkill /PID 9172 /F
SUCCESS: The process with PID 9172 has been terminated.      # it was not: alive, CPU still rising
PS> Stop-Process -Id 9172 -Force; ...                          # "still alive"
> fsutil file queryValidData run_new\patra_fuzz_bytes.patra    # 10:08:38, then the process exited
Valid Data Length is 0xbc0012000 (50465939456)
> del run_new\patra_fuzz_bytes.patra                           # free back to 191,034,081,280
```

Under wine (Linux host, sparse files) the same .exe exits 0 in seconds; on ecb / ach (APFS, sparse) and x86_64 Linux /
qemu-aarch64 it exits 0. The Linux trace shows where the "corruption" goes (`qemu-x86_64 -strace` on the x86_64 build,
first section):

```
lseek(3,575783634888364032,SEEK_SET) = 575783634888364032
read(3,0x7fd982a5a550,4096) = 0
lseek(3,575783634888364032,SEEK_SET) = 575783634888364032
write(3,0x7fd982a5a550,4096) = 4096
```

— a page at offset 575,783,634,888,364,032 (= `page_offset(n)`, `n + 1` = 0x7FD982A5A550, a heap address), written
into a sparse `/tmp` file; every section does the same, then `_try_read` reads the real, uncorrupted chain.

## Root cause

`_seed_one_blob` takes the chain's first page from a QUERY RESULT:
`first_pg = load64(data + _rs_field_off(rs, 1) + BR_PAGE)`. Since patra 1.12.8 (`309baca`, "fix for cy-yeo"),
`_rs_materialize` (patra src/lib.cyr:2640-2651) snapshots every TEXT / BYTES payload into a heap buffer while the
query's flock is held, and says so: "After this pass a chain field's BR_PAGE holds a HEAP POINTER (not a page
number)". So `_g_fp` is that pointer (freed by `patra_result_free`, and on Linux handed straight back as `buf`), and
each section's `page_read(fd, _g_fp, buf)` / `page_write(fd, _g_fp, buf)` seek to `page_offset(<address>)`:
`page_offset` bounds a page number only at 2^50, which a user-space address passes. `page_read`'s short read is
ignored by the harness, the mutation is written far past the end of the file, and the chain is never touched. NTFS
files are not sparse by default, so on Windows the write past EOF zero-fills the whole gap (VDL) first — tens of GB,
in one kernel wait that `TerminateProcess` cannot interrupt.

Before 1.16.5 this never showed on Windows: the harness's `/tmp/patra_fuzz_bytes.patra` did not exist on cass, and
1.16.4's build crashed at once (exit 0xC0000005, measured the same day).

## Fix direction

Take the first chain page from the ROW, not the result set (the on-disk bytes-ref, src/row.cyr:69-80 — e.g. scan the
table's data page, or a test-only accessor), assert that `page_read` of it succeeds before mutating it, and assert the
mutation landed (read the page back) so a harness that misses its target fails instead of passing. A row asserting the
database file's size stays within `HDR_PGCOUNT` pages after each section would have caught it on every target. Until
then, `fuzz_bytes` must not be run on Windows hardware.
