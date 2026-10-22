# A value builtin as a bare statement: `load8(p);` compiles while `load16(p);` / `load32(p);` / `load64(p);` / `f32_from(x);` / `f32_to(x);` are "unexpected load16" — OPEN

**Status:** 🟡 **OPEN** — whether a value builtin may stand as a statement, and in which words it is refused, is beyond
6.7.16's D11 (which decided `mulh64(..);` / `sizeof(..);`); the f16 lane stopped on it.
**Placement:** unplaced — filed at the 6.7.16 close (2026-10-21); the user places it — never 7.x.
**Discovered:** the f16 lane, unit FF6.
**Severity:** Low — one builtin compiles where its five siblings are refused, and the refusal's words are the generic
"unexpected".
**Kind:** decision.

## Summary

6.7.16's D11 refused `mulh64(2, 3);` and `sizeof(H);` as statements: "the value of 'mulh64(..)' is discarded - a
statement is an assignment or a call". Its reason said "every other value-only statement is already refused:
'load64(&g);'". That holds for `load16` / `load32` / `load64` / `f32_from` / `f32_to`, refused as "unexpected <name>" —
but `load8(p);` compiles (parse.cyr's builtin statement arms list `load8` and not the others).

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B); the `load8`
row also on aarch64, cx and PE: the same.

```cyrius
var b: i64 = 7;
fn main(): i64 { var p = &b; load8(p); return 3; }
syscall(60, main());
```

rc 0, no diagnostic, exit 3. With `load16(p);` in its place:

```
error:<source>:2:30: unexpected load16
```

`load32(p);` and `load64(p);` the same ("unexpected load32" / "unexpected load64"); `fn main(): i64 { var x = 3;
f32_from(x); return 3; }` gives `error:<source>:1:29: unexpected f32_from`, and `f32_to(x);` "unexpected f32_to".

## The decision

- (a) Refuse all six with D11's words ("the value of 'load8(..)' is discarded - a statement is an assignment or a call"):
  `load8(p);` stops compiling; the other five keep failing, in D11's words.
- (b) Keep `load8(p);` compiling (a load whose value is dropped) and give the other five D11's words.
- (c) Accept all six as statements, value dropped (the five newly compile).

## Acceptance

The six statements give the decided result on x86_64, aarch64, cx and PE, once each, with the next statement still
reporting its own error; `var v = load8(p);` and every store builtin (`store8(p, v);`) unchanged.
