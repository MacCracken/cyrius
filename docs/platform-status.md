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
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cycc **2,057,736 B** at 6.7.9 (`wc -c build/cycc`); the seed → cybs → cycc chain and the cycc fixpoint are byte-identical every release (release-gate steps 1–2). SIMD Phase 5 is complete on all four backends (x86 SSE / AVX2, aarch64 NEON, Win64 PE, cx). **W^X** by default since v6.3.12 (text `R E` / data `RW ` `PT_LOAD` split; `CYRIUS_WX=0` opts out). `CYRIUS_DCE=1` performs REAL elimination only here: on a plain W^X executable (123,048 → 16,552 B measured on the v6.6.1 repro) and, since 6.7.11, on a `kernel;` image and a `CYRIUS_WX=0` executable; `--pie` and `shared;` images decline compaction and NOP-fill instead, as the aarch64, Mach-O and PE targets always do. `kernel;` images and `CYRIUS_WX=0`, which put the data right after the code, declined from 6.6.20 and compact again since 6.7.11: the data moves down with the code and every data address the code holds moves with it. |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross compiler `build/cycc_aarch64` plus the native compiler `build/cycc-native-aarch64` (tracked; 1,881,280 B at 6.7.9, held in lockstep by release-gate step 1b), which self-hosts byte-identical on real `pi` every release (native self-host repaired v5.6.32). `CYRIUS_DCE=1` NOP-fills (no aarch64 compaction repair model yet). `lib/net.cyr` spells its socket syscalls with x86_64 numbers **by design** — the stdlib rule is the x86 number plus an `ESYSXLAT` row — and `tests/gates/platform/net_esysxlat_coupling.sh` holds both aarch64 rows per number. Open: [`2026-10-08-aarch64-native-region-literal-translated-silently.md`](development/issues/2026-10-08-aarch64-native-region-literal-translated-silently.md). Full corpus on real hardware: **590 / 590** on the 6.7.12 windows lane's tree (2026-10-15); the release gate runs the full corpus here from 6.7.12 (D8). |
| cyrius-x bytecode | .cyx | **✅ Narrow + Broad** — portable target since v6.4.20: one `.cyx` doing I/O runs on all four hosts through `cxvm`. SIMD lowers to per-lane scalar loops (v6.4.32); 64-bit immediates (`movhk`, v6.4.58); indirect calls — `callptr`, `fncall*`, allocator vtables, `vec_sort_by` — through `callind` (0x69, v6.5.13); a 9–16 B struct is returned by value (6.7.8). `programs/cxvm.cyr`'s header lists the opcodes (the 0x6x band runs to `ftrunc`, 0x6E, 6.6.13) and an opcode it does not implement traps. Single-threaded: `THREADS_CONCURRENT` and `CHAN_BLOCKING` are 0. **Out of scope by name** (6.6.11): `lib/tls.cyr`, `lib/tls_native.cyr` and the `lib/sigil.cyr` fold — several MB of bytecode against a 512 KiB `.cyx` — are refused at compile time. **Syscalls**: the authority is `programs/cxvm.cyr`'s op-0x70 dispatch — `read`(0) / `write`(1) / `open`(2) / `close`(3) / `lseek`(8) / `exit`(60) issued with pointer translation, `getrandom`(318) / `clock_gettime`(228) served through the HOST's stdlib (v6.6.8); any other number goes to the host raw, **without** pointer translation. ⚠ **cxvm is NOT a sandbox** — see *cyrius-x guest contract* below. Open: [`2026-10-11-cx-does-not-auto-call-main.md`](development/issues/archived/2026-10-11-cx-does-not-auto-call-main.md), [`2026-10-11-sakshi-fold-has-no-cx-arm.md`](development/issues/archived/2026-10-11-sakshi-fold-has-no-cx-arm.md). |
| macOS x86_64 | Mach-O | **✅ Narrow + Broad** — the full toolchain (wrapper + `cycc`) self-hosts byte-identical on real Intel hardware (`ach`), a release-gate host since v6.4.59. Apple Intel is EOL upstream, so arm64 (`ecb`) stays the primary macOS target, but x86 is release-gated, not parity-only. **Real threads** since 6.6.19 (raw `bsdthread_*` — this static, libSystem-free binary owns the one-shot registration — with per-thread TLS in the gs base; before 6.6.19 every thread body ran inline). ⚠ `CYRIUS_DCE=1` NOP-fills but does not compact: the stub table is reached through rip-relative displacements the compaction pass cannot repair (between v6.5.72 and v6.6.0 it emitted a binary that faulted). Open: [`2026-10-08-x86-macos-emacho-sysxlat-not-folded.md`](development/issues/2026-10-08-x86-macos-emacho-sysxlat-not-folded.md) (size), [`2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md`](development/issues/2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md). Full corpus on real hardware: **589 / 590** on the 6.7.12 windows lane's tree (2026-10-15; 585 / 589 at the slot open) — the one left is `platform/pwd_grp.tcyr`, the stdlib's passwd / group readers parsing Darwin's uid -2 as 0 (filed); the release gate runs the full corpus here once it is fixed (D8). |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real hardware (`ecb`) since v6.0.45, re-verified every release. **Real threads** since v6.5.44: `thread_create` starts a Darwin thread through libSystem `pthread_create` (`__got[5]`; the raw `bsdthread_register` is already spent by libpthread in a libSystem process), `thread_join` and the channel park on `__ulock`, `lib/sync_macos.cyr` is a blocking three-state `__ulock` lock, and each thread's TLS block is keyed on `TPIDRRO_EL0` (`tests/gates/platform/macos_arm64_real_threads.sh`). `CYRIUS_DCE=1` NOP-fills (aarch64 has no compaction repair model). `sys_openat` keeps its dirfd (Darwin `openat`, 6.7.12 — it reached BSD `open` with the dirfd dropped, so cbt's `[embed]` open could not walk from the project root). Open: [`2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md`](development/issues/2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md), [`2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md`](development/issues/2026-10-11-macos-exec-child-keeps-launcher-signal-mask.md). Full corpus on real hardware: **589 / 590** on the 6.7.12 windows lane's tree (2026-10-15; 585 / 589 at the slot open) — the one left is `platform/pwd_grp.tcyr`, the stdlib's passwd / group readers parsing Darwin's uid -2 as 0 (filed); the release gate runs the full corpus here once it is fixed (D8). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real `cass` (Windows 11) every release; `cycc_win` ships in the release tarball. Process creation, real Win32 threads (v6.0.61), environment, file I/O and directory enumeration (`lib/fs_win.cyr`, v6.1.18) through `EPE_SYSCALL_DYNAMIC` dispatch; SRWLOCK mutex; `xflock` through `LockFileEx` / `UnlockFileEx` on a sentinel byte (6.7.12 — it answered -1); cbt's `[embed]` / `${file:}` open refuses a file whose final path (`GetFinalPathNameByHandleW`) is outside the project root, so a junction planted after the link check is not followed (6.7.12); .reloc + ASLR with HIGH_ENTROPY_VA. ⚠ Before v6.4.64 a call with **10+ arguments** silently corrupted argument 1 (`tests/tcyr/crossos/win64_stack_args.tcyr` holds the fix). ⚠ `CYRIUS_DCE=1` NOP-fills but does not compact: the import table is reached through rip-relative displacements the compaction pass cannot repair (between v6.5.72 and v6.6.0 it emitted a binary that faulted `0xC0000005` before `main`). Open: [`2026-10-08-windows-symlink-no-long-path-prefix.md`](development/issues/2026-10-08-windows-symlink-no-long-path-prefix.md), [`2026-10-08-windows-trust-store-parity-gaps.md`](development/issues/2026-10-08-windows-trust-store-parity-gaps.md), [`2026-10-08-async-iocp-pe-plain-cmd-c-step2.md`](development/issues/2026-10-08-async-iocp-pe-plain-cmd-c-step2.md), [`2026-10-10-windows-cli-drops-target-selectors.md`](development/issues/archived/2026-10-10-windows-cli-drops-target-selectors.md), [`2026-10-10-strict-pin-and-pie-inert-off-linux.md`](development/issues/2026-10-10-strict-pin-and-pie-inert-off-linux.md). Full corpus on real hardware: **589 / 590** on the 6.7.12 windows lane's tree (2026-10-15; 563 / 589 at the 6.7.12 slot open, 7f57e532) — every failure triaged: the PE-inapplicable rows (socketpair / fork, the stdout / stderr captures, `mprotect`, `uname` / `sysinfo`, `/etc/passwd`, the Win64 setjmp stub) carry named `CYRIUS_TARGET_WIN` arms that still assert, the fixture defects (`/tmp` scratch paths, file-fed sockets, an environment-sized trust-store floor) are fixed, and the one left, `stdlib/result_stdlib.tcyr`, is two filed PE defects (an open is -1 for every failure; a failed `ReadFile` reads as end of file). The release gate runs the `crossos/` subset here until that reaches zero (D8). |
| Compiler optimization (O1–O6) | — | **✅ Closed** (v5.6.5 + v5.6.7–v5.6.27). |
| AGNOS userspace | ELF (ring-3, agnos ABI) | **✅ Shipped** — `CYRIUS_TARGET_AGNOS` ring-3 target (`cyrius build --agnos`; boot-to-prompt v6.0.55–.56). The syscall peer (`lib/syscalls_x86_64_agnos.cyr`, standalone) tracks the live kernel through agnos 1.57.9: the channel band and endowment, `sys_spawn_path_env` / `sys_spawn_argv`, blocking waits, the non-blocking read / write forms, and declines (-38) for the calls agnos lacks (`sys_ppoll`, `sys_ioctl`, `sys_fstatat`, 6.7.9). Single-threaded: thread bodies run inline (`THREADS_CONCURRENT` = 0). Rot gates: `scripts/agnos-crossbuild-gate.sh`, `tests/gates/platform/io_rdwr_agnos.sh`, `tests/gates/platform/folds_agnos_parity.sh` (every fold that builds for Linux must build for agnos) and the fake-kernel peer gate `tests/gates/platform/agnos_peer_fake_kernel.sh`. Distinct from the bare-metal KERNEL target below. |
| UEFI Application | PE32+ (Subsystem 10) | **✅ Shipped** — `_TARGET_EFI_APPLICATION` emit mode (PE32+ container + Subsystem 10 + EFI-variant EEXIT + zeroed Data Dirs [1]/[12]), landed across the v5.11.47–v5.11.49 gnoboot arc. OVMF runtime smoke proven; structural gate in `programs/checks/platform_efi.cyr`. **Secure Boot**: native Authenticode PE signing (`cyrius sign-efi <pe> <key.der> <cert.der> <out>`, v6.4.47, through the `cyrsign-efi` helper) + variable enrollment (`.esl` / `.auth` — `efi_signature_list_from_cert` / `efi_auth_from_esl` / `efi_time`, v6.4.48, in the folded sigil). |
| RISC-V (rv64) | ELF | Queued — pinned at **v6.8.x or v6.9.x** in [`roadmap_6.md`](development/roadmap_6.md) (hardware in hand; planned as a new rv64 backend and syscall peer, accepted only when it self-hosts on the real rv64 box). |
| Bare-metal | ELF (no-libc) | **✅ Shipped** — all seven design deliverables: #1–#3 (target triple `--target=<arch>-bare-metal-elf` / no-libc ELF / `#naked`, v6.2.27–.28; QEMU boot gate + freestanding-TLS entropy .28), #5 `[sections]` settable kernel load base + #6 inline-asm memory fences (v6.3.3), #7 freestanding `lib/tls_native.cyr` kernel link + in-kernel handshake smoke (v6.3.4), and **#4 the forbidden-module check (v6.5.24)**: a host-OS-only module marks itself with a first-column `#host_only` line (`lib/fs.cyr`, `lib/process.cyr`, `lib/net.cyr`), and a kernel build that pulls one fails naming it (`tests/gates/platform/bare_metal_forbidden_module.sh`). The bounds-checked mode is refused for a kernel / EFI image (6.7.8). `CYRIUS_DCE=1` shrinks an x86_64 `kernel;` image since 6.7.11 (not a `--pie` kernel; aarch64 still NOP-fills) ([`2026-10-10-agnos-kernel-dce-compaction-moves-data.md`](development/issues/archived/2026-10-10-agnos-kernel-dce-compaction-moves-data.md); `tests/gates/codegen/dce_kernel_compaction_boots.sh` boots one under QEMU). Open: [`2026-10-08-kernel-float-global-init-not-baked.md`](development/issues/2026-10-08-kernel-float-global-init-not-baked.md). AGNOS kernel target (not the userspace target above). |

## Verification hosts (cross-arch SSH-wired)

Every compiler-backend or stdlib change is verified on real hardware on all four hosts
(CLAUDE.md, *Cross-OS self-host is non-negotiable*). They are step 4 of
`scripts/release-gate.sh` — a gate on **every** `.NN`, not just at closeout. Since 6.7.0 the
four legs (`for H in ecb ach cass pi`) start in the background beside `check.sh`;
`CYRIUS_GATE_SERIAL=1` walks them in turn. At **6.7.9** (the 2026-10-11 release gate) all four
report `SELFHOST_OK` + `LIBTEST_OK` over the `crossos/` subset — **267** files; DERIVE it with
`find tests/tcyr/crossos -name '*.tcyr' | wc -l`.

⚠ **`LIBTEST_OK` is the `tests/tcyr/crossos/` subset on ecb, ach and cass, the full corpus on
`pi`** (6.7.12, D8: a host runs the whole corpus by default once its full run is at zero —
`CO_FULL_HOSTS` in `scripts/cross-os-selfhost.sh`), and the gate prints its own numerator /
denominator so a subset never reads as the whole. `CYRIUS_CROSS_OS_FULL=1 sh
scripts/cross-os-selfhost.sh <host>` runs the whole corpus on any host. Measured on real hardware
on the 6.7.12 windows lane's tree (2026-10-15, 590 tcyr): **590 / 590** on `pi`; **589 / 590** on
`ecb` and `ach` (`platform/pwd_grp.tcyr` — the stdlib's passwd / group readers parse Darwin's uid -2
as 0, filed); **589 / 590** on `cass` (`stdlib/result_stdlib.tcyr`, two filed PE defects). At the
6.7.12 slot open (7f57e532, 589 tcyr) they were 589 / 589, 585 / 589, 585 / 589 and 563 / 589. Quote
each with its version, never as a current figure.

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

*Stated at 6.6.10, revised at 6.6.12 when cxvm gained its memory and stack traps; the matching
statement is in `programs/cxvm.cyr`'s header.*

**cxvm is an interpreter for TRUSTED bytecode. It is not a sandbox: a guest can ask the host
kernel for anything the cxvm process may do.** What it does and does not guarantee:

- **The VM keeps a guest inside its own memory (6.6.12, the cxvm host-memory bug).** Every load and store
  (`load8/16/32/64`, `store8/16/32/64`) is checked for its FULL width against the data segment
  `[8, _CX_MEM_SIZE)`; `[0, 8)` is refused as the null page (guest 0 is the in-memory copy of the
  bytecode, so a null store used to succeed silently). The data and call stacks (65536 entries
  each) trap on overflow and underflow; the guest stack (`sub sp`, growing down from 1 MB) traps
  before it reaches the loaded image — the program's globals and its `lib/alloc_cx.cyr` heap; a
  negative program counter traps; an opcode cxvm does not implement traps. Each trap prints
  `cxvm: <what> <value> at pc <N>` (or `cxvm: unknown opcode 0xNN at pc <N>`) and exits 1.
  Before 6.6.12 none of this was checked: a guest address past 1 MB read and wrote cxvm's own heap
  (the register file, the stacks, the loaded code), the 513th nested call overwrote the loaded
  code, and an unknown opcode was a silent no-op.
- **The syscall opcode (0x70) is a pass-through.** The translated calls (`read` 0, `write` 1,
  `open` 2) check their buffer — the whole `[buf, buf + count)`, or a path up to its NUL — and
  answer `-EFAULT` without reaching the host when it leaves the data segment (6.6.12);
  `getrandom` (318) / `clock_gettime` (228) are host-served with the same check. **Every other
  number goes to the host kernel as-is, with the guest's raw register values** — so a guest can
  issue any syscall the cxvm process may (open/unlink/execve/kill …) and pass it host addresses.
- **Control flow:** `callind` traps a non-positive target (v6.5.13), a negative pc traps (6.6.12),
  and a program counter at or past the end of the image halts the run.

**What that means for untrusted bytecode:** because of the syscall pass-through, running a `.cyx`
you did not build (or whose producer you do not trust) is equivalent to running a native binary with
cxvm's privileges. Treat `.cyx` files like executables: verify their origin (e.g. a detached
signature over the file) before running them, and run cxvm under the OS's own isolation (a separate
user, a container, seccomp / sandbox-exec, a job object) when the input is not yours. The bytecode
format has no verifier and none is planned for 6.x; a syscall allowlist would be a new design, not a
patch. `tests/gates/codegen/cx_tailcall_and_vm_traps.sh` holds every trap above.

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
