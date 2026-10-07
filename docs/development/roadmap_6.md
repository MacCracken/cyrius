# Cyrius Development Roadmap — v6.7.x and beyond

**Scope — FORWARD ONLY: v6.7.x (the language arc), v6.8.x/v6.9.x (RISC-V rv64), and the shape of what follows v6.x.**
This file is deliberately *not* a record of shipped work and *not* a spec for the current
minor. Re-scoped 2026-07-29: it previously carried full per-minor detail for v6.0.x through
v6.4.x plus a duplicate v6.5.x specification, which made it 1,592 lines of mostly-history and
gave the v6.5.x plan two homes that had already drifted apart.

**Where the other content went, and where to add new content:**

| You want | Go to |
|---|---|
| The **current active minor** (v6.6.x) in slot-by-slot detail | [roadmap.md](roadmap.md) — the single authority. Do **not** re-add a v6.6.x spec here. |
| What a **closed** minor shipped | [`CHANGELOG.md`](../../CHANGELOG.md) per-patch (source of truth) · [completed-phases.md](completed-phases.md) for the arc retrospective |
| **Unpinned / speculative / post-v6.x** items | [roadmap-future.md](roadmap-future.md) |
| Durable process rules | [cycle-discipline.md](cycle-discipline.md) |
| Volatile current state | [state.md](state.md) |

> **Reading order**: [roadmap.md](roadmap.md) (active minor) → this file (the minors after it)
> → [roadmap-future.md](roadmap-future.md) (beyond the cycle).

> **PLACEMENT RULE (hard, restated because this file is where it gets violated):** every
> technical / codegen / runtime / platform item lives in the **6.x line** or an explicitly
> unscheduled 6.x backlog. **Nothing codegen is EVER parked to 7.x** — 7.x is the language
> book plus legal-for-public-release, only that. The v6.4.82 closeout found and corrected two
> violations here (DWARF, incremental compilation); the DWARF bullet in "What comes after v6.x"
> below still carries its correction note for that reason. **The 2026-08-07 doc sweep found
> two more in the same closing paragraph** — LSP/formatter/linter evolution and agnos-v2.0
> alignment — and re-homed both to the 6.x line. Four violations, all in this one file, all
> found by a sweep rather than by the rule catching them: **if you are about to write a
> capability under a 7.x heading, you are almost certainly making violation number five.**

## See also

- [roadmap.md](roadmap.md) — the **current active minor** (v6.6.x), slot-by-slot. Rotates at
  every minor cut; it is the authority for anything in flight.
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles (slot acceptance,
  bottom-to-top priority, premise-check, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size, in-flight slot).
  Refreshed every release.
- [roadmap-future.md](roadmap-future.md) — long-term watching list.
- [completed-phases.md](completed-phases.md) — historical arc retrospective (Phase 0–11 plus
  the per-minor v6.x summaries).
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

