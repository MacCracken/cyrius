# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.
>
> **Consolidated 2026-06-08 (v6.1.4):** the per-patch session-close log
> (104 entries, ~5,600 lines back to v5.x) + the stale v6.0.4-frozen
> structured sections were pruned — that detail is canonical in
> [`CHANGELOG.md`](../../CHANGELOG.md) (per-patch) and
> [`completed-phases.md`](completed-phases.md) (arc retrospective). This file
> now holds only the **active cycle** + current state.

## Current state

| | |
|---|---|
| **Version** | **6.1.8** (v6.1.x cycle — Backend Codegen Multi-Arc; see [roadmap.md](roadmap.md)) |
| **cycc** (x86_64 ELF) | 933,000 B (unchanged @ 6.1.8 — aarch64-only slot) |
| **cycc_aarch64** (x86-host cross, emits aarch64) | 593,376 B |
| **cycc-native-aarch64** (aarch64-native, tracked) | 787,248 B (refreshed @ 6.1.8 — PIE-enabled) |
| **cycc_win** (PE32+ cross) | 805,376 B |
| **cc5** (prior-major v5.11.69, tracked) | 874,232 B |
| **cybs** (bootstrap compiler) | 12,344 B |
| **seed** (`bootstrap/asm`, root of trust) | 29,016 B |
| check.sh gates | 86/86 |
| tests | 169 `.tcyr` · 15 `.bcyr` |
| stdlib | 90 `lib/*.cyr` (81 stdlib + 9 vendored deps) · 79 programs |
| bench (every-release gate) | self_compile ~452 ms |

> **Handoff (2026-06-08, pre-reboot for kernel testing):** v6.1.8 is **committed**
> (clean tree; HEAD = "aarch64 PIE — the PIE arc is now complete on both arches");
> confirm it's tagged/pushed if not already. All gates green at the cut (x86 +
> aarch64 self-host byte-identical, pi/ecb/cass cross-OS, check.sh 86/86, bench).
> **PIE arc is COMPLETE on both arches** (x86 v6.1.6, aarch64 v6.1.8).
>
> **Kernel-PIE boot-test readiness** (the v6.1.7 wrapper — relevant to the kernel
> testing): build an x86 PIE kernel with `cat <kernel.cyr with 'kernel;'> |
> CYRIUS_PIE=1 build/cycc > k.elf` → **ET_DYN, p_vaddr=0, e_entry=0xA8**, RIP-
> relative `.text`. The boot shim (AGNOS gnoboot) must handle ET_DYN: pick a base,
> slide the single PT_LOAD, jump to `base + 0xA8`. This **gnoboot-boot validation
> was the one piece left unverified** at v6.1.7 (no AGNOS `--pie` harness yet) — if
> this reboot is that test, that's the gap it closes. aarch64 kernel-PIE is still a
> follow-on (this slot did aarch64 *userland* PIE). Verification hosts pi/ecb/cass
> are remote → unaffected by a local reboot.

## v6.1.x — active cycle (Backend Codegen Multi-Arc)

Phase plan + slot detail: [roadmap.md](roadmap.md). Whole-v6.x cycle:
[roadmap_6.md](roadmap_6.md).

