# IR substrate productionization — the whole IR-optimizer perf arc gates on it (→ v6.5.x)

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
**Severity:** N/A (deferred capability, not a bug). **Blocks the entire IR-level half of the perf arc — regalloc rewrite, copy propagation, AND cross-BB DSE.** Scheduled as its own slot **v6.3.29** (roadmap.md).
**Component:** `src/common/ir.cyr` (IR pipeline emit model + local-access opcode model).

> **Bottom line:** the `CYRIUS_IR=3` optimizer is opt-in **experimental scaffolding**, not a
> verified-correct mode. THREE independent walls (below) each block a production perf pass.
> A dedicated slot (**v6.3.29 IR substrate productionization**) must make `CYRIUS_IR=3`
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

Both the v6.3.27 AND the (reverted) v6.3.28 cycc produce **0 bytes** compiling cycc itself under
`CYRIUS_IR=3`, and **SIGILL (132)** on `derive_str_deserialize`. This is pre-existing and
independent of any optimizer pass. It is exactly why `scripts/differential.sh` only tests
`default` + `CYRIUS_DCE=1`, never `CYRIUS_IR=3` — the mode is not verified-correct. Any
production perf pass gated behind `CYRIUS_IR` inherits this brokenness until it is fixed and the
mode is added to the differential corpus.

## What v6.3.27 shipped instead (the safe analysis substrate)

- **Cross-BB liveness fixpoint** (`ir_liveness_cfg`): live_out[BB] = ∪ live_in[succ],
  iterated to convergence; per-BB `ir_live_in`/`ir_live_out` u64 bitmaps. Pure analysis,
  emits zero code → byte-identical default path. The reusable substrate v6.3.28 copy-prop
  and v6.3.29 cross-BB DSE consume.
- **Spill-interval detection** (`_ir_find_spill_intervals`): counts clean intra-BB
  `PUSH`..`POP` intervals (the future allocation targets); abandons any span containing an
  opaque stack/reg op. Analysis-only — records nothing, allocates nothing.
- Gate `tests/ir_liveness_cfg.sh`; both gated under `CYRIUS_IR`.

## The productionization slot — v6.3.29 (prerequisite for regalloc / copy-prop / cross-BB DSE)

A dedicated slot (**v6.3.29 IR substrate productionization**, roadmap.md) must make
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
3. **Fix CYRIUS_IR=3 compiling real programs + add it to the differential corpus** (Wall 3). Make
   `CYRIUS_IR=3` compile cycc (0 bytes today) and derive (SIGILL 132 today), then add a
   `CYRIUS_IR=3` mode to `differential.sh` so the mode is verified byte-correct on every cut —
   not experimental scaffolding.

**Then** (v6.3.30) land the IR-level passes on the sound substrate:

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
the CEILING of what is shippable until v6.3.29 lands. The IR-INDEPENDENT x86 byte-peephole
(v6.3.28, default direct-emit stream) is the perf win that ships without this substrate.
