# Platform Status

Current platform coverage for the Cyrius toolchain. **Refresh
target**: every closeout pass (CLAUDE.md step 11).
[`CHANGELOG.md`](../CHANGELOG.md) is the per-release add history and
[`roadmap.md`](development/roadmap.md) holds the pinned future targets;
this file is the "what works now" snapshot.

> **Last verified against live code: 2026-08-20, at v6.5.33.** Every ✅
> below was re-checked that day — sizes re-measured, open platform gaps
> re-read from the issue queue, not from this file's prior claims.
> (The prior text named three libs as carrying ungated x86 asm; one of
> them no longer exists and the other two were clean. Re-derive, don't
> inherit.)

| Platform | Format | Status |
|----------|--------|--------|
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cycc ~1.13 MB (1,182,928 B at v6.5.33; x86 packed-SIMD/AVX2 emitters in float.cyr; SIMD Phase 5 complete on all four backends — x86 SSE/AVX2, aarch64 NEON, Win64 PE, cx); 3-step bootstrap byte-identical; **W^X** by default since v6.3.12 (text `R E` / data `RW ` `PT_LOAD` split, `CYRIUS_WX=0` opts out). |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross-build byte-identity + native self-host on Pi 4 (repaired v5.6.32), re-verified every release on real `pi`. Open arch-gating gap: **`lib/net.cyr` declares seven socket syscall numbers as unguarded x86_64 values** with zero `CYRIUS_ARCH` conditionals, working only because `ESYSXLAT` remaps them (`docs/development/issues/2026-07-30-net-cyr-x86-only-socket-syscall-numbers.md`). *(This row previously named `lib/hashmap_fast`, `lib/u128` and `lib/mabda` as carrying ungated x86 asm — verified stale 2026-08-07: `lib/u128.cyr` does not exist, `lib/mabda.cyr` contains no `asm` block, and `lib/hashmap_fast.cyr`'s one block is `#ifdef CYRIUS_ARCH_X86`-gated with a portable `#ifndef` arm.)*  ⭐ Full-corpus run on real hardware, **re-measured 2026-08-20 at v6.5.33: 282 pass / 0 fail of 282** — clean. (Was 255/5 of 260 at v6.5.10; the 5 were a portable core that also failed on macOS, and they are gone.)|
| cyrius-x bytecode | .cyx | **✅ Narrow + Broad** — clean CYX bytecode; portable-target arc complete (v6.4.20): a `.cyx` doing I/O runs on all 4 hosts. Full SIMD codegen (per-lane emitters for every flat-array verb, `_CX_VLOOP_BIN`, cxvm opcodes through 0x68, v6.4.32) + 64-bit immediates (opcode 253 `movhk`, v6.4.58). ⚠ **No indirect call**: `callptr` is a hard compile error on cx and `fncall*` silently returns 0, so every fn-pointer stdlib path (allocator vtables, callbacks, `vec_sort_by`) is dead there — `docs/development/issues/2026-07-30-cx-backend-has-no-indirect-call.md`, open. |
| macOS x86_64 | Mach-O | **✅ Gated self-host** — the full toolchain (wrapper + `cycc`) works on real Intel hardware (`ach`) and self-hosts byte-identical; **`ach` became a first-class release-gate host at v6.4.59** (Intel-Mac x86_64 Mach-O revival — wrapper arch/env, cycc `_read_env` un-stub, `_lint_macho_buf` structural lint, x86 release tarball), verified every slot via `cross-os-selfhost.sh ach`. Apple Intel is EOL upstream, so arm64 (`ecb`) remains the primary/promised macOS target — but x86 is no longer parity-only; it is release-gated. ⭐ Full-corpus run on real hardware, **re-measured 2026-08-20 at v6.5.33: 282 pass / 0 fail of 282** — clean. (Was 233/27 of 260 at v6.5.10) — **4 more than `ecb`**, and the extras are a *timing/clock* cluster the arm64 Mac does not have (`bench_elapsed`, `chrono`, `clock_monotonic`, `fsync`, plus `sakshi_full`, `tls_native_realpeer`, `tls_native_scaffold`). Invisible while only `ecb` was measured. |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real hardware (`ecb`), proven v6.0.45 (the `READFILE`/`openat` cross-OS gate), re-verified every release. ⚠ **No threading backend**: there is no `thread_macos.cyr` and no `bsdthread_*`/`__ulock_*` call anywhere in `lib/`, so `thread_create` does not run the worker — VR-01-guarded, pinned to v6.5.x (`docs/development/issues/2026-07-03-macos-threading-workers-dont-run.md`, open). ⭐ Full-corpus run on real hardware, **re-measured 2026-08-20 at v6.5.33: 282 pass / 0 fail of 282** on `ecb` — clean. (Was 237/23 of 260 at v6.5.10.) ⭐ Cross-referencing the other hosts splits that number: **5** of the 23 also fail on `pi` (Linux aarch64) and are a **portable** core — `include_quote_comment`, `large_input`, `large_source`, `preprocessor_past_cap`, `unicode_normconf`, three of which are the same capacity tests that fail to COMPILE under `CYRIUS_IR=3`. The other **18 are macOS-specific**, most downstream of the threading issue above. Nothing regressed — this was previously-unmeasured territory (`docs/development/issues/2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md`, open). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — substantially complete (v6.1.16–v6.1.18): process creation, threading, TLS-via-args, env read, file I/O, and **directory enumeration** (`dir_list`/`is_dir`/`dir_walk` via `lib/fs_win.cyr` + FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW, v6.1.18). `EPE_SYSCALL_DYNAMIC` var-syscall dispatch + portable mutex (SRWLOCK) + `cycc_win` shipping in the release tarball (v6.1.16); `nanosleep(35)`→`Sleep` (v6.1.17). .reloc + 32-bit ASLR (v5.5.35); HIGH_ENTROPY_VA (v5.6.31); gate fixture v5.6.36. **Win64 ABI was declared complete at v5.5.36 and was not** — `ECALLPOPS`' PE branch shuttled stack args through a fixed 5-register table with no path past `nextra == 5`, so calls with **10+ arguments silently corrupted argument 1** for about a year (5–9 args were always fine). Fixed v6.4.64, gated by `tests/tcyr/vr01_win64_stack_args.tcyr` on real hardware; that is the completeness date to trust. Verified every slot on real `cass` via `cross-os-selfhost.sh`.  ⚠ First full-corpus run on real hardware (2026-08-07, v6.5.10): **229 pass / 31 fail of 260** — mostly the expected POSIX surface (TLS, fs/process, sockets), but a few language-level ones deserve their own look (`defer`, `slices_indexing`, `expr_in_fn_args`, `flags`). ⛔ The cass leg could not produce a number until v6.5.10 fixed two harness bugs: it was fail-fast while every other host accumulated, and it had **no per-test timeout** — one test held a single ssh for 33 minutes.|
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
v6.5.10 all four report `SELFHOST_OK` + `LIBTEST_OK`.

| Host | Arch / OS | Role |
|------|-----------|------|
| `pi` | aarch64 Linux (Pi 4) | Native aarch64 self-host + multi-thread / mutex shakedown. |
| `cass` | Windows x86_64 | PE/COFF broad-scope on real Win11. |
| `ecb` | macOS Apple Silicon | Mach-O native verification (broad-scope). |
| `ach` | macOS Intel x86_64 | x86_64 Mach-O self-host — first-class release-gate host since v6.4.59. |

⚠ **`LIBTEST_OK` is a subset by default.** The gate runs the `vr01_` glob
(36 of 260 tcyr) and, since v6.5.8, prints its own numerator/denominator
rather than a bare OK — because a gate covering 13 % of the corpus used to
read as authoritative. `CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh
<host>` runs the whole corpus (~75 s on `ecb`, affordable since v6.5.8 batched
the per-test SSH connections into one).

> "NO EXCUSE THAT SHIT [is] BEING FOUND BY PORTS" — user
> 2026-05-04. SSH-wired hosts mean cross-test is mechanical, not
> aspirational.

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
