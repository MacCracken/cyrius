# Cyrius Development Roadmap — v6.1.x (active minor)

**Scope** — the **current active minor only** (v6.1.x), opened at the
v6.0.x → v6.1.0 clean cut (2026-06-08). This is the slot-pinning
working artifact. The rest of the v6.x cycle (framing, budgeting,
minors v6.2.x → v6.5.x, and the now-closed v6.0.x summary) lives in
[roadmap_6.md](roadmap_6.md); items beyond the cycle (v7.0+
aspirations, unpinned language refinements, speculative work) live in
[roadmap-future.md](roadmap-future.md).

> **Reading order**: this file (active minor) →
> [roadmap_6.md](roadmap_6.md) (rest of the v6.x cycle) →
> [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** reference
  (framing, per-minor budgeting, v6.2.x → v6.5.x, the closed v6.0.x
  summary).
- [roadmap-future.md](roadmap-future.md) — long-term watching list,
  including the **v6.1.x carry-in** candidates surfaced by the v6.0.91
  closeout judgment passes.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check at
  slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.1.x — Backend Codegen Multi-Arc

**Theme**: position-independent codegen + dynamic-link migration +
v6.0.x back-compat retirement, plus the v6.0.x → v6.1.x carry-ins
(stdlib carve, held platform items, closeout judgment-pass cleanups).
Multi-arc minor with 3 pinned sub-arcs.

Per user direction 2026-05-19: "defer larger items for multi-arc
in 6.1.x".

**Minor window**: stated at arc open and open to change
([[feedback_minor_window_at_arc_open]]) — see the slot estimate below.
Premise-check each arc at slot entry ([[feedback_premise_check_at_slot_entry]]);
cross-arch propagation is mandatory for any compiler-emit change
([[feedback_cross_arch_propagation_mandatory]]); 4-host cross-OS
self-host verify before every cut, even lib-only work
([[feedback_cross_os_verify_always_even_lib]],
[[reference_verification_hosts_ssh]]).

---

### Sub-arc A — PIE codegen x86_64 (Option A: kernel-mode only)

`--pie` build flag emitting RIP-relative codegen: `lea rax,
[rip + rel32]` instead of `mov rax, imm64` for absolute-address
loads; fixup-table machinery learns whether each fixup is
absolute (old mode) or RIP-relative (new mode). Userland
binaries + stdlib distfiles continue to use non-PIE path
unchanged.

**AGNOS as first consumer**: full-binary KASLR (Option A in
agnos's `2026-05-11-kaslr-scope.md`). AGNOS v1.28.0 ships
data-only KASLR which doesn't need PIE; pressure here is "when
AGNOS wants full binary relocation" — uncertain timing but
likely materializes during v6.x.

Work surface: ~200-400 LOC across `src/backend/x86/emit.cyr` +
`fixup.cyr`, plus `parse_expr.cyr` fns handling `&fn_name` /
`&global_var` in PIE mode.

Reference proposal:
[`proposals/2026-05-11-pie-support.md`](proposals/2026-05-11-pie-support.md).

### Sub-arc B — PIE codegen aarch64

`adrp` + `add` on aarch64 replacing the 4-chunk `movz`/`movk`
absolute-address sequence. Lands after x86 sub-arc validates the
fixup-table changes are shape-correct cross-arch.

### Sub-arc C — `.gnu.hash` migration + dynamic-link cleanup

Long-term `.gnu.hash` pin deferred at v5.6.38 (no consumer
pressure) earns its slot here — modern dynamic loaders prefer
`.gnu.hash`'s Bloom filter pre-check over the SysV `.hash` chain
walk, and PIE binaries that go through `dlopen` / symbol
resolution see the measurable difference. Land as part of
v6.1.x dynamic-link work; drop SysV `.hash` once `.gnu.hash` is
in place.

### v6.1.0 — Back-compat symlink drop

Per the v6.0.0 transition policy (the rename grace period ends at the
first v6.1 cut):

- Drop `~/.cyrius/bin/cc5 → cycc` + `~/.cyrius/bin/cyrc → cybs`
  symlinks from `scripts/install.sh` release path.
- Drop `cbt/core.cyr` lookup fallback (compiler-binary search
  tries cycc only; no fallback to cc5).
- Same shape for cross-arch symlinks (`cc5_aarch64 → cycc_aarch64`,
  `cc5_win → cycc_win`).

---

### Carried IN from v6.0.x (user 2026-06-04)

Deferred out of the v6.0.x close band; they land in v6.1.x. Slot
placement and ordering are the project leader's call at slot entry
([[feedback_no_unilateral_scope_decisions]]) — listed here as the
v6.1.x work-list, not a pre-sequenced order.

- **bayan/ganita stdlib distfile carve** — the mabda-fold half shipped
  (mabda 3.0.1 vendored @ v6.0.45); the carve rolls forward. Extract
  `json`/`toml`/`cyml`/`csv`/`base64`/`bigint`/`u128` into **bayan**
  (`bayan_<module>_*`) and `matrix`/`linalg`/advanced math into
  **ganita** (`ganita_<module>_*`), each via `[deps.<name>]`
  resolution. Math primitives + regex stay stdlib. After the carve,
  stdlib stays primitives-only so bare-metal consumers (v6.2.x RISC-V /
  firmware) don't drag the data offshoots into kernel objects.
  [[project_bayan_ganita_carve_arc]].
- **x86-macho cycc self-compile** (layer-6 miscompile) — **HELD**
  (Apple Intel EOL); revisited as a v6.1.x arc working item, not a
  blocker. arm64-macOS is the supported macOS target.
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md),
  [`issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md`](issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md).
- **TS/TSX → JS emit** (`cycc --emit-js`) — its own arc, v6.1.x+
  (user 2026-06-04 "TS/TSX→JS in 6.1.x is fine"). The TS/TSX front-end
  parses real-world TS cleanly today but has no emit stage; this is
  codegen on top of the existing AST. Full write-up in
  [roadmap-future.md](roadmap-future.md);
  [`issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`](issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md).

### Carried IN from the v6.0.91 closeout judgment passes

Concrete first-patch candidates surfaced by the closeout workflow
(heap / dead-code / refactor / code-review / security / downstream).
Detail in [roadmap-future.md](roadmap-future.md) "v6.1.x carry-in".

- **aarch64 `EADDRA_IMM` 12-bit mask** (latent, pre-existing) —
  `add x0,x0,#imm12` masks the operand to 12 bits, so a byte-array
  literal `> 4096` elements silently corrupts. Fix: a `> 4095` path
  (chunked add-imm12 or movz/movk + add-reg). Doesn't bite in-tree
  today (no brace-literal byte array > 4096). Issue:
  [`issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md`](issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md).
- **Hoist `_emit_fmt` / `_entry_base` to a shared home** — the v6.0.89
  first-bite left these byte-identical-duplicated in `x86/fixup.cyr` +
  `aarch64/fixup.cyr`. The hoist is blocked by the single-pass parser +
  include order (`_emit_fmt` reads `_TARGET_*` globals declared only in
  `emit.cyr`); prereq is moving the `_TARGET_*` declarations into
  `runtime.cyr`/`tokens.cyr` first. Structural multi-backend change;
  needs ecb/cass self-host reverify.
- **Consolidate the DCE mark-and-sweep** across `x86/fixup.cyr` +
  `aarch64/fixup.cyr` — shared `_dce_hash_lookup` + `_dce_host_fn`
  collapse 4 probe-blocks → 1 and 4 host-scans → 1 (arch delta is only
  `E8/E9`+`DECODE_LEN` vs `BL/B` 4-byte stride). Changes emitted helper
  code → cross-OS self-host reverify.
- **Reclaim the FREED scalar holes** (informational) — allocate the
  next new compiler-state scalar into the v6.0.88 `ret_patches` ~2 KB
  hole (or the v6.0.47 holes) rather than growing the band.

### Stdlib QoL carry-over

- **POSIX `*at()` family** — `openat`, `mkdirat`, `unlinkat`,
  `fstatat`, `linkat`, `renameat`, `fchmodat`, `utimensat` +
  `AT_FDCWD` / `AT_SYMLINK_NOFOLLOW` / `AT_REMOVEDIR` /
  `AT_SYMLINK_FOLLOW` consts + bare-name peers (`sys_lstat`,
  `sys_link`, `sys_rename`). Pulled out of v6.0.62 as its own slot
  (2-arch parity + cross-arch tests — not a "small"). kriya M2 surfaced
  the gap; agnos likely co-consumer. Proposal:
  [`proposals/2026-05-17-syscalls-at-family-stdlib.md`](proposals/2026-05-17-syscalls-at-family-stdlib.md).

### Holdovers (consumer-gated; may not fire in v6.1.x)

- **Cyim regex unblock** (mabda C6) — consumer-gated holdover. Land when
  cyim repo updates + re-tests against v6.x.
- **`cyrius deps --lock` Windows-portable hash** — `certutil`/built-in
  hash path behind a `_TARGET_PE` branch (cass has no `sha256sum`/`sh`).
  Low urgency; lands when a Windows deps consumer surfaces pressure.

---

### Slot estimate (v6.1.x)

| Sub-arc / cluster | Slots |
|---|---|
| PIE x86_64 (Option A — kernel-mode) | ~6 |
| PIE aarch64 | ~3 |
| `.gnu.hash` migration + drop SysV `.hash` | ~4 |
| Back-compat symlink drop (v6.1.0) | ~1 |
| bayan/ganita stdlib carve | ~4-6 |
| Closeout carry-ins (EADDRA_IMM fix, `_emit_fmt` hoist, DCE consolidation) | ~3-4 |
| POSIX `*at()` family | ~2 |
| AGNOS PIE smoke gate + cross-host verify | ~2 |
| **Total planned** | **~25-28** |
| Bug bandwidth | ~10 |
| **Budget** | **~35-38** |

x86-macho cycc self-compile and TS/TSX → JS emit are open-scope arcs
flagged for the minor; whether either lands inside v6.1.x or spills to
its own minor is a project-leader call at slot entry. Window stated at
arc open and open to change ([[feedback_minor_window_at_arc_open]]).
