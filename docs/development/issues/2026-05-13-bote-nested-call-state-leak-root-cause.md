# bote nested-call parse failure — root-cause investigation (cold case)

**Filed:** 2026-05-13 (during v5.11.49 vidya cleanup sweep)
**Severity:** Low — diagnostic hint shipped at v5.11.28; consumer workaround works; underlying state-leak not reproducible.
**Affects:** Parser; possibly identifier buffer hashing; possibly some state-leak between parse passes. Reproduction unobtained.

## Summary

bote 2.7.1 filed an intermittent `expected ')', got string` on the shape:

```cyrius
assert(streq(vec_get(caps_v, 0), "fetch") == 1, "msg")
```

A 2-arg inner fn-call inside another fn-call inside `assert`. Filing was at cyrius 5.10.34. Trigger was path-dependent — error position drifted (line 187 / 184 / 178 / 173) as preceding lines changed, and after a full chunk-by-chunk re-add the error stopped reproducing. bote couldn't reliably trigger it even at filing-time.

## v5.11.28 outcome

Premise-check at slot entry:

- Reverted bote's `cap0/cap1` var-stage workaround to recreate the inline-nested shape.
- Compiled at v5.11.27 (current) AND v5.10.34 (filing version, preserved at `~/.cyrius/versions/5.10.34/bin/cc5`).
- **Clean parse both times.**
- Synthetic fuzz: 0 / 28 triggers across 9 preceding-line counts (50→240 SSRF-URL asserts before trigger) × both versions AND 10 ident counts (100→10000 filler fns spanning the filing's ~8700 speculation boundary).
- No reproduction obtainable from any synthetic shape.

What v5.11.28 shipped:

1. `tests/tcyr/parse_nested_call_assert.tcyr` — 13 asserts locking the nested-call shape.
2. `src/common/util.cyr:425-432` — hint in `ERR_EXPECT` when surface is `expected ')'` or `expected ','` AND got-token is a string literal, gesturing at the var-stage workaround.

## Speculation about the silent fix

Commit `f3e98a3e` (first in v5.11.18, doubled identifier buffer 131072 → 262144 bytes) lines up with the filing's Speculation 2 hash-collision-boundary hypothesis — capacity doubling shifts hash-bucket distribution and probe-window boundaries. Not proof-grade (can't verify without a repro), but the timing fits.

## Why this is an issue, not just a gotcha

The diagnostic-hint patch landed at v5.11.28; the gotcha at `field_notes/compiler/gotchas.cyml::parse_nested_call_string_quirk_var_stage_hint_v51128` documents the symptom + workaround for consumers. **But the underlying bug — whatever state leak produced the path-dependent `expected ')', got string` — was never directly identified or fixed.** It may have been silently resolved by v5.11.18's identifier buffer doubling; it may still be live and waiting for the right consumer surface to retrigger it.

This issue is for tracking the root-cause investigation as a cold case, separate from the consumer-facing gotcha entry.

## Reproduction (as filed; needs verification)

The original bote file (at filing time) was approximately:

- 187 lines preceding the failing `assert(streq(vec_get(caps_v, 0), "fetch") == 1, "msg")` line
- Mix of SSRF-URL string-literal asserts + JSON-literal stress patterns
- bote project at ~10,000 idents total

A modern reproducer would need to:

1. Pull a bote snapshot at the filing tag.
2. Compile against multiple cyrius versions: 5.10.34, 5.11.17 (pre-buffer-double), 5.11.18 (post-buffer-double), 5.11.49 (current).
3. Look for the error surfacing or not surfacing across the matrix.

If the bug surfaces at 5.10.34 + 5.11.17 but disappears at 5.11.18 → confirms the buffer-doubling silent fix; the issue can be closed.
If the bug surfaces at 5.11.18+ → there's still a live state leak; investigation continues.

## Investigation entry points

- **Identifier hash table**: `src/frontend/lex.cyr` LEXID dedup uses length-bucketed linked-list chains (v5.10.40). Hash distribution change at 8192 → 16384 entries (v5.11.18) is the most likely culprit *if* the bug is real.
- **Parser state**: `src/frontend/parse_expr.cyr` and `parse_fn.cyr` paren-matching logic. State leak between assert-arg parsing and the outer fn-call could produce path-dependent symptoms.
- **`ERR_EXPECT` callsites**: `src/common/util.cyr:425-432` is the diagnostic hint site. Any reproducer trips one of these; logging which got-token shape preceded the error would localize.

## Out of scope for this issue

- Re-shipping the consumer-visible hint (already done at v5.11.28).
- Changing the parser without a reproducer (we don't fix symptoms — `feedback_premise_check_at_slot_entry`).

## Acceptance

Either:
- **Reproducer found** → file follow-up issue with the synthetic trigger; investigate root cause; close this issue.
- **6-month cold-case window expires** (2026-11-13) → close as `wontfix` (bug presumably silently resolved by v5.11.18 buffer doubling).

## Related

- `field_notes/compiler/gotchas.cyml::parse_nested_call_string_quirk_var_stage_hint_v51128`
- `CHANGELOG.md` [5.11.28]
- `tests/tcyr/parse_nested_call_assert.tcyr` (regression coverage for the shape, locks it against re-introduction)
