# v6.4.15 closeout residuals — R2 (PE prologue refactor) + D1/D2 (dead IR/decode code)

**Status:** 🟡 **OPEN for D1/D2 only** — R2 shipped v6.4.26. **Re-verified against live code on cycc
6.5.10, 2026-08-07** — nothing has moved, and every line number below is still exact:

```sh
grep -rn '\bir_lower_all\b\|\bir_dce\b\|\bir_dead_store\b\|\bir_emit2\b\|\bIR_BB_ID\b\|\bIR_EDGE_FROM\b' src/
#   ir.cyr:37  (prose)  :234 IR_BB_ID  :314 ir_emit2  :341 IR_EDGE_FROM
#   :361 ir_lower_all  :1014 ir_dce  :1263 ir_dead_store        → definitions only, zero call sites
grep -rn '\bCLASSIFY_CF\b\|\bCF_TARGET\b' src/
#   decode.cyr:12 / :19 (header comment)  :238 CLASSIFY_CF  :277 (cross-ref)  :279 CF_TARGET
```

**D1** — `ir_lower_all`, `ir_dce`, `ir_dead_store`, `ir_emit2`, `IR_BB_ID`, `IR_EDGE_FROM` each have
**1 definition and 0 call sites**; `_ir_lower_node`'s single reference is from `ir_lower_all`, so it
is dead transitively. **D2** — `CLASSIFY_CF` / `CF_TARGET` (`src/backend/x86/decode.cyr:238` / `:279`)
have **no consumer at all**. Both still dead exactly as filed.
⚠ Note `ir_dce` and `ir_dead_store` are one-line wrappers over `ir_dce_capped` / `ir_dead_store_capped`,
which **are** live — remove the wrappers, not the capped forms.
**Placement:** **v6.5.26 — band E**, the opening bite of Slot 3.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⛔ **THIS FILE'S CLAIM THAT 'EVERY LINE NUMBER BELOW IS STILL EXACT' IS FALSE AT 6.5.21.** Six of the eight D1 cites drifted +7/+13, re-derived: `ir_lower_all` :361→**:368** · `IR_BB_ID` :234→**:241** · `ir_emit2` :314→**:321** · `IR_EDGE_FROM` :341→**:348** · `ir_dce` :1014→**:1027** · `ir_dead_store` :1263→**:1276**. D2's `decode.cyr:238`/`:279` ARE still exact. D1 and D2 both re-verified genuinely dead (definition-only, zero call sites); R2 confirmed shipped. ⚖️ D2 needs a maintainer call that has outlived three closeouts: wire `CLASSIFY_CF`/`CF_TARGET` into a decoder-based CFG pass, or delete them.

> **R2 SHIPPED v6.4.26** (2026-07-08) — `_pe_fd_to_handle_rcx` extracted from `EWRITE_PE` +
> `EREAD_PE` (`src/backend/x86/emit.cyr`); `EREAD_PE` byte-identical, `EWRITE_PE` re-emitted;
> verified by cass PE self-host (reads via `EREAD_PE`, writes via `EWRITE_PE`) + pi/ecb
> `SELFHOST_OK`. **D1/D2 (dead IR/decode) REMAIN OPEN → v6.5.x IR-substrate slot.** This issue
> stays open for D1/D2; close it when they land.

**Filed:** 2026-07-07 (extracted from the now-archived
[`2026-07-03-v6345-closeout-audit-backlog.md`](archived/2026-07-03-v6345-closeout-audit-backlog.md)
so the three conscious deferrals are real issues, not CHANGELOG prose).
**Severity:** P3 — hygiene / dead-code; no correctness or consumer impact.
**Component:** `src/backend/x86/emit.cyr`, `src/common/ir.cyr`, `src/backend/x86/decode.cyr`.

## Context

The v6.4.15 absorber-band cleanup landed the L1/L2 latent-bug guards and the
R1/R3/R4/R5 parallel-copy consolidations (all byte-identical on all four targets;
CHANGELOG [6.4.15]). Three items were **deliberately deferred**, not because they're
low-value but because each carries codegen/substrate risk that a closeout slot
shouldn't absorb. They lived only as a CHANGELOG "Deferred" bullet; this issue makes
them real.

## Residual work

### R2 — extract the PE GetStdHandle fd-resolution prologue (codegen-risk refactor)
`EWRITE_PE` (`emit.cyr:~955`) and `EREAD_PE` (`emit.cyr:~1196`) hand-duplicate the
fd→HANDLE prologue (`cmp rax,2; ja .direct; neg; sub; GetStdHandle`). This is the EXACT
block the v6.2.43 VR-01 fix had to re-apply to `EWRITE_PE` after `EREAD_PE` already had
it — a proven repeat-fix hazard. Extract `_pe_fd_to_handle_rcx` called by both.
**Not byte-identical** (a parametrized collapse changes emission on the PE path) → needs
a full **cass** PE-codegen verification, which is why it was held out of the byte-identical
closeout. Land it when the next PE-codegen change touches cass anyway.

### D1 — remove dead `CYRIUS_IR=3` substrate helpers
`src/common/ir.cyr`: `ir_lower_all` / `_ir_lower_node` / `ir_dce` / `ir_dead_store` /
`ir_emit2` / `IR_BB_ID` / `IR_EDGE_FROM` have ZERO live callers, unreachable on all
targets (DCE already NOPs their bytes → no shipped cost). Removal is byte-identical-safe,
BUT `ir.cyr` is the delicate IR substrate → belongs in the **v6.5.x IR-substrate slot**
(roadmap_6.md), not a closeout. Fold into that slot's opening cleanup.

### D2 — remove or wire the speculative disassembler CFG API
`src/backend/x86/decode.cyr:~225`: `CLASSIFY_CF` / `CF_TARGET` (the v4.4.5 CFG companion
to `DECODE_LEN`) is never consumed — the DCE call-graph is byte-scan-based, not
decoder-based. Either wire it into a real decoder-based pass (v6.5.x IR work) or remove.

## Roadmap home

R2 → next PE-codegen touch (opportunistic; no dedicated slot). D1/D2 → the **v6.5.x
IR-substrate productionization** slot (roadmap_6.md), which already owns the IR cleanup.

## Acceptance

R2: `_pe_fd_to_handle_rcx` extracted, cass PE self-host + exit-code guards green. D1/D2:
the dead helpers removed (or D2 wired), `note: N unreachable fns` floor drops accordingly,
cycc self-hosts byte-identical.
