# Cyrius Development Roadmap — v6.6.x and beyond

**Scope — FORWARD ONLY: v6.6.x, v6.7.x/v6.8.x, and the shape of what follows v6.x.**
This file is deliberately *not* a record of shipped work and *not* a spec for the current
minor. Re-scoped 2026-07-29: it previously carried full per-minor detail for v6.0.x through
v6.4.x plus a duplicate v6.5.x specification, which made it 1,592 lines of mostly-history and
gave the v6.5.x plan two homes that had already drifted apart.

**Where the other content went, and where to add new content:**

| You want | Go to |
|---|---|
| The **current active minor** (v6.5.x) in slot-by-slot detail | [roadmap.md](roadmap.md) — the single authority. Do **not** re-add a v6.5.x spec here. |
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
> below still carries its correction note for that reason.

## See also

- [roadmap.md](roadmap.md) — the **current active minor** (v6.5.x), slot-by-slot. Rotates at
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

Reference points, **updated at the v6.4.82 close** — this line used to call v5.11.x's
70 slots "longest in history", which two v6.x minors have since passed. By closing
patch number: **v6.0.x ran to .91** and **v6.4.x to .82**, then v5.11.x (.69),
v6.2.x (.52), v5.7.x, v6.3.x (.45), v6.1.x (.41). Every v6.x minor except v6.1.x has
exceeded the "30-40 range" target — the working rule (user 2026-06-10) is *"no worries
about patch size, just hardening and adding features"*, and large minors are the norm,
so read the budget as a planning aid, not a cap.

---
---

## Closed minors — v6.0.x through v6.5.x

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
| v6.5.x | **ACTIVE** — see [roadmap.md](roadmap.md) | — |

Every close number above was verified against `CHANGELOG.md` on 2026-07-29 (the per-minor max
`## [6.Y.N]` heading), not carried over from the previous text.

**One item salvaged out of the deleted v6.2.x detail, because it was never built and was
quietly archived unfixed:** bare-metal deliverable **#4, the forbidden-module check**.
`CHANGELOG [6.3.4]` states plainly that it did not ship; `grep -rn forbidden src/ cbt/` finds
one unrelated comment and `host_only|kernel_ok` finds nothing. Its issue was bulk-renamed into
`issues/archived/` on 2026-07-10 (commit `79bae42f`, an 8-file rename) with **no resolution
banner**. It is carried as an open question in [roadmap.md](roadmap.md) — either implement it or
strike it from the acceptance list, but it must not sit as a shipped-arc acceptance criterion.

---

## v6.5.x — ACTIVE MINOR — specified in [roadmap.md](roadmap.md)

**This file intentionally holds no v6.5.x specification.** It used to hold a parallel one
(committed shape, acceptance anchor, slot estimate), and the two copies drifted: the roadmap.md
table and this file's five committed items had diverged on scope, and the acceptance anchor's
second clause — *"self_compile stays inside a stated budget"* — existed only here, so the budget
was never actually stated anywhere.

All of it now lives in [roadmap.md](roadmap.md): the slot sequence, the reactive windows, the
carried-over v6.4.x items, the five committed items (substrate walls · cross-BB regalloc **with
a vector register class, planned in from the start rather than retrofit** · register-resident
vector-value ops incl. true 256-bit AVX for f64v4 under `simd_has_avx2()` and wrapper inlining ·
copy-prop + cross-BB DSE · the self-compile growth-tax audit), and the acceptance anchor
(the svara formant bench closing to single-digit-× of the Rust baseline, plus the self_compile
budget — carried there as an explicit open question owed to the maintainer).

**When v6.5.x closes:** add one row to the table above, and do not copy its detail back here.


## v6.6.x — Language Ergonomics ("best of the best" imports)

**Theme set 2026-07-07 (user, horizon session).** RISC-V rv64 — previously this
minor's theme — was **re-homed again to v6.7.x/v6.8.x** (below): hardware is in
hand, but the user is deliberately holding a 7th platform while *"still heavy
quality and ergonomic improvements [are] on the horizon."* v6.6.x instead takes
the modern-language feature imports that fit the assembly-up identity — no GC,
no hidden control flow you can't disassemble. **The WHOLE list is committed; the
bring-in is STAGGERED** — bulk lands here, and **1–2 low-risk early risers may
pull forward into the v6.4.x/v6.5.x absorber bands** if slots open (surfaced at
slot entry, never folded in silently).

The list (ROI order; design decisions inside each item at arc-open):

1. ~~**`defer` / scope-exit**~~ — **✅ ALREADY SHIPPED (v3.8.0), struck 2026-07-29.** This
   sat here as pending v6.6.x work for a language feature that has existed since v3.8.0
   (token 106, `src/common/util.cyr:948`; the guide documents it running at function exit).
   Verified by running the compiler: a `defer { … }` block executes after the body
   (`A` then `D`). Do not re-plan it.
