# agnos 1.57.6: `spawn_path`#43 flags and error codes, `exec_redirect`#62 ops, `CH_ENDOW` disarm — constants + wrappers for the agnos peer; and `uptime_us`#95's −1 is now permanent — RESOLVED v6.6.7

**Status:** ✅ **RESOLVED v6.6.7** (bite 4) — `AgnosSpawnFlag` / `AgnosSpawnErr` / `AgnosRedirOp`, `sys_spawn_argv`, `sys_exec_redirect_add` / `_clear`, `sys_chan_endow_stdio` / `sys_chan_endow_disarm`, the len / src / fd<0 misroute guards, and the #95 "-1 is permanent" note landed in `lib/syscalls_x86_64_agnos.cyr`; run on agnos 1.57.10 in QEMU. The `lib/bench.cyr` -1 check and the sakshi `src/clock.cyr:152` sentence were NOT part of this bite (clock lane / sakshi upstream). See `CHANGELOG.md` [6.6.7]. It stays in the open dir for the slot-close archive pass.
**Original status:** 🟡 OPEN: the agnos kernel ships these in 1.57.6; `lib/syscalls_x86_64_agnos.cyr` has no
names for them yet. No new syscall NUMBER is involved (every item rides an existing number), so agnos's
`syscall ABI (kernel/doc/cyrius agree)` gate stays green (`kernel 105 · abi-doc 105 · cyrius 105`) —
this is a surface ask, not a gate blocker.
**Placement:** **6.6.7 bite 4** — agnos 1.57.6–1.57.9 peer surface; the a4=r10 class (cycc zeroes r10 on short agnos syscalls); monotonic socket-recv deadline; loopback listen class (CVE-47). Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Filed:** 2026-09-24, by agnos. agnos minted the ABI; cyrius owns the peer.
**Severity:** Medium: nothing breaks, but the features daimon asked agnos for (argv with spaces, a
reason for a failed spawn, stdout + stderr capture, a clean child fd table) are reachable today only by
hand-packing flag bits and op codes into raw arguments.
**Affects:** cycc 6.6.6 (the pin agnos builds with). Every earlier release too, but the kernel side
exists only from agnos 1.57.6.

## Summary

agnos 1.57.6 closes three daimon filings against `spawn_path`#43 (argv cannot contain a space; every
failure is −1; a child inherits every fd and a failed spawn leaves `CH_ENDOW` armed). The kernel side is
ABI §4.8 of agnos `docs/development/agnos-userland-abi.md` (normative), plus the `#62` and `#97` rows.
Everything is encoded in arguments of existing numbers, so an old peer keeps working unchanged — but it
cannot name any of it.

## The ask — constants

Not `SYS_`-prefixed (they are argument values, not syscall numbers):

```
# spawn_path#43 a2 = len | flags  (bits 0-15 length; bits >= 18 must be 0, else -SPAWN_E_ARGS)
SPAWN_F_ARGV    = 0x10000   # a1 = "argv0\0argv1\0...\0", 2..1024 B, 1..16 entries; argv[0] is the path
SPAWN_F_CLEANFD = 0x20000   # child gets fds 0/1/2 (after redirects) + armed #62 srcs + the endowment only

# spawn_path#43 returns pid >= 0, or the NEGATED code (the CH_E_* convention)
SPAWN_E_OTHER  = 1          # reserved; no 1.57.6 path produces -1 from #43
SPAWN_E_NOPROC = 2          # 16-slot process table full (agnos's WOULD_BLOCK value — back off, retry)
SPAWN_E_NOMEM  = 3          # page tables / 2 MB pages exhausted, or a CLEANFD child got no private fd table
SPAWN_E_NOENT  = 4          # missing, not a regular file, short read, or no ext2 root
SPAWN_E_NOEXEC = 5          # not an ELF64 agnos loads (size, magic/class, entry, phdrs, PT_LOAD bounds, W^X)
SPAWN_E_ARGS   = 6          # bad a2, path range not owned, empty path, bad argv blob, > 16 tokens/entries,
                            # or (flagged forms only) a bad env blob

# exec_redirect#62 a1 = src_fd | op
REDIR_ADD   = 0x100         # a1 = REDIR_ADD | src (src in bits 0-7): add/re-point a pair, up to 4
REDIR_CLEAR = 0x200         # exactly 0x200 (0x201 etc. -> -1): drop every armed pair
```

`execwait`#37 folds every spawn code to −1; only `#43` returns the negated codes.

## The ask — wrappers

