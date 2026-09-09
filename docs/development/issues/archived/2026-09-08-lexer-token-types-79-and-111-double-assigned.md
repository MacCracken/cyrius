# Lexer token types 79 and 111 are double-assigned, so a token type cannot recover its spelling — FIXED v6.6.2

**Status:** ✅ **FIXED in v6.6.2** — shape 1 taken (`f64_sqrt` 79 → **136**, `callptr` 111 → **137**;
`object` keeps 79 and `stack` keeps 111).

> ⛔ **THE FILING'S CENTRAL PREMISE WAS WRONG, AND IT IS WHY THIS SAT.** It says "no miscompile —
> the grammar disambiguates by POSITION" and classes the whole thing as diagnostics quality.
> **Statement position IS a shared position.** `callptr(fp, 41);` as a bare statement was a HARD
> COMPILE ERROR — `expected var, got '('` — because `PARSE_STMT` saw token 111 and routed to the
> `stack var` parser before any expression path ran. Verified against 6.6.1: that program does not
> compile; it does now. So this was a real defect the whole time, not a wart.
>
> ⭐ **And it was far cheaper than the filing estimated.** The deferral reason given was "renumbering
> touches codegen across the seven `main_*.cyr` forks and the seed chain". Leaving the STATEMENT
> KEYWORDS on their existing numbers and moving only the two INTRINSICS costs **zero fork edits** —
> `main.cyr` and `main_win.cyr` compare against 79 for `object;` and were not touched at all.
> `callptr` had exactly one consumer site, `f64_sqrt` one handler.
>
> ⚠ **The trap that would have shipped green:** `f64_sqrt` sat inside the `62..105` STATEMENT BAND,
> so renumbering it out without adding a band entry silently regresses `f64_sqrt(x);` as a bare
> statement — and **no test in the tree covered that form**. Both statement forms are now pinned by
> `tests/tcyr/frontend/token_renumber_79_111.tcyr`, along with `stack var`, `: stack` enums (the
> OTHER consumer of 111, which the whole value-form arc rests on) and `object;` mode declarations.
>
> ⛔ **`programs/checks/lint_fmt.cyr` ASSERTED THE COLLISION** — it required the literal strings
> `'object'/'f64_sqrt'` and `'stack'/'callptr'`, so it would have gone RED on the fix. Same shape as
> the v6.6.0 gate that asserted the v6.5.67 refusal and would have blocked its own repair. Rewritten
> 2 rows → 6, including a class-wide assertion that **no reserved name reports a `'/'` disjunction**,
> so the next double-assignment is caught without anyone remembering to add a row.
>
> ⚠ **seed-derive was the load-bearing gate and it is GREEN** — a front-end token change is exactly
> what the cycc fixpoint cannot see (the `>>>` case at v6.4.74). All four cross-OS hosts green too.
**Placement:** unpinned — 6.6.x repair window or the potential backlog.
**Discovered:** 2026-09-08, auditing `field_notes/compiler/gotchas.cyml`. The trap has been
*documented* since v6.4.77; what this filing adds is that the documented mitigation is a
workaround and the underlying collision is still live.
**Severity:** Low-Medium — no miscompile; a diagnostics-quality and
diagnostics-maintainability defect that has already produced one actively-wrong error message.
**Affects:** all targets (front end).

## Summary

Two lexer token types carry two different spellings each:

- **token 79** is BOTH `object` and `f64_sqrt`
- **token 111** is BOTH `stack` and `callptr`

Verified live at v6.6.1 in `src/common/util.cyr`:

```
1421:    if (typ == 79) { return "object'/'f64_sqrt"; }
1422:    if (typ == 111) { return "stack'/'callptr"; }
1487:    if (typ == 79) { return 1; }   # object / f64_sqrt (double-assigned — see TOKNAME)
1488:    if (typ == 111) { return 1; }  # stack / callptr (double-assigned — see TOKNAME)
```

Both spellings **compile correctly**, because the grammar disambiguates by POSITION —
`object;` is a top-level mode declaration and `f64_sqrt(x)` an expression intrinsic;
`stack var b[N];` and `callptr(...)` cannot occur in the same place. So the collision is
invisible at parse time and there is no miscompile.

It is not invisible in **diagnostics**. Anything mapping a token type back to a name has
lost the information. Before v6.4.77 this produced an error that named the WRONG keyword:
`var f64_sqrt = 1;` reported `reserved keyword 'object'`, and `var callptr = 1;` reported
`reserved keyword 'stack'` — sending the reader to look for a variable they never wrote.

## Current mitigation, and why it is a workaround

`TOKNAME` returns **both** spellings (`object'/'f64_sqrt`), so the diagnostic is no longer
actively wrong. It is still not right: the compiler knows exactly which keyword the user
typed at lex time and discards that knowledge, then hands the reader a disjunction to
resolve themselves. Every future consumer of "token type → name" inherits the same loss —
that is the maintainability half, and it is why this is worth repairing rather than
re-documenting.

## Why it was not simply fixed

The in-source note records the reason, and it is a legitimate one under the
"file only when the fix cannot pack" rule:

> renumbering touches codegen and is not a diagnostic fix.

Token numbers are consumed across the front end and the **seven** per-target `main_*.cyr`
forks, so a renumber is a cross-cutting change that needs the full gate (self-host fixpoint
+ seed-derive + cross-OS on ecb/ach/cass/pi), not a patch bolted onto an unrelated release.
⚠ Note specifically that **cybs** must still lex the result: the seed-derive leg is the one
that catches a front-end change the cycc fixpoint cannot (see the `>>>` case at v6.4.74,
where cybs could not lex the new spelling and only seed-derive noticed).

## Proposed fix

Give each spelling its own token number and drop the dual-name strings from `TOKNAME` /
`IS_KEYWORD_TOK`. Two candidate shapes, maintainer's call:

1. **Renumber the two intrinsics** (`f64_sqrt`, `callptr`) into free numbers, leaving the
   statement keywords `object` / `stack` where they are. Smaller blast radius — the
   intrinsics are referenced from the emit dispatch, the keywords from the parser.
2. **Allocate both a fresh pair** from the top of the range, leaving neither in place.

Either way the acceptance is the same:

- `var f64_sqrt = 1;` and `var callptr = 1;` each name the ONE keyword actually written.
- `object;` mode declarations and `stack` enums still parse; `f64_sqrt(x)` / `callptr(...)`
  still emit identically — assert byte-identical self-host.
- `TOKNAME` contains no `'/'` disjunction for any token.
- Gate it, and **run seed-derive** — a token change is exactly the class the cycc fixpoint
  cannot see on its own.

## Related

- `field_notes/compiler/gotchas.cyml` →
  `lexer_tokens_79_and_111_are_double_assigned_so_a_token_type_cannot_recover_the_spelling`
  (the entry this filing was extracted from; it stays as the trap description).
- `the_reserved_token_count_cannot_be_grepped_and_every_number_written_down_has_gone_stale`
  — same file, same subsystem: the reserved-token set is hard to enumerate mechanically,
  which is part of why this collision persisted unnoticed.
