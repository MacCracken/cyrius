# Platform Status

Current platform coverage for the Cyrius toolchain. **Refresh
target**: every closeout pass (CLAUDE.md step 11).
[`CHANGELOG.md`](../CHANGELOG.md) is the per-release add history and
[`roadmap.md`](development/roadmap.md) holds the pinned future targets;
this file is the "what works now" snapshot. Volatile per-release figures
(sizes, gate counts, the hosts' last result) are in
[`development/state.md`](development/state.md).

> **Last verified against live code: 2026-10-12, at 6.7.9** (the tree a few doc / lib commits past
> the tag; the compiler unchanged). Every row was re-read against `src/`, `lib/`, the CHANGELOG
> and the open issue queue (`docs/development/issues/`), not against this file's prior text. The
> real-hardware results are the 6.7.9 release gate's (CHANGELOG [6.7.9]); the full-corpus figures
> are older single measurements and carry their version.

| Platform | Format | Status |
|----------|--------|--------|
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cycc **2,223,320 B** at 6.7.11 (`wc -c build/cycc`); the seed → cybs → cycc chain and the cycc fixpoint are byte-identical every release (release-gate steps 1–2). SIMD Phase 5 is complete on all four backends (x86 SSE / AVX2, aarch64 NEON, Win64 PE, cx). **W^X** by default since v6.3.12 (text `R E` / data `RW ` `PT_LOAD` split; `CYRIUS_WX=0` opts out). `CYRIUS_DCE=1` performs REAL elimination only here: on a plain W^X executable (123,048 → 16,552 B measured on the v6.6.1 repro) and, since 6.7.11, on a `kernel;` image and a `CYRIUS_WX=0` executable (which put the data right after the code: it moves down with the code, and every data address the code holds moves with it; both declined from 6.6.20 to 6.7.10); `--pie` and `shared;` images decline compaction and NOP-fill instead, as the aarch64, Mach-O and PE targets always do. |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross compiler `build/cycc_aarch64` plus the native compiler `build/cycc-native-aarch64` (tracked; 1,881,280 B at 6.7.9, held in lockstep by release-gate step 1b), which self-hosts byte-identical on real `pi` every release (native self-host repaired v5.6.32). `CYRIUS_DCE=1` NOP-fills (no aarch64 compaction repair model yet). `lib/net.cyr` spells its socket syscalls with x86_64 numbers **by design** — the stdlib rule is the x86 number plus an `ESYSXLAT` row — and `tests/gates/platform/net_esysxlat_coupling.sh` holds both aarch64 rows per number. Open: [`2026-10-08-aarch64-native-region-literal-translated-silently.md`](development/issues/archived/2026-10-08-aarch64-native-region-literal-translated-silently.md). Full corpus on real hardware: **593 / 593** on the 6.7.12 windows lane's tree (2026-10-15); the release gate runs the full corpus here from 6.7.12 (D8). |
| cyrius-x bytecode | .cyx | **✅ Narrow + Broad** — portable target since v6.4.20: one `.cyx` doing I/O runs on all four hosts through `cxvm`. SIMD lowers to per-lane scalar loops (v6.4.32); 64-bit immediates (`movhk`, v6.4.58); indirect calls — `callptr`, `fncall*`, allocator vtables, `vec_sort_by` — through `callind` (0x69, v6.5.13); a 9–16 B struct is returned by value (6.7.8). `programs/cxvm.cyr`'s header lists the opcodes (the 0x6x band runs to `ftrunc`, 0x6E, 6.6.13) and an opcode it does not implement traps. Single-threaded: `THREADS_CONCURRENT` and `CHAN_BLOCKING` are 0. **Program size** (6.7.12): cx bytecode goes into a fixed 4 MiB code region (it was 512 KiB, which a ~900 KB program such as `tests/tcyr/crossos/yukti_statfs_and_stdlib_constants.tcyr` overflowed with a bare "codebuf overflow"); past it `cycc_cx` refuses by name — `error: cx bytecode exceeds the cx code region (4194304 B): <n> B emitted when fn '<name>' (its code starts at byte <off>) reached it — build this program for a native target` — and cxvm's guest memory is 8 MiB, its `.cyx` read cap that plus the 8-byte header; `alloc()` gets the free guest memory between the image and the stack through the guest `brk` cxvm serves (6.7.14 — a 128 KB static heap until then), and past it stops with `alloc: cx heap exhausted at <N> B (…)`. **Out of scope by name** (6.6.11, kept at 6.7.12): `lib/tls.cyr`, `lib/tls_native.cyr` and the `lib/sigil.cyr` fold — several MB of bytecode (2.4–2.9 MB `.cyx` measured at 6.7.12) for a single-threaded test VM — are refused at compile time. **Syscalls**: the authority is `programs/cxvm.cyr`'s op-0x70 dispatch — `read`(0) / `write`(1) / `open`(2) issued with pointer translation, `getrandom`(318) / `clock_gettime`(228) served through the HOST's stdlib (v6.6.8), `brk`(12) served in guest space (6.7.14), a short list of scalar-only calls (`close`, `lseek`, `exit`, `getpid`, `kill`, `fork`, `fsync` … — `_cx_host_sys`) served through the HOST's own stdlib wrappers (6.7.15 — until then they went out as the guest's x86-Linux number, which the aarch64 and Mach-O hosts renumbered into other calls); every other number answers -ENOSYS (-38) without reaching the host (6.7.14, D55 — until then it went to the host raw, **without** pointer translation). The stdlib's cx arms answer the same way (6.7.12): `cyr_mmap` / `mmap_stack` -1 (so `mmap_anon` and `fl_alloc` 0) and `sys_pipe` / `sys_fstat` / `sys_unlink` -38 — see the guest contract below. ⚠ **cxvm is NOT a sandbox** — see *cyrius-x guest contract* below. Open: [`2026-10-11-cx-does-not-auto-call-main.md`](development/issues/archived/2026-10-11-cx-does-not-auto-call-main.md), [`2026-10-11-sakshi-fold-has-no-cx-arm.md`](development/issues/archived/2026-10-11-sakshi-fold-has-no-cx-arm.md). |
| macOS x86_64 | Mach-O | **✅ Narrow + Broad** — the full toolchain (wrapper + `cycc`) self-hosts byte-identical on real Intel hardware (`ach`), a release-gate host since v6.4.59. Apple Intel is EOL upstream, so arm64 (`ecb`) stays the primary macOS target, but x86 is release-gated, not parity-only. **Real threads** since 6.6.19 (raw `bsdthread_*` — this static, libSystem-free binary owns the one-shot registration — with per-thread TLS in the gs base; before 6.6.19 every thread body ran inline). ⚠ `CYRIUS_DCE=1` NOP-fills but does not compact: the stub table is reached through rip-relative displacements the compaction pass cannot repair (between v6.5.72 and v6.6.0 it emitted a binary that faulted). Open: [`2026-10-08-x86-macos-emacho-sysxlat-not-folded.md`](development/issues/archived/2026-10-08-x86-macos-emacho-sysxlat-not-folded.md) (size), [`2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md`](development/issues/archived/2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md). Full corpus on real hardware: **593 / 593** on the 6.7.12 windows lane's tree (2026-10-15; 585 / 589 at the slot open — the last failure, `platform/pwd_grp.tcyr`, was the stdlib's passwd / group readers parsing Darwin's uid -2 as 0, fixed in 6.7.12); the release gate runs the full corpus here from 6.7.12 (D8). |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real hardware (`ecb`) since v6.0.45, re-verified every release. **Real threads** since v6.5.44: `thread_create` starts a Darwin thread through libSystem `pthread_create` (`__got[5]`; the raw `bsdthread_register` is already spent by libpthread in a libSystem process), `thread_join` and the channel park on `__ulock`, `lib/sync_macos.cyr` is a blocking three-state `__ulock` lock, and each thread's TLS block is keyed on `TPIDRRO_EL0` (`tests/gates/platform/macos_arm64_real_threads.sh`). `CYRIUS_DCE=1` NOP-fills (aarch64 has no compaction repair model). `sys_openat` keeps its dirfd (Darwin `openat`, 6.7.12 — it reached BSD `open` with the dirfd dropped, so cbt's `[embed]` open could not walk from the project root). Open: [`2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md`](development/issues/archived/2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md), [`2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md`](development/issues/archived/2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md). Full corpus on real hardware: **593 / 593** on the 6.7.12 windows lane's tree (2026-10-15; 585 / 589 at the slot open — the last failure, `platform/pwd_grp.tcyr`, was the stdlib's passwd / group readers parsing Darwin's uid -2 as 0, fixed in 6.7.12); the release gate runs the full corpus here from 6.7.12 (D8). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real `cass` (Windows 11) every release; `cycc_win` ships in the release tarball. Process creation, real Win32 threads (v6.0.61), environment, file I/O and directory enumeration (`lib/fs_win.cyr`, v6.1.18) through `EPE_SYSCALL_DYNAMIC` dispatch; SRWLOCK mutex; `xflock` through `LockFileEx` / `UnlockFileEx` on a sentinel byte (6.7.12 — it answered -1); `xsymlink` creates a link at a path of any length, and to an absolute target of any length (`\\?\` at 248+ units, 6.7.12 — past 260 units it failed -1); cbt's `[embed]` / `${file:}` open refuses a file whose final path (`GetFinalPathNameByHandleW`) is outside the project root, so a junction planted after the link check is not followed (6.7.12); .reloc + ASLR with HIGH_ENTROPY_VA. ⚠ Before v6.4.64 a call with **10+ arguments** silently corrupted argument 1 (`tests/tcyr/crossos/win64_stack_args.tcyr` holds the fix). ⚠ `CYRIUS_DCE=1` NOP-fills but does not compact: the import table is reached through rip-relative displacements the compaction pass cannot repair (between v6.5.72 and v6.6.0 it emitted a binary that faulted `0xC0000005` before `main`). Open: [`2026-10-08-windows-trust-store-parity-gaps.md`](development/issues/archived/2026-10-08-windows-trust-store-parity-gaps.md), [`2026-10-08-async-iocp-pe-plain-cmd-c-step2.md`](development/issues/archived/2026-10-08-async-iocp-pe-plain-cmd-c-step2.md), [`2026-10-10-windows-cli-drops-target-selectors.md`](development/issues/archived/2026-10-10-windows-cli-drops-target-selectors.md), [`2026-10-10-strict-pin-and-pie-inert-off-linux.md`](development/issues/archived/2026-10-10-strict-pin-and-pie-inert-off-linux.md). Full corpus on real hardware: **627 / 627** on the 6.7.14 platform lane's tree (2026-10-16; 589 / 590 on the 6.7.12 windows lane's tree, 563 / 589 at the 6.7.12 slot open, 7f57e532) — the PE-inapplicable rows (socketpair / fork, the stdout / stderr captures, `mprotect`, `uname` / `sysinfo`, `/etc/passwd`, the Win64 setjmp stub) carry named `CYRIUS_TARGET_WIN` arms that still assert, the fixture defects (`/tmp` scratch paths, file-fed sockets, an environment-sized trust-store floor) were fixed at 6.7.12, and the last two PE defects — an open was -1 for every failure, a failed `ReadFile` read as end of file — were fixed at 6.7.14: a failed `CreateFileW` / `ReadFile` / `WriteFile` / `SetFilePointerEx` answers a negative errno through `GetLastError`. So the release gate runs the whole corpus on cass too (D8). |
| Compiler optimization (O1–O6) | — | **✅ Closed** (v5.6.5 + v5.6.7–v5.6.27). |
| AGNOS userspace | ELF (ring-3, agnos ABI) | **✅ Shipped** — `CYRIUS_TARGET_AGNOS` ring-3 target (`cyrius build --agnos`; boot-to-prompt v6.0.55–.56). The syscall peer (`lib/syscalls_x86_64_agnos.cyr`, standalone) tracks the live kernel through agnos 1.57.9: the channel band and endowment, `sys_spawn_path_env` / `sys_spawn_argv`, blocking waits, the non-blocking read / write forms, and declines (-38) for the calls agnos lacks (`sys_ppoll`, `sys_ioctl`, `sys_fstatat`, 6.7.9). Single-threaded: thread bodies run inline (`THREADS_CONCURRENT` = 0). Rot gates: `scripts/agnos-crossbuild-gate.sh`, `tests/gates/platform/io_rdwr_agnos.sh`, `tests/gates/platform/folds_agnos_parity.sh` (every fold that builds for Linux must build for agnos) and the fake-kernel peer gate `tests/gates/platform/agnos_peer_fake_kernel.sh`. Distinct from the bare-metal KERNEL target below. |
| UEFI Application | PE32+ (Subsystem 10) | **✅ Shipped** — `_TARGET_EFI_APPLICATION` emit mode (PE32+ container + Subsystem 10 + EFI-variant EEXIT + zeroed Data Dirs [1]/[12]), landed across the v5.11.47–v5.11.49 gnoboot arc. OVMF runtime smoke proven; structural gate in `programs/checks/platform_efi.cyr`. **Secure Boot**: native Authenticode PE signing (`cyrius sign-efi <pe> <key.der> <cert.der> <out>`, v6.4.47, through the `cyrsign-efi` helper) + variable enrollment (`.esl` / `.auth` — `efi_signature_list_from_cert` / `efi_auth_from_esl` / `efi_time`, v6.4.48, in the folded sigil). |
| RISC-V (rv64) | ELF | Queued — pinned at **v6.8.x or v6.9.x** in [`roadmap_6.md`](development/roadmap_6.md) (hardware in hand; planned as a new rv64 backend and syscall peer, accepted only when it self-hosts on the real rv64 box). |
| Bare-metal | ELF (no-libc) | **✅ Shipped** — all seven design deliverables: #1–#3 (target triple `--target=<arch>-bare-metal-elf` / no-libc ELF / `#naked`, v6.2.27–.28; QEMU boot gate + freestanding-TLS entropy .28), #5 `[sections]` settable kernel load base + #6 inline-asm memory fences (v6.3.3), #7 freestanding `lib/tls_native.cyr` kernel link + in-kernel handshake smoke (v6.3.4), and **#4 the forbidden-module check (v6.5.24)**: a host-OS-only module marks itself with a first-column `#host_only` line (`lib/fs.cyr`, `lib/process.cyr`, `lib/net.cyr`), and a kernel build that pulls one fails naming it (`tests/gates/platform/bare_metal_forbidden_module.sh`). The bounds-checked mode is refused for a kernel / EFI image (6.7.8). `CYRIUS_DCE=1` shrinks an x86_64 `kernel;` image since 6.7.11 (not a `--pie` kernel; aarch64 still NOP-fills) ([`2026-10-10-agnos-kernel-dce-compaction-moves-data.md`](development/issues/archived/2026-10-10-agnos-kernel-dce-compaction-moves-data.md); `tests/gates/codegen/dce_kernel_compaction_boots.sh` boots one under QEMU). Open: [`2026-10-08-kernel-float-global-init-not-baked.md`](development/issues/archived/2026-10-08-kernel-float-global-init-not-baked.md). AGNOS kernel target (not the userspace target above). |

## Verification hosts (cross-arch SSH-wired)

Every compiler-backend or stdlib change is verified on real hardware on all four hosts
(CLAUDE.md, *Cross-OS self-host is non-negotiable*). They are step 4 of
`scripts/release-gate.sh` — a gate on **every** `.NN`, not just at closeout. Since 6.7.0 the
four legs (`for H in ecb ach cass pi`) start in the background beside `check.sh`;
`CYRIUS_GATE_SERIAL=1` walks them in turn. At **6.7.9** (the 2026-10-11 release gate) all four
report `SELFHOST_OK` + `LIBTEST_OK` over the `crossos/` subset — **267** files; DERIVE it with
`find tests/tcyr/crossos -name '*.tcyr' | wc -l`.

⚠ **`LIBTEST_OK` is the full corpus on all four hosts** — `ecb`, `ach` and `pi` from 6.7.12, `cass`
from 6.7.14 (6.7.12, D8: a host runs the whole corpus by default once its full run is at zero —
`CO_FULL_HOSTS` in `scripts/cross-os-selfhost.sh`; `CYRIUS_CROSS_OS_FULL=0` forces the
`tests/tcyr/crossos/` subset), and the gate prints its own numerator / denominator so a subset never
reads as the whole. `CYRIUS_CROSS_OS_FULL=1 sh
scripts/cross-os-selfhost.sh <host>` runs the whole corpus on any host. Measured on real hardware
on the 6.7.12 windows lane's tree (2026-10-15, 590 tcyr): **590 / 590** on `pi`; **589 / 590** on
`ecb` and `ach` (`platform/pwd_grp.tcyr` — the stdlib's passwd / group readers parsed Darwin's uid -2
as 0, fixed in the same release: **593 / 593** on both at the lane's review fix, 593 tcyr);
**589 / 590** on `cass` (`stdlib/result_stdlib.tcyr`, two filed PE defects). At the 6.7.12 slot open
(7f57e532, 589 tcyr) they were 589 / 589, 585 / 589, 585 / 589 and 563 / 589. Quote each with its
version, never as a current figure.

| Host | Arch / OS | Role |
|------|-----------|------|
| `pi` | aarch64 Linux (Pi 4) | Native aarch64 self-host + multi-thread / mutex shakedown. |
| `cass` | Windows x86_64 | PE/COFF broad-scope on real Win11. |
| `ecb` | macOS Apple Silicon | Mach-O native verification (broad-scope). |
| `ach` | macOS Intel x86_64 | x86_64 Mach-O self-host — release-gate host since v6.4.59. |

> "NO EXCUSE THAT SHIT [is] BEING FOUND BY PORTS" — user
> 2026-05-04. SSH-wired hosts mean cross-test is mechanical, not
> aspirational.

## cyrius-x guest contract (cxvm)

*Stated at 6.6.10, revised at 6.6.12 when cxvm gained its memory and stack traps and at 6.7.14
when its syscall dispatch began refusing what it does not translate (D55); the matching statement
is in `programs/cxvm.cyr`'s header.*

**cxvm is an interpreter for TRUSTED bytecode. It is not a sandbox: through the calls it translates
or passes, a guest acts on the host with the cxvm process's privileges.** What it does and does not
guarantee:

- **The VM keeps a guest inside its own memory (6.6.12, the cxvm host-memory bug).** Every load and store
  (`load8/16/32/64`, `store8/16/32/64`) is checked for its FULL width against the data segment
  `[8, _CX_MEM_SIZE)`; `[0, 8)` is refused as the null page (guest 0 is the in-memory copy of the
  bytecode, so a null store used to succeed silently). The data segment is 8 MiB (1 MB until
  6.7.12). The data and call stacks (524288 entries each since 6.7.12, so the segment rather than
  they bounds recursion) trap on overflow and underflow; the guest stack (`sub sp`, growing down
  from the top of the segment) traps before it reaches the guest break — the loaded image (the
  program's globals) and the `lib/alloc_cx.cyr` heap above it (6.7.14; the image end until then); a
  negative program counter traps; an opcode cxvm does not implement traps. Each trap prints
  `cxvm: <what> <value> at pc <N>` (or `cxvm: unknown opcode 0xNN at pc <N>`) and exits 1.
  Before 6.6.12 none of this was checked: a guest address past the segment read and wrote cxvm's own heap
  (the register file, the stacks, the loaded code), the 513th nested call overwrote the loaded
  code, and an unknown opcode was a silent no-op.
- **The syscall opcode (0x70) translates, serves, passes scalars, and refuses the rest (6.7.14,
  D55).** The translated calls (`read` 0, `write` 1, `open` 2) check their buffer — the whole
  `[buf, buf + count)`, or a path up to its NUL — and answer `-EFAULT` without reaching the host
  when it leaves the data segment (6.6.12); `getrandom` (318) / `clock_gettime` (228) are
  host-served with the same check. **`brk` (12) is served in guest space (6.7.14):** the break
  starts at the image end rounded up to 16 and moves while it stays 1 MiB below both the live guest
  sp and the segment's top — sp is a register the guest can raise past the segment, and the break
  is bounded by the segment whatever sp says (otherwise brk answers the old break, as Linux does);
  memory a move grants reads zero.
  `lib/alloc_cx.cyr`'s heap bumps over it — up to ~7 MiB less the image — where it was a static
  128 KB buffer written into every allocating `.cyx`; a `.cyx` built by the 6.7.14 `cycc_cx` that
  allocates needs a 6.7.14 cxvm (an older one answers brk -38 or with a host address, and
  `alloc_init` names it). A short list of **scalar-only** calls — every argument and
  the result an fd, pid, id, flag or length — is served through the HOST's own stdlib wrappers,
  each giving x86_64 Linux's answer (6.7.15): `close`, `lseek`, `exit` / `exit_group`, `dup` /
  `dup2`, `getpid` / `getppid`, the four uid / gid getters, `kill`, `fork`, `sched_yield`, `fsync` /
  `fdatasync`, `flock`, `ftruncate`, `fchmod` / `fchown`, `socket`, `listen`, `unshare`,
  `timerfd_create`, `epoll_create1`, and `fcntl` for its scalar commands (`F_DUPFD`, `F_GETFD` /
  `F_SETFD`, `F_GETFL` / `F_SETFL`, `F_DUPFD_CLOEXEC`) — `_cx_host_sys` in `programs/cxvm.cyr` is
  the list, derived from a run of the cx corpus. `open`'s flags and `fcntl`'s status flags travel in
  x86-Linux bits both ways: the access mode plus `O_CREAT`, `O_EXCL`, `O_TRUNC`, `O_APPEND`,
  `O_NONBLOCK`, `O_DIRECTORY`, `O_NOFOLLOW` and `O_CLOEXEC` are mapped to the host's bits, any other
  bit is dropped off x86_64 Linux and Windows (several mean another flag there). Where the host has no
  route the answer is -38: `socket`, `listen`, `unshare`, `timerfd_create` and `epoll_create1` off
  Linux, and on Windows every call whose PE peer is a stub (`getppid`, `kill`, `dup`, `dup2`, `flock`,
  `fchmod`, `fchown`, the uid / gid getters, `sched_yield`, `fork`, `fcntl`). Until 6.7.15 these
  calls went out as `syscall(<the guest's number>, …)`, which each host's compiler renumbers as if it
  were the host stdlib's own: on aarch64 Linux a guest `lseek` ran `getxattr`, `kill` ran `lseek`,
  `exit_group(77)` exited 0 and `fork` ran `close` (the parent took the child branch); on arm64 macOS
  `kill` ran `lseek` and `getppid` / `dup` / `lseek` / `getuid` / `sched_yield` / `exit_group` died
  of SIGSYS; on both Macs `open`'s Linux flags read as other Darwin flags.
  `tests/gates/codegen/cx_host_dispatch.sh` and the cross-OS legs run one fixture on every host.
  **Every other number answers `-ENOSYS` (-38) without reaching the host** — `stat`, `statfs`,
  `munmap`, `mprotect`, `mmap`, `nanosleep`, `wait4`, the socket calls that take an address, a
  raw `syscall(5, fd, buf)`. Until 6.7.14 every other number went to the host with the guest's raw
  register values, and since the 8 MiB guest (6.7.12) a guest address could be cxvm's own image on
  a Linux host (cxvm links at 0x400000 / 0x600000): `cyr_munmap(0x400000, 65536)` unmapped cxvm's
  code (exit 139), `syscall(5, 1, 0x600100)` wrote a `struct stat` over its globals. Translation
  of further calls can be added one at a time when a cx program needs one.
- **The stdlib's cx arms refuse the pointer-taking wrappers the old pass-through broke
  (6.7.12, D13).** `cyr_mmap` answers -1 on cx, so `mmap_anon` answers 0 — cxvm forwarded the
  mapping to the host, which returned a HOST address no guest access can reach (the first store
  trapped), behind a non-zero pointer a null check passed. `sys_pipe` (its fd buffer left as it
  was), `sys_fstat` and `sys_unlink` answer -ENOSYS (-38): their buffers and paths are guest
  offsets, which the host answered with -EFAULT (and `sys_unlink` left the file). `thread_create`
  answers 0 (6.6.11). The two raw mmap paths D13 missed take the same -1 (6.7.14): `mmap_stack`
  (lib/thread.cyr) and the freelist's mapping, so `fl_alloc` answers 0 instead of faulting the VM on
  a host address. Since 6.7.14 (D55) cxvm itself answers every other pointer-taking call -38
  (above), so these arms keep the same answers under any cxvm.
- **Control flow:** `callind` traps a non-positive target (v6.5.13), a negative pc traps (6.6.12),
  and a program counter at or past the end of the image halts the run.

**What that means for untrusted bytecode:** the translated `open` / `write` and the scalar-only
calls (`kill`, `fork`, `unshare`, `ftruncate` …) still act on the host with cxvm's privileges,
so running a `.cyx` you did not build (or whose producer you do not trust) is close to running a
native binary with them. Treat `.cyx` files like executables: verify their origin (e.g. a detached
signature over the file) before running them, and run cxvm under the OS's own isolation (a separate
user, a container, seccomp / sandbox-exec, a job object) when the input is not yours. The bytecode
format has no verifier and none is planned for 6.x. `tests/gates/codegen/cx_tailcall_and_vm_traps.sh`
holds every trap above; `tests/gates/codegen/cx_guest_syscall_refusal.sh` the syscall dispatch.

## Closeout audit checklist

Run during CLAUDE.md step 11 (vidya / docs sync) at every minor:

- [ ] Update compiler size for primary host (Linux x86_64) row —
      re-measure `wc -c build/cycc`, do not copy the prior number.
- [ ] Verify each "✅ Narrow + Broad" row still holds by **running the
      compiler on the host**, not by reading a CI lane. A green
      checkmark is not verification (the macOS rot, v5.3.13 → v6.0.32).
- [ ] Re-derive every named gap from live code / the open issue queue.
      A row naming a file, a lib or a bug is a claim with an expiry date.
- [ ] Move any "Queued" platform that landed mid-minor to a ✅
      row with the landing version.
- [ ] Cross-check pinned future targets against
      [roadmap.md](development/roadmap.md) and [roadmap_6.md](development/roadmap_6.md) — no version-skew.
- [ ] Re-verify the SSH-wired hosts: `cyrius audit --internal=platform-check` runs the
      cross-OS self-host on ecb / ach / cass / pi (plain `cyrius audit` is the local item
      suite only); `sh scripts/cross-os-selfhost.sh <host>` runs one host.
