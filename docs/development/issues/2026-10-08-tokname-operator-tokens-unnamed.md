# TOKNAME has no name for 23 operator / literal tokens — "expected '=', got unknown" — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: `var x <OP> 1;`
inside a fn reports `expected '=', got unknown` for all 23 tokens listed below (and for a float literal); `>>>` and `!`
(named in 6.7.5 / 6.7.3) report their names. The set was derived by diffing every token number the lexer emits
(`ADDTOK(S, N` in `src/frontend/*.cyr` + `LEXKW_EXT`'s returns) against TOKNAME + TOKNAME_BUILTIN.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 planning (roadmap commit 68de8001, 2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a misleading diagnostic on source that is invalid either way.
**Affects:** cycc through 6.7.6 (these tokens have never had names).

## Summary

`TOKNAME` (`src/common/util.cyr:2122`) names keywords, punctuation and the builtin table, and falls through to
`"unknown"` for everything else. The roadmap bullet named 8 operators; the live surface is **23 tokens**: every
comparison / bitwise / shift / logical operator that is not `==` `!=` `<` `>`, the wrapping / saturating / checked
arithmetic operators, `...`, `?`, `@unsafe`, and the float literal. Any `ERR_EXPECT` whose cursor sits on one of them —
`expected '=', got unknown`, `expected ')', got unknown`, `expected identifier, got unknown` — names nothing.

| token | spelling | token | spelling | token | spelling |
|---|---|---|---|---|---|
| 21 | `<=` | 37 | `~` | 115 | `+?` |
| 22 | `>=` | 38 | `<<` | 116 | `-%` |
| 27 | `&` | 39 | `>>` | 117 | `-\|` |
| 34 | `%` | 53 | `&&` | 118 | `-?` |
| 35 | `\|` | 54 | `\|\|` | 119 | `*%` |
| 36 | `^` | 112 | `...` | 120 | `*\|` |
| 61 | a float literal | 113 | `+%` | 121 | `*?` |
| 123 | `@unsafe` | 114 | `+\|` | 124 | `?` |

(Spellings from the lexer's operator chain, `src/frontend/lex.cyr` ~2400–2570; token 61 at lex.cyr:1426.)

## Reproduction

```sh
for op in '<=' '>=' '%' '&' '|' '^' '<<' '>>' '&&' '||' '~' '?' '+%' '+|' '+?' '-%' '-|' '-?' \
          '*%' '*|' '*?' '...' '@unsafe' '1.5' '>>>'; do
  printf 'fn main() {\n    var x %s 1;\n    return 0;\n}\nvar r = main();\n' "$op" > op.cyr
  printf '%-8s ' "$op"; build/cycc < op.cyr 2>&1 >/dev/null | head -1
done
```

Expected: `expected '=', got '<='` (etc.). Actual (6.7.6): every row but `>>>` prints
`error:<source>:2:11: expected '=', got unknown`.

Re-derive the unnamed set (prints the token numbers with no TOKNAME entry; `0` is `LEXKW_EXT`'s "not a keyword"
return, not a token):

```sh
{ grep -ohE "ADDTOK\(S, *[0-9]+" src/frontend/*.cyr | grep -oE "[0-9]+$"
  awk '/^fn LEXKW_EXT/,/^}/' src/frontend/lex.cyr | grep -oE "return [0-9]+" | grep -oE "[0-9]+"; } | sort -u > em
awk '/^fn TOKNAME_BUILTIN/,/^}/; /^fn TOKNAME\(/,/^}/' src/common/util.cyr | grep -oE "typ == [0-9]+" \
  | grep -oE "[0-9]+" | sort -u > nm
comm -23 em nm | sort -n | tr '\n' ' '
# 6.7.6: 0 21 22 27 34 35 36 37 38 39 53 54 61 112 113 114 115 116 117 118 119 120 121 123 124
```

## Root cause

`TOKNAME` (util.cyr:2122–2211) has no arm for these token numbers; it ends `return "unknown";` (util.cyr:2210). The
names were never added when the operators were.

## Proposed fix

Add a third delegate, `TOKNAME_OP(typ)`, called from `TOKNAME` before `TOKNAME_BUILTIN`. It must be a SEPARATE fn:
the comment at util.cyr:2005–2012 records that cybs mis-compiles a fn with too many string-literal (global) references,
which is why `TOKNAME_BUILTIN` was split out — 23 more literals in `TOKNAME` would risk the seed chain. Do NOT add
them to `TOKNAME_BUILTIN`: `IS_KEYWORD_TOK` derives the reserved set from that table (util.cyr:2014–2016). Token 61
reads `float literal`. Pin the set with a gate that runs the derivation above and fails on any emitted token number
without a name (the 6.5.x `got unknown` negative-control pattern, CHANGELOG `[6.4.77]`). Diagnostic only — changes
nothing that compiles. Seed-derive is mandatory (a `src/` change).
