# A `mod` / `use` / `pub` / `public` inside a fn body or a block is "unexpected <token>", not the declaration rule; a `pub fn` there is two errors — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F6, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** unplaced — filed from the 6.7.15 frontend lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — every shape is refused at compile time; nothing is silent. The message names a token, not the
rule, and `pub fn` adds a second error.
**Kind:** bug (diagnostic).
**Discovered:** unit F6, fixing issues/2026-10-17-declaration-inside-block-or-fn-body-cascades.md, whose filed
surface is `struct` / `enum` / `union` / `trait` / `impl` (now one error by name: "a `struct` declaration belongs to
the declaration section at top level, not inside a fn body", `_decl_inner` in src/frontend/parse_fn_def.cyr). The
other kinds 6.7.14's module-scope rule names (`_dl_kind`: `mod`, `use`, `pub` / `public`) were probed as controls.

## Reproduction

```sh
printf 'fn f(): i64 { mod m; return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: unexpected mod
printf 'fn f(): i64 { use m.g; return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: unexpected use
printf 'fn f(): i64 { pub var x = 1; return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: unexpected pub'/'public
printf 'var a = 1;\nif (a == 1) { mod m; }\nsyscall(60, a);\n' | build/cycc > /dev/null
# error:<source>:2:15: unexpected mod
printf 'fn f(): i64 { pub fn g(): i64 { return 1; } return 1; }\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:1:15: unexpected pub'/'public
# error:<source>:1:19: fn 'g' is defined inside fn 'f'; define it at top level
printf 'var a = 1;\nif (a == 1) { pub fn g(): i64 { return 1; } }\nsyscall(60, a);\n' | build/cycc > /dev/null
# error:<source>:2:15: unexpected pub'/'public
```

Each is one error but the last-but-one (two); none names the rule the guide states (§ Functions: "A `struct`,
`enum`, `union`, `trait`, `impl`, `mod`, `use` or `pub` / `public` declaration cannot: they belong to the declaration
section"), and the `pub` message prints the token's two-spelling table name verbatim (`pub'/'public`).

## Root cause

`_decl_inner` (6.7.15) covers the five kinds its issue filed; `mod` / `use` / `pub` / `public` below module scope
still reach `_PARSE_STMT_IMPL`'s fallback `ERR` ("unexpected " + TOKNAME). A `pub fn` then resyncs at the `fn`
keyword (`_sync_kw`), which `_refuse_nested_fn` refuses as a nested fn. TOKNAME(73) is the string `pub'/'public`.

## Fix

Widen `_decl_inner`'s kind test to `_dl_kind`'s full set (one error by name at the keyword, the declaration stepped
by `_dl_skip_at`'s `;`-or-`}` rule, a `pub fn`'s name entered as reported by `_dl_quiet`). Rows beside the N / NS
rows of tests/gates/diagnostics/decl_after_statement_named.sh: each of `mod m;`, `use m.g;`, `pub var x = 1;`,
`public fn g() { .. }` in a top-level block and a fn body — one error naming the rule.
