# A parenthesised `&f` callee (`callptr((&mk3), 5)`, `fncall1((&mk2), 5)`) is an unknown callee: its struct / vector result convention is lost — SIGSEGV — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 callargs lane (after its review fixes, x86_64) and the
slot-open compiler (`0f733aea`), alike; the lane's review measured aarch64 / cx / PE too. 6.7.11 gives a struct result
through `fncallN(&f, ..)` / `callptr(&f, ..)` the struct-call hooks when the callee is KNOWN — written `&f`, unwrapped
(`2026-10-12-struct-result-through-fn-pointer-faults.md`). The same callee in parentheses, `(&mk3)`, is not recognised,
so the call has no hidden result pointer / pair receive and the struct-typed receive takes a word: `var p: P3 =
callptr((&mk3), 5);` exits 139 on x86_64 and aarch64, 1 on cx and 5 on PE, where `callptr(&mk3, 5)` gives 18 on all four.
**Placement:** 6.7.13 — repair 3: struct values (receives lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the review of the 6.7.11 callargs lane (probes review/rev/sr/x1-x7).
**Severity:** Medium — a SIGSEGV / wrong value on valid code; the unwrapped spelling is the working one.
**Affects:** every release through 6.7.11 (through 6.7.10 the unwrapped spelling faulted too); every target.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
struct P2 { a; b; }
struct P3 { a; b; c; }
fn mk2(a): P2 { var r: P2 = P2 { a, a + 1 }; return r; }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
fn s3(p: P3) { return p.a + p.b + p.c; }
fn s2(p: P2) { return p.a + p.b; }
fn main() { var p: P3 = callptr((&mk3), 5); return p.a + p.b + p.c; }
var r = main();
syscall(60, r);
```

```
$ build/cycc < x1.cyr > x1 && ./x1; echo $?          # the lane compiler and the slot-open one alike
139                                                   # aarch64 (qemu) 139, cx (cxvm) 1, PE (wine) 5; callptr(&mk3, 5): 18
```

The same with `main` returning `s3(callptr((&mk3), 5))` (139), `s3p(callptr((&mk3), 5))` into `p: *P3` (139),
`s2(fncall1((&mk2), 5))` (139), `var p: P2 = fncall1((&mk2), 5);` (139); `return callptr((&mk3), a);` from a fn declared
`: P3` is refused "struct-return fn: return must be a bare local identifier, or a call to a fn returning the same
struct"; `var v: f64v2 = callptr((&mkv), 4, 1);` is refused by the 6.7.11 vector-local rule. The 8 B `s1(fncall1((&mk1),
5))` gives 8 (a word is the struct there).

## Root cause

The known-callee test reads the callee unwrapped only: `_icall_callee` (parse_expr.cyr) requires the callee expression
to be exactly `& IDENT` (`TOKTYP(cst) == 27`, two tokens), and the token route used before the parse — `_icall_rs_at` /
`_icall_sid_at` (the argument, `return` and declaration-zone routes) — requires `&` right after the call's `(`. A
whole-callee wrap (`_pwrap_k`) is transparent nowhere on this path.

## Proposed fix

Peel parentheses wrapping the WHOLE callee argument (as 6.7.6 made them transparent for a struct argument): in
`_icall_callee` (the callee span `cst` .. the cursor) and in `_icall_rs_at` (`o + 1`), using `_pwrap_in` (parse.cyr,
6.7.11). Rows beside struct_value_codegen.sh FP1-FP9 and tests/tcyr/crossos/fncall_struct_result.tcyr (x86 / IR / DCE /
aarch64 / cx / PE), plus the vector receive in simd_return_shapes.sh.

## Acceptance

- D28 (the user, 2026-10-15: "refused as D24 refuses mk3(5)", the wrapped callee `(&mk3)` too, via this issue):
  `var n: i64 = fncall1((&mk3), 5);` / `var n: i64 = callptr((&mk3), 5);` refused with D24's words naming mk3
  ("cannot initialise 'n: i64' from 'mk3', which returns the struct 'P3' - declare 'n: P3' or bind a field") — add the
  row beside struct_receive_inference_checked.sh FP0-FP10 (6.7.12 fixfirst shipped the unwrapped `&mk3` half there;
  FP9 wraps the whole call, `((fncall0(&mk3)))`, not the callee). Measured on the 6.7.12 fixfirst lane: both compile
  with no diagnostic and exit 139 (x86_64), as on 6.7.11.
