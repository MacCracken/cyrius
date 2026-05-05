# Cyrius Development Roadmap

For completed work, see [completed-phases.md](completed-phases.md).
For detailed changes, see [CHANGELOG.md](../../CHANGELOG.md).


## v5.3.x / v5.4.x / v5.5.x / v5.6.x / v5.7.x — shipped

All v5.3.x–v5.7.x per-patch detail lives in
[completed-phases.md](completed-phases.md);
[CHANGELOG.md](../../CHANGELOG.md) is the source of truth.

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




## v5.8.x — Optimization + language-vocabulary stabilization (62 pinned slots; cycle backstop hard at .62 — extended from .51 at v5.8.45 ship to absorb Unicode 17.0.0 fold, then to .55/.57/.59/.61/.62 across the wind-down to absorb cross-arch propagation, audit/dedup/refactor trio, str_data heap bump, NFKC/NFKD K-forms, and the v5.8.61 heap-map refactor; release-valve slot at .51 absorbed surface-during-deps-update items, Unicode work occupied .52–.55, cycle wind-down at .53–.62)

**Theme** (re-scoped 2026-05-01 at v5.8.0 ship): bug-fix /
optimization minor that ALSO folds forward the language-feature
suites originally pinned for v5.10.x / v5.11.x / v5.12.x —
slices, effect annotations, tagged unions + exhaustive match,
`Result<T,E>` + `?` propagation, and allocators-as-parameter.

**Strategic re-theming** to compress the original 4-5 separate
language-feature minors into one cycle: shipping these in v5.8.x
lets hisab + downstream consumers do ONE port pass instead of
re-porting across v5.9.x → v5.12.x. Coherent with the
optimization theme — `Result<T,E>` IS an optimization across
every -1/0/errno hot path; allocator-parameter convention IS
the perf-correctness alignment that enables per-request arenas;
slices replace ptr+len pairs in every crypto / network / I/O
hot path.

**51 pinned slots** (v5.8.1 → v5.8.51) across 3 phases (cascaded
+1 at v5.8.5 for SSH-gate carve-out, +4 at v5.8.9 for slices
re-scope to 5-patch sub-arc, **+6 at v5.8.14 to absorb the
slices true-completion sub-arc** — v5.8.13's "honest scope-
shrink" deferrals were a bandaid; user-directed re-scope to
ACTUALLY ship first-class slices instead of typedef + helpers;
**+1 at v5.8.18 for api-surface refresh + auto-build wiring +
null-byte-in-shell-substitution fix** — gate has been silently
skipping since v5.7.50 due to unbuilt binary;
**+2 at v5.8.22 for exhaustive-match cap bump (v5.8.24) + arm-
tag dedup (v5.8.25) follow-ups** — known refinements moved into
discrete pinned slots after v5.8.23's stdlib migration validates
real-world consumer pressure):
- Phase 1 (v5.8.1–v5.8.8): quick-win unblockers — fmt cap raise,
  packaging fix, ts/parse fmt sweep, f64_log2 parser dispatch
  (v5.8.4) + f64_log2 SSH-gate hardware verification (v5.8.5),
  syscall surface symmetry, _SC_ARITY audit, NI-class
  investigation. **Phase 1 complete at v5.8.8 ship.**
- Phase 2 (v5.8.9–v5.8.38): language vocabulary —
  slices foundation (5, v5.8.9-13) + slices true-completion
  (6, v5.8.14-19), effects (1), tagged unions + exhaustive
  match (7, v5.8.21-27 — extended +2 by v5.8.22 cap-bump +
  dedup cascade), Result<T,E>+? (5, v5.8.28-32), allocators
  (6, v5.8.33-38).
- Phase 3 (v5.8.39–v5.8.44): polish + closeout — including
  api-surface refresh as v5.8.44 (pre-closeout backstop
  sized for fix + snapshot regen + downstream consumer
  rebuild verification).

Soft backstop holds at ~.49 (mirroring v5.7.49's end-of-cycle
backstop pattern) through cascades. 5-slot headroom
(v5.8.45-v5.8.49) covers surface-during-cycle items + a final
closeout backstop if Phase 3 finds late-cycle issues. Below
v5.7.x's 51-patch record.

**Bare-metal arc + RISC-V rv64 stays at v5.9.x** — arch-port
work better paired after the language vocabulary stabilizes.
**v5.13.x** then opens for tail-end v5.x work (security
hardening, polymorphic codegen, `cc5`→`cyc` prep) before v6.0.0.

### v5.8.0 ✅ P(-1) hardening + vani fold-in + cyriusly starship.toml — SHIPPED 2026-05-01

Triple-anchor opener for the minor:

**1. P(-1) hardening** per CLAUDE.md §"P(-1): Project Hardening" —
cleanliness (`cyrius fmt --check`, `cyrius lint`, `cyrius vet`), test
sweep (.tcyr / heap audit / self-host), benchmark baseline (`cyrius
bench` pre-changes), audit (stale code / dead paths / opt
opportunities), refactor pass on findings, post-audit benchmarks vs
baseline, doc sync (CHANGELOG / roadmap / vidya).

