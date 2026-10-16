# x86-macOS: every `syscall()` site still inlines the whole `EMACHO_SYSXLAT` chain (~1.26 KB, 35 % of the compiler) — RESOLVED

> ✅ **RESOLVED in v6.7.12** (DW-4: x86 Mach-O now folds a literal syscall number's EMACHO_SYSXLAT chain at compile time, from the same rows. The site gets one `mov rax, imm32`, the tail's 0x200FFFF for a miss or pipe at argc 1, or nothing for EEXIT. It keeps only the fork half at 57 and the pipe half at 22 (argc >= 2), with no `push rax` / `pop r11`. A run-time number calls one shared stub per arity class (the user's decision D2, 2026-10-15: XLAT-2 in). The stub sites are patched through the disp32 registry, because x86 moves code after emitting it. The filed repro's x86-macOS compiler goes from 2,883,584 to 1,937,408 B, with 733 chain heads down to 0. The macOS x86 CLI goes from 946,176 to 733,184 B, and ELF output is byte-identical. ach passes SELFHOST_OK and crossos 292/292. A pre-classed literal >= 0x10000 (`syscall(0x2000014)`) is a run-time number to the parser's 16-bit constant fold, so it takes the stub, correctly but unfolded. Rows: `emacho_sysxlat_fold.sh` (7 axes, 7 mutations) and the run-time twins in crossos syscall_number_nonliteral, sys_pipe_every_target, darwin_short_arity_sigsys, darwin_unrouted_syscall_faults and fork_refused_stays_negative. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — re-measured 2026-10-08 against 6.7.6 @ 2fb6ad8b: the x86 Mach-O compiler
(`CYRIUS_MACHO=1 build/cycc < src/main_x86_macho.cyr`) is **2,387,968 B** and carries **668** copies of the chain
(the first row and the `_msx_tail` row each occur 668 times), **1,261 B** at the first site (a chain is 13 B longer
where the pipe row's arity rule keeps it) — **≈ 842 KB, ~35 %** of the binary. Size-only; behaviour not re-run on
hardware (a fold must be verified on ach).
**Placement:** 6.7.12 — repair 2: the platform release (darwin lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D2 — XLAT-2 in.
**Discovered:** 6.6.18 (2026-10-06), left out of XLAT-1 (CHANGELOG [6.6.18] *Known / not fixed*); filed 2026-10-08
from roadmap.md.
**Severity:** Low — size only; nothing miscompiles.
**Affects:** cycc ≤ 6.7.6 (x86_64 Mach-O output; the x86-macOS compiler and every program it builds).

## Summary

6.6.18's XLAT-1 stopped aarch64 from inlining the ESYSXLAT translation chain at a site whose syscall number is a
compile-time literal (`_esx_fold`: emit the chain, decode it, simulate it with cur = N, keep only the rows that run —
−35.2 % on `build/cycc-native-aarch64`). The x86 Mach-O twin, `EMACHO_SYSXLAT`, was not given the same treatment:
`ESYSCALL` (`src/backend/x86/emit.cyr:430`) still emits `push rax` + all 92 rows (`cmp rax, lin` / `jne` /
`mov rax, 0x2000000|bsd`, 13 B each, 16 B for numbers ≥ 128; the pipe row is skipped at argc 1) + `_msx_tail`
(15 B) + `syscall` + the carry-negate + `EMACHO_PROC_FIXUP` (the fork / pipe rax:rdx fixup, ~40 B) at **every**
site, literal or not. x86 `ESCPOPS`
(`src/backend/x86/emit.cyr:809`) already receives the literal (`lit`, "the aarch64 fold's literal number; unused
here").

## Reproduction

```sh
cd /home/macro/Repos/cyrius
CYRIUS_MACHO=1 ./build/cycc < src/main_x86_macho.cyr > /tmp/mx      # the x86-macOS compiler
ls -l /tmp/mx                                                        # 2,387,968 B
# first row: cmp rax,0 / jne +7 / mov rax,0x2000003     tail: cmp rax,0x1000000 / jae +7 / mov rax,0x200FFFF
LC_ALL=C grep -obUaP '\x48\x83\xF8\x00\x75\x07\x48\xC7\xC0\x03\x00\x00\x02' /tmp/mx | wc -l   # 668
LC_ALL=C grep -obUaP '\x48\x3D\x00\x00\x00\x01\x73\x07\x48\xC7\xC0\xFF\xFF\x00\x02' /tmp/mx | wc -l   # 668
# first head at offset 6431, first tail at 7677 → 7677 + 15 − 6431 = 1,261 B for that site's chain
```

Expected (XLAT-1's method): a literal site emits at most one `mov rax, imm32` (or the tail's 0x200FFFF for an
unrouted number). Actual: 668 chains of ~1.26 KB, ≈ 842 KB.

## Root cause

`ESYSCALL` (`src/backend/x86/emit.cyr:430-452`) calls `EMACHO_SYSXLAT(S)` (`:1142`) unconditionally under
`_TARGET_MACHO == 1`; the rows are `_msx` / `_msx32` (`:1100`, `:1113`) and `_msx_tail` (`:1135`). Nothing on the
x86 side reads `lit`.

## Proposed fix

Port XLAT-1 to the x86 Mach-O chain, keeping its guarantees:

1. When `lit >= 0`, resolve the chain at compile time **from the same rows** — `EMACHO_SYSXLAT` is a flat renumber
   list (no arg-shift bodies, unlike ESYSXLAT), so replaying it in query mode the way `_macho_x86_routes`
   (`:1371`) already does yields the classed number: emit `mov rax, imm32` (or nothing extra when the caller is
   already classed, e.g. `EEXIT`), honouring `_msx_short`'s arity rule (pipe 22 at argc 1) and `_msx_tail` for a
   miss. The row source stays untouched, so `macho_route_parity.sh` and `raw_syscall_literals_routed.sh` keep
   reading the truth.
2. With the literal known, `push rax` / `EMACHO_PROC_FIXUP` are needed only for fork 57 and pipe 22 — dropping them
   elsewhere saves ~42 B more per site (the x86 analog of XLAT-3,
   `2026-10-08-arm64-macos-literal-syscall-carries-pipe-fork-fixups.md`).
3. Optionally XLAT-2's half: a variable number calls one shared chain stub instead of inlining it.

The emitter is compiled by cybs (seed-derive), and `EMACHO_SYSXLAT` sits near cybs's per-fn reference cap (the
comment above `_msx_tail`), so the fold lives in its own fn. Gates: a literal-only x86 Mach-O probe carries zero
chain heads; the semantic twin (literal vs `var` number) must match — on **ach**, since the behaviour is Darwin's;
`tests/tcyr/crossos/` on ach for the self-host. The `CYRIUS_IR` record of `IR_SYSCALL` must keep replaying the same
bytes.
