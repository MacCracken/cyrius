# Cyrius Development Roadmap

For completed work, see [completed-phases.md](completed-phases.md).
For detailed changes, see [CHANGELOG.md](../../CHANGELOG.md).


## v5.3.x / v5.4.x / v5.5.x / v5.6.x / v5.7.x / v5.8.x — shipped

All v5.3.x–v5.8.x per-patch detail lives in
[completed-phases.md](completed-phases.md);
[CHANGELOG.md](../../CHANGELOG.md) is the source of truth.

**v5.8.x close** (2026-05-05): 65 patches over 5 days — longest minor
in cyrius history by patch count. Cycle CLOSED at v5.8.65 with the
held-open .66 release-valve retired unused (foldin fallout absorbed
in .65 itself via mid-slot fix-ups). Shipped: slices (6-arc
completion), effect annotations, sum types + exhaustive match,
`Result<T,E>` + `?` operator, allocator vtable, Unicode 17.0.0 (NFC
+ NFD + NFKC + NFKD + categories + casefold; 320,547 conformance
asserts), heap-map monotonic reorganization, lib/ + main_*.cyr
structural refactor, sandhi-pattern stdlib foldin (sakshi / patra /
sigil / vani / yukti / sankoch). cc5 720,928 → 741,048 B
(+20,120 B / +2.79%). check.sh 64 → 65 gates. tcyr 108 → 127.

---

## Long-term considerations (no version pin yet)

Items still without a slot pin after the v5.8.65 audit. Items
that earned a v5.9.x or v5.10.x pin during the audit have moved
to those sections; what remains here is genuinely waiting on a
trigger condition.

### `.gnu.hash` for shared-object emission

**Status**: deferred 2026-04-24 at v5.6.38 (during the slot's
verify-premise check). `.so` emission works correctly today
with the SysV `.hash` table (nbucket=1; chain walk does pure
strcmp per glibc `dl-lookup.c`). `.gnu.hash` is an optimization
that uses a Bloom filter pre-check to skip strcmp on misses;
modern linkers prefer it.

**Why deferred**: cyrius has zero current `.so` consumers
(sigil / mabda / yukti / kybernet all ship as static libraries
or source bundles). The optimization is purely speculative for
hypothetical future use. `.hash` works fine for the
small-symbol-count libraries cyrius emits today.

