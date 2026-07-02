# CYRIUS_IR=3 fixpoint optimizer: cascade over-elimination (deep, NOT the bite-1 class)

**Filed:** 2026-07-02 (v6.3.28, after the buffer + opcode-aliasing fixes exposed it)
**Severity:** N/A for default builds (CYRIUS_IR=3 is opt-in experimental; default codegen is
byte-identical — differential 306/306). Blocks CYRIUS_IR=3 self-hosting a byte-correct cycc.
**Component:** `src/main.cyr` IR=3 fixpoint driver (~1899-1956) + `src/common/ir.cyr`
`ir_const_fold` / `ir_dce_capped` / `ir_dead_store_capped` / `ir_lase` / `ir_apply_lase`.

## Context

v6.3.28 fixed the two failures that stopped CYRIUS_IR=3 from compiling cycc AT ALL:
the IR node buffer overflow (relocate + 1M cap) and the EVADDR_X1 opcode-aliasing SIGILL
(new opcode IR_LOAD_ADDR_G_X1). CYRIUS_IR=3 now compiles cycc (exit 0, 279787 nodes) and
**27/30 sampled tcyr pass under IR=3**. This issue is the residual: 3/30 fail
(`alloc_str_extras`, `alloc_collections` → SIGSEGV 139; `bigint` → hang) because the IR=3
optimizer miscompiles them.

## Root characterization (bisected, deterministic)

For `alloc_str_extras` (minimal-ish repro; default exit 0):

| optimizer config (CYRIUS_IR=3) | output md5 | exit |
|---|---|---|
| all passes OFF (`FOLD_OFF=1 LASE_OFF=1 DCE_CAP=0 DSE_CAP=0`) | `4de26f…` | **0 (correct)** |
| const_fold ONLY | `4de26f…` | 0 |
| LASE ONLY | `4de26f…` | 0 |
| DCE ONLY (uncapped) | `4de26f…` | 0 |
| dead_store ONLY (uncapped) | `4de26f…` | 0 |
| **all passes ON** | `f4391f…` | **139 (SIGSEGV)** |

**No single pass breaks it — only the four combined.** This is a **cascade / fixpoint-
interaction over-elimination**: each pass is individually sound on this input, but their
combined `IR_ELIMINATED` marks (all applied together by the final `ir_apply_lase` NOP-fill)
remove an instruction that is live once the *other* passes' eliminations are also in effect.
Classic multi-pass soundness gap: pass A marks X assuming Y stays; pass B marks Y assuming X
stays; both marks land. `all-off == IR=1 == a working (if +32 KB) binary`, so it is NOT the
dual-mode recording — it is the fixpoint transform interaction.

This is categorically DEEPER than the v6.3.28 bite-1 bug (a bounded opcode/register-model
mismatch fixable by one classifier edit). Fixing it needs the fixpoint's mark-interaction made
sound — e.g. re-derive liveness against the *post-mark* IR each iteration, or make each pass's
elimination criterion account for other passes' pending marks, or apply+recompute per pass
rather than batching all marks into one final `ir_apply_lase`.

## Bisection infrastructure added (v6.3.28, kept — matches the DCE_CAP/DSE_CAP methodology)

`CYRIUS_FOLD_OFF=1` skips `ir_const_fold`; `CYRIUS_LASE_OFF=1` skips `ir_apply_lase`
(`src/main.cyr` IR=1 block, default 0 → all passes run; IR-gated → default byte-identical).
With `CYRIUS_DCE_CAP` / `CYRIUS_DSE_CAP` this gives full per-pass on/off + cap bisection.

## Not on the perf arc's critical path

The perf arc (regalloc / copy-prop / cross-BB DSE) needs: (1) IR builds for cycc — DONE
(v6.3.28 bug 2); (2) sound ANALYSIS — the v6.3.27 `ir_liveness_cfg` cross-BB fixpoint + spill
detection, which emit zero code and are sound; (3) sound NEW transform passes built on (2).
It does NOT need the OLD experimental fixpoint transforms (const_fold/LASE/DCE/dead_store)
correct — those are opt-in and can stay disabled. So this cascade bug is experimental-optimizer
hygiene, separable from the perf arc. Recommendation: build the perf arc's new passes on the
sound analysis substrate; schedule the fixpoint-cascade cleanup as its own effort if/when the
old transforms are wanted in production.
