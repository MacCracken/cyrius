# Request: stdlib system-info surface (sysinfo / uname / process-identity), cross-target

> **RESOLVED (landed, targeting v6.2.23).** Premise-check found the surface was
> **already ~90% shipped** in `lib/sys.cyr` (carved off agnosys's syscall.cyr at
> v6.1.28) — `sys_uname`+`uname_hostname/release/machine`, `sys_sysinfo`+
> `sysinfo_uptime/total_memory/free_memory/procs` with the exact per-target AGNOS
> (40-byte/64-byte) vs Linux (120-byte/390-byte) struct divergence, the Linux
> mem_unit saturating-multiply, and `is_root`. v6.2.23 closed the remaining gap:
> (1) added `SYS_UNAME=34`/`SYS_SYSINFO=35` to the agnos peer's `SysNrAgnos` enum
> and switched sys.cyr's agnos branches from the bare `34`/`35` literals to the
> named consts (the "sharp edge" this issue called out); (2) added `sys_geteuid`
> to the agnos peer (routes to getuid) so the name is uniform across targets;
> (3) added a portable `sys_gettid` to sys.cyr (agnos→getpid, Linux→SYS_GETTID,
> macOS/Windows→-ENOSYS, matching the file's existing not-wired convention).
> Downstream `sigil/src/sysinfo.cyr` can now retire onto `lib/sys.cyr`. Verified:
> agnos gate, check.sh 89/89, cross-OS pi/ecb/cass. NOTE the agnosys upstream repo
> is gone (decomposed → agnodrm), so `lib/agnosys.cyr` stays pinned at 1.4.3.

**Filed:** 2026-06-19
**Type:** stdlib value-add request (NOT a bug)
**Origin:** the agnosys → agnodrm decomposition. agnosys's `syscall.cyr` carries a
genuinely useful, per-target system-info layer that does NOT belong in a device
library. It is the one piece of agnosys's syscall surface that is real value-add
(the rest — per-arch `sys_*` numbers, `io`/`fs`/`process` ops — already duplicates
cyrius's `syscalls_*.cyr` / `io.cyr` / `fs.cyr` / `process.cyr` and is being
deleted). This requests cyrius adopt the value-add so there is **one** system-info
surface, cross-target, and the downstream copies (interim `sigil/src/sysinfo.cyr`,
any future consumer) consolidate onto it.

## Why cyrius and not a lib
The hard part here is the **per-target struct divergence** — exactly the kind of
ABI knowledge cyrius's syscall layer already owns (it ships the per-target
`syscalls_x86_64_{linux,agnos}.cyr`). agnos and Linux disagree on both structs:

| | agnos (sovereign) | Linux |
|---|---|---|
| **sysinfo** | syscall **#35**, `(buf, len=40)`, **40-byte** all-`u64`, byte counts direct (no `mem_unit`) — `0 uptime · 8 totalram · 16 freeram · 24 procs · 32 cpus` (agnos-userland-abi.md §4.4) | `SYS_SYSINFO`, `(buf)`, **120-byte** packed, `totalram` at 32 scaled by `mem_unit` at 104, `procs` u16 at 80 |
| **uname** | syscall **#34**, `(buf, len=64)`, **64-byte** four 16-byte NUL-padded fields — `0 sysname · 16 nodename · 32 release · 48 machine` (agnos-userland-abi.md §4.3) | `SYS_UNAME`, `(buf)`, **390-byte** six 65-byte fields |
| **gettid/geteuid** | no separate tid/euid (single-threaded, capability-gated) → route to `getpid`/`getuid` | distinct `SYS_GETTID` / `SYS_GETEUID` |

A library can't pick the right struct without re-encoding cyrius's own per-target
knowledge — which is the redundancy this whole decomposition is removing. Note one
sharp edge the current agnosys code works around: on the **agnos x86 target** the
Linux x86 peer wrongly defines `SYS_SYSINFO=99` and doesn't define `SYS_UNAME`
(peers self-gate by *arch*, not *OS*), so agnosys hard-codes the literals `35`/`34`.
If cyrius adopts this, the agnos peer should define `SYS_SYSINFO`/`SYS_UNAME` to the
sovereign numbers so the literals disappear.

## Proposed surface (Result-typed, zero-alloc on success)
Suggested home: a new `lib/sysinfo.cyr` (or fold into `process.cyr`). Names are the
agnosys ones minus the `agnosys_` prefix — rename to taste:

```
# process identity
fn sys_getpid(): i64                 # syscall(SYS_GETPID)
fn sys_gettid(): i64                 # agnos → getpid; linux → SYS_GETTID
fn sys_getuid(): i64
fn sys_geteuid(): i64                # agnos → getuid; linux → SYS_GETEUID
fn sys_is_root(): i64                # geteuid()==0

# sysinfo — fill caller buffer, then typed accessors
fn sys_sysinfo(out): i64            # Result(out); per-target #/size/args
fn sysinfo_uptime(info): i64        # seconds
fn sysinfo_total_memory(info): i64  # bytes (linux applies saturating *mem_unit)
fn sysinfo_free_memory(info): i64   # bytes
fn sysinfo_procs(info): i64         # agnos u64 / linux u16

# uname — fill caller buffer, then field pointers
fn sys_uname(out): i64             # Result(out); per-target #/size/args
fn uname_hostname(uts): i64         # &nodename
fn uname_release(uts): i64
fn uname_machine(uts): i64
```

Plus the per-target offset/size constants (`SI_*`/`SYSINFO_SIZE`, `UTS_*`/`UTS_SIZE`)
the accessors read. Full reference implementation (both targets, saturating-multiply
guard, single-thread routing, the `35`/`34` literal workaround + rationale) is the
current `agnosys/src/syscall.cyr` — adopt that as the starting point.

## Downstream that consolidates once this lands
- **sigil** — `src/sysinfo.cyr` is an **interim** copy (`agnosys_uname` + `uname_release`
  for per-target UTS), explicitly noted as "→ cyrius eventually" in sigil's roadmap
  (P2: *retire sysinfo.cyr once cyrius owns the system-info surface*). Deletes when
  this lands.
- any future `iam` / `chakshu` / `mihi`-class tool that wants uptime/host/mem without
  re-deriving the per-target structs.

## Not in scope here
- The agnosys per-arch `syscall_x86_64_*` / `syscall_arch` files — pure duplication of
  cyrius's `syscalls_*.cyr`, just **deleted** as agnosys vacates (no port needed).
- The fs/io/process hazards from the cross-target audit — filed separately in
  `2026-06-18-stdlib-native-agnos-abi-fs.md`.
