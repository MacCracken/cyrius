# A refused `struct` / `enum` in a fn body or a block followed on its line by a `fn` / `pub fn` takes the body's own `}` — "expected '}', got end of file" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-27, `c5cf2a990`, and the review fix FF-27r, `edcf462c8` — no decision needed (diagnostics). A refused struct's / enum's derive step (`_dl_derived` / `_dl_dname`, src/frontend/parse_fn_def.cyr) takes only the fns that `#derive` registration emitted, by name (lex_pp.cyr's PP_DERIVE_CODEC / PP_DERIVE_FAM; each name once), each through its own braces, never a `}` it did not open. Filed repro 1 is the struct's error + "1:31: fn 'h' is defined inside fn 'f'" (no "expected '}', got end of file"); repro 2 the struct's + "2:31: a `pub` declaration ... not inside a block" + `zz` (no EOF line); at module scope the user's `fn h` after a refused struct is defined (its body checked). FF-27r: a user's `fn Q_h` on a DERIVED struct's line is parsed too (FF-27 took any `<Type>_` name there). Rows: tests/gates/diagnostics/decl_after_statement_named.sh DV1 / DV2 (the repros verbatim) – DV7e on five legs (floor 200); mutants RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F4) while widening `_decl_inner` to `mod` /
`use` / `pub` (issues/archived/2026-10-18-mod-use-pub-inside-fn-body-or-block-named-by-token.md). F4 restricted the derive
step to the declarations `#derive` takes (a `struct` / `enum`, `pub` or not), so a `use` / `pub var` / `pub fn` /
`impl` / `trait` / `union` followed on its line by another declaration is no longer stepped; the struct / enum shapes
below are 6.7.15's and unchanged by F4 (identical on the lane before F4, b2053aff7's build/cycc, and on F4's head).
x86_64; the frontend, every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF5) — never 7.x.
**Severity:** Low — refused (rc 1) every time; the declaration's error is right and one invented error follows (the
fn body's `}` consumed), and whatever else the line held is stepped silently.
**Kind:** bug (diagnostic cascade).

## Reproduction

```sh
printf 'fn f(): i64 { struct Q { y; } fn h(): i64 { return 1; } return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: a `struct` declaration belongs to the declaration section at top level, not inside a fn body
# error:<source>:2:18: expected '}', got end of file
printf 'var a = 1;\nif (a == 1) { struct Q { y; } pub fn h(): i64 { return 1; } }\nsyscall(60, a + zz);\n' | build/cycc > /dev/null
# error:<source>:2:15: a `struct` declaration belongs to the declaration section at top level, not inside a block
# error:<source>:3:19: undefined variable 'zz' (missing include or enum?)
# error:<source>:3:21: expected '}', got end of file
```

On separate lines each is one error per declaration (the nested `fn h` its own "defined inside fn 'f'"). At module
scope the same line shape (`a = 2;\nstruct Q { y; } fn h(): i64 { return 1; }`) loses no brace but steps `fn h`
silently, as if derived.

## Root cause

`_dl_derived` (src/frontend/parse_fn_def.cyr) steps every token left on a refused struct's / enum's last line when it
starts with `fn` / `pub` — where a `#derive` writes its generated fns (PP_DERIVE_*, on the expanded line of the
closing `}`). It cannot tell those from the user's own code on the same line, and below module scope it steps past a
depth-0 `}`, the enclosing fn body's or block's.

## Direction

Recognise the derive's output rather than "the rest of the line" (the preprocessor knows which declaration it derived
and which line it wrote; or the generated fns' `<Type>_` names), and never step a `}` at depth 0 below module scope.
Diagnostics only.
