# The TS frontend arena overlaps `tok_types` + 1.6 MB of `tok_values` — safe only by a temporal invariant

**Discovered:** 2026-07-27, v6.4.x closeout heap-map audit.
**Severity:** **Medium** (latent, not live). **Filed rather than fixed in v6.4.81 for one concrete
reason:** the fix needs ~14.2 MB contiguous, which does not exist below the arena end (`0x7400000`),
so it is a **brk / heap-LAYOUT change** and CLAUDE.md requires the two-step bootstrap for those.
Bundling that into the tail of a release whose full gate had already run is how the seed gets broken.
Everything about it that *could* be fixed safely — the false documentation — was fixed in .81.

## The overlap

TS base is `S + 0x298B000` (`src/main.cyr` TS_LEX / TS_PARSE / TS_JS_EMIT call sites);
`src/frontend/ts/lex.cyr:60` sets `TS_HEAP_SIZE = 0xD81000` (14,159,872 B). Arena spans
`0x298B000..0x370C000`. The map has `0x2D7C000 tok_types [8388608]` and `0x357C000 tok_values [8388608]`:

```
awk 'BEGIN{print (0x357C000-0x2D7C000)+(0x370C000-0x357C000)}'   → 10027008
```

Root cause is arithmetic: `0x298B000 - 0x207B000` = 9,502,720 = **exactly** the 9.06 MB the v5.11.68
reorg shrank the heap by. The TS base is still the *pre-.68* fixup end — the one literal that reorg
missed.

## Why it is not currently corrupting anything

`--lex-ts`, `--parse-ts` and `--emit-js` all `SYS_EXIT` (`main.cyr:843/904/919`) before `PREPROCESS`
and `LEX`, so the token arrays are never populated in TS mode. That is a **temporal** invariant
guarding a **spatial** collision, held by nothing but call ordering, and `tests/heapmap.sh`
structurally cannot see it because the base is a code literal rather than a map entry.

Anything that lets a `.ts` unit coexist with cyrius lexing — a cbt `--emit-js` fold, a mixed unit, a
future TS-in-`.cyr` include — silently overwrites `tok_types`. `lex_pp.cyr:377` already records this
exact failure once: "the first cut relocated … to a FIXED 0x198000 and clobbered gvar_toks → CI SIGILL".

## Already done in v6.4.81 (do not redo)

- The heap map's claimed "13.3 MB TS frontend reservation" — which **does not exist** — is corrected in
  all three comment blocks in `src/main.cyr`, with the real base, real size, the overlap arithmetic,
  and the temporal invariant written down.
- The stale `0x1D0B000` base (which lands *inside* `fixup_tbl`) is corrected in `src/main.cyr` and
  `src/frontend/ts/lex.cyr:20,35`.
- `tests/heapmap.sh` can now see `ir_nodes`/`ir_cp` and the unit-suffixed scratch regions (94 → 100),
  so the auditor no longer reports a phantom free gap above `ir_live_out`.

## What is left

1. Move the TS arena above the token arrays and extend `brk` (`syscall(SYS_BRK, S + 0x7400000)` at
   `src/main.cyr:720`) — **two-step bootstrap**, per CLAUDE.md's heap-change rule.
2. Add `ts_heap` to the heap map as a real region once it no longer overlaps.
3. Add a gate asserting the TS entry points exit before `LEX`, so the invariant is *checked* rather
   than merely documented, for as long as it is load-bearing.

## Acceptance criteria

- `sh tests/heapmap.sh` lists `ts_heap` as a real region with **0 overlaps**.
- Mutation-proven: move `ts_heap` back over `tok_types` and confirm the gate goes RED.
- `--lex-ts` / `--parse-ts` / `--emit-js` still work; self-host + seed-derive byte-identical after the
  two-step bootstrap.

## Placement

v6.5.x, alongside the IR/regalloc substrate work that already touches heap layout. **Not 7.x.**
