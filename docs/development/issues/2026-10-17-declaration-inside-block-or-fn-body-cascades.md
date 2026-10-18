# A `struct` / `enum` / `union` / `trait` / `impl` declaration inside a block or a fn body is "unexpected struct" and a cascade — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (unit F6, commit 45c06049, x86_64; the
frontend, every target). Met beside issues/archived/2026-10-12-declarations-after-first-statement-decision.md, whose filed
surface (and the user's decision D13 (a), 2026-10-16: one named error) is a declaration at MODULE scope after the
first top-level statement; that is fixed (`_decl_late`, module scope only: `GINFN` 0, `_pp_depth` 1). The same
keywords one level down — in a top-level block's body or a fn body — still reach `_PARSE_STMT_IMPL` and cascade.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — every shape is refused at compile time; nothing is silent. But the first error names a token
(`unexpected struct`), not the rule, and two to four invented errors follow.
**Discovered:** 2026-10-17, writing the D13 rows (the in-block shape was probed as a control of the module-scope fix).

## Reproduction

```sh
cd <the tree>
printf 'var a = 1;\nif (a == 1) { struct Q { y; } }\nsyscall(60, a);\n' | build/cycc > /dev/null
# error:<source>:2:15: unexpected struct
# error:<source>:2:24: expected '=', got '{'
# error:<source>:2:27: undefined variable 'y' (missing include or enum?)
# error:<source>:2:27: undefined variable 'Q'
printf 'fn f(): i64 { struct Q { y; } return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: unexpected struct
# error:<source>:1:24: expected '=', got '{'
# error:<source>:1:27: undefined variable 'y' (missing include or enum?)
# error:<source>:1:27: undefined variable 'Q'
# error:<source>:1:31: return outside a fn body
printf 'fn f(): i64 { impl P { fn g(self): i64 { return 1; } } return 1; }\nstruct P { x; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: unexpected impl
# error:<source>:1:24: fn 'g' is defined inside fn 'f'; define it at top level
# error:<source>:1:56: return outside a fn body
```

## Root cause

PARSE_PROG is also the block and fn-body parser; a declaration keyword there goes to PARSE_STMT, where it is a
statement that does not parse (`ERR`'s `unexpected <tok>`), and the statement resync re-enters the declaration's
braces (the fn body's own `}` is consumed by the cascade: "return outside a fn body"). 6.7.14's `_decl_late`
(src/frontend/parse_fn.cyr) refuses the module-scope shape by name and steps it (`_dl_skip`); it stands down below
module scope by design, since a declaration there was outside D13's question.

## Proposed fix

The rule is the guide's ("they belong to the declaration section"): one error by name — e.g. "a `struct` declaration
belongs to the declaration section at top level, not inside a fn body / a block" — at the keyword, and the
declaration stepped with `_dl_skip` (a `}` / `;`) so the fn body / block parses on in sync. Nothing that compiles
changes. Rows: each kind inside a top-level `if` / `while` block and inside a fn body, error count 1; the fn's
following statements still parsed (a second, independent mistake after it still reported).
