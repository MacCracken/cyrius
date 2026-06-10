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
| **Version** | **6.1.26** (v6.1.x cycle — Backend Codegen Multi-Arc; see [roadmap.md](roadmap.md)) |
| **cycc** (x86_64 ELF) | 1,045,752 B (unchanged @ 6.1.26 — ganita is lib-only; cycc has no matrix/linalg/math dep) |
| **cycc_aarch64** (x86-host cross, emits aarch64) | 595,800 B (unchanged @ 6.1.26) |
| **cycc-native-aarch64** (aarch64-native, tracked) | 787,248 B (refreshed @ 6.1.8 — PIE-enabled) |
| **cycc_win** (PE32+ cross) | 814,592 B (unchanged @ 6.1.26) |
| **cyrius-lsp** (language server) | 531,688 B |
| **cc5** (prior-major v5.11.69, tracked) | 874,232 B |
| **cybs** (bootstrap compiler) | 12,344 B |
| **seed** (`bootstrap/asm`, root of trust) | 29,016 B |
| check.sh gates | 87/87 |
| tests | 170 `.tcyr` · 15 `.bcyr` |
| stdlib | 87 `lib/*.cyr` (bayan @.25 −7+1; ganita @.26 −2+1, math split) · 79 programs |
| bench (every-release gate) | self_compile ~510 ms (box noise) |

