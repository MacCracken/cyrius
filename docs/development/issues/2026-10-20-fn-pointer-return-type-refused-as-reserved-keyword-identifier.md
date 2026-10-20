# A fn's `: *fn( .. )` return type is refused "expected identifier, got reserved keyword 'fn' (... rename the variable/field/fn)" — the type is not named — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-20 by the 6.7.16 gensig lane (unit GS2), implementing 6.7.16's D9
(issues/2026-10-18-trait-member-return-outside-fn-return-set-accepted.md), whose fix direction notes "the fn's own
`: *fn(..)` message is worth naming too". D9 named the trait member's line only ("a `*fn(..)` return gets its own
line"); the fn's own message was not asked, so it is filed, not changed. Pre-existing: identical on the lane's compiler
before GS2 (7a6df215c) and since 6.7.11 made `*fn( .. )` a parameter type.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — diagnostics only: the program is refused either way; the message names a non-problem and gives
advice that does not apply (there is no variable, field or fn to rename).
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn h(): *fn(i64): i64 { return 0; }
fn main(): i64 { return 4; }
syscall(60, main());
```

```
$ build/cycc < ff.cyr > ff; echo rc=$?
error:<source>:2:10: expected identifier, got reserved keyword 'fn' (cannot be used as an identifier; rename the variable/field/fn)
    fn h(): *fn(i64): i64 { return 0; }
             ^
rc=1
```

`: **fn(i64): i64` gives the same line (at its `fn`, after the two `*`). The same return on a trait member is, since 6.7.16
(D9), `error:<source>:L:C: a fn-pointer type `*fn( .. )` cannot be a fn return type` and the fn's return-type note
(`_trs_fnp_refuse`, src/frontend/parse_fn.cyr), at the type's first `*`, also under `--syntax-only`.

## Root cause

PARSE_FN_DEF's return reader takes `: *T` in `_ret_ann_alt` -> `_ret_ptr_annot` (src/frontend/parse_fn.cyr), which
expects an identifier after the `*`s and reports the `fn` keyword through the generic reserved-word refusal.

## Fix direction

In `_ret_ann_alt`, before `_ret_ptr_annot`, refuse a `*`.. `fn (` return with the member's words (`_trs_ret_fnp` /
`_trs_fnp_refuse`, or a shared reporter), reported under `--syntax-only` as the grammar refusal is now, and step past
the type so the body parses (one error, no cascade). Rows (type_name_refused.sh or traits_checked.sh): the repro, a
`**fn( .. )` return, `--syntax-only`; an impl method's `*fn( .. )` return then reads the same line (traits_checked.sh
TR8c pins it alone: its expected text moves with this fix).
