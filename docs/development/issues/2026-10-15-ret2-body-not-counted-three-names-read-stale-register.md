# A fn whose values come from `ret2(a, b)` is not counted by pass 1: `var a, b, c = g2();` binds `c` to a stale register — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 multivalue lane (l6713-multivalue, unit M4, the lane tip
f980a663 and its parent 68d421a8 alike) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (multivalue lane; filed from the 6.7.13 multivalue lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — a silent wrong value on code that compiles clean: the third name reads whatever an earlier call
left in the third return register (88 seeded, every target); the same symptom 6.7.11's pass-1 count closed for the
`return (a, b);` spelling.
**Discovered:** 2026-10-15, the 6.7.13 multivalue lane (M4), while pinning D23 B's rows for
issues/archived/2026-10-14-scalar-declared-fn-returning-multi-value-literal.md (whose triage read "the count is already
enforced by pass 1" — true of a `return (1, 2);` body only). The gap is not scalar-specific: an undeclared `ret2` fn,
the legacy idiom the guide § Multi-Return shows, has it too, so it is outside that issue's filed surface.

## Reproduction

```sh
cd <the cyrius tree>
printf 'fn h(): (i64, i64, i64) { return (1, 77, 88); }\nfn g2() { ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g2(); return c; }\nsyscall(60, main());\n' > r2.cyr
build/cycc < r2.cyr > r2 && chmod +x r2 && ./r2; echo $?
# 88    (compiles clean; `fn g2() { return (1, 2); }` is refused "multi-value destructure binds 3 names, but 'g2'
#        returns 2 values")
```

| `g2` / the bind | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (wine) |
|---|---|---|---|---|
| `fn g2() { ret2(1, 2); }` / `var a, b, c = g2();` | 88 | 88 | 88 | 88 |
| `fn g2(): i64 { ret2(1, 2); }` / `var a, b, c = g2();` | 88 | 88 | 88 | 88 |
| `fn g2(): i64 { return ret2(1, 2); }` / `var a, b, c = g2();` | 88 | 88 | 88 | 88 |
| `fn g2() { ret2(1, 2); }` / `var t: (i64, i64, i64) = g2();` (`t.2`) | 88 | 88 | 88 | 88 |
| `fn g2(x) { if (x > 0) { ret2(1, 2); } else { return (3, 4); } }` / `var a, b, c = g2(1);` | 88 | 88 | 88 | 88 |
| `fn g2() { return (1, 2); }` / `var a, b, c = g2();` | refused | refused | refused | refused |

(each program seeds the third register first with `var x, y, w = h();`)

## Root cause

`_prescan_ret_arity` (`src/frontend/parse_fn.cyr`, 6.7.11) records an undeclared fn's count only when every `return` is
`return (..);` of one arity and the body is left only through them (`_body_ends_in_return`); a `ret2` token (97) in
the body leaves the record empty by design ("Conservative: ... no `ret2` / `asm` / `?`"), and so does a body whose last
statement is `ret2(..);` (not a `return`). With no record, `_dt_arity_check` (parse_decl.cyr) and the tuple capture
(`_tup_cap_class`) accept any count. `ret2` always writes exactly two values, so a body left only through `ret2` /
`return ret2(..)` / `return (a, b);` returns two.

## For the user

Counting `ret2` as two values in pass 1 (a `ret2(..);` statement or `return ret2(..);` as a two-value exit, a final
`ret2(..);` as leaving the body) refuses `var a, b, c = g2();` and the 3-tuple capture against such a fn by the
existing text — it stops compiling code that compiles today (it bound a stale register), so it is the user's call.
Rows would join tests/gates/diagnostics/destructure_one_value_refused.sh axis 4 (cnt_ rows) and tuple_checked.sh's
R16 captures; the two-name binds of a `ret2` fn (the guide's `divmod_old`) are unchanged.
