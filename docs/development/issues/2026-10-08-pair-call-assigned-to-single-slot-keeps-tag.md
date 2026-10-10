# A pair-returning call stored into ONE slot keeps only the tag, silently — RESOLVED

**Status:** ✅ **RESOLVED in 6.7.7 (B4, bites T5 and T5b)** — CHANGELOG `[6.7.7]` *Language — tuples (B4)*. **Item 3
is fixed** (bite T5b, 2026-10-09 — the user's decision: refuse, as the guide already said): a `: stack` pair stored
through a field (any field type, a slice's `.len`, the `--syntax-only` tail), a subscript, `*p` or any compound `OP=`
— `h.n = f(7);`, `a[0] = f(7);`, `*p = f(7);`, `x += f(7);`, a classic-for step's, at top level — is refused at the
callee with the "bind both" text; `?` still consumes the pair at each (`h.n = f(7)?;` stores the payload). **Item 4
is delivered** (bite T5, 2026-10-09): `t, v = f(7);` re-assigns both names (`tests/tcyr/crossos/tuple_values.tcyr`
`reassign`, the re-poll loop over a `: stack` pair included). **Items 1–2 are settled** by the user's decision
(2026-10-08): `var x = f();` / `x = f();` keep their documented first-value meaning (the `ret2` / `rethi()` split); a
tuple captures every value by its type instead — `var t: (i64, i64) = f();`.
**Placement:** 6.7.7 — closed by the B4 lane (T5 + T5b); archived at integration.
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
   guide's *Bind the pair as a pair* says "any context that keeps only one … is a compile error"; only
   `var r = f();`, `r = f();` and `store64(&slot, f());` are.
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

## Resolution (6.7.7)

- **Item 4 — delivered (B4 bite T5).** `a, b = f();` / `a, b, c = f();` re-assigns existing variables: the
  destructure's contract (one whole call; its declared arity; a provably one-value callee refused) on 2 or 3 plain
  names, every value pushed before any store, each target stored at its width. A field, subscript, `*p`, tuple element
  or `OP=` target, a const / enum constant, an aggregate / vector / u128 / slice / array / f32 target, a name given
  twice and a bool target whose value is not declared bool are refused by name. The roadmap's first repro now has its
  spelling: `t, v = f(7);`. Gate: `tests/gates/frontend/tuple_checked.sh` rows R18 / R19 / R20.
- **Items 1–2 — settled, no change** (the user's decision, 2026-10-08): a single bind / assignment of a multi-value
  call keeps its first value, as the guide documents; the tuple capture `var t: (i64, i64) = f();` is the spelling that
  keeps them all.
- **Item 3 — fixed (B4 bite T5b; the user's decision, 2026-10-09: refuse).** `_refuse_lossy_pair` runs right before
  the value's parse at the field store (`PARSE_FIELD_STORE`, before the struct-copy dispatch so a struct-typed field is
  covered too; `_slice_fld_store`; `_synonly_fld_tail`, so `cyrius lint` agrees), the subscript store
  (`_arr_sub_assign`), `_deref_store` and `_asg_compound_op` (every compound place: a variable's, a field's, an
  element's, `*p`'s, a for step's; a u128 place's in `_w128_binop`). The issue's second repro reports its first three stores (the panic latch swallows
  the fourth's error in the same fn); each shape alone is one error at its callee. `?` consumes the pair at every one
  of them. Nothing that compiles changed otherwise: the tree's 1035 `.cyr` / `.tcyr` / `.fcyr` / `.bcyr` files compile
  byte-identical (default, `CYRIUS_DCE=1`, `--syntax-only`). Gate: `tests/gates/frontend/stack_enum_lossy_context.sh`
  axis 15 (rows 15a–15z, mutations M24a–M24i).

## Proposed fix (as filed)

Three decisions, all the USER's (each changes what compiles or adds syntax), asked at the 6.7.7 open:

1. **Item 3 (the `: stack` holes)** — call `_refuse_lossy_pair` at the field, subscript, `*p` and `OP=` stores, so
   the guide's "any context that keeps only one" is true. This refuses source that builds today (and silently
   loses the payload).
2. **Items 1–2** — whether a single bind / assignment of a raw or declared pair return is refused (it would break
   the documented `ret2` + `rethi()` split), refused only for a declared `: (T1, T2)` return, or left legal.
3. **Item 4** — whether `t, v = f();` (re-assignment of two existing names) becomes syntax.

Verify with a `tests/tcyr/crossos/` row per refused/accepted shape and a diagnostics gate for each refusal.
