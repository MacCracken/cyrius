# `x.m<T>(..)` on a receiver with no struct (an untyped local / parameter, a const, a refused annotation) is named as a field and its `<T>` read as a comparison — a FALSE "undefined variable 'i64'"; under `--syntax-only` a false "expected ';', got '>'" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-31, `68a340f16` — no decision needed (diagnostics). The genbind lane's `9ac212def` (wave 3) had already fixed the filing's untyped-local and `--syntax-only` (`p.id<f64>(1.5)`, rc 0) repros; FF-31 steps a `.m<types>(` list on the remaining receivers before the const and stand-down checks (`_meth_ngt0`, `_cst_fld_st` / `_mlist_step`, src/frontend/parse_decl.cyr; `_enum_qual_said`). The const repro is "1:39: const 'C' has no methods - a const has no storage" alone (it said "has no fields" + "undefined variable 'i64'"); the refused-annotation repro "unknown type 'Foo' for variable 'x'" alone; a local const, an undefined name and an enum's name likewise; a list that is not all type names keeps its comparison reading. Rows: tests/gates/frontend/const_checked.sh MX1 – MX3 (the filed repros verbatim) – MX9 on five legs (floor 50); mutants RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F3) beside
issues/archived/2026-10-18-const-subscript-and-generic-method-in-const-fn-misnamed.md, whose filed surface (r3) is the explicit
generic method call in a CONST FN: F3 makes the definition check refuse `a.m<T>(..)` / `C.m<T>(..)` there as a method
call, and the refused const fn's run-time body step the call whole (`_ce_mx_skip`, through `_ce_fld_said`). The
ordinary run-time shapes below never reach that stand-down and are unchanged by F3: measured identical on the lane
before F3 (e6c35814f's build/cycc) and after it (x86_64; the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF6) — never 7.x.
**Severity:** Low — every input below is refused in a normal compile (rc 1); the second error is invented. Under
`--syntax-only` the last shape refuses a call the grammar accepts (its receiver's struct being declared elsewhere is
`--syntax-only`'s own use case).
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
fn g(n) {
    var a = n;
    return a.m<i64>(1);
}
fn main() { return 0; }
var r = main();
```
```
error:<source>:3:15: no struct type in scope for 'a'; a '.field' access needs its struct declaration (missing include?)
error:<source>:3:19: undefined variable 'i64' (missing include or enum?)      <- false; and it is a method call
```

A const receiver, `const C = 5; fn main(): i64 { return C.m<i64>(1); }`:
```
error:<source>:2:26: const 'C' has no fields - a const has no storage      <- `C.m(1)` says "has no methods"
error:<source>:2:32: undefined variable 'i64' (missing include or enum?)
```

A refused annotation, `fn main(): i64 { var x: Foo = 5; return x.m<i64>(1); }`:
```
error:<source>:1:25: unknown type 'Foo' for variable 'x'
error:<source>:1:48: undefined variable 'i64' (missing include or enum?)      <- the stand-down covers `x.m(1)` only
```

`--syntax-only`, a parameter whose struct a sibling file declares, `fn g(p) { return p.id<f64>(1.5); }`:
```
error:<source>:1:26: expected ';', got '>'      <- `p.id(1.5)` is accepted
```
(The const fn shape r3 under `--syntax-only` keeps the same second line after F3's "a method call is not in a const
fn".)

## Root cause

PARSE_FIELD_LOAD takes `x.m<..>(` as a method call only through `_meth_targs` (src/frontend/parse_decl.cyr), which
needs a struct receiver (`sid > 0`) with a generic method `m` (`_mtargs_at`). With `sid == 0` the `.m` is a field
read: the `sid == 0` arm reports (or stands down: `_cst_fld_at`, `_fld_sid0_said`, `_ann_refd_said`; under
`--syntax-only` `_synonly_skip_chain`) and returns with the cursor on `<`, so the expression parser reads `< i64 >
(1)` as comparisons — `i64` an undefined variable (ERR_UNDEF prints under the latch), `>` after a comparison a syntax
error.

## Direction

In the `sid == 0` arms, a `<..>(` after the name (`_ce_mtargs_at`'s shape, src/frontend/parse_fn.cyr) is a method
call: report the method form ("a method call needs its struct declaration", "const 'C' has no methods") and step the
list and the arguments in sync; under `--syntax-only` step them silently (parse the arguments as the method arm does).
Diagnostics only in a normal compile; `--syntax-only` stops refusing the parameter shape.