**Revisit when**: any cyrius consumer pins on `.so` output
and reports a measurable lookup-time cost from the linear
chain walk. At that point, `.gnu.hash` migration is a slot
that drops the SysV `.hash` table entirely (modern loaders
require only `.gnu.hash` if it's present).

**Reference for the future implementer**: glibc
`elf/dl-lookup.c::do_lookup_x` is the consumer side; the
Bloom filter format is documented in
`https://flapenguin.me/elf-dt-gnu-hash` (tutorial) +
`elf/dl-hash.h` in glibc (the hash function itself —
single-precedent definition for the format).

### Copy propagation

**Status**: deferred 2026-04-23 after v5.6.18 + v5.6.19 recons.

**Why deferred**: cyrius's stack-machine IR has no abundant virtual
registers to fold copies through. Every binary op shuttles values
through fixed RAX/RCX positions — there are no `add y, z` → `add
x, z` rewrites to perform. The classical copy-prop wins simply
don't translate.

**Recon data**:
- v5.6.18: 110 raw `LOAD_LOCAL(x), STORE_LOCAL(y)` patterns on
  cc5 self-compile.
- v5.6.19: 18 actual rewrites that survive per-BB invalidation
  through STOREs/CALLs/&local. Direct savings: 0 B (LOAD-for-LOAD
  is byte-equal). Cascade-target dead stores newly orphaned by
  the rewrites: **1**.
- Pre-set gate (in v5.6.18 entry): "Bails if cascade adds < 5 new
  dead stores." 1 < 5 → bail.

**When to revisit**: after v5.6.19 linear-scan regalloc lands.
With cross-BB liveness data and actual virtual registers, copy
chains can span BBs and the cascade math changes — copy-prop
might earn its keep alongside register-renaming opportunities
the regalloc surfaces.

### Parser-to-emit named-op refactor (path A) — pinned to v5.10.x

**Pinned 2026-05-05 at v5.8.65 close.** RISC-V landing as the
4th backend in v5.10.x triggers the path-A precondition #1
(`_TARGET_CX == 0 && _TARGET_RISCV == 0` chains become
unwieldy). Full scope and per-backend impact lives in the
[v5.10.x section](#v510x--bare-metal-arc-agnos-kernel--risc-v-rv64).
Reference: [`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md).

### Extended dead-store elimination (cross-BB)

**Status**: deferred 2026-04-23 after v5.6.19 recon.

**Why deferred**: v5.6.18 ships the per-BB "STORE_LOCAL(x), [no
read], STORE_LOCAL(x)" pattern (15 kills). The natural extension
— "STORE_LOCAL(x) never read till function exit" — needs cross-BB
liveness to be safe. Cyrius doesn't have cross-BB liveness yet.

**Recon data**:
- v5.6.19: a naive "scan to BB terminator" version finds 2,409
  candidates — but most are spurious because they ignore that
  JMP/JCC/JMP_BACK flow to a successor BB where the local IS
  read.
- Tightening to RET/EPILOGUE-terminated BBs only: **0**
  candidates. By the time you're at a function-return BB, all
  upstream stores have already been read into the return path.
- Per the gate (same as copy-prop): 0 < 5 → bail.

**When to revisit**: same as copy-prop — after v5.6.19 regalloc
lands cross-BB liveness. With a proper liveness-out set per BB,
extended-DSE can safely catch genuine "computed-but-never-used"
locals.

### Why we tried both at v5.6.19 and bailed

Both passes share a common dependency: cross-BB data-flow analysis.
v5.6.x optimization arc deliberately stayed within per-BB scope
(LASE, const-fold, DCE, DSE) because the cross-BB version of any
of them needs liveness machinery that v5.6.19 regalloc will build.
Trying copy-prop or extended-DSE before regalloc means duplicating
that machinery for one-off use — high LOC for low payoff. Better
to wait for the natural precondition.

The recon work isn't wasted: if/when revisited, the implementation
plan already exists (`ir_copyprop_recon` and `ir_extdse_recon`
prototypes lived in `src/common/ir.cyr` during v5.6.19 evaluation,
and the data structures + gate criteria are documented above).

### Stdlib data-domain distlib carve-out — pinned to v5.9.x

**Pinned 2026-05-05 at v5.8.65 close.** The v5.8.x language-
vocabulary migration (slices / Result / allocators) has rippled
through stdlib, so the carve-out trigger fires. Targets: ~13
data-domain modules (`json`, `toml`, `cyml`, `csv`, `base64`,
`regex`, `math`, `matrix`, `linalg`, `bigint`, `u128`) fold-out
into a `cyrius-data` sibling distlib using the v5.7.0
sandhi-pattern. Bare-metal v5.10.0 benefits from a clean
primitives-only stdlib that doesn't drag the data offshoots into
kernel objects. Full slot scope under the [v5.9.x section](#v59x--niyama-fold--sovereignty-pass-bash--cyrius).

### Heap-map full reorganization (pre-v6.0 hardening pin)

**Status**: pinned 2026-05-05 at v5.8.61 ship as a
**last-minor-before-v6.0** effort. v5.8.61 took the minimum-
blast-radius reorg (str_data relocated to fit the var_enum_id..
preprocess_out gap; ~76 edits) over the full reorganization
(closing all gaps; 800+ edits) per user direction "minimum blast
is probably the safer bet to allow for some potential bumps in
the future without a full restructure ... should be something we
consider as a last minor effort before 6.0".

**The remaining gaps** (post-v5.8.61) — total ~22 MB of unused
heap reserved as documented headroom over the years:
- `0x41A000..0x44A000` (192 KB) — small pad before preprocess_out
- `0xB4A000..0x114A000` (6 MB) — between output_buf and
  struct_ftypes; sized when output_buf was 1 MB and could grow
- `0x115A000..0x11CA000` (450 KB) — between struct_ftypes and
  struct_fnames; v5.7.17 cap-grow sized for further struct cap
  raises
- `0x11DA000..0x128A000` (700 KB) — between struct_fnames and
  fn_names; pad for struct cap raises
- `0x290B000..0x368C000` (13.5 MB) — **TS frontend functional
  reservation**; used in `--lex-ts` / `--parse-ts` modes only.
  This gap is NOT a candidate for closure unless TS frontend is
  retired; flag as DO-NOT-CLOSE.

**Closeable**: 8.4 MB across 4 gaps (excluding the TS reservation).

**Scope estimate** (per the v5.8.61 audit):
- ~200 references to shift across struct_*/fn_*/ir/fixup/tok
  region offsets
- ~750 references to relocate scratch state at
  `0x18C100..0x1A6018` if the band consolidates
- Total: 800-1000 edits across 20+ source files
- Two-step bootstrap audit at byte-identity criticality

**Trigger conditions** (any one):
1. **Pre-v6.0 closeout** — last v5.x minor before the v5→v6
   binary rename (`cc5` → `cyc`) absorbs this as the "tighten
   everything" pass. v5.9.x is consumed by niyama fold +
   sovereignty pass; v5.10.x by bare-metal + RISC-V; this
   likely lands at v5.11.x or whatever the final v5.x minor
   is before the v6.0.0 rename.
2. **A region cap pressure** that would benefit from the closed
   gap — e.g., output_buf hitting 6 MB would naturally consume
   the gap to struct_ftypes.
3. **A consumer-facing slowdown** traceable to the heap layout
   (page fault patterns, mmap overhead) — unlikely but possible.

**Why deferred to pre-v6.0**: v5.8.61's minimum reorg fixes the
actual non-monotonicity defect from v5.8.59. The remaining gaps
are documented headroom. Closing them is a one-time mechanical
cost that's worth doing exactly once, ideally aligned with a
larger restructure rather than mid-cycle.

**Reference**: full audit data in v5.8.61 CHANGELOG entry +
`tests/heapmap.sh` output (84 regions documented).

---

## Sigil 3.0 enablers — remaining

Downstream `sigil` items the Cyrius toolchain still owes. Shipped
enablers (`ct_select` v5.3.2, `mulh64` v5.3.3, `secret var` v5.3.5,
`lib/keccak.cyr` v5.4.15, SSE m128 alignment fix v5.5.21 unblocking
AES-NI, fixup cap raise v5.5.37 unblocking sigil 3.0 parallel batch)
are in CHANGELOG. **Sigil 3.0 shipped 2026-05-01** — toolchain side
unblocked end-to-end; X25519 (if/when needed) is a sigil-internal
addition with no remaining cyrius-side prereqs. Pure-Cyrius TLS work
absorbed into sandhi at v5.7.0 fold; section retained for shipped-
enabler audit trail.





## v5.8.x — Held items + deferred (carried forward from v5.8.x close)

The v5.8.x cycle (CLOSED 2026-05-05; 65 patches) shipped detail
moved to [completed-phases.md](completed-phases.md) at v5.8.65 close.
What remains here is forward-looking: items not pinned to a slot
during v5.8.x that may surface in v5.9.x or later.

### Held items (surfacing-ask only; not pinned, no slot consumed)

- **`cyim` regex pattern parse error** (mabda C6) — pin when a
  cyim consumer hits it concretely. (Note: a regex-lib
  scaffold may already exist user-side; defer until cyim
  surfaces specific use case.)
- **`ESTORESTACKPARM` cx >6 args** (audit §4) — pin when a cx
  consumer surfaces a 7+-arg fn. cx backend stub returns 0
  with `# TODO: >6 args` comment at `src/backend/cx/emit.cyr:385`.
- **`float.cyr:41` peephole pattern** (audit §4) — pin when
  measured to matter. 5-instruction sequence `push rax;
  movabs rax, 0x7FFF...; mov rcx, rax; pop rax; and rax, rcx`
  may reduce to 3 bytes; preflight with bench delta.

### Deferred to v5.10.x or later

- **Class B FFI/wgpu fncall6 ABI** (mabda B1/B2). Mabda-only
  blast radius today; complex root-cause (ABI bug in Cyrius's
  fncall6 vs SysV AMD64 calling convention). Pairs naturally
  with v5.10.x's bare-metal / RISC-V cycle when ABI invariants
  get touched anyway.

---


## v5.9.x — niyama fold + sovereignty pass (bash → cyrius)

**Theme**: clean-cut maintenance minor. Two work streams:

1. **niyama fold-in** (v5.9.0) — vendor `niyama/dist/niyama.cyr`
   byte-identical into `lib/niyama.cyr` once niyama hits v1.0
   fold-ready bar (5 engines: bre / re2 / pcre / fuzzy / vim).
   Same sandhi-pattern mechanics as v5.7.0 (sandhi) and v5.8.65
   (sakshi/patra/sigil/vani/yukti/sankoch). niyama upstream is
   v0.1.0 scaffold as of 2026-05-03; engine work begins at M1
   (POSIX BRE → v0.2.0). v5.9.0 fold conditional on niyama
   reaching v1.0 — if it slips, the fold cascades to a v5.9.x
   patch slot or to v5.10.x. Bare-metal scope is no longer
   coupled here (moved to v5.10.x at v5.8.x close).

2. **Sovereignty pass — bash-toolchain → cyrius conversion**
   (v5.9.0 → v5.9.x). Forward-pinned 2026-05-04 at v5.8.58
   release-valve audit. ~8,500 LOC across ~75 files. Sized for
   a multi-slot cycle.

### Sovereignty pass scope (forward-pinned 2026-05-04)

Inventory (LOC + priority):

| Target | LOC | Effort | Priority |
|---|---|---|---|
| `tests/regression-*.sh` (60 scripts) | 6,679 | Large (batch by template) | Med-high — every CI run touches these |
| `scripts/cyrius-init.sh` | 1,021 | Med-large | Med — project scaffolder; mostly heredoc templates |
| `scripts/cyriusly` | 349 | Med (stays partial bash) | Med — version manager |
| `scripts/cyrius-port.sh` | ~400 | Med | Med — Rust→cyrius migration tool |
| `scripts/check.sh` | 200 | Small-Med | High — central audit dispatcher |
| `scripts/lib/audit-walk.sh` | ~80 | Small | Med — shared audit helper |
| `scripts/version-bump.sh` | 80 | Small | Med — runs every release |
| `scripts/cyrius-repl.sh` | 98 | Small | Low |
| `tests/heapmap.sh` | ~60 | Small | Med — heap-map auditor |
| `benches/bench_capacity_overhead.sh` | 75 | Small | Low |
| `scripts/cyrius-watch.sh` + `bench-history.sh` + `release-lib.sh` + `mac-{diagnose,selfhost}.sh` + `ci.sh` | ~250 | Small | Low |

**Total convertible bash: ~8,500 LOC.** v5.9.x slot map (pinned
at cycle entry):

- **v5.9.0** ✅ — **niyama fold-in shipped 2026-05-06**. niyama
  1.0.1 `dist/niyama.cyr` (6,664 lines) vendored byte-identical
  as `lib/niyama.cyr`. niyama ADR 0011 status: **Triggered:
  2026-05-06 via cyrius v5.9.0**. cc5 unchanged at 741,048 B
  (no heap-shape change; foldin is `lib/` content only).
  api-surface snapshot regenerated (2,725 → 2,760 public fns;
  +35 non-breaking). 65/65 check.sh; self-host two-step
  byte-identical. Sovereignty pass kickoff items moved forward
  to v5.9.1.
- **v5.9.1** ✅ — **sovereignty pass kickoff shipped 2026-05-06**.
  `scripts/check.sh` (743 LOC bash → 30-line shim + 700-line
  cyrius `programs/check.cyr`); fmt/lint walk logic ported into
  new stdlib module `lib/audit_walk.cyr` (77 → 78). Premise-check
  finding: roadmap had check.sh at 200 LOC; empirical was 743
  (3.7× pin). audit-walk.sh stayed bash because it has a second
  consumer (bash `scripts/cyrius` dispatcher, queued for v5.9.5)
  — slot scope-corrected to check.sh-only at entry. cc5
  unchanged (741,048 B); 65/65 check.sh green; api-surface
  snapshot regenerated 2,760 → 2,763 (+3 non-breaking).
- **v5.9.2-v5.9.4** — sovereignty pass: `tests/regression-*.sh`
  batch conversion (60 scripts, 6,679 LOC). Templated — group
  by category (aarch64-cross-tests, lint-tests, syscall-tests,
  etc.). Each slot ships ~15 conversions + the conversion
  template if applicable.
- **v5.9.5** — sovereignty pass: `scripts/cyriusly` (349 LOC) +
  `scripts/cyrius-init.sh` (1,021 LOC heredoc-heavy) +
  `cyrius-port.sh`. The two project-scaffolder scripts are
  mostly heredoc templates — converting requires designing a
  templating facility OR keeping the heredocs as data-files
  read at runtime.
- **v5.9.6** — sovereignty pass: small utilities batch
  (`version-bump.sh`, `cyrius-repl.sh`, `cyrius-watch.sh`,
  `bench-history.sh`, `release-lib.sh`, `tests/heapmap.sh`,
  `benches/bench_capacity_overhead.sh`).
- **v5.9.7+** — release-valve + closeout per CLAUDE.md 11-step
  protocol.

**KEEP-as-bash (intrinsic; sovereignty-allowed):**
- `bootstrap/bootstrap.sh` (88 LOC) + `bootstrap/verify.sh`
  (45 LOC) — runs before cyrius exists.
- `scripts/install.sh` (575 LOC) — bootstrap-from-zero path;
  cyrius binary may not yet exist.
- `scripts/cyrius` shim (30 LOC) — PATH-discovery wrapper.
- `programs/dlopen-helper.c` — explicit ABI shim per sovereignty
  pin (binds host glibc).
- `editors/neovim.lua` + `editors/vscode/extension.js` —
  host-IDE-side; can't port (Neovim runs Lua, VS Code runs JS).

**ARCHIVED**: `archive/seed/*.rs` + `archive/stages/*.sh`
retained in `archive/` per `feedback_archive_dont_delete_docs`
memory pin.

### v5.9.x — Other pin candidates (folded in from prior unpinned)

These items have triggers that fire in v5.9.x — moved here from
the previously unpinned/long-term sections:

- **Stdlib data-domain distlib carve-out** (long-term review at
  v5.8.65 close): trigger was "post-v5.8.41 closeout, once
  language-vocabulary migration has rippled through stdlib."
  That precondition holds. v5.9.x is the natural fit because
  the AGNOS bare-metal target at v5.10.x will want a clean
  primitives-only stdlib (no data-domain modules pulled in).
  Whether a separate v5.9.x slot or carried into v5.10.x kernel
  prep: **pin at v5.9.0 cycle entry** with empirical sizing.
  Carve-out targets: `json`, `toml`, `cyml`, `csv`, `base64`,
  `regex`, `math`, `matrix`, `linalg`, `bigint`, `u128` (~13
  modules). Sandhi-pattern fold-out into a `cyrius-data` sibling
  distlib (single repo, multi-module dist).

- **Phase 2b-aarch64 struct copy** (`LDRB`/`STRB` loop): x86
  path shipped v5.5.36; aarch64 path pending. **Pin to a
  v5.9.x patch slot** — single-purpose unblock; surfaces
  whenever a consumer cross-builds struct-by-value calls for
  aarch64.

- **`aarch64/fixup.cyr:19` syscall arity warning** (deferred
  from v5.8.53 install-pipeline slot): likely benign lint,
  confirm or fix during a v5.9.x patch cycle.

### v5.9.x — Held forward (no slot consumed; surfaces-on-ask)

These remain unpinned long-term; promote to slot when a consumer
concretely surfaces:

- **LSP `textDocument/semanticTokens/full`** — earns slot when
  an editor's textmate grammar can't satisfy a token-coloring
  request.
- **LSP `textDocument/references`** — easy add on top of
  v5.7.39's symbol-table infrastructure (~80 LOC). Claims slot
  when a downstream consumer asks.
- **TS test harness program** (option E from v5.7.37) — single
  `programs/ts_test_runner.cyr` consuming both internal-symbol
  fn dispatch and TS fixture files. v5.7.37 group-level
  consolidation is sufficient until a downstream consumer
  surfaces a test pattern that doesn't fit either current
  shape.

---

## v5.10.x — Bare-metal arc (AGNOS kernel) + RISC-V rv64

Two arch-port-style efforts grouped into one minor since both
land at the "no libc, direct hardware / different ABI" layer.
Moved from v5.9.x at v5.8.x close once it became clear v5.9.x
is wholly consumed by the niyama fold + sovereignty pass.

### v5.10.0 — Bare-metal / AGNOS kernel target

Bare-metal output (no libc, no syscalls, direct hardware).
AGNOS kernel is the concrete consumer. Slid through multiple
minors (v5.7.0 → v5.8.0 → v5.9.0 → **v5.10.0**). Details
pinned closer to landing — rough scope:

- ELF no-libc output format
- interrupt-handler emit conventions
- kernel-mode syscall stubs stripped
- boot pipeline from `scripts/boot.cyr` landed in genesis Phase
  13B (v5.6.29 gate)

Acceptance: AGNOS kernel can be built end-to-end with the
v5.10.0 toolchain; no host-libc symbols leak into the kernel
object.

### v5.10.x — RISC-V rv64 (3-5 sub-patches)

First-class RISC-V 64-bit target. Inherits a frontend-complete
compiler against a clean toolchain UX with the full v5.7.x →
v5.8.x prerequisite chain shipped, including the v5.7.30 +
v5.7.31 aarch64 f64 pair that gives RISC-V a working
f64-on-non-x87 reference.

**RISC-V needs:**

- **New backend module** — `src/backend/riscv64/` with its own
  `emit.cyr`, `jump.cyr`, `fixup.cyr` mirroring x86/aarch64.
- **New stdlib syscall peer** — `lib/syscalls_riscv64_linux.cyr`
  with the Linux rv64 generic-table numbers. Selector in
  `lib/syscalls.cyr` gains an `#ifplat riscv64` arm.
- **New cross-entry** — `src/main_riscv64.cyr` mirroring
  `main_aarch64.cyr`'s arch-include swap.
- **New test runner** — QEMU or real hardware (HiFive Unmatched
  or equivalent) for self-host verification.
- **New CI matrix** — `linux/riscv64` runners via
  qemu-user-static, analogous to the aarch64 cross-test flow.
- **ABI** — RISC-V Linux ELF psABI (different register names:
  `a0–a7` for args, `sp` for stack; use `s0` for parity with
  aarch64's `x29`).

**Acceptance gates:**

1. Cross-compiler (`build/cc5_riscv64`) emits valid rv64 ELF
   that `file(1)` identifies correctly.
2. Single-syscall "exit 42" probe runs under
   `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. `regression.tcyr` 102/102 via QEMU cross-test.
5. Native self-host byte-identical on real rv64 hardware
   (hardware-gated like the aarch64 ssh-pi check).
6. Tarball includes `cc5_riscv64` alongside `cc5_aarch64`.
7. `[release]` table in `cyrius.cyml` gets a `cross_bins` entry
   for `cc5_riscv64`.

### v5.10.x — Triggered prereq pin

- **Parser-to-emit named-op refactor (path A)** — pinned to
  v5.10.x because RISC-V landing as the 4th backend triggers
  the prior long-term pin's condition #1 ("RISC-V lands and
  adds 4th backend, making path B's `_TARGET_CX == 0 &&
  _TARGET_RISCV == 0` chains unwieldy at every site"). Scope:
  ~10 abstract ops × 4 backends = 40 fn definitions +
  parse_*.cyr rewrites. Multi-session real engineering. Pin at
  v5.10.0 cycle entry; sequence before RISC-V backend
  implementation if prudent (RISC-V starts with the named-op
  interface from day one — cleanest path). Audit doc:
  [`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md).

Deliberately NOT bundling other items into v5.10.x — bare-metal
+ RISC-V are plenty of work. Bare-metal (v5.10.0) lands first;
RISC-V picks up the rest of the v5.10.x range.

---

## v5.x — Platform Targets

Each platform is one minor release. cc5 backend-table dispatch
enables adding new targets without touching the frontend.

| Release | Platform | Format | Status |
|---------|----------|--------|--------|
| **v5.1.0** | macOS x86_64 | Mach-O | **Done** (narrow-scope) |
| **v5.3.0–v5.3.18** | macOS aarch64 | Mach-O | **Done** (narrow-scope); broad-scope gate-fixture repaired v5.6.33 |
| **v5.4.2–v5.4.8** | Windows x86_64 (PE foundation) | PE/COFF | **Done** — hello-world end-to-end on real Win11 (older build) |
| **v5.5.0–v5.5.10** | Windows x86_64 (full PE + native self-host) | PE/COFF | **Done** (narrow-scope byte-identity green at v5.5.10); broad-scope gate-fixture repaired v5.6.36 |
| **v5.5.11–v5.5.17** | macOS aarch64 libSystem + argv | Mach-O | **Done** — v5.5.13–v5.5.17 broad-scope verified on ecb |
| **v5.5.18–v5.5.22** | aarch64 Linux shakedown + SSE alignment | ELF | **Done** — multi-thread + contended mutex on real Pi 4 |
| **v5.5.34** | fdlopen foreign-dlopen completion | ELF | **Done** — 40/40 round-trip `dlopen("libc.so.6")+dlsym("getpid")` |
| **v5.5.35** | Windows PE .reloc + 32-bit ASLR | PE/COFF | **Done** — `DYNAMIC_BASE` + HIGH_ENTROPY_VA enabled v5.6.31 |
| **v5.5.36** | Windows Win64 ABI completion | PE/COFF | **Done** — struct-return via hidden RCX retptr + __chkstk via R11 + variadic float dup |
| **v5.10.x** | RISC-V rv64 | ELF | **Moved v5.9.x → v5.10.x at v5.8.x close** — v5.9.x consumed by niyama fold + bash-sovereignty pass; RISC-V keeps its pairing with bare-metal AGNOS scope (both "no libc / new ABI" arch-port work). |
| **v5.10.0** | Bare-metal | ELF (no-libc) | Queued — AGNOS kernel target. Slid v5.7.0 → v5.8.0 → v5.9.0 → v5.10.0 across multiple cycles. |
| ~~**v5.9.0–5.9.5**~~ | ~~Pure-cyrius TLS 1.3~~ | — | **Removed from roadmap 2026-04-24** — pure-Cyrius TLS work outside Cyrius's compiler/stdlib scope per sandhi scope-absorption decision; `lib/tls.cyr` continues using `libssl.so.3` bridge from stdlib's perspective; canonical home for pure-Cyrius TLS implementation TBD. See v5.9.x slot bullet in *What's next* for details. |

---

## v5.x — Toolchain Quality

Shipped toolchain rows (api-surface + LSP cross-file go-to-def +
cyrlint forward-ref scanner) moved to
[completed-phases.md](completed-phases.md). Remaining
toolchain-quality items are all consumer-trigger-gated and live
in [v5.9.x §Held forward](#v59x--held-forward-no-slot-consumed-surfaces-on-ask):

| Feature | Effort | Status |
|---------|--------|--------|
| LSP `textDocument/semanticTokens/full` | Medium | Held forward — earns slot when an editor's textmate grammar can't satisfy a token-coloring request. ~150 LOC per LSP 3.16 spec. |
| LSP `textDocument/references` | Low-Medium | Held forward — ~80 LOC on top of v5.7.39's symbol-table infrastructure. Claims slot on downstream ask. |
| TS test harness program (option E from v5.7.37) | Medium | Held forward — single `programs/ts_test_runner.cyr` consuming internal-symbol fn dispatch + TS fixture files. v5.7.37 group-level consolidation suffices until a consumer surfaces a pattern outside both shapes. |

---

## v5.x — Language Refinements

The v5.8.x language-vocabulary arc (slices / effect annotations
/ tagged unions + exhaustive match / `Result<T,E>` + `?` /
allocators-as-parameter) shipped end-to-end across slots 10-25
of the v5.8.x cycle; per-feature detail moved to
[completed-phases.md](completed-phases.md).

**Still unpinned / lower priority** (re-eval'd 2026-05-05 at
v5.8.65 close):

| Feature | Effort | Surfacing / votes | Disposition |
|---------|--------|-------------------|-------------|
| Phase 2b-aarch64 struct copy (LDRB/STRB loop) | Medium | x86 shipped v5.5.36; aarch64 path pending | **Pinned to a v5.9.x patch slot** at v5.8.65 close — see [v5.9.x §Other pin candidates](#v59x--other-pin-candidates-folded-in-from-prior-unpinned). |
| Closures capturing variables | High | gotcha #8 — consumers feel the absence | **Watching.** Promote when a consumer concretely blocks on it (vs. lambda-pattern workaround). v5.8.x ADTs make captured-state encoding cleaner. |
| Generics / traits | High | 1 vote (kavach) | **Watching.** Wait for kavach to actively reach for it; speculative implementation pre-need is risk. |
| Hardware 128-bit div-mod | Medium | — | **Stays unpinned.** abaco / sigil currently work around via u128 shifts; not blocking. |
| Phase 3-full varargs (va_arg for structs-by-value + nested) | Medium | Phase 3-min shipped v5.5.36 | **Stays unpinned.** Niche — most consumers use array-of-args pattern instead. |
| cc5 per-block scoping | Medium | — | **Stays unpinned.** Function-scope works for current consumer base; promote when a real refactor surfaces the pain. |
| Incremental compilation | High | — | **Stays unpinned.** Whole-program self-host is fast (<400 ms); incremental adds complexity for cyrius-style projects without proportional payoff. Reconsider when cc5 self-host time crosses ~2 sec. |

---

## Stdlib (76 modules + 1 git dep)

Post-v5.8.65 foldin: sakshi / patra / sigil / vani / yukti / sankoch
vendored byte-identical into `lib/` from their patched tags
(2.2.3 / 1.9.3 / 3.0.1 / 0.9.2 / 2.2.2 / 2.2.4). Only **mabda**
remains in `[deps]` (held at 2.5.0 GA pre-v3.0.0-rc.2 soak;
agnosys transitive). vidya helper relocated to
`programs/vidya.cyr` at v5.8.62 (was lib/-resident; no API
consumers in the ecosystem). Canonical view of the table is
[`README.md`](../../README.md#standard-library-76-modules--1-git-dep)
— this entry kept brief to avoid drift.

| Category | Notes |
|----------|---------|
| Core | string, fmt, alloc, io, vec, str, args, fnptr, flags |
| Types | tagged (Option), result (Result + ? at v5.8.28-.32), hashmap, hashmap_fast, trait, assert, bounds |
| Unicode | unicode/categories, casefold, normalize (NFC/NFD/NFKC/NFKD; v5.8.49-.52 + .60), _decode |
| Network | net, http, ws, ws_server, tls, **sandhi** (HTTP/2 + RPC; folded v5.7.0) |
| Audio | **vani** (ALSA PCM + ring buffer + mixer; folded v5.8.0, refolded v5.8.65) |
| Folded sibling distlibs | **sakshi** (tracing), **patra** (storage), **sigil** (security), **yukti** (hardware enumeration), **sankoch** (compression) — all sandhi-pattern, v5.8.65 |
| Live deps | mabda (GPU), agnosys (transitive) — held at v5.8.65 |

---

## Platform Status

Moved to [`docs/platform-status.md`](../platform-status.md) at
v5.8.x cycle close. That file is the canonical "what works now"
snapshot; this section retained as a back-link only. Refresh
target: every closeout pass (CLAUDE.md step 11).

---

## Ecosystem

Moved to [`docs/ecosystem.md`](../ecosystem.md) at v5.8.x cycle
close. That file is the canonical state board for downstream
consumer repos + folded-in distlibs + live deps. Refresh target:
every closeout pass (CLAUDE.md step 11), plus whenever a port
lands or a new repo joins.

---

## Future 6.0

v6.0.0 is the major-version bump after the v5.x platform-targets
arc closes. Scope is **refactoring and cleanup** that's been
accumulating debt across the v5.x line and that's risky or
disruptive to land mid-minor (rename, dead-code removal,
consolidation of `_TARGET_*` shim layers). Major bump gives
downstreams an explicit signal to re-pin and re-verify rather
than discovering breakage at random patch boundaries.

### v6.0.0 — first item: rename `cc5` → `cyc`

The `cc5` name was meaningful when the major-version digit
identified the compiler-line lineage (`cc` for cyrius compiler,
`5` for the cc5-era IR / module split that landed in v5.0.0).
With `cc5 --version` reporting the actual semver since v5.0.x —
and version baked into the build output — the trailing `5`
duplicates information now carried in `VERSION`, every binary's
`--version`, every `cyrius.cyml` `cyrius` field, and every
release tag.

**Rename:** `cc5` → `cyc` (canonical name) everywhere:
- `build/cc5` → `build/cyc`
- `build/cc5_aarch64` → `build/cyc_aarch64`
- `~/.cyrius/bin/cc5` → `~/.cyrius/bin/cyc` (install.sh, deps.cyr)
- `src/main.cyr` self-name in `cyc --version` output
- All `bootstrap/`, `scripts/`, `cbt/`, `programs/` references
- All `tests/`, `benches/`, `fuzz/` references
- All vidya `cc?` mentions (closeout-pass step 8 covers the
  ongoing per-minor refresh; v6.0.0 is the bulk pass)
- Downstream `cyrius.cyml` files don't change (`cyrius` build
  field already names the tool, not the binary), but downstream
  CI scripts that hard-coded `cc5` (e.g. yukti's
  `retest-aarch64.sh`) need a sweep — track which projects via
  the v6.0.0 closeout downstream-check step.
- Bootstrap chain comment chain: `cyrc → bridge → cc5` becomes
  `cyrc → bridge → cyc`. The seed binary path doesn't change
  (`bootstrap/asm` is an assembler, not the compiler).

**Compatibility:** v6.0.0 install ships a `cc5` symlink → `cyc`
for one minor (v6.0.x) so downstream toolchain scripts have a
window to migrate. v6.1.0 drops the symlink.

**Why a major bump:**
- Renaming the binary breaks every shell script and CI that
  invokes `cc5` directly. SemVer's whole point.
- Bootstrap chain touch — even for a rename — deserves the
  ceremony of a major.
- Bundles cleanly with the rest of the v6.0.0 cleanup so
  downstreams take one breakage hit, not many.

**Why `cyc` and not `cc6` / `cc7` / etc. — clean break, one-time
cost, forevermore source-of-truth:**
- The `cc<N>` scheme couples the binary name to the major
  version. Every major bump (v6 → v7 → v8 …) would otherwise
  trigger another rename + downstream churn. We did this once
  already (cc3 → cc5 with v5.0.0 — see CHANGELOG, vidya, and
  every `cc3 4.8.5` residue we're still cleaning up).
- `cyc` is **version-agnostic, permanently**. The binary stays
  `cyc` from v6.0.0 onward — through v7, v8, v∞. Version
  surfaces only via `cyc --version` and the `VERSION` file.
  Future major bumps run `version-bump.sh` and ship; no
  rename, no downstream sweep, no vidya `cc?` residue.
- **Anti-pattern that this rename explicitly forecloses:**
  the temptation at v7.0.0 to "match the cc3 → cc5 → cyc → cc7
  cadence." Don't. v6.0.0 is the *last* name change the
  compiler binary ever takes. If a future session is reading
  this and wondering whether to bump `cyc` → `cc7` at v7.0.0
  or `cc8` at v8.0.0 or whatever — the answer is **no**. The
  whole point of paying the v6.0.0 rename cost is that the
  pattern stops there. `VERSION` file + `cyc --version` output
  are the only sources of truth for "what version is this?"
- **Same rule applies to every other binary in the toolchain.**
  `cyrc` (bootstrap compiler) stays `cyrc`. `asm` stays `asm`.
  `cyrius` (build tool) stays `cyrius`. `cyrld` (linker) stays
  `cyrld`. `cyrfmt` / `cyrlint` / `cyrdoc` / `cyrc` / `ark`
  stay as-is. No version digits anywhere in the binary
  name-space, ever. This is now a Key Principle in CLAUDE.md.

### v6.0.0 — accompanying refactor / cleanup

Items that have been queued or accreted across v5.x and that
benefit from landing in the rename pass rather than as scattered
patches:

- **Dead-code sweep.** Every `sh scripts/check.sh` run since
  v5.4.x has reported unreachable fns in cc5 itself. v5.5.40
  removed `EMITPE_OBJ` and `PARSE_ASSIGN`. Remaining candidates
  include `ELVRLOAD`/`ELVRSTORE`, `CLASSIFY_CF`/`CF_TARGET`, IR
  scaffolding `IR_NODE_FL`, `IR_BB_*`, `IR_EDGE_*`, `ir_emit2`,
  `ir_lower_all`, `ir_apply_lase`, `ir_dead_block_elim`,
  `_macho_wstr_pad`, `SYSV_HASH` (if v5.6.28 doesn't re-wire it).
  Audit which are speculative scaffolding for future work vs
  genuinely dead, and delete the latter.
- **`_TARGET_*` flag consolidation.** `_TARGET_MACHO`,
  `_TARGET_PE`, `CYRIUS_TARGET_LINUX/WIN/MACOS`,
  `_AARCH64_BACKEND`, plus per-arch `#ifdef CYRIUS_ARCH_{X86,
  AARCH64}` and per-arch `EWRITE_PE` / `_pe_pending_imp_add` /
  `EDISP32` shim families. Consolidate into a single backend-
  dispatch table keyed on `(arch, format)`.
- **Bridge-compiler retirement assessment.** `src/bridge.cyr`
  exists to bridge cyrc's feature set to cc5's. With cc5 long
  past cyrc's surface, audit whether bridge can be retired or
  collapsed into cyrc's path.
- **`cc3`-era residue.** Vidya entries, comments in source,
  test fixtures still reference `cc3 4.8.5` and earlier. v5.5.39
  retired `src/cc/` + `src/compiler*.cyr` (3,333 LOC); remaining
  residue is in vidya + docs comments.
- **Heap-map tightening.** v5.5.40 verified 72 regions. Audit
  which are still load-bearing post-optimization-arc; reclaim
  wasted address space; document post-v6.0.0 layout as new
  baseline.
- **Backend module collapse where viable.** `src/backend/x86/`
  and `src/backend/aarch64/` each have parallel `emit.cyr`,
  `jump.cyr`, `fixup.cyr`. Audit which helpers can move to
  `src/backend/common/` without entangling asm-byte tables.
- **`cyrius build --strict` mode** — escalate `undefined
  function` warnings to hard errors through the build wrapper
  (direct `cc5 --strict` shipped v5.4.19).

### v6.0.0 — closeout

Same closeout checklist as every minor (CLAUDE.md §"Closeout
Pass") plus:
- Verify the `cc5` symlink works end-to-end on a clean install
  before tagging. Downstream CI failure on day-one of v6.0.0 is
  exactly the breakage-hit we're trying to avoid.
- Bulk vidya refresh — the rename touches every `cc?` mention,
  not just the version line. Use the closeout's vidya checklist
  as the audit list.

## Public Release (~v7.0) — "Cyrius ONE"

* **Cyrius ONE** — first book, written from Vidya + documentation, published
  alongside the public release (Amazon / Packt). Kicked back from v6 so the
  language surface is stable before the manuscript lands. Exact version TBD
  — lands with whatever version the public release cuts on (current guess: v7).

---

## Principles

- Assembly is the cornerstone
- Own the toolchain — compiler, stdlib, package manager, build system
- No external language dependencies
- Byte-exact testing is the gold standard
- Two-step bootstrap for any heap offset change
- Test after EVERY change, not after the feature is done
- **Never use raw `cat | cc5` for projects** — always `cyrius build`
- **v5.0.0 recommended minimum** — cc5 IR, cyrius.cyml, patra 1.0.0, sankoch 1.2.0
