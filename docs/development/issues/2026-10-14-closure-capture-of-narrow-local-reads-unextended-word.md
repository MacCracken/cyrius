# A closure's capture of a narrow scalar local (`i8` .. `i32`, `u8` .. `u32`) reads the slot's whole 8-byte word: a negative value is zero-extended, and stale upper bytes come along — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F4, build/cycc 2,194,096 B)
on x86_64 (plain and CYRIUS_IR=3), aarch64 (qemu) and cx (cxvm), and on the installed 6.6.0 and 6.7.9 compilers:
identical on x86 everywhere.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F4, while adding a narrow-capture row for
`issues/2026-10-11-narrow-scalar-local-and-address-of-carry-byte-pointer-step.md` (that issue is about the pointer
STEP of a narrow local; this is the captured VALUE, outside its filed surface).
**Severity:** High — a silent wrong value: a captured `i8` / `i16` / `i32` holding a negative number reads as its
unsigned bit pattern on every target, and on aarch64 / cx (and on x86 in some frame layouts) a positive one reads
with whatever the slot's upper bytes held.
**Affects:** cycc 6.6.0 – the 6.7.11 genfe lane tree (measured 6.6.0, 6.7.9, the lane). Every target.

## Reproduction

```cyrius
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/fnptr.cyr"
fn neg8(): i64 { var b: i8 = 0 - 3; var k = |z| b + z; return callptr(k, 0); }
fn neg16(): i64 { var b: i16 = 0 - 3; var k = |z| b + z; return callptr(k, 0); }
fn neg32(): i64 { var b: i32 = 0 - 3; var k = |z| b + z; return callptr(k, 0); }
fn dirty(): i64 { var a = 0 - 1; var b = 0 - 1; var c = 0 - 1; var d = 0 - 1; var e = 0 - 1; return a + b + c + d + e; }
fn pos8(): i64 { var b: i8 = 5; var k = |z| b + z; return callptr(k, 2); }
fn pos16u(): i64 { var b: u16 = 5; var k = |z| b + z; return callptr(k, 2); }
fn main(): i64 {
    alloc_init();
    fmt_int(neg8()); syscall(1, 1, " ", 1);
    fmt_int(neg16()); syscall(1, 1, " ", 1);
    fmt_int(neg32()); syscall(1, 1, " ", 1);
    var x = dirty();
    fmt_int(pos8()); syscall(1, 1, " ", 1);
    x = dirty();
    fmt_int(pos16u()); syscall(1, 1, "\n", 1);
    return 0;
}
syscall(60, main());
# expected: -3 -3 -3 7 7
```

```
x86_64 (plain, CYRIUS_IR=3; 6.6.0, 6.7.9, the lane): 253 65533 4294967293 7 7
aarch64 (qemu):                                      139792058679549 65533 4294967293 -249 -65529
cx (cxvm):                                           253 65533 4294967293 -249 -65529
```

The same locals read in their own fn (`return b;`) give -3 and 5 everywhere: only the capture is wrong. On x86 a
positive value can carry stale bytes too — measured in a file where earlier fns left the slot dirty
(`var b: i8 = 5; var c: u16 = 9; var k = |z| b + z;` returned 140727796736007, low byte 7, for 7).

## Root cause

A narrow local's frame slot holds its value only in its low 1 / 2 / 4 bytes: the local-read arm of
`_PARSE_FACTOR_IMPL` (src/frontend/parse_expr.cyr) loads it with `EFLLOAD_W(S, li, _lw)` at its width, sign-extended
when the slot's slice-width sentinel is negative (v6.3.35). The closure env copy does not: `_cl_emit_cap_word`
(parse_expr.cyr) copies a single-word capture with `EFLLOAD(S, base - k)`, the slot's whole 8 bytes, and the closure's
read, `_cl_cap_load`, is `ELOAD64` — no width, no sign. So the env word is the raw slot: a negative `i8` arrives as
`0x..FD` (253) over whatever the upper 7 bytes held.

## Proposed fix

Copy a narrow capture at its width into the env word (`EFLLOAD_W` with the signed width, as the local-read arm does),
so the env holds the extended value and `_cl_cap_load`'s `ELOAD64` reads it right; or extend at the read from the
snapshot's type. Rows: a crossos `.tcyr` with each of `i8` / `i16` / `i32` / `u8` / `u16` / `u32` captured holding a
negative and a positive value after a stack-dirtying call, read in a closure and a nested closure, and in a coroutine
body (CYRIUS_ASYNC=1, x86) — on x86_64, aarch64 (qemu), cx and PE.
