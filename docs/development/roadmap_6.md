# Cyrius Development Roadmap — after v6.7.x

**Scope — FORWARD ONLY**: the work placed after the active minor (v6.7.x): the DCE compaction arc and the net
migration, v6.8.x/v6.9.x RISC-V rv64, and the shape of what follows v6.x. Not a record of shipped work and not a spec
for the active minor.

| You want | Go to |
|---|---|
| The **active minor** (v6.7.x) | [roadmap.md](roadmap.md) — the single authority; do not copy its spec here |
| What a **closed** minor shipped | [`CHANGELOG.md`](../../CHANGELOG.md) (source of truth) · [completed-phases.md](completed-phases.md) |
| **Unpinned / speculative** items | [roadmap-future.md](roadmap-future.md) |
| Durable process rules | [cycle-discipline.md](cycle-discipline.md) · [`CLAUDE.md`](../../CLAUDE.md) |
| Volatile current state | [state.md](state.md) |

> **PLACEMENT RULE (hard):** every technical / codegen / runtime / platform item lives in the **6.x line** or
> roadmap.md's unscheduled backlog. **Nothing codegen is EVER parked to 7.x** — 7.x is the language book plus
> legal-for-public-release, only that. This file has violated it four times (DWARF, incremental compilation, LSP /
> formatter / linter evolution, agnos alignment — each found by a sweep, not by the rule): **if you are about to write
> a capability under a 7.x heading, stop.**

## Closed minors

| Minor | Theme | Closed at |
|---|---|---|
| v6.0.x | Language cleanup + stdlib + native TLS | **v6.0.91** |
| v6.1.x | Backend codegen multi-arc | **v6.1.41** |
| v6.2.x | Platform expansion (bare-metal + dependency model) | **v6.2.52** |
| v6.3.x | Language refinements | **v6.3.45** |
| v6.4.x | Staging minor → long reactive minor | **v6.4.86** (closeout cut at .85; .86 the post-closeout sandhi fold) |
| v6.5.x | Perf / quality: IR substrate, regalloc, SIMD register residency, `: stack` enums | **v6.5.73** (no `.74` — cut in error and re-cut as v6.6.0) |
| v6.6.x | Value-form `Result`, then repair; the tooling tail (manifest, distlib, `[embed]`) | **v6.6.20** (the closeout, 2026-10-07) |
| v6.7.x | **ACTIVE** — the language minor; see [roadmap.md](roadmap.md) | — (opened v6.7.0, 2026-10-07) |

Close numbers are the per-minor max `## [6.Y.N]` heading of the CHANGELOG. **When v6.7.x closes:** add its close
number here, and do not copy its detail back.

**Cycle budgeting.** Large minors are the norm (v6.0.x ran to .91, v6.4.x to .86, v6.5.x to .73): read any slot budget
as a planning aid, never a cap (user, 2026-06-10: "no worries about patch size, just hardening and adding features").

---

## Between v6.7.x and RISC-V — the DCE compaction arc and the net migration (placed 2026-10-02)

Still 6.x. About 3–5 releases. Whether they form the tail of v6.7.x or the head of the RISC-V minor is decided at the
v6.7.x close.

### The DCE compaction arc

