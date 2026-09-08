# Cyrius Development Roadmap — v6.6.x (active minor)

**Scope** — the **current active minor only** (v6.6.x). This is the slot-pinning working
artifact: the repair window, the proposal queue, the committed ergonomics list, and the
unscheduled 6.x backlog. Whole-cycle framing plus v6.7.x/v6.8.x live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slots) → [roadmap_6.md](roadmap_6.md)
> (v6.7.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

> ⚠ **This file was rewritten 2026-09-08 at v6.6.1.** It had been 1,043 lines still titled
> *"v6.5.x (active minor)"* — a closed minor — of which **~480 lines were a slot list where every
> entry read ✅ SHIPPED**. CLAUDE.md's rule is that closed-minor detail lives in the CHANGELOG and
> [completed-phases.md](completed-phases.md) and that this file carries **only what is still
> ahead**; that rule had been violated for a whole minor, which is the same drift the 2026-07-29
> re-scope removed from `roadmap_6.md`. The v6.5.x narrative was not deleted — it is in the
> CHANGELOG per-patch and summarised in `completed-phases.md`'s v6.5.x band. **Do not re-add
> shipped slots here.**

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: v6.7.x/v6.8.x RISC-V
  rv64, cycle budgeting, and the shape of what follows v6.x.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger**.
- [state.md](state.md) — volatile current state. Refreshed every release by `version-bump.sh`.
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.6.1** (2026-09-08) — cycc **1,247,608 B** (`.text` **1,090,832**) ·
`check.sh` **GREEN 240/240** · seed-derive **GREEN** · cross-OS **GREEN** on ecb/ach/cass/pi ·
**301** `.tcyr` (**68** in `crossos/`) · **102** `lib/*.cyr` · **144** shell gates under
`tests/gates/<bucket>/` · self_compile **731–734 ms** · **0 open issues** · **3 open proposals**.

> ⚠ **Every figure above was DERIVED on the day, not carried.** The previous head line was
> version-stamped to `v6.6.1` by `version-bump.sh` while still quoting pre-6.6.1 metrics
> (cycc 1,200,888 B · 297 `.tcyr` · 131 shell gates · 671 ms · 4 open issues). `version-bump.sh`
> rewrites the version token and nothing else — **the numbers beside it are yours to re-derive.**
> Re-derive gates with `find tests/gates -name '*.sh' | wc -l`; never increment.

**v6.6.0 opened this minor** with the one breaking change in it: `Result` / `Option` / `Either`
are the **value form** — a payload variant returns `(tag, payload)` in a register pair, so
construction allocates **zero bytes** (the filed `100x sock_send` → 1600 B measurement now reads
0). It shipped WITH the ecosystem — 8 sibling stdlibs migrated at source, pin-bumped, released
and re-folded. **v6.6.1** closed the entire open issue queue (three filings) and folded five more
stdlibs.

**The open queue is at zero for the first time in the cycle.** That is the condition this minor
was waiting on, and it is why the shape below starts with a repair window rather than a feature
arc: the next work is whatever 6.6.x itself surfaces, taken while the queue is still small
enough to see.

---

## The shape of v6.6.x

Three phases, in this order (user, 2026-09-08):

| Phase | Slots | What goes here |
|---|---|---|
| **1 — Repair window** | `.2` – `.6` | Defects and residuals **arriving from the 6.6.x releases themselves**. Reserved capacity, not a wish list. |
| **2 — Proposals** | after the window | The 3 open proposals, sequenced by their own stated prerequisites. |
| **3 — Committed ergonomics** | after proposals | The v6.6.x "best of the best" language-import list, carried in from `roadmap_6.md`. |

**Why the window comes first.** 6.6.0 was a layout-contract break across 125 pinned repos and
6.6.1 repaired a silent shipped-artifact crash on two targets. Work of that shape generates
follow-on defects for several releases, and the cheapest time to take them is while the queue is
empty and the context is fresh. Slots `.2`–`.6` are **reserved for that**; three known occupants
are pinned below and the remainder is deliberate slack. If the window closes early, phase 2
starts early — an unused reserved slot is not a slot to fill with something else.

---

## Phase 1 — the repair window (`.2` – `.6`)

### `.2` — `cyrius build <src>` can overwrite the running compiler, and did

**Carried in from [roadmap_6.md](roadmap_6.md) item 7 — the only item in that list that was a
defect rather than a feature.** Found the hard way at the v6.6.0 cut: in this repo
`cyrius.cyml` declares `output = build/cycc` (correct — that is how the compiler is built), and
the documented argument ladder says one positional argument means *"that src + manifest output"*.
So `cyrius build tests/tcyr/.../foo.tcyr` compiled the TEST and wrote it over `build/cycc`,
replacing the compiler with an 842 KB test binary. It was recoverable only because a verified
stage binary happened to still be in `/tmp`; from a clean tree it costs a bootstrap.

**The ladder is right and documented, so the fix is narrower than changing it:** refuse to write
the output when the resolved path is the compiler `cbt` is currently running, **unless** the
source is the manifest's declared `src`/`entry`. That combination — an explicit foreign src plus
an inherited output — is the only destructive one, and nothing legitimate needs it.

⚖️ **Deliberately not packed into 6.6.0, and the reason was named at the time**: a `cbt/` CLI
change in a different subsystem needing its own gate, landing after the release gate had already
gone green would have forced a full multi-host re-run. That is a legitimate defer under the
"cannot pack" rule — it is pinned here rather than left as prose.

**Acceptance**: building a foreign source in this repo refuses with a named error; building
`src/main.cyr` (the declared entry) still writes `build/cycc`; gate mutation-proven by reverting
the guard. Note the gate must run somewhere that is **not** this repo's `build/cycc`, or the
gate itself becomes the destructive act.

### `.3` — per-item `private` parses and silently privatises the whole file

Twelve-plus releases live, no diagnostic. `_TL_VIS` (`src/frontend/parse.cyr:222-234`) handles
token 153 by calling `_PRIV_MARK(FM_FILEID(...))` — a **FILE-level** flip — with an in-source
comment recording that a per-item running flag was deliberately rejected because it would leak
into later includes. So `private fn h(): i64 { … }` compiles clean and privatises the *entire
file*, `main` included.

This was carried as "open question 3" for months. ⛔ **It is not a question — it is a defect**,
and the roadmap that held it said so itself before failing to move it. Three options, and the
one outcome to rule out is the current one:

1. implement the per-item bit;
2. make the per-item form a **hard error** pointing at the file-level declaration;
3. keep it and document the widening.

**Default, taken rather than asked**: option 2. It is the smallest change that removes the silent
wrong-semantics, it matches how every other misuse in the visibility feature already reports, and
it leaves option 1 available later without a migration. If a consumer wants true per-item
privacy, that is a feature request against a working diagnostic rather than a bug against silence.

**Acceptance**: `private fn f()` is a named compile error citing the file-level form; file-level
`private` is unaffected; a gate axis proves the error fires and another proves the file-level
path still works — the second is what stops the fix becoming a blanket refusal.

### `.4`–`.5` — DCE cannot compact on PE or x86 Mach-O (the rip-relative repair)

**Arrived from v6.6.1.** `CYRIUS_DCE=1` now declines the whole-program compaction on PE and x86
Mach-O, exactly as it already declines under `_pie_mode`, because both reach a live import/stub
table through a **rip-relative disp32 that the compaction pass does not repair**, and both
compute file geometry *before* elimination runs. Declining was the correct release fix — those
targets emitted a binary that faulted `0xC0000005` before `main` (PE) or SIGSEGV'd on real
Intel-Mac hardware (Mach-O) — but it leaves them on NOP-fill: **correct, and not shrinking.**
ELF still eliminates for real (measured 123,048 → 16,552 B, −86.5%).

**The repair is two things that must land together**, which is why it is scoped at two slots:

1. **Repair the rip-relative shape in `wp_compact`** — when a body is removed, every `disp32`
   whose target is *not* code that moved by the same delta needs re-patching. This is the same
   repair `_pie_mode` needs, so doing it unblocks PIE compaction too; do not build a PE-only
   version of it.
2. **Re-run `_pe_layout(S)` after compaction** (and the Mach-O equivalent) so section geometry,
   RVAs and `PointerToRawData` describe the code that was actually emitted — with the ftype=4
   IAT-reference fixups patched **after** that re-layout, since their displacement is computed
   from `_pe_idata_rva`.

⚠ **Order matters and the current code proves it**: the IAT displacement in the broken build
resolved to RVA `0x39DD` for an IAT the header put at `0x23000` — it had been patched against the
old geometry and then the instruction moved. Fixing geometry without fixing displacements, or the
reverse, produces a binary that looks fine and faults later. That is exactly the shape that cost
three attempts at the v6.5.72 compaction work.

**Acceptance**: `tests/gates/codegen/dce_pe_macho_layout_declines_compaction.sh` is **inverted** —
its axes 1-2 currently assert the payload does *not* move, and on success they must assert PE and
Mach-O shrink *and still run*. Verify by RUNNING on `cass` and `ach`, not by size alone; the
whole defect class is "smaller and broken". Keep axis 3 (ELF still eliminates) unchanged.

### `.6` — reserved reactive capacity

Deliberately unassigned. If nothing claims it, phase 2 starts at `.6`.

⛔ **Do not fill this with backlog items.** The window exists because post-break minors generate
defects; a reserved slot spent early on unrelated work is how a reactive window stops being one.
The v6.5.x minor consumed both of its reactive windows and then ran nine further releases with no
slot list at all — that is the failure this reservation is shaped against.

---

## Phase 2 — the proposal queue

Three open proposals, sequenced by their own stated prerequisites rather than by size.

### P1 — `cyrius.cyml` as the build tool's actual configuration
[`proposals/2026-09-04-build-tool-manifest-integration.md`](proposals/2026-09-04-build-tool-manifest-integration.md)

Filed 2026-09-04, 🟡 OPEN. **Sequence it first, and adjacent to `.2`** — both are about the CLI
honouring its own manifest, and `.2`'s guard needs to read the declared `src`/`entry` key, which
is precisely the surface this proposal is about.

⭐ **The lesson it already records is the reason it ranks first**: the v6.5.49 slice shipped
**inert**. Its `[build]` path fallback read `src`, the key *this* repo happens to use — but of
125 `cyrius.cyml` files across `~/Repos`, **120 declare `entry` and 5 declare `src`**, one of the
five being cyrius itself. So the feature presented as *"does not exist"* to 96% of the ecosystem,
and **its gate passed the whole time because the gate's fixture manifest was written with the
same key the implementation read.** Any work here must gate against a fixture that does *not*
share the implementation's assumptions.

### P2 — Embed data files as source strings (`[embed]` / assets manifest)
[`proposals/2026-08-10-embed-data-files-as-source-strings.md`](proposals/2026-08-10-embed-data-files-as-source-strings.md)

Ergonomics, not capability — the generated-`.cyr` idiom already works and is fleet-wide, and
agnosai ships its own generator, so nothing is blocked. **Its prerequisite has cleared**:
`2026-06-25-source-level-version-constant` shipped at v6.5.21, and `PP_EMIT_PKGVER`
(`src/frontend/lex_pp.cyr`) is the template for a `#@embed` arm.

⚠ **Hard constraint learned at `.21`**: an injected directive must emit **ZERO newlines** (merge
onto the following source line) or it shifts every `<source>` diagnostic by one — a 1-for-1 line
replacement is **not** line-neutral.

### P3 — Compile-time evaluation (`const fn` / const-eval)
[`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md)

**The rung was already chosen 2026-07-07** — option 1 `const fn` primary, option 3 `#phf`
fallback, option 4 (a general const-eval VM) declined. No maintainer decision is outstanding, and
a first triage pass that labelled this "blocked on maintainer" was refuted on re-check. This is
also **item 2 of the committed ergonomics list below** — the proposal and the roadmap row are the
same work, which is why it sits at the phase 2/3 boundary rather than being listed twice.

⚠ It reuses the `ir_const_fold` fixpoint (`src/common/ir.cyr`), so it must land **after** any
work that rewrites that pass, or the churn is paid twice.

---

## Phase 3 — the committed ergonomics list

**Theme set 2026-07-07 (user, horizon session).** RISC-V rv64 — previously this minor's theme —
was re-homed to v6.7.x/v6.8.x: hardware is in hand, but a 7th platform is deliberately held while
*"still heavy quality and ergonomic improvements [are] on the horizon."* v6.6.x instead takes the
modern-language feature imports that fit the assembly-up identity — **no GC, no hidden control
flow you cannot disassemble.**

1. ✅ **SHIPPED v6.6.0 — `Result` / `Option` / `Either` are the value form.** The one breaking
   change in the minor, at the front of it because everything else is additive. Detail in the
   CHANGELOG; do not re-plan it.
2. **`const fn` — the const-eval ladder, option 1.** See **P3** above; same work, listed there
   with its sequencing constraint.
3. **Opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`) — designed in the v6.3.x
   plan, never shipped. Verified live: `CYRIUS_BOUNDS`, `#bounds` and `_bounds_check` find **0**
   hits in `src/`. The sanitizer story that makes footguns findable at their source. **OFF by
   default** — assembly-up: raw stores stay raw in release builds. Premise-check the 0-hit count
   at slot entry rather than trusting this line.
4. **Trait-bounded generics** — the post-monomorphization ceiling. **DEMAND-GATED tail**: pulls
   in only if consumer pressure materialises by the time the slot opens. Fix the
   **multi-type-param struct-type-arg residual** first (single-tparam struct type-args shipped
   v6.3.38–.39; the residual is only the mixed multi-tparam combo).

~~`defer` / scope-exit~~ and ~~per-block scoping + shadowing~~ were struck 2026-07-29: **both
already shipped** (`defer` at v3.8.0; block scoping verified by running the compiler). They sat
here as pending work for features that had existed for majors. What remains of the scoping row —
that a **same-scope** redeclaration is a hard error — is the documented rule, not a footgun.

**Explicitly NOT imported** (decided 2026-07-07): borrow-checker-style lifetimes (wrong fit for
the trust model and the single-pass design), a general const-eval VM, exceptions of any kind.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **`lib/net.cyr` §4 — per-arch socket syscall peers.** The issue is ARCHIVED (`✅ RESOLVED
  v6.5.7 + v6.5.11`) and was closed deliberately without its §4, so the sharp edge is gone but
  the work is unshipped: `lib/net.cyr` still carries bare x86 numbers with `grep -c CYRIUS_ARCH`
  → **0**, working because nine `ESYSXLAT` x86-compat rows remap them. That remap is
  **load-bearing for 51 ecosystem repos** — this is a migration, not a deletion.
- **`lib/net.cyr` AF_UNIX surface** — a yes/no design call, not a defect: whether `net.cyr` grows
  a Unix-domain socket surface alongside INET. Nothing blocks on it.
- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks with
  no shared pass-1 dispatch helper. A recurring-bug class, not cosmetics: `#io` v5.8.20, `#pure`
  v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute needed return-0 stubs in aarch64 + cx
  and only `cass`'s `cycc_cx` caught the miss. Logic-preserving ⇒ gate is byte-identical
  self-host on all four hosts + seed-derive. Premise-check the fork count at slot entry.
- **DWARF debug-info emission** — backend/codegen work; slot it when a real debugger story is
  needed. Distinct from the DX diagnostics arc, which was only the error-reporting layer.
- **Incremental compilation** — unpin condition: reconsider when cycc self-host crosses ~2 s. It
  is **731–734 ms at 6.6.1** after 150+ releases, so the whole-program model is nowhere near the
  threshold. ⚠ Read the trend with care: the same binary has measured a 52 ms spread across three
  consecutive runs — **wider than most release-over-release deltas** — so a single number carries
  no signal. Every release's mandatory bench run IS the report.
- **`ir_dce` / `ir_dead_store` uncapped wrappers and `CLASSIFY_CF` / `CF_TARGET`** — decide
  wire-or-delete. Leaving a third option open is how they survived two closeouts.
- **Bare `var a[N]` byte-vs-slot convention** — a design decision, not an arc. The typed spelling
  `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is whether to
  lint the address-taken bare-local per-slot idiom.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot). Policy: the
  next new compiler-state scalar goes into a hole rather than growing the band. **Cite the live
  count** (`grep -n FREED src/main.cyr`) and the heap map; do not maintain an enumerated list that
  goes stale every minor.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term".

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

---

## Open questions — standing defaults, not a queue

⛔ **This section was once titled "owed to the maintainer" and that framing is banned here. There
is nobody to owe: the maintainer is the person reading this.** A question parked as "owed" is a
deferral to nobody, and it is how several of these sat for months. The rule: **each item carries
a stated default and the work starts under it**; where a genuine fork remains it gets ASKED, in
one line, that turn — not recorded here and left.

The proof is on the record: `darshana-aarch64-syscall-shadow` sat as *"needs a call on where a
~350-row table lives"* until the call was simply taken (**generate it from the stdlib peers**),
whereupon it became 43 derived rows and shipped at `.51`. Assume the same of anything below.

1. **The self_compile budget — ANSWERED (user, 2026-07-29): the later performance track owns it.**
   The budget gets set as part of that track rather than pinned up front. Input for whoever opens
   it: **731–734 ms · 1,247,608 B at 6.6.1**. A previously-floated candidate pair was *≤700 ms and
   ≤1.20 MB at minor close* — ⚠ **both halves are now exceeded**, so that pair is an input to
   re-decide, not a target that was missed. Review together with item 2.
2. **The self-compile growth-tax audit — ANSWERED (user, 2026-07-29): likely dropped, but
   re-review WITH item 1's performance track**, the two being the same subject. Explicitly *not*
   silently dropped — parked against that track's opening review, which decides whether it still
   earns a bite. Record the outcome here either way.
3. **macOS concurrency ordering.** Real platform work with a genuinely broken verb on a gate
   host, so it cannot be dropped — but it has **no consumer waiting**, it mirrors an
   already-shipped split (`thread_win`), and the crossos guards mean it cannot rot silently.
   **Default: keep it last in the minor**; pull it forward if a consumer appears.

*(Former item 3 — per-item `private` — was never a question. It is a live defect and is now
slot `.3` above. Former item 2, the bare-metal forbidden-module check, SHIPPED at v6.5.24 after
this section had carried it as "never built" for thirty releases.)*

---

## Standing notes — traps this minor must not re-learn

- **The `PARSE_RETURN` tail path has skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each fixed with the same narrow divert — the `_cfo`
  escalation shape, *"declared fixed, fourth occurrence in a path nobody enumerated"*. **Any new
  `PARSE_FNCALL`-resident transformation must be grepped against the tail path before it ships**
  — grep the SHAPE, not the operator.
- **A filing's target list is a report about what the reporter builds, not about the bug.** The
  v6.6.1 DCE issue said *"PE / `--win` target only"*; x86 Mach-O shared the code path and was
  crashing on real Intel-Mac hardware, unreported, because the reporter does not build that
  platform. **Reproduce on every host that shares the path before scoping the fix.**
- **An all-identical codegen differential is not evidence a fix is inert — it is evidence of a
  corpus blind spot.** Three consecutive releases measured 0 diffs on real wrong-answer fixes.
  When a fix measures 0 diffs, add the shape to the corpus in the same release.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9 minors
  behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. Run the compiler on the
  hardware.
- **A "found by ports" test is worth more than the gate that says the code compiles.** v6.5.7's
  compile-only wrapper gate proved the wrappers *compile* on five targets — most of the risk, none
  of the bugs. The one `.tcyr` that RAN them found **seven** defects, five of which were half-fixes
  that stopped at the first symptom. Whenever a slot adds a platform-facing verb, the
  `tests/tcyr/crossos/` file is the deliverable, not the nice-to-have.
- **A gate fixture in the wrong order is a vacuous gate**, and a gate whose fixture shares the
  implementation's assumption proves nothing at all (the v6.5.49 `entry`/`src` case). Mutation-prove
  the gate *and* check that the mutation is reachable.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.** The
  retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got cited to
  file against *sigil*. This is the language repo: when the compiler cannot compile valid cyrius,
  fix the compiler. Premise-check **rules**, not just pins.
- **Re-derive every count in this file at slot entry.** The head line above was version-stamped
  correctly and wrong in five metrics simultaneously; the previous edition carried a gate count
  seven higher than the tree. A number in a roadmap has nothing checking it.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

- **Atomic commits, packed releases.** One logical change per commit; a release bundles many.
- **A bug ships complete** — no granularity by gnarliness, no slicing the hard half into the next
  patch.
- **Only the user pivots focus.** Surface findings; never unilaterally redirect or defer.
- **Release gate GREEN before every `.NN`** — self-host fixpoint · seed-derive · check.sh ·
  cross-OS on ecb/ach/cass/pi (REAL hardware) · bench. Never tag with the gate RED.
- **Benchmark every release**, recording self_compile + cycc size in the CHANGELOG entry.
- **An audit's output is fixes, not a backlog.** File only when the fix genuinely cannot pack —
  and name the reason.
