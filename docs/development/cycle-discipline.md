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
  `_pe_exit_gate` — now `programs/checks/platform_win_macho.cyr`, since
  `programs/check.cyr` was split into `programs/checks/` — always used
  correctly: it scp's a `.bat` that echoes `exit=%ERRORLEVEL%` and runs it
  with `cmd /c`)

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
v5.10.50 absorbed the wrap-up + .49 PE debunk. **v6.4.x is the
cleanest recent instance of all three steps**: the engineering
band ran .80–.84, **v6.4.85** was the closeout-complete cut
(docs / ledger / handoff reconciled, cycc byte-identical to .84
at 1,112,464 B — no code change), and **v6.4.86** was the
fold-applied tag (sandhi 1.9.3 → 1.9.5, byte-identical vendor,
cycc unchanged because `lib/sandhi.cyr` is outside cycc's
include closure).

**The conditional third step really is conditional.** v5.11.x
was pinned here as "heap-map full reorg at v5.11.68
(engineering), conditional mabda 3.0 fold at v5.11.69" — the
mabda 3.0 fold was **dropped at user direction post-.67**, and
v5.11.69 shipped instead as the v5.x cycle-close doc / scripts /
vidya sweep (see CHANGELOG [5.11.69]). Neither outcome is a
deviation: `vN.M.K+1` either carries a fold or carries nothing
that needs engineering.

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

Five steps, fail-fast, in this order (`--quick` runs 1–3 only and is NOT release-ready):

- [ ] **1** self-host fixpoint byte-identical (and `build/cycc == cycc(src)`) · **2** seed-derive (`seed→cybs→cycc`) byte-identical
- [ ] **3** check.sh all-green (record N) — the gate checks check.sh's **exit status**, not just its `N passed, 0 failed` line, because the shell gates run *after* the check binary and its summary does not cover them
- [ ] **4** cross-OS on all **four** hosts, sequentially — **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — each `SELFHOST_OK` **and** VR-01 `LIBTEST_OK` on REAL hardware
- [ ] **5** bench recorded (self_compile ms + cycc B) — non-blocking, but the number goes in the CHANGELOG

`ach` is a **first-class gate host, not a tail** — it was added to this loop at v6.4.59 after
the Intel-Mac toolchain rotted ungated for ~2.5 minors (`scripts/release-gate.sh:108` is a flat
`for H in ecb ach cass pi`). Step 4 runs the `vr01_` glob and **prints its own coverage** —
"corpus: N of M tcyr selected by glob" — so a subset can no longer read as authoritative;
`CYRIUS_CROSS_OS_FULL=1` runs the whole corpus instead (opt-in: ~75 s on ecb, and the blind
region still holds known platform gaps, so defaulting to full would wedge every release behind
a separate arc).

**Judgment passes** (where bugs hide — see CLAUDE.md items 4–8)
- [ ] Heap-map audit · dead-code audit (record floor) · refactor pass · code-review pass · cleanup sweep
- [ ] ⭐ **v6.5.x carries one heap-map item BY NAME: reclaim `0x4D9D000 output_buf [16777216]`.**
      Nothing has written that band since **v6.4.52**, when output became a 1 GiB off-heap
      `alloc(1073741824)` — but it is still documented as a live 16 MB region in the heap map of
      **all five** `src/main*.cyr` forks, and the map is **machine-read** by `tests/heapmap.sh`, so
      the phantom is audited as real. The 2026-08-07 doc sweep fixed the *description* only and left
      the band RESERVED on purpose, so the overlap audit would not move mid-minor. Reclaiming it is a
      LAYOUT change → **two-step bootstrap**, and it belongs here, not in a patch.
      ⚠ `tok_types` briefly lived at this address and has since moved to `0x2D7C000`; grep for stale
      `0x4D9D000` references (vidya carried one) before freeing it.

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
- Gates: check.sh NNN · cross-OS ecb/ach/cass/pi green · self_compile NNN ms · cycc NNN B · dead-code floor NN fns
- Judgment / compliance: <findings, or "clean">
- Backlog re-triage: N archived, N re-pinned — <notes>
- Follow-ups spawned: <issues / patches>
-->

### v6.4.x → v6.5.0 closeout — 2026-07-27 → 2026-07-28 (ran **v6.4.80 → v6.4.85**, fold tag **v6.4.86**)

