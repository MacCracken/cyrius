# Cyrius Development Roadmap

For completed work, see [completed-phases.md](completed-phases.md).
For detailed changes, see [CHANGELOG.md](../../CHANGELOG.md).


## 5.x major patch history

All per-patch detail through v5.x lives in
[CHANGELOG.md](../../CHANGELOG.md) — the source of truth.

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

### Shipped slots — see CHANGELOG.md

Per-slot detail for v5.11.0 → current lives in
[CHANGELOG.md](../../CHANGELOG.md) — the source of truth.
Volatile current state (version, cc5 size, in-flight slot,
recent shipped patches) lives in [state.md](state.md).

The pin-history / decision-context narrative for shipped slots
was trimmed at v5.11.42 sweep — ~1100 lines of stale slot-
planning prose superseded by what actually shipped.
Consumer-filed issues from the 2026-05-10 wave (kavach P1
sandbox syscalls, daimon aarch64 epoll_wait, bote net /
fl_free / streaming / WS handshake, parser assert quirk) all
shipped through v5.11.0 → v5.11.28; issue files `git mv`'d
to [`issues/archived/`](issues/archived/).

Held forward (still gated on consumer-surface triggers):
- **Class B FFI / wgpu fncall6 ABI** (mabda B1/B2) — held per
  v5.10.20 P(-1) sweep direction; pin if mabda resurfaces.
- **`cyim` regex pattern parse error** (mabda C6) — defer per
  user 2026-05-12 until cyim repo updates + re-tests against
  current cyrius.


### Remaining slots toward close (v5.11.32 → v5.11.69)

**v5.11.32 — User-binary ELF cleanup (x86 user emitter)** [SHIPPED]

`EMITELF_USER` at `src/backend/x86/fixup.cyr:827` now emits the
same 5-section ELF64 table as the .29/.30/.31 kernel + linker
emitters. See CHANGELOG `[5.11.32]`.

**v5.11.33 — `PP_IFDEF_PASS` 2 MB cap raised to 8 MB** [SHIPPED]

`preprocess_out` relocated `S + 0x44A000` → `S + 0x4EAD000` (8 MB,
appended past LEXID dedup); brk extension grew
`S + 0x4EAD000` → `S + 0x56AD000` (heap 78.6 MB → 86.6 MB). Plan A
single-slot relocation per project-leader approval 2026-05-12. Old
0x44A000..0x64A000 (2 MB) documented as freed gap absorbed by
v5.11.68's full reorg. Sit consumer verified — builds clean past
the prior cap-error site. See CHANGELOG `[5.11.33]` + archived
issue.

**v5.11.34 — User-binary ELF cleanup (aarch64 user emitter)** [SHIPPED]

`EMITELF` at `src/backend/aarch64/fixup.cyr:323` now emits the
same 5-section ELF64 table as v5.11.32 (x86 user) / .30 (aarch64
kernel). Pi cross-host smoke: `exit=42` + `readelf -S` lists 5
sections after `scp`. **Series complete** — all five ELF emit
paths (.29 x86 kernel / .30 aarch64 kernel / .31 cyrld linker /
.32 x86 user / .34 aarch64 user) carry section metadata. See
CHANGELOG `[5.11.34]`.

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

All v5.x toolchain-quality work has shipped — per-slot detail in
[CHANGELOG.md](../../CHANGELOG.md):

- `cyrius_api_surface` — public-fn inventory tool
- LSP cross-file go-to-def + textDocument/references (v5.9.10)
- LSP textDocument/semanticTokens/full (v5.9.10 baseline; legend
  extended at v5.11.42 to cover `var X` locals + `fn(args)` params)
- cyrlint forward-ref scanner
- `ts_test_runner` (v5.11.11)

No remaining toolchain-quality items. New asks land via consumer
filings to `docs/development/issues/`.

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
- ~~**Bridge-compiler retirement assessment.**~~ **Done v5.11.66
  (2026-05-19).** `src/bridge.cyr` deleted (2005 LoC). Audit
  confirmed bridge was never in any active build path — the only
  active reference was a `scripts/bench-history.sh` line that
  treated it as a cc5 INPUT (compile-time benchmark target),
  not as a compiler. Bootstrap chain is now `seed → cyrc → cc5`
  cleanly. v6.0.0 absorbs the win.
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
