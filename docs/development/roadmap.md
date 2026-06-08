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
(stdlib carve, closeout judgment-pass cleanups). Multi-arc minor.

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

## Pinned slot sequence

Organized 2026-06-08 (user direction): **primary expected items first**,
in the order *quick housekeeping → backend-refactor prep → PIE codegen →
stdlib carve*, packed **one sub-arc per release** (user: "per-sub-arc
releases"). Slot numbers are nominal — premise-check each at slot entry;
the HELD / open-arc items (below the primary block) are **not pinned** and
land only on consumer pressure or explicit user direction.

| Slot | Item | Phase |
|---|---|---|
| **v6.1.0** ✅ | Clean cut — roadmap split (`roadmap.md`/`roadmap_6.md`) + full docs sweep + `build/` cleanup (prior-major slot `cc3 → cc5`) + benchmark-every-release gate | shipped |
| **v6.1.1** ✅ | Back-compat symlink drop (install symlinks + `cbt/core.cyr` cc5 fallback + repl shim) | A — housekeeping |
| **v6.1.2** ✅ | `aarch64 EADDRA_IMM` >4095 fix (low+hi adds + movz/movk guard; pi+ecb verified) | A — housekeeping |
| **v6.1.3** ✅ | POSIX `*at()` family + bare-name peers + aarch64 ESYSXLAT collision fix (repaired pre-existing native-aarch64 `sys_stat`) | A — housekeeping |
| **v6.1.4** ✅ | Backend prep — `_TARGET_*` decl move + `_emit_fmt` hoist to common/runtime.cyr (`_entry_base` stays per-arch — not a dup) | B — backend prep |
| **v6.1.5** ✅ | DCE mark-and-sweep consolidation (`_dce_hash_lookup` + `_dce_host_fn` hoist to `common/runtime.cyr`; 4 probe-blocks → 1, 4 host-scans → 1; −51 LOC, cycc −752 B; logic-preserving) | B — backend prep |
| **v6.1.6** | PIE codegen x86_64 (Sub-arc A) | C — PIE |
| **v6.1.7** | PIE codegen aarch64 (Sub-arc B) | C — PIE |
| **v6.1.8** | `.gnu.hash` migration + drop SysV `.hash` (Sub-arc C) | C — PIE / dynlink |
| **v6.1.9** | TS/TSX → JS emit (`cycc --emit-js`) | D — frontend emit |
| **v6.1.10** | bayan distfile carve | E — stdlib carve |
| **v6.1.11** | ganita distfile carve | E — stdlib carve |
| *(bug bandwidth)* | x86-macho cycc self-compile (HELD), cyim regex unblock, Windows deps `--lock` hash | absorbed into bug bandwidth |

**Why this order** (user lead choice = housekeeping → backend-prep → PIE):
the housekeeping items (Phase A) are small, ready, and have concrete
pressure (a filed `EADDRA_IMM` bug, kriya's `*at()` ask, the overdue
rename-symlink retirement). The backend-refactor carry-ins (Phase B) are
**prep for PIE** — the `_emit_fmt` hoist needs the `_TARGET_*` decls moved
first, and PIE adds new fixup modes to the same `emit.cyr`/`fixup.cyr`
files, so consolidating them before PIE keeps the codegen clean. PIE
(Phase C) is the pinned theme; it lands on the cleaned backend, x86 first
to validate the fixup-table shape, then aarch64, then the `.gnu.hash`
dynamic-link cleanup. **TS/TSX → JS emit (Phase D)** is pulled up ahead of
the carve (user 2026-06-08) — it has active consumer pressure
(SecureYeoman `yeo-cy-test`) and the expensive part (the parser) already
exists, so it earns a primary slot before the carve. The bayan/ganita
carve (Phase E) is the last primary block — concrete (standing pin) but
independent of the backend work, so it tails the codegen + emit arcs.

---

## Slot detail

### Phase A — quick housekeeping (v6.1.1 → v6.1.3)

#### v6.1.1 — Back-compat symlink drop

The v6.0.0 rename grace period ends at the first v6.1 working patch.

- Drop `~/.cyrius/bin/cc5 → cycc` + `~/.cyrius/bin/cyrc → cybs`
  symlinks from `scripts/install.sh` release path.
- Drop `cbt/core.cyr` lookup fallback (compiler-binary search
  tries cycc only; no fallback to cc5).
- Same shape for cross-arch symlinks (`cc5_aarch64 → cycc_aarch64`,
  `cc5_win → cycc_win`).

#### v6.1.2 — aarch64 `EADDRA_IMM` 12-bit mask (>4095) fix

Latent, pre-existing (filed at the .91 closeout, **not** a .88–.90
regression). `add x0,x0,#imm12` masks the operand to 12 bits, so a
byte-array literal `> 4096` elements silently corrupts (at offset 4096,
`4096 & 0xFFF == 0` → no-op add → byte lands at `&var+0`). Reached only
via the peephole's correct `disp >= 4096` legacy fallback; doesn't bite
in-tree today (no brace-literal byte array > 4096). Fix: a `> 4095` path
(chunked add-imm12 or movz/movk + add-reg). Changes aarch64 codegen →
cross-OS self-host reverify (pi/ecb). Issue:
[`issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md`](issues/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md).

#### v6.1.3 — POSIX `*at()` family

`openat`, `mkdirat`, `unlinkat`, `fstatat`, `linkat`, `renameat`,
`fchmodat`, `utimensat` + `AT_FDCWD` / `AT_SYMLINK_NOFOLLOW` /
`AT_REMOVEDIR` / `AT_SYMLINK_FOLLOW` consts + bare-name peers
(`sys_lstat`, `sys_link`, `sys_rename`). Pulled out of v6.0.62 as its
own slot (2-arch parity + cross-arch tests — not a "small"). kriya M2
surfaced the gap; agnos likely co-consumer. Proposal:
[`proposals/2026-05-17-syscalls-at-family-stdlib.md`](proposals/2026-05-17-syscalls-at-family-stdlib.md).

### Phase B — backend-refactor prep (v6.1.4 → v6.1.5)

The .91 closeout judgment-pass carry-ins, sequenced **before PIE** because
they clean the backend PIE then extends. Detail in
[roadmap-future.md](roadmap-future.md) "v6.1.x carry-in".

#### v6.1.4 — `_TARGET_*` decl move + `_emit_fmt`/`_entry_base` hoist

The v6.0.89 first-bite left `_emit_fmt`/`_entry_base` byte-identical-
duplicated in `x86/fixup.cyr` + `aarch64/fixup.cyr`. The hoist to a shared
home is blocked by the single-pass parser + include order (`_emit_fmt`
reads `_TARGET_MACHO`/`_PE`/`_ELF64_KERNEL` as bare-identifier globals
declared only in `emit.cyr` → a hoist there is a hard "undefined variable"
exit). **Prereq (this slot)**: move the `_TARGET_*` declarations into
`runtime.cyr`/`tokens.cyr` first (verified feasible at closeout — no early
reader; all assignments happen after every include), then hoist. Structural
multi-backend change → ecb/cass/pi self-host reverify. Also reclaim the
FREED scalar holes (the v6.0.88 `ret_patches` ~2 KB hole + the v6.0.47
holes) for any new compiler-state scalar rather than growing the band.

#### v6.1.5 — DCE mark-and-sweep consolidation

The hash build/seed/propagate/sweep/undef-fn pass is duplicated across the
two `fixup.cyr` backends, and within each the open-addressing hash-probe +
the linear host-fn scan are each written twice. A shared `_dce_hash_lookup`
+ `_dce_host_fn` collapse 4 probe-blocks → 1 and 4 host-scans → 1 (arch
delta is only `E8/E9`+`DECODE_LEN` vs `BL/B` 4-byte stride). Changes
emitted helper code → cross-OS self-host reverify.

### Phase C — PIE codegen (v6.1.6 → v6.1.8)

The pinned theme — position-independent codegen, landing on the cleaned
backend. **Consumer note**: PIE's first consumer is AGNOS full-binary
KASLR (Option A in agnos's `2026-05-11-kaslr-scope.md`); AGNOS v1.28.0
ships data-only KASLR that doesn't need PIE, so this arc may land ahead of
live consumer pressure. Premise-check AGNOS pull at slot entry.

#### v6.1.6 — PIE codegen x86_64 (Sub-arc A, Option A: kernel-mode only)

`--pie` build flag emitting RIP-relative codegen: `lea rax, [rip + rel32]`
instead of `mov rax, imm64` for absolute-address loads; the fixup-table
machinery learns whether each fixup is absolute (old mode) or RIP-relative
(new mode). Userland binaries + stdlib distfiles keep the non-PIE path
unchanged. Work surface: ~200-400 LOC across `src/backend/x86/emit.cyr` +
`fixup.cyr`, plus `parse_expr.cyr` fns handling `&fn_name` / `&global_var`
in PIE mode. Reference proposal:
[`proposals/2026-05-11-pie-support.md`](proposals/2026-05-11-pie-support.md).

#### v6.1.7 — PIE codegen aarch64 (Sub-arc B)

`adrp` + `add` on aarch64 replacing the 4-chunk `movz`/`movk`
absolute-address sequence. Lands after the x86 sub-arc validates the
fixup-table changes are shape-correct cross-arch. (The `EADDRA_IMM` fix
shipped @ v6.1.2, so the `add`-imm path is already >4095-safe here.)

#### v6.1.8 — `.gnu.hash` migration + dynamic-link cleanup (Sub-arc C)

The long-term `.gnu.hash` pin deferred at v5.6.38 (no consumer pressure)
earns its slot here — modern dynamic loaders prefer `.gnu.hash`'s Bloom
filter pre-check over the SysV `.hash` chain walk, and PIE binaries going
through `dlopen` / symbol resolution see the measurable difference. Drop
SysV `.hash` once `.gnu.hash` is in place.

### Phase D — TS/TSX → JS emit (v6.1.9)

Pulled into the primary block ahead of the carve (user 2026-06-08). The
Cyrius TS/TSX front-end **parses** real-world TS/TSX cleanly today
(interfaces, generics + default type params, `?.`/`??`, async/await, enums,
JSX, a full React component) but has **no emit** — `--lex-ts` / `--parse-ts`
validate only. The ask: a `cycc --emit-js <file.tsx>` (or `cyrius build
--target=js`) codegen stage walking the existing AST — strip type
annotations / interfaces / type aliases, lower JSX → `createElement`-style
calls (configurable pragma), pass ESM through. **Single-file emit only; a
bundler is out of scope.** The expensive part (the full-fidelity TS/TSX
parser) already exists — this is codegen on top. Active consumer pressure
(SecureYeoman `yeo-cy-test`, which hand-maintains a parallel `web/app.js`
stopgap today). May widen to a small mini-arc at slot entry. Issue:
[`issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`](issues/2026-05-27-yeo-cy-test-no-tsx-js-emit.md);
full write-up in [roadmap-future.md](roadmap-future.md).

> **Framing note**: this is a *non-machine-code output target* for an
> assembly-up compiler. Premise-check the scope at slot entry — if it
> proves larger than one slot, ASK for the shape rather than re-slotting
> ([[feedback_no_unilateral_scope_decisions]]).

### Phase E — stdlib carve (v6.1.10 → v6.1.11)

The bayan/ganita distfile carve — the second half of the stdlib
clean-slate (the mabda fold shipped @ v6.0.45). After the carve, stdlib
stays primitives-only so bare-metal consumers (v6.2.x RISC-V / firmware)
don't drag the data offshoots into kernel objects. Math primitives + regex
stay stdlib. [[project_bayan_ganita_carve_arc]].

#### v6.1.10 — bayan distfile carve

Extract `json` / `toml` / `cyml` / `csv` / `base64` / `bigint` / `u128`
from stdlib into the **bayan** sibling repo + `[deps.bayan]` resolution.
Naming convention `bayan_<module>_*`.

#### v6.1.11 — ganita distfile carve

Extract `matrix` / `linalg` / advanced math from stdlib into the
**ganita** sibling repo + `[deps.ganita]` resolution. Naming convention
`ganita_<module>_*`.

---

## Bug-bandwidth items (not pinned)

Real v6.1.x candidates that ride the **bug-bandwidth** budget rather than
the planned arc (user 2026-06-08: "keep tail as bug bandwidth") — each
lands in an open bug-bandwidth slot on consumer pressure or explicit user
direction ([[feedback_no_unilateral_scope_decisions]]), not as a pinned
planned release.

- **x86-macho cycc self-compile** (layer-6 miscompile) — **HELD** (Apple
  Intel EOL); arm64-macOS is the supported macOS target. Revisited as a
  working item, not a blocker.
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md),
  [`issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md`](issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated; land when cyim
  updates + re-tests against v6.x.
- **`cyrius deps --lock` Windows-portable hash** — `certutil`/built-in
  hash path behind a `_TARGET_PE` branch (cass has no `sha256sum`/`sh`).
  Low urgency; lands when a Windows deps consumer surfaces pressure.

---

## Slot estimate (v6.1.x)

| Phase | Slots |
|---|---|
| A — housekeeping (symlink drop, EADDRA_IMM, POSIX `*at()`) | 3 |
| B — backend-refactor prep (`_TARGET_*`/`_emit_fmt` hoist, DCE consolidation) | 2 |
| C — PIE codegen (x86, aarch64, `.gnu.hash`) | 3 |
| D — TS/TSX → JS emit | 1 |
| E — stdlib carve (bayan, ganita) | 2 |
| **Total planned (primary expected)** | **~11** |
| Bug bandwidth (incl. the bug-bandwidth items above) | ~10 |
| **Budget** | **~21** |

The primary block is the ~10 pinned slots above. The HELD/open-arc tail
adds nothing to the planned count until pulled forward. Window stated at
arc open and open to change ([[feedback_minor_window_at_arc_open]]).
