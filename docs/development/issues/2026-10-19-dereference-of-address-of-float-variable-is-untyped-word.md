# `*(&f)` of an `f64` variable is the untyped integer word, not f — `*(&f) + 1.0` is integer arithmetic (warned) where `f + 1.0` is 2.5 — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S5) while landing D21 (the user's decision,
2026-10-19: `*(&x)` of a narrow INTEGER x reads and writes x's width, as x itself). The float (and `bool`) scalars are
outside that decision's question ("a narrow integer variable x (i32, i16, u8 ...)"), so S5 left them as they were:
the dereference is the untyped 8-byte load of the slot. Pre-existing: the same output on the lane's compiler before S5
(45135d7db) and after it (x86_64). Filed because 6.7.15's D21 vidya line reads `*(&x)` as x "for every x the compiler
types", which a float x is not.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — an unusual spelling (`*(&f)` for `f`); the arithmetic form warns ("integer arithmetic with an f64
right operand"), and the bits are f's, so a store or a copy keeps the value; only typed use (an operator, a float
parameter's conversion) goes wrong. Not a security id (the developer's own source).
**Kind:** language (a decision): is `*(&f)` of an `f64` / `f32` / `bool` variable f (typed), or does the guide name the
exception?

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
fn main(): i64 {
    var f: f64 = 1.5;
    var g: f64 = *(&f) + 1.0;
    var h: f64 = f + 1.0;
    pr(f64_to(g * 10.0)); pr(f64_to(h * 10.0));
    var s: f32 = 2.5;
    pr(*(&s) == s);
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < fb.cyr > fb; ./fb
warning:<source>:6:29: integer arithmetic with an f64 right operand
9223372036854775807 25 1        # g is f's bits plus 1.0's bits as integers; `f + 1.0` gives 25 (2.5)
```

## Root cause

`_deref_read` (src/frontend/parse_expr.cyr) types `*(& NAME)` only for a typed pointer (`_amp_pw`, 6.7.15's D21 A), a
struct (`_hl_dpsid`), a vector (`_amp_vd`) and, since 6.7.16, a narrow integer (`_amp_ew`); an `f64` / `f32` local or
global (SLTYPE / GVTYPE `F64_TYID` / `F32_TYID`) and a `bool` (GLBOOL / GVBOOL) get the untyped `ELOAD64`, with no
SESTYPE and no boolean mark.

## Fix direction

If `*(&f)` is f: in `_deref_read`, an `& NAME` operand naming an `f64` / `f32` / `bool` scalar sets the value's type
as the name's own read does (SESTYPE F64_TYID / F32_TYID, the bool mark); stores through it are already word stores
(both slots are 8 bytes). Otherwise the guide's D21 paragraph names the exception.
