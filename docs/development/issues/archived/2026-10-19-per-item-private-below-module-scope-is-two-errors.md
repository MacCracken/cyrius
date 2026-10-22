# A per-item `private` in a fn body or after the first top-level statement is two errors ("per-item `private` is not supported" + "unexpected private"); `private fn` in a fn body three — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-26, `b272c366a` — no decision needed (diagnostics). `_decl_inner` asks `_dl_priv` (src/frontend/parse_fn_def.cyr) at a per-item `private` and steps the marker. Each of the three filed repros is the one "per-item `private` is not supported; put `private` alone on a line to make the file private" (no "unexpected private"; no "fn 'g' is defined inside fn 'f'" for the third). A `var` / `const` after the marker still declares, a `fn` where a fn may be defined is defined (and prescanned), and a fn-body `fn` or a refused declaration is stepped with the one error standing for it. Rows: tests/gates/frontend/private_per_item_rejected.sh PI1 – PI3 (the repros verbatim) – PI9 and PC1 – PC3 on five legs (floor 60); mutants RED. The file-level `private` line after the first statement keeps "unexpected private" (PC3; whether it is accepted there is the user's call, reported blocked). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F4) as a control beside the `mod` / `use` /
`pub` rows of issues/archived/2026-10-18-mod-use-pub-inside-fn-body-or-block-named-by-token.md (`private` is not one of the
kinds the declaration-section rule names, so not that issue's surface). Identical on the lane before F4
(b2053aff7's build/cycc) and on F4's lane head. x86_64; the frontend, every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF5) — never 7.x.
**Severity:** Low — refused (rc 1) every time; the first error is right, a second (and a third) follows.
**Kind:** bug (diagnostic cascade).

## Reproduction

```sh
printf 'fn f(): i64 { private var x = 1; return x; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: per-item `private` is not supported; put `private` alone on a line to make the file private
# error:<source>:1:15: unexpected private
printf 'var a = 1;\na = 2;\nprivate var x = 1;\nsyscall(60, x);\n' | build/cycc > /dev/null
# error:<source>:3:1: per-item `private` is not supported; put `private` alone on a line to make the file private
# error:<source>:3:1: unexpected private
printf 'fn f(): i64 { private fn g(): i64 { return 1; } return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: per-item `private` is not supported; put `private` alone on a line to make the file private
# error:<source>:1:15: unexpected private
# error:<source>:1:23: fn 'g' is defined inside fn 'f'; define it at top level
```

In the declaration zone the same `private var x = 1;` is one error (`_TL_VIS` consumes the token).

## Root cause

`_PRIV_PRESCAN` (src/frontend/parse.cyr) reports the per-item form at every `private` token of the stream, once; the
parser then meets the token again where nothing takes it — PARSE_STMT's fallback ("unexpected " + TOKNAME) after the
first statement and in a fn body or block — and, for `private fn`, the resync lands on the `fn` keyword, which
`_refuse_nested_fn` refuses.

## Direction

The statement parser steps a `private` the pre-pass already reported (and what it marks, as `_dl_pub_mark` /
`_dl_skip_in` do for `pub`), so the per-item error is the one error. Diagnostics only.
