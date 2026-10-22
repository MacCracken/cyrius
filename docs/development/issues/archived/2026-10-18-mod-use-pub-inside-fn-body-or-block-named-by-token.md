# A `mod` / `use` / `pub` / `public` inside a fn body or a block is "unexpected <token>", not the declaration rule; a `pub fn` there is two errors — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-10, `da0927adc`, and its follow-up FE-13, `f626ea03c`, with the find met beside it FE-11, `8bccee4d5` — no decision needed (diagnostics only; refused before and after). `_decl_inner` (src/frontend/parse_fn_def.cyr) takes every kind `_dl_kind` names, spelling the source token (never TOKNAME's `pub'/'public`); a `pub var` / `pub const` steps its marker alone and still declares; a `pub const fn` ends at its `}`; a `pub use` alias is entered as reported; the derive same-line step follows only a `struct` / `enum` (FE-13 — FE-10's first cut still stepped after a `pub fn` / `impl`). The six filed repros are now one error each by the rule, "a `mod` declaration belongs to the declaration section at top level, not inside a fn body" (`... a block`; "a `use` / `pub` declaration ...") — the `pub fn` repro without its "fn 'g' is defined inside fn 'f'" — on x86_64, aarch64, cx, PE and Mach-O; two declarations on one line in a body no longer take the body's `}`; FE-11: a late `pub var x = 5;` at module scope still declares x (no "undefined variable 'x'"). Rows: `tests/gates/diagnostics/decl_after_statement_named.sh` NM (the 9 kinds × an if block / a while block / a fn body), NM1 – NM6 (the repros verbatim) – NM22, PM1 – PM3; mutations: b2053aff7's compiler RED all 46 NM rows of FE-10, `_decl_inner` back to five kinds RED 43, `_dl_derived` without its struct / enum test RED NM9 – NM11, NM16, NM18, NM20 – NM22, FE-10's `}` test RED NM20 – NM22, the pre-FE-11 compiler RED PM1 / PM2. Filed beside it (placed IN 6.7.16): per-item `private` below module scope, and a refused struct / enum's same-line derive step taking the body's `}`. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F6, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — every shape is refused at compile time; nothing is silent. The message names a token, not the
rule, and `pub fn` adds a second error.
**Kind:** bug (diagnostic).
**Discovered:** unit F6, fixing issues/archived/2026-10-17-declaration-inside-block-or-fn-body-cascades.md, whose filed
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
