# A global `*Foo` whose `Foo` is refused reads its fields as the program's FIRST struct: "unknown field 'y' on struct 'var'" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-5, `593070daa` — no decision asked (the brief: the local and parameter forms are refused, so not a semantics choice; D68, the user 2026-10-20, later cites this bite for the scalar-global band). `_gv_recv_sid` (src/frontend/parse_types.cyr), the field arms' global receiver, answers 0 for a GVTYPE in the `*T` step band (-2048 < t < 0), so the `sid == 0` arms answer as for a local. The three filed repros are now one error each — "unknown type 'Foo' as the target of pointer 'x'" alone (no "unknown field 'y' on struct 'var'"), the `*Foo` global beside `struct P` no longer resolved against P, the late-struct form its declaration's error alone — on x86_64, aarch64, cx, PE and Mach-O. Beyond the filing, the same root cause: a `*i64` global's `x.a`, which compiled (rc 0) and read through the program's first struct, and its `x.m()` under `--allow-undef`, are now refused "no struct type in scope for 'x'" as the local's are (a newly refused shape: ecosystem-migration § 6.7.16); a `*P` global reads through P as before (exit 9 / 12, also under qemu-aarch64, cxvm and wine). Rows: `tests/gates/diagnostics/type_name_refused.sh` axis 7 — gp_repro1 / gp_repro2 / gp_repro3 (verbatim), gp_late, gp_uses, gp_i64_read / _store / _meth / _late / _fn, gp_i64_local, gp_P / gp_P_late; mutation (the pre-fix compiler) RED 9. Filed beside it (placed IN 6.7.16, D68): a scalar-typed global's `g.d` reads its width as a struct id. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F6, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — every shape is refused by its first error (no binary); the second error names a struct the
source never declared, or none is printed and the field is resolved against an unrelated struct.
**Kind:** bug (diagnostic; a wrong struct id recorded for a refused pointer target).
**Discovered:** unit F6, fixing issues/archived/2026-10-17-late-declaration-refusal-cascades-at-its-uses.md: a global
`var x: *Q = 0;` whose `Q` was refused as a late declaration still printed a second error at `x.y` after the
stand-downs (`_tn_refuse` stands down for a refused declaration's type; the `.field` arm then meets a non-zero sid).
The same happens for a type declared nowhere, so it is not that issue's.

## Reproduction

```sh
printf 'var x: *Foo = 0;\nsyscall(60, x.y);\n' | build/cycc > /dev/null
# error:<source>:1:9: unknown type 'Foo' as the target of pointer 'x'
# error:<source>:2:16: unknown field 'y' on struct 'var'
printf 'struct P { a; }\nvar x: *Foo = 0;\nsyscall(60, x.a);\n' | build/cycc > /dev/null
# error:<source>:2:9: unknown type 'Foo' as the target of pointer 'x'
#   (rc 1; `x.a` is resolved as P's field `a` — no second error at all)
printf 'var a = 1;\na = 2;\nstruct Q { y; }\nvar x: *Q = 0;\nsyscall(60, x.y);\n' | build/cycc > /dev/null
# error:<source>:3:1: a `struct` declaration must come before the first top-level statement (line 2)
# error:<source>:5:16: unknown field 'y' on struct 'var'
```

'var' is the program's first lexed word: name offset 0, the name of a struct slot nothing registered (struct id 1
with no struct, or the first declared struct when there is one). A local (`fn f(): i64 { var x: *Foo = 0; return
x.y; }`) and a parameter (`fn f(x: *Foo)`) get sid 0 and the "no struct type in scope" arm instead.

## Root cause (not bisected)

The global path records the refused pointer target as struct id 1 (or leaves a value `_gv_recv_sid` /
`_gv_ptr_sid` reads as one: src/frontend/parse_types.cyr), so PARSE_FIELD_LOAD's global arm resolves the field
against struct 1 instead of meeting `sid == 0`.

## Fix

Record no target (0) when the pointer annotation's type is refused, as the local and parameter paths do; the `.field`
arm then takes its `sid == 0` arm (where 6.7.15's `_ann_refd_said` already stands down for a refused late
declaration's type). Rows: the three repros — one error each for the late-declaration shape, "no struct type in
scope for 'x'" (or the refused-annotation stand-down, if the receives lane's item has landed) for the others; a
`*Foo` global beside a declared struct is not resolved against it.