- **Gates**: check.sh **150** (was 147 at .72; +`lib_freshness`-era growth, +`_doc_stamp_currency_gate`
  and the `valform_simd_crosstarget` shell gate this cycle) · self-host fixpoint + seed-derive
  byte-identical · cross-OS ecb/ach/cass/pi `SELFHOST_OK` + VR-01 `LIBTEST_OK` on REAL hardware ·
  self_compile **622 ms** · cycc **1,108,368 B** · heap **100 regions, 0 overlaps** · corpus **251
  .tcyr** (verified by a per-file exit-code loop, not check.sh's grep summary) · api-surface **4749**.
  (Figures are the **.82** measurement. The band ran on to .85 at check.sh 150/0 and cycc
  **1,112,464 B**; see the five-release bullet below.)
- **Judgment findings** (all FIXED, not filed — see the feedback rule below):
  fourth `_cfo` rewind occurrence in `EMIT_OP_DISPATCH` (`p * 3 + 1` == 4; `add`/`sub` cleared the
  flag, `mul`/`div` never did) · CVE-32/33/34 three unbounded copies reachable from untrusted source
  · the heap map documenting `include_fname` at an address **no code has ever written** (0x190500
  vs the live unbounded 0x190400) so `heapmap.sh` validated a fiction for three minors ·
  `heapmap.sh` blind to **20.02 MB** of live heap (`ir_nodes` 16 MB, `ir_cp` 4 MB) because its size
  regex took a bare integer only, and mis-sizing `fn_param_struct_mask` as **5 bytes** off a trailing
  `issue [5]` · the Windows PE gates validating a **cycc 5.11.69** binary for the entire v6.x line ·
  value-form SIMD silently dropped on the PE/Mach-O **cross** paths since v6.4.31 · CVE-35/36 (23
  fixed `/tmp` literals in `cbt/`) · the TS arena overlapping `tok_types` + 1.6 MB of `tok_values`
  (10,027,008 B), safe only by a temporal invariant, now `alloc()`-backed.
- **Backlog re-triage**: verified all 11 open issues against LIVE code (not their own status text) —
  none resolved; two carried stale status text and were corrected. Archived the agnos #94/#95 filing
  as resolved. Open queue **11** + README, 3 proposals, 273 archived. Enforced the placement rule:
  DWARF debug-info and incremental compilation were parked at "v7-PARKED" in roadmap.md, contradicting
  the file's own rule ~200 lines above — moved back into the 6.x line.
- **Compliance**: new `docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36, plus CVE-37/38
  recorded as REFUTED so a future pass does not re-file them). `CLAUDE.md:164` had claimed the last
  full audit was "v5.0.1" — three minors stale; corrected.
- **Process fixes this cycle** (the durable output): `_doc_stamp_currency_gate` — a checklist entry is
  not a gate, proven by v6.4.77 fixing this rot class in `ecosystem.md`, adding a checklist item, and
  watching a row go stale again two releases later. And the feedback rule now in CLAUDE.md
  "Execution integrity": **an audit's output is FIXES, not a backlog** — this closeout initially
  filed four findings it could have fixed, growing the queue 11 → 15, and the user was right to
  reject that.
- **The closeout took FIVE releases, .80 through .85**, because each pass kept finding live
  bugs: .80 `1 - 2 + 3` == 5 · .81 the fourth `_cfo` occurrence + CVE-32/33/34 · .82 the
  closeout proper + the TS arena + agnos #94/#95 · **.83** intrinsics could not flank a
  TERM-tier operator (found by the .82 vidya sweep, by running the compiler against a
  documented claim) · **.84** `chan_try_send` + the non-blocking channel surface SIGSYS-ing on
  macOS (the new gate was the first `vr01_` ever to exercise channels there, and it caught
  both the new fn AND pre-existing breakage in `chan_try_recv`/`chan_close`).
  **.85** then carried no code at all — the closeout-complete cut that reconciled this ledger,
  `state.md`, `roadmap.md`, `doc-health.md` and `handoff.md`, cycc byte-identical to .84.
  **Three of those five were found by verification work, not by feature work.** That is the
  case for running these passes at all, and it is the number to remember next cycle.
- **Fold-applied tag: v6.4.86** — sandhi 1.9.3 → **1.9.5**, vendored byte-identical from
  upstream's committed dist (1.9.4 is the substance: `sandhi_server_recv_request` had one
  failure value and dispatched three distinct incomplete-request cases as if whole; now
  `-2` TOO_LARGE → 413, `-3` INCOMPLETE → 400, unsupported transfer coding → 501). cycc
  byte-identical — `lib/sandhi.cyr` is outside its include closure. api-surface 4752 → **4755**,
  0 removed. This is step 3 of the [Cycle-close shape](#cycle-close-shape) — the closeout proper
  is .80–.85, and .86 is the separate fold-applied tag, which is why the heading names both.
- **Follow-ups**: none deferred silently. Everything not fixed is filed with a NAMED reason.

- _v6.3.x → v6.4.0 and earlier: full gate detail predates this ledger — canonical in
  [CHANGELOG.md](../../CHANGELOG.md) + [completed-phases.md](completed-phases.md)._

Memory pin: `feedback_cycle_close_shape`.