```
# #43, argv form: NUL-separated entries, total len <= 1024, <= 16 entries. `flags` may add
# SPAWN_F_CLEANFD. env = 0 -> the default env; a non-zero env that fails the blob gate -> -6.
fn sys_spawn_argv(blob, len, env, envlen, flags): i64 {
    return syscall(SYS_SPAWN_PATH, blob, len | SPAWN_F_ARGV | flags, env, envlen);
}

# #62: add (or re-point) one redirect pair for the caller's next #43/#37 child: the child's
# writes to its fd `src` go to the caller's fd `dst`. Up to 4 pairs.
fn sys_exec_redirect_add(src, dst): i64 {
    return syscall(SYS_EXEC_REDIRECT, REDIR_ADD | src, dst);
}

# #62: drop every armed pair (use on an error path between arming and spawning).
fn sys_exec_redirect_clear(): i64 {
    return syscall(SYS_EXEC_REDIRECT, REDIR_CLEAR, 0);
}

# #97 CH_ENDOW with fd -1: disarm the pending endowment and its PTY flag (error-path counterpart
# of sys_chan_endow). Returns 0; agnos <= 1.57.5 answered -CH_E_BADFD.
fn sys_chan_endow_disarm(): i64 {
    return syscall(SYS_CHAN_OP, CH_ENDOW, 0 - 1);
}
```

`sys_exec_redirect(src, dst)` (op 0, "replace everything with this one pair") keeps its meaning.

## Semantics a wrapper author needs (all normative in ABI §4.8)

- **Arms are per-PROCESS from 1.57.6** (they were per-CPU): the `#62` pairs and the `CH_ENDOW`
  endowment are consumed only by the arming process's next child. **Every `#43` and `#37` return clears
  the caller's whole arm state, success or refusal.** `spawn`#3 consumes the endowment only (and clears it
  on every return); it never consumes `#62` pairs. `CH_CLOSE` of the armed endpoint disarms it. `fork`#96
  children and recycled slots start with none.
- **The line form is unchanged except for one refusal**: more than 16 space-separated tokens is now
  **−6** from `#43` (and −1 from `#37`) — through agnos 1.57.5 the 17th+ token was silently dropped.
- **The unflagged line form keeps its default-env fallback** for a bad env blob (2-arg callers leave
  garbage in a3/a4). Only the flagged forms report a bad blob, as −6. The `⛔ THE KERNEL TREATS A GARBAGE
  a3/a4 AS FALLBACK-TO-DEFAULT-ENV` comment above `sys_spawn_path_env` stays true for that wrapper.
- The `SysNrAgnos` comments `spawn_path(path, len) → pid/-1` and `exec_redirect(src_fd, dst_fd) → 0/-1`
  are now incomplete: #43 returns `pid / -SPAWN_E_*`, and #62 takes an op in a1 bits 8+.
- Recipes (capture stdout + stderr with a clean child, `2>&1`, hand the child one specific fd, the
  error-path disarm pair) are in ABI §4.8.

## Consumers this unblocks

- `lib/process_agnos.cyr`: its header says args are not passable and capture is unsupported on agnos —
  `run`/`exec_vec` can pass a real argv through `sys_spawn_argv`, and `run_capture` becomes implementable
  (`pipe` + `sys_exec_redirect` / `sys_exec_redirect_add` + `SPAWN_F_CLEANFD`).
- daimon (the filer): argv with spaces, precise start-failure reasons, `--agent-output capture` without
  handing every agent every other agent's pipe.

## And one note on `uptime_us`#95 (no new surface)

From agnos 1.57.6 the TSC is calibrated against the ACPI PM timer (a throttled host no longer refuses it
on q35 / i440fx), with one retry before userland; **after that, −1 from `#95` is PERMANENT for the boot**
(ABI row 95). So a latched fallback and a per-call fallback are equally correct. Two cyrius sites:

- `lib/bench.cyr:197` (`return sys_uptime_us() * 1000;`, agnos branch of the bench clock) does not check
  −1 — the same class as `lib/chrono.cyr:73-76`, already filed as
  `2026-09-23-daimon-agnos-clock-stands-still-when-tsc-calibration-refused.md`, which this does not
  replace.
- `lib/sakshi.cyr` (~:221) says `#95` is "calibrated at boot against the live tick"; the reference is now
  the ACPI PM timer, with the live tick as the fallback when no PM timer exists.

## Still to come (a separate filing when they ship)

agnos has specced, not shipped: `#106 sock_peer`, `#107 spawn_limits` and a blocking `waitpid`#4 form
(`arg1 = 0x100 | pid`, `0x1FF` = any). No constant should be minted for them before the kernel arm exists;
agnos will file one combined peer issue when they land (its ABI gate goes red on the new numbers until
then — the 1.56.55 precedent).

## Precedent

Same kernel-mints-it / cyrius-owns-the-peer split as
[`archived/2026-08-06-chan-endow-peer-and-spawn-path-env-arity.md`](archived/2026-08-06-chan-endow-peer-and-spawn-path-env-arity.md)
and [`archived/2026-09-01-agnos-sys-statfs-103-peer.md`](archived/2026-09-01-agnos-sys-statfs-103-peer.md).
