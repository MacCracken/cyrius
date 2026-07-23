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

## Closeout checklist + ledger

The **runnable** checklist we tick — and **record** — before every `x.Y.0` / `x.0.0`
bump; the operational counterpart to the [Cycle-close shape](#cycle-close-shape) above.
The durable *rationale* for each step lives in [`CLAUDE.md`](../../CLAUDE.md) "Closeout
Pass"; this is the checkbox version + the **per-closeout ledger** so drift is visible
across cycles. Copy the block into a new ledger entry and tick as you go. Ship the
closeout as the last engineering patch of the current minor (e.g. `6.4.NN` before `6.5.0`).

**Mechanical gates (fail-fast) — `sh scripts/release-gate.sh`**
- [ ] Self-host fixpoint byte-identical · seed-derive (`seed→cybs→cycc`) byte-identical
- [ ] check.sh all-green (record N) · cross-OS **ecb + cass + pi** [+ **ach** for the Intel-Mac tail] `SELFHOST_OK`+`LIBTEST_OK` on REAL hardware · bench recorded (self_compile ms + cycc B)

**Judgment passes** (where bugs hide — see CLAUDE.md items 4–8)
- [ ] Heap-map audit · dead-code audit (record floor) · refactor pass · code-review pass · cleanup sweep

**Compliance / external**
- [ ] Security re-scan (full audit every 2–3 minors) · downstream `cyrius.cyml` pins → the released tag

**Docs (silent-rot prevention)**
- [ ] CHANGELOG / roadmap / `state.md` current · vidya refresh (CLAUDE.md item 11 — language/field_notes/impl/deps + version cross-check)
- [ ] **Backlog re-triage (rot sweep)** — verify open `issues/` + `proposals/` resolved-status against **LIVE code**, not the file's own claim; archive resolved; re-pin deferrals in order (finish-out items soonest, big arcs after the queue is clean). **Enforce: no codegen/runtime in 7.x → 6.x line or the `roadmap.md` "potential backlog."** Mark stale-shipped watching entries SHIPPED. Keep the open dir lean (~10–12). See `feedback_no_codegen_parking_in_v7`.

### Closeout ledger (newest first)

One entry per minor/major closeout — gate counts + notable judgment findings + follow-ups
spawned. A ledger, not prose: it makes the rot visible (stale entries, growing dead-code
floor, a re-triage that keeps re-pinning the same item).

<!-- TEMPLATE — copy for each closeout:
### vX.Y.0 closeout — YYYY-MM-DD
- Gates: check.sh NNN · cross-OS ecb/cass/pi green · self_compile NNN ms · cycc NNN B · dead-code floor NN fns
- Judgment / compliance: <findings, or "clean">
- Backlog re-triage: N archived, N re-pinned — <notes>
- Follow-ups spawned: <issues / patches>
-->

- _**v6.4.x → v6.5.0 closeout — pending** (mid-minor at 6.4.72; run this block at the `6.4.NN`
  close). Interim: a 2026-07-11 backlog re-triage archived 4 (drishti-shift .46, EFI-enrollment
  .48, uefi-signing + cx-CLI proposals) and re-pinned the then-12 open issues into the roadmap.md
  "Deferral backlog — pinned order." Since then the .63–.72 band shipped (agnos GPU-syscall band
  #82–#91 contiguous, bayan 1.2.1 f64 JSON round-trip, sandhi 1.9.1 getpeername fold, `cyrius
  coverage` project-`src/`-scope fix) and the f64/fmt_hex/sys_reboot/agnos-GPU/getpeername/
  coverage/thread-local issues archived — leaving **9 open issues** as of 2026-07-23. Note the
  function-visibility (`pub`/`private`) arc has been MOVED OUT of 6.4.x to the v6.5.0 opener
  (user 2026-07-22)._
- _v6.3.x → v6.4.0 and earlier: full gate detail predates this ledger — canonical in
  [CHANGELOG.md](../../CHANGELOG.md) + [completed-phases.md](completed-phases.md)._

Memory pin: `feedback_cycle_close_shape`.