2. **`const fn` — the const-eval ladder, option 1** (Zig-comptime-lite / Rust) —
   proposal staged:
   [`proposals/2026-07-05-const-eval-comptime.md`](proposals/2026-07-05-const-eval-comptime.md).
   Reuses the existing `ir_const_fold` fixpoint; retires generator-program
   ceremony for computed constants. The narrow `#phf` builtin (proposal option 3)
   is the fallback if scope balloons. **Early-riser candidate.**
3. ~~**Per-block scoping + shadowing**~~ — **✅ ALREADY SHIPPED, struck 2026-07-29.**
   Verified by running the compiler: a block-local is **not** visible outside its block
   (`if (1) { var inner = 5; } return inner;` → `error: undefined variable`), and nested
   shadowing works (`var x = 1; if (1) { var x = 5; return x; }` → exits **5**, the inner
   binding). What remains — and is *correct*, not a footgun — is that a **same-scope**
   redeclaration is a hard error (`duplicate variable`); that is the documented rule in
   CLAUDE.md, not an unshipped item. So the "no-redecl footgun class" this row promised to
   retire is half shipped and half intentional.
4. **Opt-in bounds-checked memory mode** (`CYRIUS_BOUNDS` / `#bounds`) — designed in the
   v6.3.x plan (that section was removed from this file in the 2026-07-29 re-scope; the design
   is in `CHANGELOG.md`'s v6.3.x band and the archived plan), never shipped — verified live:
   `CYRIUS_BOUNDS` / `#bounds` / `_bounds_check` all find **0** hits in `src/`. The sanitizer
   story that makes footguns findable at their source. OFF by default
   (assembly-up: raw stores stay raw in release builds).
5. **Trait-bounded generics** — the post-monomorphization ceiling. **DEMAND-GATED
   tail**: pulls in only if consumer pressure materializes by arc-open; fix the
   **multi-type-param struct-type-arg residual** first (single-tparam struct type-args
   shipped v6.3.38 B1/B2 + v6.3.39 B3; the residual is only the mixed multi-tparam combo)
   ([`issues/archived/2026-07-02-generic-fns-struct-type-args-monomorph-abi.md`](issues/archived/2026-07-02-generic-fns-struct-type-args-monomorph-abi.md)).

**Explicitly NOT imported** (decided 2026-07-07): borrow-checker-style lifetimes
(wrong fit for the trust model + single-pass design), a general const-eval VM
(proposal option 4), exceptions of any kind.

---

## v6.7.x or v6.8.x — Platform: RISC-V rv64

**Theme**: the 4th platform peer — first-class RISC-V 64-bit. **Re-homed here
from v6.6.x at the 2026-07-07 horizon session** (user: hardware in hand, *"can
do it now but have been hesitant to add another platform with still heavy
quality and ergonomic improvements on the horizon … risc can be 6.7 or 6.8 arc
work"*) — the second deliberate deferral of the same shape as the first
(**re-homed from v6.2.x**, user 2026-06-27: *"6.6 is where we put it for now …
[I] don't want to worry about another platform until some of the other items in
the minors get ironed out"*). A **deferral of worry, not intent** — the point is
to let the v6.5.x perf-quality + v6.6.x ergonomics minors land before adding a
7th backend. Whether it takes 6.7 or 6.8 is decided at v6.6.x close (consumer
pressure may claim 6.7 first); the cycle is explicitly allowed to grow past 6
minors (see "What comes after v6.x" below).

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

> **Sequencing note**: v6.6.x is the *current tail pin* — the v6.3.x–v6.5.x
> arcs may surface consumer pressure or perf findings that re-order what
> lands first, and only the user pivots focus
> ([[feedback_priority_bottom_to_top]] / slot discipline). Premise-check the
> rv64 substrate at arc entry per [[feedback_premise_check_at_slot_entry]].

---

## What comes after v6.x

**v6.x is not capped at 6 minors.** Per user direction 2026-06-11, the cycle
**grows further before any major bump** — v6.4.x (CLOSED at .82) → **v6.5.x
(next: `pub`/`private` opener, then performance quality)** → **v6.6.x (language
ergonomics)** → **v6.7.x/v6.8.x
(RISC-V rv64, re-homed there 2026-07-07)** are the current pins, and more v6.x
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
- **Debug-info (DWARF) — still absent** (verified at the v6.4.82 close: zero `dwarf`
  references anywhere in `src/`, `cbt/`, `programs/`), and crash-localization is still
  x86-ELF-only. **This is 6.x-line work, NOT a v7 item** — DWARF is codegen, and per the
  placement rule nothing codegen is ever parked to 7.x. It sits under this heading only
  because the *adoption* framing surfaced it; the slot belongs in a 6.x minor or
  roadmap.md's potential backlog. Unpinned today; no consumer has filed.
- **stdlib-reference** covers ~65/88 modules — the rest need authoring. Docs work, so
  this one genuinely can ride the public-release track.

Beyond that, v7.x is open territory. Likely candidates: more language
refinements based on consumer pressure from v6.x ship; toolchain
improvements (LSP / formatter / linter evolution); agnos v2.0 alignment
if AGNOS's roadmap creates pull.
