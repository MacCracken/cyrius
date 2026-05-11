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

## Long-term considerations (no version pin yet)

Items still without a slot pin after the v5.8.65 audit. Items
that earned a v5.9.x / v5.10.x / v5.11.x pin during the audit
have moved to those sections (the bare-metal + RISC-V cycle
re-pinned v5.10.x → v5.11.x at v5.9.7 ship per
"cleanup-before-platform-add" reframe); what remains here is
genuinely waiting on a trigger condition.

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

### Parser-to-emit named-op refactor (path A) — pinned to v5.11.x

**Pinned 2026-05-05 at v5.8.65 close; re-pinned v5.10.x →
v5.11.x at v5.9.7 ship** (the bare-metal/RISC-V cycle moved to
v5.11.x). RISC-V landing as the 4th backend in v5.11.x triggers
the path-A precondition #1 (`_TARGET_CX == 0 &&
_TARGET_RISCV == 0` chains become unwieldy). Full scope and
per-backend impact lives in the
[v5.11.x section](#v511x--bare-metal-arc-agnos-kernel--risc-v-rv64).
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

### Stdlib data-domain distlib carve-out — re-pinned to v5.10.x late or v5.11.x

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

## v5.11.x — Bare-metal arc (AGNOS kernel) + RISC-V rv64

**Pushed from v5.10.x at v5.9.7 ship** per user direction:
"kernel work is a parallel task and not hard baked... more the
RISCV work has slipped but its fine as another platform is
just another item to keep up to date." Both tracks are
parallel/long-running and don't need a hard trigger; they land
when their respective drivers (AGNOS kernel readiness,
RISC-V consumer ask) line up with cycle availability. Slip is
fine — the v5.10.x cleanup minor takes precedence on the
principle of "fewer surface items to manage future slots."

Two arch-port-style efforts grouped into one minor since both
land at the "no libc, direct hardware / different ABI" layer.

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
  | v5.11.4 | Collection libraries: hashmap (0/32), json (0/57) — ~89 fns | Mid-sized libs; hashmap underlies many sandhi/agnosys flows; json is the serialization workhorse. |
  | v5.11.5 | Big consumer libraries: mabda (0/405) | Largest single gap. GPU/rendering surface. Whole slot. |
  | v5.11.6 | Closeouts: vani (86/105), patra (88/92), agnosys (540/559), sandhi (315/344), pwd (6/12), grp (8/10), shadow (4/6), cyml (14/17), fdlopen (10/19), flags (10/12), net (13/15), u128 (34/35), ws_server (12/13) — ~83 fns | Partial-coverage consumer libs; top off to 100%. |
  | v5.11.7+ | src/common/ir (24/44), src/frontend/parse_types (0/24), parse_decl/parse_fn cleanup (11/11 each, no gap) | Compiler-side internals — annotations don't expose to consumers but tighten internal reasoning. |

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
| v5.11.1-v5.11.7+ | Stdlib annotation arc (see phase table in annotation bullet above) |
| v5.11.8 | `cyrius deps` symlink → file-copy |
| v5.11.9 | `tests/regression-*.sh` → cyrius port |
| v5.11.10 | Cyriusly cmdtools port (paired with .9 per user direction) |
| v5.11.11 | TS test harness program |
| v5.11.12 | daimon aarch64 `sys_epoll_wait` (P2) |
| v5.11.13 | bote `lib/net.cyr` `recv_timeout` + getaddrinfo (P2) |
| v5.11.14 | bote arena allocator `fl_free` (P2) |
| v5.11.15-17 | bote streaming dispatch + thread async primitives (P2; 3-slot) |
| v5.11.18 | bote WS handshake key validation (Low; ride-along after bote stack) |
| v5.11.19 | **Per-repo cyrius version isolation** (pinned 2026-05-11 v5.11.3 wipe; see below) |
| v5.11.20 | **kybernet `fn_table` + `identifier buffer` cap raise** (P2; pinned 2026-05-11 at v5.11.4 entry; see below) |
| v5.11.21-38 | OPEN — emergent bugs / consumer-filed / items surface during cycle (18-slot buffer; user 2026-05-11) |
| v5.11.39 | Defensive sweep (parser `assert_eq` string-literal quirk bundled) |
| v5.11.40 | Cycle closeout |

#### v5.11.19 — Per-repo `cyrius` version isolation

**Pinned 2026-05-11 during v5.11.3 ship after a snapshot-ping-pong
wipe destroyed in-flight Phase 3 edits.**

**Root cause**: `~/.cyrius/current`, `~/.cyrius/bin`, and
`~/.cyrius/lib` are single global pointers. When sibling agents on
the same dev box (agnosys, mabda, etc.) run `cyriusly use <version>`
to test against their pinned toolchain, they mutate the global
pointers. Any other repo concurrently doing `cyrius deps` resolution
reads the wrong snapshot — and the v5.10.37-discussed snapshot-ping-
pong loop copies those stale files BACK INTO the active repo's
`lib/`, silently wiping work in progress.

**User direction (2026-05-11)**:
- *"if version is installed it should just use the cyrius.cyml's
  noted version if not complain its not installed"*.
- *"agnosys agent cyriusly use 5.10.44 for tests; switch it
  fucking back bro"* — confirms agnosys's behavior is intentional,
  but cyrius's repo shouldn't be affected by it.
- *"or they slide the version to latest without asking or telling
  me"* — surfaces a second failure mode: agents auto-update.

**Acceptance shape**:
1. `cyrius` CLI (and `cc5` / `cyrfmt` / `cyrlint` / `ark` / etc.)
   resolves the toolchain version in this priority:
   - `cyrius.cyml`'s top-level `cyrius` field (if present in cwd
     or any parent up to repo root).
   - `~/.cyrius/current` (existing global default).
   - `latest` installed (fallback if neither pin is set).
2. If the resolved version is NOT installed at
   `~/.cyrius/versions/<v>/`: error out clearly. *"version X.Y.Z
   pinned in `cyrius.cyml` is not installed — run `cyrius install
   X.Y.Z`"*. Never silently slide to `latest`.
3. `cyrius deps` resolution reads from
   `~/.cyrius/versions/<resolved>/lib/` directly — NOT from
   `~/.cyrius/lib` (which is the global-default symlink) — so
   per-repo resolution isolates from concurrent agent activity.
4. `cyriusly use <v>` (and any other version-switch verbs) gain
   a `--global` flag to be explicit when they DO want to set the
   global default. Default `cyriusly use` becomes per-repo
   (writes `cyrius.cyml`'s field) rather than mutating the
   global state.
5. Cross-host smoke: all 4 hosts (local x86, pi, ecb, cass) still
   green via SSH.

**Pairs with v5.11.8** (`cyrius deps` symlink → file-copy fix):
once both ship, snapshot-ping-pong stops being a destructive
surprise AND per-repo isolation prevents the trigger in the first
place. The two fixes are complementary, not redundant.

**Reference**: in-tree memory pin
`project_cyriusly_version_switching.md` carries the symptom + the
recovery procedure used during v5.11.3.

#### v5.11.20 — kybernet `fn_table` + `identifier buffer` cap raise

**Pinned 2026-05-11 at v5.11.4 entry per user direction** (kybernet
filed
[`docs/development/issues/2026-05-11-kybernet-fn-table-identifier-buffer-caps.md`](issues/2026-05-11-kybernet-fn-table-identifier-buffer-caps.md);
pin lands AFTER the stdlib annotation arc completes).

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

**The fix (per the issue's "Concrete ask")**:
1. `fn_table` 4096 → **8192** (2×). Single source-line edit in cc5;
   raises the cap and the warn threshold proportionally.
2. `identifier buffer` 131072 → **262144 bytes** (2×). Edit in
   `lex.cyr` (the existing error message even names the location:
   *"raise LEXID cap in lex.cyr"*).
3. No algorithmic change. No on-disk format change. No
   consumer-visible API change.

**Acceptance bar**:
- cc5 self-host byte-identical (cap raise is parse-only).
- check.sh 66/66 green.
- cyrius test 146/146 green.
- kybernet 1.1.0 build (full agnosys-full surface) compiles without
  the warn-threshold notes.
- Cross-host smoke green on all 4 hosts (local x86, pi, ecb, cass).

**Why this slot and not earlier**: per user direction, "after stdlib
annotation arc". The arc runs v5.11.1-v5.11.7+; the post-arc queue
(.8-.19) is already pinned to infrastructure / consumer-blocking
P2 work. v5.11.20 is the first buffer-band slot — kybernet is P2
non-blocking (workaround in place at 1.1.1) but cliff-narrow for
the next 1-2 minors.

**P2 rationale** (from the issue): not P1 (kybernet 1.1.1 ships
clean under existing caps); not P3 (headroom is narrow enough that
1.2.0 edge-boot plausibly tips the warn threshold). Low-risk fix
makes the P2 rate the right speed.

Held-forward items (no slot pinned; surface-on-ask): Class B
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

**Cycle close pinned at v5.11.40** (user direction 2026-05-11) —
the .19-.38 band is an explicit 20-slot buffer for bugs, items,
and small optimizations that surface mid-cycle. **The cap is
tight on purpose.** v5.12.0 bare-metal/RISC-V has slipped five
minors already (v5.7.0 → v5.8.0 → v5.9.0 → v5.10.0 → v5.11.0 →
v5.12.0); keeping v5.11.x close pinned at .40 prevents another
punt. If the buffer fills mid-cycle, surface that pressure to
the project leader rather than silently expanding — the user
will explicitly open slots if it's worth doing, but the
default is to ride the cap and protect v5.12.0's kickoff.
Slot ordering inside the buffer band is decided per slot by
the project leader as items surface.

### v5.12.0 — Bare-metal / AGNOS kernel target

**Moved from v5.11.0 → v5.12.0 at v5.10.20 P(-1) sweep**
per user direction. Has slid five minors now (v5.7.0 →
v5.8.0 → v5.9.0 → v5.10.0 → v5.11.0 → **v5.12.0**); no
hard trigger required — earns slot when AGNOS kernel work
concretely needs the toolchain capability AND the v5.10.x
+ v5.11.x backlogs have drained enough to free a minor.
Rough scope:

- ELF no-libc output format
- interrupt-handler emit conventions
- kernel-mode syscall stubs stripped
- boot pipeline from `scripts/boot.cyr` landed in genesis
  Phase 13B (v5.6.29 gate)

Acceptance: AGNOS kernel can be built end-to-end with the
v5.12.0 toolchain; no host-libc symbols leak into the
kernel object.

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
| **v5.12.x** | RISC-V rv64 | ELF | **Moved v5.10.x → v5.11.x → v5.12.x at v5.10.20 P(-1) sweep** — v5.11.x repurposed as cleanup minor (TS test harness + v5.10.x leftovers); RISC-V keeps its pairing with bare-metal AGNOS scope. |
| **v5.12.0** | Bare-metal | ELF (no-libc) | Queued — AGNOS kernel target. Slid v5.7.0 → v5.8.0 → v5.9.0 → v5.10.0 → v5.11.0 → v5.12.0. |
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
