> **v6.5.35 UPDATE — the REGALLOC half of this file is now SHIPPED; what remains is the
> RE-EMIT substrate (Wall 1 + Wall 2) only.** Band F landed cross-BB register allocation
> WITHOUT the `ir_lower_all` re-emit path this file has always named as its prerequisite —
> which disproves the dependency for the regalloc half specifically. The picker time-shares
> registers today: `RA_SCAN_LOOPS` (`src/backend/x86/decode.cyr`) finds backward edges and
> `_ra_loop_extend` (`parse_fn.cyr`) extends intervals over loop bodies. ⛔ **Two things in
> this file's framing were wrong and must not be re-derived from it**: (1) the roadmap's
> "the cross-BB defect is ONE line" was HALF the story — that line is a deliberate v5.6.22
> guard and reverting it alone fails **69 of 282** corpus tests; the unnamed second blocker
> was a LIFETIME assignment cap of 5. (2) The `_disp_adj` consolidation figure ("57 sites,
> 44 helper-replaceable") is wrong in both halves — `_disp_adj` does not exist under that
> name, and the shape it described is **37** sites.
>
> ⚖️ **Still open here, and genuinely unshipped:** `ir_lower_all` re-emit (Wall 1) and the
> local-access opcode model + `IR_SWITCH` CFG completion (Wall 2). ⭐ **Also inherited from
> band F: the VECTOR REGISTER CLASS is unbuilt** — the picker's byte matcher recognises only
> REX.W mov to/from `[rbp+disp32]`, so no xmm/ymm local is a candidate at all. That is now
> band G's opening, not this file's. ✅ Band E (v6.5.34) separately took the IR=3 divergence
> count to **0**. See CHANGELOG [6.5.35], [6.5.34].

> **v6.5.2 UPDATE, RE-VERIFIED LIVE ON 6.5.10 (2026-08-07) — Wall 3 is CLOSED; Walls 1 and 2 still
> hold.** This file's line "CYRIUS_IR=3 still miscompiles real programs" is **no longer true**: the
> const_fold/jump-span bug is fixed and **IR=3 self-hosts a byte-identical cycc** (see
> `archived/2026-07-02-ir3-fixpoint-cascade-overelimination.md`, resolved at v6.5.2). ⛔ **Wherever
> the body below still says otherwise — §Wall 3 and step 3 of the productionization list — it is
> STALE prose contradicting this header; the header is right.** Measured again today on all three
> programs the body names: `alloc_str_extras`, `alloc_collections` and `bigint` each exit **0**
> under `CYRIUS_IR=3` *and* by default, and each IR=3 binary differs from its default build (so the
> mode really ran). Still blocking, all re-derived today:
> `ir_lower_all` (`src/common/ir.cyr:361`) has **zero callers**; `IR_SENABLE(S,2)` — record-only /
> re-emit mode — is **never activated** (only mode 1, at `main.cyr:1514` and `main_win.cyr:715`);
> there are **24** `IR_RAW_EMIT` recording sites in `src/backend/x86/emit.cyr` (64 mentions
> repo-wide, 13 of them in `ir.cyr` itself), not the "~15 in parse_*.cyr" this file claims —
> `parse.cyr` and `parse_expr.cyr` have **one each**; and `ir_build_edges`
> (`src/common/ir.cyr:~1401`) still handles only `IR_JMP` / `IR_JMP_BACK` / `IR_JCC`, giving
> `IR_SWITCH` a single fall-through edge, so the CFG remains incomplete for a regalloc rewrite.

# IR substrate productionization — the whole IR-optimizer perf arc gates on it (→ v6.5.x)

**Status:** 🟡 **OPEN** — the capability is genuinely unshipped; re-verified against live code on
cycc **6.5.10**, 2026-08-07. `ir_lower_all` still has **zero** callers (`grep -rn 'ir_lower_all' src/`
→ one definition at `ir.cyr:361` plus one prose mention at `:37`, no call site), so Wall 1's re-emit
path is still dark. **Wall 3 is closed** — see the header; do not read this Status as endorsing the
stale Wall-3 body.
**Placement:** **v6.5.26–.28 — band E, Slot 3 'IR substrate productionization'. THE SPINE OPENS HERE.** Widened from 2 releases to 3: this slot has been budgeted 2 twice and spent 0 both times.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⛔ FIVE CORRECTIONS. (1) **The residual is 11 of 271, not '10 of 260'** (full-corpus default-vs-IR=3 run 2026-08-14). (2) **3 of the 11 are NOT miscompiles** — they print `error: IR block table full` from `src/common/ir.cyr:274` (`if (bi >= 32768)`); a one-constant raise clears all three, which SETTLES this file's standing 'unverified, do not assume' note. (3) **v6.5.21 ADDED one**: `tests/tcyr/crossos/multi_return.tcyr` is IR=3-broken (`IR=1` exit 0, `IR=2` exit 0, `IR=3` exit 2 → the OPTIMIZER erasing the `movq xmm0↔rax` unbox, not the recorder). (2) and (3) are pulled FORWARD to band B (.23), so this slot opens facing **7 pre-existing miscompiles**, not 11. (4) ✅ **Wall 3 stays CLOSED, re-verified at 6.5.21** — an IR=3-built cycc (1,225,704 B, +57 KB, so the mode genuinely ran) compiles src/main.cyr to a binary `cmp`-identical to build/cycc. Do not reopen. (5) **DRIFTED CITES:** `ir_lower_all` :361→**:368** (still ZERO callers); `IR_SENABLE` :1514/:715→**main.cyr:1526 / main_win.cyr:693**, both mode 1, and 5 of 7 forks never call it; live `_IR_REC0(S, IR_RAW_EMIT)` sites are **48** (x86 26 · aarch64 13 · cx 7 · parse 1 · parse_expr 1), not the 24 claimed.

> **STATUS (2026-07-07): re-scoped — the original framing is materially stale; the
> CAPABILITY is still open and correctly homed at v6.5.x.** Corrections:
> - **Wall 3** (`CYRIUS_IR=3` can't compile cycc) — **FIXED v6.3.28** (compiles: exit 0,
>   279,787 nodes; derive 5/5). No longer a wall.
> - **Wall 1** (the `ir_lower_all` re-emit rewrite is *mandatory*) — **disproved** as a red
>   herring; the named home slot v6.3.29 shipped callee-saved frame-trim instead.
> - The live `CYRIUS_IR=3` **correctness** remnant is carried by the sibling issue
>   [`2026-07-02-ir3-fixpoint-cascade-overelimination.md`](2026-07-02-ir3-fixpoint-cascade-overelimination.md).
> - This issue now tracks the **perf-substrate** residual (Wall 2 opcode/local-access model
>   + the deferred regalloc/copy-prop/DSE passes) for the **v6.5.x Performance-Quality arc**
>   (roadmap_6.md's v6.5.x entry cites both this file and the sibling). Kept OPEN — the
>   passes are real, unshipped work; the dead `CYRIUS_IR=3` helpers (D1) fold in here too
>   ([`2026-07-07-v6415-closeout-residuals.md`](2026-07-07-v6415-closeout-residuals.md)).


**Filed:** 2026-07-02 (during v6.3.27 — cross-BB regalloc arc opening)
**Expanded:** 2026-07-02 (after the v6.3.28 cross-BB DSE attempt — implemented, corpus-tested, REVERTED)
**Severity:** N/A (deferred capability, not a bug). **Blocks the entire IR-level half of the perf arc — regalloc rewrite, copy propagation, AND cross-BB DSE.** Scheduled for its own slot in the **v6.5.x** Performance-Quality arc (superseded from v6.3.29 — see STATUS header).
**Component:** `src/common/ir.cyr` (IR pipeline emit model + local-access opcode model).

> **Bottom line:** the `CYRIUS_IR=3` optimizer is opt-in **experimental scaffolding**, not a
> verified-correct mode. THREE independent walls (below) each block a production perf pass.
> A dedicated slot (**v6.5.x IR substrate productionization**) must make `CYRIUS_IR=3`
> production-correct FIRST; only then can regalloc / copy-prop / cross-BB DSE land. The
> v6.3.28 x86 byte-peephole ships perf in the meantime by NOT touching this substrate.

## Context

v6.3.27 opened the perf arc (AR-04 decision: gated IR-level substrate). The plan was a
cross-BB linear-scan register allocator that promotes `PUSH`..`POP` stack round-trips into
free callee-saved registers (rbx/r12-r15). Adversarial review of the design found the
**rewrite half is unimplementable on the current emit model** — a silent-miscompile hazard
if attempted.

## Wall 1 — in-place patch emit, no re-emit (blocks the regalloc REWRITE)

The `CYRIUS_IR` pipeline does **not** re-emit code from the IR. Confirmed in code:

- `CYRIUS_IR=1|2|3` all set `IR_ENABLED == 1` (dual mode): x86 bytes are emitted **during
  parsing**, simultaneously with IR recording (`src/main.cyr`).
- The optimizer (`CYRIUS_IR=3`) runs **after** bytes are committed and **patches the codebuf
  in place**: `ir_apply_lase` NOP-fills a node's byte span (`ir.cyr`), `ir_const_fold`
  overwrites within the same span. Every existing pass only ever **shrinks in place**
  (0x90 fill) or overwrites within the existing byte span — never grows, never relays out.
- `ir_lower_all` (the mode-2 "re-emit from IR" driver) is **defined but never called** —
  dead scaffolding. `IR_ENABLED == 2` is never activated.

Register promotion **grows** instructions: `push rax` (0x50, 1 byte) → `mov r12, rax`
(REX.W, 3 bytes); `pop rcx` (1 byte) → `mov rcx, r12` (3 bytes). There is no room to patch
3 bytes into a 1-byte slot — doing so overwrites the following instruction, silently
miscompiling every arithmetic expression (regalloc targets the ubiquitous binop shuttle).

## Wall 2 — RAW_EMIT is pervasive → sound cross-BB DSE is inert, unsound miscompiles (v6.3.28)

A full cross-BB dead-store-elimination pass was implemented and corpus-tested in the v6.3.28
attempt, then **reverted**. A store `[rbp-N] = v` can only be safely killed if EVERY read of
local N is known. Two fatal facts make that impossible on the current IR:

- **`IR_RAW_EMIT` (op 98) is pervasive.** The compiler wraps many direct-emit blocks in
  `IR_RAW_EMIT` markers (parse_*.cyr, ~15 blocks since v5.6.14). Inline asm inside a RAW_EMIT
  span can read/write **any** local slot via `[rbp-N]`, bypassing address-taken analysis — so a
  **sound** DSE must treat RAW_EMIT as reading all locals and **bail**. Even a trivial
  `fn f(n){ var x=99; if(n>0){…} }` emits `IR_RAW_EMIT`. Result: a sound DSE bails on essentially
  every real function → fires ~never → **zero perf value**.
- **An unsound DSE (ignoring RAW_EMIT) miscompiles.** The v6.3.28 attempt hit a cascade of
  distinct silent miscompiles, each a local-access the analysis didn't model:
  - `IR_CALL_INDIRECT` (op 66) reads a **spill local** (arg1) holding the callee pointer —
    closures / `callptr` → SIGSEGV.
  - SIMD `f64v2` / `f64v4` **multi-slot** locals: a value at index x occupies slots x..x+3, but
    per-slot tracking kills a store to a non-base slot; the wide `&r`/vector access uses opcodes
    the address analysis reports as `taken=0` → SIMD → SIGSEGV.
  - `IR_STORE_PARM` (op 94) writes a local via arg2 — an unmodeled def.
  - The CFG is **incomplete**: `IR_SWITCH` (op 74) records only a fall-through edge (missing
    case-target liveness); unresolved JMP/JCC edges are absent → cross-BB liveness is wrong.

  Enumerating every local-access opcode to make it sound is unbounded whack-a-mole; the clean
  fix is a **complete local-access opcode model** (part of Wall-3's productionization), not a
  per-opcode patch chase.

## Wall 3 — CYRIUS_IR=3 can't compile real programs (pre-existing, unrelated to any pass)

> ⛔ **THIS WALL IS CLOSED — v6.5.2. The paragraph below is kept only as history; do not act on
> it.** The sibling that owned it,
> [`archived/2026-07-02-ir3-fixpoint-cascade-overelimination.md`](archived/2026-07-02-ir3-fixpoint-cascade-overelimination.md),
> is RESOLVED and archived: the root cause was *not* a fixpoint cascade but `ir_const_fold` alone —
> `EJCC`/`EJMP0` (`src/backend/x86/jump.cyr`) recorded their IR node AFTER emitting bytes, so
> const_fold's NOP-fill span ran 5–6 bytes long and erased the jump. `CYRIUS_IR=3` now self-hosts a
> **byte-identical** cycc.
>
> **Live re-measurement, 2026-08-07 on 6.5.10** (whole corpus, default vs `CYRIUS_IR=3`, comparing
> both compile and run exit codes): **10 mismatches of 260** — `const_chained_multiply_fold` (0/1),
> `field_name_shadows_global` (0/139), `float` (0/3), `math_inverse_trig` (0/2),
> `math_pack_integration` (0/1), `subword_signed_load` (0/1), `types` (0/3), plus three that fail at
> **IR=3 compile time** rather than at run time — `large_input`, `large_source`,
> `preprocessor_past_cap`. Against the archived sibling's closing figure of 8-of-253:
> `switch_dispatch` has since gone green and the three compile-time failures are new (they are
> capacity tests, so they may be an IR-recording-table limit rather than a miscompile — **unverified,
> do not assume**). ⚠ `roadmap.md` Slot 3 still says "the 8 residual mismatches"; the live number is
> **10 of 260**.
>
> *(Original v6.4.82 text, now stale and disproved: "alloc_str_extras and alloc_collections exit 0
> by default and 139 (SIGSEGV) under CYRIUS_IR=3; bigint still hangs (124)". All three exit 0 under
> IR=3 today.)*

Both the v6.3.27 AND the (reverted) v6.3.28 cycc produce **0 bytes** compiling cycc itself under
`CYRIUS_IR=3`, and **SIGILL (132)** on `derive_str_deserialize`. This is pre-existing and
independent of any optimizer pass. It is exactly why `scripts/differential.sh` only tests
`default` + `CYRIUS_DCE=1`, never `CYRIUS_IR=3` — the mode is not verified-correct. Any
production perf pass gated behind `CYRIUS_IR` inherits this brokenness until it is fixed and the
mode is added to the differential corpus.

## What v6.3.27 shipped instead (the safe analysis substrate)

- **Cross-BB liveness fixpoint** (`ir_liveness_cfg`): live_out[BB] = ∪ live_in[succ],
  iterated to convergence; per-BB `ir_live_in`/`ir_live_out` u64 bitmaps. Pure analysis,
  emits zero code → byte-identical default path. The reusable substrate the copy-prop
  and cross-BB DSE passes (now homed at v6.5.x) consume.
- **Spill-interval detection** (`_ir_find_spill_intervals`): counts clean intra-BB
  `PUSH`..`POP` intervals (the future allocation targets); abandons any span containing an
  opaque stack/reg op. Analysis-only — records nothing, allocates nothing.
- Gate `tests/gates/ir-opt/ir_liveness_cfg.sh`; both gated under `CYRIUS_IR`.

## The productionization slot — v6.5.x (superseded from v6.3.29, see header) (prerequisite for regalloc / copy-prop / cross-BB DSE)

A dedicated slot (**v6.5.x IR substrate productionization**, roadmap.md) must make
`CYRIUS_IR=3` production-correct — all three walls — BEFORE any IR-level perf pass:

1. **Wire + prove the IR re-emit path** (Wall 1). Activate `ir_lower_all` (mode-2: record IR,
   skip direct emit, then lower the whole IR to fresh bytes) and prove it emits **byte-identical**
   output to today's dual-mode direct emit across the differential corpus (`differential.sh`).
   This changes how ALL code is emitted on the IR path — high-risk. Only on this model can an
   instruction grow.
2. **Build a complete local-access opcode model** (Wall 2). Model every op that defs/uses a
   local — `IR_CALL_INDIRECT`(66, arg1 spill), `IR_STORE_PARM`(94, arg2), SIMD multi-slot
   locals (index x ⇒ slots x..x+3), the SIMD/wide address ops so `taken` is correct — and either
   drive down `IR_RAW_EMIT`(98) pervasiveness or give it a precise read/write set. Complete the
   CFG for `IR_SWITCH`(74, case targets) + unresolved JMP/JCC edges. Goal: liveness-based passes
   are SOUND without bailing on every function.
3. **Add `CYRIUS_IR=3` to the differential corpus and close the residual mismatches** (Wall 3 —
   *mostly done*). The "0 bytes" and the SIGSEGV/hang symptoms this step used to name are both
   gone: v6.5.2 fixed `ir_const_fold`'s jump-span erasure and IR=3 now self-hosts a byte-identical
   cycc. What is left is the tail measured live 2026-08-07 — **10 of 260 tcyr** differ in exit code
   between default and IR=3 (7 at run time, 3 at IR=3 *compile* time; named in the Wall 3 block
   above) — plus the still-unbuilt `CYRIUS_IR=3` axis in `differential.sh`, without which the mode
   stays unverified on every cut. Gate `tests/gates/ir-opt/ir3_fold_jump_span.sh` (mutation-proven, shipped
   v6.5.2) is the model.

**Then** (a later v6.5.x slot) land the IR-level passes on the sound substrate:

- **Regalloc rewrite** — linear-scan over `_ir_find_spill_intervals`, assign a callee-saved reg
  consulting the liveness + `_cur_fn_regalloc` reservation (claim only regs EREGALLOC actually
  reserves — do NOT rely on the liveness fixpoint bits 2-6, which have no def/use model), rewrite
  PUSH/POP → mov reg via the re-emit path, wire the used regs into EREGALLOC prologue/epilogue
  save/restore.
- **Copy propagation** (`ir_copyprop_recon`) + **extended cross-BB DSE** (`ir_extdse_recon`) —
  now sound given step 2's opcode model + the v6.3.27 `ir_liveness_cfg` liveness-out set.

Each pass: gated proof, differential byte-SAFE, measure the self_compile win.

**Do NOT re-attempt copy-prop / cross-BB DSE / regalloc on the raw substrate** — the v6.3.28 DSE
attempt proved it is inert-if-sound / miscompiling-if-not. The v6.3.27 `ir_liveness_cfg` +
`_ir_find_spill_intervals` analysis substrate is in place and correct (emits zero code), but it is
the CEILING of what is shippable until the v6.5.x substrate slot lands. The IR-INDEPENDENT x86 byte-peephole
(v6.3.28, default direct-emit stream) is the perf win that ships without this substrate.