**2. Vani audio distlib fold-in.** Pinned 2026-04-30. `vani` (Sanskrit
वाणी, Saraswati's name — "voice / speech") is the audio-domain
sibling distlib mirroring the mabda / sankoch / sigil / yukti pattern.
Fold-in doc: [`vani/docs/development/cyrius-stdlib-fold-in.md`](https://github.com/MacCracken/vani/blob/main/docs/development/cyrius-stdlib-fold-in.md).
Vani-side migration done already (lib/audio.cyr → vani/src/alsa.cyr,
two-byte stack-array bug fix carried in the lift, "audio" dropped
from `[deps].stdlib` in vani's manifest).

Cyrius-side work:

1. Add `[deps.vani]` block to `cyrius/cyrius.cyml` (alphabetical slot
   between `[deps.sigil]` and `[deps.yukti]`), pinned to whatever
   vani tag ships at 5.8.0 cut time:
   ```
   [deps.vani]
   git = "https://github.com/MacCracken/vani.git"
   tag = "<vani-tag-at-cut>"
   modules = ["dist/vani.cyr"]
   ```
2. Delete `cyrius/lib/audio.cyr` (236 LOC). `dist/vani.cyr` provides
   the same `audio_*` symbol set bundled inline plus the higher-level
   `vani_*` API (typed errors, ring buffer, XRUN recovery, mixer,
   yukti adapter).
3. CHANGELOG entry: "audio.cyr retired — ALSA PCM now lives in vani;
   consumers replace `include \"lib/audio.cyr\"` with `include
   \"lib/vani.cyr\"`."
4. Pre-flight `grep -rn 'lib/audio.cyr' /home/macro/Repos` to confirm
   no in-tree consumer still imports the old path (per vani's fold-in
   doc, no AGNOS in-tree consumer does as of vani v0.1.0 cut).
5. Refresh stdlib-reference and ecosystem.cyml entries — vani joins
   the canonical sibling-distlib roster alongside mabda / sankoch /
   sigil / yukti / sandhi.

API stability: `audio_*` surface is byte-for-byte stable — existing
call sites keep working under the new include path. New `vani_*`
surface (typed errors, ring buffer, XRUN recovery, mixer) becomes
available without further work.

**3. `cyriusly` starship.toml prompt rework.** Cyrius identity glyph
at the shell level. Current state (`scripts/cyriusly:190-206`) ships
a single `[custom.cyrius]` segment with `symbol = "𝕮"` (Mathematical
Bold Fraktur C, U+1D56E) showing the toolchain version. Reworking
into a two-segment flow:

Target format: `<pkg-icon> NAME VERSION (repo) | <cyrius-icon> VERSION`

- **Cyrius icon**: 🌀 cyclone (U+1F300) primary, with `𝕮` retained
  as the ASCII-ish fallback (the existing symbol stays valid in
  terminals that don't render the emoji cleanly; cyclone signals
  self-hosting recursion + the "cyr-" name shape). Implementation:
  set `symbol = "🌀"`, document the fallback in the script comment;
  consumers on emoji-hostile terminals can keep their existing
  installs (which still have `𝕮`).
- **Package icon**: ॐ Om (U+0950). Aligns with the ecosystem's
  Sanskrit naming convention (sigil / mabda / sakshi / sankoch /
  samvada / vani / yukti / patra all Sanskrit) — instantly identifies
  a cyrius package without competing with rust's 📦 / go's gopher /
  python's snake.

Sketch:

```toml
# Package segment — fires when cyrius.cyml [package] block exists
[custom.cyrius_pkg]
command = """awk '/^\\[package\\]/{p=1; next} p && /^\\[/{p=0} p && /^name/{gsub(/[ "=]/,""); n=substr($0,5)} p && /^version/{gsub(/[ "=]/,""); v=substr($0,8); if(v ~ /\\$\\{file:VERSION\\}/) {while((getline x < "VERSION") > 0) v=x}} END{print n " " v " (" basename "")}' basename="${PWD##*/}" cyrius.cyml"""
when = "test -f cyrius.cyml"
symbol = "ॐ"
style = "bg:teal"
format = '[[ $symbol $output ](fg:base bg:teal)]($style)'

# Toolchain segment — fires alongside, separated by the | divider
[custom.cyrius]
command = """if [ -f bootstrap/asm ]; then cat VERSION 2>/dev/null; else cc5 --version 2>/dev/null | awk '{print $2}' || cat ~/.cyrius/current 2>/dev/null || echo '?'; fi"""
when = "test -f cyrius.cyml || test -f cyrius.toml"
symbol = "🌀"
style = "bg:teal"
format = '[| $symbol $output]($style)'
```

Concrete format-string + parser robustness (cyrius.cyml `[package]`
shape variations, version interpolation `${file:VERSION}`) pinned
during the slot. Mirror the same icon swap into the p10k segment
(`scripts/cyriusly:198-206`).

### v5.8.x — pinned slot map (30 slots; pinned 2026-05-01)

Surfaced from sakshi `2026-04-30-cyrius-lang-blockers.md`, mabda
`2026-04-30-toolchain-issues.md`, phylax `2026-04-30-cyrius-
stdlib-issues.md`, and the 2026-05-01 vidya audit. Plus the
language-vocabulary suites pulled forward from the original
v5.10.x / v5.11.x / v5.12.x scope per the 2026-05-01 re-theming
(strategic compression: one ecosystem port pass instead of 4-5).

**Pinning policy**: 30 slots pinned firm; soft backstop ~.44
with 14 slots of headroom for surface-during-cycle items.
Single-issue patches per the v5.4.x / v5.5.x discipline — no
grab-bags. Phase boundaries are advisory; if Phase 1 surfaces
follow-ons or Phase 2 sub-patches need extra slots, the cycle
absorbs them within the headroom budget.

#### Phase 1 — Quick-win unblockers (slots 1-7)

- **v5.8.1** — `cyrius lint` / `cyrius fmt` 128 KiB buffer cap
  raise (mabda Class A1). Same fix shape as v5.7.36 distlib
  (64K → 256K → 524K). Silent truncation past 131,072 B —
  `cyrius fmt $f > $f` destroys data; mabda `backend_native.cyr`
  (137 KiB), cyrius's own `src/frontend/ts/parse.cyr` (195 KiB,
  deferred from v5.8.0 fmt sweep) both hit this. Bump to
  ≥524288 B (4× distlib precedent for fmt output growth).
  **Bundles**: `cyrius-prompt-info` redundancy fix (drop
  `name` from `pkg` mode output — `ॐ vidya 2.3.0 (vidya)` →
  `ॐ 2.3.0 (vidya)`; one-line edit to `scripts/cyrius-prompt-
  info`).

- **v5.8.2** — `cc5_aarch64` packaging fix (sakshi / yukti) +
  `build/cyrc_check` orphan delete (audit §4). Move
  `cc5_aarch64` back under `bin/` in `install.sh` / release
  tarball; drop downstream workaround pattern from sakshi /
  yukti / patra / mabda CI files. Paired with the trivial
  `build/cyrc_check` orphan delete (zero references in `scripts/`
  / `.github/` / `tests/`; audit §4). Canonical upstream report:
  [`yukti/docs/development/issues/2026-04-30-cyrius-cc5-aarch64-packaging.md`](https://github.com/MacCracken/yukti/blob/main/docs/development/issues/2026-04-30-cyrius-cc5-aarch64-packaging.md).

- **v5.8.3** — `src/frontend/ts/parse.cyr` fmt sweep follow-up.
  Closes the v5.8.0 deferral (file at 195,483 B couldn't fmt
  without truncation); v5.8.1's cap raise unblocks it. Mechanical
  patch — single `cyrius fmt` invocation; should produce the
  ~1500-line idiomatic re-flow.

- **v5.8.4** ✅ `f64_log2` aarch64 polyfill — parser dispatch
  (phylax #1). Shipped 2026-05-01 at `79eeae4`. Replaced the
  parse_expr.cyr hard-reject with stdlib polyfill dispatch
  mirroring the v5.7.30/31 f64_exp/f64_ln shape. New
  `_f64_log2_polyfill` in `lib/math.cyr` via change-of-base
  `log2(x) = ln(x) * F64_LOG2E`; new `F64_LOG2E` global hoisted
  from `_f64_exp_polyfill`'s local. cc5 720,928 → 721,352 B
  (+424 B for new dispatch). x86 path unchanged (native fyl2x).

- **v5.8.5** ✅ `f64_log2` aarch64 polyfill — SSH-gate hardware
  verification. Shipped 2026-05-01. Carved out from v5.8.4
  per user direction after pi-live status surfaced post-commit.
  Extended `tests/regression-aarch64-f64-polyfill.sh` with 4 new
  log2 cases (log2(1)=0, log2(8)=3, log2(1024)=10, log2(0.5)=-1)
  + ulp-budget comments + check.sh gate description update.
  cc5_aarch64 cross-compiler rebuilt (420,648 → 421,072 B,
  matching cc5's dispatch growth). Verified bit-accurate on real
  aarch64 hardware via SSH pi. **Phylax #1 now FULLY closed**
  (parser dispatch + hardware-verified polyfill). Bug-fixed
  during gate authoring: initial test bit-pattern for log2(1024)
  was wrong (0x408F4... = 1000.0, not 1024.0); corrected to
  0x4090000000000000.

- **v5.8.6** ✅ `sys_stat` / `sys_fstat` x86_64 wrapper backfill
  (phylax #2). Shipped 2026-05-01. 4 LOC fn additions to
  `lib/syscalls_x86_64_linux.cyr` (sys_stat → SYS_STAT direct
  syscall; sys_fstat → SYS_FSTAT direct) closing the cross-arch
  surface asymmetry against `lib/syscalls_aarch64_linux.cyr:346-
  353`. Block comment documents the divergence (x86 has direct
  stat/fstat; aarch64 routes through newfstatat with AT_FDCWD).
  cc5 unchanged at 721,352 B (stdlib-only). Phylax + agnosys
  drop their local backfills on next pin bump.

- **v5.8.7** ✅ `_SC_ARITY` cross-arch false-positive gate
  (phylax #3 + sakshi). Shipped 2026-05-02. Single-line gate in
  `parse_expr.cyr:589` (`if (_AARCH64_BACKEND == 0) { ... arity
  check ... }`). The arity table is x86_64-specific by design;
  on aarch64 the same numerical syscall values denote different
  operations (e.g. aarch64 SYS_NEWFSTATAT=79 = x86 getcwd; aarch64
  SYS_FSTAT=80 = x86 chdir). Pre-fix: 11 spurious warnings on
  4-line stdlib probe. Post-fix: 0. Tradeoff: hand-written aarch64
  syscalls with wrong arity now surface at runtime instead of
  compile-time. Future polish slot could add `_SC_ARITY_AARCH64`
  to restore aarch64-side arity warnings — held until a consumer
  surfaces an aarch64 arity bug.

- **v5.8.8** ✅ phylax #4 NI-class investigation — STALE PIN,
  closed by sigil 3.0.0 upstream churn. Shipped 2026-05-02.
  Premise-check at slot entry surfaced the dupes don't reproduce
  at v5.8.7 + sigil 3.0.0; sigil's own `[lib].modules` section-
  header fix in 2.9.5 → 3.0.0 closed both x86 and aarch64 dupe
  classes; cyrius's pin to 3.0.0 at v5.7.49 deps refresh
  transitively closed phylax-reported residue. Verified clean
  across 3 reproduction paths (sigil src/lib.cyr aarch64 cross,
  programs/smoke.cyr aarch64 cross, sigil tcyr 96/96). Doc-only
  patch matching v5.7.46 audit-pass shape.

#### Phase 2 — Language vocabulary stabilization (slots 9-30)

The 5-feature compression: ship slices + effect annotations
+ tagged unions + `Result<T,E>` + `?` + allocators in one
cycle so hisab + downstream consumers do ONE port pass. Each
sub-feature's sub-patch breakdown matches the original
v5.10.x/v5.11.x/v5.12.x scopes.

##### v5.8.9–v5.8.13 — First-class slices (`slice<T>` / `[T]` generalizing `Str`)

A type carrying `(ptr, len)` with bounds-aware APIs. Every
`read(buf, len)` / `memcpy(dst, src, n)` / `aead_encrypt(pt,
pt_len, ct, ct_len, tag)` today is a ptr+len pair the compiler
doesn't check — slices make bounds-aware APIs the default.

**Scope re-pinned 2026-05-02 at v5.8.9 ship**: originally
single-slot; honest scope-check at slot entry surfaced this
needs the same 5-patch sub-arc shape as Tagged unions / Result /
Allocators. Sub-arc:

- **v5.8.9** ✅ §1 — Type-position parse-acceptance for
  `slice<T>` + `[T]`. Shipped 2026-05-02. Pure parser change in
  `parse_decl.cyr`'s PARSE_VAR type-annotation block: added
  LBRACKET branch consuming `[T]` element-type forms;
  `slice<T>` form already parse-accepted via the existing ident
  + SKIP_GENERICS path. No codegen, no AST tree (cyrius main
  parser has no TYPE AST kinds; that's TS-frontend-only). §1
  description's "TYPE_SLICE AST kind" was overscope — corrected
  during slot to "parse-acceptance only" matching v5.7.45 const-
  type-params shape. cc5 +464 B for new branch. Test:
  `tests/tcyr/slices_parse.tcyr` 9/9 PASS across all element-
  type variations.
- **v5.8.10** ✅ §2 — Codegen layer (16-byte alloc + helper API).
  Shipped 2026-05-02. PARSE_VAR's `[T]` branch sets
  `scalar_type = 16` (reusing u128's 16-byte stack-slot path);
  `slice<T>` ident form matched via 5-byte "slice" name-match
  (0x6563696C73 little-endian). Both forms now allocate 16-byte
  `{ptr, len}` slots. New `lib/slice.cyr` ships 9 helpers
  taking slice POINTER (`&s`): slice_set / slice_of / slice_ptr
  / slice_len / slice_zero / slice_copy / slice_eq /
  slice_is_empty / slice_is_null. Honest scope-shrink during
  slot: dot-syntax field access (`s.ptr` / `s.len`) deferred —
  would require unifying struct-field path with `scalar_type=16`
  scalar path. Bounds-aware indexing also deferred — needs
  element-type tracking parser doesn't have. Both pin candidates
  for follow-up slots if consumers surface concrete pain.
  cc5 +88 B. Tests: `tests/tcyr/slices_codegen.tcyr` 26/26 PASS.
- **v5.8.11** ✅ §3 — Str ↔ slice<u8> structural equivalence +
  stack-slice builders. Shipped 2026-05-02. Honest scope-shrink
  during slot: investigation surfaced that Str is ALREADY a
  slice<u8> structurally (`str_new` does `alloc(16); store64(s,
  data); store64(s + 8, len)` — byte-identical to a 16-byte
  stack slice). No API migration needed — Str-typed values pass
  directly to any slice helper. Documented the equivalence in
  both `lib/str.cyr` and `lib/slice.cyr` headers. Added 2 stack-
  slice builders to `lib/slice.cyr`: `slice_from_cstr` (analog
  of `str_from`) and `slice_from_buf` (analog of `str_new`) —
  for cases where heap allocation is undesirable. cc5 unchanged
  at 721,936 B (stdlib-only). Tests:
  `tests/tcyr/slices_str_interop.tcyr` 15/15 PASS.
- **v5.8.12** ✅ §4 — vec ↔ slice<T> structural-prefix
  equivalence + scope-shrink doc. Shipped 2026-05-02. Honest
  scope-shrink: vec fits naturally (first 16 bytes byte-identical
  to slice prefix); hashmap doesn't (32-byte header is not a
  contiguous-element shape, no slice abstraction); 454-site
  migration of sys_read/memcpy/memeq deferred (multi-slot scope,
  opt-in once helpers exist). Documented vec's structural
  equivalence in `lib/vec.cyr` + `lib/slice.cyr` headers; vec
  values pass directly to slice_ptr/len/is_empty/is_null/eq.
  Added `vec_as_slice(dst, v)` to lib/slice.cyr — snapshot
  semantics (dst's ptr may invalidate if vec_push reallocs).
  cc5 unchanged at 721,936 B (stdlib-only). Tests:
  `tests/tcyr/slices_vec_interop.tcyr` 12/12 PASS.
- **v5.8.13** ✅ §5 — Sub-arc closeout (slices FOUNDATION
  shipped, true completion deferred). Shipped 2026-05-02.
  Doc-only patch. Sub-arc retrospective documented (4 tcyrs,
  62 assertions, 11 helpers, 3 docs, ~190 LOC, +552 B cc5
  across 5 slots). **Honest reckoning post-ship**: §1-§5
  shipped a typedef + 11 helpers, NOT first-class slices —
  every hard piece (TYPE_SLICE typing, bounds-aware indexing,
  dot-syntax access, Str API migration, 454-site migration)
  got "honest scope-shrink" deferral. User-directed re-scope
  v5.8.14-v5.8.19 absorbs the deferred work as proper slots
  (see "##### v5.8.14–v5.8.19 — slices true-completion sub-arc"
  immediately below). v5.8.13 stays shipped as foundation
  release; .14+ delivers what "first-class" actually means.

##### v5.8.14–v5.8.19 — slices TRUE-COMPLETION sub-arc ✅ COMPLETE 2026-05-02

Re-pinned 2026-05-02 at v5.8.13 ship. The v5.8.9-v5.8.13 sub-
arc shipped a foundation but deferred every load-bearing piece.
This sub-arc absorbs that deferred work as proper slots.

**Sub-arc complete at v5.8.19 ship.** All 6 slots green:
§6 (typing), §7 (subscript), §8 (dot-syntax), §9 (pointer-to-
struct dot-syntax), §10 (slice-typed wrappers), §11 (closeout
retrospective). 159 slice assertions across 9 tcyrs. cc5 size
delta +6,024 B (721,936 → 727,960 B). See v5.8.19 CHANGELOG
entry for the full retrospective + lessons learned.

- **v5.8.14** §6 — TYPE_SLICE element-type tracking. Parser
  stores element width per slice var (currently `scalar_type=16`
  loses element type after annotation parses). New per-local
  field tracking (1=u8, 2=u16, 4=u32, 8=i64/ptr, 16=u128) so
  downstream lowering knows the right load*/store* width.
  Foundation for sized indexing in §7.
- ✅ **v5.8.15** §7 — Bounds-aware indexing `s[i]` (shipped
  2026-05-02). Lowering uses element width from §6: `s[i]` →
  `_slice_idx_get_W(&s, i)` via the width-specific helper from
  `lib/slice.cyr`. Bounds violation: stderr `slice bounds
  violation\n` + exit 134. **§7 SCOPE NOTE**: subscript syntax
  works on fn-local slices (where ~99% of real subscripting
  happens); top-level vars still need the helper-fn API
  directly — var-side subscript-syntax support reserved as
  follow-up if a downstream consumer asks. Slot also fixed a
  **pre-existing slot-collision bug**: adjacent fn-local
  16-byte vars (slices, u128) shared a stack slot because
  PARSE_VAR only bumped local count by +1; now bumps by +2 for
  scalar_type=16 with high-slot name/depth/type/slice-w
  cleared. Bug had been silent since v5.5 because no tcyr
  exercised adjacent fn-local 16-byte vars. Editor integration
  folded in: new `.lsp.json` + `docs/editor-integration.md` +
  README section.
- ✅ **v5.8.16** §8 — Dot-syntax field access `s.ptr` /
  `s.len` (shipped 2026-05-02). PARSE_FIELD_LOAD/STORE local-
  ident branch grew a slice short-circuit lowering dot access
  to address-based memory I/O via the canonical-slot address.
  Slot also fixed a **pre-existing 16-byte fn-local layout
  bug**: pre-fix the canonical slot was at the higher address
  and `&slice + 8` overflowed past the local frame into saved-
  rbp territory; `slice_set` clobbered saved rbp, `slice_len`
  read it back. Layout-flip puts the high half at the higher
  address, canonical at the lower address — `&slice + 8` now
  correctly hits the high half. Slot also added a **tail-call
  escape skip**: PARSE_RETURN's TCO detector skips when any
  arg passes `&local`, since the tail-call epilogue
  deallocates the frame before the callee reads through the
  pointer. **§8 SCOPE NOTE**: same as §7 — fn-local slices
  only; top-level vars still need helper-fn API. Var-side
  support reserved as the same follow-up slot.
- ✅ **v5.8.17** §9 — Pointer-to-struct dot-syntax capability
  + Str fn-param SLTYPE tagging (shipped 2026-05-02).
  PARSE_FIELD_LOAD/STORE auto-detects pointer-vs-inline by
  checking if slot lli-1 has the v5.5.36 sentinel name -1; if
  yes, inline-mode (`EFLADDR_X1`); else pointer-mode
  (`EFLLOAD + EMOVCA`). PARSE_FN_DEF tags `: <StructName>`
  param slots with `SLTYPE = -sid` so `param.field` resolves
  via the struct-typed-local branch. **Honest scope shift**:
  pinned scope was ~30-site stdlib migration; empirical scope
  was 81 sites + a `: Str` annotation per site (most stdlib
  fns take untyped params). Capability ships now; mass
  migration moves to v5.8.18 §10 which folds in the
  str_data/str_len sweep alongside the original 454-site
  sys_read/memcpy/memeq work. **§9 SCOPE NOTE**: dot-syntax
  fires only when the local or param has the `: Str` (or other
  struct) annotation; untyped locals storing Str pointers fall
  through to the existing error path.
- ✅ **v5.8.18** §10 — Slice-typed wrapper helpers
  (`sys_read_slice` / `slice_copy_bytes` / `slice_eq_bytes`)
  shipped 2026-05-02. **Honest scope-shrink**: pinned scope
  was the 454-site mass migration + the §9-deferred ~80-site
  str sweep; empirical counts came in smaller (~295 sites
  total) and a pilot migration of `lib/fs.cyr` was reverted
  twice in-flight, signalling that mass call-site churn isn't
  wanted this slot. Capability ships now (additive — canonical
  (ptr, len) primitives stay as the building blocks); mass
  sweep deferred to a future slot once a downstream consumer
  earns the change. The "454-site re-port pain" the cycle-
  compression argument was meant to prevent doesn't materialize
  from the helper-fn API existing — downstream code calling
  `memcpy(dst, src, n)` keeps working unchanged.
- ✅ **v5.8.19** §11 — TRUE sub-arc closeout (shipped
  2026-05-02). Doc-only / verification slot — no compiler or
  stdlib code change. Sub-arc retrospective + sub-arc
  COMPLETE marker. The "downstream consumers rebuild against
  migrated stdlib" line in the original pin assumed §9/§10
  would mass-migrate; both honest-scope-shrunk to capability
  + tcyr (twice-reverted lib/fs.cyr pilot signalled mass
  churn wasn't wanted), so §11's downstream-rebuild story
  collapses to a no-op assertion: additive helpers don't
  break any pre-existing call site. Sub-arc total: §6-§11,
  6 slots, 159 slice assertions across 9 tcyrs, +6,024 B
  compiler size delta (721,936 → 727,960 B), 11+10+3 = 24
  helpers in lib/slice.cyr, 4 stale pin items closed.

**Acceptance gates** (per slot, true-completion sub-arc):
1. Byte-identical self-host at every patch.
2. v5.8.14 gate: type-tracking visible — `var s: [u8] = 0`
   stores element width 1; `var t: [i64] = 0` stores 8;
   verifiable via compiler-internal probe or runtime sentinel.
3. v5.8.15 gate: `tests/tcyr/slices_indexing.tcyr` — bounds
   guard fires on out-of-range index; in-range elements load
   with correct width per §6 element type.
4. v5.8.16 gate: `tests/tcyr/slices_field_access.tcyr` —
   `s.ptr` and `s.len` work without helper fns; assignable
   via `s.ptr = newptr` / `s.len = newlen`.
5. v5.8.17 gate: stdlib `str_data` / `str_len` call sites
   migrated; backward-compat aliases functional; tcyr coverage
   exercises both old and new shapes.
6. v5.8.18 gate: stdlib internal callers of sys_read/memcpy/
   memeq migrated; tcyr coverage exercises slice-typed signatures.
7. v5.8.19 gate: every downstream consumer builds against the
   migrated stdlib (with explicit migration notes for any that
   need source changes — backward-compat aliases mean most
   downstream is unaffected).

Was originally pinned at v5.9.0 in the defunct TLS arc; rehomed
at v5.7.49; re-pinned to v5.8.9 at the 2026-05-01 re-theming;
expanded from single-slot to 5-patch sub-arc at v5.8.9 ship;
re-expanded to 11-patch sub-arc (foundation 5 + true-completion
6) at v5.8.13 ship per user direction "complete the task as
assigned, it was there for a reason".

##### v5.8.20 ✅ — Per-fn effect/purity annotations (`#pure` / `#io` / `#alloc`)

Shipped 2026-05-02. Compiler-checked decorators that catch
helpers that silently allocate or touch I/O in "pure" crypto
paths. Simpler than OCaml5 / Koka effects (no polymorphism,
no row types) — three decorators the compiler warns on at
every call-site mismatch. **Warnings, not errors** for
downstream incremental adoption (same shape as #must_use /
#deprecated). Both PARSE_FNCALL and tail-call (PARSE_RETURN)
paths enforce. `fn_flags[fi]` bits 3 / 4 / 5; lexer tokens
125 / 126 / 127. **Annotation ramp opt-in per consumer** —
mass-touch across stdlib (lib/keccak.cyr, sigil PQC, AEAD)
not in scope this slot; lands incrementally as consumers
audit. cc5 grew 727,960 → 732,320 B (+4,360 B). New
`tests/tcyr/effect_annotations.tcyr` 7/7. check.sh 64/64.

##### v5.8.21–v5.8.27 — Tagged unions + exhaustive pattern match (+2 cascade at v5.8.22 ship)

Algebraic data types — biggest language-ergonomics addition of
the v5.x line. Every ad-hoc `int tag; union { ... }` struct
pattern across IR walkers, NSS-strategy dispatch, fdlopen
result codes, parser state machines, hashmap key-typing folds
into first-class sum types. **Required by Phase 2's later
slots** (`Result<T,E>` IS a tagged union; `?` operator pattern-
matches it).

- ✅ **v5.8.21** — Sum-type syntax + constructor parsing
  (shipped 2026-05-03). The pinned canonical shape
  `enum Result<T, E> { Ok(T), Err(E) }` now lexes + parses +
  codegens end-to-end. Generic-parameter syntax via
  `SKIP_GENERICS(S)` after the enum name (mirroring
  struct/union); comma variant separators (token 31)
  accepted alongside the legacy `;` (token 5); multi-arg
  variant constructors `Foo(a, b, c)` with arity-scaled
  codegen (8 + 8N alloc, payload[i] at +8 + 8*i, frame size
  `(arity + 1) * 16`). Byte-identical for the arity-1 case
  preserves the v5.5.2 single-arg corpus. Cascaded into the
  slot: directive-token Pass 1 / Pass 2 tolerance fix
  (precondition for v5.8.20's annotation ramp landing) +
  the demo annotation ramp itself (`sys_open/close/read/write`
  `#io`; `u128_eq/u128_is_zero` `#pure`). cc5 +2,272 B
  (732,320 → 734,592). New `tests/tcyr/enum_generics.tcyr`
  31/31 across 9 groups.
- ✅ **v5.8.22** — Exhaustive pattern match in `match`
  (shipped 2026-05-03). Compiler-emitted **warning** (not
  error, per v5.8.x incremental-adoption policy) when a
  `match` over an enum value misses one or more variants
  and has no `_ =>` opt-out. Two bites: (#1) per-variant →
  parent-enum bookkeeping infrastructure — new heap regions
  `var_enum_id[]` (0x204000), `enum_count` (0x214000),
  `enum_variant_count[]` (0x214008), `enum_name[]` (0x214808);
  6 accessor fns in util.cyr; PARSE_ENUM_DEF writes all four
  in pass 1. (#2) PARSE_MATCH coverage check + diagnostic —
  pre-PCMPE peek at each arm's first ident, look up parent
  enum-id; track primary `match_eid`, mixed-enum, default
  flag, covered count; emit "non-exhaustive match over enum
  'X' — covers N of M variants" or "match arms span multiple
  enums" warnings as appropriate. Codegen unchanged
  (metadata-only check; self-host stays byte-identical). cc5
  +2,568 B (734,592 → 737,160). New
  `tests/tcyr/exhaustive_match.tcyr` 10/10 across 3 groups.
  0 false positives during self-host or stdlib compile.
  `cyrius lint --strict` escalation reserved for a follow-up.
- ✅ **v5.8.23** — Stdlib adoption pass 1: `lib/tagged.cyr`
  migration (shipped 2026-05-03). Two bites: (#1) empty-parens
  nullary tagged variant — `Foo()` is now `alloc(8)` tag-only,
  removing v5.8.21's arity-1 collapse landmine. (#2)
  `lib/tagged.cyr` migration — `enum OptionTag` + `fn None()`
  / `fn Some(value)` etc. replaced with compiler-generated
  `enum Option { None(); Some(v); }` / `enum Result { Ok(v);
  Err(e); }` / `enum Either { Left(v); Right(v); }`. Helper
  bodies updated to reference lowercase variant names. cc5
  -48 B (737,160 → 737,112 — collapse removal + EMOVI
  constant-fold on arity-0). All downstream tcyr consumers
  intact: tagged.tcyr 14/14, enum_generics.tcyr 31/31.
  **Honest scope-shrink** at slot entry: pin's hashmap
  `key_type` migration + dynlib + json/toml premise empirically
  partial (json/toml had 0 ad-hoc tag dispatch hits;
  fdlopen 2 hits; hashmap 12 hits — real but pure ergonomic).
  Symlink-corruption ceremony per `lib/` edit (CLAUDE.md
  ecosystem rule) makes per-file migrations costly; hashmap
  key_type migration **deferred to v5.8.26** alongside
  downstream symlink audit. **Bare-name auto-tagging in mixed
  enums** (per pin's prescriptive `enum Option { None; Some(v); }`
  example) deferred — empirical migration uses paren-consistent
  shapes (`None()` not bare `None`) and works cleanly without
  it. **Symlink corruption discovery (this slot)**:
  `/home/macro/Repos/sakshi/lib` is a symlink to
  `~/.cyrius/lib` — exactly the pattern CLAUDE.md warns
  against; mid-bite-2 `lib/tagged.cyr` edits reverted between
  Edit calls via the install-snapshot ping-pong path. Audit
  + cleanup of all downstream cyrius consumer repos
  (sakshi confirmed; mabda / sigil / yukti / kybernet /
  hadara likely affected) queued for v5.8.26.
- ✅ **v5.8.24** — Exhaustive-match table cap bump 256 → 1024
  (shipped 2026-05-03). Single-bite slot. Audit found cyrius
  stdlib at 299 enum decls; downstream vani/yukti/sigil/patra/
  mabda compose to >250 in realistic multi-dep programs;
  empirical 300-enum probe pre-bump correctly fail-fasted via
  the v5.8.22 diagnostic. Cap bump: `SENUMC >= 256` → `>= 1024`;
  `enum_variant_count[]` grew 2KB→8KB at 0x214008;
  `enum_name[]` grew 2KB→8KB and shifted 0x214808 → 0x216008
  (six accessor fns updated). Total metadata-band +12 KB.
  cc5 unchanged at 737,112 B (instruction encoding identical
  for 256 vs 1024 — both fit in 32-bit imm at same length).
  **Honest scope-shrink**: pin's `cyrius vet` 80%-cap pre-warn
  deferred — would need new vet-tool compile-time
  instrumentation; fail-fast diagnostic already gives clear
  error before silent overflow. Earns its own slot if a
  consumer reports the fail-fast surprised them.
- ✅ **v5.8.25** — Exhaustive-match arm-tag dedup (shipped
  2026-05-03). Single-bite slot. PARSE_MATCH stack-allocates
  `seen_vcnt[256]` per match; O(N²) linear scan flags
  duplicate arms with `warning: duplicate match arm 'X'` and
  skips counting toward `match_covered` so non-exhaustive
  math stays accurate. **Dedup keyed by `vcnt`** (variant-var-
  index, unique program-wide) not tag value — avoids the
  v5.5.2 `enum_const_val` 1024-vcnt cap. Codegen unchanged
  (runtime cmp/jcc cascade still picks first matching arm).
  cc5 +776 B (737,112 → 737,888). New
  `tests/tcyr/match_dedup.tcyr` 10/10 locks first-match-wins
  on dup-first / dup-middle / triple-dup. 0 false positives
  in self-host or stdlib compile.
- ✅ **v5.8.26** — Stdlib adoption pass 2 + ecosystem
  hardening (shipped 2026-05-03). Three bites: (#1) CLAUDE.md
  "Snapshot-ping-pong protection" subsection added under the
  ecosystem-rule section — 3-step edit-then-snapshot-refresh
  recipe documented + directory-level `lib` symlink finder
  added to the audit-script block. (#2) `lib/hashmap.cyr`
  key_type migration — `enum KeyType { KeyTypeCstr; KeyTypeStr;
  KeyTypeU64; }` replaces raw 0/1/2 literals at 6 sites (pin
  estimated 12; empirically 6); auto-incremented tags match
  prior raw-int exactly so call shapes unchanged. (#3) Symlink
  audit re-verification — 0 directory-level `lib/` symlinks
  remain (sakshi v5.8.23 fix holds). cc5 unchanged at
  737,888 B (compiler untouched). Migration survived
  `version-bump.sh` snapshot refresh without ping-pong
  reversion — protection-doc workflow validated end-to-end.
  Pre-existing tcyrs intact.
- ✅ **v5.8.27** — Tagged unions sub-suite closeout (shipped
  2026-05-03). Doc-only / verification slot. Sub-suite
  COMPLETE (v5.8.21–v5.8.27, 7 slots, +5,568 B compiler delta,
  51 new tcyr assertions across 3 new tcyrs). Downstream
  pin audit: all 10 consumers (mabda/sigil/yukti/phylax/sakshi/
  vani/patra/cyrius-doom @ 5.7.48; vidya @ 5.8.19; yantra @
  5.6.17) pinned at pre-v5.8.21 cyrius — pin bumps to 5.8.27
  are downstream-repo operations queued for next consumer
  cycle. **Last release in the v5.8.21–v5.8.27 work session**;
  handoff to un-versioned doc/vidya pass per user direction
  2026-05-03 ("doc and vidya pass after not attached to a
  release. As handoff/wrapup"). Sub-suite arc retrospective +
  honest scope-shrink ledger captured in CHANGELOG.

**Acceptance gates**: byte-identical self-host at every patch;
`tests/tcyr/exhaustive_match.tcyr` (missing variant → error;
`_ =>` accepted; new variant triggers diagnostic at every
uncovered site); `cyrius audit` passes with internal-migration-
only changes visible at v5.8.23.

**Out of scope**: GADTs, higher-kinded types, type-level
computation. Keep feature surface boringly orthogonal.

##### v5.8.28–v5.8.32 — `Result<T,E>` + `?` propagation operator (+2 cascade from v5.8.22)

Replaces -1/0/errno convention pervasive in stdlib with
compiler-enforced error handling. Depends on tagged unions
(v5.8.21–v5.8.27). The `?` operator: `var x = foo()?;` short-
circuits on `Err`, unwraps `Ok` — half the LOC of error-
checking code in practice.

- ✅ **v5.8.28** — `Result<T,E>` type in `lib/result.cyr`
  (shipped 2026-05-03). Carved Result + 6 helpers (`is_ok`,
  `is_err_result`, `result_unwrap`, `result_unwrap_or`,
  `err_code_of`, `result_print`) out of `lib/tagged.cyr` into
  the new dedicated module. Typed shape `enum Result<T, E> {
  Ok(v); Err(e); }` using v5.8.21 generic-parameter syntax;
  helpers inline `load64()` so result.cyr has no circular dep
  on tagged.cyr. `lib/tagged.cyr` adds `include "lib/result.cyr"`
  near the top so existing consumers (`lib/net.cyr`,
  `lib/ws_server.cyr`, `lib/sandhi.cyr`, `tests/tcyr/tagged.tcyr`)
  keep working transitively. New `tests/tcyr/result.tcyr` —
  24 assertions across 9 groups (constructors, all 6 helpers,
  payload roundtrip, `match load64(res)` consumer, realistic
  `_safe_div(n, d)` shape). cc5 unchanged at 737,888 B (zero
  compiler delta — pure stdlib reorganization). check.sh
  64/64; self-host two-step byte-identical; tagged tcyr 14/14
  via transitive include. Snapshot-ping-pong fired during
  first check.sh run, recovered per CLAUDE.md mitigation
  recipe. Convenience constructors `Ok(v)` / `Err(e)` and
  pattern-match consumers shipped per pin.
- ✅ **v5.8.29** — `?` propagation operator (shipped 2026-05-03).
  Lex token 124 (standalone `?`, distinct from TS-regex
  `+?`/`-?`/`*?` compounds 115/118/121); parse hook in
  `PARSE_TERM` immediately after the first `PARSE_FACTOR` call;
  emit desugar via existing primitives (`EVSTORE`/`EVLOAD`/
  `ELOAD64`/`EMOVI`/`EMOVCA`/`ECMPR`/`EJCC(0x84)`/`EJMP0`/
  `EPATCH`/`EADDR`) — no new x86 hex literals. Hidden temp var
  holds the Result ptr across tag-check / unwrap branches (same
  idiom as `PARSE_MATCH`'s `midx`). Early-return uses the
  existing fn-epilogue jump table at `0x18DA20`. Highest
  precedence — binds tighter than `*`/`/`. Outside-fn-body `?`
  is a parse-time hard error (`?: '?' propagation operator only
  valid inside a fn body`); the stricter "outside Result-
  returning fn is type error" requires fn return-type tracking
  that doesn't exist yet — pinned for a future slot per honest-
  scope-shrink pattern. cc5 737,888 → 738,856 B (+968 B).
  `tests/tcyr/result_propagation.tcyr` — 29 assertions across
  11 groups (Ok unwrap, Err short-circuit at first/second `?`,
  `return expr?;` shape, `?` in binary-op context, `?` as first
  fn-body stmt, `?` inside `if` body, payload roundtrip
  negatives + zero). check.sh 64/64; self-host two-step byte-
  identical.
- ✅ **v5.8.30** — Stdlib migration pass 1 (shipped 2026-05-03).
  Ships Result-returning `*_r` variants across four stdlib
  modules — `lib/io.cyr`, `lib/json.cyr`, `lib/toml.cyr`,
  `lib/cyml.cyr`. Per-module error enums with module-prefixed
  variant names: `IoError {IoNotFound, IoAccessDenied, IoBadFd,
  IoFailed, IoOther}`, `JsonError {JsonIoErr, JsonParseErr,
  JsonOther}`, `TomlError {TomlIoErr, TomlParseErr, TomlOther}`,
  `CymlError {CymlIoErr, CymlOther}`. lib/io adds the 6 main
  file_*_r fns (open/close/read/write/read_all/write_all)
  mapping the negated kernel errno through `_io_errno_to_iorr`.
  json/toml add `*_parse_file_r` variants surfacing underlying
  file-read failures as `Err(...IoErr)` instead of silent empty
  vecs. cyml gains the brand-new `cyml_parse_file_r` (cyml had
  no prior file-loading helper). `lib/syscalls.cyr` left
  unchanged — it's a thin arch-dispatcher; the migration
  happens at the higher-level lib/io layer instead. Legacy
  int-returning fns stay callable per migration policy. Zero
  compiler delta (cc5 unchanged at 738,856 B). New
  `tests/tcyr/result_stdlib.tcyr` — 29 assertions across 14
  groups. Required mid-slot cross-compiler refresh:
  `build/cc5_aarch64` (May 2) choked on `enum Result<T, E>`
  syntax newly transitively included via `lib/io.cyr`; rebuilt
  from `src/main_aarch64.cyr` via host cc5. check.sh 64/64;
  self-host two-step byte-identical.
- ✅ **v5.8.31** — Stdlib migration pass 2 (shipped 2026-05-03).
  Result-returning `*_r` variants + module-prefixed error enums
  added to 6 of the 7 pin-named modules: lib/http.cyr (HttpError +
  http_get_r), lib/dynlib.cyr (DynlibError + dynlib_open_r /
  dynlib_sym_r), lib/pwd.cyr (PwdError + pwd_getpwuid_r /
  pwd_getpwnam_r), lib/grp.cyr (GrpError + grp_getgrgid_r /
  grp_getgrnam_r / grp_getgrouplist_r), lib/shadow.cyr
  (ShadowError + shadow_getspnam_r), lib/pam.cyr (PamError +
  pam_unix_authenticate_r). **Premise-check finding:** lib/net.cyr
  was already Result-returning (Err(errno) form) from a pre-cycle
  migration — refactor to NetError enum would break payload-
  comparing consumers (ws_server / sandhi); skipped per honest
  scope-shrink. **Bug fix:** lib/http.cyr's http_get treated net.cyr
  Result heap ptrs as raw ints (`var fd = tcp_socket(); if (fd < 0)`
  — heap ptr always positive, guard never fired); replaced with
  is_err_result/payload guards in the lib/sandhi.cyr shape.
  **Compiler fix:** v5.8.29's `?` hook lived only in PARSE_TERM,
  but PARSE_STMT's IDENT+LPAREN dispatch bypasses PARSE_TERM —
  bare `expr?;` statements hit "expected ';', got unknown".
  Replicated `?` desugar inline in PARSE_STMT after PARSE_FNCALL
  (+816 B). cc5 738,856 → 739,672 B (+816 B; the 6 stdlib modules
  ship zero compiler delta). New tests/tcyr/result_stdlib_pass2.tcyr
  — 24 assertions across 12 groups. check.sh 64/64; aarch64 SSH
  gate PASS; self-host two-step byte-identical.
- ✅ **v5.8.32** — Result sub-suite closeout (shipped 2026-05-03).
  Sub-suite COMPLETE (v5.8.28–v5.8.32, 5 slots, +1,784 B compiler
  delta, 106 new tcyr assertions across 4 new tcyrs). Cross-repo
  downstream smoke executed via temporary-pin-bump methodology
  (backup cyrius.cyml + lib/, bump pin to 5.8.31, copy
  v5.8.31/lib/*.cyr over snapshot preserving symlinks, add NEW
  lib/result.cyr, `cyrius build` + run, restore). **Smoke results**:
  sigil 3.0.0 ✅ compile + runtime exit 0; mabda ✅ compile OK;
  yukti ✅ compile OK; ark ⚠ repo not present at
  `/home/macro/Repos/ark/` — flagged for next downstream cycle
  when ark lands. **Static audit pre-dynamic**: 0 enum-variant
  name collisions across all 3 reachable repos (each defines
  module-prefixed enums — SigilError, WGPUBlendOp, DeviceClass —
  none clash with v5.8.30/.31 Io*/Json*/Toml*/Cyml*/Http*/Dynlib*/
  Pwd*/Grp*/Shadow*/Pam* variants); all sub-suite changes additive
  (legacy file_open / json_parse_file / tcp_socket / pwd_getpwuid
  preserved verbatim). **Honest scope-shrink ledger**: lib/net.cyr
  pre-migrated (Err(errno) form; refactor would break
  ws_server/sandhi consumers); strict "?-outside-Result-returning-fn
  type error" enforcement deferred (needs fn return-type tracking).
  **Bonus fix**: doc-audit deletion of docs/benchmarks.md (commit
  62eec00) caught afterwards as breaking ci.yml's required-docs
  check; restored as a stub redirecting readers to
  size-comparisons.md + development/benchmarks.md; original v3.4.15
  content preserved at docs/development/archive/. CLAUDE.md memory
  updated (feedback_archive_dont_delete_docs.md). **Methodology
  pinned for future closeouts**: `cyrius deps` does NOT refresh
  cyrius-side stdlib snapshots — only `[deps.*]`-declared packages.
  Cross-version smoke needs the manual lib/ overlay step. cc5
  unchanged at 739,672 B. check.sh 64/64; self-host two-step
  byte-identical.

**Acceptance gates**: byte-identical self-host every patch;
`tests/tcyr/result_propagation.tcyr` (`?` on `Err` short-
circuits, on `Ok` unwraps, outside Result-returning fn is type
error); cross-repo smoke at v5.8.31.

**Migration policy**: modules migrate one at a time. `-1`-
return fns stay callable from non-migrated call sites through
v5.8.x. v6.0.0 closeout fully removes the old convention.

##### v5.8.33–v5.8.38 — Allocators-as-parameter convention (+2 cascade from v5.8.22)

Largest ecosystem-churn item; biggest modern-systems-language
insight (Zig's contribution). Every allocating fn takes an
`Allocator`; global `alloc_init()` singleton retires; per-
request arenas fall out naturally; failing-allocator test
harness becomes a one-liner. Slotted last in Phase 2 because
it ripples through every stdlib module that allocates — having
sum types + Result already in means the migration uses
`Result<T, AllocError>` for failure returns (cleaner than
doing it before Result lands).

- ✅ **v5.8.33** — Allocator vtable interface (shipped 2026-05-03).
  40-byte / 5-slot Allocator layout (alloc_fn / realloc_fn /
  free_fn / reset_fn / state). 3 default impls: `bump_allocator()`
  wraps the global bump (state=0; free=no-op; reset=alloc_reset
  GLOBAL — use carefully); `arena_allocator(cap)` wraps a fresh
  arena (state=arena ptr; reset clears only this arena);
  `test_allocator()` tracks alloc_count / bytes_total / fail_after
  threshold for the v5.8.34 OOM harness (state=24 B counter
  struct). Dispatch helpers `alloc_via(a, size)` /
  `realloc_via(a, p, oldsz, newsz)` / `free_via(a, p)` /
  `reset_via(a)` call through the vtable via fncall1/fncall2/
  fncall4. Vtable accessors `allocator_alloc_fn` /
  `allocator_realloc_fn` / `allocator_free_fn` /
  `allocator_reset_fn` / `allocator_state`. test_allocator extras:
  `test_allocator_fail_after(a, n)` (-1 = never), 
  `test_allocator_alloc_count(a)`, `test_allocator_bytes_total(a)`.
  cc5 unchanged at 739,672 B (zero compiler delta — pure stdlib
  addition). New `tests/tcyr/alloc_iface.tcyr` — 43 assertions
  across 12 groups. check.sh 64/64; self-host two-step
  byte-identical. **Doc-coverage gate caught 8 undocumented
  public fns** on first check.sh run (5 accessors + 3
  constructors); fixed inline per `cyrdoc --check` convention.
- ✅ **v5.8.34** — Failing-allocator test harness (shipped 2026-05-03).
  `lib/assert.cyr` gains `include "lib/alloc.cyr"` (transitive
  for test consumers) + `fn fail_after_n_allocs(n)` — a thin
  wrapper over v5.8.33's `test_allocator()` +
  `test_allocator_fail_after()`. Returns an Allocator configured
  to fail after `n` successful `alloc_via` calls (n=0 fails every
  alloc; n=-1 never fails). New `tests/tcyr/oom_handling.tcyr` —
  33 assertions across 9 groups covering thresholds 0/1/3,
  alloc_count tracking through failures, bytes_total accumulation,
  reset_via behavior, consumer-pattern fallback (rc=0 primary OOM /
  rc=1 backup OOM / rc=2 both OK), vtable sanity. cc5 unchanged
  at 739,672 B (zero compiler delta). check.sh 64/64; self-host
  two-step byte-identical. Doc-coverage gate clean on first run
  (v5.8.33 lesson stuck). Foundation for v5.8.35-37 stdlib
  migration's OOM tcyrs.
- ✅ **v5.8.35** — Stdlib Allocator migration pass 1 (shipped
  2026-05-03). 10 new `_a` variants threading Allocator as
  first arg through vec / str / hashmap. lib/alloc.cyr gains
  `default_alloc()` lazy-init singleton (returns the same
  bump_allocator() Allocator on every call). lib/vec.cyr:
  `vec_new_a(a)` returns 0 on OOM; `vec_push_a(a, v, val)`
  returns -1 on grow OOM (vs. back-compat vec_push aborts).
  lib/str.cyr: `str_from_a` / `str_new_a` / `str_cat_a` /
  `str_clone_a` / `str_from_int_a` all return 0 on OOM (Str-
  typed sentinel). lib/hashmap.cyr: `map_new_a` /
  `map_new_str_a` / `_map_grow_a` / `map_set_a` — map_set_a
  returns -1 on grow OOM. Back-compat wrappers preserved
  byte-identically. (map_u64_new / map_u64_set / str_split /
  str_trim deferred to v5.8.36 with json/toml/cyml/http/sandhi.)
  New tests/tcyr/alloc_stdlib.tcyr — 33 assertions across 14
  groups (back-compat, bump/arena/test dispatch, OOM behavior,
  default_alloc singleton). cc5 unchanged at 739,672 B (zero
  compiler delta). check.sh 64/64; self-host two-step
  byte-identical. Doc-coverage gate caught 1 undocumented
  public fn (map_new_str lost its leading comment when _a
  variant was inserted); fixed inline.
- ✅ **v5.8.36** — Stdlib Allocator migration pass 2 (shipped
  2026-05-03). 17 new `_a` variants across the peripheral modules:
  lib/json.cyr (12 — _jv_alloc_a + 5 leaf v_*_new_a + v_arr_new_a +
  v_obj_new_a + _jv_pair_new_a + json_v_arr_push_a +
  json_pair_new_a; arr/obj constructors use vec_new_a internally so
  inner vec also lives in arena); lib/toml.cyr (toml_section_new_a +
  toml_pair_new_a); lib/cyml.cyr (cyml_entry_new_a + cyml_doc_new_a);
  lib/http.cyr partial migration (http_get_a routes the 64KB recv
  buffer + 32B response struct + early-return error responses through
  the supplied allocator; URL parsing + request-build buffers stay
  on default_alloc — smaller, bounded, shared between requests in
  the typical per-request-arena pattern; documented).
  **lib/sandhi.cyr deferred** — auto-generated bundle from sandhi
  distrepo via `cyrius distlib`; migration requires upstream sandhi
  changes + re-bundling. Pinned for next sandhi distlib refresh.
  cc5 unchanged at 739,672 B (zero compiler delta). New
  tests/tcyr/alloc_stdlib_pass2.tcyr — 30 assertions across 10
  groups. check.sh 64/64; self-host two-step byte-identical.
  **Lint gate caught 2 long-line warnings** in http.cyr (one-liner
  if-blocks exceeded 120 cols); reformatted before bump.
- ✅ **v5.8.37** — Retire `alloc_init()` global singleton (shipped
  2026-05-03). Honest interpretation: alloc_init() itself stays
  callable, but the REQUIREMENT to call it before any alloc() is
  retired via lazy-init. `if (_heap_base == 0) { alloc_init(); }`
  guard added to alloc() in lib/alloc.cyr (Linux) +
  lib/alloc_macos.cyr (macOS) + lib/alloc_windows.cyr (Windows).
  Pre-v5.8.37 every consumer had to call alloc_init() at top-level;
  new code can omit. Existing code keeps working — explicit
  alloc_init() is now a re-callable shim that re-brk's the heap
  (same multiple-call contract as pre-v5.8.37). default_alloc()
  (v5.8.35 lazy-init singleton) is the modern entry point. cc5
  unchanged at 739,672 B (zero compiler delta). New
  tests/tcyr/alloc_no_init.tcyr — 17 assertions across 8 groups
  deliberately omitting top-level alloc_init() (direct alloc,
  multiple distinct ptrs, alloc_via via default_alloc, arena_new,
  explicit alloc_init post-lazy-init, vec/str/hashmap). check.sh
  64/64; self-host two-step byte-identical. **Migration policy**:
  v6.0.0 closeout sweeps explicit alloc_init() calls out of
  consumers; only then can the fn itself retire. **Sandhi-side
  proposal handed off** —
  `sandhi/docs/proposals/2026-05-03-allocator-migration.md` filed
  for parallel agent work targeting sandhi v1.1.0 (6-batch
  bottom-up migration of 27 files / ~135 alloc sites; per-batch
  acceptance gates; process notes from v5.8.33-36 lessons).
- ✅ **v5.8.38** — Allocators sub-suite closeout (shipped 2026-05-03).
  Sub-suite COMPLETE (v5.8.33–v5.8.38, 6 slots, +0 B compiler
  delta, 156 new tcyr assertions across 4 new tcyrs). **Phase 2
  COMPLETE** — both sub-suites done (Result+? at +1,784 B,
  Allocators at +0 B). Cross-repo downstream smoke via temp-pin-
  bump methodology (pinned at v5.8.32; reused cleanly here):
  sigil 3.0.0 ✅ (compile OK; runtime exit 4 matches v5.7.48
  baseline — sigil's smoke is non-zero by design, not a
  regression); mabda ✅ (compile OK); yukti ✅ (compile OK);
  ark 0.8.0 ✅ (5.1.10 → 5.8.37 → 5.1.10; compile OK; runtime
  exit 0 matches baseline — ark's pin was 7 minors old,
  validating back-compat from a long-stale caller). **Static
  audit**: 0 collisions across all 4 reachable repos for every
  v5.8.33-37 symbol (bump/arena/test_
  allocator, alloc_via et al, default_alloc, fail_after_n_allocs,
  all 30 `_a` variants). **Allocator-API adoption tracking**:
  0 of 47 downstream alloc_init() call sites migrated yet
  (per migration policy opt-in; lazy-init in v5.8.37 keeps
  existing calls working unchanged). **Acceptance-gate audit**:
  byte-identical self-host every patch ✅; oom_vec_push.tcyr
  Err(OutOfMemory) gate ⚠ partial — vec_push_a returns -1 not
  Err (back-compat shape preserved; v6.0.0 closeout removes
  legacy wrapper and ships full Result-typed OOM); compiler-
  internal explicit Allocator ⚠ partial (cc5's src/ uses global
  bump; pinned for v6.0.0 sweep). **Honest scope-shrink ledger**:
  sandhi deferred (handed off to parallel agent for v1.1.0 —
  `sandhi/docs/proposals/2026-05-03-allocator-migration.md`);
  str_split / str_trim / str_builder_new and map_u64_* not
  migrated (transitive arena routing via default_alloc works);
  http_get_a partial migration; alloc_init() retirement is
  requirement-only. **Process note**: sigil smoke baseline check
  before claiming regression (first v5.8.37 sigil smoke returned
  exit 4 → restored to v5.7.48 baseline pin reproduced exit 4 →
  sigil's smoke is non-zero by design, not a v5.8.37 regression).
  Lesson: baseline FIRST when smoking against a downstream
  pinned baseline. cc5 unchanged at 739,672 B. check.sh 64/64
  (intermittent flicker to 63/64 on first run, second run clean).

**Acceptance gates**: byte-identical self-host every patch;
`tests/tcyr/oom_vec_push.tcyr` (`vec_push` returns
`Err(OutOfMemory)` under `fail_after_n_allocs(1)`) at
v5.8.34; every internal compiler path uses explicit allocator
at v5.8.37.

**Migration policy**: allocator parameter is opt-in during
v5.8.x. Default-allocator wrapper preserves existing
`vec_push(v, x)` shape as `vec_push(default_alloc(), v, x)`
syntactic sugar. v6.0.0 closeout removes the shim — every
fn requires explicit allocator.

#### Phase 3 — Polish + cycle closeout (+2 cascade from v5.8.22)

- ✅ **v5.8.40** — Preprocessor string-literal awareness (shipped
  2026-05-03; cascaded from v5.8.39 by sandhi re-slot). Closes
  the v5.7.49-vidya-audit-filed issue at
  `docs/development/issues/2026-05-01-preprocessor-include-pattern-
  in-string-literals.md`. PP_PASS + PP_IFDEF_PASS in
  src/frontend/lex_pp.cyr now track `"`-bounded string-literal
  state via in_string + escape_next flags; the
  `if (bol == 1)` directive-detection block is gated on
  `&& in_string == 0`. Mirrors the v5.7.36 cyrlint string-literal
  awareness fix shape. cc5 739,672 → 740,312 B (+640 B; 320 B
  per pass). Vidya entry at content/cyrius/ecosystem.cyml:685-720
  flipped from "pinned for v5.8.x" → "✅ FIXED in v5.8.40";
  workaround text kept for pre-v5.8.40 toolchain users; cross-ref
  to canonical issue file maintained per v5.7.49 audit policy.
  New tests/tcyr/preprocessor_string_literal.tcyr — 12 assertions
  across 5 groups. check.sh 64/64; self-host two-step
  byte-identical.

- ✅ **v5.8.41** — cyrlint large-file false-positive verification slot
  (shipped 2026-05-03). Pin originally targeted "cyrlint multi-line
  assert false-positive (mabda C5)" — mabda's re-bisection at filing
  (Step 3e) had revised the diagnosis to FILE-SIZE THRESHOLD
  ~3270 lines emitting false-positive "unclosed braces at end of
  file" + "trailing whitespace" warnings. **Premise check at v5.8.41
  entry across 4 synthetic repros found the bug NOT reproducing**
  at v5.8.40: 3504-line plain-vars file, mabda's actual mabda.tcyr
  at 2743 lines, doubled mabda content at 5486 lines, 9007-line
  synthetic with 600 fns + multi-line assert_eq + comments — all 0
  warnings. Cyrius git log shows multiple "fixing linter" commits
  between v5.7.23 filing and v5.8.40; probable resolution
  candidates: v5.7.36 string-literal awareness fix, later
  brace-tracker refactor, v5.8.40 preprocessor string-literal
  awareness as secondary protection. Per user direction at slot
  entry: ship as verification slot; if mabda hits a new variant
  they file a NEW issue with fresh repro + repo location.
  **Deliverable**: new tests/regression-cyrlint-large-file.sh
  generates a 7010-line synthetic matching mabda's repro shape
  (700 fns each with test_group + multi-line assert_eq + brace-
  block body + comments), runs cyrlint, asserts 0 "unclosed braces"
  / 0 "trailing whitespace" warnings. Wired into check.sh as
  section 4an2 alongside the existing v5.7.32 cyrlint global-init-
  order gate. mabda issue annotated as ✅ RESOLVED in cyrius
  v5.8.41 with premise-check methodology + 4-repro evidence +
  regression-floor pointer. cc5 unchanged at 740,312 B (zero
  compiler delta). check.sh 65/65 (gate count +1). Self-host
  two-step byte-identical.

- ✅ **v5.8.42** — Paired UX/diagnostic polish (shipped 2026-05-03;
  mabda A2 + C1, combined per pin). **Half (a) cyrius fmt --check
  exit code** (mabda A2): cbt's cmd_fmt invoked
  `cyrfmt <file> --check` but cyrfmt parses --check only at argv(1);
  with file at argv(1), _check_mode stayed 0, cyrfmt fell through
  to format-to-stdout, exit 0 regardless of drift. Drift detection
  silently broken via cbt wrapper. Fix: swap run_tool args to put
  --check FIRST. Matches Rust/Go: silent on no-drift, exit
  non-zero on drift. cbt-only edit, zero compiler delta. **Half (b)
  var X; bare-decl diag** (mabda C1): two ERR_EXPECT(S, 4) sites
  in parse_decl.cyr (PARSE_VAR line 953; EMIT_GVAR_INITS line 594)
  emitted generic "expected '=', got ';'" for the bare-decl shape.
  Fix: special-case the `;` token — emit specific "uninitialized
  variable not allowed; use `var X = 0;` or initial value". Other
  missing-= cases (e.g. `var x 42;`) keep generic ERR_EXPECT path.
  cc5 740,312 → 740,528 B (+216 B; entirely from half b's
  diagnostic improvement). check.sh 65/65; self-host two-step
  byte-identical. Manual smoke clean across all paths.

- **v5.8.42-orig (superseded)** — Paired UX/diagnostic polish: `cyrius fmt
  --check` exit-code semantics (mabda A2; match Rust/Go —
  exit non-zero on drift, silent on no-drift) + `var X;`
  bare-decl error-message polish (mabda C1; current "expected
  expression after `=`" → "uninitialized variable not allowed;
  use `var X = 0;` or initial value").

- ✅ **v5.8.43** — Phase 3 polish absorber: stdlib Allocator
  migration pass 3 (peripheral cleanup) (shipped 2026-05-03).
  Absorbs the deferred-from-v5.8.35 + v5.8.36 peripheral `_a`
  variants. **lib/str.cyr** gains 9 new fns (str_sub_a /
  str_trim_a / str_split_a + str_builder_new_a + _sb_grow_a
  internal + str_builder_add_a / add_cstr_a / add_int_a /
  build_a); **lib/hashmap.cyr** gains 3 (_map_u64_grow_a internal
  + map_u64_new_a / map_u64_set_a). Migration now at ~100%
  stdlib coverage: 45 `_a` variants + 10 typed-error enums
  across 11 stdlib modules. Unblocks sandhi v1.1.0
  dup-elimination work (sandhi's `_sandhi_client_host_header_a`
  / `_sandhi_wd_session_url_a` / `sandhi_json_build_a` use the
  global bump + dup pattern because v5.8.36 stdlib lacked
  str_builder_*_a; v5.8.43 ships those variants — sandhi-side
  follow-up at v1.1.x or v1.2.0). cc5 unchanged at 740,528 B
  (zero compiler delta — pure stdlib addition). New
  tests/tcyr/alloc_stdlib_pass3.tcyr — 33 assertions across 11
  groups. **Surfaced bug filed**: `str_split` pre-existing —
  sep treated as ptr at impl level despite Str API annotation;
  always returns 1 part regardless of separator. Affects
  lib/process.cyr:214 cmdline parsing. Filed at
  `docs/development/issues/2026-05-03-str-split-sep-treated-as-
  pointer.md` for separate slot; out of scope for absorber.
  v5.8.43 str_split_a preserves the broken behavior end-to-end;
  tcyr assertions reflect actual state so the floor catches the
  fix when it lands. check.sh 65/65; self-host two-step
  byte-identical.

- ✅ **v5.8.44** — api-surface refresh + auto-build wiring +
  null-byte-in-shell-substitution fix (shipped 2026-05-03).
  Pinned 2026-05-02 at v5.8.18 ship; shifted v5.8.42 → v5.8.44
  by the v5.8.22 +2 cascade. Three-part deliverable shipped
  per the original spec — see CHANGELOG for the full repro/fix
  details. Headline outcomes: (a) check.sh now build-on-demands
  cyrius_api_surface if missing (mirrors cyrfmt/cyrlint
  fallback pattern); (b) off-by-one 66→65 length literal at
  api_surface.cyr lines 337+350 (BREAKING-report header was
  including cstring's trailing \0 in syscall length, producing
  the "command substitution: ignored null byte in input" shell
  warnings); (c) snapshot regen 2563 → 2750 entries (+187)
  reflecting v5.7.x→v5.8.x stdlib growth. Gate now real PASS
  not silent skip; 0 null-byte warnings; all 3 test cases
  green. cc5 unchanged at 740,528 B (zero compiler delta —
  tool fix + wiring + snapshot regen). check.sh 65/65; self-
  host two-step byte-identical. **Surface-during-cycle finding
  noted in CHANGELOG**: off-by-one byte counts in
  `syscall(SYS_WRITE, 2, "literal", N)` sites are a recurring
  foot-gun without compile-time `sizeof("...")`. Surface a
  `strlen_const("...")` helper proposal during v5.8.49 closeout
  refactor pass if it bites again. Three-part deliverable:

  1. **`cyrius_api_surface` binary auto-build wiring.** The
     binary is in `cyrius.cyml`'s `bins = [...]` list but the
     CI/release pipeline doesn't build it on `sh scripts/check.sh`
     paths, so `tests/regression-api-surface.sh` has been silently
     skipping with `skip: build/cyrius_api_surface not built`
     since v5.7.50. Fix: include the build in the same path that
     builds cc5/cyrlint/cyrfmt/cyrdoc, OR teach the gate to
     compile-on-demand from `programs/api_surface.cyr`.

  2. **Snapshot regeneration.** `docs/api-surface.snapshot` was
     last refreshed 2026-04-29 at 2563 entries. Current code has:
     additions (slice helpers from §6-§10 — `_slice_idx_get_W`,
     `slice_unchecked_get_W`, `sys_read_slice`, `slice_copy_bytes`,
     `slice_eq_bytes`, etc.); some agnosys removals (e.g.
     `bootloader_config_*` family). Regen via `cyrius
     api-surface --update`.

  3. **Null-byte-in-shell-substitution fix.** The gate's three
     test cases produce `command substitution: ignored null
     byte in input` warnings on the synthetic-snapshot tests
     (lines 54 + 71 of `tests/regression-api-surface.sh`). Root
     cause is the tool emitting null bytes in some failure
     paths that survive the shell capture; either the tool's
     emit path needs trimming or the shell capture needs
     `tr -d '\\0'` filtering. Pre-existing — noted in the
     v5.7.50 P(-1) audit as deferred.

  Acceptance gate: `tests/regression-api-surface.sh` returns 0
  with all three test cases green and zero null-byte warnings;
  `sh scripts/check.sh` shows api-surface gate as PASS not skip.

- ✅ **v5.8.45** — `kernel` reserved-word misleading diagnostic
  (shipped 2026-05-03; filed 2026-05-03 from vidya audio_dsp
  11-lang port at
  `docs/development/issues/2026-05-03-kernel-reserved-word-misleading-diagnostic.md`).
  **Severity: Medium** (silent miscompile of error reporter —
  correct code paths work, but `kernel` as a fn parameter name
  fires `expected identifier, got unknown` at an unrelated
  earlier function in the same file, making bugs extremely hard
  to bisect). Two-part deliverable:
  1. Investigate where `kernel` collides — likely the lexer
     keyword table OR a parser-level sentinel value. Bisection
     candidates: `weights` / `bias` / `tensor` / `layer`
     (other potentially-reserved DSP/ML names; the issue file
     notes these weren't bisected and may have the same bug
     shape).
  2. Fix per the issue's preferred path: allow `kernel` as a
     normal identifier (it's a common DSP/graphics/AI name).
     Fallback: emit a specific diagnostic at the declaration
     site (`error: 'kernel' is a reserved identifier; please
     rename`) so the error reporter doesn't drift to a
     downstream innocent line.
  Acceptance gate: tcyr that declares `fn f(kernel) {...}` and
  parses cleanly OR errors with a specific reserved-name
  diagnostic at the right line. Bisection-sweep results for
  the other DSP/ML names captured in the slot's CHANGELOG.

- ✅ **v5.8.46** — Arithmetic-in-fn-args regression-floor lock +
  vidya cleanup AND token-array cap raised 262144 → 1048576
  (sit v0.7.2 unblocked) (shipped 2026-05-03). Two coherent
  deliverables landed in the same slot. **Part A** closes the
  v5.8.34-filed arithmetic-in-fn-args pin (vidya audio_dsp
  11-lang port; archived
  `docs/development/issues/archived/2026-05-03-arithmetic-in-fn-args-rejected.md`)
  as a regression-floor lock — parser fix landed earlier in the
  cycle as a side-effect of expression-grammar work
  (`lib/assert.cyr:11` already comment-noted "Now that
  comparisons work in function arguments, assert(x == 42, 'name')
  works"), but neither issue nor vidya field-note
  `no_comparisons_in_fn_args` was refreshed until this slot's
  audit. **Premise-check method**: revert the consumer workaround
  in `vidya/content/audio_dsp/cyrius.cyr` and recompile against
  unmodified cyrius — 17/17 audio_dsp tests pass. Part-A
  deliverables: new `tests/tcyr/expr_in_fn_args.tcyr` (30
  assertions × all 18 operator shapes × operand-source mix ×
  arg-position variation + biquad inline repro); vidya
  audio_dsp port restored to inline form + missing
  `lib/syscalls.cyr` / `lib/vec.cyr` includes added (port had
  been silently broken at compile time independent of the
  arithmetic bug); vidya field-note flipped to ✅ FIXED with
  workaround preserved for pre-v5.8.46 toolchain users. **Part
  B** closes the 2026-04-25-filed sit cap-overflow issue
  (sit-side
  `docs/development/issues/archived/2026-04-25-cyrius-fixup-table-cap.md`,
  mirrored to cyrius archived/) — surfaced mid-slot when the
  user named the sit issue file. Originally framed as
  fixup-table overflow but v5.8.45 retest's `error: token limit
  exceeded (262144)` came from a separate cap site —
  `lex.cyr:95` ADDTOK, not the fixup table (fixup caps had
  moved 32K → 262K → 1M in v5.7.1/v5.7.7; ADDTOK hadn't moved
  since pre-v5.7.1). Part-B sub-deliverables per the issue's
  preferred path: (B.1) ADDTOK diagnostic upgraded to print
  `needed M, cap is N` (REQUIRED before the cap bump per the
  issue's "Step 1"); (B.2) cap raise 4× to 1048576 + token
  arrays relocated from the 0x94A000/0xD4A000/0xF4A000 trio
  (each 2 MiB; tok_types overlapped with output_buf at 0x94A000
  — undocumented v3.6.2 recycling) to a fresh post-TS-region
  high block at 0x368C000/0x3E8C000/0x468C000 (each 8 MiB);
  brk extended in every main_*.cyr; main_win.cyr MMAP raised
  0x2000000 → 0x5000000. cc5 740,528 → **741,040 B** (+512 from
  v5.8.45's `_TOK_IS_KERNEL(S)` inheritance + Part B's PRNUM
  call sequence + relocated-offset literals; Part A added zero
  compiler bytes). Self-host two-step byte-identical.
  **Premise-check method memo** (folded into existing memory
  pin `feedback_premise_check_at_slot_entry`): revert the
  consumer workaround in the filing repo, recompile against
  unmodified cyrius — synthetic minimal programs miss
  shape-dependent bugs. Surfaced first in Part A and applied
  immediately in Part B — same lesson, two consecutive
  applications in one slot. **Slot-scope note**: Part B was
  added to v5.8.46 (rather than cut as a fresh v5.8.47) because
  v5.8.46 hadn't shipped yet — same fold-in pattern as
  v5.8.45's `kernel_ident.tcyr` correction. The
  originally-pinned v5.8.47 starship/vidya-audit slot stays at
  v5.8.47 (not yet shipped, not displaced). **Stale-pin
  streak**: 2 consecutive (v5.8.45 + v5.8.46-Part-A) + 3 total
  in v5.8.x cycle, but Part B ships actual consumer-unblocking
  work in the same slot freeing vidya, yantra, hoosh, ifran,
  daimon, mela, ark, sit. Verification: 30/30 expr_in_fn_args
  pass; CI-shape pipefail loop on 123 tcyr = 123 passed;
  cyrius `scripts/check.sh` 65/65 PASS; vidya audio_dsp port =
  17/17 + zero warnings against the post-v5.8.46 cyrius lib;
  **sit v0.7.2 builds (1,283,232-byte binary; was parked at
  v0.7.1's ~709 KB) + sit `cyrius test` 127/127 PASS** — the
  canonical end-to-end gate for Part B. Pin candidates queued:
  (a) cap-overflow diagnostics should include source file +
  line so future cap-site drift is unambiguous (v5.8.50
  closeout); (b) heap-map comments should be re-validated
  against actual code at every minor closeout — the
  tok_types-vs-output_buf overlap was a v3.6.2-era recycling
  pattern that the comments never caught up to.

- ✅ **v5.8.47** — starship + p10k prompt color split AND vidya
  cyrius-language audit (shipped 2026-05-03). Two-part slot per
  the original pin. **Part A** (starship/p10k color refresh):
  edited `scripts/cyriusly`'s `_CYRIUS_STARSHIP` +
  `_CYRIUS_P10K` heredocs — package side (ॐ Om) → forestgreen
  `#228B22` TEXT; toolchain side (🌀 cyclone) → light blue
  `#87CEEB` TEXT (color on the text, not the background;
  first-pass attempt put it on bg, corrected after user
  feedback "not the background the text"). p10k uses 256-color
  fg codes -f 28/-f 117 for the same split. Pre-fix both
  shared `bg:teal` / `fg:base` and visually collapsed. Acceptance gate run:
  `scripts/cyriusly cmdtools install starship` re-installed
  cleanly via the existing purge-then-write path; both
  segments now render in distinct colors. **Part B** (vidya
  audit): swept ~20K lines across 33 cyml files. **3 entries
  flipped to ✅ FIXED** (`global_init_order_silent_zero`
  v5.7.32, `no_var_redecl_same_scope` v5.8.x,
  `multi_line_struct_enum_bodies_dont_parse` v5.8.x — all
  FIXED-by-side-effect of v5.8.x parser/expression-grammar
  work). **3 entries refreshed** for stale cap/version refs
  (`the_gvar_wall` 256→1024 entries, `the_256kb_ceiling`
  256K→2M output_buf at v5.6.43, `the_preprocessed_line_number_problem`
  still-active confirmation). **1 new local issue filed** at
  `docs/development/issues/2026-05-03-parser-cosmetic-limits-bare-return-and-var-bracket.md`
  for two confirmed-still-active parser cosmetic limits;
  vidya entries cross-referenced. cc5 unchanged at 741,040 B
  (no compiler change). **Stale-pin streak now 4 of 6 in
  v5.8.x cycle** (v5.8.45 4-of-5, v5.8.46-Part-A 18-of-18,
  v5.8.47 3-of-6); pinned for v5.8.48 — parser-grammar slots
  should grep vidya field_notes/language/ for FIXED-by-side-
  effect entries before declaring scope.

- **v5.8.48** ✅ SHIPPED 2026-05-04 — P(-1) audit + alloc tcyr
  rename + CHANGELOG `## [Unreleased]` anchor restoration.

  **Honest scope-shift note:** the originally-pinned scope
  (refactor pass + heap-map deep audit + dead-code-removal
  attempt) was NOT what shipped. User opened the slot with a
  P(-1) audit request; mid-audit the temporal `_passN` test
  names surfaced as a 20-yr-QA pet peeve and the rename became
  the slot's main user-facing deliverable. The refactor pass on
  Phase 2's 30 `_a` variants + v5.8.30/.31 `_r` variants did
  not happen. Per user direction at slot close ("cascade
  remaining; .49 picks up the remaining .48 work"), the
  unfinished refactor / heap-deep-audit / dead-code-removal
  work cascades to v5.8.49. **Premise-check failed** — should
  have read this roadmap pin before declaring the audit
  findings done; flagged for v5.8.x cycle retrospective.

  What actually shipped:
  - alloc_stdlib*.tcyr → topical names (alloc_collections /
    alloc_serdes / alloc_str_extras); git mv preserves blame;
    file headers rewritten with original-name + landing-version
    breadcrumbs.
  - `## [Unreleased]` anchor restored above latest version in
    `CHANGELOG.md` so `version-bump.sh`'s sed insertion stops
    silently no-op'ing (silent miss caught at v5.8.48 bump
    itself; VERSION/CLAUDE.md/install.sh/snapshot/version_str.cyr
    all updated correctly, only CHANGELOG was missed).
  - P(-1) audit baseline recorded: cc5 = 741,040 B
    byte-identical self-host; check.sh 65/65; heapmap.sh 84
    regions / 0 overlaps / 0 warnings; cyrius bench 15/15;
    dead-code floor = 36 unreachable fns / 22,571 B (all
    mode-dispatched TS_*/macho_*/IR cross-arch — NOT removable
    per the dead-code-audit-scope memory pin).
  - Discipline pin saved to memory:
    `feedback_no_temporal_test_names`.

### v5.8.x — Unicode 17.0.0 fold (v5.8.49 → v5.8.52)

Pinned 2026-05-03 at v5.8.45 ship per user direction
("we will make 5.8.55 the new backstop and we will want to
finally add in UNICODE support"). v5.8.x will be the longest
minor in cyrius history (55 patches, ~36 days). Justification:
the work fits the existing cycle structurally — it's stdlib
expansion, not language-feature change — and starting v5.9.0
with half-built Unicode infrastructure would force premature
v5.9.x cycle planning. Better to let v5.8.x absorb the full
Unicode fold and ship v5.9.0 with niyama regex stdlib + bare-
metal AGNOS arc (per existing pin).

**Slot numbers shifted forward 2026-05-04** (originally pinned
.52-.55, then briefly .50-.53 mid-shuffle) so:
1. Closeout sits at the actual cycle backstop (.55) rather
   than mid-cycle ahead of new feature work — closeout =
   last patch of current minor per CLAUDE.md.
2. The cascaded v5.8.48 closeout-prep refactor pass sits
   immediately BEFORE closeout (at .53), where audits
   structurally belong — clean tree feeds a clean closeout.
3. Unicode work starts at .49 (now), not deferred behind the
   audit/refactor.

Reference: https://www.unicode.org/versions/Unicode17.0.0/.
Unicode 17.0 (released 2025-09-09) adds 4,803 characters →
total 159,801 graphemes. Cyrius's v5.7.13 string-literal UTF-8
encoder at `lib/string.cyr` already handles bytes-and-encode;
this fold adds the missing **categorization + normalization +
case-folding** infrastructure that consumer regex (niyama),
fmt rendering (sigil), and TUI clipping (mabda) currently
hand-roll incompletely.

- **v5.8.49** ✅ SHIPPED 2026-05-04 — Unicode 17.0.0 character
  categories + general-category lookup.

  Delivered:
  - `lib/unicode/categories.cyr` — public surface (first stdlib
    subdirectory). GeneralCategory enum (30 leaf categories,
    indexed 0..29) + `unicode_category(cp)` binary-search
    lookup over 4144 sorted ranges.
  - `lib/unicode/_categories_data.cyr` — auto-generated; 9
    string-literal pieces × 500 ranges; 58 016 hex chars total
    encoding (3-byte u24 start + 3-byte u24 end inclusive +
    1-byte category, hex-pair printable encoding for
    lexer-safety).
  - `scripts/gen-unicode-data.py` — build-time codegen
    (committed; runs offline on Unicode revision bumps; first
    Python script in scripts/).
  - `tests/tcyr/unicode_categories.tcyr` — 60 assertions
    across 11 verification categories (ASCII / Latin / Greek /
    Cyrillic / Hebrew / Arabic / CJK / Hangul / Devanagari /
    punctuation dispatch / supplementary planes / surrogate +
    noncharacter Cs/Cn / out-of-range sentinels / Private Use
    Area). Auto-discovered by check.sh.
  - cc5 unchanged at 741,040 B (Unicode is stdlib, only loaded
    by consumers).

  Follow-ups carried into v5.8.50:
  - `install.sh --refresh-only` doesn't recursively traverse
    `lib/<subdir>/*.cyr`; manual mirror to
    `~/.cyrius/versions/<v>/lib/unicode/` was required at
    bump. v5.8.50 adds the second file under `lib/unicode/`
    (casefold.cyr) — fixing the script's lib glob is in scope
    there.

- **v5.8.50** ✅ SHIPPED 2026-05-04 — Unicode 17.0.0 case folding
  (simple + full).

  Delivered:
  - `lib/unicode/casefold.cyr` — 5 public fns: `unicode_to_upper`
    / `unicode_to_lower` / `unicode_to_title` (simple 1:1),
    `unicode_fold(cp, out_buf, cap)` (full 1:n → 1..3 cps),
    `str_lower_unicode(s)` / `str_upper_unicode(s)` (Str-typed
    UTF-8 walkers).
  - `lib/unicode/_decode.cyr` — extracted shared hex decoders
    (`_uc_hex1` / `_uc_hex2` / `_uc_u24`) so categories.cyr +
    casefold.cyr share the encoding without duplication.
  - `lib/unicode/_casefold_data.cyr` — auto-generated; 4 tables
    (1505 simple upper / 1488 simple lower / 1509 simple title /
    1585 full fold) across 18 string-literal pieces.
  - `scripts/gen-unicode-data.py` extended — single offline
    invocation now regenerates both categories + casefold data.
  - `tests/tcyr/unicode_casefold.tcyr` — 70 assertions across
    9 verification categories (ASCII / Latin / Greek+Cyrillic /
    titlecase Lt / no-mapping / one-to-many full fold / identity
    fold / out-of-range / Str wrappers).
  - `cyrius.cyml [deps] stdlib` updated with 3 new entries.
  - cc5 unchanged at 741,040 B.

  Pin deviation:
  - Pin specified wiring `str_lower_unicode` / `str_upper_unicode`
    into `lib/str.cyr`. Shipped in `lib/unicode/casefold.cyr`
    instead so str.cyr-only consumers don't transitively pull
    ~100 KB of Unicode data tables. Consumers wanting Str-level
    case fold include both modules.

  Carried forward to v5.8.51 / v5.8.53:
  - Snapshot ping-pong corruption recurred during this slot
    (categories.cyr reverted to pre-extraction state during a
    customer-flow probe). Mitigated in-slot by re-applying +
    snapshotting; root cause TBD. Mabda 2.5.0 dep-cache
    directory symlink remains the leading suspect — may need
    removal sooner than v5.8.49 closeout indicated.

- **v5.8.51** ✅ SHIPPED 2026-05-04 — Unicode 17.0.0 canonical
  normalization (NFC + NFD).

  Delivered:
  - `lib/unicode/normalize.cyr` — `NormalForm` enum (NFC=0, NFD=1) +
    `unicode_canonical_combining_class` + `unicode_canonical_decomp`
    (Hangul algorithmic) + `unicode_compose` (Hangul L+V→LV +
    LV+T→LVT) + `str_normalize(s, form)` + `str_eq_normalized`.
  - `lib/unicode/_normalize_data.cyr` — auto-generated; 3 tables
    (968 CCC / 2081 canonical decomp / 961 composition) ~70 KB.
  - `scripts/gen-unicode-data.py` extended (now fetches
    CompositionExclusions.txt; emits all three sub-tables).
  - `tests/tcyr/unicode_normalize.tcyr` — 51 assertions across 11
    verification categories.
  - cc5 unchanged at 741,040 B.

  Honest scope shrink:
  - Pin specified all 4 forms (NFC/NFD/NFKC/NFKD). Shipped NFC+NFD
    only. Compat-only decomposition table (~445 KB hex) overflows
    cc5's 256 KB `str_data` heap region (`0x14A000`, sized v3.6.9).
    Bumping that cap requires the two-step heap-change bootstrap
    per CLAUDE.md — out of scope for this slot.
  - The compat-only table IS parsed by `gen-unicode-data.py` (3833
    records, ready to emit); it's just dropped at emit time. NFKC
    + NFKD ship as a follow-up once `str_data` is bumped.

  In-slot bug fix:
  - `_uc_compose_pass` had a position-tracking bug (writing
    composed cps to `buf[0]` instead of the current starter's
    position). Caught by the multi-syllable Hangul / multi-mark
    Latin tests; fixed by tracking `starter_pos` explicitly.

  Filed for follow-up:
  - Bump cc5's `str_data` from 256 KB to ~2 MB (proportional to
    v3.6.9's 32 KB → 256 KB jump). Two-step heap-change
    bootstrap. Ships NFKC + NFKD as immediate follow-on.

- **v5.8.52** ✅ SHIPPED 2026-05-04 — Unicode 17.0.0 regression
  suite. Locks the v5.8.49-51 Unicode infrastructure behind a
  120,518-assert regression floor.

  Delivered:
  - `tests/data/NormalizationTest.txt` — 2.7 MB verbatim UCD
    17.0.0 corpus (20034 rows × 6 Parts).
  - `tests/tcyr/unicode_normconf.tcyr` — runtime UCD conformance
    harness reading the corpus via `file_read_all`. Asserts the
    NFC/NFD conformance contract for every row (6 asserts × 20034
    = 120,205 conformance asserts; 120,207 total in the tcyr).
    Cols 4-5 (NFKC/NFKD) skipped at parse time; auto-pick-up
    when v5.8.56 ships K-forms.
  - `unicode_categories.tcyr` extended +62 boundary asserts
    (60→122) — script-block boundaries, plane edges, surrogate
    range, noncharacter sentinels, sub-category transitions.
  - `unicode_normalize.tcyr` extended +32 real-world phrase
    round-trips (51→83) — multi-script multi-word inputs the
    conformance corpus's per-row tests don't directly target.
  - `unicode_casefold.tcyr` extended +36 full-fold equivalence
    asserts (70→106) — ß↔SS, İ↔i+dot, Σ↔σ↔ς, ligatures,
    idempotency.
  - `scripts/gen-unicode-data.py` extended to fetch
    NormalizationTest.txt verbatim alongside the existing UCD
    files; one offline invocation refreshes everything.
  - cc5 unchanged at 741,040 B (no compiler change — pure tests
    + offline tooling).

  Honest scope shrink:
  - Pin item 2 ("~500 known-tricky strings") shrunk to ~30
    multi-word real-world phrases. The 20034-row conformance
    suite already covers the bulk single/short-multi-codepoint
    surface; 470 additional hand-written strings would duplicate
    conformance coverage. The 30 phrases focus on inputs the
    conformance corpus DOESN'T target (longer multi-word
    multi-script real-world strings).
  - Pin item 4 ("conversion-script-emitted tcyr") shifted shape
    — single-file 20K-row tcyr would be ~10 MB of source, far
    over cc5's 256 KB str_data cap (same cap that pushed
    NFKC/NFKD off v5.8.51). Shipped as runtime data file +
    `file_read_all` parser instead. Sidesteps str_data entirely;
    corpus refresh is a single `python scripts/gen-unicode-data.py`
    invocation.

### v5.8.x — Cycle wind-down (v5.8.53 → v5.8.62)

- **v5.8.53** ✅ SHIPPED 2026-05-04 — aarch64 cross-compiler
  staleness unblock + install pipeline rebuild discipline.
  Single-purpose unblock slot triggered by sit v0.7.2 release flow
  surfacing a v5.8.46 token-cap miss on aarch64 cross-build.

  Root cause was NOT a source-code propagation gap — `src/main_aarch64.cyr`
  already had the v5.8.46 layout (`0x368C000` / `0x3E8C000` / `0x468C000`,
  brk to `0x4E8C000`) and `src/frontend/lex.cyr`'s cap check was
  already raised (`tc >= 1048576`). The gap was in the **install
  pipeline**: `scripts/install.sh --refresh-only` (invoked by
  `scripts/version-bump.sh` on every patch) only `cp`'d
  `build/<bin>` into the per-version snapshot — it never rebuilt.
  `build/cc5_aarch64` is gitignored (dev-local, never tracked) and
  was last rebuilt before v5.8.46. So every version-bump from .46
  through .52 silently copied the same stale 438896 B aarch64
  cross-compiler forward, with the pre-cap-raise codegen baked in.

  Delivered:
  - `build/cc5_aarch64` rebuilt from current source — 438960 B,
    new error format `"token limit exceeded: needed N, cap is 1048576"`
    (was: `"token limit exceeded (262144)"` — the smoking-gun
    string sit's release flow caught).
  - `scripts/install.sh --refresh-only` patched to detect-stale-and-
    rebuild for each `[release].bins` + `[release].cross_bins`
    target. Source-mapping rules: `cyrius` ← `cbt/cyrius.cyr`;
    `cc5_aarch64` ← `src/main_aarch64.cyr`; `cc5_<arch>` ←
    `src/main_<arch>.cyr` (future-proof); other `bins` ←
    `programs/<name>.cyr`. Staleness defined as missing binary or
    source mtime newer than binary mtime. `cc5` itself is
    seed-bootstrapped, never rebuilt by `--refresh-only`.
  - Silent error suppression dropped from BOTH `--refresh-only`
    rebuilds AND the bootstrap-from-source path (`2>/dev/null`
    + `|| true` was hiding cc5 warnings AND build failures; the
    downstream `cp` step's `[ -x build/$bin ]` check then silently
    dropped missing artifacts). Now: stderr captured to a tempfile,
    surfaced as warnings on success, surfaced + binary deleted on
    failure. `cc5`'s "note: N unreachable fns" diagnostic is now
    visible (it's expected, not a bug).
  - `dlopen-helper` rebuild added to `--refresh-only` (was only
    rebuilt by full install). Same shape of bug — host libc
    upgrade between version-bumps would leave the snapshot
    stale.
  - cc5 unchanged at 741040 B (no compiler change).

  Verified:
  - x86_64 Linux: `scripts/check.sh` 65/65 named gates green;
    self-host cc5 == cc5b byte-identical at 741040 B.
  - aarch64 Linux (`pi`, agnosarm.local): native self-host gate
    in check.sh passes; minimal cross-built smoke binary scp'd to
    pi runs correctly (prints + exits 42).
  - sit v0.7.2 cross-build via `cyrius build --aarch64`: the
    token-cap error is gone. (sit's release still hits a SECOND
    aarch64 issue downstream — its `lib/agnosys.cyr` is pinned to
    agnosys 1.0.0 which references `SYS_OPEN` unconditionally;
    aarch64 Linux uses `SYS_OPENAT`. agnosys 1.0.4 fixed this with
    `#ifdef CYRIUS_ARCH_X86` gating. **Sit needs an agnosys pin
    bump to ≥1.0.4** to clear this; not a cyrius-side regression.)

  Out of scope (deferred to v5.8.54):
  - aarch64 emit-fn parity gaps — `EFLADDR`, `EFLADDR_X1`,
    `EREAD_PE`, `EOPEN_PE`, `ECLOSE_PE`, `ELSEEK_PE`, `EMMAP_PE`
    are defined in `src/backend/x86/emit.cyr` only. cc5 emits
    "undefined function" warnings on every aarch64 cross-build.
    The PE shims are dead at runtime on aarch64 (gated behind
    `_TARGET_PE == 1`); EFLADDR/EFLADDR_X1 are called
    unconditionally and would crash if reached. Latent issue,
    not sit-blocking — gets its own slot.
  - `aarch64/fixup.cyr:19` syscall arity warning (3-arg `syscall`
    on macOS clock_gettime branch). Likely benign lint, confirm
    or fix in v5.8.54.
  - install.sh P2 audit findings (cosmetic): refresh-only
    `pwd == repo root` defensive check; `cp -L` symlink-cycle
    risk (already CLAUDE.md-mitigated).

  Filed at v5.8.52 ship 2026-05-04; surfaced by sit v0.7.2 release
  process when its `cyrius build --aarch64` hit the pre-cap error
  format. User direction: tight-scope this slot (cap unblock +
  install pipeline rebuild discipline), let emit-fn parity be its
  own .54 slot, cascade remaining items.

- **v5.8.54** ✅ SHIPPED 2026-05-04 — aarch64 emit-fn parity
  (cross-arch propagation follow-up to v5.8.53). Three latent gaps
  from `cat src/main_aarch64.cyr | build/cc5` warnings:

  - **`EFLADDR(S, lli)` + `EFLADDR_X1(S, lli)`** in
    `src/backend/aarch64/emit.cyr`. x86 versions live at
    `src/backend/x86/emit.cyr:1391` / `1373` and emit
    `lea rax, [rbp - disp]` / `lea rcx, [rbp - disp]`. aarch64
    equivalents: `add x0, x29, #disp` / `add x1, x29, #disp`
    with proper imm12 range handling and the move-into-temp
    fallback for out-of-range offsets. Called unconditionally
    from `parse_decl.cyr` (lines 127, 236, 301, 355, 931, 1019,
    1060) and `parse_expr.cyr:234` — would crash if hit.
  - **PE-shim stubs** for `EREAD_PE / EOPEN_PE / ECLOSE_PE /
    ELSEEK_PE / EMMAP_PE`. Dead at runtime on aarch64 (parser
    gates with `if (_TARGET_PE == 1)`) but cc5 still flags them
    as undefined symbols. No-op stubs satisfy the fn table
    without runtime cost.
  - **`aarch64/fixup.cyr:19` syscall arity warning** —
    investigate; fix or annotate.

  Verification: x86 check.sh + aarch64 cross-build with zero
  "undefined function" warnings + native pi self-host. Per
  user-pinned cross-arch propagation rule, all three SSH hosts
  (pi / cass / ecb) get touched even where the change is
  arch-specific, to confirm zero regression.

  Filed at v5.8.52 ship 2026-05-04. User direction: tight-A-then-B
  split with v5.8.53 above.

- **v5.8.55** ✅ SHIPPED 2026-05-04 — UTF-8 codec dedup
  (Unicode stdlib refactor, first of three audit/refactor
  slots). Audit pass for v5.8.x (heap-map deep audit +
  dead-code audit + refactor scope identification) folded
  into the slot prose; the only ship this slot was the
  codec dedup. Dead-code removal moved to v5.8.56;
  remaining refactor opportunities moved to v5.8.57.

  Audit baseline captured:
  - **Dead-code floor unchanged** at v5.8.48's 36 fns /
    22,571 B. Unicode (.49-51) + cross-arch (.53-54) work
    added zero new dead code.
  - **Heap map: 95 regions** — no unused regions, no cap
    pressure. v5.8.x additions (var_enum_id from .22,
    enum_count/variant_count/name from .22-.24, tok_types/
    values/lines relocation .46) all actively used; no
    obvious low-effort consolidation.
  - **Refactor candidates surfaced**: UTF-8 codec dup
    across casefold + normalize (shipped), 8 nearly-
    identical binary-search loops across the 3 unicode
    modules (deferred — moderate effort, low payoff for
    closeout), `_a`/`_r` stdlib variants (no obvious
    collapse — pattern IS the consolidation).

  Delivered:
  - Lifted `_uc_emit_utf8` + `_uc_decode_utf8` from
    `lib/unicode/casefold.cyr` (lines 188-260) and
    `_uc_nz_emit_utf8` + `_uc_nz_decode_utf8` from
    `lib/unicode/normalize.cyr` (lines 245-302) into the
    existing private-shared `lib/unicode/_decode.cyr`
    (which both files already include).
  - Single canonical name pair `_uc_emit_utf8` /
    `_uc_decode_utf8`; the synthetic `_uc_nz_*` collision-
    dodge prefix retired with the deduplication.
  - Updated `normalize.cyr`'s 2 internal callers (lines
    363, 379) to use the canonical names; `casefold.cyr`
    already used canonical names so no rename needed.
  - Test-local UTF-8 codec copies in
    `tests/tcyr/unicode_normconf.tcyr` +
    `unicode_casefold.tcyr` retained — those are test
    fixtures and isolation from stdlib internals is a
    feature, not duplication-to-fix.

  Dedup metrics: ~80 lines deleted (160 lines of duplicate
  body across 2 files, replaced by 1 canonical body in 1
  file plus 2 short comment blocks pointing to it).

  Snapshot-ping-pong incident (in-slot resolution): first
  edit pass was reverted by `check.sh`'s `cyrius deps`
  resolution (the trap CLAUDE.md's "Snapshot-ping-pong
  protection" section explicitly documents — the install
  snapshot still had the pre-dedup unicode/* contents and
  cyrius's own `[deps].stdlib` resolution copied them back
  over the repo edits). Re-applied edits, then immediately
  ran `sh scripts/install.sh --refresh-only` to seal the
  snapshot, then re-ran check.sh — edits stuck. Reinforces
  the documented mitigation; no source code change needed
  beyond the snapshot refresh discipline.

  Verified:
  - `scripts/check.sh`: 65/65 named gates green.
  - Self-host: cc5 == cc5b byte-identical at 741,120 B
    (cc5 unchanged — stdlib-only edit).
  - All 4 unicode tcyrs pass: 122 + 106 + 83 + 120,207 =
    **120,518 unicode asserts** (identical count to
    v5.8.54).

- **v5.8.56** ✅ SHIPPED 2026-05-04 — Dead-code removal pass.
  Audit pinned at v5.8.55 surfaced removal candidates that needed
  per-fn vidya cross-check before deletion (per
  `feedback_dead_code_audit_scope` memory pin: TS_*/macho_*/cross-arch
  fns are reachable via mode flags; 0-callers-in-grep is NOT
  safe-to-remove on its own).

  Delivered (4 fn names removed, 11 fn defs deleted across 3 backends):
  - **ELVRLOAD / ELVRSTORE / ELVRINIT** — loop-var r12 caching
    from v4.8.4-alpha6 never wired to the parser. 9 fn defs
    across x86 (real bodies) + aarch64 + cx (no-op stubs).
    Vidya only referenced ELVRINIT in archive (historical, not
    canonical).
  - **ESHRIMM** — `shr rax, imm` emit fn; sibling of ESHLIMM
    (heavily used at parse_expr.cyr:1141) that never got a call
    site. 2 fn defs across x86 + aarch64.

  Kept after vidya cross-check (despite 0 callers):
  - **GFVA** — coupled with `SFVA` writer (actively called from
    parse_fn.cyr:729,943); accessor for v5.5.36 Phase 3-min/full
    variadic-ABI infrastructure pinned in
    vidya/.../platform_abi.cyml:90.
  - **IR optim pipeline pre-`_capped` fns** (`ir_dce`,
    `ir_dead_store`, `ir_dead_block_elim`, `ir_lower_all`,
    `_ir_lower_node`, `ir_emit2`, `IR_BB_*`, `IR_EDGE_*`,
    `IR_NODE_FL`) — multiple commented-out call sites in
    main.cyr:1229 + main_win.cyr:741 gate them behind env-var
    flags. Staged infrastructure; coupled set; removing
    requires reasoning about IR-emit pipeline as a whole.
  - **CLASSIFY_CF / CF_TARGET** — decode.cyr header explicitly
    documents them as "Foundation for byte-walking CFG
    construction (4.5.x), DCE correctness validation, and future
    register allocation work."
  - **TS_*** (10 fns) — mode-flag-reachable via `--parse-ts`.
  - **_macho_* / EMITMACHO_ARM64** (5 fns) — mode-flag-reachable
    via `--target=macho` + `main_aarch64_macho.cyr`.

  Verified across all three SSH-wired hosts (pi/cass/ecb) via
  existing check.sh wiring per the cross-arch propagation memory
  pin. Self-host cc5 == cc5b byte-identical at 741,120 B (no
  binary delta — removed fns had no reachability path; savings
  are source-side LOC).

  Dead-fn floor: **36 → 32** fn names. Bytes-figure stable at
  22,571 since the removed fns weren't contributing dead-bytes
  to the binary.

  Filed at v5.8.55 ship 2026-05-04 per user direction
  ".55 dedup; .56 deadcode; .57 refactor; cascading remaining."

- **v5.8.57** ✅ SHIPPED 2026-05-04 — sovereign UCD generator.
  Replaces `scripts/gen-unicode-data.py` (the Python predecessor
  carried since v5.8.49) with a native cyrius program. Cycle ethos
  per CLAUDE.md "Own the language. Own the toolchain. No external
  governance." — the Python script's "offline build-machinery"
  rationalization, written into the script header at v5.8.49, was
  rejected at this slot's premise-check. No non-cyrius language is
  acceptable as a slot deliverable.

  Pre-shipped scope (the .55 audit's surfaced candidates) was
  superseded by user direction "rewrite all that shit" 2026-05-04:
  - **Binary-search dedup** across 3 unicode modules — DEFERRED
    (premise-check found NO viable cyrius mechanism: fn-pointer
    callback adds 482-line `lib/fnptr.cyr` to the Unicode dep
    chain (net +437 lines); table-id internal dispatch puts
    branching in the hot binary-search loop (perf regression);
    cyrius lacks macros/generics. The 3 simple-mapping loops
    stay duplicated until cyrius grows the language facility).
  - **gen-unicode-data.py Python consolidation** — REJECTED as
    category error (cyrius release shipping Python work is the
    sleight-of-hand the user explicitly named).

  Delivered:
  - **`tests/data/ucd/*.txt`** committed (4 UCD source files:
    DerivedGeneralCategory.txt, CaseFolding.txt, UnicodeData.txt,
    CompositionExclusions.txt — total ~2.6 MB). Paired with the
    pre-existing `tests/data/NormalizationTest.txt` from .52.
    Hermetic regen — no network, no HTTPS dep, no fetch.
  - **`programs/gen_unicode_data.cyr`** — single-program native
    cyrius UCD generator. Architecture: `_parse_hex` /
    `_parse_decimal` / `_parse_cp_seq` / `_skip_ws` / `_line_end`
    / `_content_end` / `_ud_field_start` / `_ud_field_end`
    primitives; `_sort_records(arr, n, stride)` insertion-sort
    by slot 0 (stable); `_sort_records_by_slot(arr, n, stride,
    slot)` for 2-key sort (composition table needs (cp1, cp2)
    lex order — two-pass stable sort gives that). Per-table
    parse + emit fns; `_emit_table_block(out, prefix, blob,
    blob_len, count, per_piece, chars_per_rec)` shared piece-
    block emitter. Three top-level entry fns: `gen_categories`
    / `gen_casefold` / `gen_normalize`.
  - **Byte-identical to Python output** for the data portions of
    all 3 generated files (`lib/unicode/_categories_data.cyr`
    body, `_casefold_data.cyr` body, `_normalize_data.cyr` body).
    Only the headers differ — the generator-name comment now
    points at `programs/gen_unicode_data.cyr`. Verified by `cmp`
    on `tail -n +<N>` portions of each file vs the v5.8.56
    snapshot (where N skips the header lines).
  - **`scripts/gen-unicode-data.py` deleted.** The Python script
    that v5.8.49-.52 extended four times across the Unicode arc
    is gone. References in `tests/tcyr/unicode_normconf.tcyr`
    updated to point at `build/gen_unicode_data` invocation.

  Verified:
  - Self-host: cc5 == cc5b byte-identical at 741,120 B (compiler
    untouched; this is a stdlib-tooling change).
  - All 4 unicode tcyrs pass against cyrius-regenerated data:
    122 + 106 + 83 + 120,207 = 120,518 asserts (identical count
    to v5.8.56 — semantically transparent regeneration).
  - `scripts/check.sh`: 65/65 named gates green; cross-host gates
    on pi/cass/ecb pass via existing SSH wiring.

  Filed at v5.8.55 ship 2026-05-04. Scope rewritten at v5.8.57
  start per user direction: "How dare you USE ANOTHER LANGUAGE —
  this is a sovereign language project". The sovereignty rule
  pinned to memory at this slot.

- **v5.8.58** ✅ SHIPPED 2026-05-04 — Deps cleanup + release-valve.
  All deps audited at latest GA (zero bumps needed). Release-valve
  shipped state.md refresh (10-slot silent rot since v5.8.47) +
  sovereignty audit pinning v5.9.0 cycle theme. See CHANGELOG for
  detail.

  Original slot pin retained below for historical reference.

- **v5.8.58** — Deps cleanup + release-valve (combined slot).
  Two purposes:
  1. **Deps cleanup** — update `cyrius/cyrius.cyml`
     `[deps.*]` fields to whatever new dep tags the v5.8.x
     cycle's stdlib changes motivated; re-bundle stdlib
     distfiles via `cyrius distlib` if any dep cut a new
     release. Per user direction 2026-05-03 PM.
  2. **Release-valve** — buffer slot for any issue surfaced
     by the Unicode 17.0.0 fold (v5.8.49-52) or the cross-
     arch propagation work (v5.8.53-54) before closeout
     commits the cycle. Mirrors the v5.7.50 P(-1) unblock
     pattern from the v5.7.x cycle's end-of-cycle. If
     everything shipped clean and no consumer flagged
     anything, this absorbs housekeeping (stale-comment
     sweep, orphan file cleanup, the small-but-not-urgent
     items deferred from earlier slots). Per user framing:
     "release valve of any issue surfaced by updates".

  Note: downstream pin bumps (per-repo `cyrius` field updates
  in mabda / sigil / sakshi / yukti / kybernet / hadara / …)
  are NOT executed in this slot — they happen in each
  downstream repo's own cycle, against the v5.8.62 release
  tag.

- **v5.8.59** ✅ SHIPPED 2026-05-05 — `str_data` heap-region
  bump for Unicode compat-only decomposition. Two-step bootstrap
  slot per CLAUDE.md "Two-step bootstrap for heap changes — cc5
  compiles cc5b, cc5==cc5b". Stood alone — no other changes — to
  keep the bootstrap delta auditable.

  Background unchanged from original pin: v5.8.51 shipped NFC +
  NFD only because the ~445 KB compat-only decomposition table
  overflowed the 256 KB `str_data` cap at `0x14A000` (sized
  v3.6.9). v5.8.59 bumps the cap 8x — proportional to the v3.6.9
  jump.

  Layout decision (Option B chosen — relocate str_data to high
  block): the scratch-state cluster at `0x18C100..0x19A000` sits
  inside what an in-place 2 MB grow would consume. Option A
  (in-place + shift downstream — ~200 edits across ~20 files;
  monotonic) vs Option B (relocate to `0x4E8C000` post-tok_lines
  high block, brk → `0x508C000`; ~50 edits, single-purpose;
  non-monotonic). Precedent: v5.8.46 tok-array relocation used
  the same Option-B pattern. User-approved at slot entry
  2026-05-05 with explicit acknowledgment that gaps are
  acceptable — heap-map refactor pinned forward to a pre-closeout
  slot to reorganize.

  Delivered:
  - `str_data` offset `0x14A000` → `0x4E8C000`; size `0x40000`
    (256 KB) → `0x200000` (2 MB).
  - brk: `0x4E8C000` → `0x508C000` (~80.5 MB) in main.cyr,
    main_aarch64.cyr, main_aarch64_native.cyr,
    main_aarch64_macho.cyr, main_cx.cyr.
  - Windows MMAP region: `0x5000000` → `0x5100000` in
    main_win.cyr.
  - 41 `0x14A000` references rewritten across 8 source files
    (lex.cyr 17, x86 fixup.cyr 4, aarch64 fixup.cyr 2, macho
    emit.cyr 2, pe emit.cyr 2, parse.cyr 3, parse_fn.cyr 1,
    main_cx.cyr 1). Historical-context comments in the seven
    main_*.cyr files preserved with "(was 0x14A000)" annotation.
  - 3 cap-check sites in lex.cyr: `262144` → `2097152`. Three
    error messages: "256KB limit" → "2MB limit". Cap-tracking
    85% warnings in main.cyr + main_win.cyr likewise updated.
  - Heap-map comments in all seven main_*.cyr files refreshed.
  - In-slot fix: duplicate `str_data` line in main.cyr's heap
    map parsed by `tests/heapmap.sh` as two regions; resolved
    by demoting the cross-reference to a non-parser-matched
    form (parens around the line).

  Verified:
  - Self-host: cc5 == cc5b byte-identical at **741,128 B**
    (was 741,120 B; +8 B from wider cap-value digits).
  - Two-step: cc5 (v5.8.58 layout) → cc5b (v5.8.59) → cc5b' =
    cc5b byte-identical.
  - `tests/heapmap.sh`: 84 regions, 0 overlaps, 0 warnings.
  - `scripts/check.sh`: 65/65 named gates green.
  - All 127 tcyr files PASS (120,518 unicode asserts unchanged).
  - Cross-host: pi (aarch64 native self-host), ecb (macOS arm64),
    cass (Windows PE), libssl fdlopen TLS — all PASS.
  - aarch64 cross-build: `build/cc5_aarch64` rebuilt at
    **439,880 B** (was 439,904 B; -24 B delta on aarch64).

  Heap-map refactor pin (forward to pre-closeout slot): the
  high-block relocation leaves str_data at `0x4E8C000` above the
  IR/fixup/tok regions — non-monotonic. A pre-closeout slot
  (TBD: .60.5 insertion or absorbed into .61) will reorganize
  the layout. Acceptable per user direction "you should be able
  to review to re-organize and not leave heavy gaps in the
  layout".

  Filed at v5.8.51 ship 2026-05-04; user-approved cycle
  extension past v5.8.55 closeout pin to absorb this and
  v5.8.60's NFKC/NFKD ship. Renumbering history:
  v5.8.55 → v5.8.57 at v5.8.53 ship (cross-arch propagation
  insertion); v5.8.57 → v5.8.59 at v5.8.55 ship (audit/
  dedup/refactor trio insertion at .55-.57).

- **v5.8.60** ✅ SHIPPED 2026-05-05 — Unicode 17.0.0 NFKC + NFKD
  compatibility normalization. Stdlib + data work only — no compiler
  change. Ships the K-forms originally pinned with v5.8.51 but
  deferred per the str_data cap; v5.8.59 raised that cap, this
  slot fills the room.

  Mid-slot encoding pivot (worth flagging — tracking this for
  future heap-map sizing decisions): initial design used fixed-
  width 116-char compat records (cp + count + 18-cp slots, sized
  to U+FDFA's 18-cp Arabic ligature). 3833 × 116 = ~445 KB,
  matching the v5.8.51 pin's sizing assumption. **Hit the
  preprocess_out 2 MB cap** when the data file pushed expanded-
  source past 2 MB on consumer tcyrs. preprocess_out is a
  separate buffer from str_data — the latter holds the
  compiler's string-literal data, the former holds the
  expanded include-resolved source. Pivoted to a 2-table split
  (sorted IDX + variable-width DATA blob, ~87 KB total — saves
  ~360 KB) since the histogram showed 70% of compat decomps are
  1-cp (fixed-width was padding ~100 chars of zeros per record).

  Delivered:
  - **`lib/unicode/_normalize_data.cyr`** regrew from 68,265 →
    156,732 bytes (was 513,758 with fixed-width encoding pre-
    pivot; -71% via 2-table split). New tables: COMPAT_IDX (5
    pieces × 800 records × 12 chars = ~46 KB) + COMPAT_DATA
    (single string, 41,344 chars).
  - **`programs/gen_unicode_data.cyr`** extended (sovereign UCD
    generator):
    - `_parse_normalize_ud` now extracts compat-tagged decomp
      records from UCD field 5 (3833 records).
    - `_emit_compat_data_blob` writes variable-width records and
      populates parallel `compat_idx_recs` with per-record offsets.
    - `_emit_compat_idx_blob` emits the 12-char IDX records.
  - **`lib/unicode/normalize.cyr`** public API:
    - `NormalForm::NFKC = 2`, `NormalForm::NFKD = 3` enum variants.
    - `unicode_compat_decomp(cp, out_buf, cap)` — IDX binary search
      + DATA indirect read; falls back to canonical decomp on miss
      (UAX #15 §1.3 semantics).
    - `_uc_decompose_cp_recursive_compat` private helper —
      single recursion handles compat + canonical as one pass.
    - `str_normalize` dispatch: `use_compat = form ∈ {NFKC,NFKD}`,
      `should_compose = form ∈ {NFC,NFKC}`. Canonical composition
      pass reused (UAX #15 §1.3: NFKC = compat-decompose then
      canonical-recompose).
    - Worst-case decomposition expansion bumped 3x → 18x for
      K-forms (U+FDFA sets the new ceiling).
  - **`tests/tcyr/unicode_normalize.tcyr`** +16 K-form unit
    asserts: ligatures (ﬁ→fi, ﬂ→fl, ﬃ→ffi), full-width Latin/
    digits (Ａ→A, １２３→123), super/subscript digits (²→2,
    ₅→5), Roman numerals (Ⅷ→VIII), NBSP→SPACE collapse,
    U+2100→"a/c", NFKD-vs-NFD parity on canonical-only input,
    K-form idempotency, U+FDFA 33-byte expansion check.
    Asserts: 83 → **99**.
  - **`tests/tcyr/unicode_normconf.tcyr`** auto-discovered cols
    4-5 of NormalizationTest.txt — 6 asserts/row → **16
    asserts/row**, total **320,547 conformance asserts PASS**
    (was 120,207). Per-row scratch added: c4_buf + c5_buf at
    512 bytes (compat decomp can expand 1 cp to 18 cps ≤ 72
    UTF-8 bytes; 7x headroom).

  Verified:
  - Self-host: cc5 == cc5b byte-identical at 741,128 B (no
    compiler change).
  - `scripts/check.sh`: 65/65 named gates green.
  - All 127 tcyr files PASS — total unicode asserts now
    **320,874** (122 + 106 + 99 + 320,547; was 120,518).
  - Cross-host gates: pi (Linux aarch64 native self-host), ecb
    (macOS arm64), cass (Windows PE), libssl fdlopen TLS — all
    PASS via existing SSH wiring.
  - aarch64 cross-build: `build/cc5_aarch64` rebuilt at 439,880 B
    (unchanged from v5.8.59).
  - Total str_data consumption by the new compat data: ~87 KB
    (4.4% of the 2 MB cap raised at v5.8.59); preprocess_out
    room preserved for downstream consumer growth.

  Filed at v5.8.51 ship 2026-05-04.

- **v5.8.61** — Heap-map refactor (post-v5.8.59 layout
  reorganization). Stands alone — no other changes — to keep
  the bootstrap delta auditable. Two-step bootstrap slot per
  CLAUDE.md "Two-step bootstrap for heap changes — cc5 compiles
  cc5b, cc5==cc5b".

  Background: v5.8.59 chose Option B (relocate `str_data` to
  high block at `0x4E8C000` post-`tok_lines`, brk → `0x508C000`)
  over Option A (in-place grow + shift downstream) for blast
  radius / byte-identity reasons. Trade-off: the layout is now
  non-monotonic — the small string-literal buffer sits above
  the big IR/fixup/tok regions. v5.8.46's tok-array relocation
  set the same precedent. Both reorganizations are pinned for
  resolution at this slot. User direction at v5.8.59 ship
  2026-05-05: "you should be able to review to re-organize and
  not leave heavy gaps in the layout".

  Scope:
  - **Heap-map deep audit**. Re-evaluate every region. Identify:
    (a) regions out of monotonic offset order (str_data, tok_*),
    (b) gaps no code uses that would close cleanly under
    consolidation, (c) regions that have grown past their
    original sizing rationale, (d) candidates for retirement
    (legacy fixup-table slot at `0x124A000` is already a
    256 KB documented gap; check if any others sit unused).
  - **Reorganize layout** to monotonic. Fold str_data + tok_*
    back into proper offset order. Concrete proposal (to be
    refined at slot entry):
    - Keep var_* tables at 0x11A000-0x13A000.
    - Insert str_data at 0x14A000 + 2 MB span (ends 0x34A000) —
      back to its v3.6.9-precedent offset, now 8x larger. Every
      downstream region (preprocess_out, codebuf, output_buf,
      struct_*, ir_*, fixup_tbl, tok_*) shifts down to close the
      v5.8.46 + .59 high-block gaps. Scratch state at
      `0x18C100..0x19A000` (currently inside the 256 KB padding
      after old str_data) relocates to a fresh band ABOVE the new
      str_data end. Exact offsets sized at slot entry.
    - Or alternative: keep str_data at 0x4E8C000 and reorganize
      the rest to absorb the gap (less reorganization, less
      win). Decision deferred to slot-entry sizing.
  - Update every offset reference across the 13 source files
    that v5.8.59 touched, plus any others that the reorg
    surfaces. Update heap-map comments in all seven main_*.cyr
    files. Update `tests/heapmap.sh` if its parsing assumptions
    need adjustment.
  - **Two-step bootstrap audit**: cc5 (v5.8.60 layout) compiles
    cc5b (v5.8.61 layout); cc5b compiles cc5b'; cc5b == cc5b'
    byte-identical at the new size.

  Acceptance: cc5 == cc5b byte-identical post-reorg; bootstrap
  closure intact; `tests/heapmap.sh` reports monotonic layout
  (no out-of-order regions, gap distribution improved over
  v5.8.60); all existing tcyrs still pass; cross-host gates
  pi/cass/ecb green via existing SSH wiring.

  Filed at v5.8.59 ship 2026-05-05. User direction: cascade the
  closeout slot forward by one to absorb this — **closeout moves
  from .61 to .62**, backstop hard at v5.8.62.

- **v5.8.62** — Cycle closeout pass. **The cycle backstop
  and the actual final patch of v5.8.x** (extended from
  v5.8.55 to absorb str_data heap bump + K-forms + the
  cross-arch propagation slots + the audit/dedup/refactor
  trio at .55/.56/.57 + the v5.8.61 heap-map refactor). Per
  CLAUDE.md "Closeout Pass" (11-step protocol — mechanical
  first, judgment-call passes, doc sync):

  §1-3 **Mechanical (fast-fail):**
  - Self-host verify (cc5 == cc5b byte-identical)
  - Bootstrap closure (seed → cyrc → asm → cyrc
    byte-identical)
  - Full check.sh — all gates green; record the test count
    (grew from 65 at v5.8.48; expected to reach ~70+ with
    Unicode tcyrs including the v5.8.52 conformance harness
    and the v5.8.60 K-form additions)

  §4-8 **Judgment (cross-check, since v5.8.55 already did
  the deep passes):**
  - §4 Heap-map audit (re-verify Unicode-table regions
    documented in heap map — Unicode normalize +
    decomposition tables consume new bake-in regions)
  - §5 Dead-code audit (record new floor)
  - §6 Refactor pass (any consolidation v5.8.49 missed +
    Unicode-specific opportunities)
  - §7 Code review pass (walk Unicode + late-cycle diffs
    end-to-end; ABI/PE/macho guards; byte-order typos in
    UCD-blob hex literals)
  - §8 Cleanup sweep (stale comments, dead `#ifdef`
    branches, orphan files in `build/` / `tests/`)

  §9-10 **Compliance / external:**
  - §9 Security re-scan (UCD data files are read-only blobs
    but worth confirming no parse-time write paths leak
    through; full audit was last v5.0.1 — assess whether
    this closeout warrants a fresh audit per the
    "every 2-3 minors" rule)
  - §10 Downstream check (all `cyrius.cyml` `cyrius` fields
    across ecosystem repos point to released tags; flag any
    repo behind on bumps for the consumer to catch up)

  §11 **Docs sync (silent-rot prevention):**
  - CHANGELOG/roadmap/state.md/vidya all reflect v5.8.61
    state
  - **Vidya per-minor refresh** — `language.cyml` (Unicode
    APIs new entries), `field_notes/compiler.cyml` /
    `field_notes/language.cyml` (cycle gotchas including
    the v5.8.59 high-block relocation + v5.8.61 reorg),
    `implementation.cyml` / `types.cyml` (heap map +
    structural changes), `dependencies.cyml` /
    `ecosystem.cyml` (dep refresh from .56)
  - Cross-check version refs in vidya match VERSION file
  - Migrate completed v5.8.* slot narratives from roadmap
    into `docs/development/completed-phases.md`

  Acceptance gate: every CLAUDE.md §1-11 step ticked;
  completed-phases.md migration of all v5.8.* sections; cc5
  byte-identical; no new warnings.

  **Cycle backstop hard at v5.8.62** (was v5.8.51 pre-
  Unicode-pin → extended to v5.8.55 on 2026-05-03 PM →
  extended to v5.8.57 on 2026-05-04 to absorb the v5.8.51-
  deferred str_data heap bump + NFKC/NFKD ship → extended
  to v5.8.59 on 2026-05-04 PM to absorb the cross-arch
  propagation slots .53 (install pipeline) + .54 (emit-fn
  parity) → extended to v5.8.61 on 2026-05-04 evening to
  absorb the audit/dedup/refactor trio at .55-.57 per user
  direction "flatten some runway for all the items" →
  extended to **v5.8.62** on 2026-05-05 at v5.8.59 ship to
  absorb the heap-map refactor as its own dedicated slot
  (the Option-B high-block relocation from .59 left a
  non-monotonic layout that warrants a clean reorg before
  closeout)). The cycle now exceeds the original v5.8.60
  buffer that was pre-approved at the .51 ship;
  user-approved at every extension because the runway
  flattening required it.

### v5.8.x — held items (surfacing-ask only; not pinned, no slot consumed)

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

### v5.8.x — deferred to v5.9.x or later

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

## Stdlib (65 modules + 6 deps)

| Category | Modules |
|----------|---------|
| Core | string, fmt, alloc, io, vec, str, args, fnptr, flags |
| Types | tagged, hashmap, hashmap_fast, trait, assert, bounds |
| System | syscalls, callback, process, bench |
| Concurrency | thread, thread_local, atomic, async, freelist |
| Data | json, toml, cyml, csv, base64, regex, math, matrix, linalg, bigint, u128 |
| Network | net, http, ws, tls (+ sandhi at v5.7.0 clean-break fold, absorbing http_server — see [sandhi ADR 0002](https://github.com/MacCracken/sandhi/blob/main/docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) |
| Filesystem | fs |
| Audio | (vani distlib at v5.8.0; lib/audio.cyr retired into vani's higher-level vani_* API) |
| Logging | log |
| Time | chrono |
| Knowledge | vidya |
| Interop | mmap, dynlib, fdlopen, cffi |
| Identity | pwd, grp, shadow, pam |
| Tracing (dep) | sakshi, sakshi_full |
| Database (dep) | patra |
| Security (dep) | sigil |
| Hardware (dep) | yukti |
| GPU (dep) | mabda |
| Compression (dep) | sankoch |

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
