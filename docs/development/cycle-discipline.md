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
- [ ] **4** cross-OS on all **four** hosts, sequentially — **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — each `SELFHOST_OK` **and** `tests/tcyr/crossos/` `LIBTEST_OK` on REAL hardware
- [ ] **5** bench recorded (self_compile ms + cycc B) — non-blocking, but the number goes in the CHANGELOG

`ach` is a **first-class gate host, not a tail** — it was added to this loop at v6.4.59 after
the Intel-Mac toolchain rotted ungated for ~2.5 minors (`scripts/release-gate.sh` step 4 is a flat
`for H in ecb ach cass pi`). Step 4 runs the `tests/tcyr/crossos/` SUBDIRECTORY (the `vr01_`
filename glob it used until v6.5.11 is retired) and **prints its own coverage** —
"corpus: N of M tcyr selected by subdir" — so a subset can no longer read as authoritative;
`CYRIUS_CROSS_OS_FULL=1` runs the whole corpus instead (opt-in: ~75 s on ecb, and the blind
region still holds known platform gaps, so defaulting to full would wedge every release behind
a separate arc).

**Judgment passes** (where bugs hide — see CLAUDE.md items 4–8)
- [ ] Heap-map audit · dead-code audit (record floor) · refactor pass · code-review pass · cleanup sweep
- [x] ⭐ ~~**v6.5.x carries one heap-map item BY NAME: reclaim `0x4D9D000 output_buf [16777216]`.**~~
      **✅ ALREADY RECLAIMED — verified at the v6.5.73 closeout, not taken on this entry's word.**
      `preprocess_out` now spans `0x459D000..0x5D9D000` (24 MiB), so 0x4D9D000 sits INSIDE it; the
      band was absorbed when that cap grew, and `heapmap.sh` parses 102 regions with zero overlaps
      and no region at that address. ⚠ The item below it was right that stale references linger —
      five were found and fixed at the closeout (a doubled `— was 0x4D9D000 — was 0x4D9D000`, a
      brk boundary quoted as `0x00000..0x4D9D000`, and a `pfx` scratch address that has been
      `_output_base` since v6.4.51). **A checklist entry is a claim like any other: re-derive it.**
      Nothing has written that band since **v6.4.52**, when output became a 1 GiB off-heap
      `alloc(1073741824)` — but it is still documented as a live 16 MB region in the heap map of
      **all five** `src/main*.cyr` forks, and the map is **machine-read** by `tests/gates/memory/heapmap.sh`, so
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

### v6.6.x → v6.7.0 closeout — 2026-10-06 (ran 6.6.20)

> ⚠ **DRAFT — written by the docs lane before the merge.** Every `⟨INTEGRATION: …⟩` marker is a figure only
> the merged tree can give; fill it, then delete this note. The audit figures below are from the closeout
> audit at `e696746d` (the 6.6.20 slot open), not from the merged tree.