Order: **aarch64 first** (its own repair model, which rv64 reuses; cheaper after 6.6.18's ESYSXLAT fold), then PE /
x86 Mach-O (no consumer today). Every target is correct today — the unsupported ones only skip the shrink, and since
6.6.18 each names itself and its reason in the "compaction declined: <why>" note (static x86 ELF past the 4,096-run
repair-registry cap says so too).

- ⚠ **aarch64 compaction must repair the resolved `bl <ESYSXLAT stub>` sites** (6.6.18 XLAT-2): a variable syscall
  number calls a shared per-class stub through a `bl` with no fixup-table entry and no position registry, and
  `ESYSX_STUBS`'s site list is drained before FIXUP — a code-moving pass must find them itself. `wp_compact` returns 0
  for EVERY aarch64 target today (`src/common/ir.cyr`), so arm64 Mach-O and aarch64 ELF never compact.
- **PE and x86 Mach-O decline** (since v6.6.1) because both reach a live import / stub table through a rip-relative
  disp32 the compaction pass does not repair, and both compute file geometry before elimination runs. Declining was the
  right release fix (they emitted binaries that faulted before `main`), but it leaves them on NOP-fill. ELF still
  eliminates for real (123,048 → 16,552 B, −86.5 %). **The repair is two things that land together:** (1) repair the
  rip-relative shape in `wp_compact` — every `disp32` whose target did not move by the same delta is re-patched; the
  same repair unblocks `_pie_mode` compaction, so never build a PE-only version; (2) re-run `_pe_layout(S)` after
  compaction (and the Mach-O equivalent) so section geometry, RVAs and `PointerToRawData` describe the emitted code —
  with the ftype=4 IAT-reference fixups patched AFTER that re-layout, since their displacement is computed from
  `_pe_idata_rva`. ⚠ Order matters: fixing geometry without displacements, or the reverse, gives a binary that looks
  fine and faults later — the shape that cost three attempts at v6.5.72.
- **The WPNR 4,096-run merge** — merge a dead run into the previous one when `cp == prev_cp + prev_len` — lifts static
  x86 ELF's compaction cliff at 4,097 dead fns; then `dce_data_vaddr_frozen.sh` becomes a behavioural gate (≤ 4,096
  dead fns of ≳ 520 B cross a 2 MB bucket).
