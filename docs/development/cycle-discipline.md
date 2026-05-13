# Cyrius Cycle Discipline — Durable Operating Principles

**Purpose** — Evergreen guidance that applies to every minor cycle,
extracted from accumulated v5.9.x / v5.10.x / v5.11.x feedback. These
principles outlive any single cycle and are referenced from
[roadmap.md](roadmap.md) and [`CLAUDE.md`](../../CLAUDE.md). When a
new principle emerges from a cycle's lessons, it lands here once it's
proven durable across at least one subsequent cycle.

---

## Slot acceptance principle (revised at v5.10.0)

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

## Bottom-to-top priority (v5.10.1 user direction)

When choosing between competing slots, walk the stack
bottom→top: agnosys (baseOS/kernel) > stdlib runtime services >
specialized libraries (hisab) > applications > optimization-only.
Memory pin: `feedback_priority_bottom_to_top`.

## Premise-check at slot entry

Pins go stale; empirically test the gap before committing scope.
v5.10.45 (struct-byval scope re-cast) and v5.10.49 (PE pin
debunked) both saved 1-3 slots of mis-aimed work by 15-minute
empirical re-tests. Memory pin:
`feedback_premise_check_at_slot_entry`.

## Cross-host smoke wrapper discipline (v5.10.49 lesson)

When SSH-ing to cass (Win64) to capture an exit code, the obvious
`cmd /c "prog.exe & echo %errorlevel%"` shape expands `%errorlevel%`
at **parse time** and falsely reports `exit=0`. Use either:
- `cmd /v /c "prog.exe & echo exit=!errorlevel!"` (delayed expansion)
- `.bat` indirection (newlines split parse passes; what
  `_pe_exit_gate` in `programs/check.cyr` always used correctly)

Memory pin: `feedback_windows_errorlevel_test_wrapper`.

## Cycle-close shape

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

Memory pin: `feedback_cycle_close_shape`.