> **Handoff (2026-06-10):** v6.1.26 ready for cut — **ganita distfile carve**
> (Phase E, second half — CLOSES the stdlib data/math carve). matrix (14) +
> linalg (26, `mat_*` decomposition/solver suite) carved whole; the **13 advanced
> math fns** (transcendental + fibonacci/binomial) SPLIT out of `lib/math.cyr` →
> the **ganita** sibling (ganita 1.0.0), all prefixed `ganita_*` (rename-only),
> folded byte-identical into `lib/ganita.cyr` (1,358 lines; `lib/{matrix,linalg}.cyr`
> deleted; `lib/math.cyr` trimmed to primitives — F64 constants + basic ops +
> gcd/lcm + f64_parse + the `_f64_*_polyfill` builtin-fallbacks). **0 git deps
> preserved.** Back-compat aliases (53). ~9 test consumers migrated to `ganita_*`.
> **cycc UNCHANGED** — no compiler dep on matrix/linalg/advanced-math (self-hosts
> byte-identical, no #derive-style change). **No ripple:** none of matrix/linalg/
> math were auto-prepended; `gcd` (sigil's only math dep) STAYS in stdlib.
> `version-bump.sh 6.1.26` to apply; **user pushes/tags after CI**. Gates: cycc
> self-host **byte-identical (unchanged)**, fold byte-identical, check.sh **87/87**,
> all 170 tcyr exit-0, api-surface regenerated (+ganita), ecb/cass `SELFHOST_OK`,
> bench self_compile 510 ms, ganita smoke exit-42 + tests 11/11. Deterministic
> verify: rename-only confirmed (0 diff lines), no orphaned ud2 callers.
> **Downstream (aliases bridge; migrate on re-pin):** code using `mat_*` /
> transcendental `f64_*` / `fibonacci`/`binomial` swaps `lib/matrix.cyr`/
> `lib/linalg.cyr` includes → `lib/ganita.cyr` (keep `lib/math.cyr` for polyfills +
> constants). Phase E (bayan .25 + ganita .26) DONE — stdlib is primitives-only.
> **NOT fixed (separate, still OPEN):** sandhi's own Darwin non-blocking-connect
> constants (`issues/2026-06-06-sandhi-nonblocking-connect-not-darwin-ported.md`) —
> needs an upstream sandhi fix + re-fold.
> **Deferred polish:** relocate the 64 KB `_ts_cst` scratch to the ts_base heap.
>
> **Kernel-PIE boot-test readiness** (the v6.1.7 wrapper — still pending an AGNOS
> `--pie` harness): build an x86 PIE kernel with `cat <kernel.cyr with 'kernel;'> |
> CYRIUS_PIE=1 build/cycc > k.elf` → **ET_DYN, p_vaddr=0, e_entry=0xA8**, RIP-
> relative `.text`. The boot shim (AGNOS gnoboot) must handle ET_DYN: pick a base,
> slide the single PT_LOAD, jump to `base + 0xA8`. gnoboot-boot validation +
> aarch64 kernel-PIE remain the consumer-gated follow-ons.

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
- **v6.1.9** — Phase C tail (Sub-arc C): **`.gnu.hash` migration** — `EMITELF_SHARED`
  (x86 `fixup.cyr`) emits a single-bucket `.gnu.hash` + `DT_GNU_HASH` instead of
  SysV `.hash`/`DT_HASH`. The native loader (`lib/dynlib.cyr`) was **already**
  gnu-hash-only — it never read `DT_HASH`, so cyrius `.so`s were resolving via the
  linear `.dynsym` fallback over a dead SysV table; this flips them onto the O(1)
  Bloom path. x86-only (aarch64 has no `.so` path). cycc byte-identical self-host;
  dlopen gate resolves *through* gnu.hash (exit 99); cass/pi/ecb cross-OS green.
  The v5.6.38 pin, closed. See CHANGELOG [6.1.9].
- **v6.1.10** — Phase D **prereq** (mini-arc): **TS children-list allocator fix**.
  Premise-check found the TS parser builds a CORRUPT AST for every nested list
  (`TS_AST_CHILDREN_RESERVE` didn't advance the pool cursor → sibling lists
  overlapped); `--parse-ts` passed only because nothing read lists back. Fixed via
  deferred construction (`TS_CST_PUSH`/`FLUSH`) across all value builders + the
  `<T,>` trailing-comma generic-param parse fix. New `cycc --emit-js` walks the AST
  to a stable kind-S-expr and **self-validates** (exits non-zero on overlap —
  proven to catch a re-broken allocator); check.sh gate 87. TS frontend is
  x86-Linux-only. cycc +79 KB / self_compile +61 ms (new module; documented
  growth-tax). x86 self-host byte-identical; cass/pi/ecb green. See CHANGELOG [6.1.10].
- **v6.1.11** — Phase D proper: **TS/TSX → JS emitter** (`cycc --emit-js` emits real
  browser JS). AST-driven (`src/backend/js/emit.cyr`): type-strips interfaces/
  aliases/annotations/`as`/`!`/generics/`?`; lowers JSX → `h(tag, props, ...kids)`
  (pragma configurable via `CYRIUS_JSX_PRAGMA`, default `h`, + a standalone `h`
  runtime prelude); ESM passthrough with type-only export pruning; verbatim
  string/template literals. The consumer's **app.tsx emits valid runnable JS**
  (node --check + `--parse-ts` round-trip + stub-DOM run all pass). `_ts_walk_gate`
  upgraded to emit→round-trip. x86-Linux-only; cycc +24.7 KB. Closes the SY
  `yeo-cy-test` ask. **Phase D mini-arc COMPLETE.** See CHANGELOG [6.1.11].
- **v6.1.12** — agnos `getenv` HIGH-sev fix + Phase D edges. (1) `lib/io.cyr`
  `getenv()` guards its 8 KB `/proc/self/environ` reader behind
  `#ifndef CYRIUS_TARGET_AGNOS` — the buffer was compiled past the agnos early
  return (agnoshi #PF). **Verified it's `.bss` static, not a stack frame** as the
  issue assumed (agnos `.bss` −8,208 B, `.text` −928 B). (2) `cyrius build
  --target=js` CLI wrapper over `cycc --emit-js`. (3) Indented JS output (AST-
  driven structural newlines). (4) **Fixed a pre-existing bug: every for /
  for-of / for-in header emitted invalid JS** (`;;` / `; of ` / `; in ` — the
  loop binding kept its statement `;`); shipped silent in 6.1.10/.11 (consumer
  had no loops); `_ts_walk_gate` now scans for it + fixture coverage. See
  CHANGELOG [6.1.12].
- **v6.1.13** — agnos `fnptr` HIGH-sev fix (agnoshi): `lib/fnptr.cyr` `fncall0..8`
  had no `CYRIUS_TARGET_AGNOS` asm branch → indirect calls returned 0 → null
  allocator vtable #PF. Added the agnos+x86 SysV branch in-place. cycc flat
  (stdlib-only); ecb/cass green. See CHANGELOG [6.1.13].
- **v6.1.14** — agnos `argc()`/`argv()` HIGH-sev fix (bannermanor): the init-rsp
  capture sat in the entry epilogue (after `PARSE_PROG`) and recorded a stale
  pointer; moved before `PARSE_PROG`. cycc flat (`_TARGET_AGNOS`-gated); ecb/cass
  green. See CHANGELOG [6.1.14].
- **v6.1.15** — TS/TSX→JS `async`-on-wrong-node fix (yeo-cy-test): the single
  pending-async slot was stolen by the first nested arrow → bare `await`; added
  `TS_PS_TAKE_ASYNC` capture-at-entry/apply-after-push. cycc +512 B; ecb/cass green.
  See CHANGELOG [6.1.15].
- **v6.1.16** — Windows-correctness pack (3 items): `cycc_win` missing from the
  x86_64 release tarball since v6.0.50 (`release.yml` fix); PE `syscall(<var>,…)`
  silent miscompile → `EPE_SYSCALL_DYNAMIC` runtime dispatch; `lib/sync.cyr`
  portable mutex (futex/SRWLOCK/spinlock). cycc +2,552 B; ecb+cass `SELFHOST_OK`.
  See CHANGELOG [6.1.16].
- **v6.1.17** — sakshi 2.2.8 fold + PE `nanosleep(35)` routing (`ENANOSLEEP_PE`,
  completing the 6.1.16 PE dispatch) + **unblocked the PE release tarball** (6.1.16
  made an unroutable-arity var-syscall a hard error → arity-5 getdents64 broke the
  wrapper build; softened to -38+warning). cycc +1,736 B; ecb+cass green;
  `nanosleep_pe` + `var_syscall_arity_pe` → exit 42 on real Windows;
  `build-windows-tarball.sh` succeeds. See CHANGELOG [6.1.17].
- **v6.1.18** — Windows directory-listing port (`dir_list`/`is_dir`/`dir_walk` now
  work on Windows via FindFirstFileW/FindNextFileW/FindClose/GetFileAttributesW —
  `lib/fs_win.cyr` + four `0xF016-0xF019` reroutes) + **sakshi 2.2.10 fold** (2.2.9
  timespec fix + 2.2.10 busy-spin drop). cycc +2,248 B; ecb+cass green;
  `tests/win/dir_list_pe.cyr` → exit 42 on real Windows. See CHANGELOG [6.1.18].

**Next:** **Phase E** — bayan distfile carve (v6.1.19) then ganita (v6.1.20); see
[[project_bayan_ganita_carve_arc]]. The kernel-PIE gnoboot-boot validation +
aarch64 kernel-PIE land when an AGNOS `--pie` harness exists.

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
