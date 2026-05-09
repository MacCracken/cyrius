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

## v5.10.x — Open bug / optimization arc

**Theme** (re-framed at v5.9.7 ship per user direction): a
dedicated bug-backlog + perf-optimization minor. v5.9.x's
"clean what's there before adding new surface" principle
extends one minor — v5.10.x reduces existing surface area
through bug-fix work and performance optimization rather than
adding new platforms or feature surface (which costs more in
every future slot).

Original v5.10.x content (bare-metal/AGNOS kernel + RISC-V rv64)
pushed to v5.11.x. Both are parallel work tracks (kernel is
downstream-driven by AGNOS; RISC-V just-another-platform); slip
is fine. RISC-V has no consumer pressure; kernel has slipped
four minors (v5.7 → .8 → .9 → .10 → .11) with AGNOS unblocked-
but-unrushed.

### v5.10.x — Shipped

- **v5.10.0** ✅ — **per-phase compile-time profiling
  instrumentation shipped 2026-05-08**. Opens the v5.10.x
  optimization arc with the measurement tool; future slots
  build on the per-phase data this captures. 7 phase-end
  timestamp captures gated on `CYRIUS_PROF=1` (pp / lex /
  gvar / parse / fixup / emit / write). Profile baseline:
  ```
  prof: compile 984 ms (pp=84 lex=580 gvar=104 parse=2
                        fixup=210 emit=2 write=0 ms)
  ```
  Lex is the dominant target (59% of compile time). cc5
  cd48bdb6 (+1280 B for the 7 captures + multi-field epilogue);
  byte-identical self-host. Two whitespace fast-path attempts
  measured during this slot — both no-op on total time;
  reverted. Real lex optimization needs deeper analysis (see
  v5.10.1 pin).

### v5.10.x — Pinned next (priority: bottom-to-top, agnosys first)

**Priority pivot at v5.10.1 entry (2026-05-08, user direction)**:
v5.10.x is now ordered bottom-to-top.

1. **agnosys (kernel/baseOS)** — bottom-of-stack — every
   downstream baseOS item depends on it. Type-system arc
   closes the agnosys 1.1.12 cascade across v5.10.1-.5
   (extended one slot at v5.10.2 ship — overload dispatch
   split out of v5.10.2 to its own v5.10.3 slot per the
   honest-scope rule). v5.10.5's "CLOSE" claim was
   PARTIAL — Str-typed fields + real-Pi aarch64 still
   failed; v5.10.7 lands the real close (consumer's
   verdict matches now).
2. **vyakarana 2.1.0 cap unblock** — slot-on-need surfaced
   2026-05-08 (return-cap proposal); slotted before runtime
   services because it's a narrow, mechanical fix that
   unblocks the vyakarana grammar-batch flow without
   blocking sandhi. v5.10.6.
3. **stdlib runtime services (TLS / net)** — third priority
   per the bottom-to-top stack — sandhi 1.3.x's TLS arc
   needs `lib/net.cyr` `net_connect_nb` primitive +
   `lib/tls.cyr` native-transport prep audit. v5.10.10-.11
   (pushed back several times: agnosys close at v5.10.7,
   JSON-escaping at v5.10.8, version-pinned-lib at v5.10.9
   each took the slot ahead of net/tls).
4. **specialized libraries (hisab math)** — fourth priority —
   typed SIMD math expansion now that overload dispatch
   from v5.10.3 enables typed `f64v4` primitives. v5.10.12.
5. **compile-time speedups + surface review** — last, since
   they don't unblock any baseOS or runtime-service item.
   v5.10.13+.

