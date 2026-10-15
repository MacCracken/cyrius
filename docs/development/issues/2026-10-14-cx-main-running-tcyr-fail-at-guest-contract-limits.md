# cx: seven corpus .tcyr fail under cxvm once their `fn main` runs — stdlib wrappers that compile for cx but pass guest offsets to the host (pipe, fstat, unlink), a host-address `mmap_anon`, and tests with no cx arm — OPEN

**Status:** 🟡 **OPEN**. Found 2026-10-14 by the 6.7.11 genfe lane (unit F5), while landing
[`2026-10-11-cx-does-not-auto-call-main.md`](archived/2026-10-11-cx-does-not-auto-call-main.md) (commit 09e06b72 on
`l6711-genfe`): cx now calls the `fn main` a program defines from the entry epilogue, so files whose
assertions all live in `main` run them under cxvm for the first time. A before/after cxvm differential
over the 584-file `.tcyr` corpus: 17 files now pass in full on cxvm (15 printed nothing and exited 0,
two exited with a global's value); these seven now fail. Not fixed in that bite — each fix is a cx guest-contract design (or a test's cx arm),
not a codegen repair.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D13 — honest cx arms in the wrappers.
**Discovered:** 2026-10-14, 6.7.11 genfe F5 (the cx `main` auto-call).
**Severity:** Low. Every failure is loud — an assertion `FAIL` line and a non-zero exit, or a cxvm
trap with exit 1 — and no gate runs these files on cx (the cross-OS legs run `tests/tcyr/crossos/`
natively). Before the auto-call they "passed" on cxvm by running nothing. Two parts are worth more
than Low on their own: `mmap_anon` on cx returns a NON-ZERO pointer that is not a guest address (the
caller's null check passes; the first access traps), and `sys_unlink` on cx returns -EFAULT and leaves
the file, so `uid_identity.tcyr` run under cxvm leaves `_uid_identity_probe.bin.<pid>` in its cwd.
**Affects:** the cx target (`CYRIUS_TARGET_CX`, `programs/cxvm.cyr`), every version — the wrappers were
always like this; the auto-call only made the corpus reach them.

## The seven files (cxvm, the lane tip; x86_64 passes each in full)

| File | cxvm | Cause |
|---|---|---|
| `tests/tcyr/crossos/mmap_anon_flag.tcyr` | `cxvm: guest address out of range: <host addr> at pc 97912`, exit 1 | `mmap_anon` → raw `syscall(9, …)`: the host maps it and the guest gets a HOST address |
| `tests/tcyr/crossos/mmap_include_order.tcyr` | the same trap, exit 1 | the same |
| `tests/tcyr/crossos/uid_identity.tcyr` | `11 passed, 2 failed (13 total)`, exit 2 (`sys_fstat … (got 1, expected 0)`, `owned by sys_geteuid() (got 0, expected 1000)`); the probe file is left behind | `fstat(5)`'s buffer and `unlink(87)`'s path are guest offsets: -EFAULT |
| `tests/tcyr/crossos/sys_pipe_every_target.tcyr` | `2 passed, 4 failed (6 total)`, exit 4 (`sys_pipe returns 0 (got -14, expected 0)`) | `pipe(22)`'s fd-pair buffer is a guest offset: -EFAULT |
| `tests/tcyr/concurrency/async_relay_once_no_deadlock.tcyr` | `1 passed, 7 failed (8 total)`, exit 7 (`input pipe created (got 0, expected 1)`) | the same `pipe` |
| `tests/tcyr/concurrency/integration_closures_threads.tcyr` | `1 passed, 1 failed (2 total)`, exit 1 (`got 0, expected 110`) | by design: `thread_create` returns 0 on cx (`lib/thread.cyr`'s 6.6.11 cx arm); the test has no cx arm |
| `tests/tcyr/crossos/signal_errno_peer_values.tcyr` | `0 passed, 1 failed (1 total)`, exit 1 (`a platform arm ran (0 = this test compiled into nothing)`) | the test's arms are MACOS / LINUX / WIN / AGNOS; cx predefines only `CYRIUS_TARGET_CX`, so its anti-vacuous guard fires |

`tests/gates/codegen/cx_auto_call_main.sh` rows X1 (mmap_anon_flag) and X2 (uid_identity) pin the
first and third rows' exact failures as XFAIL naming this file; a fix turns them RED as an XPASS, to
be promoted to `N passed, 0 failed` rows.

## Reproduction (the wrapper half)

```cyr
# cx: stdlib wrappers that compile for cx and cannot work under cxvm (x86_64 is the oracle).
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
var fds[16];
var rp = sys_pipe(&fds);                       # pipe(22): the fd-pair buffer is a guest offset
var fd = sys_open("_cx_probe.bin", 577, 384);  # open(2) is translated: the file is created
var st[160];
var rs = sys_fstat(fd, &st);                   # fstat(5): the stat buffer is a guest offset
sys_close(fd);
var ru = sys_unlink("_cx_probe.bin");          # unlink(87): the path is a guest offset
var p = mmap_anon(4096);                       # mmap(9): the host maps it and returns a HOST address
var bad = 0;
if (rp != 0) { bad = bad | 1; }
if (rs != 0) { bad = bad | 2; }
if (ru != 0) { bad = bad | 4; }
if (p == 0) { bad = bad | 8; }
syscall(1, 1, "before store\n", 13);
store64(p, 7);
syscall(60, bad);
```

From the cyrius root (compilers from the tree: `cat src/main_cx.cyr | build/cycc > cycc_cx`,
`cat programs/cxvm.cyr | build/cycc > cxvm`), run in an empty directory:

```text
$ build/cycc < r.cyr > x86 && ./x86; echo $?; ls _cx_probe.bin
before store
0
ls: cannot access '_cx_probe.bin': No such file or directory

$ cycc_cx < r.cyr > r.cyx && cxvm < r.cyx; echo $?; ls _cx_probe.bin
before store
cxvm: guest address out of range: 140673329893376 at pc 50028
1
_cx_probe.bin
```

With the `store64(p, 7);` line replaced by `syscall(60, bad);` cxvm exits **7** (pipe, fstat and
unlink failed; `mmap_anon` "succeeded"), and each of `rp` / `rs` / `ru` is **-14** (EFAULT).

## Root cause

`programs/cxvm.cyr`'s op-0x70 dispatch translates the guest buffer of `read`(0) / `write`(1) /
`open`(2) (`close`, `lseek` and `exit` take none) and serves `getrandom`(318) / `clock_gettime`(228)
itself; every other number goes to the host with the guest's raw register values (the guest contract, `docs/platform-status.md` § *cyrius-x
guest contract*; `lib/syscalls.cyr`'s cx arm says the same: "a wrapper outside that set compiles on cx
and will not work"). So:

- `pipe` / `fstat` / `unlink` (and every other pointer-taking wrapper) pass a guest OFFSET as a host
  address — the host answers -EFAULT. A translation alone is not the whole fix: `struct stat`'s layout
  is the HOST's (x86_64 Linux 144 B with `st_uid` at 28, aarch64 Linux's generic 128 B at 24, Darwin's
  own), while the cx guest reads the x86_64-Linux peer's `STAT_UID`; macOS `pipe` returns the two fds
  in registers, not through the buffer; Windows routes neither.
- `mmap` (6 arguments; cxvm forwards five) succeeds on the host and returns a host address, which no
  guest load or store can reach — cxvm's 6.6.12 bounds check traps the first one. `lib/thread.cyr`'s
  cx arm already refuses exactly this hazard for its own stacks ("cxvm hands a guest mmap to the HOST
  kernel, which succeeds, and the stores below then go through a host address").
- `integration_closures_threads.tcyr` and `signal_errno_peer_values.tcyr` are corpus files with no cx
  arm: the first meets cx's documented single thread (`THREADS_CONCURRENT` = 0, `thread_create` → 0),
  the second matches no target arm on cx.

## What a fix has to decide (the user's call)

1. For each pointer-taking wrapper reachable on cx: a cxvm translation (with the per-host struct
   conversion where the layout differs), or an honest cx arm in the wrapper (-ENOSYS / 0, as
   `thread_create` does), or the guest contract stated per wrapper.
2. `mmap` / `mmap_anon` on cx: a guest-heap mapping served by cxvm (or `lib/alloc_cx.cyr`), or a cx
   arm returning failure (0 / -ENOSYS) so a caller's null check sees it.
3. The two test files: a cx arm (or a cx fence naming the contract) in each.

Acceptance: the seven files pass, or skip by name, under cxvm; X1 / X2 in `cx_auto_call_main.sh`
promoted to full-pass rows; no wrapper reachable on cx returns a non-guest pointer as success.
