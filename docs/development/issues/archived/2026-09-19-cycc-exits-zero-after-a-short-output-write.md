# cycc exits 0 after a FAILED write of its output, and `cyrius build` then prints `OK (65536 bytes)` for a truncated binary — FIXED

**Status:** ✅ **FIXED in 6.6.6 (bite 15)** — found during 6.6.6 bite 12 (while auditing gates under
a full temp dir); reconfirmed at the bite-12 tree with the repro below, and again on the bite-15
tree (b6b3bbd6) before the fix.
**Placement:** unpinned — 6.x-line backlog (the next repair batch). Compiler change → the full
self-host + seed-derive + cross-OS cycle.
**Discovered:** 2026-09-19
**Severity:** High — silent data corruption: a truncated executable reported as a successful build,
exit status 0, on any full disk (or quota, or RLIMIT_FSIZE). Every CI step that trusts `$?` ships it.
**Affects:** cycc 6.6.5 (x86_64 Linux measured); the same write loop is in 6 of the 7 driver forks
(`main.cyr`, `main_aarch64{,_macho,_native}.cyr`, `main_win.cyr`, `main_x86_macho.cyr`).

## Summary

cycc writes the finished image to stdout in a loop that stops on the first `write` that returns
`<= 0` — and then carries on to exit 0 as if every byte had landed. `cyrius build` sees exit 0,
stats the output file and reports its (truncated) size as the artifact.

## Reproduction

```sh
S=$(mktemp -d); mkdir -p "$S/m"
unshare -rm sh -c "mount -t tmpfs -o size=64k tmpfs $S/m &&
  ./build/cyrius build programs/gen_syscall_xlat.cyr $S/m/gen; echo cyrius-build-rc=\$?; ls -l $S/m/gen;
  rm -f $S/m/gen; cat programs/gen_syscall_xlat.cyr | ./build/cycc > $S/m/gen2; echo cycc-rc=\$?; ls -l $S/m/gen2"
```

Actual:

```
OK (65536 bytes)
cyrius-build-rc=0
-rwxr-xr-x 1 root root 65536 ... gen
cycc-rc=0
-rw-r--r-- 1 root root 65536 ... gen2        # the full image is 71272 bytes
```

Mount-free (RLIMIT_FSIZE with SIGXFSZ ignored gives the writer the kernel's full-disk sequence — a
short count, then EFBIG):

```sh
( trap '' XFSZ; ulimit -f 100; cat programs/gen_syscall_xlat.cyr | ./build/cycc > out ); echo rc=$?; wc -c < out
# rc=0, 51200 bytes (bash's 512-byte blocks) of a 71272-byte image
```

Expected: cycc prints `error: could not write the output (N of M bytes): <errno>` to stderr and exits
non-zero; `cyrius build` then prints its FAIL line, not `OK`.

## Root cause

`src/main.cyr` ~2236–2246 (and the same loop in the other forks):

```
while (wgo == 1) {
    var w = syscall(SYS_WRITE, 1, _output_base + written, olen - written);
    if (w <= 0) { wgo = 0; }          # stops — but records no error
    else { ... }
}
```

`written < olen` after the loop is never tested. `cbt/commands.cyr` ~150–165 trusts `compile()`'s
status and reports `_artifact_size(output)`.

## Proposed fix

After the loop, `if (written < olen)` write a diagnostic to stderr and exit 1 — in every fork (grep
`while (wgo == 1)`), in small helper fns so cybs can compile it (seed-derive is mandatory). Optionally
`cyrius build` can also compare the artifact size against a size cycc reports, but the exit status is
the load-bearing half.

## Acceptance criteria

- The 64k-tmpfs repro: cycc exits non-zero with a message naming the short write; `cyrius build`
  prints FAIL and exits non-zero; no `OK (…)` line.
- A gate pins it without a mount (RLIMIT_FSIZE + `trap '' XFSZ`), mutation-proven by removing the check.
- Self-host fixpoint, seed-derive and the cross-OS leg green.

## Corrections to this filing

1. **"the same write loop is in 6 of the 7 driver forks" understates the surface.** It is in six,
   yes — but `main_cx.cyr` (the seventh) has its OWN six writes and ignored the result of every
   one of them, and `src/backend/js/emit.cyr`'s `_ej_flush` has a THIRD copy of the loop whose
   own comment claims it is "partial-write safe" while `if (n <= 0) { return 0; }` returns
   SUCCESS. `--version` writes to fd 1 unchecked in two forks as well. Grepping
   `while (wgo == 1)`, as the "Proposed fix" says, finds six of the eleven sites. The census the
   fix used instead is `syscall(SYS_WRITE, 1,` across `src/`, and the gate now keeps it at zero
   outside the one helper.

2. **"in every fork … in small helper fns" is the right instinct but the wrong placement.** Seven
   copies of a check is the shape that produces six-with and one-without; the check lives once,
   in `src/common/util.cyr`, which every fork already includes after its own `enum Sys` (so the
   aarch64 fork's `SYS_WRITE = 64` / `SYS_EXIT = 93` resolve correctly with no per-fork code).

3. **The optional half is not needed and would have been the weaker check.** "`cyrius build` can
   compare the artifact size against a size cycc reports" — cbt compiles to a TEMP file and
   renames only on exit 0, so once cycc exits non-zero `cyrius build` already prints
   `FAILED (compiler exit 1)` and leaves **no artifact at all**, which is better than reporting a
   wrong size for one that exists. No cbt change was made.

4. **The gate does not use the filing's `unshare -rm` + tmpfs repro**, although that repro was run
   by hand before and after the fix and is recorded in the CHANGELOG. `unshare -r` fails outright
   on a host with unprivileged user namespaces disabled, which would make the gate skip silently —
   the failure mode this release keeps finding. `RLIMIT_FSIZE` with `SIGXFSZ` ignored gives the
   writer the identical kernel sequence (a short count, then `EFBIG`) with no privilege at all.

**Verification:** the filing's verbatim tmpfs repro now prints `FAILED (compiler exit 1)`,
`cyrius-build-rc=1`, no `gen`, and `cycc-rc=1` with
`error: could not write the output (65536 of 67160 bytes): errno 28`. Self-host fixpoint +
`seed-derive-cycc.sh` green; all 7 forks compile; 0 of 330 `.tcyr` binaries changed a byte.
Gate: `tests/gates/toolchain/output_write_failure_is_loud.sh` (7 axes, 4 mutations each RED).
