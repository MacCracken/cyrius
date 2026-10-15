# `ret2(a, b)` in a fn returning a struct over 16 B or of 8 B or less takes the multi-value path — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 struct lane (`l6711-struct`, unit S6, after the
tuple-literal refusal of issues/archived/2026-10-08-struct-operator-results.md #4) on x86_64, aarch64 (qemu), cx (cxvm)
and PE (wine).
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 struct lane) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (S6), while refusing `return (a, b);` in a struct fn.
**Severity:** Medium — a silent wrong value on code that compiles clean (the retptr is never written, or the
second value is dropped); the builtin is rarely written in a struct fn.
**Affects:** every target; at least 6.6.x – 6.7.11 (the `ret2` landing is `_mret_land`, unchanged since 6.7.7).

## Summary

6.7.11 refuses the tuple LITERAL `return (a, b[, c]);` in a fn declared to return a named struct, in every
size class (the user's decision, 2026-10-13: a tuple is another type). The builtin statement `ret2(a, b)` is the
same multi-value landing (`_mret_land`: rax:rdx, then the epilogue) and is not judged by the enclosing fn's
struct class:

| class | `fn f(a, b): S { ret2(a, b); }` received as `var q: S = f(1, 2);` |
|---|---|
| over 16 B (`P3 { x; y; z; }`, a hidden result pointer) | the result pointer is never written: q = 0, 0, 0 |
| 8 B or less (`S8 { v; }`, one register) | the second value is dropped silently: q.v = 1 |
| 9-16 B (`Pt`) | the two words, by ABI coincidence (rax:rdx; aarch64 syncs x1 from x2, 6.7.7) |

## Reproduction

```sh
cd <the cyrius tree>
printf 'struct P3 { x; y; z; }\nfn f(a, b): P3 { ret2(a, b); }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x * 100 + q.y * 10 + q.z; }\nsyscall(60, main());\n' > p_ret2.cyr
printf 'struct S8 { v; }\nfn f(a, b): S8 { ret2(a, b); }\nfn main(): i64 { var q: S8 = f(1, 2); return q.v; }\nsyscall(60, main());\n' > p2_ret2.cyr
for f in p_ret2 p2_ret2; do build/cycc < $f.cyr > $f && chmod +x $f && ./$f; echo "$f: $?"; done
# p_ret2: 0      (expected 120 if it were the struct { 1, 2, 0 }, or a refusal)
# p2_ret2: 1     (b dropped)
```

Measured (x86_64 / aarch64 qemu / cx cxvm / PE wine): p_ret2 exit 0 on each, p2_ret2 exit 1 on each. The
tuple-literal spelling of both is refused since 6.7.11 (`a fn returning the struct `P3` returns that struct —
`(a, b)` is a tuple, another type`).

## Root cause

`ret2(a, b)` (`src/frontend/parse_expr.cyr`, the `ret2` builtin arm, ~:6256) loads rax:rdx and lands through
`_mret_land` (`src/frontend/parse_fn.cyr`), which consults `_cur_fn_ret_sid` only for a dyn (refused) and the
9-16 B pair (ESTRUCT_PAIR_HI_SYNC). A retptr fn's result pointer and an 8 B fn's one-register class are never
considered. The tuple literal is now refused in `_refuse_struct_tuple_return` (called from
`_refuse_vector_tuple_return`, PARSE_RETURN's multi-value arm); `ret2` never reaches that arm.

## For the user

Whether `ret2(a, b)` in a fn returning a named struct is refused (as the tuple literal now is, in every class,
or only where it is wrong: over 16 B and 8 B or less) is a language question: the 9-16 B form gives the right
words today and tests/tcyr/crossos/struct_pair_multi_value_crossing.tcyr, cx_struct_pair.sh P8b,
simd_return_shapes.sh A7 and multi_value_into_named_struct.sh C2 rely on it (6.7.11 moved their tuple
producers to `ret2`).