- **Acceptance**: `tests/gates/codegen/dce_pe_macho_layout_declines_compaction.sh` is **inverted** — axes 1-2 assert
  PE and Mach-O shrink *and still run* (verified by RUNNING on cass and ach — the defect class is "smaller and
  broken"); axis 3 (ELF still eliminates) is unchanged. Re-grep the decline / `_pe_layout` / IAT-disp32 sites in
  `src/backend/x86/fixup.cyr` at the arc's open — the lines move.

### `lib/net.cyr` §4 — per-arch socket syscall peers

`lib/net.cyr` still carries bare x86 numbers (`grep -c CYRIUS_ARCH lib/net.cyr` → 0) and works on aarch64 only because
nine ESYSXLAT x86-compat rows remap them. The sharp edge is gone (the issue closed at v6.5.7 + v6.5.11, deliberately
without §4) but the work is not: that remap is load-bearing for everything that calls `net.cyr` on aarch64, so this is
a migration — written up in [ecosystem-migration.md](ecosystem-migration.md) when it ships — not a deletion.

### `lib/net.cyr` AF_UNIX

A design call, default **yes**: `net.cyr` grows a Unix-domain socket surface alongside INET.

### The syscall families still unnamed by the stdlib

`setrlimit`, `ptrace`, `sched_getaffinity`, `pread64` / `pwrite64` — what remains of the surface v6.6.5 measured and
deliberately did not ship (per-family reasons in
[`issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md`](issues/archived/2026-09-17-thoth-memfd-ftruncate-sendmsg-unnamed-pass-through-on-aarch64.md)).
⛔ They are in the silent class: `_SYSX_MEANT` carries only numbers named in BOTH peers, so a NAMELESS number warns
nothing (raw 160 on the aarch64 fork is silent). Already shipped and no longer listed: Tier 1 at 6.6.8 (`unshare`,
`chroot`, `capget` / `capset`, `process_vm_readv` / `writev`, `pivot_root`) and `getrlimit` at 6.6.12.
- **`setrlimit` has no arg-shift blocker**: aarch64 has `setrlimit` **164** natively, as it has `getrlimit` 163 (measured
  under qemu at 6.6.16). It takes the getrlimit shape: a native declaration in the aarch64 peer, no ESYSXLAT row.
- **What is left is the warning interplay, not number collisions.** The aarch64 peer declares the NATIVE numbers —
  **117** ptrace, **123** sched_getaffinity, **67** / **68** pread64 / pwrite64, **164** setrlimit — which are neither
  sources nor products of the ELF-arm chain. `programs/gen_syscall_xlat.cyr`'s `is_native_a64` can only drop a warning
  row that EXISTS, and only **117** has one (x86 `setresuid`): declaring `ptrace` natively silences that live warning;
  123 / 67 / 68 / 164 have no row and warn nothing either way. So the one decision is `ptrace`'s: accept losing the
  setresuid-117 warning, or give `ptrace` a ≥ 1000 alias (as the 6.6.12 xattr band did). Re-check with
  `programs/gen_syscall_xlat.cyr` when the slot opens.
- **Acceptance**: every family named in `lib/syscalls_linux_common.cyr` (or the peer that owns it) with a Darwin arm, a
  row whose placement `esysxlat_row_order.sh` passes, and a runtime assertion in `tests/tcyr/crossos/` that fails when
  the number is wrong.

---

## v6.8.x or v6.9.x — Platform: RISC-V rv64

**Re-homed 2026-10-01 (user)** behind the v6.7.x language minor — the third deferral of the same shape (v6.2.x → v6.6.x
→ v6.7/6.8 → v6.8/6.9), each a deferral of worry, not intent. Whether it takes 6.8 or 6.9 is decided at the v6.7.x
close. **The hardware is in hand** (user, 2026-06-10), so the real-hardware self-host gate is live from the start —
wire the rv64 box into the SSH verification fleet beside pi / ecb / ach / cass at the arc's open.

The 4th platform peer after x86_64 / aarch64 / PE-x86_64. Substrate already landed: the typed-SIMD ABI, the real type
system and the struct-byval ABI (v5.10.x), the parser-to-emit named-op refactor (v5.11.x), and the v6.2.0
growable-region foundation (the new backend inherits the vec-backed pattern — no fixed-cap re-duplication).

**Scope**: `src/backend/riscv64/{emit,jump,fixup}.cyr`; `lib/syscalls_riscv64_linux.cyr`; `src/main_riscv64.cyr`;
`qemu-riscv64-static` for the bring-up probes + the rv64 hardware over SSH for the self-host verify; a CI matrix arm.

**Acceptance gates**:
1. `build/cycc_riscv64` emits valid rv64 ELF that `file(1)` identifies.
2. A single-syscall "exit 42" probe runs under `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on the **real rv64 hardware** over SSH — the non-negotiable cross-OS self-host gate.
5. `[release].cross_bins` in `cyrius.cyml` gains `cycc_riscv64`.

Premise-check the rv64 substrate at the arc's entry (CLAUDE.md *Planning & slots*); only the user re-orders it.

---

## What comes after v6.x

**v6.x is not capped** (user, 2026-06-11): the cycle grows further before any major bump — v6.7.x (the language arc) →
v6.8.x/v6.9.x (RISC-V) are the current pins, and more v6.x minors can follow before v7.0.0.

v7.x scope is open; its known invariants are in [roadmap-future.md](roadmap-future.md) § *v7.0 commitments* (no binary
rename at v7.0.0; the prior-major slot rotates to the last v6.x `cycc`).

### Usability / adoption readiness

Whether v7 is a *full public* release is an open question (user, 2026-06-11: "sovereign and usage — whether its full
public is still in question"). Sovereign + usable is the committed direction, so this debt is worth paying regardless
of a launch date ([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)):

- **Licensing (LEGAL-01)** — a hard blocker *if/when* it goes public. The GPL-3.0-only stdlib is source-included into
  every consumer binary with no runtime-library exception, and `sigil.cyr` elects the GPLv2-only leg of dual BSD/GPLv2
  code (GPL-3-incompatible). Needs legal review and a linking-exception decision. (The only genuine 7.x item.)
- **Trust story — resolved**: sovereign release signing (`cyrsign` Ed25519), integrity / pinning, and seed → cycc
  derivation (`build/cycc` is machine-derivable from the 29 KB seed, byte-identical).
- **Diagnostics — the error-reporting half shipped in v6.4.x** (column + excerpt v6.4.60, multi-error recovery
  v6.4.62, the reserved-word diagnostic naming the token v6.4.77).
- **Debug-info (DWARF) — still absent**, and crash localization is x86-ELF-only. 6.x-line codegen work: it is a
  roadmap-future.md row, not a v7 item.
- **stdlib-reference coverage** — `docs/stdlib-reference.md` covers a subset of the `lib/*.cyr` modules (re-derive the
  gap; 65 of 99 at 2026-08-07, 106 modules now). Docs work, so it can ride the public-release track.
- **Toolchain evolution (LSP / formatter / linter)** — `cbt/` and `programs/` tooling: 6.x-line work, an `issues/` file
  (the cyrlint gates) when it has a concrete item.
- **The agnos peer** (`lib/*agnos*.cyr`) — agnos is a CONSUMER. Its peer changes when agnos files an issue against
  cyrius (`docs/development/issues/`), never proactively.
