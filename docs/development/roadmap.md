# Cyrius Development Roadmap — v6.x

**Scope** — the v6.x cycle (post-v6.0.0 cycle-open 2026-05-19).
Items outside the current minor — v7.0+ aspirations, unpinned
language refinements, speculative work — live in
[roadmap-future.md](roadmap-future.md). v5.x history is canonical
in [`CHANGELOG.md`](../../CHANGELOG.md) per-patch and in
[completed-phases.md](completed-phases.md) for arc retrospective.

## See also

- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check,
  cross-host smoke, cycle-close shape). Evergreen; not cycle-specific.
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [roadmap-future.md](roadmap-future.md) — long-term watching list
  (unpinned items, speculative type-system work, v7.0+ aspirations).
- [completed-phases.md](completed-phases.md) — pre-v5.11.x historical
  arc retrospective (Phase 0–11 foundation summary post-trim).
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

## v6.x framing

v5.x froze "what the language IS." **v6.x is what the language
gains** — new platforms, position-independent codegen, language
features (closures, generics, async syntax), Class B FFI fix,
cross-BB regalloc + the deferred optimization passes that gate on
it. Plus a dedicated middle-late perf-refactor minor to absorb the
accumulated growth-tax from v5.x feature work + early-v6.x platform
additions.

## v6.x cycle budgeting

**Per-minor target**: ~30-slot budget = 20 planned + 10 bug
bandwidth (per user direction 2026-05-19). Can flex to 40-50 like
late v5.x cycles when a minor's substantive new-code surface
warrants it (notably v6.2.x platform expansion + v6.4.x ABI+Perf
arcs).

Reference points: v5.11.x = 70 slots (longest in history),
v5.7.x = 49. v6.x cycles target a middle-ground — most minors
in the 30-40 range, with the substantive-new-code minors flexing
higher.

---

## v6.0.x — Language Cleanup + Stdlib Expansion + Stdlib Clean-Slate

**Theme**: absorb leftover v5.x runway-carryover items + small
language QoL improvements + holdovers, paired with the
near-imminent mabda 3.0 GA stdlib clean-slate (mabda fold +
bayan/ganita carve, all together).

**Shipped**:
- **v6.0.0** — two-binary rename ceremony: `cyrc → cybs` (Cyrius
  Bootstrap) + `cc5 → cycc` (Cyrius Computer Compiler). Bootstrap
  chain `seed (asm) → cybs → cycc`. ~2,100 occurrences renamed
  across ~157 files; historical narrative preserved.
- **v6.0.1** — two stdlib-resolution hotfixes filed same-day as the
  v6.0.0 cycle-open. (1) Rename-skip off-by-one in
  `src/frontend/lex.cyr` (`vp = 4` / `_pd_self_start = 4` should
  have been 5 for `"cycc "`) corrupted the version-pinned stdlib
  fallback path to `$HOME/.cyrius/versions/ <v>/lib/` (leading
  space), causing `include "lib/X.cyr"` to silently fail-resolve
  for consumers without a vendored `./lib/` — gnoboot 0.2.0
  shipped a PE32+ with `ud2/ud2/nop` sentinels at every UEFI
  service call. Same bug fired the pin-drift warning when versions
  matched. (2) Pre-existing `cmd_deps` mkdir-before-find regression
  (v5.11.17 vintage) — `sys_mkdir("lib", 0x1ED)` before
  `_dep_find_stdlib_dir` tripped priority (a) for ANY downstream
  repo with `src/main.cyr` + non-empty stdlib pin. Surfaced when
  gnoboot adopted `stdlib = ["fnptr"]`. Two regression smoke gates
  added (check.sh 78/78 now).

### Pinned slot sequence (next three)