**Shipped (all 2026-06-08):**
- **v6.1.0** — clean cycle cut: roadmap split into 3 tiers (roadmap.md active /
  roadmap_6.md cycle / roadmap-future.md beyond) + full docs sweep + `build/`
  prior-major slot corrected `cc3 → cc5` + **benchmark-every-release gate**
  (CLAUDE.md Release rule #6).
- **v6.1.1** — Phase A: back-compat symlink drop (install `cc5`/`cyrc`
  symlinks + `cbt/core.cyr` cc5 fallback + repl shim). cycc untouched.
- **v6.1.2** — Phase A: aarch64 `EADDRA_IMM` >4095 fix (12-bit-mask → low+hi
  adds + movz/movk guard). Latent pre-existing; verified on pi + ecb.
- **v6.1.3** — Phase A: POSIX `*at()` family + bare-name peers (`sys_link`/
  `lstat`/`rename`) — **and the aarch64 ESYSXLAT collision fix it forced**:
  native `newfstatat`(79)/`utimensat`(88) collided with x86 `getcwd`/`symlink`
  → stdlib emits x86 262/280, ESYSXLAT renumbers. **Repaired `sys_stat`
  silently broken on native aarch64 since v6.0.41** (found-by-ports).
- **v6.1.4** — Phase B: hoist `_TARGET_*` + `_emit_fmt` to
  `src/backend/common/runtime.cyr` (logic-preserving). `_entry_base` stays
  per-arch (premise-check: arch-specific VAs, not a dup).
- **v6.1.5** — Phase B (final): DCE mark-and-sweep probe consolidation —
  `_dce_hash_lookup` + `_dce_host_fn` hoisted to `common/runtime.cyr`, collapsing
  4 hash-probe blocks → 1 and 4 host-fn scans → 1 across the two `fixup.cyr`
  backends. Logic-preserving (−51 LOC, cycc −752 B). Verified byte-identical via
  338-input old-vs-new corpus + DCE-torture (report + `CYRIUS_DCE=1` NOP-fill,
  both arches) + a 4-reviewer adversarial workflow + pi/ecb/cass self-host.
- **v6.1.6** — Phase C (PIE): `--pie` / `CYRIUS_PIE=1` position-independent codegen
  x86_64. Ships **working userland PIE executables** (ET_DYN, RIP-relative) —
  validated by running the full 169-test `.tcyr` corpus as ASLR'd PIE binaries +
  a new check.sh gate. **Premise correction**: PIE was ~80% pre-built via
  `shared`/object `_IS_OBJ` (proven), so this widened the gate + fixed the one
  ungated site (`EVADDR_X1`) rather than greenfield; the fn-ptr/vtable "awkward
  case" was a non-issue. Non-PIE byte-identical (338-input differential). Kernel-PIE
  ELF (AGNOS KASLR) is a follow-on (needs the AGNOS `--pie` boot harness; no live
  pull). See CHANGELOG [6.1.6].
- **v6.1.7** — packed (user-directed): (1) **Windows COM/DXGI `.rdata` corruption
  fix** (ai-hwaccel consumer bug) — function-local arrays are `.rdata` globals and
  the m128 array padding was computed against the ELF base in `FIXUP` but the
  unpadded sum in `_pe_layout`, so `&desc` (GetDesc1's out-param) drifted +8 into
  the string region and its write smashed `"true"`. Fixed by padding against the PE
  gvar VA base in both. Diagnosed debugger-free via exit-code probes on real-GPU
  cass; GPU-confirmed (60→42). PE-only → ELF/aarch64 byte-identical. (2) **Kernel-PIE
  ELF wrapper** — `EMITELF64_KERNEL` emits ET_DYN+p_vaddr=0+`e_entry=0xA8` under
  `--pie` (the deferred v6.1.6 pickup); structurally validated, gnoboot-boot pending
  the AGNOS harness. See CHANGELOG [6.1.7].
- **v6.1.8** — Phase C (PIE, Sub-arc B): **aarch64 PIE** — `--pie`/`CYRIUS_PIE=1`
  reuses the proven Mach-O `adrp`/`add` PIC path for ELF (6 address-emit sites + 3
  fixup branches gated on `_TARGET_MACHO==2` now also fire for `_pie_mode`; ELF
  emitter → ET_DYN+p_vaddr=0; `FIXUP_ADRP_ADD` uses `_entry_base`, Mach-O
  byte-identical). **Completes the PIE arc on both arches.** Validated: full tcyr
  corpus as aarch64 PIE on **pi (real ARM)** — exit-code parity with non-PIE, zero
  PIE-only failures; 338-input non-PIE byte-identical; pi/ecb/cass self-host; x86
  cycc untouched. See CHANGELOG [6.1.8].

**Next:** **v6.1.9** — Phase C tail: `.gnu.hash` migration + drop SysV `.hash` (the
long-deferred v5.6.38 pin). Then D (TS/TSX→JS emit — active SecureYeoman pressure),
E (bayan/ganita carve). The kernel-PIE gnoboot-boot validation + aarch64 kernel-PIE
land when an AGNOS `--pie` harness exists. See roadmap.md.

**Open / filed (v6.1.x):**
- `2026-06-08-macho-arm-at-family-darwin-syscall-mappings.md` — macho-arm
  `fstatat`/`utimensat`/`linkat`/`renameat` lack Darwin ESYSXLAT mappings
  (pre-existing; `sys_stat` was already broken there; Darwin lacks `utimensat`
  → needs design). openat/mkdirat/unlinkat/fchmodat work on macОS.
- `stdlib-reference.md` covers ~33/90 lib modules (native TLS, SIMD, async,
  base64/bigint, etc. undocumented) — human-led rewrite, flagged since v6.1.0.
- x86-macho cycc self-compile (HELD, Intel EOL) — v6.1.x carry-in tail.

## Consumers

AGNOS kernel, agnostik (58 tests), agnosys (20 modules), argonaut (424
tests), sakshi, sigil (206 tests), libro (240 tests), shravan (audio),
cyrius-doom, bsp, mabda, kybernet (140 tests), hadara (329 tests),
ai-hwaccel (491 tests). All AGNOS ecosystem projects depend on the compiler
and stdlib.

## Verification hosts

- `ssh pi` — Pi 4 (Linux aarch64 native runtime)
- `ssh ecb` — Apple Silicon MBP (Mach-O arm64 runtime)
- `ssh ach` — Intel Mac (Mach-O x86_64 runtime, Apple EOL-track; self-hosts byte-identical)
- `ssh cass` — Windows 11 24H2 (PE32+ runtime)

> **Note (2026-06-08):** ecb's repo checkout is stale (main @ v6.0.1, committed
> x86 `build/cycc` — only its installed `~/.cyrius/bin/cycc` runs there). Live
> ecb self-host needs that checkout updated; cross-emitted-binary runs verify it
> meanwhile. pi has no repo checkout (the self-host gate ships source over SSH).

## Bootstrap chain

```
bootstrap/asm (29 KB committed binary — root of trust)
  → cybs (bootstrap compiler; formerly cyrc, renamed v6.0.0)
    → cycc (modular compiler + IR; formerly cc5, renamed v6.0.0)
      → cycc_aarch64 (Linux + macOS Mach-O cross-compiler)
      → cycc_win (Windows PE32+ cross-compiler)

(bridge.cyr — the old intermediate stage — was retired at v5.11.66.)
No Rust. No LLVM. No Python. Just sh + Linux x86_64.
Build: sh bootstrap/bootstrap.sh
```
