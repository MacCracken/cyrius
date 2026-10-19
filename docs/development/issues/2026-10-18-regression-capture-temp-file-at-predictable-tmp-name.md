# lib/regression.cyr's capture verbs write the child's stdout to `/tmp/audit_xc_<pid>` / `/tmp/audit_xa_<pid>`, opened O_CREAT | O_TRUNC with no O_EXCL / O_NOFOLLOW: a symlink planted at that name truncates and overwrites the file it points to — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 libfix3 lane (branch l6715-libfix3) with the worktree's
`build/cycc` (x86_64 Linux).
**Placement:** 6.7.15 — repair 5 (libfix4 lane, unit L6; placed at the wave-3 integration, 2026-10-18: a security vulnerability, `CYRIUS-2026-0036`, P2 — fixed in the current minor, and a lib/ defect is always fixed) — never 7.x.
**Severity:** P2 — **`CYRIUS-2026-0036`** (judged at the 6.7.15 wave-3 integration, 2026-10-18, by the CYRIUS-2026-0034 precedent: the same class in a stdlib primitive) — attacker: another local user on the same
machine; boundary: the shared, world-writable `/tmp` (a pid-predictable fixed name, the "predictable shared /tmp
names" surface). Impact: a process running `regression_exec_capture_status`, `regression_exec_capture`,
`regression_exec_with_arg_capture[_status]` or `regression_exec_with_arg_capture_both[_status]` (the check driver runs
every .tcyr through the first) truncates and overwrites any file it can write that the planted symlink names, and
reads its "capture" back from a path the other user controls. 2026-09-03's audit fixed this shape in scripts/
(CYRIUS-2026-0007's companions) and in cbt/ (`_cbt_tmpdir()` / `_cbt_tmpfile()`, "the only `/tmp` path producers");
lib/regression.cyr was not in either sweep. The id was spent at the wave-3 integration (docs/audit/2026-10-08-security-ledger.md).
**Found:** in passing by the 6.7.15 libfix3 lane (unit L4), reading the verbs while fixing their child redirects.
**Cross-user reach — NOT measured (the lane's review, 2026-10-18):** the reproduction below plants the link as the
SAME user, so it shows the open follows a link, not that another user can make a victim follow one. The ledger
question turns on the cross-user case, and on Linux the kernel defaults stand in its way: this box (Arch, kernel
7.2.10) has `fs.protected_symlinks = 1` and `fs.protected_regular = 1`, pi (7.0.0-raspi) 1 and 2. With
`protected_symlinks` the kernel refuses to follow a symlink in a sticky world-writable directory unless the follower
or the directory's owner owns it, so the symlink case shown does not reach a victim as written. With
`protected_regular` it refuses an O_CREAT open of an existing regular file there that someone else owns, which covers
the second vector: another user pre-creates a writable regular file at `/tmp/audit_xc_<pid>`. Without that setting,
O_CREAT | O_TRUNC with no O_EXCL would open the attacker-owned file, and the attacker would control the "capture" the
parent reads back. (Both effects are the kernel's documented behaviour; neither was measured cross-user here.) macOS
has no such protection: on ecb (macOS 27.0.1) `/tmp` is `/private/tmp`, `drwxrwxrwt root`, with no `protected_*`
sysctl. Either vector, a symlink or a pre-created file, is plausible there and unmeasured. **Before integration spends
a CYRIUS id, measure one vector cross-user on ecb or ach with a second account** (CLAUDE.md: name the attacker and the
boundary). The fix is the same whatever the answer: O_EXCL | O_NOFOLLOW on a private temp (cbt's `_cbt_tmpfile`
shape, below).

## Reproduction

The program plants the link for its own pid (another user plants a range of upcoming pids):

```cyr
include "lib/regression.cyr"
var victim = "/path/to/scratch/victim.txt";
file_write_all(victim, "precious\n", 9);
var sb = str_builder_new();
str_builder_add_cstr(sb, "/tmp/audit_xc_");
str_builder_add_int(sb, sys_getpid());
var link = str_data(str_builder_build(sb));
sys_symlink(victim, link);            # what another local user plants ahead of time
var buf[64];
var n = regression_exec_capture(victim, &buf, 64, 0);   # any program: it is never the point
sys_unlink(link);
var vb[64];
syscall(60, file_read_all(victim, &vb, 64));
```

```text
exit 0        victim.txt: 9 bytes ("precious\n") before, 0 bytes after
```

## Root cause

`_regression_tmp_path(prefix)` (lib/regression.cyr, end of file) builds `"/tmp/" + prefix + getpid()`, and the
capture verbs open it with `sys_open(out_path, 577, 420)` — 577 = O_WRONLY | O_CREAT | O_TRUNC: no O_EXCL, no
O_NOFOLLOW, and `/tmp` regardless of TMPDIR. The open follows a pre-planted symlink; `/tmp`'s sticky bit stops
deletion, not planting.

## Fix direction

Create the capture file exclusively in a private place — O_CREAT | O_EXCL | O_NOFOLLOW (mode 0600) with a retry on
EEXIST, under a per-run private directory (cbt's `_cbt_tmpdir()` shape) or `$TMPDIR` — or capture through a pipe as
lib/process.cyr does. Rows: the repro's victim keeps its 9 bytes (the verb fails or uses another name); a gate axis
like `gates_never_write_tree.sh` axis 7 over lib/ for a fixed `/tmp` name.
