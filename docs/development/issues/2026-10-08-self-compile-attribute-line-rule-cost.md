# self_compile pays ~4 % for the preprocessor's per-byte `PP_LEXST_AT` call layer (the 6.6.20 attribute-line rule) — OPEN

**Status:** 🟡 **OPEN** — re-measured 2026-10-08 against 6.7.6 @ 2fb6ad8b (interleaved A/B, 15 + 20 runs, on a box
running parallel work — absolute ms are noisy, the deltas repeat): self-compiling `src/main.cyr`, HEAD `build/cycc`
**1,204 / 1,205 ms** median; a variant whose `PP_LEXST_AT` drops the attribute check but keeps the call **1,202 /
1,192 ms**; a variant whose eight walk sites call `PP_LEXST` directly **1,159 / 1,147 ms** (−45 / −58 ms). Both
variants compile HEAD's source to bytes identical to `build/cycc`. The cost is the call layer, not the attribute test.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.6.20 bench (2026-10-07): 924 → 987 ms on 6.6.19's source (+6.8 %), bisected to s-pplex
`0d85cdcd` (+50 ms on the same input; CHANGELOG [6.6.20] *Bench*); filed 2026-10-08 from roadmap.md.
**Severity:** Low — compiler speed (+~4 % self_compile), no correctness impact.
**Affects:** cycc 6.6.20 – 6.7.6.

## Summary

`0d85cdcd` (the attribute-line desync fix) taught the preprocessor that a `#` spelling one of the lexer's ten
attribute words (`#assert`, `#inline`, …) does not open a comment, and moved EVERY PP walk from `PP_LEXST(st, c)` onto
`PP_LEXST_AT(base, i, n, st)` (`src/frontend/lex_pp.cyr:204-212`), a wrapper that loads the byte and calls
`PP_LEXST` — one extra call per source byte per pass, over the ~8 walks (`PP_PASS`, `PP_IFDEF_PASS`,
`PP_MACRO_PASS`, `PP_REF_PASS`, `PP_IS_HOST_ONLY`, `PP_NEUT_FMARK`, `PP_A64_NATIVE_AT`, the `#derive` brace copy).
`LEXATTRWORD` itself is cheap: it bails on the byte after `#` unless it is `a`–`z`, and the compiler's comments are
`# text`.

## Reproduction

```sh
# in a scratch `git archive HEAD` copy, with HEAD's build/cycc:
# variant B — drop the attribute test, keep the wrapper:
#   fn PP_LEXST_AT(base, i, n, st): i64 { return PP_LEXST(st, load8(base + i)); }
# variant C — no wrapper: rewrite the 8 sites `X = PP_LEXST_AT(b, i, n, X);` → `X = PP_LEXST(X, load8(b + i));`
#   sed -i -E 's/(\b[a-z]+) = PP_LEXST_AT\(([^,]+), ([^,]+), ([^,]+), \1\);/\1 = PP_LEXST(\1, load8(\2 + \3));/' src/frontend/lex_pp.cyr
cat src/main.cyr | build/cycc > /tmp/cycc_C          # likewise /tmp/cycc_B
# then time `<cc> < src/main.cyr > /dev/null` for HEAD / B / C, interleaved, ≥ 15 runs each
```

Expected: the attribute rule costs what its test costs. Actual: B ≈ HEAD (−3 to −13 ms), C ≈ HEAD − 45…58 ms. (B
and C are measurement probes only — both reopen the forged-`#@file` vector and must not ship.)

## Root cause

The per-byte indirection `PP_LEXST_AT` → `PP_LEXST` (`src/frontend/lex_pp.cyr:167`, `:204`) at the eight walk
sites (`:261, :430, :846, :2101, :4682, :4750, :5038, :5153` — `grep -n "PP_LEXST_AT(" src/frontend/lex_pp.cyr`). Speculation for the remainder of 6.6.20's +50 ms: the lexer's
`LEXATTRWORD` dispatch that replaced ten unrolled byte chains in `LEX`.

## Proposed fix

Keep the rule, lose the layer: test `st == 0 && c == 35` inline at each walk site and call `LEXATTRWORD` only
there, else `PP_LEXST(st, c)` directly (or admit `PP_LEXST_AT` to `#inline` replay if the inliner takes it). Same
state machine, so `file_marker_forge_refused.sh` axes 11–26, `macro_invocation_boundary.sh` and
`lexer_attribute_word_boundary.sh` must stay green and output stay byte-identical; record the A/B (same box,
interleaved) in the CHANGELOG bench line. Seed-derive: `lex_pp.cyr` is compiled by cybs.
