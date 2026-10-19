# A `struct` / `enum` refused as a declaration after the first top-level statement (D13 (a)) still cascades at each use of it — RESOLVED

> ✅ **RESOLVED in v6.7.15** (FE-18, `6593fbf1d` — no decision needed: diagnostics only. Each refusal that steps a declaration enters its struct / union / enum names and an enum's members as reported (`_dl_names`; a payload constructor as a reported fn), and the reporters stand down for exactly those names (`_undef_var_report`, `_tn_refuse`, a stray literal `Q { .. }` and a `Q { 5 };` statement) and for a variable whose annotation or literal initializer named one (`_ann_refd_mark` / `_ann_refd_said`: its `.field`, method and field store). The four filed repros are the declaration's one error each, 3:1 (were 3 / 2 / 2 / 3); so are `var q = Q { 5 }; q.y`, `var e: E = E.A`, `sizeof(Q)`, a `*Q` return, a generic literal, `Ok2(5)` of a refused `: stack` enum, uses after a declaration inside a body and a refused inclusion's names. A name declared nowhere is still reported. Rows: `decl_after_statement_named.sh` U1 – U4 (the filed repros verbatim), UX1 – UX8, UE1 / UE2, UC; mutations RED on their rows. Partly closed against the title's "each use": uses that reach other reporters — a const context (`case E.A:`, `const C = E.B;`, an array size), a refused trait as a bound, `var q: Q;` with no initializer, a use before the refused declaration, a by-name `*Str` parameter — still cascade, filed (6.7.16) as `2026-10-18-refused-declaration-names-cascade-in-const-contexts-bounds-and-uninit.md`; a global `*Foo` resolving against the first struct as `2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md`. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b, x86_64; the
frontend, every target). Beyond the filed surface of issues/archived/2026-10-12-declarations-after-first-statement-decision.md
(fixed in the lane by 45c06049, the user's decision D13 (a), 2026-10-16: the declaration itself is one error by name,
and the fns it would have defined are quieted by `_dl_quiet`); a USE of the refused TYPE was not part of the filed
repros. Distinct from the staged 2026-10-17-declaration-inside-block-or-fn-body-cascades.md (a declaration below
module scope). Met by the 6.7.14 frontend review.
**Placement:** 6.7.15 — repair 5 (frontend lane, wave 1, unit F6; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — every shape is refused; the first error is the right one. One to three invented errors follow.
**Kind:** bug (diagnostic).

## Reproduction

```sh
cd <the tree>
printf 'var a = 1;\na = 2;\nstruct Q { y; }\nvar q = Q { 5 };\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:3:1: a `struct` declaration must come before the first top-level statement (line 2)
# error:<source>:4:11: undefined variable 'Q' (missing include or enum?)
# error:<source>:4:11: expected ';', got '{'
printf 'var a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, E.B);\n' | build/cycc > /dev/null
# error:<source>:3:1: an `enum` declaration must come before the first top-level statement (line 2)
# error:<source>:4:16: undefined variable 'E'
printf 'var a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, B);\n' | build/cycc > /dev/null
# error:<source>:3:1: an `enum` declaration must come before the first top-level statement (line 2)
# error:<source>:4:14: undefined variable 'B' (missing include or enum?)
printf 'var a = 1;\na = 2;\nstruct Q { y; }\nfn f(q: *Q): i64 { return q.y; }\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:3:1: a `struct` declaration must come before the first top-level statement (line 2)
# error:<source>:4:10: unknown type 'Q' for parameter 'q'
# error:<source>:4:30: no struct type in scope for 'q'; a '.field' access needs its struct declaration (missing include?)
```

The slot-open compiler gave four errors at line 3 for each (`unexpected struct` / `unexpected enum` and three
invented), and stopped there; the lane's line-3 error is the decided one, and what follows is each use of the name.

## Root cause

`_decl_late` (src/frontend/parse_fn.cyr) refuses the declaration and `_dl_skip` steps it, so the struct / enum /
its variants are never registered; `_dl_quiet` enters the FNS the declaration would have defined as reported (offset
-2, `_nested_fn_mark`'s rule), but there is no such mark for a type name, an enum name or its variants. Each later
use then meets an unknown name: the factor's undefined-variable arm (`Q {` also loses sync: "expected ';'"), the
qualified `E.B`, the bare variant `B`, a parameter type and its `.field`.

## Proposed fix

Enter what the refused declaration names as reported, as `_dl_quiet` does for fns: a refused struct / union / enum
name (and an enum's variants) marked so a use is silent — e.g. register the declaration's names in a "refused late"
set that the undefined-variable, unknown-type and struct-scope reports consult — or register the struct / enum
itself (pass 1 has its shape) while keeping the one error. Rows: each repro above one error; a use of a name that was
never declared still reported; a correctly placed declaration unchanged.
