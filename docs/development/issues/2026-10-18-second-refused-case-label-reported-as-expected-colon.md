# A second refused `case` label is reported as "expected ':', got identifier 'ww'" instead of its own refusal — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 frontend lane (unit F3) beside
issues/2026-10-16-pass1-in-place-const-refusals-swallow-the-next.md, whose filed surface is the pass-1 / declaration-zone
in-place const contexts (enum values, global array sizes, `#assert`). A `case` label is the fifth in-place const
context and is outside it: F3 leaves case labels as they were (`_ce_ctx_open` keeps a case label's latch). Measured
the same on the slot-open compiler (b2e1f4c48's build/cycc), the lane before F3 (e5a003c6f) and after F3.
**Placement:** unplaced — filed from the 6.7.15 frontend lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — the input is refused; the second label's error names the wrong rule (a syntax error the source
does not have).
**Kind:** diagnostics.

## Repro

```cyrius
fn f(v): i64 {
    switch (v) {
        case yy: return 1;
        case ww: return 2;
        default: return 0;
    }
    return 0;
}
syscall(60, f(1));
```
```
error:<source>:3:14: unknown name 'yy' in a const context
error:<source>:4:14: expected ':', got identifier 'ww'      <- want: unknown name 'ww' in a const context
```
(The same with a good label between them: `case yy:` `case 2:` `case ww:` gives `5:14: expected ':', got identifier
'ww'`.)

## Root cause

The switch's pre-scan (PARSE_SWITCH's "collect case values" loop, src/frontend/parse.cyr) evaluates every label once
through `_case_val` -> `_cst_ctx_val` (stop = `:`), which memoises it by token (`_clm_add`). The first refusal latches
`_panic`, and the pre-scan is not a statement — nothing resyncs before the next label — so the second label's refusal
is swallowed and memoised with its end where the evaluator stopped (ON `ww`: `_cst_ctx_skip` does nothing for a case
label). The body path then replays the memo (`_clm_find`), leaving the cursor on `ww`, and its own `:` check
(`if (PEEKT(S) != 49) { ERR_EXPECT(S, 49); }`) prints "expected ':'" once the latch has been cleared.

## Fix sketch

Evaluate each pre-scan label with the latch clear and restore it after (the 6.7.15 `_ce_ctx_open` / `_ce_ctx_close`
pair, with the `:` as the in-sync end), and memoise a refused label's end at its `:` (its extent), so the replay steps
to the `:` silently. Diagnostics only: refused before and after.