Reference points, **updated at the v6.4.x close, corrected 2026-08-07, v6.5.x added 2026-09-08**
— this line used to call v5.11.x's 70 slots "longest in history", which two v6.x minors have
since passed. By closing patch number: **v6.0.x ran to .91** and **v6.4.x to .86** (this line
said `.82` until 2026-08-07 while the table below already said `.86` — the same
one-copy-drifts-from-the-other failure the table's own header warns about), then
**v6.5.x (.73)**, v5.11.x (.69), v6.2.x (.52), v5.7.x, v6.3.x (.45), v6.1.x (.41). Every v6.x minor except v6.1.x has
exceeded the "30-40 range" target — the working rule (user 2026-06-10) is *"no worries
about patch size, just hardening and adding features"*, and large minors are the norm,
so read the budget as a planning aid, not a cap.

---
---

## Closed minors — v6.0.x through v6.6.x

Per-minor narrative used to live here in full. It does not any more: it duplicated
`CHANGELOG.md` (the source of truth) and `completed-phases.md` (the retrospective), and being
duplicated it went stale — the v6.4.x header sat at "closed at v6.4.82" for weeks when the
minor actually closed at **v6.4.86**, which is exactly the failure a second copy invites.

| Minor | Theme | Closed at |
|---|---|---|
| v6.0.x | Language cleanup + stdlib + native TLS | **v6.0.91** |
| v6.1.x | Backend codegen multi-arc | **v6.1.41** |
| v6.2.x | Platform expansion (bare-metal + dependency model) | **v6.2.52** |
| v6.3.x | Language refinements | **v6.3.45** |
| v6.4.x | Staging minor → long reactive minor | **v6.4.86** (closeout cut at .85; .86 was the post-closeout sandhi fold) |
| v6.5.x | Perf / quality: IR substrate, regalloc, SIMD register residency, `: stack` enums | **v6.5.73** (there is no `.74` — that number was cut in error and re-cut as v6.6.0) |
| v6.6.x | Value-form `Result`, then repair; the tooling tail (manifest, distlib, `[embed]`); its language list moved to v6.7.x | **v6.6.20** (the closeout, 2026-10-07; CVE-79 … CVE-102) |
| v6.7.x | **ACTIVE** — the language minor: real traits, the missing common features, `const fn`, bounds mode, trait-bounded generics; see [roadmap.md](roadmap.md) | — (opened **v6.7.0**, 2026-10-07) |

Every close number above was verified against `CHANGELOG.md` on 2026-07-29 (the per-minor max
`## [6.Y.N]` heading), not carried over from the previous text, re-verified 2026-08-07, and the
v6.5.x row added 2026-09-08 from the same source.

> **Bare-metal deliverable #4 (the forbidden-module check) SHIPPED at v6.5.24.** The full
> correction block that stood here — an item described as unbuilt *because it had been archived*,
> wrong for thirty releases — is retired 2026-09-08 now that the acceptance list it warned about
> is gone with the v6.5.x spec. The lesson is kept in
> [cycle-discipline.md](cycle-discipline.md): **an archive entry is evidence of completion, not
> of absence** — verify resolved-status against LIVE code, never against a file's own claim.

---

## v6.7.x — ACTIVE MINOR — specified in [roadmap.md](roadmap.md)

**This file intentionally holds no v6.7.x specification.** The language arc set 2026-10-01 (*"6.7.0 become the
real trait arc and missing common features arc …"*) was specified here until the v6.7.0 open on 2026-10-07,
when it MOVED to [roadmap.md](roadmap.md) with the decisions taken at the open, the re-measured premise table
and the ecosystem keyword survey — the same move made for v6.5.x (2026-07-29) and v6.6.x (2026-09-08). One
authority per active minor. v6.6.x closed at **v6.6.20** (row above).

**When v6.7.x closes:** add one row to the table above, and do not copy its detail back here.

---

## Between v6.7.x and RISC-V — the DCE compaction arc and the net migration (placed 2026-10-02)

Still 6.x, never 7.x. Moved out of the 6.6.x tail with the accepted plan: **the DCE compaction arc**
(aarch64 first — its own repair model, which rv64 reuses, cheaper after 6.6.18's ESYSXLAT fold — then PE /
x86 Mach-O, which have no consumer today; spec below), **`lib/net.cyr` §4
per-arch socket peers**, the remaining syscall families, and **AF_UNIX** (default yes; 19 repos hand-roll
it). About 3–5 releases. Whether they form the tail of v6.7.x or the head of the RISC-V minor is decided at
the v6.7.x close.

### The DCE compaction arc — spec (moved from roadmap.md at the 6.6.20 closeout)

> **Re-placed 2026-10-02 (user accepted the tail plan): AFTER v6.7.x, before the RISC-V minors — still 6.x.**
> The PE / x86 Mach-O half has no consumer today (the 18 repos that use DCE build aarch64); aarch64 needs its
> own repair model, which rv64 will reuse, and it is cheaper after the ESYSXLAT fold (6.6.18). Every target is
> correct today (the unsupported ones only skip the shrink); ✅ the honest "compaction declined: <why>" note
> SHIPPED in 6.6.18 — every declining target (PE, x86 Mach-O, `--pie`, `shared;`, aarch64 ELF, arm64 Mach-O) names
> itself and its reason inside the existing note line, and static x86 ELF past the 4,096-run repair-registry cap
> says so. Order: aarch64 first, then PE / Mach-O.
>
> ⚠ **aarch64 compaction must repair the resolved `bl <ESYSXLAT stub>` sites** (6.6.18 XLAT-2): a variable
> syscall number calls a shared per-class stub through a `bl` that carries no fixup-table entry and no position
> registry; `ESYSX_STUBS`'s site list is drained before FIXUP, so a code-moving pass must find them itself.

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

**Premise (re-checked at the 6.6.7 open; re-grep at the arc's open — the lines move).** The decline was live at
`src/backend/x86/fixup.cyr:875-876`; `_pe_layout(S)` ran at `fixup.cyr:146` (the comment at `:859` and the gate header
still said "line 123"); the ftype=4 IAT disp32 is baked at `:295-300`, before compaction runs at `:877-878`. ⚠ **Wider
than its first slot said**: `wp_compact` also returns 0 for EVERY aarch64 target (`src/common/ir.cyr:1634`), so arm64
Mach-O and aarch64 ELF never compact either — the same arc, taken together. *(Two placement paragraphs that stood here —
"the anchor `src` lane of the release after 6.6.9" and "stays in v6.6.x and runs in the tail" — contradicted the
2026-10-02 placement above and were dropped at the 6.6.20 closeout, BACKLOG-14.)*

## v6.8.x or v6.9.x — Platform: RISC-V rv64

**Re-homed again 2026-10-01 (user)** — from v6.7.x/v6.8.x back *"a minor or two"*, because v6.7.x
became the language minor (above). This is the third deferral of the same shape (v6.2.x → v6.6.x →
v6.7/6.8 → v6.8/6.9), and again a deferral of worry, not intent: the hardware is in hand. **Whether it
takes 6.8 or 6.9 is decided at the v6.7.x close.** The history below is kept as written.

**Theme**: the 4th platform peer — first-class RISC-V 64-bit. **Re-homed here
from v6.6.x at the 2026-07-07 horizon session** (user: hardware in hand, *"can
do it now but have been hesitant to add another platform with still heavy
quality and ergonomic improvements on the horizon … risc can be 6.7 or 6.8 arc
work"*) — the second deliberate deferral of the same shape as the first
(**re-homed from v6.2.x**, user 2026-06-27: *"6.6 is where we put it for now …
[I] don't want to worry about another platform until some of the other items in
the minors get ironed out"*). A **deferral of worry, not intent** — the point is
to let the v6.5.x perf-quality + v6.6.x ergonomics minors land before adding a
7th backend. *(This sentence read "whether it takes 6.7 or 6.8 is decided at
v6.6.x close"; the 2026-10-01 re-home above superseded it.)* The cycle is
explicitly allowed to grow past 6 minors (see "What comes after v6.x" below).

First-class RISC-V 64-bit target — the 4th platform peer after
x86_64 / aarch64 / PE-x86_64. Substrate prerequisites already landed:
typed-simd ABI (v5.x), REAL TYPE SYSTEM (v5.10.x), struct-byval ABI
(v5.10.x), parser-to-emit named-op refactor (v5.11.x close), and the
**v6.2.0 growable-region foundation** (backend #7 inherits the vec-backed
pattern — no fixed-cap re-duplication, which is exactly why growable
landed first in v6.2.x).

> **Hardware is in hand** (user 2026-06-10: *"I have a bunch of hardware
> already; was waiting for RISC-V to do it"*). The rv64 box is the gating
> resource the original plan flagged as a procurement risk (finding RM-04)
> — it's already available, so the **real-hardware self-host gate is live
> from the start** (no QEMU-only interim, no purchase decision blocking arc
> entry). Wire it into the SSH verification fleet alongside pi/ecb/ach/cass
> at arc open.

**Scope**:
- New backend: `src/backend/riscv64/{emit,jump,fixup}.cyr`
- New stdlib syscall peer: `lib/syscalls_riscv64_linux.cyr`
- New cross-entry: `src/main_riscv64.cyr`
- New test runner: `qemu-riscv64-static` for the bring-up probes +
  the **in-hand rv64 hardware over SSH** for the self-host verify
- New CI matrix arm + the rv64 SSH-host wiring

**Acceptance gates**:
1. Cross-compiler `build/cycc_riscv64` emits valid rv64 ELF
   that `file(1)` identifies.
2. Single-syscall "exit 42" probe runs under `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on the **in-hand real rv64 hardware**
   (hardware-gated over SSH like the aarch64 ssh-pi check) — the
   non-negotiable cross-OS self-host gate, on real silicon.
5. `[release].cross_bins` in `cyrius.cyml` gets a `cycc_riscv64` entry.

> **Sequencing note**: the v6.7.x language arc sits ahead of it — that arc
> may surface consumer pressure or findings that re-order what
> lands first, and only the user pivots focus
> ([[feedback_priority_bottom_to_top]] / slot discipline). Premise-check the
> rv64 substrate at arc entry per [[feedback_premise_check_at_slot_entry]].

---

## What comes after v6.x

**v6.x is not capped at 6 minors.** Per user direction 2026-06-11, the cycle
**grows further before any major bump** — v6.4.x (CLOSED at **.86**) → v6.5.x
(CLOSED at **.73**) → **v6.6.x (ACTIVE at .12: the value-form `Result`/`Option`/`Either`
flip SHIPPED at v6.6.0 with the 8-repo ecosystem migration, then a repair window and a repair
batch through `.12`; `.13` repairs memory and the reported issues, and tooling closes the minor —
see [roadmap.md](roadmap.md))** → **v6.7.x (the language arc: real traits, the missing common
features, `const fn`, the bounds-checked mode, trait-bounded generics; set 2026-10-01)** →
**v6.8.x/v6.9.x (RISC-V rv64, re-homed there 2026-10-01)** are the current pins, and more v6.x
minors can still follow (consumer pressure, language refinements, platform work)
before v7.0.0. v7 is *further out* than the original
"6 minors" framing implied; don't treat the tail as the cycle's hard end.

v7.x scope is open. Known commitments per CLAUDE.md "Version
lives in `VERSION` + `--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
  Future major bumps run `version-bump.sh` and ship; no rename,
  no downstream sweep, no vidya `cc?` residue.
- **Prior-major slot rotates at v7.0.0**. **cc3 was already dropped at
  v6.1.0** (corrected 2026-06-10 — the v6.0.0 cut should have rotated
  cc3→cc5 but didn't, leaving cc3 a stale prior-PRIOR; v6.1.0 fixed it).
  The prior-major slot now holds **cc5** (the last v5.x top compiler,
  5.11.69). At v7.0.0 it rotates to the last v6.x `cycc` — same binary
  name, so the slot effectively retires (no rename bridge). [Earlier
  drafts here and in roadmap-future.md said "cc3 drops at v7.0.0" — that
  was the RM-05 contradiction with CLAUDE.md; fixed.]

### Usability / adoption readiness (added 2026-06-10; reframed 2026-06-11)

**Whether v7 is a *full public* release is an open question** (user 2026-06-11:
"sovereign and usage — whether its full public is still in question"). Sovereign
+ usable is the committed direction; a public launch ("Cyrius ONE" book +
installer aimed at strangers) is **NOT a fixed gate**. So treat the debt below
as **usability/adoption readiness** — worth paying to make the toolchain
pleasant for more users (the existing ecosystem included) — and de-coupled from
any committed public-launch date. The deep-dive surfaced it
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)):

- **Licensing (LEGAL-01) — a hard blocker *if/when* it goes public** (and worth
  resolving regardless). The GPL-3.0-only stdlib is *source-included* into every
  consumer binary with no Runtime-Library-Exception → arguably forces GPL on all
  downstream binaries; and `sigil.cyr:533` elects the GPLv2-only leg of dual
  BSD/GPLv2 code (GPLv2-only is GPL-3-incompatible). Needs legal review + an
  RLE-style linking-exception decision.
- **Trust-story prerequisites (CVE-12/13/20/21) — RESOLVED.** Sovereign
  release signing (`cyrsign` Ed25519, .31) + integrity/pinning (.30) +
  **seed→cycc derivation** (`build/cycc` is machine-derivable from the 29 KB
  seed, byte-identical, 2026-06-20). The shipped `cycc` is now seed-derived
  (no longer a blob disjoint from the seed chain), releases are signed, deps
  are commit-pinned. The sovereignty story holds.
- **Diagnostics — ✅ the error-reporting half SHIPPED in v6.4.x.** This bullet used to
  read "errors are first-error-exit with no column/excerpt". Both halves are gone:
  **v6.4.60** added column + source-excerpt/caret on every error (~452 sites routed
  through `_err_head`), and **v6.4.62** replaced first-error-exit with panic-mode
  multi-error recovery that never hangs or crashes on hostile input. **v6.4.77** then
  made the reserved-word diagnostic name the token you hit (all **67** of them) instead
  of `got unknown`.
- **Debug-info (DWARF) — still absent** (re-verified 2026-08-07 at v6.5.10:
  `grep -rni dwarf src/ cbt/ programs/` → **0**), and crash-localization is still
  x86-ELF-only. **This is 6.x-line work, NOT a v7 item** — DWARF is codegen, and per the
  placement rule nothing codegen is ever parked to 7.x. It sits under this heading only
  because the *adoption* framing surfaced it; the slot belongs in a 6.x minor or
  roadmap.md's potential backlog. Unpinned today; no consumer has filed.
- **stdlib-reference** covers **65 of 99** `lib/*.cyr` modules (`docs/stdlib-reference.md:1501`,
  re-derived 2026-08-07; this line read "~65/88" while the live module count is **99**, so the
  gap it describes was understated by 11 modules). Docs work, so this one genuinely can ride
  the public-release track.

Beyond that, v7.x is open territory for **book + legal content**. Likely candidates: the
manuscript itself, the licensing decision, and whatever public-release invariants come with
them.

> ⛔ **CORRECTED 2026-08-07 — this paragraph used to end by parking "toolchain improvements
> (LSP / formatter / linter evolution)" and "agnos v2.0 alignment" at 7.x.** Both are
> **PLACEMENT RULE violations** and both are hereby **re-homed to the 6.x line**:
> - **LSP / formatter / linter evolution** — `cbt/`-resident tooling that reads and rewrites
>   cyrius source. The two cyrlint gates are a bullet in [roadmap.md](roadmap.md)'s *potential
>   backlog* (re-pinned 2026-10-06 — the "named W2 fold-in slot" this line cited had gone with
>   the v6.5.x slot list); the rest belongs there too, unscheduled but 6.x. (Live evidence that this is real 6.x work, not a far-future aspiration: v6.5.7's
>   entry notes the LSP flags `sys_chdir` on every `programs/checks/main.cyr` edit, and v6.5.8
>   shipped fixes to five `cyrius` verbs.)
> - **agnos v2.0 alignment** — the syscall peer, i.e. runtime/ABI work, and the single most
>   active reactive generator in the whole cycle (`#97 chan_op` minted v6.5.8, `CH_ENDOW`
>   v6.5.9). It rides the reactive windows, exactly as agnos 1.5x alignment does today.
>
> This is the **third and fourth** instance of the identical pattern in this file — DWARF and
> incremental compilation were the first two, corrected at the v6.4.82 closeout. The far-future
> label is how real work stops being scheduled.