- **How it ran**: one audit of the whole checklist at `e696746d` — 17 passes (heap, dead code, refactor, nine
  code-review lenses over the minor's diffs, cleanup, security, downstream, vidya, backlog) — produced **141
  findings** (6 P0 · 9 P1 · 35 P2 · 65 P3 · 26 cosmetic); every one of the **44 P0–P2 bugs** was then
  re-proven by an independent verifier before any fix started. They were fixed in **28 parallel worktree
  lanes** (14 `src/`, 14 cbt / lib / gates / docs), merged once, and the gate run once on the merged tree
  (user, 2026-10-06: "find ways to parallelize as much of the fixes as possible"). The user promoted three
  backlog items into the release the same day (BACKLOG-01/02/03).
- **Gates** ⟨INTEGRATION: the merged tree's `scripts/release-gate.sh` — check.sh N of N shell gates produced
  a result, F failed, S named SKIPs · self-host fixpoint + ARM lockstep (after `cyrius pulsar`) · seed-derive ·
  cross-OS ecb / ach / cass / pi `SELFHOST_OK` + `LIBTEST_OK` · self_compile N ms · cycc N B (`.text` N B) ·
  `cycc-native-aarch64` N B⟩. At the slot open: cycc **1,586,184 B** (`.text` 1,405,464) · `cycc-native-aarch64`
  1,323,400 B · **372** shell gates under `tests/gates/` (376 registered, `sh scripts/check.sh --registry | wc -l`, with the 4 `scripts/` gates — three `*-gate.sh` and `differential-smoke.sh`) · **482** `.tcyr` (197
  `crossos/`) · api-surface 5,827 · self_compile 923 ms (the 6.6.19 gate).
- **Heap map** (HEAP-01…12): `heapmap.sh` **102 regions, 0 overlaps** — but it parses `src/main.cyr` only;
  run over the six fork maps the same parser FAILS (the three aarch64 maps 1 overlap each, `main_win` 3,
  x86 Mach-O and cx parse 0 regions). **v6.6.x added no fixed heap offset** (151 distinct `S + 0x…` literals,
  the identical set at 6.5.73) and consumed no FREED hole (18; ~15.7 KB free in the scalar band). It found
  **two silent miscompiles from unbounded writes into fixed regions** — the `#ifdef` nesting stack (HEAP-01)
  and the 64-entry `use` alias table (HEAP-02) — plus the 17th function-like macro dropped silently
  (HEAP-03). Dead bands: the 3 MB codebuf band at 0x41A000 on six forks, `ir_edges`, `pub_flags`. Caps under
  25 % headroom: WPJS 12 % (cycc under IR=3), `jump_src` saturated in one cycc fn, IR nodes at 97 % on a
  16-fold build. Stale heap facts in vidya and ADR-003 refreshed (HEAP-11). ⟨INTEGRATION: the merged map's
  region count, and whether the fork-map drift (HEAP-05…10) closed⟩.
- **Dead code** (DEAD-01…10): floor at the slot open **73 fns / 36,937 B** on x86 (aarch64 cross 149, cx
  151, PE 108, aarch64 native 149, arm64 macOS 153, x86 macOS 138); v6.5.73's 77 / 37,345 B reproduced on
  its own tree. One fn went dead this minor (`_gvar_bytes_named`). Classified: 17 remove, 6 live only in
  another fork (the arm64 Mach-O writer, **15.8 KB dead in every x86-family compiler**), 50 keep (49 stdlib
  + `TS_PEEKLINE`). Every removal measured in scratch first: floor → **50 fns / 10,082 B**, cycc −28,912 B.
  ⟨INTEGRATION: the merged floor — `note: N unreachable fns (N bytes)`⟩.
- **Refactor + code review**: the dominant shape was **a fix that reached one sibling and not the others**
  — `--syntax-only` in 2 of 7 forks (so `cyrius lint` refuses valid files on pi / ecb / ach, REFACTOR-01),
  `cyrius deps`' own `[deps.NAME]` walker outside 6.6.17's one manifest reader, three environment readers of
  which one still reads 8 KB, three leaf-name rules for one token; and in the code review, CVE-40's bound
  applied to the macro body but not its arguments (LEX-EXPR-01), 6.6.3's continue fix one nesting level
  short (RPF-01), CVE-78's fix on one of `fmt`'s two paths (RLM-04/05), the 6.6.10 alloc census missing
  `_tn_alloc_a(` (NET-02). Silent miscompiles found: RPF-01 (continue through a `while`), RPF-02 (a `: f64`
  fn's tail call, bare `return;` or fall-off hands back a stale xmm0), RPD-01 (inline replay drops a `*T` pointer step),
  HEAP-01 / HEAP-02, REVBE-01 (DCE compaction on `kernel;` and `CYRIUS_WX=0`). P0 outside the compiler:
  **CBT-01** — a cloned repo's `[package] cyrius` pin was path-traversed into an `execve` (code execution
  on ANY verb).
- **Security re-scan**: `~/.cache/cyrius-6620/audit/security.md` — SEC-01…SEC-09, ids proposed from
  CVE-79. SEC-01 = CBT-01 and SEC-09 = CBTB-02 are in lanes. ⚠ **SEC-02…SEC-08 (two P1: `[build] output`
  reaching a shell / cmd.exe unquoted; `update` / `deps --lock` writing through checkout symlinks) never
  reached `findings.json`** — the security pass's structured result was cut off — so no lane carries them.
  ⟨INTEGRATION / user: placed, fixed, or deferred with a named reason⟩. CVE ids are assigned at integration
  (the next free id is 79) and the September audit file + CLAUDE.md counters move in the same commit.
- **Downstream pins** (DOWNSTREAM-01): **clean** — 126 manifests read from git HEAD: 6.6.2 ×56, 6.6.3 ×10,
  6.6.6 ×29, 6.6.9 ×2, 6.6.10 ×3, 6.6.11 ×3, 6.6.12 ×1, 6.6.14 ×8, 6.6.18 ×12 (the folds), 6.6.20 ×1 (cyrius);
  gpumm is not a git repo (working copy 6.6.2). **None below 6.6.2; no working copy differs from its HEAD.**
  All 12 folds pin 6.6.18, their latest tags equal `docs/ecosystem.md`'s rows, and the 11 tracked `dist/`
  bundles `cmp` identical to `lib/` (yantra's `dist/` is gitignored). The 66 repos on 6.6.2 / 6.6.3 are
  consumers — filings only; they bump when they choose to. Every repo named in roadmap.md *Sibling follow-ups*
  exists in `~/Repos`.
- **Vidya** (VIDYA-01…14, lane d-vidya): coverage of the minor's features is good (refreshed at every tag
  6.6.13–6.6.19); the rot is in entries written before the release that changed them — `types.cyml`'s
  structural facts stamped 6.6.1 (14 stale facts), and **nine older claims that now describe false
  behaviour**, each disproved by a compiled probe. ⟨INTEGRATION: confirm the d-vidya lane's refresh landed⟩.
- **Backlog re-triage** (BACKLOG-00…14): all **61** *Potential backlog* bullets re-verified against the tree —
  **55 live** (5 with a materially wrong claim, corrected in place), **2 shipped**, **2 partly shipped**, **2
  obsolete**, and **1 removed item that recurred** (the race-gate flake, root-caused). The audit scored a 3rd
  as shipped — the `/tmp/cyrius-<pid>` dirs, "cleaned, 2 left" — and they were back to 49 the same evening; it
  stays a live bullet (see *Met during the closeout*). The v6.7.x candidates
  moved into roadmap_6.md § v6.7.x (two were duplicates there); the DCE arc's spec moved there ahead of the
  rotation; roadmap-future's NFKC row struck as shipped and its cyrlint gates re-pinned (they pointed at a slot
  that had not existed for a month). **0 open issues · 2 open proposals** (both correctly open). Placement
  rule clean: nothing codegen or runtime parked at 7.x.
