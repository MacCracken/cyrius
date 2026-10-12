# `+| +? -| -?` on a typed pointer add an unscaled count, then hand the result the pointer's step: with `q: *i32`, `(q +| 1) + 1` is `q + 5` — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (is a saturating / checked add of a pointer a pointer?). Raised by
the 6.7.9 critical lane (bite 5, the pointer-step reset), which left these four operators as they are because their
step restore is deliberate code. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379,
2,057,736 B) on x86_64 and aarch64 (qemu): with `q: *i32`, `(q +| 1) + 1`, `(q +? 1) + 1` and `(q -| 0) + 1` are
`q + 5`, `q + 5` and `q + 4` bytes, where `(q + 1) + 1` is `q + 8`. The installed 6.7.0 and 6.7.8 compilers agree.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *The releases after 6.7.8*; the four arms in `_PEXPR_IMPL`,
parse_expr.cyr, beside 6.7.9's pointer-step rules) (the user's call, asked at that release's open) — placed 2026-10-11
— never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's
[pointer-step reset](2026-10-10-pointer-step-leaks-through-operators.md).
**Severity:** Low — a silent mixed result, but only for a saturating or checked add on a typed pointer, which nothing
in the tree writes.
**Affects:** cycc 6.6.17 (typed pointer steps) – 6.7.9, every target (frontend state).

## Summary

The v5.6.2 operators `+|` / `+?` / `-|` / `-?` lower to `_sat_add_i64` / `_chk_add_i64` / `_sat_sub_i64` /
`_chk_sub_i64` (lib/overflow.cyr). Their arm in `_PEXPR_IMPL` sets the step to 0 while it parses the right operand
("overflow ops are defined on integers only"), so `q +| 1` adds ONE BYTE — and then restores the left operand's step
(`SPSC(S, ps)`), so the RESULT is a `*i32` again and the next `+ 1` scales by 4. Neither reading of the operator is
applied whole: as integer arithmetic, the result should carry no step (6.7.9's decision 1(a), "the pointer step resets
after every operator that does not produce a pointer"); as pointer arithmetic, the count should scale (`q +| 1` = `q +
4`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/overflow.cyr"
var buf[64];
fn main(): i64 {
    var q: *i32 = &buf;
    var a = (q +| 1) + 1;
    var d = (q + 1) + 1;
    return (a - &buf) * 10 + (d - &buf);
}
syscall(60, main());
# actual 58 (a = q + 5, d = q + 8)
```

## The decision

- **(a) Integers only (decision 1(a)'s class):** the four operators reset the step, so `(q +| 1) + 1` is `q + 2` —
  the operands are plain words, as their lowering treats them. Recommended: it is what "defined on integers only"
  says, and a saturating add of an address has no clamp that means anything.
- **(b) Pointer arithmetic:** `q +| n` scales `n` by `sizeof(T)` and the result is a `*T` (a saturating pointer add).
- **(c) Refuse a typed pointer operand** by name.

Each changes what such an expression computes (or compiles). Rows in the 6.7.9 pointer-step gate: the four operators
with `*i32` and `*u8` left operands and a following `+ 1`, x86_64 and qemu-aarch64.