Reference: memory pin
`feedback_priority_bottom_to_top.md` — *"fixing hisab now doesn't
help getting a new boot kernel setup... which will always be
prioritize right.... bottom to top."* sandhi cross-ref:
sandhi 1.3.x TLS arc roadmap explicitly pins items #2's two
slots (net_connect_nb factoring + tls.cyr audit) as
"cyrius-side ask" / "Not sandhi's slot" per ADR 0001 (sandhi
composes, doesn't reimplement).

#### v5.10.1-.5 — REAL TYPE SYSTEM ARC (agnosys-driven)

Closes the agnosys 1.1.12 cascade. The verbatim repro
(`/tmp/cyrius-derive-serialize-incomplete/minimal_repro.cyr`,
hash `6425355b6147d5a674078794310ae2c1`) ended at:
```cyr
var out = str_builder_build(sb);    # out: Str (16-byte struct)
println(out);                        # treats Str as cstring → garbage
println(strlen(out));                # treats int as cstring → SIGSEGV
```
Both lines are API misuse the type system would catch /
dispatch correctly. v5.9.x had three options to fix
(polymorphic-runtime-detection / break str_builder_build /
partial Option-3); user rejected all three as either sloppy or
breaking. The right fix is real types.

Cyrius today tracks type *annotations* (struct fields, var
slots, fn params via `: Type` or `: Str`) and uses them for
width-correct loadN/storeN + pointer-mode dot access — but the
parser does NOT enforce types at fn call sites and there's no
overload dispatch.

- **v5.10.1 — Type system pass 1: call-site check on
  EXISTING `: Str` local-typed args (synthetic fixture)**.
  Adds the call-site type-check machinery using the
  v5.8.17 §9 `: Str` annotation infrastructure that already
  exists for both parameters AND `var x: Str = ...`-style
  locals. No stdlib calling-convention changes; no new
  type-tag mechanism — leverage what's already there.

  **Scope** (Path 1 per the scope-check at slot entry):
  - **Call-site check at PARSE_FNCALL** (`src/frontend/
    parse_fn.cyr` line ~525): when arg is an IDENT and
    resolves to a local-var via FINDLOCAL with SLTYPE
    indicating Str (`-STR_SID`) — OR a global-var via
    FINDVAR with GVTYPE indicating Str — AND the param's
    `str_mask` bit (1 << argc) is NOT set (cstring
    expected), emit a WARNING (not hard error — keeps
    cycle moving while v5.10.2 overload dispatch lands).
  - **No stdlib annotation pass this slot** — that's
    bundled with v5.10.2 overload dispatch (where
    annotating `str_builder_build` etc. with `: Str`
    return type pairs naturally with adding `println_str`
    overloads).
  - **No calling-convention changes** — Str-returning
    fns continue using their current scalar-pointer
    return; the parser doesn't need to special-case
    ≤16-byte struct returns until v5.10.2 actually adds
    return annotations.

  **Acceptance**:
  - Synthetic fixture `tests/tcyr/type_check_str_to_cstr.tcyr`:
    `var s: Str = str_from("hello"); takes_cstring(s);`
    where `takes_cstring` is a fn whose first param is
    NOT `: Str`-annotated — cc5 emits warning at the
    `takes_cstring(s)` line.
  - cc5 byte-identical self-host.
  - cyrius test + check.sh green (no false-positive
    warnings on the existing source corpus — verified
    by the 132/132 .tcyr suite + 66/66 check.sh).

  **NOT in this slot** (deferred to v5.10.2 / .3 / .4 with
  explicit pinnage below):
  - Stdlib `: Str` return annotations (v5.10.2 — bundled
    with overload dispatch since the two are paired work).
  - Calling-convention special-case for ≤16-byte struct
    returns (v5.10.2 — surfaces when the stdlib audit
    annotates Str-returning fns).
  - Overload dispatch (v5.10.2).
  - Inference through `var x = f(...)` (v5.10.3).
  - Diagnostic hints + agnosys verbatim repro CLOSE (v5.10.4).

- **v5.10.2 — Type system pass 2: stdlib `: Str` return
  annotations + ≤16-byte calling-convention special-case**.
  **Overload dispatch deferred to v5.10.3** (split per the
  v5.10.2-entry scope-check — stdlib annotation pass +
  calling-convention work was already a Big-Heavy-One-Thing
  slot; bundling overload dispatch on top veered into
  sleight-of-hand territory). Per
  `feedback_deferral_requires_roadmap_pinnage`, the deferral
  is explicit: overload dispatch lands at v5.10.3 with the
  acceptance bar `var s: Str = str_from("x"); println(s);`
  routing to `println_str` instead of warning.

  **Scope** (what ships this slot):
  - **Calling-convention special-case** for `: Str` (and
    other ≤16-byte struct returns): rough-scan in
    `parse_fn.cyr` peeks the return-type's struct id +
    STRUCTSZ; if ≤16, skip `_cur_fn_ret_stash = 8` so the
    return flows through scalar rax/rdx (existing stdlib
    convention preserved). Also gate `PARSE_RETURN`'s
    struct-byval-copy path on `_cur_fn_ret_stash > 0` so
    Str returns fall through to scalar return.
  - **asv-path caller-side gate**: at `parse_decl.cyr`, the
    asv (assignment-from-struct-value) gate now requires
    `STRUCTSZ > 16` — Str-returning fns flow through
    v5.8.17 §9 pointer-mode local path instead of triggering
    multi-slot retptr machinery on the receiver.
  - **Stdlib annotation pass on `lib/str.cyr`**: 12 fns
    annotated with `: Str` return type — `str_from_a` /
    `str_from` / `str_new_a` / `str_new` / `str_cat_a` /
    `str_cat` / `str_sub_a` / `str_sub` / `str_clone_a` /
    `str_clone` / `str_from_int_a` / `str_from_int` /
    `str_trim_a` / `str_trim` / `str_from_buf` /
    `str_substr`. Each callsite verified byte-identical
    self-host.
  - **Latent bug surfaced + fixed in slot**: param-binding
    in `parse_fn.cyr` already cleared SLTYPE explicitly
    (v5.10.1 fix); v5.10.2 doesn't change that — the fix
    was a v5.10.1 surfaced-during-implementation surprise.

  **Acceptance**:
  - cc5 byte-identical self-host after annotation pass
    (verified — annotations don't change the COMPILER's
    output bytes; cc5 doesn't link against lib/str.cyr).
  - cyrius test 132/132; check.sh 66/66.
  - Cross-arch: cc5_aarch64 cross-rebuilt with v5.10.2 cc5;
    Mach-O ARM gate on ecb still green.

  **NOT in this slot** (deferred with explicit pinnage
  below):
  - Overload dispatch (v5.10.3).
  - Inference through `var x = f(...)` (v5.10.4).
  - Diagnostic hints + agnosys CLOSE (v5.10.5).

- **v5.10.3 — Type system pass 3: overload dispatch**.
  Deferred from v5.10.2's scope-shrink. Extend `FINDFN` to
  support multiple impls keyed by arg-type signature.
  PP-mangled names at the symbol level (`println_cstr` /
  `println_str` / `println_int`); parser routes calls
  based on arg type. Acceptance: synthetic fixture
  `var s: Str = str_from("x"); println(s);` routes to
  `println_str` (no warning, no garbage). Note: `println(out)`
  from a non-annotated `var out = str_builder_build(sb)`
  still doesn't fire correctly until v5.10.4 inference.

- **v5.10.4** ✅ — **Type system pass 4: type inference at
  `var x = f(...)` + stdlib param-side `: Str` annotation pass
  (bundled)**. SHIPPED. Inference at PARSE_VAR pre-PCMPE peek
  picks up the called fn's return-struct-id from `GFRS` and
  folds it into the SLTYPE-set branch as `0 - sid`. Combined
  with v5.10.3 dispatch, unannotated `var out =
  str_builder_build(sb); println(out);` now routes to
  `println_str` correctly. cc5: 757920 → 758888 (+968 B).
  Byte-identical self-host on x86_64 Linux + Mach-O ARM64
  (round2==round3, 557492 B). Cross-tested aarch64 Linux on
  pi: 4/4 inference assertions pass + prints `inferred Str`
  via dispatch. Bundled 13 stdlib param annotations
  (`str_len`, `str_data`, `str_print`, `str_println`,
  `str_index_of`, `str_to_int`, `str_clone_a/_clone`,
  `str_sub_a/_sub`, `str_substr`, `str_trim_a/_trim`).
  Inference for binary operators / field-reads / pointer
  deref deferred (not blocking; promote on consumer ask).

  **Original scope** (kept here for closeout audit): Propagate
  fn return types through `var x = f(...);` so `x`'s slot
  tracks the type. Also for binary operators (`x + 1` keeps
  x's type if int; struct-field reads keep field's type;
  pointer deref tracks pointee).

  **Bundled work** (per the v5.10.3 deferral): annotate
  ~12 stdlib fns in `lib/str.cyr` with `: Str` parameter
  annotations — `str_len(s)`, `str_data(s)`, `str_print(s)`,
  `str_index_of(s, ch)`, `str_to_int(s)`, `str_clone_a(a, s)`,
  `str_clone(s)`, `str_sub_a(a, s, ...)`, `str_sub(s, ...)`,
  `str_substr(s, ...)`, `str_trim_a(a, s)`, `str_trim(s)`.
  Bundled because the inference work is the natural trigger
  to also clean up param annotations, and the param
  annotations are what unblock v5.10.5's
  `CYRIUS_TYPE_CHECK` default-on flip.

  **Acceptance**:
  - Existing patterns continue working byte-identical
    (no regression on the cc5 self-host or 66-gate audit
    corpus).
  - Type-inferred `var` slots resolve correctly through
    multi-step expression chains.
  - Synthetic fixture: `var out = str_builder_build(sb);
    println(out);` (no explicit `: Str` annotation)
    routes to `println_str` via type inference + the
    v5.10.3 overload dispatch.
  - Stdlib param annotations don't fire false positives
    on legitimate `str_len(s)`-style call sites in the
    132-tcyr corpus.

- **v5.10.5** — **Type system pass 5: extended overload
  dispatch + diagnostic hint catalog**. SHIPPED — but the
  agnosys 1.1.12 close claim was **PARTIAL** (corrected at
  v5.10.7). The verbatim repro file passed end-to-end on
  x86_64 numeric path, but the consumer's actual use case
  (Str fields + aarch64) still failed. See v5.10.7 for the
  real close. Hash
  `6425355b6147d5a674078794310ae2c1` runs end-to-end
  with output `[{"x":1,"y":42,"z":7}]\n22\n`, exit=0.

  Landed: scalar return-type annotations (`: i8/i16/i32/i64`)
  encoded as negative `fn_ret_sid` values; v5.10.2 rough-scan
  extended to recognize scalar names so retptr-stash isn't
  allocated for them; extended overload dispatch handles
  `IDENT (` fn-call args (looks up GFRS for the called
  fn's return type); 3 new dispatch routes (`println(Str-
  fncall)→println_str`, `strlen(Str)→str_len`,
  `println(i64)→println_int`); `println_int` helper in
  `lib/string.cyr`; `strlen` annotated `: i64`;
  `str_builder_build_a/build` and `str_join` annotated
  `: Str` (v5.10.2 misses); diagnostic hint catalog (Str
  → cstring with one-line hint pointing at str_data /
  str_println / annotate `: Str`).

  cc5: 758888 → 764552 (+5664 B). Byte-identical self-host
  on x86_64 Linux + Mach-O ARM64 (round2==round3). Pi
  (aarch64 Linux) cross-test: same verbatim output. 66/66
  check.sh, 133/133 cyrius test, heapmap clean.

  **NOT in this slot** (deferred with explicit pinnage):
  - `CYRIUS_TYPE_CHECK` default-on flip — moved to a future
    slot pinned in the v5.10.x held-arc section. The
    flip was tried, surfaced a NEW false-positive shape
    (Str → generic i64-shaped fns like vec_push_a / alloc
    where Str-as-i64-pointer is fine semantically), needs
    per-param scalar-vs-pointer annotation infrastructure
    that doesn't exist yet.
  - Scalar return-type INFERENCE for `var n = strlen(s);`
    (local n carrying SLTYPE-encoded i64) — also tried,
    reverted because positive-width SLTYPE = 8 tripped
    parse_expr.cyr's width-aware load path (arithmetic
    narrowed wrong). Direct fn-call dispatch
    `println(strlen(s))` still works (uses GFRS at call
    site). Pinned with the default-on flip.

  **Slot-side fixes**:
  - `cyriusly install <version>` honored its argument
    (was always installing "latest" because the env-var
    pipe was misordered).
  - `cyrius audit` snapshot ping-pong recovery
    (`~/.cyrius/lib` had reverted to v5.10.0; re-pointed
    to v5.10.4 + parked `versions/5.10.0/lib` as
    `lib.parked-pingpong-source` to fail loudly on
    future regressions).

#### v5.10.6 ✅ — Per-fn return-statement cap raise 64 → 256 + cyrfmt char-literal brace fix (SHIPPED)

Both deliverables landed. cc5: 764,552 B (heap-layout
reshuffle, no codegen change — same binary size as
v5.10.5). 7 cap-check sites bumped 64 → 256;
`ret_patch_cnt` relocated 0x18DC20 → 0x18E220;
`GRPC`/`SRPC` accessors + heap-map comments updated
across 5 main_*.cyr files. cyrfmt's brace counter
now skips `'...'` char literals (mirrors the v5.7.22
skip for `#` comments + `"..."` strings). New regression
`tests/tcyr/return_cap.tcyr` (100-return synthetic);
6 cyrfmt negative cases verified (`'{'`, escaped quotes,
mixed strings, nested braces). Byte-identical x86_64 +
Mach-O ARM64 self-host; pi cross-test passes. 66/66
check.sh, 134/134 cyrius test, heapmap clean.

#### v5.10.6 — original scope (kept here for closeout audit)

**Driver**: vyakarana 2.1.0 surfaced the cap during the
PowerShell extension batch (`.ps1` / `.psm1` / `.psd1`) —
`detect_language(path)` hit 83 returns past the 64-entry
fixed array at `S + 0x18DA20`. vyakarana 2.1.0 shipped a
length-bucket helper-split workaround; this slot lifts the
cap so the dispatcher pattern works at scale. Filed proposal:
[`docs/development/proposals/2026-05-08-raise-return-cap.md`](proposals/2026-05-08-raise-return-cap.md).

**Why 256 not 128**: do-it-once. 128 covers vyakarana's
foreseeable 2.1.x-2.3.x growth; 256 buys headroom for any
extension dispatcher (file-format detectors, MIME tables,
syscall translators) we'd surface in the next 24 months. The
cost delta is +1024 B per parser-state instance over 128 —
negligible. Picking 256 vs 128 saves a future bump cycle for
the same file edits + cross-arch verification.

**Why fixed (not dynamic) at v5.10.6**: a growable buffer
(Option C in the proposal) is the right long-term fix but
needs a `realloc`-shaped path inside the parser — invasive
enough to land at v6.x.x with the broader cleanup arc.
Pinned: see "v6.x.x — return-patch buffer dynamic
conversion" entry below.

**Scope**:
- **Heap-map relocation**: `ret_patches` array grows from
  512 B (64 entries) to 2048 B (256 entries) at 0x18DA20,
  ending at 0x18E220. `ret_patch_cnt` (8 B) relocates from
  0x18DC20 → 0x18E220. Headroom before `loop_top`
  (0x18F838) is ~5.5 KB after the move; no other field
  collides.
- **Cap-check sites**: 8 enforcement points across
  `src/frontend/parse.cyr`, `parse_fn.cyr`,
  `parse_expr.cyr` change `>= 64` → `>= 256`.
- **Cross-arch heap-map comments**: every `main_*.cyr`
  maintains its own copy of the layout map — update
  `main.cyr`, `main_aarch64.cyr`, `main_aarch64_macho.cyr`,
  `main_aarch64_native.cyr`, `main_win.cyr`, `main_cx.cyr`
  in lockstep. Cross-arch propagation per the
  `feedback_cross_arch_propagation_mandatory` pin — this
  is exactly the shape of the v5.8.52 token-fixup x86-only
  miss; verify all six entry points before commit.
- **Brk extension**: probably none required — parser state
  sits well within first-MB; existing brks already cover
  far past 0x18F838. Verify per main_*.cyr regardless.

**Bundled side-deliverable — cyrfmt char-literal brace
bug**: cyrfmt's brace-depth counter doesn't skip char
literals, so a `}` inside `'}'` decrements it and
subsequent statements lose their indent. Smallest repro:

```cyr
fn foo(sb) {
    str_builder_putc(sb, '}');
    var x = 1;             // ← cyrfmt drops the indent here
}
```

`build/cyrfmt /tmp/repro.cyr` outputs the second line at
column 0 instead of column 4. Same bug almost certainly
applies to `'{'` (would over-indent), and likely to `}`/
`{` inside `"..."` string literals depending on whether
the lexer-shape used for indent tracking handles strings.

**Fix shape**: cyrfmt's indent walker needs the same
char-literal / string-literal skip the lexer uses. The
walk is in `programs/cyrfmt.cyr` (or wherever the indent
state machine lives). Likely a single conditional that
says "if cursor is inside `'...'` or `"..."` quotes, skip
brace counting for these bytes." Mirror handling: `\\` /
`\'` / `\"` escape sequences should not break the literal.

**Acceptance for the bundled fix**:
- Repro above formats with the second statement still
  indented to column 4.
- `'{'` indent doesn't get over-counted (synthetic test:
  `str_builder_putc(sb, '{');` followed by another
  statement should still indent correctly).
- `"...{...}..."` and `"...\"...\"..."` strings don't
  trip the counter either.
- Existing `cyrfmt --check` corpus stays green
  (currently passing all stdlib + programs/).
- Bundled into v5.10.6 because both are mechanical,
  consumer-prerequisite tooling fixes (vyakarana surfaced
  the cap; cyrfmt char-literal bug is a quality-of-life
  fix that surfaces on any code generating bracketed
  output via `str_builder_putc`).

**Acceptance**:
- New regression `tests/tcyr/return_cap.tcyr` with a
  100-return synthetic that compiles cleanly post-bump and
  errored at 64 pre-bump (run against the post-bump cc5;
  pre-bump expectation is asserted via the error message
  being absent).
- Diagnostic message for >256 cap stays useful: `error:
  too many return statements in function (max 256)` — same
  shape as the 64 message, new number.
- cc5 byte-identical self-host (heap-layout reshuffle but
  no codegen change).
- Cross-arch: cc5_aarch64 byte-identical; cc5_macho
  byte-identical (round2 == round3 on ecb); cc5_win_cross
  builds.
- 66/66 check.sh; 134/134 cyrius test (133 + the new
  return_cap regression); heapmap clean.
- vyakarana stays on its 2.1.0 helper-split (collapsing
  back is a stylistic choice for vyakarana; not in this
  slot's scope).

**NOT in this slot** (deferred with explicit pinnage):
- **Dynamic growable buffer** (Option C) — pinned at
  v6.x.x as the structural fix. Removes the cap entirely
  via realloc-shape, lands during the v6.0.0 broader
  cleanup arc.
- **Diagnostic improvement** (Option D) — folded into the
  cap raise itself (same message shape, just `256`
  instead of `64`); standalone hint-with-vyakarana-example
  variant deferred (low value once the cap is high enough
  that nobody trips it).

#### v5.10.7 ✅ — agnosys 1.1.12 REAL CLOSE (Str-typed struct fields + real-Pi aarch64) (SHIPPED)

Honest correction of the v5.10.5 "CLOSE" claim. The
agnosys agent's update to the issue file at v5.10.6
verdict was **PARTIAL FIX**:
- `: Str` typed struct fields fail to compile entirely
  (`error:<source>:N: unexpected '}'` in synthetic
  `_to_json` body).
- aarch64 SIGILL on real Pi for any Serialize-derived
  struct (Ubuntu 6.8.0-raspi kernel).

**Root cause** (Str fields): PP_DERIVE Serialize codegen
treats `: Str` as a single 8-byte pointer slot
(`load64(ptr+N)` semantics), but `FIELDSZ` returned 16
bytes (`STRUCTSZ(Str)` — the full data+len embed). The
`PARSE_STRUCT_INIT` positional flatten consumed TWO
expressions per Str field (data + len), so user code
like `var s = named_status { my_str, x };` errored
because the parser was still expecting an expression for
the next field after consuming both `my_str` and `x` as
data/len.

**Fix**: added `IS_STR_FIELD(S, ft)` helper in
`parse_types.cyr` that matches the field type's first 4
bytes against `"Str\0"`. `FIELDSZ` returns 8 (pointer
slot) for Str fields. `PARSE_STRUCT_INIT` positional
flatten takes ONE expression slot for Str fields.

**aarch64 SIGILL**: also fixed (or was already fixed in
v5.10.5/v5.10.6 work — re-verified clean on real Pi).
Both i64-numeric verbatim AND Str-field repros run
cleanly with correct JSON output on Ubuntu 6.8.0-raspi
aarch64.

cc5: 764552 → 765208 (+656 B). Byte-identical x86_64
self-host. Pi cross-test: both i64-numeric + Str-field
repros pass on real hardware. 66/66 check.sh, 134/134
cyrius test.

**NOT in this slot** (held forward):
- Untyped-Str-field auto-detection (per agent's open
  item 4) — codegen has no way to know an unannotated
  field's runtime shape; consumers should annotate
  `: Str` (which now works).

#### v5.10.8 ✅ — `#derive(Serialize)` JSON escaping fix (agnosys 1.1.12 follow-up) (SHIPPED)

Agent's v5.10.7 verdict surfaced a new bug: the
now-working Str-field codegen emits raw bytes without
escaping `"`, `\`, or control chars — invalid JSON for
any string carrying user input or kernel-audit text.

Landed: `str_builder_add_json_str(sb, s: Str)` helper in
`lib/str.cyr` (RFC 8259 §7 compliant — `"`→`\"`,
`\`→`\\`, named escapes for `\b\f\n\r\t`, `\u00XX` for
other control chars). PP_DERIVE Str-field branch now
emits a single helper call instead of 3-call raw cstr
sequence. cc5: 765,208 → 764,936 (-272 B).

Real Pi cross-test: all 3 shapes (numeric verbatim,
Str-field plain, Str-with-escapes) pass with valid JSON.

Held forward: untyped-Str-field auto-detection (agent's
#5, lower priority — annotate `: Str` is the workaround);
aarch64 cwd-dependent silent miscompile (compiler should
error on missing includes instead of emitting broken
aarch64).

#### v5.10.9 ✅ — Version-pinned lib path (kills cc5/lib version-mismatch contamination class) (SHIPPED)

The agnosys agent's "aarch64 still SIGILL" verdict
across v5.10.6/.7/.8 wasn't a codegen bug — it was lib
resolution loading a stale snapshot. Each cc5 binary's
PP_DERIVE codegen emits calls to helpers that exist in
ITS OWN VERSION's lib; running it against a
`~/.cyrius/lib` symlink pointing at an older version
produces undefined-fn warnings + SIGILL.

Fix: `_init_cyrius_lib` now builds the path
`$HOME/.cyrius/versions/<MY_VERSION>/lib/` where
`<MY_VERSION>` comes from `_VERSION_STR_CC5` extracted
at runtime. Each cc5 binary self-isolates to its own
matching lib snapshot. The `~/.cyrius/lib` symlink
stays for backwards-compat but cc5 no longer consults
it.

cc5: 764,936 → 765,608 (+672 B). Byte-identical
self-host. Pi (real aarch64) verified with broken
`~/.cyrius/lib` symlink — version-pinned path
resolves cleanly.

`src/version_str.cyr` now included across all 6 main_*
variants (was only main.cyr + main_win.cyr); cross-arch
propagation per the feedback pin.

#### v5.10.10 ✅ — cyrlint char-literal brace fix + agnosys aarch64 closeout (shadow-lib diagnosis) (SHIPPED)

cyrlint had the same brace-counter bug as v5.10.6's
cyrfmt fix. Both lint sites updated. agnostik 5.10.9
toolchain refresh closed (694 false positives gone).

agnosys aarch64 SIGILL diagnosed as shadow-lib
contamination (cwd `lib/` shadowing version-pinned
`$HOME/.cyrius/versions/<v>/lib/`). Sha256-verified all
artifacts identical between cyrius-team and agent
setup; only divergent variable was cwd-relative shadow
lib. Consumer-side fix: delete stale lib/.

cc5 unchanged in semantic. Held forward (see "Held /
pinned bug arc" below): shadow-lib guard +
defensive `lib/fnptr.cyr` ifndef rewrite.

#### v5.10.11 ✅ — `lib/net.cyr` `net_connect_nb` primitive (sandhi 1.3.x prereq) (SHIPPED)

`net_connect_nb(fd, addr, port, timeout_ms)` factored
into stdlib. Returns 0 / `_NET_CONN_NB_TIMEOUT` (-2) /
`_NET_CONN_NB_ERR` (-1). Restores blocking mode on
every exit path. `regression_network_probe` refactored
to compose on it; sandhi files its own switchover patch
on its cycle per ADR 0001. api-surface +1
(2795 → 2796). cc5 unchanged in semantic. 66/66
check.sh, 134/134 cyrius test, doc-coverage clean.

#### v5.10.11 — original scope (kept here for closeout audit)

**Driver**: sandhi 1.3.x roadmap explicitly asks for this as
a stdlib factoring — the non-blocking-connect + poll(POLLOUT)
+ SO_ERROR-readback shape currently duplicated in two places:
- sandhi's `_sandhi_conn_connect_nb` in `src/http/conn.cyr`
- cyrius's `regression_network_probe` in `lib/regression.cyr`
  (shipped v5.9.42)

Both implementations share the exact same syscall sequence
(socket / fcntl O_NONBLOCK / connect / poll / getsockopt
SO_ERROR). Factoring up into stdlib gives sandhi the primitive
its 1.3.x TLS arc needs to compose on, and lets cyrius's own
`regression_network_probe` switch from raw syscalls to the
stdlib primitive.

**Scope**:
- New `fn net_connect_nb(fd, addr, port, timeout_ms)` in
  `lib/net.cyr`. Returns 0 on connected, `_NET_CONN_NB_TIMEOUT`
  (-2) on poll timeout, `_NET_CONN_NB_ERR` (-1) on
  fcntl/connect/SO_ERROR failure. Restores blocking mode on
  every exit path so subsequent recv/send behave normally.
- Update `lib/regression.cyr`'s `regression_network_probe`
  to compose-use the new primitive (delete duplicate
  syscall machinery).
- Sandhi files its own 1.3.x patch to switch
  `_sandhi_conn_connect_nb` to the new primitive — that's
  sandhi's slot, not cyrius's. cyrius ships the primitive;
  sandhi adopts on its cycle.

**Acceptance**:
- New primitive in `lib/net.cyr`; api-surface +1.
- `regression_network_probe` regression: cyrius's TLS-live
  gate still PASS on dev box (verifies the primitive's
  semantics match the inlined version).
- cc5 byte-identical self-host.
- Cross-arch: works on Linux x86 + Linux aarch64 (the
  syscall numbers in lib/syscalls_*.cyr already cover poll
  / fcntl / getsockopt across both); Mach-O ARM uses BSD
  syscall numbers (already wired up).

#### v5.10.12 — `lib/tls.cyr` native-transport prep audit (sandhi 1.3.x prereq)

**Driver**: sandhi 1.3.x roadmap pinned this as a cyrius-side
ask under "Not sandhi's slot" — auditing the hook surface
(`tls_connect`, `tls_connect_with_ctx_hook`, ALPN / SNI / SPKI
extraction) for fdlopen-leaning assumptions ahead of any
future native-TLS transition. Per sandhi's ADR 0001 (sandhi
composes, doesn't reimplement), the hook surface is owned by
stdlib `lib/tls.cyr`; sandhi keeps calling the contract;
cyrius is responsible for keeping it byte-identical across
any transport swap.

**Scope** (audit-only, not a swap):
- Walk `lib/tls.cyr`'s public surface: every `tls_*` verb,
  the `tls_connect_with_ctx_hook` callback shape, the SPKI
  extraction path, ALPN / SNI parameters.
- Identify each spot where the implementation leans on
  fdlopen-loaded libssl symbol names, struct layouts, or
  ABI specifics that wouldn't survive a swap to a native
  cyrius TLS impl.
- Document each finding inline (`# v5.10.11 audit:
  fdlopen-bound — see ADR 000X if/when native-TLS lands`)
  + collect into `docs/audit/2026-MM-DD-tls-native-transport-prep.md`.
- No code changes unless the audit surfaces a hook-surface
  abstraction leak that should be fixed even before any
  swap (e.g., a callback signature that exposes libssl
  internals).

**Acceptance**:
- Audit document at `docs/audit/`.
- Inline annotations in `lib/tls.cyr`.
- Hook surface remains byte-identical (no caller-visible
  change).
- cc5 byte-identical self-host.

**Native-TLS swap itself is NOT in v5.10.x**. It's a separate,
much-bigger undertaking (multi-slot or multi-minor) that
needs its own design pass before pinning. v5.10.11 just
documents the surface so a future swap is guided.

#### v5.10.13 — SIMD math expansion (typed; hisab gap close)

Sandhi-side cousin of the type-system arc. Now that overload
dispatch exists (v5.10.2), SIMD primitives can be exposed as
typed verbs (`f64v4_add(a: f64v4, b: f64v4): f64v4`) instead
of raw `f64*` API. Width is part of the type; compile-time
check; overload dispatch picks the right SIMD primitive
(`f64v2` for 2-wide SSE2 or `f64v4` for 4-wide AVX or paired
NEON).

**JUSTIFIED, not speculative**: hisab documents a measured
30-700× gap vs Rust+glam in `docs/benchmarks-rust-v-cyrius.md`,
with "No SIMD" cited as a 2-4× cost factor on vector/matrix
ops. Hisab is the **keystone for Wave 4 (37 dependents —
impetus, kiran, joshua, aethersafha, tara, badal,
hisab-mimamsa, brahmanda)**. Per hisab's own benchmark doc,
"SIMD — Cyrius 5.x roadmap; would close gap 2-4×".

Compiler infrastructure already in place: f64v packed-SSE2
ops have been in production since v1.9.0 (`f64v_add` / `_sub`
/ `_mul` / `_div` / `_sqrt` / `_abs` / `_fmadd` in
`src/backend/x86/float.cyr`). The slot expands the SIMD
primitive set to cover hisab's hot Vec3/Vec4/Mat4 ops (cross
product, normalize, slerp, mat4 inverse, ray-sphere intersect
— top entries in hisab's gap table).

**Cross-arch budget**: x86 SSE2 (production); aarch64 NEON
equivalent (`fadd.2d` / `fmul.2d` for f64-packed; native on
Apple Silicon — cyim / hisab's macOS consumers); cx scalar
fallback (cxvm has no SIMD primitives); future RISC-V RVV
awaits the v5.11.x backend.

Acceptance: hisab's `bench-history.csv` shows measurable
improvement on at least one Wave-4-consumed op (cross /
normalize / mat4_mul / mat4_inverse), targeted at closing
the 2-4× gap. Cross-host gate verifies parity on aarch64.
Memory pin `project_simd_state.md` lays out the cross-arch
tax + the "byte-at-a-time is fine" stance applies to byte-
parsing not math.

#### v5.10.14+ — compile-time wins (lex / fixup), surface review, etc.

Items that don't unblock baseOS but improve developer
experience for everyone:

- **Lex dedup hot-path optimization**. v5.10.0 profile data
  shows lex at 580 ms (59% of compile time) and an O(N²)
  LEXID dedup scan inside it. Length-buckets (~20 LOC,
  ~5-10× expected on dedup_cmps) is the recommended starting
  point — preserves the linear-scan model per cyrius's
  byte-parsing philosophy. Last-K cache (~15 LOC, ~2-3×) and
  hand-rolled-hash-in-cc5 (~100 LOC, 30-40×) are escalation
  paths if length-buckets isn't enough.
- **Fixup phase optimization**. v5.10.0 profile shows fixup
  at 210 ms (21%). Second-largest target after lex.
- **Surface review** items: `cyrius audit` outside-repo
  semantics design call, `parse_fn.cyr:910` defensive
  guard, doc/vidya version-ref drift cleanup.

- **`CYRIUS_TYPE_CHECK` default-on flip** (deferred from
  v5.10.5 — see `parse_fn.cyr::_TYPE_CHECK_ENABLED`
  comment for the rationale). The v5.10.4 stdlib param-
  annotation pass DID clean up the original false-
  positive shape (Str-passing into annotated stdlib fns).
  But a separate false-positive shape surfaced at
  v5.10.5: Str values passed to GENERIC i64-shaped fns
  (`vec_push_a`, `alloc`, `map_set`, etc.) trigger the
  warning even though Str-as-i64-pointer is the legitimate
  semantic. Distinguishing "untyped i64" from "expects
  cstring" requires per-param scalar-vs-pointer
  annotation tracking. Lands when that infrastructure
  ships. Until then, the gate stays `CYRIUS_TYPE_CHECK=1`
  opt-in.

### v5.10.x — Held / pinned bug arc (slot-on-need)

Items earn a slot when consumer pressure surfaces or
opportunistic touch makes sense:

- **Shadow-lib guard** (pinned 2026-05-08 at v5.10.10 close
  — agnosys aarch64 SIGILL diagnosis surfaced the gap).
  cyrius's `READFILE` resolves `include "lib/<file>.cyr"`
  against cwd FIRST, only falling through to the version-
  pinned `$HOME/.cyrius/versions/<MY_VERSION>/lib/`. A stale
  `lib/` in a project folder (often left behind by an old
  `cyrius deps` run, manual install, or pre-version-pinning
  setup) silently shadows the version-pinned snapshot. Same
  cc5 binary + same source produces different output across
  machines depending on whether the project folder has a
  shadow lib, and worse — a shadow lib that's an OLDER
  version of `lib/fnptr.cyr` etc. emits the wrong asm
  blocks (e.g. x86 inline asm in an aarch64 binary), with
  no compile-time warning. Two complementary fixes worth
  considering:
  - **Compile-time warning** when cwd has a `lib/` that
    will shadow the version-pinned path. Print one
    `note: cwd lib/ shadowing version-pinned lib/ — using
    cwd; delete cwd lib/ to use the version-matched
    snapshot` so consumers catch the issue immediately.
  - **Defensive `lib/fnptr.cyr` rewrite** — gate x86 asm on
    `#ifndef CYRIUS_ARCH_AARCH64` so even if a shadow lib
    has stale content, the cc5_aarch64 binary's predefine
    wins and aarch64 asm emits regardless. Cross-arch
    pollution becomes a silent-correct-output instead of a
    silent-broken-binary.
  Lands when consumer pressure resurfaces or when the lib-
  resolution-precedence design call gets a fresh look.

- **REAL TYPE SYSTEM** (pinned 2026-05-08 at v5.9.36 wrap;
  user direction; multi-slot effort). Call-site type checking,
  overload dispatch (cstring vs Str vs int), type inference
  through expressions. Currently cyrius tracks type
  *annotations* (struct fields, var slots, fn params via
  `: Type` or `: Str`) and uses them for width-correct
  loadN/storeN + pointer-mode dot access — but the parser
  does NOT enforce types at fn call sites and there's no
  overload dispatch.

  **Canonical motivating example** — agnosys 1.1.12 verbatim
  repro at `/tmp/cyrius-derive-serialize-incomplete/minimal_repro.cyr`
  (hash `6425355b6147d5a674078794310ae2c1` at v5.9.37 ship).
  Builds clean post-v5.9.37 but the binary SIGSEGVs at runtime:
  ```cyr
  var out = str_builder_build(sb);    # out: Str
  println(out);                        # treats Str as cstring -> garbage
  println(strlen(out));                # treats int as cstring -> SIGSEGV
  ```
  Both lines are API misuse the type system would catch /
  dispatch correctly. v5.9.x had three options to fix
  (polymorphic-runtime-detection / break `str_builder_build` /
  partial Option-3); user rejected all three as either sloppy
  or breaking — the right fix is a real type system.

  **Multi-slot scope** (rough; refine at first slot entry):
  1. Surface audit — annotate every fn body in stdlib +
     cyrius-side code with implicit return-type info.
  2. Call-site type check — at `PARSE_FNCALL`, compare each
     arg's tracked type against the callee's param annotation.
  3. Overload dispatch — extend `FINDFN` to support multiple
     impls keyed by arg-type signature. PP-mangled names
     (`println_cstr` / `println_str` / `println_int`) at the
     symbol level; parser routes by arg type.
  4. Type inference — propagate fn return types through
     `var x = f(...);` and binary operators.
  5. Diagnostics — `error: cannot pass Str to fn expecting
     cstring; use str_data(x) or str_println(x)` hints.

- **`cyrius audit` outside-repo semantics** (held from v5.9.4;
  pending user design call). `cbt/commands.cyr:415` `cmd_audit`
  invokes `~/.cyrius/bin/check.sh` which doesn't exist outside
  the cyrius repo. Two design questions:
  (a) Intended semantics outside the repo (clean error vs
      polymorphic project-level audit)?
  (b) Defensive `file_exists(script)` check in `run_script`
      (one-line fix, applies to all script callers).
  The defensive guard is opportunistic — could land inside any
  v5.10.x slot that touches `cbt/build.cyr`. Full design
  question is held until user picks (a).

- **`cyrius --version` stray `\xb3` byte** (held from
  agnosys 1.1.5 filing side-observation). Locally NOT
  reproduced under v5.9.22+. Held until reporter's
  `~/.cyrius/current` xxd is captured. Defensive
  `read_file_str` hardening (extend trim to drop bytes ≥
  0x80) is the likely fix once env is reproducible.

- **`aarch64/fixup.cyr:19` syscall arity warning** (deferred
  from v5.8.53). "Likely benign lint, confirm or fix" —
  one-slot read.

- **macOS arm64 struct-by-value calling-convention path**
  (v5.5.36 deferred). Surfaces on consumer cross-build.

- **`parse_fn.cyr:910` defensive `_AARCH64_BACKEND==0`
  guard** (surfaced at v5.9.43 closeout code-review pass).
  x86 callee-save block is `if (_TARGET_CX == 0)` only; not
  a leak in practice (aarch64 doesn't auto-enable regalloc),
  but a v5.10.x defensive-guard cleanup target. Tiny;
  bundle into a related slot.

- **Stdlib data-domain distlib carve-out** (re-pinned from
  v5.9.0). ~13 modules (`json`, `toml`, `cyml`, `csv`,
  `base64`, `regex`, `math`, `matrix`, `linalg`, `bigint`,
  `u128`, etc.); sandhi-pattern fold-out into `cyrius-data`
  sibling distlib. Multi-slot effort; earns slot when
  scheduling lines up.

- **`lib/tls.cyr` hook-surface contract audit** (filed
  from sandhi 1.1.x roadmap-cleanup pass, 2026-05-08).
  With pure-Cyrius TLS removed (2026-04-24 decision —
  `lib/tls.cyr` stays libssl.so.3-bridged) AND sandhi
  folded into stdlib at v5.7.0, the `lib/tls.cyr` ↔
  `lib/sandhi.cyr` hook surface (`tls_connect`,
  `tls_connect_with_ctx_hook`, ALPN advertise, SNI, SPKI
  extraction) is now load-bearing across two stdlib
  modules. Sandhi's `tls_policy` layer (cert pinning /
  mTLS / trust-store override / ALPN advertise) exercises
  every hook; the contract was de-facto ratified at sandhi
  1.0.0 fold + 1.1.0 alloc migration end-to-end. Document
  it formally — per-hook docstring covering parameters,
  return semantics, error contract, ABI guarantees — so
  future maintenance (defensive hardening, internal
  refactors) preserves the byte-identical surface
  consumers built against. Tiny if surface is already
  abstraction-clean (likely — stable since v5.6.40 ALPN
  hook ship); multi-slot if any hardening surfaces. No
  P0/P1 today; opportunistic cleanup, earns a slot when
  scheduling lines up (e.g. could pair with the stdlib
  data-domain carve-out if that ever touches
  `lib/tls.cyr`, or with any future `lib/tls.cyr` patch).
  ADR-0001 framing on the sandhi side (sandhi composes,
  doesn't reimplement) makes this explicitly cyrius's
  slot, not sandhi's — sandhi can't audit a contract it
  consumes from outside.

- **Class B FFI / wgpu fncall6 ABI** (mabda B1/B2 — held;
  see *Deferred to v5.11.x or later* above). Could land in
  v5.10.x bug arc if mabda resurfaces it as blocking.

- **Surface review items** — tcyr-relay-vs-testsuite-gate
  redundancy (pinned v5.9.6); doc/vidya version-ref drift.
  Each gets a slot when the cleanup makes sense.

### v5.10.x — Held forward (no slot consumed; surfaces-on-ask)

These remain unpinned long-term; promote to slot when a
consumer concretely surfaces:

- **TS test harness program** (option E from v5.7.37) —
  single `programs/ts_test_runner.cyr` consuming both
  internal-symbol fn dispatch and TS fixture files. v5.7.37
  group-level consolidation suffices until a downstream
  consumer surfaces a test pattern that doesn't fit either
  current shape.

**No hard cap on slot count.** v5.10.x runs as long as the
work is productive — could be 5 patches, could be 20. Cycle
ends when the bug/optimization backlog drains or v5.11.x
bare-metal/RISC-V drivers concretely line up.

### v5.10.x — Acceptance principle (revised at v5.10.0 ship)

Each v5.10.x slot must close a chapter or open one with
measurable forward motion. No bookkeeping-only slots.

**A standalone ONE-thing slot is justified when**:
- **Big Heavy One Thing** — real refactor / non-trivial fix
  that can't reasonably bundle with adjacent work.
- **High-profile bug fix** — P0/P1 consumer-filed;
  user-visible regression; security item.
- **Tooling that opens a multi-slot arc** — e.g. v5.10.0
  profiling instrumentation that future optimization
  slots build on.

**A standalone slot is NOT justified for**:
- *"Updated 1 document to draft what we do next"* —
  planning rides along with implementation, not as its
  own version bump.
- *"One minor edit to whitespace"* / format-only / lint-
  satisfying nudges — bundle into the next real slot.
- Adjacent micro-fixes sharing the same cascade — bundle
  per the v5.9.38/40/42 lazy-defer feedback.
- Cleanup/refactor that earns measurable improvement only
  when paired with the next optimization — bundle.

The previous formulation ("ONE thing per slot, no bundled
work") was too strict — it would have argued against the
v5.9.39 Mach-O Bug A + Bug B + gate combined slot, which
landed correctly bundled because the three pieces were the
same cascade. Revised principle keeps the discipline
(don't sleight-of-hand bundle unrelated work) while
allowing tooling-arcs and same-cascade fixes to ride
together when the work is genuinely coupled.

User direction (2026-05-08, at v5.10.0 ship): "ONE thing
per slot needs revision; if it's a Big Heavy One Thing
sure... if it's a high-profile bug fix one thing yes;
I'll accept tooling as the start of a cleanup/optimization
arc this time. Otherwise if it's like I updated this 1
document to draft what we do next — HELL NO. Or made one
minor edit to whitespace... meh."

---

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

### v5.11.0 — Bare-metal / AGNOS kernel target

Bare-metal output (no libc, no syscalls, direct hardware).
AGNOS kernel is the concrete consumer. Has slid four minors
already (v5.7.0 → v5.8.0 → v5.9.0 → v5.10.0 → **v5.11.0**); no
hard trigger required — earns slot when AGNOS kernel work
concretely needs the toolchain capability AND the v5.10.x
backlog has drained enough to free a minor. Rough scope:

- ELF no-libc output format
- interrupt-handler emit conventions
- kernel-mode syscall stubs stripped
- boot pipeline from `scripts/boot.cyr` landed in genesis Phase
  13B (v5.6.29 gate)

Acceptance: AGNOS kernel can be built end-to-end with the
v5.11.0 toolchain; no host-libc symbols leak into the kernel
object.

### v5.11.x — RISC-V rv64 (3-5 sub-patches)

First-class RISC-V 64-bit target. Inherits a frontend-complete
compiler against a clean toolchain UX with the full v5.7.x →
v5.8.x prerequisite chain shipped, including the v5.7.30 +
v5.7.31 aarch64 f64 pair that gives RISC-V a working
f64-on-non-x87 reference. Just-another-platform work; lands
when scheduling allows.

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

### v5.11.x — Triggered prereq pin

- **Parser-to-emit named-op refactor (path A)** — pinned to
  v5.11.x because RISC-V landing as the 4th backend triggers
  the prior long-term pin's condition #1 ("RISC-V lands and
  adds 4th backend, making path B's `_TARGET_CX == 0 &&
  _TARGET_RISCV == 0` chains unwieldy at every site"). Scope:
  ~10 abstract ops × 4 backends = 40 fn definitions +
  parse_*.cyr rewrites. Multi-session real engineering. Pin at
  v5.11.0 cycle entry; sequence before RISC-V backend
  implementation if prudent (RISC-V starts with the named-op
  interface from day one — cleanest path). Audit doc:
  [`docs/audit/2026-04-27-cx-direct-emit-inventory.md`](../audit/2026-04-27-cx-direct-emit-inventory.md).

Deliberately NOT bundling other items into v5.11.x — bare-metal
+ RISC-V are plenty of work. Bare-metal (v5.11.0) lands first;
RISC-V picks up the rest of the v5.11.x range.

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