Per user direction 2026-05-20. v6.0.2 lands at the user's
convenience once the in-flight stdlib walk completes; v6.0.3 +
v6.0.4 form a two-slot mini-arc closing out the v5.11.x deferred
return-patch-buffer → vec conversion (proposal Option C,
[`proposals/archived/2026-05-08-raise-return-cap.md`](proposals/archived/2026-05-08-raise-return-cap.md)).

- **v6.0.2 — stdlib pin refresh** — pull the latest of each
  stdlib dep into cyrius's own `cyrius.cyml` (sigil, sakshi,
  patra, sankoch, niyama, vani, yukti, agnosys, …) reflecting
  the parallel "walk the stdlibs and update to 6.0.1" sweep the
  user is running alongside kernel-arc work. **mabda holds at
  its current pin** until rc.4 validation closes — explicit
  exception. Acceptance: every dep's `cyrius` field tracks
  v6.0.1; `cyrius deps` resolves clean; `scripts/check.sh` green;
  smoke across all four SSH hosts ([[reference_verification_hosts_ssh]]).
- **v6.0.3 — alloc + vec pull-in (prep)** — fold `lib/alloc.cyr`
  (+ OS-variant `alloc_windows.cyr` / `alloc_macos.cyr` brought
  in by its internal `#ifdef` chain) and `lib/vec.cyr` into
  cycc's source tree. Add `include` lines to both `src/main.cyr`
  and `src/main_aarch64.cyr`; call `alloc_init()` explicitly at
  top-level (explicit > v5.8.37 lazy-init for compiler internals
  — narrower failure mode). Allocate the parser's
  return-patch vec once via `rp_vec = vec_new()` at parser-state
  init. **Zero behavior change**: the fixed 256-slot array at
  `S + 0x18DA20` is still the active storage; the parser still
  errors out at >256 returns. This slot just makes the surface
  available. Total pull-in surface: ~842 LoC (alloc 483 +
  alloc_windows 87 + alloc_macos 117 + vec 155). Cycc binary
  growth bookkept as honest growth-tax per
  [[feedback_perf_deltas_growth_tax_default]]. Acceptance: cycc
  byte-identical; full `scripts/check.sh`; 4-host smoke.
