# `gp().n = 5` through a `*T`-returning call is refused as "the result is a temporary" — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`: `gp().n = 5;` and
`gp().m += 5;` with `fn gp(): *H` are refused "cannot assign to a field of a call result: the result is a
temporary"; the READ `var q = gp().n;` and `var p: *H = gp(); p.n = 5;` compile and write the pointee.
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 6.7.5 decisions pass (roadmap commit 68de8001); filed 2026-10-08 from roadmap.md.
**Severity:** Low
**Affects:** cycc 6.6.17 – 6.7.6 (the read has worked since 6.6.17's `: *T` arm; the store refusal dates from 6.6.12)

## Summary

A field store on a call result is refused with a reason ("the result is a temporary") that is true for a struct
returned BY VALUE (the retptr / rax:rdx temp) and false for a `: *T` return: the result is a pointer to storage
that outlives the statement — exactly what `p.n = 5` through `var p: *H = gp();` writes. The workaround is a
named `*T` local. Whether a field of a returned pointer is an lvalue is a language question (the user's call); at
minimum the diagnostic misstates why.

## Reproduction

```cyrius
struct H { n; m; }
var buf[16];
fn gp(): *H { return &buf; }
fn main() {
    gp().n = 5;
    return load64(&buf);
}
var r = main();
syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r
```

Actual: `error:<source>:5:12: cannot assign to a field of a call result: the result is a temporary` (the same for
`gp().m += 5;`). Control: `var p: *H = gp(); p.n = 5; var q = gp().n;` builds and exits 10 (both see 5).
Expected: either the store compiles and writes `buf` (exit 5), or a refusal that names the real rule.

## Root cause

`_stmt_call_field` (`src/frontend/parse_expr.cyr:2162`) runs `_call_field`, then refuses ANY `=` / `OP=` after the
field chain via `_asg_temp_refused` (`parse_expr.cyr:2172`). `_call_field` (`parse_expr.cyr:2117`) already
distinguishes the `: *T` return — it routes it to `_call_ptr_field` (`src/frontend/parse_decl.cyr:1443`, 6.6.17),
which loads through the pointer — but the statement form does not consult that distinction before refusing.

## Proposed fix

The USER decides whether `f().field = v` / `OP= v` is legal when `f` returns `*T` (it makes code that is refused
today compile; no existing program changes meaning). If yes: in `_stmt_call_field`, for a `: *T` callee, compute
the field's address from the returned pointer (the `_call_ptr_field` base, plus the `_fld_addr_ra` offset/width
logic) and store through it as `PARSE_FIELD_STORE` does for a `*T` local, `=` and `OP=` alike. If no: keep the
refusal but word it for the pointer case ("bind the pointer first: `var p: *H = gp();`"). Either way, the
by-value struct return keeps today's refusal.

## Related (found 2026-10-08 while filing)

`var p = gp();` with `fn gp(): *H` leaves `p` without a struct type — `p.n = 5` then fails with "no struct type in
scope for 'p'" — while `var p: *H = gp();` works. Whether an untyped `var` should take a `*T` return's pointee type is
the same language question.
