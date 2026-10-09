# A pair-returning call stored into ONE slot keeps only the tag, silently — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` (x86_64): the
roadmap's repro exits 0 with no diagnostic; a `: stack` pair stored through a field, a subscript, `*p` or `OP=`
compiles clean and drops the payload; `t, v = f();` is still `expected '=', got ','`.
**Placement:** 6.7.7 (being fixed in this release) — its fix is a language decision asked at the 6.7.7 open — never 7.x.
**Discovered:** 2026-10-08 against `build/cycc` 6.7.6 (roadmap.md's backlog); filed 2026-10-08 from roadmap.md.
**Severity:** Medium
**Affects:** cycc ≤ 6.7.6 (raw pair returns since multi-return, v3.7.2; the `: stack` store holes since v6.6.0)

## Summary

A call that returns two values (rax:rdx — `ret2(a, b)`, `return (a, b);`, a declared `: (i64, i64)`, a `: stack`
enum constructor) stored into a single slot keeps the first value (the tag) and drops the second, and several of
those stores are silent. ⚠ The roadmap's one-line version ("the single-bind refusal covers `var x = f()` but not a
plain assignment") is not what the live compiler does; the live surface is:

1. **Raw pair returns are never refused, bind or assignment.** For `fn f(x) { return ret2(0, x); }`, `return (0, x);`
   or `fn f(x): (i64, i64)`, both `var q = f(9);` and `rt = f(7);` compile silently and keep rax. The pair flag the
   refusals test (GFLG bit 256) is set only for `: stack` constructors and their forwarders. The legacy split
   `var q2 = divmod_old(10, 3); var r2 = rethi();` is documented in the guide (*Multi-Return*) and works with the
   assignment form too — so refusing it changes what compiles.
2. **A declared `: (i64, i64)` fn bound to ONE name is silent**, while binding it to THREE names is refused
   ("multi-value destructure count does not match the fn's declared return arity", `_dt_arity_check`).
3. **A `: stack` pair stored into a field, a subscript, through `*p`, or with `OP=` compiles clean and drops the
   payload** (`h.n = f(7);`, `a[0] = f(7);`, `*p = f(7);`, `x += f(7);` — each exits 0 where 7 is the payload). The
   guide's *Bind the pair as a pair — the three refusals* says "any context that keeps only one … is a compile
   error"; only `var r = f();`, `r = f();` and `store64(&slot, f());` are.
4. **There is no re-assignment form.** `t, v = f(7);` is `expected '=', got ','`, so a loop that re-polls a `Result`
   must declare a fresh `var t, v = f();` each iteration and copy the payload out of the loop's scope.

## Reproduction

```cyrius
fn f(x) { return ret2(0, x); }
fn main() {
    var t, v = f(5);
    var rt = 0;
    rt = f(7);
    return rt;
}
var r = main();
syscall(60, r);
```

```cyrius
enum Res: stack { Ok(v); Err(e); }
fn f(x) { return Ok(x); }
struct H { n; }
fn main() {
    var h: H;
    h.n = f(7);
    var a: i64[2];
    a[0] = f(7);
    var x = 0;
    var p = &x;
    *p = f(7);
    x += f(7);
    return h.n + a[0] + x;
}
var r = main();
syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected (if refused): a compile error naming the pair. Actual: both build with no diagnostic and exit 0 (the tag
0; the payload 7 is dropped). Controls on the same compiler: `rt = f(7);` / `var rt = f(7);` with the `: stack`
`f` are refused ("a `: stack` enum returns two values — bind both"); `var a, b = f(); t, v = f(7);` →
`expected '=', got ','`; `fn f(x): (i64, i64)` with `var q = f(9);` builds and `q` = 0.

## Root cause

- The refusals test GFLG bit 256 only (`_callee_returns_pair_at`, `src/frontend/parse.cyr:802`), set for `: stack`
  constructors and the wrappers that forward them (the prescan above it) — never for `ret2` / a tuple return / a
  declared `MULTIRET_SID` return.
- `_refuse_lossy_pair` (`parse.cyr:847`) runs at the plain variable assignment (`parse.cyr:4335`), the classic-for
  step aggregate (`src/frontend/parse_ctrl.cyr:777`), the if-expression branch (`parse_ctrl.cyr:328`) and the
  `store8..64` builtins (`src/frontend/parse_expr.cyr:3976`–`4009`). It is not called from `PARSE_FIELD_STORE`
  (`src/frontend/parse_decl.cyr:1802`), `_arr_sub_assign` (`parse_expr.cyr:2445`), `_deref_store`
  (`parse.cyr:3180`) or `_asg_compound_op` (`parse.cyr:3149`).
- `_dt_arity_check` (`parse_decl.cyr:5080`) checks the destructure's count against a declared arity; nothing checks
  a single bind of a declared multi-value fn.
- The statement parser takes `IDENT ,` as nothing; there is no multi-target assignment production.

## Proposed fix

Three decisions, all the USER's (each changes what compiles or adds syntax), asked at the 6.7.7 open:

1. **Item 3 (the `: stack` holes)** — call `_refuse_lossy_pair` at the field, subscript, `*p` and `OP=` stores, so
   the guide's "any context that keeps only one" is true. This refuses source that builds today (and silently
   loses the payload).
2. **Items 1–2** — whether a single bind / assignment of a raw or declared pair return is refused (it would break
   the documented `ret2` + `rethi()` split), refused only for a declared `: (T1, T2)` return, or left legal.
3. **Item 4** — whether `t, v = f();` (re-assignment of two existing names) becomes syntax.

Verify with a `tests/tcyr/crossos/` row per refused/accepted shape and a diagnostics gate for each refusal.
