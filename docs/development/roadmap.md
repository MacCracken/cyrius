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

#### v5.10.12 ✅ — Defensive `lib/fnptr.cyr` rewrite (agnosys aarch64 saga follow-on) (SHIPPED)

The originally-pinned audit-only scope (TLS surface
walk + inline annotations) was deferment dressed as a
slot. Pivoted to real code: 18 `#ifdef CYRIUS_ARCH_X86`
blocks in `lib/fnptr.cyr` wrapped with `#ifndef
CYRIUS_ARCH_AARCH64`. Defense-in-depth so even if
shadow-lib or env pollution leaks `CYRIUS_ARCH_X86`
into a cc5_aarch64 invocation, the AARCH64 gate wins
and the x86 asm block is skipped. cc5 byte-identical
self-host (no cc5 semantic change; gating lives in
stdlib). 66/66 check.sh, 134/134 cyrius test.

The originally-planned `tls.cyr` audit + native-transport
prep moved forward to v5.10.13 (was SIMD math; user
direction "TLS as priority" 2026-05-08) — pivoting from
audit-only to typed-wrapper consumer-pull work. Audit
walk DID surface real leaks (`tls_dlsym`,
`tls_connect_with_ctx_hook`'s raw `SSL_CTX*` arg, openssl
constants in `enum TlsConst`); v5.10.13 picks a
consumer-driven subset to fix.

#### v5.10.12 — original scope (kept here for closeout audit)

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

#### v5.10.13 ✅ — TLS surface tightening: typed `tls_set_alpn` + `tls_set_verify` wrappers + opaque-handle hook contract (SHIPPED)

Pivot from SIMD math on user direction "TLS as priority"
2026-05-08. The v5.10.12 audit walk surfaced abstraction
leaks; this slot closes the two highest-impact shapes
with consumer-driven typed wrappers.

`tls_set_alpn(handle, protos, len)` wraps
`SSL_CTX_set_alpn_protos`. `tls_set_verify(handle, mode,
callback)` wraps `SSL_CTX_set_verify`. Hook contract
clarified: the 2nd arg is now an OPAQUE handle (today
libssl-backed, future native-TLS-backed); consumers use
typed `tls_set_*` verbs instead of touching the handle.
`tls_dlsym` soft-deprecated as escape hatch. Sandhi's
`tls_policy/alpn.cyr` switchover is sandhi-side per
ADR 0001.

cc5 unchanged in semantic. api-surface 2796 → 2798. 66/66
check.sh, 134/134 cyrius test, doc-coverage clean.

Held forward: `enum TlsConst` openssl integer constants
(consumer-pull-driven typed names); `tls_get_alpn_selected`
typed wrapper for ALPN result readback.

#### v5.10.14 ✅ — multi-stack `#derive(...)` directives (agnosys V1.1.12-reopen blocker) (SHIPPED)

agnosys filed `2026-05-08-cyrius-derive-multi-stacking.md`
documenting that stacked `#derive(accessors) +
#derive(Serialize)` only honored one. Root cause:
`PP_PARSE_STRUCT_DEF`'s `#`-skip loop silently swallowed
the second directive. Fix: flag tracking at S+0x197F08 +
factored `PP_DERIVE_*_BODY` helpers + cross-emit in
entry-point handlers. Both stacked orderings (accessors-
first AND Serialize-first) emit the union of fns.

Multi-arg form `#derive(accessors, Serialize)` held
forward to a separate slot (different parse path).
Diagnostic on dropped/unknown directives also held.

cc5: 765,616 → 766,496 (+880 B). Byte-identical
self-host. 66/66 check.sh, 134/134 cyrius test.

#### v5.10.15 ✅ — Shadow-lib compile note (closes v5.10.10 held-arc) (SHIPPED)

cc5 now emits a one-line stderr note when cwd has a
`./lib/` that shadows the version-pinned
`$HOME/.cyrius/versions/<MY_VERSION>/lib/`. Probes via
`sys_open("lib", O_RDONLY|O_DIRECTORY)` at `_init_cyrius_lib`
end. `CYRIUS_NO_WARN_SHADOW_LIB=1` opt-out for cyrius-
repo dev workflow + consumers using vendored lib
snapshots intentionally. cc5: 766,496 → 771,784
(+5,288 B). Byte-identical self-host. 66/66 check.sh
(both with note firing AND with env opt-out), 134/134
cyrius test. Pairs with v5.10.12's defensive
`lib/fnptr.cyr` rewrite to close the agnosys-saga
held-arc completely.

#### v5.10.16 ✅ — SIMD cross-arch close + api-surface brace-desync (paired) (SHIPPED)

Two related lexer-correctness fixes plus a long-latent
codegen bug, bundled because the api-surface filing landed
the same day as the SIMD slot was running.

**Premise check at slot entry** uncovered the SIMD primitives
were broken on every arch — not "in production since v1.9.0"
as the prior roadmap entry claimed. Three layers:

- **aarch64**: `EMIT_F64V_LOOP/UNARY/FMADD` were `return 0;`
  no-op stubs. Fixed with NEON `.2D` packed-double encodings
  (`fadd` / `fsub` / `fmul` / `fdiv` / `fsqrt` / `fabs` /
  `fmla`).
- **x86 (latent codegen bug)**: loop-body load disp didn't
  apply the `_cur_fn_regalloc * 8 + _cur_fn_ret_stash`
  adjustment that EFLSTORE applies — fns with auto-regalloc
  segfaulted by 40+ bytes off the stash. Fixed via new
  `_F64V_DISP` helper + always-disp32 mov form.
- **cx**: arity-aligned no-op stubs to match x86 + aarch64
  signatures. Real cx f64 support is multi-minor scope.

Plus the **api-surface scanner brace-desync** fix in
`programs/cyrius_api_surface.cyr` — string + char + `#`
comment skip before brace counting, same pattern as
cyrlint v5.10.10. agnosys 1.1.13 surfaced this; their
filing's "numeric `125` read as `}`" hypothesis was wrong,
the actual cause was `{` inside JSON string literals like
`"{\"x\":"`. Fix is the same.

Coverage gate: `tests/tcyr/simd.tcyr` (8 asserts) wires
`f64v_*` into check.sh so the cross-arch gap can't silently
re-open. `programs/simd_expand_test.cyr` was the only
prior consumer and was never wired in — that's why both
the aarch64 stub AND the x86 codegen bug rode along
unnoticed for ~3.5 years of releases.

Cross-host SSH verify on pi (aarch64 Linux), ecb (Apple
Silicon Mach-O), cass (Windows PE) is part of the
acceptance bar — pending in this entry.

cc5 (x86): 771,784 → 771,464 (-320 B; helper factoring +
disp32 form net negative). cc5_aarch64: 467,016 → 468,888
(+1,872 B for NEON). api-surface snapshot: 2798 → 2808
(10 newly-revealed niyama_vim + cyml fns previously hidden
by the brace-desync). Byte-identical x86 self-host.
66/66 check.sh, 135/135 cyrius test.

#### v5.10.17 ✅ — SIMD math primitive expansion (dot, scale, axpy) (SHIPPED)

The "new primitives" half of the SIMD arc. Three keystone
primitives (`f64v_dot/scale/axpy`) implemented x86 SSE2 +
aarch64 NEON in same slot, plus `parse.cyr` statement-
level dispatch fix discovered while testing.

**Surfaced + fixed in-slot**: `parse.cyr` statement-
dispatch only covered `typ 62-105`. `f64v_scale(...);` as
a bare expression statement gave "unexpected unknown" with
misleading line numbers. Extended to `typ 128-130`.

**Encodings**:
- x86: `mulpd + addpd` for dot loop, `haddpd` (SSE3) for
  reduce. `mulpd + unpcklpd` broadcast for scale/axpy.
- aarch64: `fmla v2.2d` per iteration for dot, `faddp d0,
  v2.2d` for reduce. `dup v3.2d, v3.d[0]` broadcast +
  `fmul.2d` / `fmla.2d` for scale/axpy.
- cx: arity-aligned no-op stubs (still pending cx f64).

cc5: 771,464 → 778,120 (+6,656 B). cc5_aarch64: 468,888 →
473,688 (+4,800 B). Byte-identical x86 self-host.
66/66 check.sh, 135/135 cyrius test (+3 for dot/scale/
axpy groups). Cross-host verified: pi 11/11, ecb 11/11.

#### v5.10.18 ✅ — Hotfix: lib/process.cyr O_WRONLY (agnosys CI unblock) (SHIPPED)

