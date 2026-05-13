# Cyrius Development Roadmap

For completed work, see [completed-phases.md](completed-phases.md).
For detailed changes, see [CHANGELOG.md](../../CHANGELOG.md).


## v5.3.x / v5.4.x / v5.5.x / v5.6.x / v5.7.x / v5.8.x / v5.9.x — shipped

All per-patch detail through v5.9.x lives in
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

**v5.9.x close** (2026-05-08): 44 patches over 2 days. Cycle
CLOSED at v5.9.43. Theme: cleanup-and-lib-improvement. Shipped:
niyama 1.0.1 fold (8th sibling distfile, 5 regex engines), full
sovereignty pass (`scripts/check.sh` 743 LOC bash → 30-line shim
+ `programs/check.cyr`; `tests/regression-*.sh` 60 → 0;
`.sh-conversion arc CLOSED at v5.9.41), agnosys 1.1.12
`#derive(Serialize)` cascade end-to-end including Mach-O ARM64
fn-pointer ASLR fix (paired Bug A `lib/fnptr.cyr` macOS branches
+ Bug B `aarch64/fixup.cyr` ftype==3 ADRP+ADD), cx Phase 2c
parity (sub-byte field load + struct-byval return + 7+-arg fn
calls), `lib/regression.cyr` testing-stdlib carve-out (22 public
verbs). cc5 741,048 → 751,744 B (+10,696 B / +1.4%). check.sh
56 → 66 gates. api-surface 2615 → 2792 (+177). Stdlib module
count 76 → 79 (+`audit_walk`, `niyama`, `regression`).

---

## Long-term considerations (slot pins resolved 2026-05-12)

Items still without a slot pin after the v5.8.65 audit. Items
that earned a v5.9.x / v5.10.x / v5.11.x pin during the audit
have moved to those sections. The **2026-05-12 tight-close
decision** resolved several additional pins; the entries below
are kept for their detailed scope + recon data, with new
"**Pinned**" markers at the head of each entry pointing to the
slot where the work now lives. Sections without a pin marker
are genuinely waiting on a trigger condition.

### `.gnu.hash` for shared-object emission

**Pinned v6.1.x** (2026-05-12 tight-close) — lands paired with
PIE codegen in v6.1.x. PIE binaries that go through
`dlopen`/symbol resolution will see the measurable difference
from the Bloom filter pre-check, satisfying the original
"any cyrius consumer pins on `.so` output and reports a
measurable lookup-time cost" trigger condition.

**Status (original deferral)**: deferred 2026-04-24 at v5.6.38
(during the slot's verify-premise check). `.so` emission works
correctly today with the SysV `.hash` table (nbucket=1; chain
walk does pure strcmp per glibc `dl-lookup.c`). `.gnu.hash` is
an optimization that uses a Bloom filter pre-check to skip
strcmp on misses; modern linkers prefer it.

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

**Pinned v6.4.x** (2026-05-12 tight-close) — lands paired with
cross-BB regalloc in v6.4.x. The "after regalloc lands" trigger
condition is met by v6.4.x's regalloc work; copy-prop earns
its slot alongside.

**Status (original deferral)**: deferred 2026-04-23 after
v5.6.18 + v5.6.19 recons.

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

### Parser-to-emit named-op refactor (path A) — pinned v5.11.x close

**Pinned 2026-05-05 at v5.8.65 close; re-pinned v5.10.x →
v5.11.x at v5.9.7 ship; re-pinned v5.11.x → v5.12.x at v5.10.20
P(-1) sweep; re-pinned v5.12.x → v5.11.x close at 2026-05-12
tight-close** — the original "RISC-V 4th-backend forces it"
trigger is gone (RISC-V moved to v6.x), but the refactor still
earns its slot in v5.11.x close for compiler hygiene. ~10
abstract ops × 3 backends (x86 / aarch64 / cx) = ~30 fn
definitions + parse_*.cyr rewrites. cx benefits immediately;
v6.x's RISC-V backend lands on the named-op interface from day
one. Reference: [`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md).

### Extended dead-store elimination (cross-BB)

**Pinned v6.4.x** (2026-05-12 tight-close) — lands paired with
cross-BB regalloc in v6.4.x. Same trigger as copy-prop above;
both gate on the liveness-out data regalloc builds.

**Status (original deferral)**: deferred 2026-04-23 after
v5.6.19 recon.

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

### Stdlib data-domain distlib carve-out — pinned v5.11.x close

**Re-pinned v5.10.x-late/v5.11.x → v5.11.x close** at 2026-05-12
tight-close. Lands as a mid-v5.11.x slot per the [Remaining slots toward close](#remaining-slots-toward-close-v51132--v51169)
plan. Original scope text below preserved for reference.

**Originally pinned 2026-05-05 at v5.8.65 close** for v5.9.x.
**Re-pinned at v5.9.43 close**: never landed in v5.9.x because
the cycle filled with sovereignty pass + emergent consumer-filed
work. Targets: ~13 data-domain modules (`json`, `toml`, `cyml`,
`csv`, `base64`, `regex`, `math`, `matrix`, `linalg`, `bigint`,
`u128`) fold-out into a `cyrius-data` sibling distlib using the
v5.7.0 sandhi-pattern. Bare-metal v5.11.0 benefits from a clean
primitives-only stdlib that doesn't drag the data offshoots into
kernel objects. Earns slot whenever scheduling lines up — late
v5.10.x bug arc OR v5.11.x kernel-prep.

### Heap-map full reorganization — pinned v5.11.68 (true closeout slot)

**Re-pinned to v5.11.68** at 2026-05-12 tight-close as the
true closeout slot of v5.11.x. The patch number is **.68 (not
.69)** because v5.11.69 is reserved as the fold-applied tag for
any dep foldins that earn their slot during the window (mabda
3.0 GA conditional). If no fold lands, .68 is the final v5.x
patch and .69 stays unused; if a fold lands, .69 = .68 +
fold-applied. Original "last-minor-before-v6.0 effort" semantic
preserved. Scope text below preserved for reference.

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
   everything" pass. v5.9.x is cleanup + lib improvement;
   v5.10.x is the open bug/optimization arc; v5.11.x is
   bare-metal + RISC-V; this likely lands at v5.12.x or
   whatever the final v5.x minor is before the v6.0.0 rename.
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
during v5.8.x that may surface in v5.10.x or later (v5.9.x came
and went; cleanup arc filled with sovereignty pass + emergent
consumer-filed work — see [completed-phases.md Phase 16](completed-phases.md)).

### Held items (surfacing-ask only; not pinned, no slot consumed)

- **`cyim` regex pattern parse error** (mabda C6) — pin when a
  cyim consumer hits it concretely. (Note: a regex-lib
  scaffold may already exist user-side; defer until cyim
  surfaces specific use case.)
- **`ESTORESTACKPARM` cx >6 args** (audit §4) — **folded into
  v5.9.33 cx Phase 2c parity slot** (2026-05-07; pin moved
  from "surfaces-on-ask" to active-cycle scheduling).
  Originally: pin when a cx consumer surfaces a 7+-arg fn.
  cx backend stub returns 0 with `# TODO: >6 args` comment at
  `src/backend/cx/emit.cyr:385`. Now landing alongside cx
  struct-by-value + sub-byte field-load parity since all three
  share the byte-memory-ops + stack-arg shuffling shape.
- **`float.cyr:41` peephole pattern** (audit §4) — pin when
  measured to matter. 5-instruction sequence `push rax;
  movabs rax, 0x7FFF...; mov rcx, rax; pop rax; and rax, rcx`
  may reduce to 3 bytes; preflight with bench delta.

### Deferred to v5.11.x or later

- **Class B FFI/wgpu fncall6 ABI** (mabda B1/B2). Mabda-only
  blast radius today; complex root-cause (ABI bug in Cyrius's
  fncall6 vs SysV AMD64 calling convention). Pairs naturally
  with v5.11.x's bare-metal / RISC-V cycle when ABI invariants
  get touched anyway. Could land in v5.10.x's bug arc if mabda
  resurfaces it as blocking — slot-fits the open-bug theme.

---

## v5.10.x — CLOSED (50 patches, 2026-05-06 → 2026-05-11)

Slot-by-slot detail in [`CHANGELOG.md`](../../CHANGELOG.md) entries
`[5.10.0]` through `[5.10.50]`. Cycle retrospective in
[`vidya/content/cyrius/field_notes/compiler/retros/v510x.cyml`](../../../vidya/content/cyrius/field_notes/compiler/retros/v510x.cyml)
(entries `v510x_cycle_retro_through_39` + `v510x_cycle_close_40_through_50`).

### Headline outcomes

- **THREE completed arcs**: typed-simd ABI (11 phases v5.10.28-.39),
  REAL TYPE SYSTEM (5 phases v5.10.1-.26), struct-by-value ABI
  (3 phases v5.10.45-.47).
- **ONE compile-time-perf miniarc** (v5.10.40 + .41): lex 603 → 59 ms
  (10×) + fixup 213 → 76 ms (2.8×) = **total compile 1037 → 387 ms (2.7×)**.
- **ONE TLS contract pin** (v5.10.42): `docs/development/lib-tls-contract.md`
  documenting the 24-verb hook surface.
- **4 audit-found issues closed** at v5.10.43/.44/.48 (str_split, exec_*,
  parser cosmetics) + 1 archived as already-resolved (kernel-reserved
  at v5.8.45).
- **1 PE premise debunked** at v5.10.49 (15-slot phantom from a
  `cmd /c "& echo %errorlevel%"` test-wrapper bug).
- **Cycle closeout** at v5.10.50 — 11-step pass all green; cycle CLOSED.

### Numbers

- cc5 (x86_64): 753,768 → **804,472 B** (+50,704 B, +6.7 %)
- cc5_aarch64_native: 463,776 → **587,048 B**
- check.sh gate count: stable at 66
- api-surface: 2,769 → **2,876** entries (+107 public fns)

### Held items NOT shipped this cycle — carried into v5.11.x

- **Class B FFI / wgpu fncall6 ABI** (mabda B1/B2). Held per user
  direction at v5.10.20 P(-1) sweep ("leave mabda issue out to be
  held"). Lands in v5.11.x or later if mabda resurfaces it as
  blocking; otherwise stays held-forward until consumer pressure.
- **`cyim` regex pattern parse error** (mabda C6). Surface-on-ask;
  cyim consumer hasn't surfaced a concrete repro.
- **`float.cyr:41` peephole pattern** (audit §4). Perf opt;
  preflight with bench delta before pinning.

---

## Cycle discipline (durable across cycles)

These principles emerged from v5.9.x / v5.10.x feedback cycles and
apply to every subsequent minor.

### Slot acceptance principle (revised at v5.10.0)

Each slot must close a chapter or open one with measurable forward
motion. No bookkeeping-only slots.

**A standalone ONE-thing slot is justified when**:
- **Big Heavy One Thing** — real refactor / non-trivial fix that
  can't reasonably bundle with adjacent work.
- **High-profile bug fix** — P0/P1 consumer-filed; user-visible
  regression; security item.
- **Tooling that opens a multi-slot arc** — e.g. v5.10.0 profiling
  instrumentation that future optimization slots build on.

**A standalone slot is NOT justified for**:
- *"Updated 1 document to draft what we do next"* — planning rides
  along with implementation, not as its own version bump.
- *"One minor edit to whitespace"* / format-only / lint-satisfying
  nudges — bundle into the next real slot.
- Adjacent micro-fixes sharing the same cascade — bundle per the
  v5.9.38/40/42 lazy-defer feedback.
- Cleanup/refactor that earns measurable improvement only when
  paired with the next optimization — bundle.

### Bottom-to-top priority (v5.10.1 user direction)

When choosing between competing slots, walk the stack
bottom→top: agnosys (baseOS/kernel) > stdlib runtime services >
specialized libraries (hisab) > applications > optimization-only.
Memory pin: `feedback_priority_bottom_to_top`.

### Premise-check at slot entry

Pins go stale; empirically test the gap before committing scope.
v5.10.45 (struct-byval scope re-cast) and v5.10.49 (PE pin
debunked) both saved 1-3 slots of mis-aimed work by 15-minute
empirical re-tests. Memory pin:
`feedback_premise_check_at_slot_entry`.

### Cross-host smoke wrapper discipline (v5.10.49 lesson)

When SSH-ing to cass (Win64) to capture an exit code, the obvious
`cmd /c "prog.exe & echo %errorlevel%"` shape expands `%errorlevel%`
at **parse time** and falsely reports `exit=0`. Use either:
- `cmd /v /c "prog.exe & echo exit=!errorlevel!"` (delayed expansion)
- `.bat` indirection (newlines split parse passes; what
  `_pe_exit_gate` in `programs/check.cyr` always used correctly)

Memory pin: `feedback_windows_errorlevel_test_wrapper`.

### Cycle-close shape (durable pattern across recent minors)

Every recent minor cycle has closed in the same three-step
shape, with the **last patch reserved for dep updates**:

1. **End cycle** — the substantive engineering work lands at
   `vN.M.K`. This is the "Big Heavy One Thing" closeout slot
   per the [Slot acceptance principle](#slot-acceptance-principle-revised-at-v5100).
2. **Update deps** — fold any deps that GA'd during the cycle
   window via the v5.7.0 sandhi pattern (vendor source
   byte-identical into `lib/<name>.cyr`, drop the `[deps.*]`
   entry, regen).
3. **Last release with updated deps** at `vN.M.K+1` — the
   "fold-applied tag." If no deps fold during the window,
   `vN.M.K` is the final patch and `vN.M.K+1` stays unused.
   Engineering work does NOT land in the fold-applied tag —
   that's exclusively for the sandhi vendor + drop ceremony.

Then the new minor opens at `vN.(M+1).0`.

**Examples in recent history**: the v5.8.x close at v5.8.65
absorbed the six-distlib sandhi foldin (sakshi 2.2.3 / patra
1.9.3 / sigil 3.1.0 / vani 0.9.2 / yukti 2.2.2 / sankoch 2.2.4).
v5.9.x close at v5.9.43 absorbed niyama 1.0.1. v5.10.x close at
v5.10.50 absorbed the wrap-up + .49 PE debunk. v5.11.x is
following the same shape: heap-map full reorg at v5.11.68
(engineering), conditional mabda 3.0 fold at v5.11.69 (or .69
stays unused).

**Exceptions are explicit, not accidental**. The v5.11.1–.7
stdlib annotation arc landed at the **start** of v5.11.x, not
the end — that was a user-directed priority flip (annotation
arc first, everything else after), called out in the v5.11.x
intro at slot entry. Future deviations from the close-shape
should be similarly explicit at cycle entry rather than
discovered mid-cycle.

Memory pin: [[feedback-cycle-close-shape]].

## v5.11.x — **Final 5.x minor** (close-out arc)

**Heading updated 2026-05-12** (tight-close decision). v5.11.x
is now the last minor of the v5.x line. All work that closes
the v5.x arc — user-binary ELF cleanup, stdlib data-domain
carve-out, parser-to-emit named-op refactor, sovereignty/polish
remainders, and the pre-v6.0 heap-map full reorganization —
lands here, sealing the cycle at the **v5.11.68 / v5.11.69 close
pair** — heap-map full reorganization at .68 (the true
closeout engineering work), with .69 reserved for any dep
foldins that earn their slot during the window (mabda 3.0 GA
conditional; if no fold lands, .68 is the final v5.x patch).

Anything that would expand the language's *capabilities* (new
platforms, new language features, new linker modes) moves to
v6.x. The v5.x → v6.x boundary is now: **v5.x = "what the
language IS"; v6.x = "new platforms + advanced features the
language gains."** See the [v6.x section](#v6x--platform-expansion--advanced-features)
for what was formerly v5.12.x scope (bare-metal formalization +
RISC-V rv64) plus the broader 6.x capability expansion.

**Historical pin path** (preserved for reference): the v5.11.x
slot has hosted three distinct cycle themes as priorities
shifted. (1) Originally pinned as **bare-metal + RISC-V arc**
at v5.9.7 ship; (2) repurposed at v5.10.20 P(-1) sweep into
a **cleanup minor** (stdlib annotation arc + consumer-issue
closeout) when bare-metal/RISC-V moved to v5.12.x; (3) now
the **final 5.x minor** at the 2026-05-12 tight-close
decision, with v5.12.x retired and its scope absorbed into
v6.x. The detailed slot-by-slot record for shipped slots
.0 → .31 follows below; remaining slots .32 → .69 are spelled
out in the [Remaining slots toward close](#remaining-slots-toward-close-v51132--v51169)
subsection further down this section.

### v5.11.x — Cleanup minor (TS test harness + held-forward absorber)

**Repurposed at v5.10.20 P(-1) sweep** (2026-05-09): user
direction "TS test harness will moving into 5.11.x and
5.12.0 is now baremetel/riscv". v5.11.x is now a short
cleanup-cycle absorbing items that surface during the
v5.10.x close, NOT the bare-metal / RISC-V kickoff (which
moves to v5.12.0).

**PRIORITY (user direction 2026-05-11):** stdlib annotation arc
FIRST. Everything else in the Scope below — `cyrius deps`
copy, regression-*.sh → cyrius port, TS test harness,
Consumer-filed issues, Held-forward items — queues AFTER the
annotation arc completes.

**Scope**:

- **Stdlib annotation refactor — multi-patch breakout**
  (pinned 2026-05-10 at v5.10.32 ship). User direction:
  *"given we have a type system now... it probably would
  be worth review of the other libs and refactoring where
  possible... it can be in front of the ts test work of
  5.11.x items"*.

  REAL TYPE SYSTEM arc closed at v5.10.26 (default-on
  CYRIUS_TYPE_CHECK + 11 stdlib cstring annotations). The
  v5.10.32 type-audit shows **75% lib coverage** — 1,010
  unannotated public fns out of 4,133. The annotations are
  dormant signal: `var x: Str = f(...)` is correct today but
  warning-silent if `f` lacks a `: Str` return annotation.
  Adding annotations across the rest of stdlib lights up the
  type-check warning surface for downstream consumers — same
  shape as the v5.10.24 ship (cstring annotations in
  string.cyr/io.cyr).

  Multi-patch breakout planned phases (refine at slot
  entry per `feedback_premise_check_at_slot_entry`):

  | Phase  | Modules (gap counts) | Why this order |
  |--------|----------------------|----------------|
  | v5.11.1 | Foundational core: alloc (0/26), vec (0/11), fmt (0/14), freelist (0/4), fnptr (0/9), result (0/6), tagged (0/11), assert (0/12) — ~93 fns | Used by every consumer; sets the floor for downstream value. Most are scalar/i64-returning; a few Str/Result/Option-returning that enable downstream inference. |
  | v5.11.2 | I/O surface: io (1/21), fs (0/11), process (0/10), syscalls_x86_64_linux (0/62), syscalls_aarch64_linux (0/62) — ~166 fns | High cstring-shape exposure (file paths). Strong type-check signal once consumers thread Str through fs ops. |
  | v5.11.3 | String/format completion: string (9/16), str (52/68), bigint (0/20), chrono (0/16), bench (0/18) — ~71 fns | Closes string-handling surface; bigint/chrono/bench are heavily-called specialized libs. |
  | v5.11.4 | Collection libraries: hashmap (0/41), json (0/86) — 127 fns | Mid-sized libs; hashmap underlies many sandhi/agnosys flows; json is the serialization workhorse. |
  | ~~v5.11.5~~ | ~~Big consumer libraries: mabda (0/405)~~ — **NOT a cyrius release slot** (user 2026-05-11). mabda is **blocked from any release until 3.0.0 GA**; annotation work happens in `/home/macro/Repos/mabda/` on the `v3` branch as prep for the eventual GA, with no version bump there. Re-pulls into cyrius when mabda 3.0 GA folds in (per v5.8.65 sandhi pattern). |
  | v5.11.5 | Closeouts: vani (86/105), patra (88/92), agnosys (540/559), sandhi (315/344), pwd (6/12), grp (8/10), shadow (4/6), cyml (14/17), fdlopen (10/19), flags (10/12), net (13/15), u128 (34/35), ws_server (12/13) — ~83 fns | Partial-coverage consumer libs; top off to 100%. **Promoted from v5.11.6 → v5.11.5 after mabda removal.** |
  | v5.11.6 | **Cross-binary ship: cc5_win + cc5_aarch64_macho (+ cc5_aarch64_native / cc5_cx as bandwidth allows)** | **PLATFORM BLOCKER inserted 2026-05-11** — ai-hwaccel agent flagged at v5.10.37: `cc5_win` exists in `build/cc5_win_cross` but isn't in `[release].cross_bins`, so consumers can't get a Windows cyrius from the release tarball. Same gap for macOS Apple Silicon (`cc5_aarch64_macho` exists in src but not shipped). Phase 7 compiler internals cascades to v5.11.7. See below for full slot spec. |
  | v5.11.7 | src/common/ir (24/44), src/frontend/parse_types (0/24), parse_decl/parse_fn cleanup (11/11 each, no gap) | Compiler-side internals — annotations don't expose to consumers but tighten internal reasoning. **Arc CLOSES here.** Cascaded from v5.11.6 → v5.11.7 to make room for the platform unblock at .6. |

  **Acceptance shape per phase**:
  - Self-host byte-identical (annotations don't change emit)
  - 66/66 check.sh + 136+/136+ cyrius test
  - Downstream consumer regression sweep (per-phase verify):
    no new false-positive type-check warnings
  - Coverage delta tracked per slot in CHANGELOG

  **NOT in scope**: API surface changes (renames, signature
  shifts). This is a pure-annotation arc — `: Str` / `: cstring`
  / `: Result` / `: Option` / `: Tagged` / `: i64` / `: f64v2`
  added without altering the existing fn signatures' I/O.
  Refactoring of fn bodies (DRY-up, abstraction tightening) is
  a separate concern that may be folded in opportunistically
  but is not the slot's primary ask.

  **Why now**: at v5.10.32 the typed-simd ABI arc is one slot
  from close (v5.10.33 ships f64v4 + lib/simd.cyr typed
  wrappers). After that, the v5.10.x cleanup minor naturally
  flows into v5.11.x. The stdlib annotation arc fills the
  v5.11.x cleanup-minor remit (TS test harness was the only
  pinned item; this becomes the primary v5.11.x narrative).
  TS test harness stays opportunistic per its original pin.

#### After the annotation arc completes

Every item below runs AFTER the stdlib annotation arc
finishes. No interleaving. Slot numbers are starting points
(annotation arc fills v5.11.1-v5.11.7+; this list picks up
right after).

| Slot | Item |
|------|------|
| v5.11.0 ✅ | kavach P1 sandbox syscall wrappers (shipped) |
| v5.11.1-v5.11.5 | Stdlib annotation arc (Phases 1-4 + 6; mabda annotation handled out-of-band on mabda v3 branch — not a cyrius release slot) |
| v5.11.6 | **Cross-binary ship — cc5_win + cc5_aarch64_macho (+ aarch64_native / cx as bandwidth allows)** — PLATFORM BLOCKER (inserted 2026-05-11; ai-hwaccel agent flagged at v5.10.37) |
| v5.11.7 | Phase 7 — compiler-side internals annotation pass — **arc CLOSES here** (cascaded from v5.11.6) |
| v5.11.8 | `cyrius deps` symlink → file-copy |
| v5.11.9 | `tests/regression-*.sh` → cyrius port |
| v5.11.10 | Cyriusly cmdtools port (paired with .9 per user direction) |
| v5.11.11 | TS test harness program |
| v5.11.12 | daimon aarch64 `sys_epoll_wait` (P2) |
| v5.11.13 | bote `lib/net.cyr` `recv_timeout` + getaddrinfo (P2) |
| v5.11.14 | bote arena allocator `fl_free` (P2) |
| v5.11.15 | bote streaming dispatch primitives — **closed in 1 slot** (chan_try_recv + cancel_token_*; chan_* MPSC already shipped v5.5.31, atomics v5.5.31, arena pattern v5.11.14). Original 3-slot scope was over-budget. |
| v5.11.16 | bote WS handshake key validation (Low; RFC 6455 §4.1 — Sec-WebSocket-Key must be 24-char base64; consolidated from .18 at v5.11.15 close per user direction "close up open gap, so we have additional runway later") |
| v5.11.17 | **Per-repo isolation Part 1: `cyrius deps` stdlib_dir fix** (pinned 2026-05-11 v5.11.3 wipe; 5-item acceptance split into 3 slots at v5.11.16 close per user direction "Reframe — split into 3 slots"; Part 1 = the actual ping-pong wedge in `cbt/deps.cyr::_dep_find_stdlib_dir`) |
| v5.11.18 | **kybernet bundle Part A.i + Part B: identifier buffer 2× + socket-syscall wrappers** (P2; pinned 2026-05-11 at v5.11.4/.5; Part A.ii fn_table 4096→8192 split off to v5.11.19 at v5.11.18 audit per user direction "Split honestly — ship .18 partial" after audit revealed ~15 fn_* tables across scattered locations require relocate-and-shift instead of "single source-line edit") |
| v5.11.19 | **kybernet Part A.ii: fn_table 4096 → 8192 (heap-map refactor)** (pinned 2026-05-11 at v5.11.18 audit; ~300-500 hex-literal edits across 7 src/ files; relocate 7 scattered fn_* tables + double 16 contiguous tables + shift IR/fixup regions; standalone slot per honest scope shrink) |
| v5.11.20 | **Syscall-wrapper DRY consolidation** (Linux x86_64 + aarch64 wrapper-body dedup; pinned 2026-05-11 from v5.11.7 close-out lib audit) |
| v5.11.21 | **0-call public stdlib fn downstream survey** (10 fns: async_new, callback::for_each, *_invalidate_cache trio, log_init, niyama_bre_compile, sakshi_clock_recalibrate, sandhi_err_kind_name, sig_alg_name) — pinned 2026-05-11 |
| v5.11.22 | **ai-hwaccel cc5_win debunk + mkdir/unlink PE plumbing** (pinned 2026-05-11 at v5.11.21 close; minimal `syscall(60,42)` premise debunk — works on cass; real ai-hwaccel gap is unrouted syscalls 83/87/89 → cyrius adds CreateDirectoryW/DeleteFileW auto-import + parser dispatch with -ENOSYS placeholder bodies; updated warning text; pre-existing `EOPEN_PE` UTF-16-widening fault on Win11 26200 surfaced — pinned v5.11.23) |
| v5.11.23 | **EOPEN_PE + ECREATEDIR/EDELETEF UTF-16 widening fix** (pinned 2026-05-11 at v5.11.22 audit; pre-existing PE-emit bug — `_pe_exit_gate` only tests `exit42`+`hello-world`, never path-API kernel32 calls; fault is in `ntdll!+0x41912` (path-validation routine) on Win11 26200 (cass); wine accepts both. Slot: bisect widening pattern vs Windows path validation, fix the shared shape, wire the real CreateDirectoryW/DeleteFileW call bodies in src/backend/x86/emit.cyr, add PE-mode gate to programs/check.cyr that exercises CreateFileW + CreateDirectoryW on cass) |
| v5.11.24 | **`#derive(accessors)` >16-field silent miscompile fix** (Medium; agnos 1.28.3 filed 2026-05-11; `src/frontend/lex_pp.cyr` per-struct `field_names`/`field_types`/`offsets` tables hard-sized at 16 entries — 17th field overflows into field_types[0], offsets diverge silently. agnos 22-field `struct Process` corrupted CR3 → kernel page-fault on first context switch. Raise cap + add hard-cap diagnostic.) |
| v5.11.25 | **Per-repo isolation Part 2: `cyrius` CLI version-resolved dispatcher** (pinned 2026-05-11 at v5.11.16 close; binary reads `cyrius.cyml`'s `cyrius` top-level field → re-exec `~/.cyrius/versions/<v>/bin/cyrius`; error if not installed; touches every cyrius CLI entry point; multi-slot scope) |
| v5.11.26 | **Per-repo isolation Part 3: `cyriusly use --global` flag + per-repo default** (pinned 2026-05-11 at v5.11.16 close; `programs/cyriusly.cyr`'s `use` verb defaults to writing `cyrius.cyml`'s `cyrius` field instead of `~/.cyrius/current`; `--global` keeps the legacy write; sibling agents `cyriusly use 5.10.44 --global` becomes the explicit form) |
| v5.11.27 | **aarch64-native build repair** (re-pinned 2026-05-12 mid-slot after pi premise-check exposed two stale-fork bugs. (1) `src/main_aarch64_native.cyr` missing `CYRIUS_TARGET_LINUX`/`CYRIUS_TARGET_MACOS` predefine block that `src/main_aarch64.cyr:148-159` ships — every aarch64-native binary SIGILLs at first `alloc()` because `lib/alloc.cyr`'s `#ifdef CYRIUS_TARGET_LINUX` branch was dead. (2) `_init_cyrius_lib` + `_check_shadow_lib` (lex.cyr:221, :319) use bare `syscall(2, path, …)` on aarch64; xlat changes 2→56 but doesn't shift args, so path ends up in dfd slot and dfd=0 in path → EFAULT, `_cyrius_lib_len` stays 0, version-pinned-lib fallback dead. Latent since v5.5.16 split. Fix: port predefine dispatch + match `READFILE`'s `if (SYS_OPEN == 2)` branching. Pi e2e verify required.) |
| v5.11.28 | **bote parser quirk: closed no-repro + diagnostic improvement + regression test** (shipped 2026-05-12. Premise-check at slot entry: reverted bote's `cap0/cap1` var-stage to recreate the inline-nested shape, compiled at v5.11.27 AND v5.10.34 — clean parse both times. Synthetic fuzz 0/28 across 9 preceding-line counts + 10 ident counts spanning the filing's ~8700 boundary speculation. Likely closed silently by v5.11.18's identifier buffer doubling (`f3e98a3e`, 131072 → 262144 bytes), fitting the filing's Speculation 2 hash-collision boundary hypothesis. Ships: (1) `tests/tcyr/parse_nested_call_assert.tcyr` (13 asserts) locking the shape; (2) `src/common/util.cyr:425-432` `ERR_EXPECT` hint when `expected ')' / ','` AND got-token is string — saves consumers from the misleading-fix rabbit hole the filing called out. Issue archived.) |
| v5.11.29 | **hisab 18-arg-fn scrambles params (x86_64 SysV silent miscompile)** (P1; hisab filed 2026-04-26; pinned 2026-05-12 after v5.11.26 audit. LOCALLY VERIFIED at v5.11.26: `f18(1..18)` returns param 1 as 0; params 1, 2, 7-12 scrambled; works at ≤16 args. Affects EVERY consumer hitting 17+ args. No diagnostic. Workaround: refactor to ≤10 args.) |
| v5.11.30 | **sigil [rbp-N] stack-frame-drift breaks NI inline-asm** (P1; sigil 2026-05-10 filing. sigil 2.9.1+ AES-NI / SHA-NI / ed25519-NI hand-coded `[rbp-N]` offsets SIGILL on cc5 5.10.x+; cc5 prologue expansion shifted param-slot positions. majra 2.4.2 held sigil at 2.9.0 to ship at all; blocks every consumer needing sigil ≥2.9.1 NI features. Slot: bisect cc5 prologue change, document slot stability contract OR add a cyrius-side hand-asm trampoline that masks the shift.) |
| v5.11.31 | **sigil ed25519_verify accepts wrong pubkey on cc5_aarch64** (P1; sigil 2026-05-10 filing. x86_64 correct; cc5_aarch64 returns 1 (valid) for a wrong pubkey. Trust-boundary auth break on aarch64. Slot: split cyrius aarch64 codegen vs sigil 3.x logic; reproduce on pi; bisect.) |
| v5.11.32-35 | OPEN — emergent bugs / consumer-filed / items surface during cycle (4-slot buffer; was 5 before .27 aarch64-native repair re-pinned mid-slot 2026-05-12) |
| v5.11.36 | **cc5_aarch64_macho cross-bin ship** (deferred from v5.11.6 — host-runtime mmap fix + ecb smoke; user 2026-05-11: "fine for back of the current line") |
| v5.11.37 | **cc5_aarch64_native cross-bin ship** (deferred from v5.11.6 — build + pi smoke) |
| v5.11.38 | **cc5_cx cross-bin ship** (deferred from v5.11.6 — bytecode emit + VM smoke target) |
| v5.11.39 | Defensive sweep (small parser cosmetic items bundled — note v5.11.28 absorbs the bote parser quirk; remaining minor items + v5.11.26 audit's LOW/P3 bundle: hisab `for (;cond;step)`, lint-rc-as-warning-count, agnosys #ifplat codegen, phylax `_SC_ARITY` false positives on at-family wrappers, phylax aarch64 duplicate-fn warnings, sakshi log primitives, hisab cbt modules substring false positive, bote 2MB compile-source-size cap re-eval — pinned 2026-05-12 from audit) |
| v5.11.40 | Cycle closeout |

#### v5.11.6 — Cross-binary ship (Win64 PE + macOS Apple Silicon + bonus targets)

**Pinned 2026-05-11 per user direction as a PLATFORM BLOCKER** after
ai-hwaccel agent re-surfaced their v5.10.37 note:

> *"Windows DXGI backend — `cc5_win` exists at v5.10.37 (built in
> `/home/macro/Repos/cyrius/build/cc5_win_cross`) but isn't installed
> in the standard toolchain. COM/DXGI surface is multi-slot scope.
> Re-evaluate when cc5_win ships in the default install."*

State at v5.11.5: still unshipped. `build/cc5_win_cross` exists
locally (598 KB, 2026-05-10 build) but `cyrius.cyml [release].cross_bins`
contains only `["cc5_aarch64"]`. Consumers downloading the release
tarball get no Windows cyrius. Same shape applies to macOS Apple
Silicon — `src/main_aarch64_macho.cyr` exists but `cc5_aarch64_macho`
isn't in cross_bins either.

This slot **cascades Phase 7 compiler-internals annotation to v5.11.7**
(previously the arc-closing slot at .6). Annotation arc and the
.7 cushion both shift down by one to make room — the platform unblock
takes priority because it gates downstream consumer work
(ai-hwaccel DXGI; future macOS native Apple Silicon flows that
currently depend on running `cc5` x86 cross under Rosetta).

**Targets to add to `[release].cross_bins`**:

| Cross-bin | Entry source | Target | Status |
|---|---|---|---|
| `cc5_win` | `src/main_win.cyr` | Win64 PE x86_64 cross | ✅ shipped at v5.11.6 — verified runs on Linux, emits valid PE32+, deploys + runs on cass |
| `cc5_aarch64_macho` | `src/main_aarch64_macho.cyr` | macOS Apple Silicon Mach-O cross | ⏸ **Pinned v5.11.36** — main_aarch64_macho.cyr uses macOS mmap for its OWN heap init at startup, so the Linux-host cross-compiler binary fails with "cc5_macho: mmap heap init failed". Needs source fix (use Linux syscalls for host runtime, mach-o emit for output) + ecb smoke. |
| `cc5_aarch64_native` | `src/main_aarch64_native.cyr` | aarch64 Linux self-build | ⏸ **Pinned v5.11.37** — not built/verified this slot; needs build + pi smoke + cross_bins add. |
| `cc5_cx` | `src/main_cx.cyr` | cyrius-x bytecode | ⏸ **Pinned v5.11.38** — bytecode emit works locally but no runtime smoke target; needs cyrius-x VM verification + cross_bins add. |

**Acceptance bar**:
1. `cyrius.cyml [release].cross_bins` updated to list the four entries
   (or whatever subset bandwidth allows; cc5_win + cc5_aarch64_macho
   are the platform-blocker minimum).
2. `scripts/install.sh --refresh-only` rebuild rules already follow the
   generic `cc5_<name>` → `src/main_<name>.cyr` pattern (line 115); verify
   no per-target carve-outs needed. If a target needs a custom rebuild
   path (e.g., Mach-O linker invocation), add it under the
   `_rebuild_stale` arm.
3. Each binary reproducibly rebuilds from current `build/cc5` (i.e., the
   x86_64 host compiler cross-compiles all 4 targets without external
   toolchain dependency).
4. **Cross-host smoke matrix**:
   - `cc5_win` — copy to cass, compile a minimal program, run, verify exit code.
   - `cc5_aarch64_macho` — copy to ecb, compile a minimal program, run, verify exit code.
   - `cc5_aarch64_native` — copy to pi, run native self-host fixpoint (b == c).
   - `cc5_cx` — in-tree test (no remote host).
5. Release tarball at next v5.11.x ship includes all 4 binaries; `cyrius
   install` (or the equivalent CI install path) places each at
   `~/.cyrius/versions/<v>/bin/cc5_<name>`.
6. Downstream consumer regression: ai-hwaccel DXGI work unblocked
   (signal: ai-hwaccel agent can begin COM/DXGI surface implementation
    without the gating note).

**Why now (vs slot in buffer band)**: PLATFORM BLOCKER class —
ai-hwaccel can't start DXGI work without cc5_win shipping. Pushing
to .17 (version isolation) or .18 (kybernet caps) defers a downstream
agent's entire arc by 13+ slots. cc5_win is built and tested locally;
the slot is mostly ceremony (cyml edit + install.sh rule verify +
cross-host smoke), not new code.

**Estimated scope**: 1 slot if all 4 targets follow the generic
rebuild pattern; could split into 2 slots if a target needs custom
build infrastructure (e.g., Mach-O codesigning shim). Refine at slot
entry per `feedback_premise_check_at_slot_entry`.

#### v5.11.17 — Per-repo isolation Part 1: `cyrius deps` stdlib_dir fix

**Pinned 2026-05-11 during v5.11.3 ship; original 5-item acceptance
bar split into 3 slots at v5.11.16 close per user direction
("Reframe — split into 3 slots"). This slot lands the actual
ping-pong wedge. Parts 2 and 3 pinned at v5.11.24 and v5.11.25.**

**Root cause**: `~/.cyrius/current`, `~/.cyrius/bin`, and
`~/.cyrius/lib` are single global pointers. When sibling agents on
the same dev box (agnosys, mabda, etc.) run `cyriusly use <version>`
to test against their pinned toolchain, they mutate the global
pointers. Any other repo concurrently doing `cyrius deps` resolution
reads the wrong snapshot — and the v5.10.37-discussed snapshot-ping-
pong loop copies those stale files BACK INTO the active repo's
`lib/`, silently wiping work in progress.

**Why this part first**: `cbt/deps.cyr::_dep_find_stdlib_dir()` is
the single wedge where the wipe happens. Closing it stops the
destructive failure mode immediately, regardless of when (or
whether) Parts 2-3 land. Parts 2-3 add the broader per-repo
discipline; Part 1 is the actual bleed-fix.

**User direction (2026-05-11)**:
- *"if version is installed it should just use the cyrius.cyml's
  noted version if not complain its not installed"* — drives
  Part 2 (CLI dispatcher).
- *"agnosys agent cyriusly use 5.10.44 for tests; switch it
  fucking back bro"* — confirms sibling-agent behavior is
  intentional, but cyrius's repo shouldn't be affected.
- *"or they slide the version to latest without asking or telling
  me"* — second failure mode (auto-update), addressed by Part 2.

**Acceptance bar (this slot)**:
1. `cbt/deps.cyr::_dep_find_stdlib_dir()` resolution order:
   - **(a) `./lib`** (dev mode) — preferred when running from cyrius
     source repo. Closes the cyrius-repo ping-pong since the repo
     reads from its own in-tree files instead of the global snapshot.
   - **(b) `~/.cyrius/versions/<cyml-cyrius-field>/lib/`** —
     when `cyrius.cyml` (or any parent up to repo root) has a
     top-level `cyrius = "X.Y.Z"` field, AND that version is installed.
   - **(c) `~/.cyrius/lib`** — legacy fallback (kept for repos
     without a cyrius pin; behavior unchanged for them).
   - **Hard error** (not silent fallback) when the cyrius.cyml pin
     references a NON-installed version — error message names the
     pinned version + suggests `cyrius install X.Y.Z`.
2. cyrius repo's own `lib/*.cyr` edits survive a `cyrius deps` run
   regression test (write an edit, run `cyrius deps`, verify the
   edit is preserved).
3. cc5 self-host byte-identical (deps.cyr is dispatcher-only; no
   compiler change).
4. check.sh 66/66 + cyrius test 146/146 green.
5. Cross-host smoke: pi (aarch64), ecb (Apple Silicon), cass
   (Windows) — `cyrius deps` resolves without regression.

**Out of scope** (pinned forward):
- Part 2 (v5.11.23): `cyrius` CLI itself version-resolved
  dispatcher — multi-slot architectural change.
- Part 3 (v5.11.24): `cyriusly use --global` flag + per-repo
  default — ~80 LOC in `programs/cyriusly.cyr`.

**Pairs with v5.11.8** (`cyrius deps` symlink → file-copy fix):
once both ship, snapshot-ping-pong stops being a destructive
surprise AND per-repo resolution prevents the trigger in the first
place. The two fixes are complementary, not redundant.

**Reference**: in-tree memory pin
`project_cyriusly_version_switching.md` carries the symptom + the
recovery procedure used during v5.11.3.

#### v5.11.18 — kybernet bundle: cap raise + socket-syscall wrappers

**Original pin 2026-05-11 at v5.11.4 entry** (cap raise from
[`docs/development/issues/2026-05-11-kybernet-fn-table-identifier-buffer-caps.md`](issues/2026-05-11-kybernet-fn-table-identifier-buffer-caps.md)).
**Expanded 2026-05-11 at v5.11.5 ship per user direction** to bundle
kybernet's 1.1.5 socket-syscall wrapper filing
([`docs/development/issues/2026-05-11-kybernet-socket-syscall-wrappers.md`](issues/2026-05-11-kybernet-socket-syscall-wrappers.md))
into the same slot — both kybernet P2 stdlib asks, both low-risk,
both pinned AFTER the stdlib annotation arc completes.

**Background**: kybernet 1.1.0 (AGNOS PID-1 init system) assembled
the full AGNOS surface (stdlib + agnosys-full + agnostik + libro +
patra + argonaut + sigil + sakshi) and hit:
- `fn_table at 92% (3779 / 4096)` — warn threshold (90%)
- `identifier buffer at 85% (112094 / 131072 bytes)` — warn threshold

kybernet 1.1.1 worked around the cliff by switching `[deps.agnosys]`
from `dist/agnosys.cyr` (350 fns) → `dist/agnosys-core.cyr` (56 fns).
That's a one-shot lever — 1.2.0 edge-boot work brings
`agnosys-storage` + `agnosys-trust` profiles back into scope, and
the next minor tips past the hard cap (non-recoverable error).

**Audit at v5.11.18 entry (2026-05-11)** revealed the reporter's
"single source-line edit" framing was wrong for fn_table. The
identifier buffer raise IS mechanical (uses the existing 0xA0000-
0x18C100 heap-map gap; ~10 literal updates in lex.cyr +
main*.cyr + util.cyr). The fn_table piece, however, requires
relocating 7 scattered fn_* tables (fn_deprecated_msg /
fn_name_hash / fn_start_hash / fn_regalloc / fn_ret_sid /
fn_variadic / fn_flags — each adjacent to non-fn_* regions that
collide at 2× size) AND doubling 16 contiguous fn_* tables (8
extended + 8 primary) AND shifting ir_nodes / blocks / state /
edges / cp / fixup_tbl by 0x80000. ~300-500 hex-literal edits
across 7 src/ files.

**Slot scope (post-audit split)**:

1. **Part A.i**: `identifier buffer` 131072 → **262144 bytes** (2×).
   Buffer grows 0x60000-0xA0000 (was 0x60000-0x80000). Uses
   existing gap; no heap-map shift. lex.cyr NPOS_GUARD/LEXID
   threshold + main.cyr/main_win.cyr warning thresholds +
   util.cyr parse-failure dump + heap-map comments across all
   main_*.cyr.
2. **Part B**: 7 socket-syscall wrappers in both
   `lib/syscalls_x86_64_linux.cyr` + `lib/syscalls_aarch64_linux.cyr`
   peers. See "Part B" section below.
3. **Part A.ii** (`fn_table` 4096 → 8192 with full heap-map
   refactor) **split off to v5.11.19** per user direction at audit
   ("Split honestly — ship .18 partial"). Honest scope shrink
   based on audit data, NOT lazy defer — the reporter's "single
   source-line edit" framing didn't survive contact with the
   actual heap-map.

**Acceptance bar (this slot, Part A.i + Part B)**:
- cc5 self-host byte-identical (Part A.i: comment + literal
  updates only; Part B: additive stdlib).
- check.sh 66/66 green.
- cyrius test 146/146 green.
- kybernet 1.1.0 build no longer hits the *identifier buffer*
  warn threshold (the fn_table warning will persist until v5.11.19).
- Part B: pi (aarch64) cross-host smoke green for `sys_socket` +
  `sys_bind` (load-bearing — the bug class is silent aarch64 misroute).

**Why this slot and not earlier**: per user direction, "after stdlib
annotation arc". The arc runs v5.11.1-v5.11.7+; the post-arc queue
(.8-.19) is already pinned to infrastructure / consumer-blocking
P2 work. v5.11.18 is the first buffer-band slot — kybernet is P2
non-blocking (workaround in place at 1.1.1) but cliff-narrow for
the next 1-2 minors.

**P2 rationale** (from the issue): not P1 (kybernet 1.1.1 ships
clean under existing caps); not P3 (headroom is narrow enough that
1.2.0 edge-boot plausibly tips the warn threshold). Low-risk fix
makes the P2 rate the right speed.

##### Part B (added v5.11.5 ship) — socket-syscall wrappers

kybernet 1.1.5 P(-1) audit caught three sites in `src/lib/notify.cyr`
where x86_64 syscall numbers were hardcoded and silently routed to
the wrong aarch64 syscalls (41 → `pipe2`, 49 → `setsockopt`, 45 →
`getsockopt`). Workaround landed at the kybernet layer (per-arch
`#ifdef` enum); upstream gap is missing socket-family stdlib wrappers.

**Wrappers to add** (mirror the v5.11.0 kavach sandbox-syscall
pattern across both x86_64 + aarch64 peers):

| Wrapper | Arity | x86_64 | aarch64 | Use |
|---------|------:|-------:|--------:|-----|
| `sys_socket(domain, type, protocol)` | 3 | 41 | 198 | sd_notify dgram, supervisor IPC |
| `sys_bind(fd, sockaddr, addrlen)` | 3 | 49 | 200 | sd_notify socket bind |
| `sys_recvfrom(fd, buf, len, flags, srcaddr, srcaddrlen)` | 6 | 45 | 207 | sd_notify message read |
| `sys_listen(fd, backlog)` | 2 | 50 | 201 | supervisor control-socket accept loop (kybernet 1.2.x) |
| `sys_accept4(fd, srcaddr, srcaddrlen, flags)` | 4 | 288 | 242 | same accept loop |
| `sys_connect(fd, sockaddr, addrlen)` | 3 | 42 | 203 | service-side sd_notify client (argonaut) |
| `sys_recvmsg(fd, msghdr, flags)` *(adjacent)* | 3 | 47 | 212 | SCM_CREDENTIALS peer-cred capture (argonaut 1.6.2 already uses) |

**Acceptance bar (Part B)**:
- All 7 wrappers added to `lib/syscalls_x86_64_linux.cyr` AND
  `lib/syscalls_aarch64_linux.cyr` with the matching syscall numbers
  (per `feedback_cross_arch_propagation_mandatory` — same-slot
  propagation mandatory).
- Each wrapper annotated `: i64` (matches v5.11.x annotation arc).
- New test in `tests/tcyr/socket_syscalls.tcyr` mirroring the v5.11.0
  `sandbox_syscalls.tcyr` shape: compile-time `&fn` reference for
  callability + runtime exercise where side-effect-safe (e.g.,
  `sys_socket(AF_UNIX, SOCK_DGRAM, 0)` + immediate close).
- Cross-host smoke: pi (aarch64 Linux) runtime green; the original
  bug class is silent-misroute on aarch64, so pi verify is load-bearing.
- kybernet 1.1.5's `#ifdef SockSysNr` block can be deleted upstream
  and replaced with direct `sys_socket()` / `sys_bind()` /
  `sys_recvfrom()` calls in a follow-up kybernet patch.

**Why bundle into v5.11.18**: both kybernet asks ship from the same
consumer at the same audit window (1.1.5 P(-1)); both are pure stdlib
additions with no API change; both are low-risk (cap raise + new fns,
no removals). Combined slot is still well-bounded — one parser-cap
edit + 14 fn additions (7 × 2 arches) + 1 test file. User direction
2026-05-11: pin alongside the existing kybernet request.

**P2 rationale (Part B)**: same as Part A — local workaround in
place, no active break, but the footgun class (silent aarch64
misroute, invisible on x86 CI) is exactly what stdlib wrappers
exist to prevent. Every new consumer needing a socket re-rolls the
per-arch dispatch and re-introduces the bug.

#### v5.11.19 — kybernet Part A.ii: `fn_table` 4096 → 8192 (heap-map refactor)

**Pinned 2026-05-11 at v5.11.18 audit per user direction**
"Split honestly — ship .18 partial" after the audit revealed
this is a heap-map refactor, not a single-line edit. Source
issue is kybernet 1.1.0 hitting *fn_table at 92% (3779/4096)*
in
[`docs/development/issues/2026-05-11-kybernet-fn-table-identifier-buffer-caps.md`](issues/2026-05-11-kybernet-fn-table-identifier-buffer-caps.md).

**Why this is heap-map work, not a literal bump**: cyrius's fn_*
metadata lives in 15+ tables across both contiguous blocks and
scattered locations:

```
Contiguous extended block (0x124A000-0x128A000, 256KB / 8 tables × 32KB):
  fn_param_cstring_mask / _result_mask / _option_mask / _tagged_mask
  fn_overload_str / _int / _cstr
  fn_param_simd_mask

Contiguous primary block (0x128A000-0x12CA000, 256KB / 8 tables × 32KB):
  fn_names / fn_offsets / fn_params / fn_body_start / fn_body_end
  fn_inline / fn_param_str_mask / fn_code_end

Scattered (each 32KB, adjacent to non-fn_* regions):
  0x104000 fn_deprecated_msg     (next: fn_name_hash at 0x10C000)
  0x10C000 fn_name_hash          (next: fn_start_hash at 0x110000)
  0x110000 fn_start_hash         (next: var_noffs at 0x11A000)
  0x1C8000 fn_regalloc           (next: enum_const_val at 0x1D8000)
  0x1EC000 fn_ret_sid            (next: fn_variadic at 0x1F4000)
  0x1F4000 fn_variadic           (next: fn_flags at 0x1FC000)
  0x1FC000 fn_flags              (next: var_enum_id at 0x204000)
```

Doubling cap to 8192 means each table needs 64KB stride (was
32KB). Every scattered table collides with its neighbor at 2×
size — they have to be RELOCATED, not just grown. The contiguous
blocks need stride doubled + everything after primary block
(ir_nodes / blocks / state / edges / cp / fixup_tbl) shifted by
0x80000.

**Refactor shape (estimated)**:

1. **Relocate 7 scattered fn_* tables** to a new contiguous block
   in the 0xA0000-0x18C100 gap freed up after v5.11.18's
   identifier-buffer raise to 256KB (still ~944 KB of headroom
   there). Each table at 64KB stride; new block ~448 KB.
2. **Double extended fn_* block** stride 0x8000 → 0x10000 (8
   tables, ~80 hex-literal edits).
3. **Shift primary fn_* block** forward to make room for doubled
   extended block, double its stride too (8 tables, ~80 edits).
4. **Shift IR + fixup regions** forward by 0x80000 (ir_nodes /
   blocks / state / edges / cp / fixup_tbl / brk-fixup-end).
5. **Update REGFN cap check** (`parse_fn.cyr:95`: 4096 → 8192) +
   warning thresholds (`main.cyr:1475-1479`, `main_win.cyr:761-765`,
   `util.cyr:401, 423`).
6. **Update heap-map comments** across `main.cyr` /
   `main_aarch64.cyr` / `main_aarch64_macho.cyr` /
   `main_aarch64_native.cyr` / `main_win.cyr` (~30 comment-line
   updates per file; the heap-map ASCII art is the source of
   truth for region offsets).
7. **Update fn_name_hash + fn_start_hash sizing** (currently 8192
   slots × 2B; doubled cap means 16384 slots × 2B = 32KB each to
   maintain the v5.10.41 load-factor target).

Estimated **~300-500 hex-literal edits** across `main.cyr` +
`main_aarch64*.cyr` (3 files) + `main_win.cyr` + `parse_fn.cyr` +
`backend/x86/fixup.cyr` + `backend/aarch64/fixup.cyr` +
`common/util.cyr`.

**Acceptance bar**:
1. cc5 self-host byte-identical fixpoint at the post-refactor
   size (cap raise IS a size change — every fn_* offset moves).
2. check.sh 66/66 + cyrius test 146/146 green.
3. kybernet 1.1.0 (full agnosys-full surface) compiles WITHOUT
   the `fn_table at 92%` warning.
4. Cross-host smoke green on all 4 hosts (this is the highest-risk
   slot of v5.11.x — heap-map refactor on a self-hosting compiler).

**Risk**: high. Self-host byte-identical is load-bearing — any
missed offset reference produces silent miscompile. Phased
internally with cc5 fixpoint check after each phase (relocate
scattered → double extended → shift+double primary → shift IR/
fixup → cap + warnings).

**Why pinned at .19 and not later**: kybernet 1.1.0 still hits
the warn threshold post-.18 (Part A.i only raised identifier
buffer; fn_table cap unchanged). Want this to land in the
buffer band, not at cycle close.

#### v5.11.20 — Syscall-wrapper DRY consolidation

**Pinned 2026-05-11 at v5.11.7 close from a lib refactor audit.**

`lib/syscalls_x86_64_linux.cyr` + `lib/syscalls_aarch64_linux.cyr`
peers have ~10+ wrapper fns with body-identical impls — the
divergence is only the `SYS_*` enum constant resolved per arch:

```
# Both peers identical at the wrapper layer:
fn sys_close(fd): i64 { return syscall(SYS_CLOSE, fd); }
fn sys_read(fd, buf, count): i64 { return syscall(SYS_READ, fd, buf, count); }
fn sys_write(fd, buf, count): i64 { return syscall(SYS_WRITE, fd, buf, count); }
# ...
```

**Refactor shape**: move the body-identical wrappers into a new
`lib/syscalls_linux_common.cyr` that includes both arch peers (for
the `SYS_*` enum values) and defines the wrappers once. The arch
peers shrink to just enum + arch-specific wrappers (anything where
arity / shape differs across arches).

**Identified candidates** (~10-12 fns, more under audit):
- `sys_close`, `sys_read`, `sys_write`, `sys_fstat`, `sys_fchmod`,
  `sys_exit`, `sys_execve`, `sys_getpid`, `sys_getppid`, `sys_kill`

**Acceptance bar**:
- Self-host byte-identical (refactor is shape-only).
- check.sh 66/66 + cyrius test 146/146 green.
- Pi cross-arch smoke green (aarch64 runtime — the diff target).
- Each consumer that includes `lib/syscalls.cyr` keeps working
  (selector still picks the right arch peer + new common file).
- Saves ~50-80 lines, ~20 fn dups.

**Risk**: medium — touches stdlib syscall layer. v5.11.20 places
this at start of the buffer band so emergent bugs can ride later
slots if needed.

#### v5.11.21 — 0-call public stdlib fn downstream survey

**Pinned 2026-05-11 at v5.11.7 close from a lib refactor audit.**

The audit found 10 PUBLIC stdlib fns with 0 callers across the
cyrius repo (`grep -rE` across all .cyr / .tcyr / .bcyr / .scyr).
Stdlib is consumed by downstream repos (kybernet, mabda, agnosys,
kavach, hadara, ai-hwaccel, libro, argonaut, bote, sigil, etc.),
so 0-call-in-grep is not safe-to-remove.

**The 10 candidates**:

| Module       | Fn                            | Likely purpose |
|--------------|-------------------------------|----------------|
| `async`      | `async_new`                   | bote / future async consumers |
| `callback`   | `for_each`                    | iterator-style consumer ergonomics |
| `grp`        | `grp_invalidate_cache`        | cache-flush ops (kavach? kybernet?) |
| `log`        | `log_init`                    | structured-log consumer entry point |
| `niyama`     | `niyama_bre_compile`          | one of 5 regex engines in niyama 1.0.1 fold |
| `pwd`        | `pwd_invalidate_cache`        | cache-flush ops |
| `sakshi`     | `sakshi_clock_recalibrate`    | long-running consumer recalibration |
| `sandhi`     | `sandhi_err_kind_name`        | diagnostic / pretty-print |
| `shadow`     | `shadow_invalidate_cache`     | cache-flush ops |
| `sigil`      | `sig_alg_name`                | pretty-print / introspection |

**Acceptance bar**:
- Survey each downstream repo (`grep -rn '<fn>(' ~/Repos/<dep>/`)
  for each of the 10 fns.
- Per-fn decision tree:
  - **Has consumer caller** → keep, document the consumer in the
    fn's docstring.
  - **No caller anywhere** → flag in CHANGELOG, mark deprecated
    in v5.11.21, drop in v5.12.x (or v6.0.0 closeout — fits the
    "dead-code sweep" item already pinned there).
  - **Speculative scaffolding for active work** (per `feedback_dead_code_audit_scope`)
    → keep, add roadmap pointer in the docstring.
- Output: a `docs/audit/2026-XX-XX-zero-call-stdlib.md` listing
  the decision per fn + rationale.

**Why this slot and not earlier**: low-priority cleanup work; no
consumer is blocked on these fns. Survey-and-decide doesn't ship
behavioral changes, just clarity + a deprecation plan if needed.

#### v5.11.23 — EOPEN_PE + ECREATEDIR/EDELETEF UTF-16 widening fix

**Pinned 2026-05-11 at v5.11.22 audit.** v5.11.22's debunk
investigation surfaced a pre-existing PE-emit bug: the UTF-16
widening + kernel32 path-API call pattern faults in
`ntdll!+0x41912` on Win11 26200 (cass). Affects EOPEN_PE
(CreateFileW, existing) and ECREATEDIR_PE / EDELETEF_PE
(CreateDirectoryW / DeleteFileW, new placeholders at v5.11.22).

**Diagnostic evidence (from v5.11.22)**:
- `_pe_exit_gate` (programs/check.cyr) tests `exit42` +
  `hello-world` only — never exercises any kernel32 path API.
  EOPEN_PE has been silently broken for an unknown number of
  minors.
- Wine 11.8 accepts the same binary; real Win11 26200 faults.
- `syscall(2, "C:\\test.tmp", 65, 384)` built with old cc5_win
  (5.11.18) AND new cc5_win (5.11.22) → both crash with
  STATUS_ACCESS_VIOLATION (0xC0000005) at ntdll offset 0x41912.
- Working PE routes that DON'T use widening: EWRITE_PE (1),
  EREAD_PE (0), ECLOSE_PE (3), EMMAP_PE (9), EEXIT (60),
  ELSEEK_PE (8), EGETTICKS_PE (228).
- Failing PE routes that DO use widening + kernel32 path API:
  EOPEN_PE (2), ECREATEDIR_PE (83, placeholder at .22),
  EDELETEF_PE (87, placeholder at .22).

**Acceptance bar**:
1. Bisect the widening + call pattern: hand-write a known-good
   PE that calls CreateDirectoryW with a hardcoded UTF-16
   string baked into .rdata (no runtime widening). If that
   works, the bug is in the widening loop. If it fails, the
   bug is in IAT setup / call convention / Windows path
   validation.
2. Fix the shared pattern in src/backend/x86/emit.cyr (and
   src/backend/pe/emit.cyr if IAT side needs adjustment).
3. Wire the real call bodies into ECREATEDIR_PE + EDELETEF_PE
   (replacing v5.11.22's -ENOSYS placeholders).
4. Add a new gate to programs/check.cyr::_pe_exit_gate (or a
   new sibling gate) that compiles `syscall(2, path, ...) +
   syscall(83, path, mode) + syscall(87, path)`, deploys to
   cass, runs, verifies success exit codes + filesystem
   side-effects. This keeps the bug class from regressing
   silently again.
5. cc5 self-host byte-identical.
6. check.sh 66+ green (new gate is +1).
7. cyrius test 147/147 green.
8. Cross-host smoke green (the new gate ARE the cross-host
   smoke for kernel32 path APIs).

**Risk**: medium. Touches PE emit + check.sh gates. Phased
internally: (a) reproduce on cass with hand-written PE to
isolate the widening, (b) fix, (c) wire bodies, (d) gate.
Per `feedback_premise_check_at_slot_entry` — empirical
bisect first, then commit to fix.

**Related**: v5.10.49 debunked a 15-slot "PE exit-code broken"
phantom caused by the cmd /v wrapper bug. THIS slot is the
inverse — a real PE bug that's been hidden because the
existing gate doesn't exercise it. The pattern: gate coverage
gaps mask real bugs that masquerade as wrapper issues when
consumers hit them.

#### v5.11.22 — ai-hwaccel cc5_win debunk + mkdir/unlink PE plumbing

**Pinned + shipped 2026-05-11.** ai-hwaccel 2.2.2 filed a
PE-exit-code-crash issue. Empirical audit on cass found:

- The minimal `syscall(60, 42)` repro WORKS on cass — exit=42
  via `cmd /v /c "...!errorlevel!"` AND `.bat` indirection.
  Hello-world (`syscall(1, 1, "hello\n", 6); syscall(60, 42)`)
  prints "hello" AND exits 42.
- Same cass: Win11 Pro 26200 (matches reporter's environment).
- Same binary bytes (1536 B, byte-identical between 5.11.5
  install bundle + 5.10.37 cross per the reporter's cmp).

This is the **second premise-debunk** in the v5.10-v5.11 cycle
(memory pin `feedback_windows_errorlevel_test_wrapper` records
v5.10.49's 15-slot fictional claim).

**Real gap surfaced by ai-hwaccel review**: ai-hwaccel.exe
crashes with STATUS_ILLEGAL_INSTRUCTION (0xC000001D) — not
the minimal-exit42 path, but the FULL binary. Three call sites
use unrouted Linux syscall numbers:

- `src/cache.cyr:174` — `syscall(83, ...)` (mkdir): not routed
- `src/cache.cyr:195` — `syscall(87, ...)` (unlink): not routed
- `src/detect/platform.cyr:41` — `syscall(89, ...)` (readlink): not routed

cyrius's compile-time warning IS firing for these, but the
text was stale: said "routes n=0,1,2,3,8,9,60" (missing 228).
No mention of the actual crash code (0xC000001D) consumers see.

**Shipped (this slot)**:

1. PE auto-import helpers `_pe_ensure_createdir` +
   `_pe_ensure_deletef` in `src/backend/pe/emit.cyr`.
2. Parser dispatch for `syscall(83, path, mode)` and
   `syscall(87, path)` in `src/frontend/parse_expr.cyr` →
   ECREATEDIR_PE / EDELETEF_PE.
3. Placeholder bodies: pop args, return -ENOSYS (-38).
   Held back from real CreateDirectoryW/DeleteFileW calls
   until v5.11.23 fixes the shared UTF-16-widening fault
   (see v5.11.23 detail above).
4. Updated warning text: now says
   `"routes n=0,1,2,3,8,9,60,83,87,228 today; others crash
   with STATUS_ILLEGAL_INSTRUCTION (0xC000001D)"`. Names the
   actual crash code so consumers can grep for it.
5. ai-hwaccel issue archived with debunk evidence +
   `#ifdef CYRIUS_TARGET_WIN` guidance for their readlink call
   (no clean Windows equivalent; Windows symlinks need
   DeviceIoControl + FSCTL_GET_REPARSE_POINT — multi-slot scope).

**NOT shipped (pinned v5.11.23)**: the actual CreateDirectoryW
/ DeleteFileW call bodies. Hardcoded -ENOSYS in placeholders
until the widening-pattern bug is fixed.

**Cass verify (this slot's placeholder)**:
- `var rc = syscall(83, "C:\\x", 493); syscall(60, 0 - rc);`
  → exit=38 (= -(-38)) — consumer's `if (rc < 0)` path fires
  CLEANLY instead of STATUS_ACCESS_VIOLATION.
- No more access violations on cass for these syscalls.
- cc5 byte-identical at 806,104 B (+1,648 B from auto-imports
  + parser dispatch + placeholder bodies).

#### v5.11.22-RETIRED — cc5_win PE exit-code crash + WriteFile stdout fix

**HIGH-severity blocker** filed 2026-05-11 by ai-hwaccel 2.2.2.
Pinned to the gap per user direction at v5.11.10 close. Full repro
+ analysis in
[`docs/development/issues/2026-05-11-ai-hwaccel-cc5-win-pe-exit-propagation.md`](issues/2026-05-11-ai-hwaccel-cc5-win-pe-exit-propagation.md).

**Symptom**: minimal `syscall(60, 42);` compiled with `cc5_win`
produces a PE32+ that **loads and starts** on Windows but **crashes
before reaching `ExitProcess(42)`**. Exit code is `0x40001000`
(1,073,745,920) instead of `42`. Hello-world (`syscall(1, 1, ...);
syscall(60, ...)`) — WriteFile stdout NEVER lands, same crash.

**Reproduces across**: v5.11.5 install bundle's cc5_win, v5.10.37
`cc5_win_cross` source build (byte-identical PEs), with both
`cmd /v /c "exe & echo !errorlevel!"` and `.bat` indirection.
Known-good `cmd /c "exit 42"` propagates cleanly — so the Windows
loader / cmd exit-code plumbing is fine; bug is in the PE itself.

**Status code analysis**: `0x40001000` has the high byte `0x40`
(informational, not error) but doesn't match any well-known
`STATUS_*` constant (not `STATUS_BREAKPOINT`, `DBG_CONTROL_C`,
`DBG_PRINTEXCEPTION_C`, or `STATUS_ACCESS_VIOLATION`). PE header
looks structurally fine on `xxd` inspection (MZ + PE at +0x40,
machine 0x8664, valid SizeOfHeaders, IAT references kernel32.dll
+ ExitProcess).

**Hypothesis** (from the issue file): malformed entry-point or IAT
setup — loader runs the image, user code never executes, Windows
synthesizes some default informational exit before the syscall
reroute fires.

**Bisect candidates** flagged by the reporter:
- 5.10.47 — first PE+struct-byval Phase 3 test on cass passing.
- 5.10.49 — premise-debunk slot, "cass: exit=42 ✓" claimed.
- 5.11.5 — `cc5_win` added to release tree.
- 5.11.6 — install.sh refresh — slot entry mentioned "CRLF quirk
  surfaced — separate item". The reporter notes that "separate
  item" was likely never tracked; this filing fills the gap.

**Internal load-bearing check**: `programs/check.cyr`'s
`_pe_exit_gate` uses .bat indirection and runs as part of check.sh.
Currently passing — so either:
(a) the gate's test fixture is built with a NEWER (post-v5.11.6)
    cc5_win that emits a different shape than the install bundle, or
(b) the regression is between the gate's last successful run and
    the v5.11.5 cc5_win shipped to ai-hwaccel.

Slot work has to disambiguate. Start by running the issue's exact
repro against current `build/cc5_win_cross` AND
`~/.cyrius/versions/5.11.10/bin/cc5_win` — confirm whether the bug
reproduces in-house before changing anything.

**Acceptance bar**:
1. `echo 'syscall(60, 42);' > /tmp/exit42.cyr && cc5_win < /tmp/exit42.cyr > /tmp/exit42.exe`
   produces a PE32+ that runs on cass with `exit=42` (not 0x40001000).
2. Hello-world fixture (`syscall(1, 1, "hello\n", 6); syscall(60, 42);`)
   produces a PE that writes "hello\n" to stdout AND exits 42.
3. `programs/check.cyr`'s `_pe_exit_gate` continues to pass.
4. Cross-host smoke: cass runtime green on the minimal +
   hello-world fixtures.
5. ai-hwaccel-side: their `tests/regression-pe-exit.sh`
   cross-host validation can be re-enabled and passes.

**Risk**: medium-high. PE backend bugs are subtle (entry-point
shape, IAT layout, relocation tables); a fix may need to touch
`src/backend/x86/emit.cyr`'s PE-specific paths AND
`src/backend/x86/fixup.cyr`'s PE fixup walker. Self-host
byte-identical is required (PE backend changes shouldn't affect
x86 Linux ELF emit), plus cross-host smoke green on all 4 hosts.

**Why pinned at .22 and not earlier**: user direction at v5.11.10
close — "plan it in the gap" preserved the existing pins at .20
(syscall DRY) and .21 (0-call survey). At consolidation (v5.11.15
close) the whole pinned block shifted back 2 to close the .16-17 gap;
this slot rode along. The next emergent fixup (`#derive(accessors)`
16-field cap, agnos 1.28.3, 2026-05-11) pinned at .23. The v5.11.18
audit split off kybernet Part A.ii to its own slot (v5.11.19),
shifting every subsequent pin forward by 1 (this slot .21 → .22).

#### v5.11.24 — `#derive(accessors)` >16-field silent miscompile fix

**Pinned 2026-05-11 at v5.11.15 close alongside the WS handshake
slot.** Filed by agnos 1.28.3 during a kernel `struct Process`
(22 fields) refactor; full repro + analysis in
[`docs/development/issues/2026-05-11-derive-accessors-16-field-cap.md`](issues/2026-05-11-derive-accessors-16-field-cap.md).

**Symptom**: `#derive(accessors)` on a struct with > 16 fields
compiles without diagnostic but emits accessor fns at wrong byte
offsets. Stores land in the wrong slot; loads return stale /
corrupted values. Manifests in agnos as `CR3=0x2` page-fault on
first context switch (proc_get_cr3 reading a clobbered field).

**Root cause**: `src/frontend/lex_pp.cyr`'s `PP_PARSE_STRUCT_DEF`
walks the struct body and writes per-field metadata into three
hard-sized-at-16 tables:

```
S+0x197060: field_names[16][32]   (512 B)
S+0x197260: field_types[16][32]   (512 B)
S+0x197460: offsets[16]           (128 B)
```

No bounds check. The 17th field's name (`fc = 16`) writes to
`S + 0x197060 + 16*32` = `S + 0x197260` — **clobbering
field_types[0]**. Subsequent fields cascade the overflow into the
adjacent `offsets` region; `PP_DERIVE_ACCESSORS_BODY` reads
corrupted "type indicator" bytes and emits accessors with offsets
that don't match the actual struct layout.

**Fix shape** (per the issue's "Suggested fix" section):

1. Raise the per-struct field cap from **16 → 32** (or 64 if
   downstream caller patterns warrant — 32 covers agnos's worst
   case at 22 fields with 10-slot headroom). Three regions resize:
   `field_names[N][32]`, `field_types[N][32]`, `offsets[N]`.
2. Downstream layout boundary `S+0x197500` moves up by
   `(N - 16) * 72` bytes. Update the heap-map and every per-struct
   table base that follows.
3. Add a hard-cap diagnostic in `PP_PARSE_STRUCT_DEF`:
   ```
   if (fc >= FIELD_CAP) {
       PP_ERROR("too many fields in struct (max ", FIELD_CAP, ")");
       return ip;
   }
   ```
   An explicit error beats silent miscompilation — the 17th-field
   overflow cost agnos days of kernel-debugging before the
   metadata-clobber theory landed.

**Acceptance bar**:
1. agnos's `struct Process` (22 fields) ports cleanly with
   `#derive(accessors)` and the kernel boots through first
   context switch without `CR3=0x2`.
2. New regression test (`tests/tcyr/derive_accessors_large.tcyr`)
   exercising a 17-field struct: `S_set_f16(p, 0xCAFE)` then
   `load64(p + 128) == 0xCAFE`. Without the fix this asserts
   to a wrong offset; with the fix it passes.
3. Hard-cap diagnostic test (`fuzz/fcyr` or equivalent
   compile-fail fixture): struct with `FIELD_CAP + 1` fields
   produces the new diagnostic, not a silent miscompile.
4. cc5 self-host byte-identical (the struct-metadata tables
   exist in the compiler itself — none of cc5's own structs
   exceed 16 fields today, but the heap-map shift moves
   downstream regions; verify the resize doesn't cascade).
5. Cross-host smoke green on all 4 hosts.

**Risk**: medium. Touches lex_pp.cyr's per-struct metadata layout
+ heap-map. Adjacent regions cascade. Self-host byte-identical is
load-bearing — the cap raise shifts every per-struct table base
that lives above `S+0x197500`.

**Why pinned at .23**: emergent consumer-filed fixup; rides the
band that opened up after consolidation closed .16-17. Bundle
with the PE exit-code fix at .22 as the second compiler-side bug
fix in the cluster. Shifted from .22 → .23 at v5.11.18 audit when
kybernet Part A.ii split off to .19.

**Agnos-side status**: workaround in place at 1.28.3 (reverted
`#derive(accessors)` on `Process`, kept raw `load64`/`store64`
+ documented byte offsets in the struct comment). Re-port to
`#derive(accessors)` becomes an agnos-side follow-up once this
slot ships.

#### v5.11.25 — Per-repo isolation Part 2: `cyrius` CLI version-resolved dispatcher

**Pinned 2026-05-11 at v5.11.16 close from the 3-slot reframe
of the original v5.11.17 acceptance bar (user direction:
"Reframe — split into 3 slots").**

**Scope**: the `cyrius` binary (`programs/cyrius.cyr` /
`cbt/cyrius.cyr`) becomes version-resolved at every command
entry. Before dispatching to any subcommand, it:
1. Walks `cwd` and parents looking for `cyrius.cyml`.
2. If found, parses the top-level `cyrius = "X.Y.Z"` field.
3. If the field's version != current binary's version: re-execs
   `~/.cyrius/versions/<v>/bin/cyrius` with the same argv.
4. If the field's version is NOT installed at
   `~/.cyrius/versions/<v>/`: errors out clearly with the
   pinned version + `cyrius install X.Y.Z` suggestion.
   **Never silently slides to `latest`.**
5. If no `cyrius.cyml` is found (or no `cyrius` field), falls
   back to current global-default behavior.

**Why pinned at .24 and not earlier**: multi-slot architectural
change — every cyrius CLI entry point needs the re-exec wrapper,
and the re-exec needs to be idempotent (the re-execed binary must
NOT re-walk and re-exec into a third process). Loop guard via
`CYRIUS_RESOLVED=1` env var or similar. Touches dispatch, but
NOT compiler internals — cc5 should remain byte-identical.

**Acceptance bar**:
1. From a repo with `cyrius = "5.11.X"` in `cyrius.cyml`:
   running `cyrius <any-cmd>` from a globally-different
   toolchain version dispatches to the pinned version's
   binary; output identical to running it directly.
2. Pinning to a NON-installed version produces a clear error,
   not a silent slide to `latest`.
3. Loop protection: `CYRIUS_RESOLVED=1` (or equivalent) set on
   re-exec; second-pass binary skips the resolution walk.
4. Companion tools (`cc5` invoked via cyrius, `cyrfmt`, `cyrlint`,
   `ark`) inherit the resolved version's binary layer when
   spawned by `cyrius`.
5. cc5 self-host byte-identical.
6. check.sh 66/66 + cyrius test 146/146 green.
7. Cross-host smoke green on all 4 hosts.

**Risk**: medium-high. CLI dispatcher is consumed by every cyrius
user; loop bugs would lock out the CLI. Acceptance-bar item #3
(loop protection) is load-bearing.

**Pairs with v5.11.17** (deps stdlib_dir fix) — Part 1 closed the
actual wipe wedge; Part 2 makes the version-pinning intentional
+ visible. Without Part 2, a repo whose `cyrius.cyml` pins
`5.10.44` still runs whatever's at `~/.cyrius/current` for CLI
dispatch — Part 2 makes the pin authoritative.

#### v5.11.26 — Per-repo isolation Part 3: `cyriusly use --global` flag

**Pinned 2026-05-11 at v5.11.16 close from the 3-slot reframe
of the original v5.11.17 acceptance bar.**

**Scope**: `programs/cyriusly.cyr`'s `use` verb (today at line
176-202, writes `~/.cyrius/current`) gets the following shape:

```
cyriusly use 5.11.X            # NEW DEFAULT — writes cyrius.cyml's
                               # top-level cyrius field in cwd
cyriusly use 5.11.X --global   # legacy behavior — writes
                               # ~/.cyrius/current
```

Sibling agents (agnosys, mabda, ai-hwaccel) that want to flip the
GLOBAL toolchain for their tests must now pass `--global`
explicitly. Quiet, in-repo workflow (the common case) stops
mutating global state.

**Why pinned at .25 and not earlier**: depends on Part 2's
cyrius.cyml resolution to actually take effect. Shipping Part 3
before Part 2 would write the cyml field but cyrius CLI wouldn't
honor it — confusing half-state.

**Acceptance bar**:
1. `cyriusly use 5.11.X` (no flag) from a repo with `cyrius.cyml`:
   updates the file's `cyrius` field to "5.11.X"; leaves
   `~/.cyrius/current` untouched.
2. `cyriusly use 5.11.X --global`: writes `~/.cyrius/current`
   (legacy behavior; cyrius.cyml not touched).
3. `cyriusly use 5.11.X` from a directory WITHOUT a `cyrius.cyml`
   anywhere up the tree: error message instructs user to either
   `cd` to a project or pass `--global`. **Don't silently fall
   back to `--global`.**
4. `cyriusly use` (no version arg): print the resolved version
   (per Part 2's priority: cyml → current → latest) + the
   source (`cyrius.cyml at /path/`, `~/.cyrius/current`, or
   `latest fallback`).
5. cc5 self-host byte-identical.
6. check.sh 66/66 + cyrius test 146/146 green.
7. Cross-host smoke green.

**Risk**: low. Localized to `programs/cyriusly.cyr` (binary in
`[release].bins` since v5.11.10). Behavior change is opt-out
(`--global`), so existing sibling-agent invocations need a one-line
patch to add the flag.

**Sibling-agent migration**: agnosys / mabda / ai-hwaccel
`cyriusly use <v>` lines need to add `--global`. Communicate
during the v5.11.25 ship.

**Held-forward items (no slot pinned; surface-on-ask)**: Class B
FFI/wgpu fncall6 ABI (mabda B1/B2), `cyim` regex parse error,
`float.cyr:41` peephole.

Item details below.

- **`cyrius deps` file-copy instead of symlink for resolved deps**
  (pinned 2026-05-10 at v5.10.37 ship). User direction:
  *"yeah lets do a C with A plan longer term... will need to
  get some time to work on mabda GA"*.

  **Background**: pre-GA deps (e.g. mabda 3.0.0-rc.2) currently
  get **symlinked** into the consumer's `lib/<dep>.cyr` from
  `~/.cyrius/deps/<dep>/<ver>/dist/<dep>.cyr` by `cyrius deps`
  resolution. When `install.sh --refresh-only` runs the snapshot
  copy loop (`cp -L lib/*.cyr ~/.cyrius/versions/<v>/lib/`),
  both source and destination dereference to the same inode if
  the snapshot already has a parallel dep-symlink, and `cp`
  errors with *"are the same file"*. `set -e` then kills the
  install before the symlink-update block at install.sh:249-251
  reaches `rm -rf ~/.cyrius/{bin,lib} && ln -sf
  versions/$VERSION/...`. Result: `~/.cyrius/bin` /
  `~/.cyrius/current` stay pinned at the previous version,
  `cyrius-prompt-info` reads stale toolchain version, and the
  user-visible symptom looks like prompt-config corruption.

  **The fix shape (Option C from the v5.10.37 discussion)**:
  change `cyrius deps` resolution so non-folded deps get a
  physical file copy into `lib/<dep>.cyr` instead of a symlink.
  The dep cache at `~/.cyrius/deps/<dep>/<ver>/dist/` remains the
  immutable source; `cyrius deps` becomes a cp-from-cache step
  rather than a `ln -sf` step. Then install.sh's `cp -L` sees
  distinct inodes at every layer (project → snapshot, project →
  cache) and the same-file collision can't fire.

  **Acceptance bar**:
  1. `cbt/deps.cyr` resolution path: replace the symlink emit
     (currently around the `_dep_copy_file` or equivalent
     helper that creates `lib/<dep>.cyr`) with a copy that
     reads bytes from `~/.cyrius/deps/<dep>/<ver>/dist/<dep>.cyr`
     and writes them to `lib/<dep>.cyr`. Update mtime preserved
     or not — call out which (mtime preservation has
     implications for `-nt` rebuild checks in
     `_rebuild_stale`).
  2. Cross-consumer verification: in every ecosystem repo
     using a pre-GA dep symlink, `rm lib/<dep>.cyr && cyrius
     deps` produces a plain file (not symlink). Verify with
     `ls -la lib/`.
  3. `install.sh --refresh-only` succeeds end-to-end including
     the symlink-update block (verified by `readlink
     ~/.cyrius/bin` matching the new version after `version-
     bump.sh`).
  4. `cyrius deps --check` (if implemented) detects when the
     project's `lib/<dep>.cyr` content drifts from the cache —
     same-as-symlink invariant under copies.
  5. The `cp -L same-file` defensive guard in install.sh
     (per the v5.10.50 closeout pin) is ALSO landed as
     belt-and-suspenders even with this fix.

  **Long-term plan — Option A fold-in cadence** (per-dep,
  ongoing): each pre-GA dep that reaches a 1.0.0 / 2.0.0 / 3.0.0
  release gets folded byte-identical into `lib/<name>.cyr` via
  the v5.8.65 pattern (committed file, `cyrius.cyml` updated).
  Once a dep is fully folded, the `[deps.<name>]` git resolution
  is replaced by a fold-pin entry — `cyrius deps` becomes a
  no-op for that dep. Slot list (refines as deps land):
  - **mabda 3.0.0 GA** — user-flagged needs work time;
    promote from `[deps.mabda]` to fold once GA tagged.
  - Future pre-GA deps follow same pattern.
  The fold cadence isn't pinned to specific slot numbers —
  it lands when the dep hits GA, alongside its consumers'
  pin bumps.

- **`tests/regression-*.sh` → cyrius port arc**
  (pinned 2026-05-10 at v5.10.36; paired with TS test harness
  per user direction *"any newly added regression.sh scripts
  will be apart of 5.11.x before TS test work since they seem
  good to go together later in the cycle"*).

  v5.x has been progressively converting bash regression
  gates into cyrius-native bespoke gates in
  `programs/check.cyr` (see CLAUDE.md DO NOT bullet on
  `regression-X.sh` retirement). A small number of `.sh`
  gates remain — including the v5.10.50-pinned
  `_cyriusly_starship_add_only_gate` whose subject is itself
  the shell `scripts/cyriusly`. Folding the remaining `.sh`
  gates into cyrius lands in v5.11.x **BEFORE** the TS test
  harness because the harness work benefits from a
  fully-cyrius gate surface to consume.

  **Acceptance bar** (multi-patch, refine at slot entry):
  1. Inventory: walk `tests/regression-*.sh` (if any remain)
     + the v5.10.50 closeout-investigation gate, list each
     subject + assertion shape.
  2. Per-gate: rewrite as a bespoke fn in
     `programs/check.cyr` using `lib/regression.cyr` helpers
     (same shape as `_macho_exit_gate` / `_pe_exit_gate`).
  3. **Cyriusly cmdtools port** — the v5.10.50 starship
     add-only gate's subject is shell. Port the cmdtools
     install/remove paths (currently `scripts/cyriusly:160+`)
     into a cyrius binary or `cyrius` sub-command first, so
     the gate's subject is itself cyrius. This is the bigger
     scope of the two paired items.
  4. Once gates + cyriusly are cyrius-native, the
     `scripts/cyriusly` shell file shrinks to whatever can't
     yet be cyrius (or retires entirely).
  5. Self-host byte-identical x86 + cross-host SSH cluster
     green per memory pin
     `reference_verification_hosts_ssh`.

- **TS test harness program** (option E from v5.7.37) —
  single `programs/ts_test_runner.cyr` consuming both
  internal-symbol fn dispatch and TS fixture files.
  v5.7.37 group-level consolidation has held since 2026-04
  through every v5.7.x → v5.10.x cycle; promoting to the
  v5.11.0 slot at v5.10.20 P(-1) sweep so it lands when a
  downstream consumer surfaces a test pattern that doesn't
  fit either current shape. Lands AFTER the
  `tests/regression-*.sh` → cyrius port arc (user pairing
  direction above) so the harness has a fully cyrius-native
  gate surface to integrate with. Otherwise stays
  opportunistic — the stdlib annotation arc takes the
  primary v5.11.x slot sequence.
- **Other v5.10.x leftovers** that surface during the cycle
  close — refine at first slot entry per
  `feedback_premise_check_at_slot_entry`.

#### Consumer-filed issues (2026-05-10 wave — bote / daimon / kavach)

Seven issues filed on 2026-05-10 during the v5.10.x close.
Listed by priority + likely slot affinity. All are in
[`docs/development/issues/`](issues/) with full repro + fix
shape. Per `feedback_priority_bottom_to_top` and
`feedback_consumer_request_full_surface`: P1 lands earliest;
ship the full filed surface, not the easy half.

- **P1 — `kavach`: sandbox-relevant syscall wrappers**
  ([2026-05-10-kavach-sandbox-syscall-wrappers.md](issues/2026-05-10-kavach-sandbox-syscall-wrappers.md)).
  Six post-fork-relevant Linux syscalls have no stdlib
  wrapper in `lib/syscalls.cyr` (`unshare`, `setns`,
  `pivot_root`, `chroot`, `mount`, `umount2`). kavach
  currently inlines them as bare `syscall(N, ...)` calls;
  stdlib wrappers enable type-checked sandbox config and
  cross-arch (x86_64 + aarch64) syscall-number parity.
  Likely shape: small per-syscall fns added to
  `lib/syscalls_x86_64_linux.cyr` + `_aarch64_linux.cyr`
  parallel mirrors. Single slot.

- **P2 — `daimon`: aarch64 `sys_epoll_wait` undefined**
  ([2026-05-10-daimon-async-aarch64-sys-epoll-wait.md](issues/2026-05-10-daimon-async-aarch64-sys-epoll-wait.md)).
  `lib/async.cyr` references `sys_epoll_wait` at lines 117
  + 145 which isn't defined for aarch64 (x86_64 has it).
  Cross-arch propagation gap per
  `feedback_cross_arch_propagation_mandatory`. Single-slot
  fix in `lib/syscalls_aarch64_linux.cyr`.

- **P2 — `bote`: `lib/net.cyr` recv_timeout +
  `getaddrinfo`-equivalent**
  ([2026-05-10-bote-net-stdlib-recv-timeout-and-getaddrinfo.md](issues/2026-05-10-bote-net-stdlib-recv-timeout-and-getaddrinfo.md)).
  Two stdlib net gaps; bote ships fine without them today
  but the audit-deferral pattern flags both. Likely
  multi-piece (recv_timeout = setsockopt SO_RCVTIMEO call;
  getaddrinfo-equivalent = larger surface, may stage).

- **P2 — `bote`: arena allocator `fl_free` for reuse**
  ([2026-05-10-bote-fl-free-for-arena-reuse.md](issues/2026-05-10-bote-fl-free-for-arena-reuse.md)).
  `lib/alloc.cyr` bump allocator has no free-list reclaim
  — long-running WS/streaming servers leak. Likely shape:
  free-list-on-arena variant alongside the existing bump
  allocator. Pairs with the streaming-dispatch item below
  (same consumer / same workload).

- **P2 — `bote`: streaming dispatch + thread async
  primitives**
  ([2026-05-10-bote-streaming-dispatch-thread-async-primitives.md](issues/2026-05-10-bote-streaming-dispatch-thread-async-primitives.md)).
  MCP-spec capability items the bote roadmap has carried
  since pre-v5.10.x. Probably multi-slot — concurrency
  primitives are a non-trivial stdlib surface. Pair
  scheduling with the `fl_free` item if both touch
  `lib/alloc.cyr` / `lib/thread.cyr`.

- **Low — `bote`: WS server handshake key validation
  (RFC 6455)**
  ([2026-05-10-bote-ws-server-handshake-key-validation.md](issues/2026-05-10-bote-ws-server-handshake-key-validation.md)).
  RFC 6455 §4.1 conformance gap; not exploitable. One-line
  validation add. Easy ride-along with other ws_server
  changes if any surface.

- **Low — parser: `assert_eq(my_fn("literal"))` quirk**
  ([2026-05-10-parser-assert-call-string-literal-quirk.md](issues/2026-05-10-parser-assert-call-string-literal-quirk.md)).
  Parser cosmetic — has one-line workaround. Bundle into a
  defensive sweep slot toward the v5.11.x close (same
  shape as the v5.10.48 parser-cosmetics bundle).

#### Held forward from v5.10.x (carried, not pinned)

- **Class B FFI / wgpu fncall6 ABI** (mabda B1/B2). Held
  per v5.10.20 P(-1) sweep ("leave mabda issue out to be
  held"). Land if mabda resurfaces it; otherwise stays
  held-forward.
- **`cyim` regex pattern parse error** (mabda C6). Surface-
  on-ask; cyim consumer hasn't surfaced a concrete repro.
- **`float.cyr:41` peephole pattern** (audit §4). Perf opt;
  preflight with bench delta before pinning.

**Cycle close re-pinned at v5.11.68 / v5.11.69 pair** (user
direction 2026-05-12) — v5.11.x is now the **FINAL 5.x minor**.
The .68 slot does the true closeout engineering (heap-map full
reorg); .69 is reserved as the fold-applied tag for any dep
foldins that arrive during the window (mabda 3.0 GA conditional).
If no fold lands, .68 is the final v5.x patch. The original .40 cap
was set to protect v5.12.0's bare-metal/RISC-V kickoff; with
that arc moving to v6.x (tight-close decision, see [v6.x section](#v6x--platform-expansion--advanced-features)),
v5.11.x absorbs the remaining 5.x-flavored work that previously
lived in long-term considerations or v5.12.x scope:

### Remaining slots toward close (v5.11.32 → v5.11.69)

**v5.11.32 — User-binary ELF cleanup (x86 user emitter)** [SHIPPED]

`EMITELF_USER` at `src/backend/x86/fixup.cyr:827` now emits the
same 5-section ELF64 table as the .29/.30/.31 kernel + linker
emitters. See CHANGELOG `[5.11.32]`.

**v5.11.33 — `PP_IFDEF_PASS` 2 MB cap raise (cascade-in)**

Pinned 2026-05-12 per sit v0.7.6 → v0.8.x filing
[`docs/development/issues/2026-05-12-pp-2mb-cap-blocks-sit-on-sandhi-fold.md`](issues/2026-05-12-pp-2mb-cap-blocks-sit-on-sandhi-fold.md).
Cascaded in ahead of the aarch64 user-emitter; the EMITELF
aarch64 cleanup moves to v5.11.34. Backstop pins (.68/.69)
unchanged.

Sit's expansion of `[deps].stdlib` listing `sandhi` measures
2,099,593 bytes — 2,441 over the 2 MB `PP_IFDEF_PASS` cap.
sandhi accreted TLS 1.3 0-RTT (v1.3.2), session-cache cred-strip
(v1.3.3), and annotation pass (v1.3.4) silently across .10.x →
.11.x; the cap was last sized in v5.6.40 (1 MB → 2 MB) before
sandhi folded. Blocks every AGNOS consumer that lists `sandhi`
in `[deps].stdlib` (canonical service-boundary shape; sit /
hoosh / ifran / daimon / mela / yantra / ark all path through
this).

Scope: raise the cap + buffer pair (currently 2 MB at
`0x44A000`) to 4 MB per issue's primary recommendation, OR a
smaller bump (2.5–3 MB) if the heap-map move is best deferred
to v5.11.68's full reorg. **Heap implications**: `preprocess_out`
sits between `str_data` (0x21A000) and `codebuf` (0x64A000)
exactly 2 MB wide — in-place growth requires shifting `codebuf`
+ `output_buf` + everything downstream, OR moving
`preprocess_out` into the 6 MB gap at `0xB4A000..0x114A000`
documented in v5.8.61's minimum-blast-radius pass. Touch points:
`src/frontend/lex_pp.cyr` (cap checks + tmp mmap size at lines
1687, 2012, 2025); heap-map headers in `src/main.cyr` +
`src/main_aarch64*.cyr` + `src/main_win.cyr`. Two-step bootstrap
required (heap change).

**v5.11.34 — User-binary ELF cleanup (aarch64 user emitter)**

Cascaded from .33 at 2026-05-12 cap-repair re-pin.

Mirror v5.11.32 into `EMITELF` at
`src/backend/aarch64/fixup.cyr:323` (ELF64). Same 5-section
pattern. Closes the section-header arc cleanly — `objdump -d` /
`gdb` / `ltrace` / `readelf -S` / IDE symbol indexers all see
real section info on every Cyrius user binary.

Not MVP-blocking (`execve` ignores section headers) but worth
the slot for consistency with the kernel/linker/user-x86 fixes
already shipped, and for downstream tooling that introspects
ELF sections.

**v5.11.x mid — Stdlib data-domain distlib carve-out**

Originally pinned 2026-05-05 at v5.8.65 close as "re-pin to
v5.10.x late or v5.11.x"; slipped through v5.9.x (filled with
sovereignty pass) and v5.10.x (filled with three-arc substrate).
Lands here.

Scope: ~13 data-domain modules (`json`, `toml`, `cyml`, `csv`,
`base64`, `regex`, `math`, `matrix`, `linalg`, `bigint`, `u128`,
plus their friends) fold out into a `cyrius-data` sibling
distlib using the v5.7.0 sandhi-pattern (sakshi / patra / sigil
precedent). Stdlib stays primitives-only after the carve;
bare-metal consumers in v6.x's RISC-V / firmware work won't
drag the data offshoots into kernel objects.

**v5.11.x mid — Parser-to-emit named-op refactor (path A)**

Originally pinned to v5.11.x → v5.12.x at v5.9.7 ship per the
RISC-V "4th backend trigger" condition. With RISC-V moving to
v6.x, the strict trigger lifts — but the refactor still earns
its slot in 5.x close for compiler hygiene: ~10 abstract ops ×
3 backends (x86 / aarch64 / cx) = ~30 fn definitions plus
parse_*.cyr rewrites. cx benefits immediately; v6.x's RISC-V
backend lands on the named-op interface from day one instead
of plumbing through `_TARGET_*` chains.

Audit doc: [`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md).

**v5.11.x late — Sovereignty / polish / consumer-filed**

Whatever surfaces from consumer-filed bugs, doc-health audit,
TS-frontend held-forward items, peephole patterns deferred
(`float.cyr:41` if bench delta justifies it), `cyim` regex if
it surfaces, agnosys post-release polish. Bundle per
cycle-discipline; resist single-item slots (see [Slot acceptance principle](#slot-acceptance-principle-revised-at-v5100)).

**v5.11.x — mabda 3.0 GA fold (CONDITIONAL, watching window)**

Watching this 2026-05-12 → ~mid-cycle: **if mabda 3.0 GA cuts
during the v5.11.x window**, fold mabda into stdlib using the
v5.7.0 sandhi pattern (sakshi 2.2.3 / patra 1.9.3 / sigil 3.1.0
/ vani 0.9.2 / yukti 2.2.2 / sankoch 2.2.4 precedent in v5.8.x;
niyama 1.0.1 in v5.9.x). Sister fold: agnosys (transitive via
mabda).

**Soak gate**: mabda 3.0.0-rc.2 is currently running its
**24-hour passing soak** (project-leader-set standard for GA
promotion). 2-hour window observed clean at 2026-05-12 session;
remaining 22 hours decide whether GA cuts inside the v5.11.x
window.

**Backstory worth remembering** (per project-leader 2026-05-12):
mabda was the last "old" stdlib dep still pinned at a pre-fold
tag (`[deps.mabda] tag = "2.5.0"`) — a lock-in that prevented
cyrius from bumping to consume newer mabda RCs without the
fold/bump ceremony. Didn't block mabda's RC publishing on its
own cadence, but it did concentrate dep-update pressure into
the GA cut. **Pattern to avoid in future fold cycles**: don't
let stdlib `[deps.*]` pins drift past the consumer's last
working tag without a planned unlock; the sandhi fold IS the
unlock, so schedule the fold close to the dep's next GA rather
than letting the gap widen.

**Why this fits 5.x close** (despite the language-feature
exclusion rule): the fold itself is **stdlib hygiene, not a
language capability addition** — it vendors source byte-identical
into `lib/mabda.cyr` and removes the git-dep resolution. No new
ABI, no new language syntax, no new backend. Same shape as the
six v5.8.x sandhi folds that shipped without anyone treating
them as new capabilities.

**Decoupled from Class B FFI / wgpu fncall6 ABI**: that's the
*language-level* ABI work (held-forward through v5.9.x →
v5.11.x); stays in v6.4.x as a capability addition regardless
of whether the fold lands earlier. The mabda 3.0 GA fold can
proceed in v5.11.x **only if mabda 3.0 GA shipped without
needing the Class B FFI fix to be functional** (e.g., the
consumer routed around the ABI bug or the GA surface doesn't
hit fncall6). If mabda 3.0 GA gates on the ABI work, both
fold + ABI move together to v6.4.x.

**Slot-entry check**: at the moment mabda 3.0 GA cuts, re-verify
the Class B FFI gate per `feedback_premise_check_at_slot_entry`.
If GA works clean: fold here. If GA still leans on Class B FFI:
both move to v6.4.x. No mid-window auto-promotion.

**v5.11.68 — Heap-map full reorganization (true closeout)**

Originally pinned 2026-05-05 at v5.8.61 ship as the documented
"last-minor-before-v6.0 effort." Lands as the **true closeout
slot** of v5.11.x — the last substantive engineering work
before v6.0.0 opens.

**Why .68 and not .69**: v5.11.69 is reserved as the
**fold-applied tag** for any dep foldins that earn their slot
during the window (mabda 3.0 GA being the live candidate, see
the [conditional slot above](#v511x--mabda-30-ga-fold-conditional-watching-window)).
If no fold lands in the window, .68 is the final v5.x patch
and .69 is unused. If a fold lands, .69 = .68 + fold-applied
(byte-identical sandhi-pattern vendor of source, drop the
`[deps.*]` entry, regen). The .68/.69 split keeps the heavy
heap-map engineering and the conditional fold cleanly
bisectable.

The remaining gaps post v5.8.61's minimum-blast-radius reorg
(~22 MB of unused heap reserved as documented headroom):

- `0x41A000..0x44A000` (192 KB) — pad before preprocess_out
- `0xB4A000..0x114A000` (6 MB) — output_buf → struct_ftypes gap
- `0x115A000..0x11CA000` (450 KB) — struct_ftypes → struct_fnames
- `0x11DA000..0x128A000` (700 KB) — struct_fnames → fn_names
- `0x290B000..0x368C000` (13.5 MB) — **TS frontend functional
  reservation; DO NOT CLOSE** unless TS frontend is retired

Closeable: 8.4 MB across 4 gaps. ~200 references to shift
across struct_*/fn_*/ir/fixup/tok region offsets + ~750
references to relocate scratch state at `0x18C100..0x1A6018`.

Done as its own slot (not bundled) per cycle-discipline ("Big
Heavy One Thing"). Substantial enough that bundling would
obscure the bisect target if anything regresses; the v5.8.61
minimum-blast pass already proved the safer per-region approach
is viable.

### Buffer between named slots

The band between named slots (.34 → .68, roughly 35 slots) is
the explicit absorber for items that surface during the cycle:
emergent consumer bugs, doc-health follow-ups, the items still
in [Long-term considerations](#long-term-considerations-no-version-pin-yet)
that earn a slot as their trigger condition materializes, plus
the in-progress and yet-to-arrive sub-patches of the named
arcs above. Same default-bias as before — ride the cap rather
than silently expanding; if the buffer truly fills, surface
the pressure rather than punting.

### Why v5.11.x and not v5.12.x

Tight-close decision 2026-05-12: v5.x stays a "feature-complete
self-hosting sovereign language." No new language features
land in v5.x. Anything that would have been v5.12.x is either:

- absorbed into v5.11.x close (data-domain carve-out, parser-to-emit
  refactor, user-binary ELF cleanup, heap-map reorg), OR
- moved to v6.x (bare-metal formalization, RISC-V rv64, PIE,
  closures, generic instantiation, language-level async syntax,
  Class B FFI fold, cross-BB regalloc + dependent passes).

The boundary is clean: v5.x = "what the language IS." v6.x =
"new platforms + advanced features the language gains."

## v5.12.x — **retired** (scope moved to v6.x at 2026-05-12 tight-close)

The v5.12.x slot previously held the bare-metal formalization +
RISC-V rv64 arc. At the 2026-05-12 tight-close decision v5.12.x
was retired entirely — v5.11.x absorbs the remaining 5.x-shaped
work (closing the v5.x line at v5.11.69), and the platform
expansion (bare-metal formalization + RISC-V rv64) plus
parser-to-emit refactor's "4th backend" trigger condition all
move into the [v6.x section](#v6x--platform-expansion--advanced-features)
below.

The original v5.12.x scope detail — six bare-metal deliverables,
RISC-V acceptance gates, parser-to-emit refactor as triggered
prereq — is preserved verbatim under v6.2.x and v6.3.x with
"originally pinned v5.12.x" provenance lines on each sub-pin.

**Why retired and not just renamed**: keeping v5.12.x as the
home would have implied a v5.12.x exists. Under the tight-close
framing, **v5.x ends at v5.11.69 and v6.0.0 is the next minor.**
There is no v5.12.x.

---

## v5.12.x-original-spec — archived reference (DO NOT REVIVE)

Below is the original v5.12.x cycle spec as it stood prior to
the 2026-05-12 retirement. Preserved in-line for reference
while the v6.x sub-pins are still being written up; once v6.2.x
and v6.3.x scopes are fully migrated, this archived block
collapses into a single pointer to git history. Do not pin
new work to v5.12.x.

### Original v5.12.x — Bare-metal formalization + RISC-V rv64 arc

**Cycle theme**: codify two existing-but-informal capabilities into first-class toolchain targets — (1) **bare-metal compilation mode** that agnos already uses ad-hoc, (2) **RISC-V rv64 backend** as the fourth platform peer. Both have been pinned-and-slipped across five+ minors; v5.12.x is where they finally land together because their substrate prerequisites (v5.10.x typed-simd ABI + REAL TYPE SYSTEM + struct-byval ABI + v5.11.x stdlib annotation arc) are now complete.

**Important framing — bare-metal is formalization, not enablement**: the agnos kernel **already builds and boots** as a multiboot1 ELF i386 binary against the current toolchain (5.10.44 pin verified working 2026-05-11; kernel reaches userland exec + "Launching kybernet" in QEMU). What v5.12.0 delivers is the *language-side codification* of the ad-hoc bare-metal mode agnos has been using since first boot — clean acceptance criteria, documented conventions, a formal target triple, reusable by future bare-metal projects (firmware, alternative kernels, embedded). It does NOT gate AGNOS kernel work; per the [agnosticos MVP scope](https://github.com/MacCracken/agnosticos/blob/main/docs/development/roadmap.md#phase-13a--boot-to-shell-mvp--os-independence-beta-blocker), closed-beta ship is independent of this cycle landing.

### v5.12.0 — Bare-metal / AGNOS kernel target (formalization)

**Moved from v5.11.0 → v5.12.0 at v5.10.20 P(-1) sweep** per user direction. Has slid five minors now (v5.7.0 → v5.8.0 → v5.9.0 → v5.10.0 → v5.11.0 → **v5.12.0**) — but the slips reflect substrate-first sequencing (v5.7.x sandhi-fold, v5.8.x foldins, v5.9.x O5/O6 close, v5.10.x three-arc substrate, v5.11.x stdlib annotation), not the bare-metal work being hard. The kernel proves out the capability in production *during* the slips, so formalization arrives with empirical receipts.

**Scope (six deliverables):**

1. **Formal target triple** — `[target] = "bare-metal-x86_64-elf"` (and aarch64 peer) in `cyrius.cyml` `[build]` section. Recognized by `cyrius build` as a first-class target, not a `cflags`-hack invocation. Same for cross-compiles: `cyrius build --target bare-metal-x86_64-elf …`.

2. **ELF no-libc output format** — no `INTERP` segment (no `/lib64/ld-linux-x86-64.so.2`), no implicit `_start` from libc, no dynamic-link metadata. Static-only ELF with the user's `_start` (or multiboot entry) as the actual entry point. Reproducibility-test: rebuilding the agnos kernel with this target produces a byte-identical artifact to the current ad-hoc-mode build.

3. **Interrupt-handler emit conventions** — `naked_fn` attribute (or equivalent) for ISRs: no prologue, no epilogue, explicit control over which registers are pushed/popped. Calling convention compatible with x86_64 / aarch64 interrupt entry. Allows agnos's existing hand-rolled handlers in `kernel/arch/x86_64/` and `kernel/arch/aarch64/` to migrate from inline-asm-only to Cyrius-with-attribute where possible.

4. **Kernel-mode stdlib subset** — a documented contract for which `lib/*.cyr` modules are safe in bare-metal context (`string`, `alloc` with custom allocator, `vec` with custom allocator, basic `fmt` without floating-point if no FPU enabled, etc.) and which are explicitly forbidden (anything touching `lib/syscalls_*_linux.cyr`, `lib/fs.cyr`, `lib/process.cyr` — these assume a Linux host kernel underneath). `cyrius build --target bare-metal-*-elf` errors loudly if forbidden modules are pulled.

5. **Linker-script / section-placement control** — declarative section placement in `cyrius.cyml` (`[sections]`) for `.multiboot`, `.text`, `.data`, `.bss`, `.rodata` ordering. Today agnos accomplishes this via a manual linker script; v5.12.0 makes it expressible in the manifest. Sub-feature: BSS sizing declaration so kernels don't have to hand-compute the zero-init footprint.

6. **Inline assembly primitives for kernel work** — first-class language support (not stdlib functions, since stdlib isn't available pre-PMM-init) for: `cli` / `sti` / `hlt`; port I/O (`in` / `out` byte/word/dword); memory barriers (`mfence` / `lfence` / `sfence` / `dmb ish` on aarch64); `cpuid`. Same primitive set on aarch64 (`msr DAIFSet`, `wfi`, `dsb sy`, etc.). Today agnos uses ad-hoc inline-asm bursts; v5.12.0 makes them documented language primitives.

**Acceptance gates:**

1. `cyrius build --target bare-metal-x86_64-elf agnos/src/main.cyr build/agnos` produces a byte-identical binary to the current ad-hoc-mode build.
2. The forbidden-module check errors with a clear diagnostic when bare-metal code tries to pull `lib/fs.cyr` (or similar host-OS module).
3. `cyrius lint --target bare-metal-*` understands the kernel-mode stdlib subset and doesn't warn about legitimate omissions (no host-OS modules = expected, not a finding).
4. A minimal `examples/firmware-hello.cyr` (separate from agnos) builds, links, and runs in QEMU under bare-metal mode — demonstrates the target outside of agnos and proves it's reusable.
5. agnos kernel boots in QEMU rebuilt against v5.12.0 toolchain with no regressions in the boot log against the current 1.29.0 baseline.
6. Documentation: `docs/targets/bare-metal.md` in cyrius repo lays out the contract, the stdlib subset, the linker-script controls, and links to agnos as the canonical existing consumer.

**Cross-references (monolithic-by-design):**

- agnos kernel already works without this target — see [agnosticos roadmap Phase 13A](https://github.com/MacCracken/agnosticos/blob/main/docs/development/roadmap.md). v5.12.0 does NOT gate agnos's closed-beta MVP. Language and kernel ship on independent cadences; v5.12.0 is a *quality-of-life* improvement for future kernel work, not an enabler.
- Other future bare-metal Cyrius consumers expected to benefit: firmware projects, alternative microkernels, embedded controllers, the genesis-repo `scripts/boot.cyr` chain (which currently builds Linux-host-targeted but will eventually want bare-metal-target capability for self-bootstrapping ISO assembly).

### v5.12.x — RISC-V rv64 (3-5 sub-patches)

**Moved from v5.11.x → v5.12.x at v5.10.20 P(-1) sweep**.
First-class RISC-V 64-bit target. Inherits a frontend-
complete compiler against a clean toolchain UX with the
full v5.7.x → v5.10.x prerequisite chain shipped,
including the v5.7.30 + v5.7.31 aarch64 f64 pair that
gives RISC-V a working f64-on-non-x87 reference. Just-
another-platform work; lands when scheduling allows.

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

### v5.12.x — Triggered prereq pin

- **Parser-to-emit named-op refactor (path A)** — pinned to
  v5.12.x because RISC-V landing as the 4th backend triggers
  the prior long-term pin's condition #1 ("RISC-V lands and
  adds 4th backend, making path B's `_TARGET_CX == 0 &&
  _TARGET_RISCV == 0` chains unwieldy at every site"). Scope:
  ~10 abstract ops × 4 backends = 40 fn definitions +
  parse_*.cyr rewrites. Multi-session real engineering. Pin at
  v5.12.0 cycle entry; sequence before RISC-V backend
  implementation if prudent (RISC-V starts with the named-op
  interface from day one — cleanest path). Audit doc:
  [`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md).

Deliberately NOT bundling other items into v5.12.x —
bare-metal + RISC-V are plenty of work. Bare-metal
(v5.12.0) lands first; RISC-V picks up the rest of the
v5.12.x range.

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
| **v6.2.x** | RISC-V rv64 | ELF | **Moved v5.10.x → v5.11.x → v5.12.x → v6.2.x at 2026-05-12 tight-close**. The "4th backend forces parser-to-emit refactor" trigger condition is resolved by landing the refactor in v5.11.x close instead, so v6.2.x's RISC-V backend lands on the named-op interface from day one. |
| **v6.2.0** | Bare-metal | ELF (no-libc) | **Formalization, not enablement** — agnos kernel already boots without this target. Moved v5.7.0 → v5.8.0 → v5.9.0 → v5.10.0 → v5.11.0 → v5.12.0 → v6.2.0. Pairs with the v6.2.x RISC-V minor since both are platform/target work. |
| ~~**v5.9.0–5.9.5**~~ | ~~Pure-cyrius TLS 1.3~~ | — | **Removed from roadmap 2026-04-24** — pure-Cyrius TLS work outside Cyrius's compiler/stdlib scope per sandhi scope-absorption decision; `lib/tls.cyr` continues using `libssl.so.3` bridge from stdlib's perspective; canonical home for pure-Cyrius TLS implementation TBD. See v5.9.x slot bullet in *What's next* for details. |

---

## v5.x — Toolchain Quality

Shipped toolchain rows (api-surface + LSP cross-file go-to-def +
cyrlint forward-ref scanner + LSP `textDocument/references`
landed v5.9.10) moved to
[completed-phases.md](completed-phases.md). Remaining
toolchain-quality items are all consumer-trigger-gated and live
in [v5.10.x §Held forward](#v510x--held-forward-no-slot-consumed-surfaces-on-ask):

| Feature | Effort | Status |
|---------|--------|--------|
| LSP `textDocument/semanticTokens/full` | Medium | Held forward — earns slot when an editor's textmate grammar can't satisfy a token-coloring request. ~150 LOC per LSP 3.16 spec. |
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
| Phase 2b-aarch64 struct copy (LDRB/STRB loop) | Medium | **✅ Shipped v5.9.26**. See [completed-phases.md](completed-phases.md). |
| Closures capturing variables | High | gotcha #8 — consumers feel the absence | **Pinned v6.3.x** at 2026-05-12 tight-close. Held out of v5.x as a language-feature add; lands in v6.3.x alongside generic instantiation + async syntax. v5.8.x ADTs make captured-state encoding cleaner. |
| Real generic instantiation | High | 1 vote (kavach) | **Pinned v6.3.x** at 2026-05-12 tight-close. Today's erasure becomes monomorphization. Re-verify kavach pressure at slot entry (`feedback_premise_check_at_slot_entry`); speculative implementation pre-need is still risk. |
| Language-level async/await syntax | Medium | — | **Pinned v6.3.x** at 2026-05-12 tight-close. Today's callback-based `lib/async.cyr` epoll runtime (v5.11.15) gets a sugary surface — `async fn` / `await` CPS-transforms to the existing runtime. |
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

## v6.x — Platform expansion + advanced features

v6.0.0 is the major-version bump after v5.x closes at v5.11.69
(tight-close decision, 2026-05-12). Section title was previously
"Future 6.0" and scoped to refactoring + cleanup only; expanded
2026-05-12 to absorb the retired v5.12.x scope (bare-metal
formalization + RISC-V rv64) plus the language-feature pins that
the tight-close decision pushed out of v5.x.

**Theme**: v5.x froze "what the language IS." v6.x is **what the
language gains** — new platforms, position-independent codegen,
language features (closures, generic instantiation, async
syntax), Class B FFI fold, cross-BB regalloc + the deferred
optimization passes that gate on it.

**Cycle shape** (each `vN.x.y` is a real release; minor numbers
are pinned, patch counts are estimates):

| Minor | Theme | Status |
|-------|-------|--------|
| **v6.0.x** | Rename ceremony (`cc5` → `cyc`) + dead-code sweep + `_TARGET_*` consolidation + bridge-compiler retirement assessment | Detailed below |
| **v6.1.x** | PIE (position-independent executable) codegen + `.gnu.hash` migration | Detailed below |
| **v6.2.x** | Bare-metal formalization + RISC-V rv64 backend | Migrated from v5.12.x — see [v6.2.x](#v62x--bare-metal-formalization--risc-v-rv64-was-v512x) |
| **v6.3.x** | Language refinements: closures (lexical capture), real generic instantiation, language-level async/await syntax | New pin — see [v6.3.x](#v63x--language-refinements) |
| **v6.4.x** | Class B FFI fold (mabda 3.0.0 GA fold) + cross-BB regalloc + deferred passes (copy-propagation, extended dead-store elimination) | New pin — see [v6.4.x](#v64x--class-b-ffi-fold--perf-arc) |

**Why a major bump for v6.0**: scope is **refactoring and cleanup**
that's been accumulating debt across the v5.x line and that's
risky or disruptive to land mid-minor (rename, dead-code removal,
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
  genuinely dead, and delete the latter. Per
  `feedback_dead_code_audit_scope`: scaffold is **alive by default**
  unless actual work behind it is debunked.
- **`scripts/build-cyc.sh`** (pinned 2026-05-11 at v5.11.7 close).
  Wrap the byte-identical fixpoint check that's the canonical
  cyc/cc-rename verifier:
  ```sh
  cat src/main.cyr | build/cyc > /tmp/cyc_a && chmod +x /tmp/cyc_a
  cat src/main.cyr | /tmp/cyc_a > /tmp/cyc_b && chmod +x /tmp/cyc_b
  cmp /tmp/cyc_a /tmp/cyc_b && echo "FIXPOINT OK"
  cmp /tmp/cyc_a build/cyc && echo "byte-identical to build/cyc"
  ```
  Currently this runs as ad-hoc one-liners in chat (see v5.11.x
  retro transcript). At v6.0.0 the binary rename `cc5` → `cyc`
  warrants a permanent script so the verifier survives the cut-over.
  Mirror the `bootstrap/verify.sh` pattern.
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
- **Return-patch buffer dynamic conversion** (pinned 2026-05-08
  at v5.10.6 ship — proposal Option C). The cap raise to 256
  at v5.10.6 lifts the per-fn return ceiling well beyond any
  realistic consumer workload, but the underlying fixed array
  at `S + 0x18DA20` remains a magic-number'd parser-state
  field. v6.x.x converts it to a `vec_*`-shaped growable
  buffer (realloc on grow, freed at fn-end), removing the cap
  entirely. Lands here rather than mid-v5.10.x because the
  realloc-shaped path inside the parser is invasive enough to
  belong with the broader v6.0.0 cleanup arc; until then the
  256 cap is "do it once" headroom. Reference proposal:
  [`docs/development/proposals/2026-05-08-raise-return-cap.md`](proposals/2026-05-08-raise-return-cap.md)
  (Option C section).

### v6.0.0 — closeout

Same closeout checklist as every minor (CLAUDE.md §"Closeout
Pass") plus:
- Verify the `cc5` symlink works end-to-end on a clean install
  before tagging. Downstream CI failure on day-one of v6.0.0 is
  exactly the breakage-hit we're trying to avoid.
- Bulk vidya refresh — the rename touches every `cc?` mention,
  not just the version line. Use the closeout's vidya checklist
  as the audit list.

### v6.1.x — PIE (Position-Independent Executable) codegen

Slot — not pinned. Triggered when a consumer's address-space-
randomization need surfaces. AGNOS full-binary KASLR (Option A
in [`agnos/docs/development/proposals/2026-05-11-kaslr-scope.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/proposals/2026-05-11-kaslr-scope.md))
is the first such consumer; AGNOS v1.28.0 ships data-only KASLR
which doesn't need PIE, so the pressure here is "when AGNOS
wants full binary relocation," which is genuinely uncertain
timing (could be v1.29.x, could be v1.30.x+, could be never if
data-only is sufficient).

**Scope (Option A — kernel-mode PIE only, recommended first
cut):** add `--pie` build flag emitting RIP-relative codegen
(`lea rax, [rip + rel32]` instead of `mov rax, imm64` for
absolute-address loads; `adrp`+`add` on aarch64). Userland
binaries and stdlib distfiles continue to use the non-PIE path
unchanged. AGNOS is the only known consumer at slot time.

**Why v6.x and not v5.x:**
- Cross-cutting backend change. Every code-emit site producing
  an absolute address needs audit + conversion — same shape as
  the v6.0.0 `_TARGET_*` consolidation.
- ABI implication. PIE-vs-non-PIE linking compatibility is the
  kind of question that deserves a major-bump signal to
  downstreams.
- v5.x is mid-arc on stdlib annotation + foldin; perturbing the
  ABI mid-cycle compounds risk.

**Why v6.1.x and not v6.0.0:** v6.0.0 is the rename + cleanup
ceremony. Adding a substantive new codegen mode in the same cut
multiplies downstream risk. PIE lands as its own focused minor.

**Work surface estimate:** ~200-400 LOC across
`src/backend/x86/emit.cyr` + `fixup.cyr`, plus `parse_expr.cyr`
fns handling `&fn_name` / `&global_var` in PIE mode. Single
session for x86_64; aarch64 follows in a v6.1.1 sub-patch.

**Option B (universal PIE — stdlib + userland)** is a v6.2.x or
later follow-up if a real consumer materializes. AGNOS alone
doesn't justify it. Could stay open indefinitely.

Reference proposal:
[`docs/development/proposals/2026-05-11-pie-support.md`](proposals/2026-05-11-pie-support.md)
(8-step work breakdown, open questions, decision checkboxes).

**Pair with `.gnu.hash` migration**: long-term `.gnu.hash` pin
deferred at v5.6.38 (no consumer pressure) earns its slot here
— modern dynamic loaders prefer `.gnu.hash`'s Bloom filter
pre-check over the SysV `.hash` chain walk, and PIE binaries
that go through `dlopen`/symbol resolution will see the
measurable difference. Land as part of the v6.1.x dynamic-link
work; drop SysV `.hash` once `.gnu.hash` is in place.

### v6.2.x — Bare-metal formalization + RISC-V rv64 (was v5.12.x)

**Originally pinned to v5.12.x; moved to v6.2.x at the
2026-05-12 tight-close decision.** Detailed scope in the
[archived v5.12.x spec block](#original-v512x--bare-metal-formalization--risc-v-rv64-arc)
above; summary here.

**v6.2.0 — Bare-metal target formalization**

Codify the ad-hoc bare-metal mode that agnos has been using
since first boot into a first-class `--target bare-metal-x86_64-elf`
(and aarch64 peer) triple. Six deliverables: formal target triple,
ELF no-libc output format, interrupt-handler emit conventions
(`naked_fn` attribute), kernel-mode stdlib subset, linker-script /
section-placement control via `[sections]` in `cyrius.cyml`,
and inline assembly primitives for kernel work (`cli`/`sti`/`hlt`,
port I/O, memory barriers, `cpuid`).

Acceptance: rebuilding the agnos kernel with `--target bare-metal-x86_64-elf`
produces a byte-identical artifact to the current ad-hoc build;
forbidden-module check errors clearly when bare-metal code pulls
host-OS modules; `examples/firmware-hello.cyr` demonstrates the
target outside of agnos.

**Important framing**: bare-metal is **formalization, not
enablement**. The agnos kernel already builds and boots without
this target; v6.2.0 is a quality-of-life feature for future
bare-metal Cyrius consumers (firmware, alt-kernels, embedded).
It does NOT gate AGNOS closed-beta MVP. Per the [agnosticos roadmap](https://github.com/MacCracken/agnosticos/blob/main/docs/development/roadmap.md),
language and kernel ship on independent cadences.

**v6.2.x — RISC-V rv64 backend**

First-class RISC-V 64-bit target. The 4th platform peer after
x86_64 / aarch64 / PE-x86_64. Substrate prerequisites
(typed-simd ABI, REAL TYPE SYSTEM, struct-byval ABI, parser-to-emit
named-op refactor from v5.11.x) all land before this slot opens.

Scope: new backend (`src/backend/riscv64/`), new stdlib syscall
peer (`lib/syscalls_riscv64_linux.cyr`), new cross-entry
(`src/main_riscv64.cyr`), new test runner (QEMU + HiFive Unmatched
or equivalent), new CI matrix arm.

Acceptance gates:
1. Cross-compiler `build/cyc_riscv64` (note: post-`cyc` rename)
   emits valid rv64 ELF that `file(1)` identifies.
2. Single-syscall "exit 42" probe runs under `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on real rv64 hardware (hardware-gated
   like the aarch64 ssh-pi check).
5. `[release].cross_bins` gets a `cyc_riscv64` entry.

### v6.3.x — Language refinements

Three language features the user community has been requesting
through the v5.x cycle but that the tight-close decision (2026-05-12)
explicitly held out of v5.x. All three are real syntactic/semantic
additions that benefit from a major-bump signal.

**Closures with lexical capture**

Today: function pointers + lambda-pattern workarounds (see
`lib/fnptr.cyr`). Gotcha #8 noted in v5.x Language Refinements
table — consumers feel the absence. v5.8.x ADTs (sum types +
exhaustive match + Result + ?) make captured-state encoding
cleaner than it would have been pre-v5.8.

Scope: closure literals + lexical capture analysis +
closure-environment lowering (allocate-on-construct, deallocate
when the closure pointer goes out of scope; vtable-shaped
indirect call). Pairs with the existing trait/vtable
infrastructure (`lib/trait.cyr`).

**Real generic instantiation**

Today: generics parse (type params accepted at `SKIP_GENERICS`
in `src/frontend/parse_decl.cyr`) but erase at compile time —
no monomorphization, type-check semantics are weakest-applicable.
Test floor: `tests/tcyr/enum_generics.tcyr` (v5.8.21 syntax-
acceptance only).

Scope: type checker recognizes type parameters as concrete-at-
instantiation; emit-time substitution generates per-monomorph
code. Kavach was the original 1-vote consumer (per v5.x
Language Refinements table); reach out at v6.3.x slot entry
to verify consumer pressure is still real.

**Language-level async/await syntax**

Today: callback-based async on epoll runtime (`lib/async.cyr`,
v5.11.15). Works but is verbose at consumer sites.

Scope: `async fn` / `await` syntax compiles to CPS-transformed
state machines over the existing epoll runtime. Same runtime
semantics, sugarier surface. Pairs with closures (capture state
across await points).

### v6.4.x — Class B FFI + perf arc

**Class B FFI / wgpu fncall6 ABI work**

Held-forward through v5.9.x / v5.10.x / v5.11.x. The
*language-level* ABI work: fix Cyrius's `fncall6` vs SysV
AMD64 calling convention bug that mabda's wgpu integration
needs. Lands here regardless of where the mabda 3.0 GA fold
itself lands.

**mabda 3.0 fold provenance** (see [v5.11.x mabda CONDITIONAL slot](#v511x--mabda-30-ga-fold-conditional-watching-window)):

- **If mabda 3.0 GA shipped clean and folded in v5.11.x**:
  v6.4.x is just the Class B FFI ABI fix; no fold work here.
  Other mabda-consumer downstreams may need a re-pull when the
  ABI fix lands, but no stdlib-side fold action.
- **If mabda 3.0 GA gates on the ABI fix**: fold + ABI work
  land together in v6.4.x using the v5.7.0 sandhi pattern.
  Sister fold: agnosys (transitive via mabda).

**Cross-BB regalloc + deferred passes**

Linear-scan register allocator with cross-BB liveness data.
Unlocks three deferred passes that all share the same gate:

- **Copy propagation**: deferred 2026-04-23 after v5.6.18/.19
  recon. Stack-machine IR had no virtual registers for the
  classical wins; regalloc surfaces them.
- **Extended dead-store elimination** (cross-BB): deferred
  same date, same gate. Per-BB DSE shipped v5.6.18; cross-BB
  variant needs the liveness-out set per BB that regalloc
  builds.
- **Float peephole** (`float.cyr:41`, 5-instruction → 3-byte
  reduction): worth landing here if bench delta justifies.

Both deferred-pass recons (`ir_copyprop_recon`,
`ir_extdse_recon`) lived in `src/common/ir.cyr` during the
v5.6.19 evaluation and can be revived against the new liveness
data.

### v6.x — items lifted from long-term considerations

The following long-term-considerations entries (in this file
above) had their trigger conditions materialize via the v6.x
re-pinning:

- `.gnu.hash` for shared-object emission → **v6.1.x** (with PIE)
- Parser-to-emit named-op refactor (path A) → **v5.11.x** (close)
- Stdlib data-domain distlib carve-out → **v5.11.x** (close)
- Heap-map full reorganization → **v5.11.68** (true closeout); v5.11.69 reserved as fold-applied tag
- Copy propagation → **v6.4.x** (with regalloc)
- Extended dead-store elimination (cross-BB) → **v6.4.x** (with regalloc)

Their detailed scope + recon data stays in the long-term-
considerations block as the implementation reference; only the
"when to revisit" answer is now resolved.

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