- **Docs** (CLN-04/06/07/08/09/12): the public figures had **frozen at v6.6.1 for nineteen releases** (README,
  faq, platform-status, size-comparisons, stdlib-modules — re-derived); doc-health marked a v6.3.0 README
  Fresh (re-derived row by row); `handoff.md` was stale again and is **archived** (state.md is the handoff);
  CLAUDE.md and the guide still prescribed `vr01_` tests (which opt OUT of the cross-OS leg); 58 + 5 comment
  pointers and 4 deleted-script references re-pointed.
- **Met during the closeout, outside the findings**: the 37 qemu core dumps (5.6 GB) in the repo root were
  already gone by the time their lane looked (CLN-14); `/tmp/cyrius-*` went 962 → 2 at the audit and was
  back to **49** by 19:34 the same day (every pid dead, **33** non-empty — a killed `cyrius check`'s
  temporaries). CLN-03 reaps only EMPTY dead-pid dirs under `$TMPDIR`, so these stay: the class is a live
  roadmap.md backlog bullet, not fixed ⟨INTEGRATION: re-count `/tmp/cyrius-*` after the merged check.sh⟩.
- **Follow-ups spawned** ⟨INTEGRATION: every finding a lane skipped or could not pack, with its named reason;
  DEAD-10, HEAP-12, LEX-EXPR-04 went to the backlog by decision (DECISIONS.md); the backlog's proposed order
  (B)–(F) is the user's to promote⟩.