- **v6.0.4 — return-patch buffer → vec (conversion)** — replace
  the fixed-array storage at all 9 enforcement sites
  (`parse.cyr` ×1, `parse_expr.cyr` ×3, `parse_fn.cyr` ×5) with
  `vec_push(rp_vec, v)`; replace the read-back at
  `parse_expr.cyr:803-812` with `vec_get(rp_vec, clri)` and the
  iteration bound with `vec_len(rp_vec)`. Save/restore for
  closure-bodied nesting at `parse_expr.cyr:760-812` becomes
  `snap = vec_len(rp_vec); vec_truncate(rp_vec, 0)` on entry,
  `vec_truncate(rp_vec, snap)` on exit (may need to add
  `vec_truncate` to `lib/vec.cyr` if not already present —
  confirm at slot entry). Per-fn lifecycle: `vec_truncate(rp_vec,
  0)` at each fn-start — **Option A reuse pattern, chosen for
  security reasons**: cycc's allocator is a bump allocator
  (`lib/alloc.cyr` header line 17), so per-fn `vec_new`/free
  would leave stranded allocations and create a DoS surface on
  malicious input. Reset-per-fn keeps memory bounded at the
  high-water-mark of the largest fn. Delete `GRPC`/`SRPC` from
  `src/common/util.cyr:128-129` and sweep all callers; the dead
  2KB region `[0x18DA20..0x18E220)` and the now-unused counter
  slot at `0x18E220` stay in place — flagged for v6.x closeout
  heap-map sweep per user direction 2026-05-20 ("if needed
  collapse it otherwise closeouts should focus on those kind
  of cleanups"). The "too many return statements (max 256)"
  diagnostic is replaced by an OOM error at the single
  `vec_new()` site. Cross-arch propagation mandatory
  ([[feedback_cross_arch_propagation_mandatory]]): x86 +
  aarch64 + cx + macho in this same slot. Acceptance: cycc
  byte-identical post-conversion; new
  `tests/tcyr/return_cap_removed.tcyr` exercising a fn with
  >256 returns (currently rejected) compiling clean; full
  `scripts/check.sh`; 4-host smoke.

### Planned

#### Toolchain & tests

- **`programs/check.cyr` → `programs/checks/main.cyr` + per-suite
  split** — current monolithic ~9,300 LoC / ~80 gates file is
  hard to navigate and saturated. Break out into a slim dispatcher
  + per-suite files (self-host, EFI, deps, heap-map, etc. — exact
  breakdown ASK at slot entry). Self-host byte-identical post-
  split. User direction 2026-05-19.

### v6.0-runway carry-forward (5 items from v5.11.x close band)

The v5.11.x close absorbed 5 of 10 v6.0.0 accompanying-refactor
items into v5.x close (CVE-05, bridge retirement, build-cycc-
verify.sh skeleton, cc3-residue cleanup, heap-map full reorg).
The remaining 5 land in v6.0.x:

- **Byte-array literal peephole** — 5× emit compression for
  `var foo[N] = { 0x.., ... };` init via `mov byte [rcx+disp8],
  imm8` (x86) / STRB Wn, [Xn, imm12] (aarch64) / cx peer. Moved
  here from v5.11.66/.67 at user direction. Acceptance: cycc
  byte-identical; gnoboot binary shrinks visibly (~1300 B per
  UTF-16LE string, ~250 B per EFI GUID). Cross-arch propagation
  per `feedback_cross_arch_propagation_mandatory`.
- **Dead-code careful sweep** — walk cycc's reported unreachable
  fns. Per [`feedback_dead_code_audit_scope`]: scaffold (TS_*/
  ir_*/cross-arch helpers) stays alive by default; only
  confirmed-dead removable. Risk: 0-LoC outcome if all
  candidates classify as scaffold.
- **Return-patch buffer → vec** — pinned as the v6.0.3 +
  v6.0.4 mini-arc (alloc/vec pull-in + conversion). See
  "Pinned slot sequence" above for full scope. Proposal
  Option C; allocator prereq surface confirmed at v5.11.67
  premise-check.
- **`_TARGET_*` flag consolidation** — `_TARGET_MACHO`,
  `_TARGET_PE`, `CYRIUS_TARGET_LINUX/WIN/MACOS`, `_AARCH64_BACKEND`,
  plus per-arch `EWRITE_PE` / `_pe_pending_imp_add` / `EDISP32`
  shim families. Consolidate into a single backend-dispatch
  table keyed on `(arch, format)`. Substantial multi-slot
  refactor; lands here per user direction "keep in v6.0.x
  bundle".
- **Backend module collapse where viable** — `src/backend/x86/`
  and `src/backend/aarch64/` parallel `emit.cyr` / `jump.cyr` /
  `fixup.cyr`. Audit which helpers can move to
  `src/backend/common/` without entangling asm-byte tables.

### Stdlib QoL expansion

- **POSIX `*at()` family** — `openat`, `mkdirat`, `unlinkat`,
  `fstatat`, `linkat`, `renameat`, `fchmodat`, `utimensat` +
  `AT_FDCWD` / `AT_SYMLINK_NOFOLLOW` / `AT_REMOVEDIR` /
  `AT_SYMLINK_FOLLOW` consts + bare-name peers (`sys_lstat`,
  `sys_link`, `sys_rename`). kriya M2 surfaced this gap;
  agnos likely co-consumer. Proposal:
  [`proposals/2026-05-17-syscalls-at-family-stdlib.md`](proposals/2026-05-17-syscalls-at-family-stdlib.md).
- **TOML `[section]` single-bracket** in `lib/toml.cyr` —
  spec-conformant single-table syntax alongside existing
  `[[name]]` array-of-tables. ~10 LOC change in `toml_parse`'s
  dispatch. commandress config-loader driver. Proposal:
  [`proposals/2026-05-17-toml-single-bracket-sections.md`](proposals/2026-05-17-toml-single-bracket-sections.md).
- **Octal literal syntax** (`0o755`) — lexer-only feature,
  ~30 LOC in `src/frontend/lex.cyr::LEXNUM` + new `LEXOCT`
  routine. kriya M2 surfaced this for POSIX file-mode constants.
  Proposal:
  [`proposals/2026-05-17-octal-literal-syntax.md`](proposals/2026-05-17-octal-literal-syntax.md).

### Holdovers

- **Build-artifact pre-commit hook** — generalize the v5.11.45
  `_cc5_contamination_gate` (now `_cycc_contamination_gate`)
  from "catch after the fact" to "refuse the commit". Adds a
  `cyrius hooks install` verb that installs `.git/hooks/pre-
  commit` checking for foreign-binary strings, size sanity, and
  ELF magic on `build/<bin>` commits. Issue:
  [`issues/2026-05-13-build-artifact-precommit-hook.md`](issues/2026-05-13-build-artifact-precommit-hook.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated holdover.
  Land when cyim repo updates + re-tests against v6.x. May not
  fire in v6.0.x window.

### Stdlib clean-slate — mabda 3.0 GA fold + bayan/ganita carve

**Status**: near-imminent. mabda 3.0.0-rc.3 passed its initial
soak window 2026-05-19; one 24-hour soak away from GA. Fold +
carve land together as the v6.0.x **primary stdlib arc** when
mabda 3.0 GA cuts.

Per user direction 2026-05-19: "stdlib stuff will wait until
mabda is 3.0 GA so we can clean slate and update all the items
together... most likely will happen in 6.0.x cycle".

**Three-part atomic update**:

1. **mabda 3.0 fold** into stdlib using the v5.7.0 sandhi pattern
   (sakshi/patra/sigil/vani/yukti/sankoch v5.8.x precedent; niyama
   v5.9.0). Sister fold: agnosys (transitive via mabda).

2. **bayan distfile carve** — extract `json` / `toml` / `cyml` /
   `csv` / `base64` / `bigint` / `u128` modules from stdlib into
   sibling repo + `[deps.bayan]` resolution. Naming convention
   `bayan_<module>_*`. Math primitives + regex stay in stdlib.

3. **ganita distfile carve** — extract `matrix` / `linalg` /
   advanced math from stdlib into sibling repo + `[deps.ganita]`
   resolution. Naming convention `ganita_<module>_*`.

After the carve, stdlib stays primitives-only — bare-metal
consumers in v6.2.x's RISC-V / firmware work won't drag the data
offshoots into kernel objects.

**Class B FFI / wgpu fncall6 ABI**: if mabda 3.0 GA shipped clean
(rc3 soak passing → GA is the test), the Class B FFI work doesn't
gate the fold. Class B FFI ABI fix proper lands in v6.4.x
regardless. If mabda 3.0 GA gates on the ABI fix in rare
unforeseen circumstance, fold + ABI move together to v6.4.x.

Memory pins: [`project_bayan_ganita_carve_arc`],
[`project_mabda_rc3_at_closeout`] (carried forward from v5.x).

### Slot estimate (v6.0.x)

| Cluster | Slots |
|---|---|
| Stdlib pin refresh (v6.0.2) | 1 |
| Runway carry-forward (5 items, incl. v6.0.3+v6.0.4 mini-arc) | ~16 |
| Stdlib QoL (POSIX *at + TOML + octal) | ~7 |
| Holdovers (pre-commit hook + cyim conditional) | ~2-3 |
| Stdlib clean-slate (mabda fold + bayan + ganita) | ~6-8 |
| **Total planned** | **~32-35** |
| Bug bandwidth | ~10 |
| **Budget** | **~42-45** |

The stdlib clean-slate flexes total slot count above the 30
target — acceptable given the "clean slate, update all together"
intent. If mabda GA slips past v6.0.x window, the stdlib portion
defers and v6.0.x lands at ~25 planned slots.

### Deferred to v6.1.0 cut

- v6.0.x → v6.1.0 back-compat symlink drop (cc5 → cycc + cyrc →
  cybs in install snapshot + cbt/core.cyr lookup fallback). Per
  the v6.0.0 transition policy.

---

## v6.1.x — Backend Codegen Multi-Arc

**Theme**: position-independent codegen + dynamic-link migration
+ v6.0.x back-compat retirement. Multi-arc minor with 3 sub-arcs.

Per user direction 2026-05-19: "defer larger items for multi-arc
in 6.1.x".

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

- Drop `~/.cyrius/bin/cc5 → cycc` + `~/.cyrius/bin/cyrc → cybs`
  symlinks from `scripts/install.sh` release path.
- Drop `cbt/core.cyr` lookup fallback (compiler-binary search
  tries cycc only; no fallback to cc5).
- Same shape for cross-arch symlinks (`cc5_aarch64 → cycc_aarch64`,
  `cc5_win → cycc_win`).

### Slot estimate (v6.1.x)

| Sub-arc | Slots |
|---|---|
| PIE x86_64 (Option A — kernel-mode) | ~6 |
| PIE aarch64 | ~3 |
| `.gnu.hash` migration + drop SysV `.hash` | ~4 |
| Back-compat symlink drop (v6.1.0) | ~1 |
| AGNOS PIE smoke gate + cross-host verify | ~2 |
| **Total planned** | **~16** |
| Bug bandwidth | ~10 |
| **Budget** | **~26** |

---

## v6.2.x — Platform Expansion (Bare-metal + RISC-V rv64)

**Theme**: 4th platform peer (RISC-V rv64) + bare-metal target
codification. Substantial new-code minor; substrate prerequisites
all landed in v5.11.x close (parser-to-emit named-op refactor,
heap-map full reorg) + v6.1.x backend codegen.

Per user direction 2026-05-19: "previous C items lets break up
logically into prioritized proposals into 6.2.x and 6.3.x" —
platform work (bottom-to-top priority) takes v6.2.x.

### v6.2.0 — Bare-metal target formalization

Codify the ad-hoc bare-metal mode that agnos has been using
since first boot into a first-class
`--target bare-metal-x86_64-elf` (and aarch64 peer) triple.
Six deliverables:

1. Formal target triple (`<arch>-bare-metal-elf`)
2. ELF no-libc output format (no PT_INTERP, no DT_NEEDED, no
   _start expecting libc init)
3. Interrupt-handler emit conventions (`naked_fn` attribute —
   no prologue/epilogue, manual register save/restore)
4. Kernel-mode stdlib subset (forbidden-module check errors
   when bare-metal code pulls host-OS modules)
5. Linker-script / section-placement control via `[sections]`
   block in `cyrius.cyml`
6. Inline assembly primitives for kernel work: `cli`/`sti`/`hlt`,
   port I/O (`in`/`out`), memory barriers (`mfence`/`lfence`/
   `sfence`), `cpuid`

**Acceptance**: rebuilding the agnos kernel with `--target
bare-metal-x86_64-elf` produces a byte-identical artifact to the
current ad-hoc build; forbidden-module check errors clearly when
bare-metal code pulls host-OS modules;
`examples/firmware-hello.cyr` demonstrates the target outside
of agnos.

**Important framing**: bare-metal is **formalization, not
enablement**. The agnos kernel already builds and boots without
this target; v6.2.0 is a QoL feature for future bare-metal
Cyrius consumers (firmware, alt-kernels, embedded). It does NOT
gate AGNOS MVP.

### v6.2.x — RISC-V rv64 backend

First-class RISC-V 64-bit target. The 4th platform peer after
x86_64 / aarch64 / PE-x86_64. Substrate prerequisites already
landed: typed-simd ABI (v5.x), REAL TYPE SYSTEM (v5.10.x),
struct-byval ABI (v5.10.x), parser-to-emit named-op refactor
(v5.11.x close).

**Scope**:
- New backend: `src/backend/riscv64/{emit,jump,fixup}.cyr`
- New stdlib syscall peer: `lib/syscalls_riscv64_linux.cyr`
- New cross-entry: `src/main_riscv64.cyr`
- New test runner: QEMU + HiFive Unmatched (or equivalent rv64
  hardware) for self-host verify
- New CI matrix arm

**Acceptance gates**:
1. Cross-compiler `build/cycc_riscv64` emits valid rv64 ELF
   that `file(1)` identifies.
2. Single-syscall "exit 42" probe runs under
   `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on real rv64 hardware (hardware-
   gated like the aarch64 ssh-pi check).
5. `[release].cross_bins` in `cyrius.cyml` gets a
   `cycc_riscv64` entry.

### Slot estimate (v6.2.x)

| Cluster | Slots |
|---|---|
| Bare-metal target formalization (6 deliverables) | ~8 |
| RISC-V rv64 backend (new emit/jump/fixup + syscalls peer) | ~12 |
| Cross-arch test harness + CI matrix | ~3 |
| Hardware self-host gate (HiFive Unmatched or equivalent) | ~2 |
| **Total planned** | **~25** |
| Bug bandwidth | ~10 |
| **Budget** | **~35** |

Larger minor — flexes above 30 budget per user direction
"larger patch bandwidth like the last few minor cycles of 5.x"
when substantive new-code surface warrants.

---

## v6.3.x — Language Refinements

**Theme**: language-level closures + generics + async sugar.
Three syntactic/semantic additions the v5.x cycle held out
explicitly (per 2026-05-12 tight-close).

Per user direction 2026-05-19: language work (mid-priority,
above ABI/perf) takes v6.3.x.

### Closures with lexical capture

Today: function pointers + lambda-pattern workarounds (see
`lib/fnptr.cyr`). Gotcha #8 in v5.x Language Refinements table —
consumers feel the absence.

**Scope**: closure literals + lexical-capture analysis +
closure-environment lowering (allocate-on-construct, deallocate
when closure pointer goes out of scope; vtable-shaped indirect
call). Pairs with existing trait/vtable infrastructure
(`lib/trait.cyr`). v5.8.x ADTs (sum types + exhaustive match +
Result + ?) make captured-state encoding cleaner than it would
have been pre-v5.8.

### Real generic instantiation (monomorphization)

Today: generics parse (type params accepted at `SKIP_GENERICS`
in `src/frontend/parse_decl.cyr`) but erase at compile time —
no monomorphization, type-check semantics are weakest-applicable.
Test floor: `tests/tcyr/enum_generics.tcyr` (v5.8.21 syntax-
acceptance only).

**Scope**: type checker recognizes type parameters as
concrete-at-instantiation; emit-time substitution generates
per-monomorph code. Kavach was the original 1-vote consumer
(per v5.x Language Refinements table); re-verify pressure at
slot entry per [`feedback_premise_check_at_slot_entry`].

### Language-level async/await syntax

Today: callback-based async on epoll runtime (`lib/async.cyr`,
v5.11.15). Works but is verbose at consumer sites.

**Scope**: `async fn` / `await` syntax compiles to
CPS-transformed state machines over the existing epoll runtime.
Same runtime semantics, sugarier surface. Pairs with closures
(capture state across await points).

### Required vs Optional Dependencies

Today: `cyrius.cyml` has no required/optional distinction. Every
entry in `[deps].stdlib = [...]` auto-prepends; every `[deps.<name>]`
block resolves unconditionally via `cyrius deps`. No feature gating,
no target conditionals, no schema knob for "include this only when
needed." Consumers that want conditional code must wrap call sites
in `#ifdef` and hope the transitive resolver doesn't drag the dep
in anyway.

**Scope** (per user direction 2026-05-23 — combine feature +
platform axes):

1. **Feature-gated optional deps** (Cargo-style)
   - `optional = true` flag on `[deps.<name>]` blocks
   - `[features]` table declaring named feature sets +
     default-features
   - `cyrius build --features <list>` / `--no-default-features`
     CLI surface
   - Resolver only fetches+prepends deps whose feature gate is
     active for the current build
2. **Platform-conditional resolution**
   - `target = "<arch>"` / `target = "<os>"` keys on
     `[deps.<name>]` blocks (e.g. `target = "windows"`,
     `target = "aarch64"`, `target = "bare-metal"`)
   - Matches existing cross-arch story (`_TARGET_PE` / aarch64
     emit paths). Bare-metal target (v6.2.0) and RISC-V backend
     (v6.2.x) immediately benefit — kernel objects skip
     non-applicable userland deps without `#ifdef` gymnastics
3. **Axes combine** — a dep can be both feature-gated AND
   platform-conditional: `optional = true` + `target = "windows"`
   + listed under a feature

**Manifest schema delta** (illustrative):

```toml
[features]
default = ["std-io"]
std-io = []
gpu = ["wgpu"]
win-shell = ["mabda"]

[deps.wgpu]
git = "..."
tag = "..."
optional = true
target = "linux"            # AGNOS userland only

[deps.mabda]
git = "..."
tag = "..."
optional = true
target = "windows"          # win-shell feature gates further
```

**Touched surfaces**:
- `src/frontend/parse_decl.cyr` / cyml parser — schema additions
- `programs/cyrius_deps.cyr` — feature + target filtering before
  resolve
- `programs/cyrius_build.cyr` — `--features` / `--no-default-features`
  CLI surface, target detection passthrough
- Existing consumers (sakshi/patra/sigil/mabda/agnosys/etc.) —
  audit `[deps]` for entries that should become optional once the
  schema is available; consumer migration is opt-in (omitted
  `optional` defaults to required, preserving today's behavior)
- vidya — new `language.toml` entries for `[features]` block +
  optional/target keys; `field_notes/language.toml` for the
  "default = [...] vs --no-default-features" gotcha

**Acceptance bar**:
- Manifest parser round-trips a `[features]` block + optional/target
  keys byte-identical
- `cyrius build --features gpu` resolves wgpu, plain `cyrius build`
  does not
- `target = "windows"` deps skip resolution on aarch64-linux host
- Pre-existing consumer manifests (no `[features]`, no `optional`)
  build byte-identical to v6.2.x
- One vidya entry per axis (feature gate, target gate, combined)

**Out of scope for this slot**: feature unification across
transitive deps (Cargo's hardest semantic — defer to v6.4.x or
later if pressure surfaces); per-feature CHANGELOG/version
constraints; cross-package feature exports.

### Slot estimate (v6.3.x)

| Feature | Slots |
|---|---|
| Closures with lexical capture | ~7 |
| Real generic instantiation | ~7 |
| Language-level async/await syntax | ~5 |
| Required vs Optional Dependencies | ~5 |
| Cross-feature integration + tcyr suite | ~3 |
| **Total planned** | **~27** |
| Bug bandwidth | ~10 |
| **Budget** | **~37** |

---

## v6.4.x — ABI + Perf Arc

**Theme**: Class B FFI / wgpu fncall6 ABI fix + register
allocation upgrade + deferred peephole passes.

Held-forward through v5.9.x / v5.10.x / v5.11.x. The
*language-level* ABI work plus the regalloc-gated perf passes
that have been waiting for cross-BB liveness data.

### Class B FFI / wgpu fncall6 ABI fix

Fix Cyrius's `fncall6` vs SysV AMD64 calling convention bug that
mabda's wgpu integration needs. Lands here regardless of where
the mabda fold itself lands (likely already shipped in v6.0.x
clean-slate by this point per the mabda 3.0 GA timing).

### Cross-BB regalloc + liveness pass

Linear-scan register allocator with cross-BB liveness data.
Unlocks three deferred passes that all share the same gate:

- **Copy propagation** — deferred 2026-04-23 v5.6.18/.19. Stack-
  machine IR had no virtual registers for the classical wins;
  regalloc surfaces them. `ir_copyprop_recon` revival.
- **Extended cross-BB dead-store elimination** — deferred same
  date, same gate. Per-BB DSE shipped v5.6.18; cross-BB variant
  needs the liveness-out set per BB that regalloc builds.
  `ir_extdse_recon` revival.
- **Float peephole** (`float.cyr:41`, 5-instruction → 3-byte
  reduction) — worth landing here if bench delta justifies.

### Slot estimate (v6.4.x)

| Cluster | Slots |
|---|---|
| Class B FFI / wgpu fncall6 ABI fix | ~5 |
| Cross-BB regalloc + liveness pass | ~6 |
| Copy propagation revival | ~3 |
| Extended cross-BB DSE | ~3 |
| Float peephole | ~2 |
| Bench-delta evaluation + tcyr coverage | ~2 |
| **Total planned** | **~21** |
| Bug bandwidth | ~10 |
| **Budget** | **~31** |

---

## v6.5.x — Self-Compile Perf-Refactor

**Theme**: dedicated perf cleanup once accumulated growth
surfaces. Middle-late v6.x timing per user direction 2026-05-19:
"compile time can holdover until later in 6.x cycle probably
middle-late".

### Background

v5.11.x review queue (originally captured at v5.x cycle close,
referenced from CHANGELOG [5.11.69])
captured a perf-growth-tax finding: `bench-history.sh` tier-3
shows self_compile **244 ms → 404 ms (+160 ms / +65 %)** between
commits `a17a8de` (2026-04-18, post-v5.10.50) and `f60ec9b2`
(2026-05-18, post-v5.11.63). Growth-tax not regression — cycc
binary grew only +1,072 B over the same window, so the cost is
parse/codegen overhead from feature work (more parser tracking,
more dispatch checks, more cross-arch propagation), not output
bloat.

**v6.x adds its own growth-creating surfaces**: PIE codegen
(v6.1.x), bare-metal + RISC-V rv64 (v6.2.x), language
refinements (v6.3.x), Class B FFI + cross-BB regalloc (v6.4.x).
By v6.5.x the new baseline is established and a dedicated
perf-refactor minor can land without bumping capability work.

### First-step audit

Capture intermediate datapoints via on-quiet-box
`bench-history.sh` runs across the v6.x cycle so the trend has
more than 2 endpoints. Gradual-accretion vs one-patch-dominates
determines whether bisection is even productive (gradual is the
likelier shape given the work mix).

### Slot estimate (v6.5.x)

Open scope at v6.5.x slot entry — depends on the
accumulated-growth shape uncovered during the audit phase.
Target: ~20 planned + 10 bug bandwidth = ~30 budget. Could flex
to 40+ if the perf-refactor surface is wider than expected.

---

## What comes after v6.x

v7.x scope is open. Two known commitments per CLAUDE.md "Version
lives in `VERSION` + `--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
  Future major bumps run `version-bump.sh` and ship; no rename,
  no downstream sweep, no vidya `cc?` residue.
- **build/cc3 drops at v7.0.0** per the prior-major-seed
  retirement policy (cc3 stays through v6.x as the
  v5.0.0-era historical anchor; retires when v6.x → v7.x bump
  removes the legacy back-compat surface).

Beyond that, v7.x is open territory. Likely candidates: more
language refinements based on consumer pressure from v6.x ship;
toolchain improvements (LSP / formatter / linter evolution);
agnos v2.0 alignment if AGNOS's roadmap creates pull.
