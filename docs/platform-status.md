# Platform Status

Current platform coverage for the Cyrius toolchain. **Refresh
target**: every closeout pass (CLAUDE.md step 11). The roadmap's
[Platform Targets](development/roadmap.md#v5x--platform-targets)
section tracks the per-release add history; this file is the
"what works now" snapshot.

| Platform | Format | Status |
|----------|--------|--------|
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cycc ~1.04 MB (1,091,000 B at v6.4.48; x86 packed-SIMD/AVX2 emitters in float.cyr; SIMD Phase 5 complete on all four backends — x86 SSE/AVX2, aarch64 NEON, Win64 PE, cx); 3-step bootstrap byte-identical. |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross-build byte-identity + native self-host on Pi 4 (repaired v5.6.32). Three libs (`lib/hashmap_fast`, `lib/u128`, `lib/mabda`) still contain ungated x86 asm — arch-gating queued. |
| cyrius-x bytecode | .cyx | **✅ Narrow + Broad** — clean CYX bytecode; portable-target arc complete (v6.4.20): a `.cyx` doing I/O runs on all 4 hosts. Full SIMD codegen (per-lane emitters for every flat-array verb, `_CX_VLOOP_BIN`, cxvm opcodes through 0x68, v6.4.32). |
| macOS x86_64 | Mach-O | **⏸️ Parity-track** (Apple Intel EOL) — cycc DOES self-host byte-identical on real Intel hardware (`ach`), verified every slot via `cross-os-selfhost.sh ach`. Kept parity-only; arm64 (`ecb`) is the primary/promised macOS target. |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — cycc self-hosts byte-identical on real hardware (`ecb`), proven v6.0.45 (the `READFILE`/`openat` cross-OS gate). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — substantially complete (v6.1.16–v6.1.18): process creation, threading, TLS-via-args, env read, file I/O, and **directory enumeration** (`dir_list`/`is_dir`/`dir_walk` via `lib/fs_win.cyr` + FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW, v6.1.18). `EPE_SYSCALL_DYNAMIC` var-syscall dispatch + portable mutex (SRWLOCK) + `cycc_win` shipping in the release tarball (v6.1.16); `nanosleep(35)`→`Sleep` (v6.1.17). Win64 ABI complete (v5.5.36); .reloc + 32-bit ASLR (v5.5.35); HIGH_ENTROPY_VA (v5.6.31); gate fixture v5.6.36. Verified every slot on real `cass` via `cross-os-selfhost.sh`. |
| Compiler optimization (O1–O6) | — | **✅ Closed** (v5.6.5 + v5.6.7–v5.6.27). |
| AGNOS userspace | ELF (ring-3, agnos ABI) | **✅ Shipped** — `CYRIUS_TARGET_AGNOS` ring-3 target (.48–.49; boot-to-prompt .55–.56). `getenv`/envp (.87) verified on the real agnos 1.43.2 kernel under QEMU. Cross-build rot gate: `scripts/agnos-crossbuild-gate.sh`. Distinct from the bare-metal KERNEL target below. |
| UEFI Application | PE32+ (Subsystem 10) | **✅ Shipped** — `_TARGET_EFI_APPLICATION` emit mode (PE32+ container + Subsystem 10 + EFI-variant EEXIT + zeroed Data Dirs [1]/[12]), landed across the v5.11.47–v5.11.49 gnoboot arc. OVMF runtime smoke proven; structural gate in `programs/checks/platform_efi.cyr`. Consumer: gnoboot. **Secure Boot**: native Authenticode PE signing shipped (`cyrius sign-efi <pe> <key.der> <cert.der> <out>`, v6.4.47, dispatches to the cyrsign-efi helper) + variable enrollment (`.esl`/`.auth` — `efi_signature_list_from_cert`/`efi_auth_from_esl`/`efi_time`, v6.4.48, via folded sigil 3.11.1). |
| RISC-V (rv64) | ELF | Queued — **v6.7.x / v6.8.x** (horizon plan 2026-07-07; re-homed from v6.2.x, user 2026-06-27; hardware in-hand, deferred to keep earlier v6.x minors from taking on a 2nd platform). |
| Bare-metal | ELF (no-libc) | **✅ Partial** — design deliverables #1–#3 shipped (target triple / no-libc ELF / `#naked`, v6.2.27–.28; QEMU boot gate + freestanding-TLS entropy .28). Open #5 `[sections]` / #6 inline-asm primitives / #7 freestanding-TLS link **pinned to v6.3.x** (user 2026-06-27). AGNOS kernel target (not the userspace target above). |

## Verification hosts (cross-arch SSH-wired)

Per the cross-arch propagation rule (CLAUDE.md, memory pin
`feedback_cross_arch_propagation_mandatory`), every compiler-side
fix gets cross-tested in the same slot:

| Host | Arch / OS | Role |
|------|-----------|------|
| `pi` | aarch64 Linux (Pi 4) | Native aarch64 self-host + multi-thread / mutex shakedown. |
| `cass` | Windows x86_64 | PE/COFF broad-scope on real Win11. |
| `ecb` | macOS Apple Silicon | Mach-O native verification (broad-scope). |

> "NO EXCUSE THAT SHIT [is] BEING FOUND BY PORTS" — user
> 2026-05-04. SSH-wired hosts mean cross-test is mechanical, not
> aspirational.

## Closeout audit checklist

Run during CLAUDE.md step 11 (vidya / docs sync) at every minor:

- [ ] Update compiler size for primary host (Linux x86_64) row.
- [ ] Verify each "✅ Narrow + Broad" row still holds against
      its CI lane.
- [ ] Move any "Queued" platform that landed mid-minor to a ✅
      row with the landing version.
- [ ] Cross-check pinned future targets against
      [roadmap.md](development/roadmap.md) — no version-skew.
- [ ] Re-verify SSH-wired hosts by running `cyrius audit --internal=platform-check`
      (v6.2.12: plain `cyrius audit` is now the local item suite only; the cross-OS
      self-host across ach/ecb/pi/cass moved behind `--internal=platform-check`) via
      `scripts/cross-os-selfhost.sh`).
