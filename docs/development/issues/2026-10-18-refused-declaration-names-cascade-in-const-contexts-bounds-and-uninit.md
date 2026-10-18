# Uses of a refused declaration's names that 6.7.15's stand-downs do not reach: const contexts, a trait bound, an uninitialized `var q: Q;`, a use before the declaration — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F6, x86_64; the
frontend, every target); each shape below prints the same on the slot-open compiler (b2e1f4c48's build/cycc), except
where noted.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 frontend lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — every shape is refused; the first error is the right one. One or two invented errors follow.
**Kind:** bug (diagnostic cascade).
**Discovered:** unit F6, fixing issues/2026-10-17-late-declaration-refusal-cascades-at-its-uses.md. That issue's
four repros (a struct literal, `E.B`, a bare member, a `*Q` parameter and its `.y`) are now one error each:
`_dl_names` (src/frontend/parse_fn_def.cyr) enters a refused declaration's struct / union / enum names and enum
members as reported, and the undefined-variable, unknown-type (`_tn_refuse`), stray-literal and `sid == 0`
reporters stand down for exactly those names (`_dl_refd_at`, `_ann_refd_said`). The shapes below reach other
reporters, or run before the declaration is refused, and are outside that filing.

## Reproduction

```sh
H='var a = 1;\na = 2;\n'
# 1. A const context: a case label, a const, a global array size.
printf "${H}enum E { A, B }\nfn g(x): i64 { switch (x) { case E.A: return 1; } return 0; }\nsyscall(60, g(1));\n" | build/cycc > /dev/null
# error:<source>:3:1: an `enum` declaration must come before the first top-level statement (line 2)
# error:<source>:4:34: unknown name 'E' in a const context
printf "${H}enum E { A, B }\nconst C = E.B;\nvar arr: i64[E.B];\nsyscall(60, C);\n" | build/cycc > /dev/null
# error:<source>:4:11: unknown name 'E' in a const context          <- printed BEFORE the declaration's (pass 1's sweep)
# error:<source>:3:1: an `enum` declaration must come before the first top-level statement (line 2)
# error:<source>:5:14: unknown name 'E' in a const context
# 2. A refused trait as a bound.
printf "${H}trait Tr { fn m(self): i64; }\nfn g<T: Tr>(x: T): i64 { return 1; }\nsyscall(60, g<i64>(1));\n" | build/cycc > /dev/null
# error:<source>:3:1: a `trait` declaration must come before the first top-level statement (line 2)
# error:<source>:5:20: generic 'g': its type argument does not implement trait 'Tr'
# 3. `var q: Q;` with no initializer (a struct local's usual declaration).
printf "${H}struct Q { y; }\nfn h(): i64 { var q: Q; return q.y; }\nsyscall(60, h());\n" | build/cycc > /dev/null
# error:<source>:3:1: a `struct` declaration must come before the first top-level statement (line 2)
# error:<source>:4:23: uninitialized variable not allowed; use `var X = 0;` or initial value
#   (slot-open: + "4:22: unknown type 'Q' for variable 'q'"; the same "uninitialized" error follows any refused
#    annotation: `fn f(): i64 { var q: Foo; return 1; }` is "unknown type 'Foo'" + "uninitialized variable")
# 4. A use BEFORE the refused declaration (an earlier fn): the names are entered when the declaration is refused.
printf "${H}fn g(q: *Q): i64 { return q.y; }\nstruct Q { y; }\nsyscall(60, 0);\n" | build/cycc > /dev/null
# error:<source>:3:10: type 'Q' is declared after its use; declare it above the first use
# error:<source>:3:30: no struct type in scope for 'q'; a '.field' access needs its struct declaration (missing include?)
# error:<source>:4:1: a `struct` declaration must come before the first top-level statement (line 2)
# 5. A refused inclusion's by-name parameter type (`Str` is taken by name, so no annotation is refused or marked).
printf 'syscall(39);\ninclude "lib/str.cyr"\nfn f(s: *Str): i64 { return s.len; }\nsyscall(60, 3);\n' | build/cycc > /dev/null
# error:<source>:2:1: an include of a file that declares a `struct` (lib/str.cyr:24) must come before the first top-level statement (line 1)
# error:<source>:3:34: no struct type in scope for 's'; a '.field' access needs its struct declaration (missing include?)
```

(The `case B:` beside a refused `case E.A:` adds "expected ':', got identifier 'B'": staged separately as
2026-10-18-second-refused-case-label-reported-as-expected-colon.md.)

## Root cause

1. The const evaluator's unknown-name refusal (`_ce_badn`, src/frontend/parse_fn.cyr) does not consult the refused
   set; a top-level const and a global array size are evaluated in pass 1 (`_cst_sweep`, PARSE_GVAR_ARR), before
   PARSE_PROG reaches the late declaration that fills the set. 2. The bound check (`_bnd_*`) knows no refused trait.
   3. PARSE_VAR's no-initializer refusal follows any refused annotation (the variable is a plain i64 then). 4. The
   set is filled when the refusal is met, in source order. 5. `_pty_name` / `_classify_param_type` accept `Str` by
   name, so the parameter is never marked.

## Fix

Fill the refused set in pass 1 (where `_prescan_tail` already walks the statements after the first: a depth-0
`struct` / `union` / `enum` / `trait` there is refused later, so its names can be recorded then), and consult it in
the const evaluator's unknown-name arm (a quiet refusal), the bound check, and PARSE_VAR's no-initializer refusal
after a stood-down annotation (`_tn_refuse` / `_dl_refd_ann`, or the receives lane's refused-annotation mark). Rows
beside the U / UX rows of tests/gates/diagnostics/decl_after_statement_named.sh: each repro one error.