Single-line fix in `lib/process.cyr:51`. Replaced
`O_WRONLY` (defined only in `lib/io.cyr` on Linux/macOS;
absent from process.cyr's docstring deps) with the
literal `1`, matching the `lib/fdlopen.cyr:234`
pattern. Pre-existing latent bug — only hit by
downstream consumers that don't include `lib/io.cyr`
(agnosys 1.1.13 surfaced via CI failure on their V1.1.12
ship). cyrius's own `programs/check.cyr` happened to
include io.cyr first so the bug rode through all
v5.10.x .0–.17 releases.

cc5 size unchanged (no compiler-side change). 66/66
check.sh, 135/135 cyrius test, byte-identical x86 self-
host, pi 11/11 simd cross-arch.

#### v5.10.19 ✅ — `cyrius deps` transitive include resolution (agnosys CI unblock #2) (SHIPPED)

Second iteration of the agnosys 1.1.x CI unblock. After
v5.10.18 fixed `O_WRONLY`, v5.10.19 fixes the next bug
in the chain: `cyrius deps` only copied directly-named
stdlib modules, not the per-arch peers they include
via `#ifdef CYRIUS_TARGET_*` dispatch. Affected
modules:

- `lib/syscalls.cyr` → needs `_x86_64_linux.cyr`,
  `_aarch64_linux.cyr`, `_windows.cyr`
- `lib/alloc.cyr` → needs `_macos.cyr`, `_windows.cyr`

Fix in `cbt/deps.cyr`: scan each copied stdlib file
for `include "lib/X.cyr"` directives and recursively
copy. CRITICAL detail caught mid-slot: only the
top-level (consumer-named) module gets pushed onto
`_dep_includes` — transitive files MUST NOT, or
`compile()`'s explicit-include prepend overrides the
arch-dispatcher `#ifdef`s and parses every peer
simultaneously (caused 135/135 → 15/120 regression
during slot iteration; recovered via `is_top` flag).

cyrius CLI: 168,392 → 170,848 (+2,456 B for the
recursive scanner). cc5 unchanged (fix is in `cbt/`,
not the compiler). 66/66 check.sh, 135/135 cyrius
test. Byte-identical x86 self-host.

#### v5.10.20 ✅ — P(-1) project hardening sweep (SHIPPED)

Refactor-cycle audit per CLAUDE.md P(-1) phase. Runs the
seven hardening steps before opening the v5.10.20+ slot
arc. Performed at the v5.10.19 → .20 boundary by user
direction 2026-05-09: "push current remaining back by
one; do a P(-1) hardening sweep on the project as
5.10.20; held items lets get them slotted and pinned —
leave mabda issue out to be held."

**Sweep results**:
1. **Cleanliness** — `check.sh` 66/66 (format + lint +
   vet gates). PASS.
2. **Test sweep** — `cyrius test` 135/135. 2-step
   self-host byte-identical (cc5 → cc5_b → cc5_c).
   Heap audit `tests/heapmap.sh` clean: 84 regions,
   0 overlaps. PASS.
3. **Benchmark baseline** — `cyrius bench` captured:
   vec/push_10 1µs, push_100 3µs, push_1000 21µs,
   vec/get 1µs, vec/find_100 1µs (15/15 bench
   asserts pass).
4. **Audit** — 34 unreachable fns / 22,792 bytes (all
   subsystem-prefix-protected per memory pin
   `feedback_dead_code_audit_scope`: TS_*/macho_*/IR_*
   are reachable via `--mode` flags or other
   `main_*.cyr` builds; not safe to remove). No
   FIXME/TODO/HACK markers in v5.10.x edits. api-
   surface clean (2,808 fns matches snapshot). Vidya
   version refs consistent. No new attack surface
   (READFILE call sites unchanged from pre-v5.10.16).
5. **Refactor** — nothing surfaced. v5.10.x cycle
   landed clean: SIMD primitives + cross-arch close
   + parse-dispatch + stdlib hotfixes + recursive
   `cyrius deps`. No consolidation opportunities
   identified.
6. **Post-audit benchmarks** — no refactor → no
   comparison needed. Baseline becomes the v5.10.20+
   reference for the optimization slots later in
   v5.10.x.
7. **Documentation** — this entry + slot-and-pin
   reorg of held items (next entries below). Roadmap
   re-baselined for the remaining v5.10.x cycle.

cc5 unchanged at 778,120 B. cc5_aarch64 unchanged at
473,688 B. cyrius CLI unchanged at 170,848 B. No
codegen changes; pure audit + roadmap restructure.

### v5.10.21+ — Slot pinning for the remainder of v5.10.x

User direction at v5.10.20 P(-1) sweep
(2026-05-09): "held items lets get them slotted and
pinned — leave mabda issue out to be held."

The v5.10.x bug arc is now concretely pinned. Mabda
Class B FFI / wgpu stays held (see end of file). TS
test harness moves to v5.11.x. v5.12.0 is now the
bare-metal AGNOS / RISC-V kickoff (was v5.11.x).

#### v5.10.21 ✅ — TLS surface completion: session resumption + 0-RTT (sandhi 1.3.x unblocking) (SHIPPED)

User flagged 2026-05-09: "when we did TLS did you fucking
differ the primary pieces? requested... No tls_set_session
/ tls_get_session / tls_write_early_data /
tls_read_early_data exist anywhere." v5.10.13 shipped
`tls_set_alpn` + `tls_set_verify` and silently deferred
the session-resumption + 0-RTT primitives sandhi 1.3.1/1.3.2
explicitly requested. v5.10.21 closes the gap: 10 new typed
wrappers + 2 capability probes covering session resumption
(`get_session` / `set_session` / `session_free` / 3
session-cache callback installers / `session_cache_mode`)
and TLS 1.3 0-RTT (`max_early_data` setter, `write_early_data`,
`read_early_data`). Plus extended `enum TlsConst` with
`SSL_READ_EARLY_DATA_*` status + `SSL_SESS_CACHE_*` modes.

Resolution failure for the new libssl symbols is non-fatal —
`tls_supports_early_data()` /
`tls_supports_session_resumption()` let consumers probe.
api-surface 2,808 → 2,820. Self-host byte-identical x86.
66/66 check.sh, 135/135 cyrius test.

#### v5.10.22 ✅ — REAL TYPE SYSTEM Phase 1A: Surface audit + bulk annotation (SHIPPED)

Phase 1 kickoff of the 5-phase type-system arc. Built
`programs/cyrius_type_audit.cyr` (audit tool) + ran
bulk annotation pass: 20/4124 (0.5%) → **3137/4124
(76%)** coverage. Smart annotator skips Result/Option-
returning fns (they need proper type annotation in
Phase 1B). cc5 unchanged (stdlib + src annotation pass
only, no compiler change). 66/66 check.sh, 135/135
cyrius test, byte-identical x86 self-host.

Remaining 987 fns deferred to v5.10.23 Phase 1B —
predominantly Result/Option/Tagged-returning. Phase 1B
also decides on `Result`/`Option`/`cstring` type
additions to the cyrius type vocabulary.

#### v5.10.23 ✅ — REAL TYPE SYSTEM Phase 1B: type vocabulary + annotation close (SHIPPED)

Phase 1B closes Phase 1. Added `Result` / `Option` /
`Tagged` / `cstring` to the parser's return-type
vocabulary in `src/frontend/parse_fn.cyr` (encoded
-16 / -17 / -18 / -19, all i64-shape at runtime). Bulk-
annotated ~735 more fns with their actual return type
via the Phase 1B smart annotator. Coverage 76% → 93%
(3872/4124).

Mid-slot regression caught + fixed: rough-scan at
fn-decl entry needed mirror-extension to recognize the
new type names; without it, Result-annotated fns
silently took retptr/X8 ABI and broke
`is_ok`/`result_unwrap` caller semantics
(result_stdlib.tcyr 15 sub-asserts went red, recovered
after fix).

cc5: 778,120 → 779,760. Byte-identical x86 self-host.
66/66 check.sh, 135/135 cyrius test. Phase 2 entry
criteria met.

#### v5.10.24 ✅ — REAL TYPE SYSTEM Phase 2: call-site type check (SHIPPED)

Phase 2 closes the v5.10.5 false-positive flood. Added
4 new per-fn param-type bitmasks (cstring/Result/Option/
Tagged) at heap region 0x124A000 (reused the 256KB
v5.5.37-retired gap). PARSE_FN_DEF param parser
recognizes the 4 new annotations + populates masks.
PARSE_FNCALL warning polarity inverted: fires only when
param EXPLICITLY `: cstring` (not when param is
unannotated, which was the v5.10.5 false-positive
shape).

Annotated `: cstring` on canonical-motivator stdlib fns
in `lib/string.cyr` (println/strlen/streq/strchr/atoi/
strstr/str_lower_cstr/str_upper_cstr/memchr) +
`lib/io.cyr` (file_open/file_open_r).

cc5: 779,760 → 783,408. Byte-identical x86 self-host.
66/66 check.sh, 135/135 cyrius test BOTH with and
without `CYRIUS_TYPE_CHECK=1` — **zero false positives**
on the full suite. Canonical motivator (`Str → cstring
mismatch`) warns correctly with hint catalog.

CYRIUS_TYPE_CHECK default-on flip stays pinned at
Phase 5 (v5.10.26).

#### v5.10.25 ✅ — REAL TYPE SYSTEM Phase 3 generalize: registry-based overload dispatch (SHIPPED)

Replaced the v5.10.3-5 hardcoded byte-by-byte name
lookups (`_PRINTLN_NOFF` / `_PRINTLN_STR_NOFF` /
`_PRINTLN_INT_NOFF` / `_STRLEN_NOFF` / `_STR_LEN_NOFF`,
~190 LOC) with a per-fn overload registry populated
automatically at `REGFN` time. `<base>(arg)` →
`<base>_str(arg)` / `<base>_int(arg)` /
`<base>_cstr(arg)` routing for ANY user-defined sibling
pair, no compiler edit needed.

3 new heap regions at `0x126A000+`
(`fn_overload_str` / `fn_overload_int` /
`fn_overload_cstr`) populated bidirectionally at REGFN
(forward when suffix-fn registers, reverse when base
registers). cc5: 783,408 → 780,288 (**−3,120 B** —
registry helper smaller than 5 hand-rolled name-ladder
fns it replaces). `lib/str.cyr` adds `strlen_str(s: Str)`
to fit the suffix convention (`strlen` → `str_len`
mapping was the only non-conforming hardcoded name).

Self-host byte-identical x86. **66/66 check.sh, 135/135
cyrius test, 0 type-check warnings on cyrius / agnosys
/ hisab / kavach** with `CYRIUS_TYPE_CHECK=1`. Agnosys
1.1.12 verbatim repro prints `hello\n5\n` clean.

#### v5.10.22-25 — REAL TYPE SYSTEM phase summary (continuation)

**Reordered at v5.10.21 slot-entry premise check**
(2026-05-09): typed `f64v2`/`f64v4` (originally
v5.10.21) needs overload dispatch infrastructure that
this arc provides — so the type system lands FIRST,
typed simd wrappers go after Phase 4 (overload
dispatch) ships. **Then re-reordered at v5.10.21 ship**:
TLS surface completion took the v5.10.21 slot (sandhi
unblocking partial-fix close), so REAL TYPE SYSTEM
shifts one slot later: phases 1-5 originally pinned at
v5.10.22-26.

Pinned 2026-05-08 at v5.9.36 wrap; user direction;
multi-slot effort. Promoted from "held bug arc" to
concrete slot pin at v5.10.20 P(-1) sweep.

**Premise-check correction at v5.10.25 slot entry**
(2026-05-09): empirical testing showed Phase 4 (type
inference for `var x = f();` and call-arg shapes) had
ALREADY shipped at v5.10.3-5 alongside the original
narrow dispatch, and Phase 3 (narrow hardcoded
dispatch) was also live for the canonical motivator.
The agnosys 1.1.12 verbatim repro printed
`hello\n5\n` clean BEFORE this slot opened. v5.10.25
shipped Phase 3 GENERALIZE (registry replacing
hardcoded dispatch) instead of inference work that was
already done. Phase 4 numbering retired; Phase 5 (flip)
moves up one slot to v5.10.26.

**Canonical motivating example** — agnosys 1.1.12
verbatim repro at
`/tmp/cyrius-derive-serialize-incomplete/minimal_repro.cyr`
(hash `6425355b6147d5a674078794310ae2c1` at v5.9.37
ship). Pre-v5.10.3 SIGSEGV'd at runtime:
```cyr
var out = str_builder_build(sb);    # out: Str
println(out);                        # treats Str as cstring -> garbage
println(strlen(out));                # treats int as cstring -> SIGSEGV
```
v5.10.3-5 narrow dispatch + inference closed it; v5.10.25
generalized the dispatch so it works for any user-defined
overload pair, not just the 3 hardcoded shapes.

**Phases shipped:**
1. **v5.10.22 — Phase 1: Surface audit** ✅ —
   `programs/cyrius_type_audit.cyr` + bulk annotation
   (76% coverage).
2. **v5.10.23 — Phase 1B: Type vocabulary close** ✅ —
   added `Result` / `Option` / `Tagged` / `cstring` to
   the parser's return-type vocabulary; coverage 93%.
3. **v5.10.24 — Phase 2: Call-site type check** ✅ —
   per-fn `cstring_mask` / `result_mask` / `option_mask`
   / `tagged_mask` bitmasks; PARSE_FNCALL warning
   polarity inverted to fire only on explicit `: cstring`
   annotations.
4. **v5.10.25 — Phase 3 generalize: registry-based
   dispatch** ✅
5. **v5.10.26 — Phase 5: CYRIUS_TYPE_CHECK default-on
   flip** ✅ — flipped env-default from off to on.
   `CYRIUS_TYPE_CHECK=0` opts out (retains env knob for
   diagnosis). Empirical zero-false-positive sweep across
   18 downstream consumers + cyrius itself confirmed
   safe. Slot ALSO repaired the v5.10.25 silent-regression
   that dropped the v5.10.24 cstring annotations from
   `lib/string.cyr`/`lib/io.cyr`; 11 annotations re-applied.

#### REAL TYPE SYSTEM arc closed at v5.10.26

Arc spanned 5 slots (v5.10.22-26) plus Phase 4 inference
(already shipped at v5.10.3-5 per premise check). Phase 5
flip lights up the type system for ALL consumers without
per-build env-knob — every cyrius compile now fires
Str→cstring warnings with hint catalog by default.

#### v5.10.27 ✅ — TLS staged-connect API (sandhi 1.3.1 client-resumption unblock — SHIPPED)

Closed via Option A (sandhi-preferred). Split
`tls_connect_with_ctx_hook` into:
- `tls_connect_alloc(sock, host, hook_fp, hook_ctx)` —
  Phase 1: SSL_CTX + SSL handle + fd binding + SNI + hook,
  stops before SSL_connect.
- `tls_connect_complete(ctx)` — Phase 2: runs SSL_connect,
  returns 1 on success / 0 on failure.

Existing `tls_connect_with_ctx_hook` collapsed to a 3-line
wrapper (alloc + complete + tls_close-on-fail). Existing
v5.6.40 callers see byte-identical behavior. api-surface
+2 fns. cc5 unchanged at 780,336 B (lib-only change).

Sandhi 1.3.1 can now do
`alloc → tls_set_session(ctx, cached_session) → complete`
to inject a cached session in the timing window.

Filed 2026-05-09 via
`sandhi/docs/issues/2026-05-09-stdlib-tls-staged-connect.md`.
Per `feedback_consumer_request_full_surface` — full
surface shipped this slot, no Phase B deferral.

#### v5.10.28 ✅ — value-type ABI Phase 1: f64v2 + 16-byte stack-local + x86 pair return (SHIPPED)

**Premise-check correction at slot entry** (2026-05-10):
empirical testing confirmed the v5.10.21 roadmap pin —
16-byte struct-by-value return ABI broken (high half lost).
Cyrius's existing struct types (Str etc.) are pointer-typed
(heap-allocated, accessed via load64), NOT register-passed
value types. The roadmap pin assumed typed-simd would compose
with overload dispatch but didn't account for missing
value-type ABI.

**User direction at slot entry**: "Real register-passing ABI"
(3-5 slots). f64v2/f64v4 typed simd extends across multiple
slots, starting with the foundational value-type ABI work.

**v5.10.28 shipped Phase 1**: f64v2 as a primitive value type
recognized by parser (rough-scan + post-param-list scalar
return + var-decl type annotation, sentinel encoding -20).
2-slot stack allocation reusing the v5.5.36 Phase 2 struct-
local pattern with hardcoded sv_sz = 16. x86 SysV multi-
register pair return (rax = lo, rdx = hi) via new emit
helpers `EFLLOAD_F64V2_PAIR` / `EFLSTORE_F64V2_PAIR`. PARSE_
RETURN dispatches f64v2 returns; parse_decl handles
caller-side `var x: f64v2 = f();` allocate-call-store-pair.

cc5: 780,336 → 784,312 (+3,976 B). Self-host byte-identical
x86 (no current cyrius source uses f64v2). 66/66 check.sh,
136/136 cyrius test (+1 new gate). aarch64 + cx backends
stub the f64v2 helpers with ERR_MSG fallback for cross-arch
propagation in Phase 2/3.

#### v5.10.29+ — value-type ABI Phases 2-5 (multi-slot)

Pinned 2026-05-10 at v5.10.28 ship per user direction
"Real register-passing ABI (3-5 slots)" + memory pin
`feedback_no_one_fix_per_slot` (genuine multi-slot work,
not lazy splits). Each phase delivers measurable forward
motion.

| Phase | Slot     | Status | Description |
|-------|----------|--------|-------------|
| 2     | v5.10.29 | ✅     | aarch64 propagation: X0+X1 pair return + ldur/stur emits in `EFLLOAD_F64V2_PAIR` / `EFLSTORE_F64V2_PAIR`. Pi SSH cross-arch verify: 8/8 sub-asserts pass. |
| 3     | v5.10.30 | ✅     | cx bytecode (r0+r1 pair); macho aarch64 inherits v5.10.29's emit (macho/emit.cyr binary-format-only). cxvm pipeline runs without crash on f64v2 code. |
| 4     | v5.10.31 | ✅ partial | Win64 PE retptr-style return (≤16B composite ABI). Codegen wired in PARSE_FN_DEF rough-scan / PARSE_RETURN / parse_decl caller side. Cross-compile produces valid PE32+ binary; runs on cass without crash. **Full runtime verify gated on Win64 stdlib** (println silent + exit-code propagation broken — pre-existing gaps, separate arc). |
| 5     | v5.10.32 | ✅     | x86 SysV XMM register passing optimization: `movupd xmm0, [&v]` + `movupd [&x], xmm0` (8 bytes each) replaces v5.10.28's int-class rax/rdx pair (14 bytes each). cc5 SHRINKS by 384 B from the encoding-density gain. Standard SysV PCS for SSE class composites. |
| 6     | v5.10.33 | ✅ partial | `lib/simd.cyr` typed wrappers (10 fns: make/lo/hi/add/sub/mul/div/fmadd/dot/scale) using pointer inputs + by-value f64v2 return. Closes the consumer-visible piece of the arc. **Param-side ABI, abs/sqrt, f64v4, and aarch64 V0 NEON deferred to slots 7–10.** |
| 7     | v5.10.35 | pinned | `PARSE_SIMD_EXT` 3-arg/4-arg same-TU codegen bug fix (unblocks `f64v2_abs` / `f64v2_sqrt`). |
| 8     | v5.10.36 | ✅     | aarch64 V0 NEON return-register optimization (mirrors v5.10.32 XMM0 work; replaces v5.10.29's X0+X1 int-class pair). cc5_aarch64 -560 B. |
| 9     | v5.10.37 | ✅     | `f64v4` (32-byte): x86 XMM0+XMM1 pair / aarch64 Q0+Q1 NEON pair (+imm12-scaled deep-frame fallback) / cx R0..R3 / Win64 retptr. cc5 +4,888 B. AVX/YMM0 path NOT in scope (future optimisation). |
| 10    | v5.10.38 | ✅     | f64v2 + f64v4 value-form param ABI (callee + caller; SysV/aarch64/cx end-to-end; Win64 PE errors out by design, points to v5.10.33 pointer-form wrappers). cc5 +6,064 B. |
| 11    | v5.10.39 | ✅     | Overload dispatch (`&IDENT → _ptr` routing via name-mangling + _FINDFN_CSTR; no new heap region) + `lib/simd.cyr` value-form wrapper migration (50 fns total: pointer-form universal + value-form gated on CYRIUS_HAS_VAL_SIMD_PARAMS for non-PE) + companion locname-staleness fix at ptyp 89-91 (companion to v5.10.35). cc5 +6,920 B. Arc fully closed. |

Adds `f64v2` and `f64v4` as primitive types (16-byte
and 32-byte packed-f64 respectively), overloaded
`f64v2_add(a: f64v2, b: f64v2): f64v2` etc. exposed in
`lib/simd.cyr`. The flat-array primitives
(`f64v_add`/`_dot`/`_scale`/...) remain the underlying
codegen — typed wrappers just give consumers a cleaner
API. Hisab benchmark gap (30-700× vs Rust+glam) closes 2-4×
once Phase 4 XMM register passing lands.

#### v5.10.29 — Stdlib data-domain distlib carve-out (multi-slot kickoff)

Re-pinned from v5.9.0; promoted from held to concrete
slot at v5.10.20 P(-1) sweep.

~13 modules (`json`, `toml`, `cyml`, `csv`, `base64`,
`regex`, `math`, `matrix`, `linalg`, `bigint`, `u128`,
etc.); sandhi-pattern fold-out into `cyrius-data`
sibling distlib. Multi-slot effort. Phased shape:
1. **v5.10.27 — Phase 1: Carve-out kickoff** — create
   the `cyrius-data` sibling repo, scaffold
   `cyrius.cyml`, identify the 13-ish module set,
   land the first 3-4 modules as proof of pattern.
2. **v5.10.28+ — Phase 2: Migration** — move the
   remaining modules with downstream consumer pin
   bumps in lockstep (sandhi-pattern lifecycle).
3. **v5.10.x — Phase 3: Carve-out close** — once all
   data-domain modules are in `cyrius-data`, retire
   the in-tree copies and update the stdlib_modules
   manifest.

May pair with `lib/tls.cyr` hook-surface audit
(v5.10.30) if scheduling overlaps and any module
touches TLS.

#### v5.10.34 ✅ — `lib/tls.cyr` early-data status accessors (sandhi 1.3.2 unblocker) + `docs/doc-health.md` scaffold (SHIPPED)

Two-piece slot per user direction at v5.10.33 ship:
the sandhi-blocker TLS work + the doc-health
convention adoption (initial scaffold from
agnosticos's pattern). Both ride the same slot
because (1) sandhi 1.3.2 is the consumer-driven
forcing function, (2) doc-health is a lightweight
ledger landing — no compiler-side change — and (3)
the two-piece shape avoids a bookkeeping-only
"one document drafted" slot per the v5.10.0 ship
acceptance principle (`feedback_one_thing_slot_revised`).

##### Piece A — TLS early-data status accessors (sandhi 1.3.2 unblocker)

Filed by sandhi 2026-05-10
(`/home/macro/Repos/sandhi/docs/issues/2026-05-10-stdlib-tls-early-data-status.md`)
after v5.10.31 verification surfaced the gap. Sandhi
1.3.2 (TLS 1.3 0-RTT, opt-in via
`sandhi_http_options_allow_0rtt`) is **blocked** on
this filing — the v5.10.21 0-RTT primitives ship the
write/read calls but not the post-handshake acceptance
check or pre-attempt eligibility probe required to do
0-RTT safely on the client side.

Two thin libssl wrappers + 3 enum constants:

```cyr
fn tls_get_early_data_status(ctx): i64;
# wraps SSL_get_early_data_status — returns:
#   TLS_EARLY_DATA_NOT_SENT  = 0
#   TLS_EARLY_DATA_REJECTED  = 1  → caller must resend
#   TLS_EARLY_DATA_ACCEPTED  = 2

fn tls_session_get_max_early_data(session): i64;
# wraps SSL_SESSION_get_max_early_data — returns max
# early-data bytes the cached session permits;
# 0 means session doesn't advertise 0-RTT.
```

Plus 3 entries appended to `enum TlsConst`. Same
defensive shape as the existing v5.10.21 wrappers:
null-check inputs, return safe defaults when the
libssl symbol is unresolved (so cc5 binaries built
against older libssl still link cleanly).

**Acceptance bar**:
1. Both wrappers + 3 enum entries land in
   `lib/tls.cyr`; api-surface snapshot regenerated.
2. `tests/tcyr/tls_early_data_status.tcyr` (new gate)
   exercises the symbol-resolution path on x86 +
   aarch64 (capability probe — both fns return safe
   defaults when symbol missing); cross-host SSH
   verify on pi for the aarch64 path.
3. Self-host byte-identical x86; 66/66 check.sh;
   cyrius test +1 gate.
4. Sandhi 1.3.2 unblocked: confirm via paired sandhi-
   side build that the new wrappers resolve and the
   `feedback_consumer_request_full_surface` antipattern
   is avoided (ship the FULL filing in one slot — both
   wrappers + the enum, not split).

Why now: per memory pin
`feedback_consumer_request_full_surface` (v5.10.13
ALPN+verify-only ship was the antipattern), when a
downstream files a request the FULL surface lands in
one slot. v5.10.21 closed the write/read primitives;
v5.10.27 closed the staged-connect timing window;
this slot closes the client-side correctness gap so
sandhi 1.3.2 can ship.

##### Piece B — `docs/doc-health.md` scaffold (convention adoption from agnosticos)

Initial scaffold of `docs/doc-health.md` — a living
ledger of doc currency per tier (fresh / stale /
read-through / archived / open-question). Convention
filed in agnosticos at
`agnosticos/docs/doc-health.md` and codified for
adoption in
`agnosticos/docs/development/planning/first-party-documentation.md`.
v5.10.34 is cyrius's adoption.

cyrius's doc tree is ~61 markdown files (vs
agnosticos's ~265) so the tier structure is leaner:

- Tier 1 — Structural (root + `/docs` root)
- Tier 2 — Architecture
- Tier 3 — Operational / Development
- Tier 4 — ADRs
- Tier 5 — Audits
- Tier 6 — Issues + Proposals
- Tier 7 — FFI / Reference
- Tier 8 — Archive

**Acceptance bar**:
1. `docs/doc-health.md` lands at the repo's `/docs`
   root (matches agnosticos's location post-relocation
   — whole-tree scope reflected in path).
2. Tier tables populated by inspection (filename +
   git-date spot-check), NOT a full per-doc audit pass
   — that's the next-cycle work the ledger surfaces.
3. Cross-refs to `state.md`, `roadmap.md`, CLAUDE.md
   "Closeout Pass" + "Security Audit Process" from
   the Forward-doc-policy-commitments table.
4. `CONTRIBUTING.md` (or equivalent index doc — verify
   at slot entry) gets a row pointing at doc-health.md
   per the agnosticos `first-party-documentation.md`
   pattern.

NOT in scope for this slot: doing the full per-doc
audit pass. The point of the ledger is to *surface*
which tiers need read-through (currently ~15 files
flagged 🟠). That work happens opportunistically in
follow-up slots (or rolls into v5.11.x cleanup).

#### v5.10.35 ✅ — `PARSE_SIMD_EXT` locname-staleness codegen fix (`f64v2_abs` / `f64v2_sqrt` unblock) + sandhi 1.3.3 stdlib fold + threat-model TLS refresh (SHIPPED)

Pinned 2026-05-10 at v5.10.33 ship as the first SIMD-
deferral cascade slot; sandhi 1.3.3 fold + threat-model
refresh added per user direction during the slot.

Pre-existing codegen bug in
`src/frontend/parse_expr.cyr` `PARSE_SIMD_EXT`: when a
4-arg `f64v_X` intrinsic (add/sub/mul/div/scale)
compiles in the same TU **before** a 3-arg `f64v_abs`
or `f64v_sqrt` call, the 3-arg form's emit shifts by
8 bytes and returns a stack address instead of the
absed/sqrt'd lo half.

Latent since v5.10.16 (when `f64v_abs` /
`f64v_sqrt` were introduced); never surfaced because
no consumer mixed 3-arg and 4-arg forms in one TU.
The v5.10.33 typed-wrapper layer would have done so —
diagnosed during v5.10.33 development; pinned out as
a separate-slot fix per `feedback_no_one_fix_per_slot`
(genuine multi-slot scope, not lazy split).

**Acceptance bar**:
1. Diagnose the 8-byte shift in `PARSE_SIMD_EXT`
   (likely a stack-offset miscalculation in the 3-arg
   path that's correct in isolation but wrong when
   the 4-arg path's slot allocation has run earlier
   in the TU).
2. Fix preserves correct emit for **both** 3-arg
   isolation and 3-arg-after-4-arg interleave.
3. Add `f64v2_abs` / `f64v2_sqrt` to `lib/simd.cyr`
   and exercise the interleave in
   `simd_typed_wrappers.tcyr`.
4. Cross-arch verify (x86 / aarch64 native pi /
   cx / macho ecb / Win64 cass) — bug fix is in
   shared parser, but the emit path differs per
   backend; check all four.
5. Self-host byte-identical x86; 66/66 check.sh.

#### v5.10.36 ✅ — aarch64 V0 NEON return-register optimization (typed-simd ABI Phase 8) (SHIPPED)

Pinned 2026-05-10 at v5.10.33 ship.

v5.10.29 (Phase 2) shipped aarch64 f64v2 return as
**X0+X1 int-class pair** (mirrors v5.10.28's x86
rax/rdx). v5.10.32 (Phase 5) shipped x86 SSE-class
optimization (XMM0 register passing, single MOVUPD).
This slot mirrors that for aarch64: replace X0+X1
int-class pair with **V0** (NEON 128-bit register)
using `ldr q0, [&v]` / `str q0, [&x]` (8 bytes each;
matches AAPCS64 SIMD class).

Mirror of v5.10.32: same shape, same cc5_aarch64
size-shrink expected from encoding density (8-byte
LDR Q vs 14-byte X-pair).

**Acceptance bar**:
1. `EFLLOAD_F64V2_PAIR` / `EFLSTORE_F64V2_PAIR` in
   `src/backend/aarch64/emit.cyr` rewritten to emit
   `ldr q0, [rbp+disp]` (`A4 0x ... NEON LDR Q`) and
   `str q0, [rbp+disp]`.
2. Existing `tests/tcyr/f64v2_byval_return.tcyr` +
   `simd_typed_wrappers.tcyr` pass cross-arch.
3. cc5 + cc5_aarch64 byte-identical post-fix on their
   respective hosts (no x86 emit change — aarch64-
   only optimization).
4. Real Pi (pi) + qemu-aarch64 verify: 9/9 sub-asserts
   on `simd_typed_wrappers.tcyr`; 8/8 on
   `f64v2_byval_return.tcyr`.

#### v5.10.37 ✅ — `f64v4` (32-byte packed-double) value-type (typed-simd ABI Phase 9) (SHIPPED)

Pinned 2026-05-10 at v5.10.33 ship.

Adds `f64v4` as a 32-byte primitive value type
(four packed f64s). Three backend strategies:

| Backend | Return ABI | Param ABI |
|---------|------------|-----------|
| x86 SSE2 | two-XMM pair (XMM0+XMM1, 32B) | retptr-style (>16B composite) |
| x86 AVX  | YMM0 single 256-bit register (AVX-detected at fn entry) | YMM0 single |
| aarch64 NEON | V0+V1 pair (32B) or V0 single (SVE2-detected later) | V0+V1 pair |
| cx       | r0+r1+r2+r3 (4-register pair; cxvm extension) | retptr |
| Win64 PE | retptr-style (>16B composite per MS x64 ABI) | retptr |

Builds on v5.10.36's V0 work for aarch64 and v5.10.32's
XMM0 work for x86. AVX detection at fn-entry uses
`CPUID.07H:EBX[5]` — gate behind `CYRIUS_SIMD_AVX=1`
env var initially; auto-detect at fn boundary in a
follow-up.

**Acceptance bar**:
1. `f64v4` recognized as primitive type in
   `parse_fn.cyr` rough-scan + return-type vocabulary
   (encoding `0 - 21` per the v5.10.28 pattern).
2. Stack-local allocation: 32-byte slot (4× f64 vs
   v5.10.28's 16-byte for f64v2).
3. Backend emit per the table above; per-backend
   `EFLLOAD_F64V4_*` / `EFLSTORE_F64V4_*` helpers.
4. `tests/tcyr/f64v4_byval_return.tcyr` (new gate)
   covers the cross-arch return path.
5. `lib/simd.cyr` extension: `f64v4_make` / `f64v4_*`
   wrappers around `f64v_*` intrinsics with arity 4.
6. Self-host byte-identical x86; 66/66 check.sh;
   cross-host pi/ecb/cass verify per memory pin.

#### v5.10.38 ✅ — f64v2 + f64v4 value-form param ABI (typed-simd ABI Phase 10, callee + caller) (SHIPPED)

Pinned 2026-05-10 at v5.10.33 ship as the arc-closing
slot.

The v5.10.28-32 typed-simd ABI work shipped the
**return side** end-to-end. The **param side** is
half-implemented — `fn f(v: f64v2)` reads the lo half
correctly via `&v + 0`, but `&v + 8` is undefined
memory because `parse_decl` allocates a single 8-byte
slot for the f64v2 param and the hi half is silently
dropped at the call-site register-to-stack transfer.

This slot fixes that: **2-slot allocation per f64v2
param + register-pair → 2-slot store sequence at fn
entry** (mirror of the existing return-pair → call-
site-pair load sequence). After this lands,
`lib/simd.cyr` typed wrappers can shift from
pointer-input form (`f64v2_add(a_ptr, b_ptr)`) to
value-input form (`f64v2_add(a: f64v2, b: f64v2)`)
via overload dispatch — the consumer-clean shape
originally intended for v5.10.33.

**Acceptance bar**:
1. `parse_decl` allocates 2 slots for f64v2 params
   (mirrors return-side multi-slot pattern).
2. Per-backend register-pair → 2-slot store at fn
   entry: x86 XMM0 → 2 stack slots, aarch64 V0 (or
   X0+X1 pre-Phase-8) → 2 slots, cx r0+r1 → 2 slots,
   Win64 retptr-passed → 2 slots.
3. `lib/simd.cyr` typed wrappers updated to
   value-param form: `f64v2_add(a: f64v2, b: f64v2):
   f64v2`. Pointer-input forms retained as `_ptr`
   suffixed variants for consumers needing them.
4. Overload dispatch (Phase 3 generalize from
   v5.10.25) routes `f64v2_add(&x, &y)` (pointer
   form) and `f64v2_add(x, y)` (value form)
   correctly.
5. `tests/tcyr/f64v2_byval_param.tcyr` (new gate)
   exercises the param-side ABI on every backend.
6. Self-host byte-identical x86; 66/66 check.sh; full
   cross-host pi/ecb/cass verify before tagging.

Arc fully closes at v5.10.39: from no-vector-types at
v5.10.27 → consumer-clean
`f64v2_add(a: f64v2, b: f64v2): f64v2` overload-
dispatched API across x86 SSE / aarch64 NEON / cx /
macho / Win64 PE.

#### v5.10.39 ✅ — typed-simd overload dispatch + `lib/simd.cyr` value-param wrapper migration (typed-simd ABI Phase 11, arc close) (SHIPPED)

Pinned 2026-05-10 at v5.10.38 slot entry as the
**pre-planned split** of the original v5.10.38 acceptance
bar per user direction *"A+B in .38; C as .39"*. The
v5.10.38 work shipped the language-level ABI (callee
multi-slot alloc + register-pair store at fn entry +
caller-side SIMD arg-reg routing). v5.10.39 ships the
consumer-facing surface on top:

1. **Overload dispatch** — extend the Phase 3 generalize
   (v5.10.25) registry-based routing to also key on
   pointer-vs-value first-arg shape, not just `_str` /
   `_int` suffix. `f64v2_add(p_ptr, q_ptr)` (callsite
   detects `&local` arg) → `f64v2_add_ptr`;
   `f64v2_add(p, q)` (callsite detects local f64v2 var)
   → `f64v2_add`. Same shape as the existing
   `<base>_str` / `<base>_int` dispatch.

2. **`lib/simd.cyr` value-param siblings** — add
   value-param shape for each existing pointer-form
   typed wrapper:
   - `f64v2_add(a: f64v2, b: f64v2): f64v2` alongside
     existing `f64v2_add(a_ptr, b_ptr): f64v2` (renamed
     to `f64v2_add_ptr` if needed for clarity)
   - Same for sub/mul/div/fmadd/dot/scale/abs/sqrt
   - Mirror for f64v4 surface

3. **`tests/tcyr/simd_value_param.tcyr`** — gate
   exercises both forms via overload dispatch + verifies
   correct routing across backends.

**Acceptance bar**:
- Self-host byte-identical x86 (overload dispatch is
  parser-internal; emit unchanged for existing
  consumers using the pointer form).
- 66/66 check.sh + cross-host pi/ecb/cass verify.
- Existing v5.10.33 pointer-form consumers (any
  ecosystem repo calling `f64v2_add(&x, &y)`) compile
  unchanged.

**Why split from v5.10.38**: A+B in .38 is already a
multi-touch slot (param-parse + per-backend prologue
emit + per-backend caller-side SIMD-arg load + per-fn
mask + cross-arch verify). Adding overload-dispatch +
the typed-wrapper migration in the same slot would
2× the surface and increase the chance a regression
hides between layers. C riding as a tail follow-up
gives the A+B work room to bake before consumer-side
typed-wrapper migration lands. Pre-planned split per
memory pin `feedback_no_one_fix_per_slot` (genuine
multi-piece work, not lazy defer).

#### v5.10.40 — Lex dedup hot-path optimization

Promoted from "compile-time wins" held entry to
concrete slot at v5.10.20 P(-1) sweep; cascaded from
original .31 pin at v5.10.33 ship (displaced by
value-type ABI Phases 1-5 + simd-deferral cascade).

v5.10.0 profile data: lex 580 ms = 59% of compile
time. O(N²) LEXID dedup scan inside it. Length-
buckets (~20 LOC, ~5-10× expected on dedup_cmps) is
the recommended starting point — preserves the
linear-scan model per cyrius's byte-parsing
philosophy. Last-K cache (~15 LOC, ~2-3×) and
hand-rolled-hash-in-cc5 (~100 LOC, 30-40×) are
escalation paths if length-buckets isn't enough.

Acceptance: measurable improvement vs the v5.10.20
P(-1) baseline (vec/push_1000 21µs, vec/find_100
1µs — these are the published reference points).

#### v5.10.41 — Fixup phase optimization

Promoted from held to concrete slot at v5.10.20 P(-1)
sweep; cascaded from original .32 pin at v5.10.33
ship. v5.10.0 profile: fixup 210 ms = 21% of compile
time. Second-largest target after lex.

#### v5.10.42 — `lib/tls.cyr` hook-surface contract audit

Filed from sandhi 1.1.x roadmap-cleanup pass,
2026-05-08; promoted from held to concrete slot at
v5.10.20 P(-1) sweep; cascaded from original .33 pin
at v5.10.33 ship.

With pure-Cyrius TLS removed (2026-04-24 decision —
`lib/tls.cyr` stays libssl.so.3-bridged) AND sandhi
folded into stdlib at v5.7.0, the `lib/tls.cyr` ↔
`lib/sandhi.cyr` hook surface (`tls_connect`,
`tls_connect_with_ctx_hook`, ALPN advertise, SNI,
SPKI extraction) is now load-bearing across two
stdlib modules. Sandhi's `tls_policy` layer (cert
pinning / mTLS / trust-store override / ALPN
advertise) exercises every hook; the contract was
de-facto ratified at sandhi 1.0.0 fold + 1.1.0
alloc migration end-to-end. Document it formally —
per-hook docstring covering parameters, return
semantics, error contract, ABI guarantees — so
future maintenance (defensive hardening, internal
refactors) preserves the byte-identical surface
consumers built against.

Tiny if surface is already abstraction-clean (likely
— stable since v5.6.40 ALPN hook ship); multi-slot
if any hardening surfaces. ADR-0001 framing on the
sandhi side (sandhi composes, doesn't reimplement)
makes this explicitly cyrius's slot, not sandhi's.

May pair with stdlib data-domain carve-out
(v5.10.27) if scheduling overlaps.

#### v5.10.43 — macOS arm64 struct-by-value calling-convention

Promoted from held to concrete slot at v5.10.20 P(-1)
sweep; cascaded from original .34 pin at v5.10.33
ship. v5.5.36 deferred. Surfaces on consumer
cross-build. Mach-O ABI work, isolated from other
held items — earns its own slot.

#### v5.10.44 — Defensive sweep (small bundle)

Promoted from held to concrete slot at v5.10.20
P(-1) sweep. Bundle of small defensive cleanups
that don't share a cascade but are individually too
small to justify standalone slots:

- **`parse_fn.cyr:910` defensive `_AARCH64_BACKEND==0`
  guard** (surfaced v5.9.43 closeout). x86 callee-
  save block is `if (_TARGET_CX == 0)` only; not a
  leak in practice (aarch64 doesn't auto-enable
  regalloc), but a defensive cleanup target.
- **`aarch64/fixup.cyr:19` syscall arity warning**
  (deferred v5.8.53). "Likely benign lint, confirm
  or fix" — one-slot read.
- **`cyrius --version` stray `\xb3` byte** (held
  from agnosys 1.1.5 filing side-observation).
  Locally NOT reproduced under v5.9.22+. Defensive
  `read_file_str` hardening (extend trim to drop
  bytes ≥ 0x80) is the likely fix. Lands as a
  defensive-only change even without env repro.
- **`cyrius audit` outside-repo defensive guard**
  (held from v5.9.4). `cbt/commands.cyr:415`
  `cmd_audit` invokes `~/.cyrius/bin/check.sh` which
  doesn't exist outside the cyrius repo. Defensive
  `file_exists(script)` check in `run_script`
  (one-line fix, applies to all script callers).
  The full design call (clean error vs polymorphic
  project-level audit) stays held until user picks
  semantics; the defensive guard ships now.
- **Surface review** — tcyr-relay-vs-testsuite-gate
  redundancy (pinned v5.9.6); doc/vidya version-ref
  drift cleanup. Bundle in if scope permits.

Earns a slot via "Big Heavy One Thing" — 5 items
add up to a meaningful defensive cleanup. Per the
v5.10.0 acceptance principle: bundling unrelated
defensives is OK when each is too small standalone
AND scheduling lines up.

#### v5.10.45 — Win64 PE `println` silent + exit-code propagation fix

Pinned 2026-05-10 at v5.10.33 ship. Pre-existing
Win64 stdlib gap surfaced repeatedly across the
v5.10.x cycle:

- **v5.10.31** (Phase 4 PE retptr-style): "Full
  runtime verify gated on Win64 stdlib (println
  silent + exit-code propagation broken — pre-
  existing gaps, separate arc)."
- **v5.10.33** (typed-simd typed wrappers, this
  ship): cross-host cass verify shows `exit=0` (test
  passes) but **no stdout** — `println` calls
  silently drop because the Win64 console-output
  path doesn't route `syscall(1, ...)` through
  `WriteFile` on `STD_OUTPUT_HANDLE`.

**Two-piece scope** (genuine multi-piece per
`feedback_no_one_fix_per_slot` — both pieces share
the same Win64 runtime cascade):

1. **`println` console output** — route
   `syscall(1, fd, buf, len)` on `_TARGET_PE == 1`
   through `kernel32!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),
   buf, len, &written, NULL)`. Currently the Win64
   syscall router (warning text:
   `"syscall(n, ...) on CYRIUS_TARGET_WIN=1 routes
   n=0,1,2,3,8,9,60 today"` claims n=1 is routed —
   verify whether it's truly wired or just stubbed.
2. **Exit-code propagation** — `syscall(60, code)`
   on Win64 PE must propagate `code` as the process
   exit code (currently observed `exit=0` even when
   the `.tcyr` returned non-zero from
   `assert_summary()`). Likely `kernel32!ExitProcess(code)`
   path.

**Acceptance bar**:
1. `tests/tcyr/simd_typed_wrappers.tcyr` on cass
   prints all 5 `===` group headers + the
   `9 passed, 0 failed` summary line, exit=0.
2. A deliberately-failing variant (assert with
   wrong expected value) returns `exit=1` on cass
   (proves exit-code propagation works in the
   non-zero case, not just by accident).
3. Existing `_pe_exit_gate` regression in
   `programs/check.cyr` continues to pass (T1
   exit=42, T2 hello+exit=42, T3 peephole). This
   slot tightens stdlib console-output / exit-code
   path; the bare-syscall path remains.
4. Self-host byte-identical x86 (no x86 codegen
   change); cross-host cass verify after fix shows
   correct stdout + exit codes for the SIMD typed-
   wrapper test and any other `.tcyr` cross-built
   for PE.

Why now: surfaced repeatedly, blocks meaningful
runtime verify on cass for stdlib-using `.tcyr`
fixtures. Before this fix, cass verify is "exit-
code-only" — fine for primitive gates (`_pe_exit_gate`
uses bare `syscall(60, 42)`), but blind for
anything using `println`-based test reporting.

#### v5.10.46 — v5.10.x cycle closeout

Pinned 2026-05-10 at v5.10.33 ship as the cycle-
close slot. Per CLAUDE.md "Closeout Pass (before
every minor/major bump)": ships as the LAST patch
of the v5.10.x cycle before tagging v5.11.0.

**Scope** (per CLAUDE.md §"Closeout Pass" 11-step
order):

**Mechanical (automated, fail-fast)**:
1. Self-host verify — cc5 byte-identical
2. Bootstrap closure — seed → cyrc → asm → cyrc
   byte-identical
3. Full check.sh — all gates green; record count

**Judgment-call passes**:
4. Heap map audit — newly-added regions, unused/
   stale, cap pressure, consolidation opportunities
   (the v5.10.x cycle added: nothing major to the
   primary heap map; verify against current
   `main.cyr` HEAP MAP block)
5. Dead code audit — unreachable fns floor recorded
   in CHANGELOG (per the existing N-unreachable
   note pattern)
6. **Refactor pass** — review v5.10.x diffs for
   consolidation. Likely candidates: f64v2 ABI
   dispatch across x86 / aarch64 / cx / macho /
   PE — 5 backends with similar shape; check if a
   common emitter helper makes sense (or if the
   per-backend asymmetry is genuine and should
   stay)
7. **Code review pass** — walk the v5.10.x diffs
   end-to-end. Specifically watch for: ABI leaks
   (unguarded x86 encodings on non-x86 paths,
   SysV leaks on Win64 paths), missed `_TARGET_PE`
   guards, byte-order typos in PE encoding hex
   literals, silently-ignored errors, off-by-one
   in fixup arithmetic
8. Cleanup sweep — stale comments (old version
   refs, outdated TODOs, references to renamed
   fns), dead `#ifdef` branches, unused includes,
   orphaned files in `build/` / `tests/`

**Compliance / external**:
9. Security re-scan — quick grep for new
   `sys_system`, `READFILE`, unchecked writes
   added during v5.10.x. Full audit pinned
   separately in `doc-health.md` Forward
   Commitments table (cycle audit due before
   v5.11.0)
10. Downstream check — all `cyrius.cyml` `cyrius`
    fields across ecosystem repos point to the
    released tag (sandhi 1.3.2, hisab, agnosys,
    mabda, etc.)

**Docs (silent-rot prevention)**:
11. CHANGELOG / roadmap / vidya sync per CLAUDE.md
    closeout-step-11. Vidya files manually refreshed
    (version-bump.sh doesn't touch them):
    `vidya/content/cyrius/language.cyml`,
    `field_notes/{compiler,language}.cyml`,
    `implementation.cyml`, `types.cyml`,
    `dependencies.cyml`, `ecosystem.cyml`. Doc-health
    ledger refreshed (per-tier "Last touched" dates
    bumped where the cycle touched them).

**Order matters**: mechanical first (fail-fast); judgment
passes uncover scope for follow-ups; doc sync last.
Refactor that lands during closeout MUST stay byte-
identical; otherwise defer to v5.11.0's first patch.

**Acceptance bar**:
- All 11 steps complete with green outcomes recorded
  in the v5.10.46 CHANGELOG entry.
- Cycle stats summarized: total patches, cc5 size
  delta v5.10.0 → v5.10.46, check.sh gate count
  growth, cyrius test growth, slot-summary table
  (one line per .x).
- v5.11.0 entry-bar prepped: P(-1) sweep starting
  point, baseline benchmarks captured.

**Additional closeout investigations (surfaced mid-cycle)**:

- **`cyriusly cmdtools install starship` add-only discipline**
  (filed 2026-05-10 at v5.10.36).

  **Governing principle** (user direction 2026-05-10):
  cyriusly's prompt-install role is **language-tool addition
  only** — same shape as how a `rust` / `node` / `python`
  toolchain integration would add its own per-language block
  to the user's prompt config. Cyriusly adds the
  `[custom.cyrius_pkg]` + `[custom.cyrius]` blocks and that's
  it. User's prompt format / modules / colors are theirs to
  configure; cyriusly never touches anything outside the
  cyrius-tagged blocks.

  Quote: *"The install process if starship cmdline tool
  requested with only add the language items... like rust or
  others... user can do what they want with that after."*

  **Repro target** (suspected clobber path):
  `scripts/cyriusly:265-271` —
  ```sh
  if grep -qE "custom\.cyrius(_pkg)?" "$_starship_conf" 2>/dev/null; then
      sed -i '/\[custom\.cyrius_pkg\]/,/^$/d' "$_starship_conf"
      sed -i '/\[custom\.cyrius\]/,/^$/d' "$_starship_conf"
  fi
  echo "" >> "$_starship_conf"
  echo "$_CYRIUS_STARSHIP" >> "$_starship_conf"
  ```
  Hypotheses to test:
  1. **Open-ended sed range** — `/\[custom\.cyrius\]/,/^$/d`
     deletes from match to the NEXT blank line; if the user's
     file ends without a trailing blank, the range extends to
     EOF and wipes everything after the cyrius block.
  2. **Adjacent-block bleed** — if user has the cyrius block
     followed directly by another `[module]` without an
     intervening blank line, the sed range crosses into the
     next module and deletes it too.
  3. **Stale-blank-line cascade** — multiple cyriusly install
     runs each append `echo ""` + the block; later cleanup
     seds may have unintended interaction with the
     accumulated blank lines.
  4. **`install.sh` elif `cat >` clobber** —
     `scripts/install.sh:529-541` writes a fresh starship.toml
     via `cat >` when the file doesn't exist AND starship is
     on PATH. If the file got removed between
     `cyriusly cmdtools remove starship` and a subsequent
     install, this branch could overwrite a fresh user-authored
     config. **This path should likely be removed entirely** —
     creating a fresh file with only cyrius blocks is too
     opinionated. If no config exists, the install should
     either ask first or just emit a stderr hint that the
     user should run `starship preset` (or similar) before
     re-running cyriusly.

  **Fix shape**:
  1. Switch the per-block delete from sed-range-to-blank-line
     to a bounded delete (awk block-aware filter, or sed with
     explicit `[custom.cyrius...]` open + the known fixed
     number of lines per block + the trailing blank).
  2. Drop the `install.sh:529` "create fresh starship.toml"
     elif. Cyriusly is add-only; if there's no config, leave
     it that way and print a hint.
  3. Same audit pass on the p10k integration
     (`scripts/cyriusly:273+`) — confirm it's also add-only
     for prompt_cyrius and doesn't touch other p10k functions
     or the user's `POWERLEVEL9K_*_ELEMENTS` arrays.

  **Add a regression gate** (cyrius-native, NOT bash — per
  the v5.x check.cyr conversion arc; see memory pin
  `feedback_sovereignty_no_other_languages`): add a
  bespoke gate fn in `programs/check.cyr` (e.g.
  `_cyriusly_starship_add_only_gate()`) that exercises in
  cyrius:
  - Clean install on a starship.toml with N user blocks → cyrius
    blocks appended; the N user blocks byte-identical.
  - Idempotent re-install → cyrius blocks replaced, N user
    blocks still byte-identical.
  - Install on a config with no trailing blank line → same
    result; no bleed.
  - Install on a config with cyrius block directly adjacent
    to another `[module]` (no blank separator) → cyrius
    replaced, adjacent module untouched.
  - Uninstall → cyrius blocks gone, N user blocks
    byte-identical.

  Open question for the gate: cyriusly itself is currently
  shell (`scripts/cyriusly`). The closeout fix may need to
  port the cmdtools paths into cyrius (a `cyriusly` cyrius
  binary, or a sub-command on the existing `cyrius` tool)
  before a cyrius gate can test it end-to-end. If that
  port is out of closeout scope, the gate uses cyrius to
  set up fixtures + invoke the shell `cyriusly` + assert
  on the resulting file bytes — still cyrius-native test
  code, just exercising a shell script as the subject.
  The shell→cyrius port itself can be a separate held item
  in v5.11.x.

  **Acceptance**: any non-cyrius bytes in the user's
  starship.toml are **byte-identical** before and after every
  cyriusly install/remove cycle. Cyrius blocks
  delete/re-add cleanly with no bleed in either direction.

  **User context** (v5.10.36): the immediate fix was a
  hand-restored `starship.toml` to just the two cyrius
  blocks (matching what was actually there before, per
  user confirmation); the install-path fix is closeout
  work, not slot-emergency work.

  **v5.10.37 follow-up — version-bump symlink-update gap
  (root cause confirmed)**. Surfaced 2026-05-10 during
  v5.10.37 mid-slot. User observed cyrius prompt segments
  rendering with stale versions after a `version-bump.sh`
  invocation. Across multiple version bumps (5.10.36 → .37),
  `~/.cyrius/bin` remained symlinked to `versions/5.10.34/bin`
  and `~/.cyrius/current` still read `5.10.34`.

  **Root cause (confirmed by manual repro 2026-05-10)**:
  `install.sh:224-235` uses `cp -L "$f" "$dst"` to copy
  `lib/*.cyr` into `~/.cyrius/versions/$VERSION/lib/`. When
  `lib/mabda.cyr` (project-side resolved by `cyrius deps`) is
  a symlink into `~/.cyrius/deps/mabda/<ver>/dist/mabda.cyr`,
  AND `~/.cyrius/versions/$VERSION/lib/mabda.cyr` is ALSO a
  symlink to the same real file, then `cp -L` dereferences
  both symlinks, sees source and destination resolve to the
  same inode, and exits with:
  ```
  cp: 'lib/mabda.cyr' and '/home/macro/.cyrius/versions/$VERSION/lib/mabda.cyr' are the same file
  ```
  install.sh's top-level `set -e` makes this fatal. Execution
  exits **before** reaching the symlink-update block at
  `install.sh:249-251` — so `~/.cyrius/bin`,
  `~/.cyrius/lib`, and `~/.cyrius/current` all stay pointing
  at the previous version. `cyrius-prompt-info` reads through
  `~/.cyrius/bin/cc5` for the toolchain version segment; a
  stale symlink renders stale numbers, which looks like
  "starship.toml corruption" from the user side even though
  the .toml content is intact.

  Aggravating factor: any `lib/*.cyr` that's a dep-resolved
  symlink whose realpath collides with the snapshot copy
  triggers this. As more deps fold in (`cyrius deps` ships
  more of stdlib via the deps-symlink pattern), the surface
  for this bug grows.

  **Fix shape** (per user direction 2026-05-10 — *"yeah
  lets do a C with A plan longer term..."*):
  1. **Primary fix (v5.11.x slot — see "`cyrius deps`
     file-copy instead of symlink for resolved deps"
     pin in v5.11.x scope above)**: change `cyrius deps`
     resolution to physically copy `lib/<dep>.cyr` from the
     dep cache instead of symlinking. This eliminates the
     root cause at the architectural layer — install.sh's
     `cp -L` then sees distinct inodes everywhere and the
     "same file" collision can't fire.
  2. **Belt-and-suspenders in install.sh** (this slot,
     v5.10.46 closeout): even with the v5.11.x cyrius-deps
     fix, harden the refresh-only lib-copy loop against
     the same-file class of errors generally. Replace
     `cp -L "$f" "$dst"` with `rm -f "$dst" && cp -L "$f"
     "$dst"` (or guard with realpath equality check + skip).
     Defensive layer for any future symlink-collision path
     that might re-emerge (e.g. user-set symlinks from
     other tools).
  3. Add a tail-of-refresh-only verification step that
     `readlink ~/.cyrius/bin` matches the new version; hard
     fail with the actionable diagnostic ("re-link did not
     update — investigate the cp loop above") if not. This
     turns the silent-skip into a loud failure, which would
     have caught this bug in seconds instead of multiple
     observations across slots.
  4. **Long-term — port version-bump into cyrius**
     (per the sovereignty principle; v5.11.x or later).
     bash is acceptable bootstrap-layer glue but this
     dance lives in PATH territory, runs after cyrius
     is built, and could be `cyrius bump 5.10.X` instead.
     Would also retire the regex-hunting fragility around
     CHANGELOG version sed, the cross-script-state
     synchronization, etc.

  Manual workaround (until fix lands): after every
  `version-bump.sh`, run
  `rm -rf ~/.cyrius/{bin,lib} && ln -sf ~/.cyrius/versions/$(cat VERSION)/{bin,lib} ~/.cyrius/ && echo $(cat VERSION) > ~/.cyrius/current`.

### v5.10.x — Held (no slot pinned; surfaces-on-ask)

Items that DO NOT get concrete slot numbers — they
stay held until consumer pressure surfaces them.

- **Class B FFI / wgpu fncall6 ABI** (mabda B1/B2).
  Held per user direction at v5.10.20 P(-1) sweep:
  "leave mabda issue out to be held." Lands in
  v5.10.x or later if mabda resurfaces it as
  blocking; otherwise rolls into v5.11.x consideration.

**No hard cap on v5.10.x slot count.** Cycle runs
as long as the pinned slots produce measurable
forward motion. Cycle ends when the pinned items
above ship + the bug/optimization backlog drains.
The next cycle (v5.11.x) absorbs the held-forward
items below; v5.12.0 is the bare-metal kickoff.

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

### v5.11.x — Cleanup minor (TS test harness + held-forward absorber)

**Repurposed at v5.10.20 P(-1) sweep** (2026-05-09): user
direction "TS test harness will moving into 5.11.x and
5.12.0 is now baremetel/riscv". v5.11.x is now a short
cleanup-cycle absorbing items that surface during the
v5.10.x close, NOT the bare-metal / RISC-V kickoff (which
moves to v5.12.0).

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
     (per the v5.10.46 closeout pin) is ALSO landed as
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
  gates remain — including the v5.10.46-pinned
  `_cyriusly_starship_add_only_gate` whose subject is itself
  the shell `scripts/cyriusly`. Folding the remaining `.sh`
  gates into cyrius lands in v5.11.x **BEFORE** the TS test
  harness because the harness work benefits from a
  fully-cyrius gate surface to consume.

  **Acceptance bar** (multi-patch, refine at slot entry):
  1. Inventory: walk `tests/regression-*.sh` (if any remain)
     + the v5.10.46 closeout-investigation gate, list each
     subject + assertion shape.
  2. Per-gate: rewrite as a bespoke fn in
     `programs/check.cyr` using `lib/regression.cyr` helpers
     (same shape as `_macho_exit_gate` / `_pe_exit_gate`).
  3. **Cyriusly cmdtools port** — the v5.10.46 starship
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

No hard trigger; v5.11.x runs as long as cleanup work is
productive, ends when v5.12.0 bare-metal/RISC-V drivers
concretely line up.

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
