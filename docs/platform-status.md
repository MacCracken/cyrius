# Platform Status

Current platform coverage for the Cyrius toolchain. **Refresh
target**: every closeout pass (CLAUDE.md step 11).
[`CHANGELOG.md`](../CHANGELOG.md) is the per-release add history and
[`roadmap.md`](development/roadmap.md) holds the pinned future targets;
this file is the "what works now" snapshot.

> **Last verified against live code: 2026-09-08, at v6.6.1.** Every ✅
> below was re-checked that day — sizes re-measured, open platform gaps
> re-read from the issue queue, not from this file's prior claims.
> (The prior text named three libs as carrying ungated x86 asm; one of
> them no longer exists and the other two were clean. Re-derive, don't
> inherit.)

| Platform | Format | Status |
|----------|--------|--------|
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cycc ~1.59 MB (1,586,184 B at v6.6.19; x86 packed-SIMD/AVX2 emitters in float.cyr; SIMD Phase 5 complete on all four backends — x86 SSE/AVX2, aarch64 NEON, Win64 PE, cx); 3-step bootstrap byte-identical; **W^X** by default since v6.3.12 (text `R E` / data `RW ` `PT_LOAD` split, `CYRIUS_WX=0` opts out). ✅ `CYRIUS_DCE=1` performs REAL elimination here — the only target that shrinks (123,048 → 16,552 B measured on the v6.6.1 repro). |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross-build byte-identity + native self-host on Pi 4 (repaired v5.6.32), re-verified every release on real `pi`. Open arch-gating gap: **`lib/net.cyr` declares seven socket syscall numbers as unguarded x86_64 values** with zero `CYRIUS_ARCH` conditionals, working only because `ESYSXLAT` remaps them (`docs/development/issues/archived/2026-07-30-net-cyr-x86-only-socket-syscall-numbers.md` — archived to keep the open queue lean; the file still reads OPEN, with its §3 collision disarmed at v6.5.7). *(This row previously named `lib/hashmap_fast`, `lib/u128` and `lib/mabda` as carrying ungated x86 asm — verified stale 2026-08-07: `lib/u128.cyr` does not exist, `lib/mabda.cyr` contains no `asm` block, and `lib/hashmap_fast.cyr`'s one block is `#ifdef CYRIUS_ARCH_X86`-gated with a portable `#ifndef` arm.)*  ⭐ Full-corpus run on real hardware, **re-measured 2026-08-20 at v6.5.33: 282 pass / 0 fail of 282** — clean. (Was 255/5 of 260 at v6.5.10; the 5 were a portable core that also failed on macOS, and they are gone.)|
| cyrius-x bytecode | .cyx | **✅ Narrow + Broad** — clean CYX bytecode; portable-target arc complete (v6.4.20): a `.cyx` doing I/O runs on all 4 hosts. Full SIMD codegen (per-lane emitters for every flat-array verb, `_CX_VLOOP_BIN`, v6.4.32) + 64-bit immediates (opcode 253 `movhk`, v6.4.58); cxvm opcodes through **0x69** (`callind`). ✅ **Indirect call works since v6.5.13** — `callptr` / `fncall*` emit `callind` (0x69), so allocator vtables, callbacks and `vec_sort_by` run on cx (re-verified 2026-09-28: `callptr(&add, 40, 2)` and `fncall2(&add, 20, 22)` return 42 on cxvm, `vec_sort_by` sorts). The issue `docs/development/issues/archived/2026-07-30-cx-backend-has-no-indirect-call.md` reads **RESOLVED v6.5.13**. *(This row said "No indirect call … still reads OPEN" until 6.6.10 — stale for a whole minor.)* **Syscalls the guest can use correctly** — the authority is `programs/cxvm.cyr`'s op-0x70 dispatch: `read`(0) / `write`(1) / `open`(2) / `close`(3) / `lseek`(8) / `exit`(60) issued with pointer translation, and `getrandom`(318) / `clock_gettime`(228) served through the HOST's stdlib (v6.6.8); any other number is passed to the host raw, **without** pointer translation (see the guest contract below). ⚠ **cxvm is NOT a sandbox** — see *cyrius-x guest contract*. |
| macOS x86_64 | Mach-O | **✅ Gated self-host** — the full toolchain (wrapper + `cycc`) works on real Intel hardware (`ach`) and self-hosts byte-identical; **`ach` became a first-class release-gate host at v6.4.59** (Intel-Mac x86_64 Mach-O revival — wrapper arch/env, cycc `_read_env` un-stub, `_lint_macho_buf` structural lint, x86 release tarball), verified every slot via `cross-os-selfhost.sh ach`. Apple Intel is EOL upstream, so arm64 (`ecb`) remains the primary/promised macOS target — but x86 is no longer parity-only; it is release-gated. ⭐ Full-corpus run on real hardware, **re-measured 2026-09-28 on the 6.6.10 tree (bite 14): 378 pass / 0 fail of 378** — clean. At the bite's start it was 373 / 2: `derive_enum_inside_ifdef` did not compile for Mach-O and `dynlib_init`'s SKIP path asserted nothing; both fixed. (282/282 at v6.5.33; 233/27 of 260 at v6.5.10) — **4 more than `ecb`**, and the extras are a *timing/clock* cluster the arm64 Mac does not have (`bench_elapsed`, `chrono`, `clock_monotonic`, `fsync`, plus `sakshi_full`, `tls_native_realpeer`, `tls_native_scaffold`). Invisible while only `ecb` was measured. ⚠ **`CYRIUS_DCE=1` NOP-fills here but does not compact (v6.6.1).** Real elimination shrinks the code and shifts every rip-relative displacement; this target reaches a live import/stub table through one the compaction pass cannot repair, and its file geometry is computed before elimination runs. Between v6.5.72 and v6.6.0 it emitted a binary that SIGSEGV'd on real `ach` hardware — unreported, because the filing that surfaced the PE half named only `--win`. It now declines compaction exactly as `_pie_mode` does — correct binary, size unchanged, dead bodies zeroed. ELF still eliminates for real (−86.5% measured). |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real hardware (`ecb`), proven v6.0.45 (the `READFILE`/`openat` cross-OS gate), re-verified every release. ⚠ **No CONCURRENT threading backend**: `lib/thread_macos.cyr` DOES exist (8,614 B, added v6.5.11) and the worker DOES run — as a documented single-threaded SERIAL fallback. What is absent is the concurrent Darwin backend: every `bsdthread_*`/`__ulock_*` occurrence in `lib/` is a COMMENT (9 of 9, re-derived 2026-08-22), and `lib/sync_macos.cyr` is still a 2-state `atomic_cas` spinlock with no kernel wait. *(This row read "there is no `thread_macos.cyr`" until 2026-08-22 — half false since v6.5.11.)* VR-01-guarded, pinned to v6.5.x (`docs/development/issues/archived/2026-07-03-macos-threading-workers-dont-run.md` — **PARTIALLY FIXED at v6.5.39**: the filed headline is closed, band J remains). ⭐ Full-corpus run on real hardware, **re-measured 2026-09-28 on the 6.6.10 tree (bite 14): 378 pass / 0 fail of 378** on `ecb` — clean. At the bite's start it was 372 / 3 (the two above plus `math_inverse_trig`, which compiled to ZERO assertions on aarch64 behind a stale x86 guard); all fixed. (282/282 at v6.5.33.) (Was 237/23 of 260 at v6.5.10.) ⭐ Cross-referencing the other hosts splits that number: **5** of the 23 also fail on `pi` (Linux aarch64) and are a **portable** core — `include_quote_comment`, `large_input`, `large_source`, `preprocessor_past_cap`, `unicode_normconf`, three of which are the same capacity tests that fail to COMPILE under `CYRIUS_IR=3`. The other **18 are macOS-specific**, most downstream of the threading issue above. Nothing regressed — this was previously-unmeasured territory (`docs/development/issues/archived/2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md` — **PREMISE OBSOLETE**, the failures are gone; this line called it "open" two clauses after stating 282/282 pass). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — substantially complete (v6.1.16–v6.1.18): process creation, threading, TLS-via-args, env read, file I/O, and **directory enumeration** (`dir_list`/`is_dir`/`dir_walk` via `lib/fs_win.cyr` + FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW, v6.1.18). `EPE_SYSCALL_DYNAMIC` var-syscall dispatch + portable mutex (SRWLOCK) + `cycc_win` shipping in the release tarball (v6.1.16); `nanosleep(35)`→`Sleep` (v6.1.17). .reloc + 32-bit ASLR (v5.5.35); HIGH_ENTROPY_VA (v5.6.31); gate fixture v5.6.36. **Win64 ABI was declared complete at v5.5.36 and was not** — `ECALLPOPS`' PE branch shuttled stack args through a fixed 5-register table with no path past `nextra == 5`, so calls with **10+ arguments silently corrupted argument 1** for about a year (5–9 args were always fine). Fixed v6.4.64, gated by `tests/tcyr/crossos/win64_stack_args.tcyr` on real hardware; that is the completeness date to trust. Verified every slot on real `cass` via `cross-os-selfhost.sh`. ⚠ **`CYRIUS_DCE=1` NOP-fills here but does not compact (v6.6.1).** Real elimination shrinks the code and shifts every rip-relative displacement; this target reaches a live import/stub table through one the compaction pass cannot repair, and its file geometry is computed before elimination runs. Between v6.5.72 and v6.6.0 it emitted a binary that faulted `0xC0000005` before `main`. It now declines compaction exactly as `_pie_mode` does — correct binary, size unchanged, dead bodies zeroed. ELF still eliminates for real (−86.5% measured).  ⚠ First full-corpus run on real hardware (2026-08-07, v6.5.10): **229 pass / 31 fail of 260** — mostly the expected POSIX surface (TLS, fs/process, sockets), but a few language-level ones deserve their own look (`defer`, `slices_indexing`, `expr_in_fn_args`, `flags`). ⛔ The cass leg could not produce a number until v6.5.10 fixed two harness bugs: it was fail-fast while every other host accumulated, and it had **no per-test timeout** — one test held a single ssh for 33 minutes.|
| Compiler optimization (O1–O6) | — | **✅ Closed** (v5.6.5 + v5.6.7–v5.6.27). |
| AGNOS userspace | ELF (ring-3, agnos ABI) | **✅ Shipped** — `CYRIUS_TARGET_AGNOS` ring-3 target (.48–.49; boot-to-prompt .55–.56). `getenv`/envp (.87) verified on the real agnos 1.43.2 kernel under QEMU. Syscall-peer surface tracks the live kernel: channel band incl. `CH_ENDOW` + `sys_chan_endow` and `sys_spawn_path_env` against agnos 1.56.40 (v6.5.9), `sys_chdir` / `signal_default` / the `x*` family / `sys_fchownat` via the aarch64 ≥1000 private-alias band (v6.5.7). Rot gates: `scripts/agnos-crossbuild-gate.sh`, plus `tests/gates/platform/io_rdwr_agnos.sh` (v6.5.1) and `tests/gates/platform/folds_agnos_parity.sh` (v6.5.2 — every folded stdlib that builds for Linux must also build for agnos) in `check.sh`. Distinct from the bare-metal KERNEL target below. |
| UEFI Application | PE32+ (Subsystem 10) | **✅ Shipped** — `_TARGET_EFI_APPLICATION` emit mode (PE32+ container + Subsystem 10 + EFI-variant EEXIT + zeroed Data Dirs [1]/[12]), landed across the v5.11.47–v5.11.49 gnoboot arc. OVMF runtime smoke proven; structural gate in `programs/checks/platform_efi.cyr`. Consumer: gnoboot. **Secure Boot**: native Authenticode PE signing shipped (`cyrius sign-efi <pe> <key.der> <cert.der> <out>`, v6.4.47, dispatches to the cyrsign-efi helper) + variable enrollment (`.esl`/`.auth` — `efi_signature_list_from_cert`/`efi_auth_from_esl`/`efi_time`, v6.4.48, via folded sigil 3.11.1). |
| RISC-V (rv64) | ELF | Queued — **v6.7.x / v6.8.x** (horizon plan 2026-07-07; re-homed from v6.2.x, user 2026-06-27; hardware in-hand, deferred to keep earlier v6.x minors from taking on a 2nd platform). |
| Bare-metal | ELF (no-libc) | **✅ Partial** — six of seven design deliverables shipped: #1–#3 (target triple / no-libc ELF / `#naked`, v6.2.27–.28; QEMU boot gate + freestanding-TLS entropy .28), **#5 `[sections]` settable kernel load base + #6 inline-asm memory fences (v6.3.3)**, **#7 freestanding `lib/tls_native` kernel link + in-kernel handshake smoke (v6.3.4)**. **#4 (the forbidden-module check) is still unbuilt** — re-verified against live code 2026-08-07: a `--target=<arch>-bare-metal-elf` build sets `CYRIUS_KERNEL` but does not restrict which `lib/*.cyr` an `include` may pull, so a kernel build that pulls a host-OS-only module compiles silently and faults at runtime. P3, no consumer blocked; issue archived into the roadmap backlog. AGNOS kernel target (not the userspace target above). |

## Verification hosts (cross-arch SSH-wired)

Per the cross-arch propagation rule (CLAUDE.md, memory pin
`feedback_cross_arch_propagation_mandatory`), every compiler-side
fix gets cross-tested in the same slot. All four are step 4 of
`scripts/release-gate.sh` (`for H in ecb ach cass pi`, real hardware,
sequential) — a gate on **every** `.NN`, not just at closeout. At
**v6.6.1** all four report `SELFHOST_OK` + `LIBTEST_OK` (crossos **68/68** each, on real
hardware — the subset grew 54 → 68 since `.34`; DERIVE it with
`find tests/tcyr/crossos -name '*.tcyr' | wc -l`). ⚠ **That is the `crossos/` subset, not the full corpus** — the
282-of-282 numbers in the table above are the 2026-08-20 full-corpus measurement and were
NOT re-derived at `.34`. Quote them as a v6.5.33 figure, not a current one.

| Host | Arch / OS | Role |
|------|-----------|------|
| `pi` | aarch64 Linux (Pi 4) | Native aarch64 self-host + multi-thread / mutex shakedown. |
| `cass` | Windows x86_64 | PE/COFF broad-scope on real Win11. |
| `ecb` | macOS Apple Silicon | Mach-O native verification (broad-scope). |
| `ach` | macOS Intel x86_64 | x86_64 Mach-O self-host — first-class release-gate host since v6.4.59. |

⚠ **`LIBTEST_OK` is a subset by default.** The gate runs the `tests/tcyr/crossos/` directory
(it was the `vr01_` filename glob until v6.5.11) and, since v6.5.8, prints its own numerator/denominator
rather than a bare OK — because a gate covering 13 % of the corpus used to
read as authoritative. `CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh
<host>` runs the whole corpus (~75 s on `ecb`, affordable since v6.5.8 batched
the per-test SSH connections into one).

> "NO EXCUSE THAT SHIT [is] BEING FOUND BY PORTS" — user
> 2026-05-04. SSH-wired hosts mean cross-test is mechanical, not
> aspirational.

## cyrius-x guest contract (cxvm)

*Stated at 6.6.10 (the roadmap's "cxvm guest-address bounds" item), revised at 6.6.12 when cxvm
gained its memory and stack traps; the matching statement is in `programs/cxvm.cyr`'s header.*

**cxvm is an interpreter for TRUSTED bytecode. It is not a sandbox: a guest can ask the host
kernel for anything the cxvm process may do.** What it does and does not guarantee, as of 6.6.12:

- **The VM keeps a guest inside its own memory (6.6.12, CVE-58).** Every load and store
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
      [roadmap.md](development/roadmap.md) — no version-skew.
- [ ] Re-verify SSH-wired hosts by running `cyrius audit --internal=platform-check`
      (v6.2.12: plain `cyrius audit` is now the local item suite only; the cross-OS
      self-host across ach/ecb/pi/cass moved behind `--internal=platform-check`) via
      `scripts/cross-os-selfhost.sh`).
