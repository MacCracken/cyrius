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

Items deferred without a v5.6.x or v5.7.x slot. Add to a future
minor only when the right preconditions land — typically when
v5.6.19 regalloc + cross-BB liveness machinery exists to make a
meaningful version land cleanly.

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

### Parser-to-emit named-op refactor (path A from v5.7.12 inventory)

**Status**: pinned long-term 2026-04-27 after v5.7.12 took
path B (`_TARGET_CX == 0` guards on ~10 sites). The path A
refactor is the right long-term architecture; v5.7.12 ships
the tactical fix without committing to it.

**The problem path A solves**: `parse_*.cyr` directly emits
x86 instruction bytes via `EB(S, 0xNN)` / `E2(S, 0xNNNN)` /
`E3(S, 0xNNNNNN)` calls in shared codepaths. Each backend
(x86, aarch64, cx, future-RISC-V) has to either map those
literal bytes to its own emit (cx already does, but x86 hex
literals aren't CYX opcodes) or guard the site
arch-conditionally. Path B chose the latter; path A would
replace every direct emit with a named abstract op that each
backend implements natively.

**Scope estimate** (per the v5.7.12 inventory at
[`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md)):
- ~10 distinct logical sites at v5.7.11. Each is a 3-12 byte
  x86 sequence that needs a single named op in each backend.
- Roughly: 10 new abstract ops × 3 backends (= 4 with RISC-V)
  = 30-40 fn definitions, plus rewriting the 10 parse_*.cyr
  call sites to use the named ops.
- Multi-session real engineering. Not a wedge.

**Trigger conditions** (any one):

1. **RISC-V (v5.7.26-v5.7.30) lands and adds 4th backend**, making
   path B's `_TARGET_CX == 0 && _TARGET_RISCV == 0` chains
   unwieldy at every site.
2. **2+ new direct-emit sites slip past the static-analysis
   gate** (TBD if a regex-scanner check.sh gate gets added in
   the v5.7.x cycle). If parse_*.cyr drift recurs, path A
   becomes the durable fix.
3. **A bytecode VM consumer surfaces** that needs the cx
   backend to handle ops path B currently no-ops (f64,
   struct return, regalloc). Adding those one at a time to
   cx would expose the same architectural mismatch path A
   solves once.

**Per-backend impact** when path A lands:
- x86 emit: every existing direct-byte sequence in
  `parse_*.cyr` becomes a 1-line wrapper in `backend/x86/emit.cyr`
  (mostly already wrapped — EMOVCA, EADDR, ESUBR, etc.).
  Direct-emit sites in parse_*.cyr replaced with named ops.
  Byte-identity must hold (the new named op emits the same
  bytes the old direct call did).
- aarch64 emit: implements the same named ops with aarch64
  encodings. Many already exist; the new ones map to
  patterns currently handled by `if (_AARCH64_BACKEND == 1)`
  branches (which path B leaves in place).
- cx emit: implements the named ops as CYX bytecode opcodes —
  THIS is where the real semantic work happens. Half the
  v5.7.12 path-B sites are currently no-ops on cx;
  path A forces a real CYX opcode for each (which means
  cxvm interpreter changes too, in lockstep).
- RISC-V emit: starts with the named-op interface from day
  one. Cleanest backend addition path.

**Why deferred**: v5.7.12 needs to STOP THE BLEEDING (cx
output is x86 noise + valid CYX interleaved) on a tractable
budget. Path B does that in ~50 LOC. Committing to path A's
30-40 fn definitions + cxvm coordination + byte-identity
across 3 backends is a different scope category. Defer until
a trigger fires.

**Reference**: full inventory + per-site classification at
`docs/audit/2026-04-27-cx-direct-emit-inventory.md`. When a
trigger fires, the audit doc is the starting point — every
class B/C/D site listed there becomes a named-op design
decision in path A.

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

### Stdlib data-domain distlib carve-out (sibling-repo consolidation)

**Status**: long-term thought captured 2026-05-01 during the
v5.8.x slot-pinning conversation. Not pinned to any minor; revisit
post-v5.8.x when the language vocabulary stabilizes and hisab-
class consumers have ported.

**The idea**: extend the v5.7.0 sandhi-fold precedent (HTTP/RPC
moved out of stdlib into a sibling distlib) across the rest of
the data-domain stdlib modules. Cyrius core retains primitives
(syscalls, alloc, str/string, vec, hashmap, fmt, io, fs); the
"data offshoots" (json, toml, cyml, csv, base64, regex, math,
matrix, linalg, bigint, u128) carve out into a new sibling-
distlib repo. Consumers pull what they need via `[deps.<name>]`:

```
[deps.core]   = "cyrius-core"   (always — language primitives)
[deps.json]   = "cyrius-data"   (modules = ["dist/json.cyr"])
[deps.math]   = "cyrius-data"   (modules = ["dist/math.cyr", "dist/matrix.cyr"])
[deps.regex]  = "cyrius-data"   (modules = ["dist/regex.cyr"])
```

**Why the precedent fits**: sandhi proved the model works (clean-
break fold at minor cut, byte-identical distfile, consumer
adopts `[deps.<name>]` line, stdlib surface trims). Each carve-
out shrinks cyrius's stdlib footprint without changing what
consumers can build with the toolchain. Downstream usage gets
cleaner — projects pull only what they touch instead of
inheriting the kitchen-sink.

**Why deferred (not v5.8.x scope)**: the v5.8.x cycle is already
folding 5 language features forward; adding a 13-module-carve-out
would blow scope. More importantly, the v5.8.x language-
vocabulary work (slices / Result / allocators) WILL touch these
modules' APIs (`json.cyr` parses via `Result<Value, JsonError>`,
`vec_push` takes an allocator). Carving them out before the API
shape stabilizes means re-folding right after — wasted motion.

**Trigger to pin**: post-v5.8.41 closeout, once the language-
vocabulary migration has rippled through stdlib. At that point
each carve-out is a clean lift-and-shift (no API churn imminent).
Likely v5.9.x consideration if the carve-out aligns with bare-
metal needs (kernel target may want NO data-distlib, just
core), or v6.0.0 cleanup if held longer.

**Out of scope for this entry**: the specific repo split (one
big "cyrius-data" sibling vs. multiple narrow ones — `cyrius-
json` / `cyrius-math` / `cyrius-regex`). Pin that decision when
the trigger fires. Sandhi is one repo with `dist/sandhi.cyr` —
multiple-modules-per-distlib pattern works.

**Why `dep.core` matters as a primitive**: separating "language
primitives the compiler needs to see" from "stdlib modules
consumers may opt into" makes bare-metal targets cleaner —
the AGNOS kernel target (v5.9.0) only needs the primitives.
Today there's no clean line; this carve-out draws it.

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
1. **Pre-v6.0 closeout** — last v5.x minor (likely v5.9.x tail or
   a dedicated v5.10.x hardening minor) absorbs this as the
   "tighten everything" pass before the v5→v6 binary rename.
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

### Deferred to v5.9.x or later

- **Class B FFI/wgpu fncall6 ABI** (mabda B1/B2). Mabda-only
  blast radius today; complex root-cause (ABI bug in Cyrius's
  fncall6 vs SysV AMD64 calling convention). Pairs naturally
  with v5.9.x's bare-metal / RISC-V cycle when ABI invariants
  get touched anyway.

---

## v5.9.x — Bare-metal arc (AGNOS kernel) + RISC-V rv64 + sovereignty pass

Three arc-style efforts grouped into one minor:
1. **Bare-metal output** (no libc, direct hardware) for the AGNOS
   kernel. The original v5.9.x theme.
2. **RISC-V rv64 port** — arch port at the "no libc, different ABI"
   layer.
3. **Sovereignty pass** — bash-toolchain conversion to cyrius. Pinned
   forward at v5.8.58 release-valve from the audit findings.

The sovereignty arc was added 2026-05-04 after the v5.8.x cycle
retired Python entirely (`scripts/gen-unicode-data.py` → native
`programs/gen_unicode_data.cyr` at v5.8.57). The remaining sovereignty
debt is bash, not Python — too large to cram into v5.8.x's wind-down,
sized correctly for a v5.9.0 cycle theme.

Original framing carried forward: "Two arch-port-style efforts grouped
into one minor since both land at the 'no libc, direct hardware/
different ABI' layer." Moved from v5.8.x at 2026-05-01 v5.7.49 ship —
v5.8.x became the slices true-completion + language-feature arc
instead (slot-map cascade +6 at v5.8.14 absorbed the deferred §6-§11
work; sub-arc through v5.8.18 = halfway mark); arch-port work needs
its own dedicated cycle.

### v5.9.x — Sovereignty pass scope (forward-pinned 2026-05-04)

Inventory captured at v5.8.58 release-valve audit:

| Target | LOC | Effort | Priority |
|---|---|---|---|
| `tests/regression-*.sh` (60 scripts) | 6,679 | Large (batch by template) | Med-high — every CI run touches these |
| `scripts/cyrius-init.sh` | 1,021 | Med-large | Med — project scaffolder; mostly heredoc templates |
| `scripts/check.sh` | 200 | Small-Med | High — central audit dispatcher |
| `scripts/cyriusly` | 349 | Med (stays partial bash) | Med — version manager |
| `scripts/cyrius-port.sh` | ? | Med | Med — Rust→cyrius migration tool |
| `scripts/cyrius-watch.sh` | 37 | Trivial | Low |
| `scripts/cyrius-repl.sh` | 98 | Small | Low |
| `scripts/version-bump.sh` | 80 | Small | Med — runs every release |
| `scripts/release-lib.sh` | ? | Small | Low — runs once per release |
| `scripts/bench-history.sh` | 50 | Small | Low |
| `scripts/mac-diagnose.sh` + `mac-selfhost.sh` | ? | Small | Low — macOS helpers |
| `scripts/lib/audit-walk.sh` | ? | Small | Med — shared audit helper |
| `scripts/ci.sh` | ? | Small | Low — CI dispatcher |
| `tests/heapmap.sh` | ? | Small | Med — heap-map auditor |
| `benches/bench_capacity_overhead.sh` | 75 | Small | Low |

**Total convertible bash: ~8,500 LOC across ~75 files.** Sized for
a multi-slot cycle.

**KEEP-as-bash (intrinsic; sovereignty-allowed):**
- `bootstrap/bootstrap.sh` (88 LOC) + `bootstrap/verify.sh` (45 LOC) —
  runs before cyrius exists.
- `scripts/install.sh` (575 LOC) — bootstrap-from-zero path can't be
  cyrius (the cyrius binary it installs may not yet exist).
  `--refresh-only` post-install path is portable but the trunk
  stays bash.
- `scripts/cyrius` shim (30 LOC) — PATH-discovery wrapper that finds
  & execs `build/cyrius`. Required to bridge "cyrius not on PATH"
  to the compiled tool.
- `programs/dlopen-helper.c` — explicit ABI shim per sovereignty
  pin (binds host glibc).
- `editors/neovim.lua` + `editors/vscode/extension.js` — host-IDE-
  side; can't port (Neovim runs Lua, VS Code runs JS).

**ARCHIVED (no longer active):**
- `archive/seed/*.rs` (10 Rust files, 240 KB) — original pre-self-
  hosting seed assembler. `archive/stages/*.sh` (6 stage-bootstrap
  scripts, 320 KB). Both retired at commits `d042853 no more rust`
  and `53301cc fixing repo` respectively. Remain in `archive/` for
  historical reference per `feedback_archive_dont_delete_docs`
  memory pin.

Slot map for v5.9.x sovereignty arc TBD — sized at audit, decisions
deferred to v5.9.0 cycle entry.



### v5.9.0 — Bare-metal / AGNOS kernel target + niyama fold-in

**Bare-metal target.** Bare-metal output (no libc, no syscalls,
direct hardware). AGNOS kernel is the concrete consumer. Slid through
multiple minors (was v5.7.0 pre-v5.6.x pin → v5.8.0 → v5.9.0). Details
pinned closer to landing — rough scope: ELF no-libc output format,
interrupt-handler emit conventions, kernel-mode syscall stubs
stripped, boot pipeline from `scripts/boot.cyr` landed in genesis
Phase 13B (v5.6.29 gate).

**niyama fold-in** (pinned 2026-05-03). niyama is the additional-
regex-engine library — bre / re2 / pcre / fuzzy / vim flavors that
extend the existing `lib/regex.cyr` Thompson-NFA engine in stdlib.
Sandhi-pattern fold lifecycle (per niyama ADR 0001 + niyama roadmap
M5 → v1.0): when niyama hits its v1.0 fold-ready bar (all 5 engines
shipped, public surface frozen, ≥2 long-horizon AGNOS-lineage
consumers, security audit, fold ADR drafted), cyrius vendors
`niyama/dist/niyama.cyr` byte-identical as `lib/niyama.cyr` (same
mechanics as the v5.7.0 sandhi fold and the v5.8.39 sandhi v1.1.0
re-fold). niyama-side roadmap at
[`/home/macro/Repos/niyama/docs/development/roadmap.md`](https://github.com/MacCracken/niyama/blob/main/docs/development/roadmap.md);
niyama at v0.1.0 (scaffold) as of 2026-05-03 — engine work begins
at M1 (POSIX BRE → v0.2.0). niyama's own roadmap previously listed
"Speculative cyrius fold target: 5.8.0" — that target was
overoptimistic; v5.8.x consumed by Phase 2 (Result+? + Allocators
sub-suites + Phase 3 polish). v5.9.0 is the new realistic fold
target conditional on niyama hitting v1.0 first.

**Fold mechanics** (per the v5.7.0 sandhi + v5.8.39 sandhi-v1.1.0
precedent):
- niyama upstream ships v1.0 → `dist/niyama.cyr` regenerated via
  `cyrius distlib`.
- cyrius v5.9.0 slot does the fold: `cp niyama/dist/niyama.cyr
  cyrius/lib/niyama.cyr` + snapshot refresh per ping-pong protection
  + verify cyrius-side consumers (none yet — niyama would be a
  fresh stdlib add) + downstream propagation via `cyrius deps` on
  next resolution.
- Roadmap entry's bare-metal scope is the larger v5.9.0 deliverable;
  niyama fold rides as a smaller bundled item. If niyama hasn't hit
  v1.0 by the v5.9.0 cut, the fold cascades to a later v5.9.x patch
  slot or v5.10.x — bare-metal AGNOS kernel work doesn't block on
  it.

### v5.9.x — RISC-V rv64 (3-5 sub-patches)

First-class RISC-V 64-bit target. Moved from v5.8.x at 2026-05-01
along with bare-metal — pairs naturally with the bare-metal scope
since both deal with new ABI / non-libc runtime considerations and
both are arch-port-shaped efforts.

Inherits a frontend-complete compiler against a clean toolchain UX
with the full v5.7.x → v5.8.x prerequisite chain shipped, including
the v5.7.30 + v5.7.31 aarch64 f64 pair that gives RISC-V a working
f64-on-non-x87 reference (likely reuse the polyfill shape — RISC-V
has hardware f64 in the F/D extensions but the polynomial reuses
cleanly).

**RISC-V needs:**

- **New backend module** — `src/backend/riscv64/` with its own
  `emit.cyr`, `jump.cyr`, `fixup.cyr` mirroring x86/aarch64.
- **New stdlib syscall peer** — `lib/syscalls_riscv64_linux.cyr` with
  the Linux rv64 generic-table numbers (different from aarch64's even
  though both use the generic table — numbers match aarch64 for most
  syscalls but rv64 drops `renameat`, `link`, `unlink` which means
  the at-family wrappers need review). Selector in
  `lib/syscalls.cyr` gains an `#ifplat riscv64` arm (the v5.4.19
  directive extends naturally here).
- **New cross-entry** — `src/main_riscv64.cyr` mirroring
  `main_aarch64.cyr`'s arch-include swap.
- **New test runner** — QEMU or real hardware (HiFive Unmatched or
  equivalent) for self-host verification.
- **New CI matrix** — `linux/riscv64` runners via qemu-user-static,
  analogous to the aarch64 cross-test flow.
- **ABI** — RISC-V Linux ELF psABI (different register names: `a0–a7`
  for args, `sp` for stack, no frame pointer by default but we'll
  use `s0` for parity with aarch64's `x29`).

**Acceptance gates:**

1. Cross-compiler (`build/cc5_riscv64`) emits valid rv64 ELF that
   `file(1)` identifies correctly.
2. A single-syscall "exit 42" probe runs under `qemu-riscv64-static`
   and exits 42.
3. Hello-world probe via `sys_write` + `sys_exit` runs under QEMU.
4. `regression.tcyr` 102/102 via QEMU cross-test.
5. Native self-host byte-identical on real rv64 hardware (not QEMU
   — hardware-gated like the aarch64 ssh-pi check).
6. Tarball includes `cc5_riscv64` alongside `cc5_aarch64`.
7. `[release]` table in `cyrius.cyml` gets a `cross_bins` entry for
   `cc5_riscv64`.

Deliberately NOT bundling other items into the v5.9.x RISC-V arc —
a new architecture port is plenty of work on its own. Bare-metal
(v5.9.0) lands first; RISC-V picks up the rest of the v5.9.x range.

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
| **v5.9.x** | RISC-V rv64 | ELF | **Moved from v5.8.x at v5.7.49 ship** — paired with v5.9.0 bare-metal AGNOS scope (both "no libc / new ABI" arch-port work); v5.8.x reframed as bug-fix/optimization minor. |
| **v5.9.0** | Bare-metal | ELF (no-libc) | Queued — AGNOS kernel target |
| ~~**v5.9.0–5.9.5**~~ | ~~Pure-cyrius TLS 1.3~~ | — | **Removed from roadmap 2026-04-24** — pure-Cyrius TLS work outside Cyrius's compiler/stdlib scope per sandhi scope-absorption decision; `lib/tls.cyr` continues using `libssl.so.3` bridge from stdlib's perspective; canonical home for pure-Cyrius TLS implementation TBD. See v5.9.x slot bullet in *What's next* for details. |

---

## v5.x — Toolchain Quality

| Feature | Effort | Status / Description |
|---------|--------|----------------------|
| `cyrius api-surface` | Medium | **✅ Shipped v5.7.33.** Snapshot-based public API diff. Scans `fn` declarations, tracks `mod::name/arity`, diffs against committed snapshot. Catches breaking removals/renames, allows additions. Pure-cyrius impl in `programs/api_surface.cyr`; pattern from agnosys `scripts/check-api-surface.sh`. |
| `cyrius api-surface --update` | Low | **✅ Shipped v5.7.33.** Regenerate snapshot after intentional API bump. |
| CI template with api-surface gate | Low | **✅ Shipped v5.7.33** (gate 4ao in cyrius's own check.sh; downstream consumers add their own copy). |
| LSP cross-file resolution + go-to-def | Medium | **✅ Shipped v5.7.39.** Symbol indexer (parallel-array table cap 4096), recursive include walker, `textDocument/definition`, `textDocument/documentSymbol`. cyrius-lsp promoted to release binary. Cross-file resolution verified by `tests/regression-lsp-definition.sh` (5 sub-tests including includer→included resolution). |
| LSP `textDocument/semanticTokens/full` | Medium | **Pinned long-term 2026-04-30 at v5.7.39 ship.** Deferred from v5.7.39's "polish" framing — go-to-def landed as the headline; semanticTokens earns its own slot when a real consumer surfaces a token-coloring request the editor's textmate grammar can't satisfy. Adds a mini-lexer + delta-encoded token array per the LSP 3.16 spec. ~150 LOC. |
| LSP `textDocument/references` | Low-Medium | **Pinned long-term 2026-04-30 at v5.7.39 ship.** Easy add on top of v5.7.39's symbol-table infrastructure — needs an inverted index (name → use-sites). ~80 LOC. Claims a slot when a downstream consumer asks. |
| cyrlint forward-ref scanner — string-literal awareness | Low-Medium | **✅ Shipped v5.7.36.** Pulled forward from the v5.7.37 trio. Pass-2 scan loop in `lint_globals_init_order` skips IDENTs inside `"..."` and `'...'` literals (with `\\` / `\"` / `\'` escapes); regression test 4 in `tests/regression-lint-global-init-order.sh` covers the shape. |
| TS test harness program (option E from v5.7.37) | Medium | **Pinned long-term 2026-04-30 at v5.7.37 ship.** A single `programs/ts_test_runner.cyr` consuming both internal-symbol fn dispatch (replacing the current `tests/tcyr/ts_{lex_combined,parse_core,parse_decls,parse_advanced}.tcyr` runners) and TS fixture files (replacing the SY-corpus regression gates `regression-ts-{lex,parse,parse-tsx,asserts,decorators,mapped}.sh`). One tool, two modes. v5.7.37 group-level consolidation is sufficient until a downstream consumer surfaces a test pattern that doesn't fit either current shape; at that point claims a v5.7.x slot (likely v5.7.45 floating slot in the queue). Out of scope: replacing `cc5 --parse-ts`-style flags themselves — the harness CALLS them, doesn't replace them. |

---

## v5.x — Language Refinements

**Pinned arc** (re-eval'd 2026-04-28 at v5.7.33 ship — arc holds; ordering reflects "smaller language adds first, big own-minor features as their slot opens"):

| Feature | Pinned | Effort | Notes |
|---------|--------|--------|-------|
| First-class slices (`slice<T>` / `[T]` generalizing `Str`) | **v5.8.x** | Medium | **Moved from v5.9.0 (defunct TLS arc) at v5.7.49 ship.** Bounds-aware (ptr, len) pair as a first-class type — sandhi / sigil / stdlib net.cyr / fs.cyr all want this; `slice<u8>` collapses the ptr+len pattern repeated across stdlib. Pinned as a v5.8.x slot candidate alongside the dep-surfaced bug fixes. |
| Per-fn effect annotations (`#pure` / `#io` / `#alloc`) | **v5.8.x** | Medium | **Moved from v5.9.1 (defunct TLS arc) at v5.7.49 ship.** Compiler-checked decorators (`#pure`, `#io`, `#alloc`) catch helpers that silently allocate or touch I/O in "pure" crypto paths; simpler than OCaml5/Koka effects (no polymorphism, no row types). sigil + sankoch want this. Pinned as a v5.8.x slot candidate. |
| Tagged unions + exhaustive pattern match | **v5.8.x** (slots 10-14) | Large | **Moved from v5.10.x at 2026-05-01 v5.8.x re-theming** — folded into the language-vocabulary stabilization phase. Biggest ergonomics win; replaces tagged.cyr + manual dispatch. See v5.8.x §Phase 2 for sub-patch breakdown. |
| `Result<T,E>` + `?` propagation | **v5.8.x** (slots 15-19) | Large | **Moved from v5.11.x at 2026-05-01 re-theming.** Depends on tagged unions (slots 10-14). Replaces -1/0/errno convention across stdlib + ecosystem. |
| Allocators-as-parameter | **v5.8.x** (slots 20-25) | Large | **Moved from v5.12.x at 2026-05-01 re-theming.** Per-call-site allocator selection. Last language addition of the compressed v5.8.x cycle. |

**Still unpinned / lower priority** (re-eval'd 2026-04-28):

| Feature | Effort | Surfacing / votes | Disposition |
|---------|--------|-------------------|-------------|
| Phase 2b-aarch64 struct copy (LDRB/STRB loop) | Medium | x86 shipped v5.5.36; aarch64 path pending | **Pin candidate** — likely v5.7.x patch slate or v5.8.x aarch64-polish slot. Surfaces whenever a consumer cross-builds struct-by-value calls for aarch64. Phylax / mabda may hit. |
| Closures capturing variables | High | gotcha #8 — consumers feel the absence | **Watching.** Promote to pinned slot when a consumer concretely blocks on it (vs. lambda-pattern workaround). v5.10.x ADTs make captured-state encoding cleaner. |
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

| Platform | Format | Status |
|----------|--------|--------|
| Linux x86_64 | ELF | **✅ Narrow + Broad** — primary host. cc5 710 KB (v5.7.12); 3-step fixpoint byte-identical. |
| Linux aarch64 | ELF | **✅ Narrow + Broad** — cross-build byte-identity + native self-host on Pi 4 (repaired v5.6.32). Three libs (`lib/hashmap_fast`, `lib/u128`, `lib/mabda`) still contain ungated x86 asm — arch-gating queued. |
| cyrius-x bytecode | .cyx | **✅ Narrow** — clean CYX bytecode (path B, v5.7.12); literal-arg propagation pinned v5.7.x patch slot. |
| macOS x86_64 | Mach-O | **✅ Narrow** (v5.1.0). |
| macOS aarch64 | Mach-O | **✅ Narrow + Broad** — gate fixture repaired v5.6.33 (no compiler regression existed; bytes unchanged since v5.5.13). |
| Windows x86_64 | PE/COFF | **✅ Narrow + Broad** — gate fixture repaired v5.6.36; HIGH_ENTROPY_VA enabled v5.6.31. Win64 ABI complete (v5.5.36); .reloc + 32-bit ASLR (v5.5.35). |
| Compiler optimization (O1–O6) | — | **✅ Closed** (v5.6.5 + v5.6.7–v5.6.27). |
| RISC-V (rv64) | ELF | Queued — **v5.7.26-v5.7.30** |
| Bare-metal | ELF (no-libc) | Queued — **v5.9.0** |

---

## Ecosystem

| Status | Repos |
|--------|-------|
| **Done** | agnostik, agnosys, argonaut, kybernet, nous, ark |
| **Done** | sakshi, majra, bsp, cyrius-doom, mabda, hadara |
| **Done** | sigil, patra, libro, shravan, tarang, yukti |
| **Done** | avatara, ai-hwaccel, hoosh, itihas, sankoch |
| **Done** | hisab |
| **In progress** | bhava |
| **In progress** | **bote** — MCP core service (JSON-RPC 2.0, tool registry, schema validation). Active port; unblocks vidya MCP. |
| **Blocked** | vidya MCP (needs bote) |

### Downstream server-stack arc

10-layer hardened-server stack is consumer of the Cyrius toolchain.
Current status: **kavach is the last port blocking completion**
(memory: `project_server_stack.md`). Once kavach lands, the server
OS stack is feature-complete at the consumer layer. No direct
Cyrius-compiler release targets this — progress is tracked in
consumer repos. Listed here so it's not forgotten across account
switches.

### Deferred consumer projects

- **CYIM** — postponed until the server base OS is wrapped
  (memory: `project_cyim_deferred.md`). No Cyrius release target;
  resumes when the server-stack arc above closes.
- **sandhi repo extraction** (सन्धि — *junction, connection, joining*;
  named 2026-04-24, formerly the "services" placeholder) —
  `lib/http_server.cyr` extraction into `sandhi::server` landed
  at sandhi v0.2.0 (M1, 2026-04-24). **sandhi** is the
  service-boundary layer that composes stdlib primitives
  (`http.cyr`, `ws.cyr`, `tls.cyr`, `json.cyr`, `net.cyr`) into
  full-featured client patterns + service discovery.
  **Fold target: v5.7.0 clean-break** per [sandhi ADR
  0002](https://github.com/MacCracken/sandhi/blob/main/docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)
  — v5.7.0 stdlib deletes `lib/http_server.cyr` and adds
  `lib/sandhi.cyr` in one event; 5.6.YY releases carry a
  deprecation warning naming the cutover. Revised 2026-04-24
  from the original "before v5.6.x closeout" target after
  reconsidering the alias-window migration model.


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
