# A signed narrow global (`i8` / `i16` / `i32`) declared after the first top-level statement reads zero-extended — `var GS: i16 = 0 - 2;` after `Z = 1;` reads 65534 — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S5) while writing the D21 rows (`*(&x)` of a
narrow integer x at its width): a row's `i16` global, declared after the rows file's first top-level statement, read
65534 for -2 — through `x` itself and so through `*(&x)`, which reads as x does. Pre-existing: the same output on the
lane's compiler before S5 (45135d7db) and after it; x86_64, aarch64 (qemu), cx (cxvm) and PE (wine) alike. Not D21's
filed surface (`*(&x)` agrees with `x` either way), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Medium — a silent wrong value: every read of the global (a plain read, a comparison, arithmetic, an
argument) takes the zero-extended bytes, so a negative value reads as a large positive one; the store is right. Any
program with a top-level statement (`alloc_init();`, `main();`) before a signed narrow global meets it. Not a security
id (the developer's own source).
**Kind:** bug.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
var Z = 0;
Z = 1;
var GS: i16 = 0 - 2;
var GI: i32 = 0;
var GB: i8 = 0;
fn main(): i64 {
    GI = 0 - 2;
    GB = 0 - 2;
    pr(GS); pr(GI); pr(GB);
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < ng.cyr > ng; ./ng          (rc 0, no diagnostic; aarch64 / cx / PE print the same)
65534 4294967294 254
                                          # without the `Z = 1;` line: -2 -2 -2
```

## Root cause

A global declared after the first top-level statement is registered by PARSE_VAR's top-level arm (the PARSE_PROG
path, src/frontend/parse_decl.cyr — the `scalar_type > 0` / `scalar_type < 8` arm after `_sc_global_receive`), which
writes the var size, SVTYPE and EVSTORE_W but not the sign mark: GVSGN stays 0, so the name's read (`EVLOAD_W` with a
positive width, parse_expr.cyr) zero-extends. A global in the declaration zone goes through PARSE_GVAR_REG, which sets
`SVSGN(S, vcnt, ann_signed)` (v6.4.23). Measured in a scratch tree: adding `SVSGN(S, vcnt, scalar_signed);` to that arm
prints `-2 -2 -2` for the repro (not committed: it changes what a program computes).

## Fix direction

Set the sign mark in the PARSE_PROG arm as PARSE_GVAR_REG does (`scalar_signed` is in scope there), with rows for a
read, a comparison, arithmetic, `*(&GS)`, an initialiser and an assignment, at each of `i8` / `i16` / `i32`, on
x86_64 / aarch64 / cx / PE; and check the arm's other marks against PARSE_GVAR_REG's (a bool, a float, a `*T`).