### v6.5.x → v6.6.0 closeout — 2026-09-06 (ran **v6.5.73**)

- **Gates**: check.sh **240** passed / 0 failed (was 150 at the v6.5.0 closeout — +90 this minor)
  · shell gates on disk **139** (DERIVED) · self-host fixpoint + seed-derive byte-identical ·
  cross-OS ecb/ach/cass/pi `SELFHOST_OK` + crossos `LIBTEST_OK` on REAL hardware ·
  self_compile **~722 ms** · cycc **1,235,272 B** (`.text` 1,079,648) · **dead-code floor 77 fns
  / 37,345 B** — and as of v6.5.72 `CYRIUS_DCE=1` genuinely REMOVES them (1,198,408 B, −36,864).
- **Heap map**: the item this checklist carried BY NAME — reclaim `0x4D9D000 output_buf` — was
  **already done** and the entry was stale. `preprocess_out` spans `0x459D000..0x5D9D000` (24 MiB)
  and 0x4D9D000 sits inside it; `heapmap.sh` parses **102 regions, 0 overlaps, 0 warnings**.
  ⚠ Its warning about lingering references was right: **five stale mentions fixed**, including a
  doubled `— was 0x4D9D000 — was 0x4D9D000`, a brk boundary quoted as `0x00000..0x4D9D000`, and a
  `pfx` scratch address that has been `_output_base` since v6.4.51.
  **A checklist entry is a claim like any other — re-derive it.**
- **Judgment / compliance**: code-review pass clean — no raw x86 encodings in shared frontend
  files, and all three whole-program-registry overflow flags are consulted (the pass declines
  rather than half-repairing). Security: the re-scan cadence had **silently slipped inside
  CLAUDE.md** — it pointed at the 2026-07-27 audit (CVE-32…36, cycc 6.4.82) for the whole minor
  while `docs/audit/2026-09-03-security-audit.md` (CVE-38…42, cycc 6.5.45) existed. Corrected,
  **and the "next CVE is 39" note with it: it is 43.**
- **Downstream pins**: 125 repos declare a `cyrius` pin; **0 are at ≥ 6.5.60**, 110 sit in
  6.5.0–6.5.59 and 15 below 6.5.0. Recorded as a finding — re-pinning 125 repos is cross-repo
  coordination, not a closeout edit.
- **Vidya**: `types.cyml`'s "Live structural facts" entry read **cycc 6.5.10 / 1,141,792 B** — 62
  releases stale, the exact silent rot this step exists for. Refreshed against derived counts.
- **Backlog re-triage**: **1 open issue + 3 proposals**, down from 5 issues at the start of
  `.70`. Archived this run: `async-fn-arity-7-silent-miscompile`,
  `stiva-stackless-coroutines-interactive-exec`, `derive-accessors-auto-inline`,
  `dce-nop-fill-does-not-eliminate`. All three proposals premise-checked against LIVE code and
  genuinely unshipped (`const fn` and `#embed` have no implementation; the manifest proposal
  shipped only its first slice). Placement rule clean — **nothing codegen/runtime parked in 7.x**.
  The single open issue, `sock-send-result-allocates-per-call`, is **pinned to v6.6.0 by the
  maintainer**, not deferred.
- **Follow-ups spawned**: none. The v6.5.x technical queue is empty.

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
