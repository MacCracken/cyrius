# IR register-allocation rewrite is blocked on an IR re-emit path (deferred from v6.3.27)

**Filed:** 2026-07-02 (during v6.3.27 — cross-BB regalloc arc opening)
**Severity:** N/A (deferred capability, not a bug). Blocks the codegen half of the perf arc.
**Component:** `src/common/ir.cyr` (IR pipeline emit model).

## Context

v6.3.27 opened the perf arc (AR-04 decision: gated IR-level substrate). The plan was a
cross-BB linear-scan register allocator that promotes `PUSH`..`POP` stack round-trips into
free callee-saved registers (rbx/r12-r15). Adversarial review of the design found the
**rewrite half is unimplementable on the current emit model** — a silent-miscompile hazard
if attempted.

## The blocker

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

## What v6.3.27 shipped instead (the safe analysis substrate)

- **Cross-BB liveness fixpoint** (`ir_liveness_cfg`): live_out[BB] = ∪ live_in[succ],
  iterated to convergence; per-BB `ir_live_in`/`ir_live_out` u64 bitmaps. Pure analysis,
  emits zero code → byte-identical default path. The reusable substrate v6.3.28 copy-prop
  and v6.3.29 cross-BB DSE consume.
- **Spill-interval detection** (`_ir_find_spill_intervals`): counts clean intra-BB
  `PUSH`..`POP` intervals (the future allocation targets); abandons any span containing an
  opaque stack/reg op. Analysis-only — records nothing, allocates nothing.
- Gate `tests/ir_liveness_cfg.sh`; both gated under `CYRIUS_IR`.

## The deferred work

A dedicated later slot must, IN ORDER:

1. **Wire + prove the IR re-emit path.** Activate `ir_lower_all` (mode-2: record IR, skip
   direct emit, then lower the whole IR to fresh bytes) and prove it emits **byte-identical**
   output to today's dual-mode direct emit across the differential corpus (`differential.sh`).
   This changes how ALL code is emitted on the IR path — high-risk, must be its own slot.
2. **Then** land the register allocation + rewrite on the re-emit model (only there can an
   instruction grow): linear-scan over the `_ir_find_spill_intervals` output, assign a
   callee-saved reg consulting the liveness + `_cur_fn_regalloc` reservation (claim only regs
   EREGALLOC actually reserves — do NOT rely on the liveness fixpoint for bits 2-6, which have
   no def/use model), rewrite PUSH/POP → mov reg, wire the used regs into EREGALLOC
   prologue/epilogue save/restore. Prove differential byte-SAFE + measure the self_compile win.

Until (1) exists, the perf win from regalloc cannot land. The liveness substrate is in place,
so v6.3.28/.29 are unblocked independently.
