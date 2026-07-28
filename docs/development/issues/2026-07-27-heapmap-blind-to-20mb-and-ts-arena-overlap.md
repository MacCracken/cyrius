# `tests/heapmap.sh` is blind to 20 MB of live heap, and the TS frontend arena overlaps the token arrays by 10 MB

**Discovered:** 2026-07-27, by the v6.4.x closeout heap-map audit (CLAUDE.md item 4).
**Severity:** **High** — the gate that exists to catch heap collisions cannot see the regions most
likely to collide. v6.4.81 already shipped one live memory-safety bug (CVE-32) that survived three
minors of heap-map audits *because the map documented a region that does not exist*; these are the
rest of that class.
**Affects:** `tests/heapmap.sh`, `src/main.cyr`'s heap map (and the four other forks carrying it),
`src/frontend/ts/lex.cyr`.

## Part A — the auditor's size parser drops six live regions (20.02 MB)

`tests/heapmap.sh:49` extracts sizes with `while (match(line, /\[([0-9]+)\]/, arr))` — a **bare
integer only**. Every map line whose size is written with a unit suffix is silently skipped:

```
0x191800  lex_pp file-scratch        [16KB]
0x1FC000  PP #derive field-name scratch [8KB]
0x1FE000  PP #derive field-types     [8KB]
0x200000  PP #derive field-offsets   [2KB]
0x5E9D000 ir_nodes                   [16 MB]
0x6E9D000 ir_cp                      [4 MB]
```

All six are live (`grep -rn --include='*.cyr' 'S + 0x191800\|S + 0x1FC000\|S + 0x5E9D000\|S + 0x6E9D000' src/`
hits `lex_pp.cyr:2482,2494,2496,2497,2502` and the `ir.cyr` / emit paths).

Because `ir_nodes` and `ir_cp` are invisible, the auditor reports a **phantom ~21.4 MB free gap**
between `ir_live_out` (`0x5E9D000`) and `lexid_entries` (`0x7300000`) that is in fact fully occupied.
A future allocation placed "in the free space above the liveness arrays" would land inside `ir_nodes`
and **PASS the gate**.

Separately, `fn_param_struct_mask` is parsed as **5 bytes** — off by a factor of 13,107. Its map line
(`src/main.cyr:141`) reads `… _fnt_structmask (v6.3.36 issue [5]: bit N = …)` and the awk takes the
*last* bracketed number on the line, grabbing the issue number.

This is the same parser-hole class as the v5.5.40 bug `heapmap.sh`'s own header brags about fixing.
It is also the trap that bit the v6.4.81 fix: the first corrected `include_fname` map line carried the
old `0x190500 [256]` in an explanatory parenthetical, and the parser reported the region as 256 B
again. **The map is a machine-read format; prose belongs on continuation lines.**

## Part B — the TS frontend arena overlaps `tok_types` entirely + 1.6 MB of `tok_values`

`src/main.cyr:826,877,882,908,913,918` all pass `S + 0x298B000` as the TS heap base;
`src/frontend/ts/lex.cyr:60` sets `TS_HEAP_SIZE = 0xD81000` (14,159,872 B). So the arena spans
`0x298B000..0x370C000`. But the map has `0x2D7C000 tok_types [8388608]` and
`0x357C000 tok_values [8388608]`:

```
awk 'BEGIN{print (0x357C000-0x2D7C000)+(0x370C000-0x357C000)}'   → 10027008
```

Root cause is arithmetic and unambiguous: `main.cyr:386-388` records the brk-fixup end as `0x207B000`
"(post-v5.11.68 reorg; was `0x298B000` pre-.68)". The TS base **still is** the pre-.68 fixup end —
`0x298B000 - 0x207B000` = 9,502,720 = exactly the 9.06 MB that reorg shrank the heap by. The one
literal the reorg missed.

The documented reservation is also too small regardless: `0x2D7C000-0x207B000` = 13,635,584 B vs
`TS_HEAP_SIZE` 14,159,872 B — 524,288 B short. And a **third** number contradicts both:
`src/main.cyr:708-709` and `src/frontend/ts/lex.cyr:20,35` still say the base is `0x1D0B000`, which
is inside `fixup_tbl` (`0x107B000..0x207B000`).

**Not a live corruption today.** All three TS entry points (`--lex-ts`, `--parse-ts`, `--emit-js`)
`syscall(SYS_EXIT, …)` at `main.cyr:843/904/919`, before `PREPROCESS` (`:1107`) and `LEX` (`:1166`),
so the token arrays are never populated in TS mode. But that is an **undocumented temporal invariant
guarding a 10 MB spatial collision**, and `heapmap.sh` structurally cannot see it — the TS base is a
code literal, not a map entry. Anything that makes a `.ts` unit coexist with cyrius lexing (a cbt
`--emit-js` fold, a mixed unit, a future TS-in-`.cyr` include) silently overwrites `tok_types`. This
is precisely the failure `lex_pp.cyr:377` already records: "the first cut relocated … to a FIXED
0x198000 and clobbered gvar_toks → CI SIGILL".

## Fix

**Part A** — shell-only, no compiler impact:
- Extend the matcher at `tests/heapmap.sh:49` to accept `[N]`, `[N KB]`, `[N MB]` and scale.
- Take the size as the **first** bracketed number after the region name, not the last (or reword
  `src/main.cyr:141` to put the size in the size column).
- Give the 8 fn-table lines that carry no size an explicit one.

With both fixes the gate reports **108 regions, 0 overlaps, 0 warnings** (verified offline against
the corrected table: no overlaps, no sub-16 B gaps).

**Part B** — comment-only first, relocation second:
- Add `ts_heap` to the map as a real entry with its true base/size, state the temporal invariant
  explicitly, and delete the fictional "13.3 MB TS frontend reservation" wording.
- Fix the stale `0x1D0B000` base in `main.cyr:708-709` and `ts/lex.cyr:20,35`.
- Then relocate the TS arena above the token arrays (or into the genuinely free 9.06 MB at
  `0x207B000..0x298B000`) so the invariant becomes spatial rather than temporal.

## Acceptance criteria

1. `sh tests/heapmap.sh` accounts for `ir_nodes`, `ir_cp`, and the four unit-suffixed scratch regions.
2. **Mutation-proven**: introduce a deliberate overlap involving `ir_nodes` and confirm the gate goes
   RED. (It currently would not.)
3. The TS arena either no longer overlaps `tok_types`/`tok_values`, or the map documents the arena and
   the temporal invariant, and a gate asserts the TS entry points exit before `LEX`.

## Placement

v6.4.82 closeout (Part A + the Part B comments) → v6.5.x (the relocation). **Not 7.x.**
