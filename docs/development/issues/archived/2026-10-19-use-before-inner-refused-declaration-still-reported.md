# A use parsed BEFORE a refused declaration inside a fn body (an earlier fn's `q: *Q`, `E.B`, a bound `T: Tr`) is still a second error — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-28, `8c5be2e81`, with FF-30 `f8256705b` and the review fix FF-28r `b2ae86cc5` — no decision needed (diagnostics). `_dl_inner_fill` (src/frontend/parse_fn_def.cyr) walks the bodies before any pass-1 reporter and enters each inner refused struct / enum / union / trait's names; the bound's "unknown trait", `dyn Tr` and `impl Tr for P` reporters stand down for them. Each of the three filed repros is the declaration's one error (no "type 'Q' is declared after its use", "undefined variable 'E'", "unknown trait 'Tr' in the bound"; `--syntax-only` 2 → 1); `dyn Tr` / `impl Tr for P` likewise; a name declared nowhere and a valid top-level declaration of the same name are unaffected. FF-28r: a declaration in a body pass 2 never parses (a trait default no impl inherits, an uninstantiated bounded generic, a refused nested fn) whose name a use stood down through is reported at its keyword at the end of the parse (it left rc 1 with no line). FF-30 (met): a non-`fn` impl member is "an impl body holds only `fn` definitions". Rows: decl_after_statement_named.sh UI1 – UI3 (the repros verbatim) – UI9 and UP1 – UP12 on five legs; traits_checked.sh IB1 – IB7; mutants RED. Not closed (reported blocked, the user's call): an inner declaration in a never-parsed body that nothing uses is never refused. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F4), fixing
issues/archived/2026-10-18-refused-declaration-names-cascade-in-const-contexts-bounds-and-uninit.md, whose shape 4 (a use before
a LATE module-scope declaration) F4 fixed by entering those names in pass 1 (`_dl_fill`, depth-0 declarations after the
first statement — the brief's scope). A declaration refused one level down (`_decl_inner`, 6.7.15) enters its names
only when PARSE_PROG parses that fn body, so a use in an earlier fn is reported. Measured on F4's lane head (x86_64;
the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF5) — never 7.x.
**Severity:** Low — refused (rc 1); the declaration's error is printed, after one invented error.
**Kind:** bug (diagnostic cascade).

## Reproduction

```sh
printf 'fn g(q: *Q): i64 { return q.y; }\nfn f(): i64 { struct Q { y; } return 1; }\nsyscall(60, g(0) + f());\n' | build/cycc > /dev/null
# error:<source>:1:10: type 'Q' is declared after its use; declare it above the first use
# error:<source>:2:15: a `struct` declaration belongs to the declaration section at top level, not inside a fn body
printf 'fn h(): i64 { return E.B; }\nfn f(): i64 { enum E { A, B } return 1; }\nsyscall(60, h() + f());\n' | build/cycc > /dev/null
# error:<source>:1:25: undefined variable 'E'
# error:<source>:2:15: an `enum` declaration belongs to the declaration section at top level, not inside a fn body
printf 'fn f(): i64 { trait Tr { fn m(self): i64; } return 1; }\nfn g<T: Tr>(x: T): i64 { return 1; }\nsyscall(60, g<i64>(1) + f());\n' | build/cycc > /dev/null
# error:<source>:2:9: unknown trait 'Tr' in the bound on type parameter 'T'
# error:<source>:1:15: a `trait` declaration belongs to the declaration section at top level, not inside a fn body
```

With the declaring fn first, each is one error (the names are entered before the use is parsed).

## Root cause

`_dl_names` runs for an inner declaration at `_decl_inner` time (pass 2, source order). Pass 1's fill walks only the
module-scope statements after the first; it does not look inside fn bodies or blocks. The trait shape also reaches a
reporter none of the stand-downs consult ("unknown trait 'Tr' in the bound", the generic's definition).

## Direction

Enter an inner declaration's names in pass 1 too (the fn-body prescan meets each `{ .. }` body; a depth-0
`struct` / `union` / `enum` / `trait` in a body is always refused), and consult the refused set in the bound's
unknown-trait report. Diagnostics only.
