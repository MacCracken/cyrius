# `*p = v` through `p: *f32` / `*i32` is a raw 8-byte word store (documented design gap) — OPEN

**Status:** 🟡 **OPEN** (design gap, documented) — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`:
`*q = 5` through `q: *i32` over `i32[2]` zeroes the NEXT element; `*p = 1.5` through `p: *f32` over `f32[2]` stores
1.5's f64 bits as a word (element 0 = 0x00000000, element 1 = 0x3FF80000) instead of the f32 1.5 (0x3FC00000).
**Placement:** 6.7.8 — features: checked dyn + C2 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.6 review (roadmap commit d2d5309b: "documented — outside 'every f32 write rounds'"); filed
2026-10-08 from roadmap.md.
**Severity:** Low — documented behaviour (guide § Pointers), with a stated workaround (`store32`, or subscript a typed
array); it is a trap, not a miscompile of the documented rule.
**Affects:** cycc ≤ 6.7.6 (`*p = v`, always; `*p OP= v` since 6.7.5)

## Summary

A `*T` variable steps `sizeof(T)` in pointer arithmetic, but `*p` reads 8 bytes and `*p = v` / `*p OP= v` write 8 bytes
whatever `T` is. The guide says so: "`*p = v` and `*p OP= v` (6.7.5) write 8 bytes the same way — `*p += 1` through a
`*i32` is a WORD add over two elements; write `store32(p, load32(p) + 1)` or subscript a typed array for an element."
For `*f32` it also sits outside 6.7.6's rule that "every other write into an `f32` rounds" (the guide's list — an
assignment, a field store, a struct-literal field, an argument — does not include `*p`), so an f64 value is stored as
its 64-bit pattern. Filed as a design gap: the pointer's element type is known at the store and is ignored.

## Reproduction

```cyrius
fn main(): i64 {
    var b: i32[2];
    b[0] = 1; b[1] = 7;
    var q: *i32 = &b;
    *q = 5;                         # writes 8 bytes: b[1] becomes 0
    var a: f32[2];
    store32(&a + 4, 0x40400000);    # a[1] = 3.0f
    var p: *f32 = &a;
    *p = 1.5;                       # 1.5's f64 bits as a word: a[0] = 0, a[1] = 0x3FF80000
    var e = 0;
    if (b[0] != 5) { e = e | 1; }
    if (b[1] != 7) { e = e | 2; }
    if (load32(&a) != 0x3FC00000) { e = e | 4; }      # f32 1.5
    if (load32(&a + 4) != 0x40400000) { e = e | 8; }  # a[1] untouched
    return e;
}
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected under an element-width rule: 0. Actual (the documented rule): **14** (= 2 | 4 | 8), no diagnostic.

## Root cause

`_deref_store` (`src/frontend/parse.cyr:3180`) parses the address, then the value, and emits `ESTORE64` — a word
store — with no look at the pointer's element type; the compound arm loads with `ELOAD64` and stores the word back.
The factor `*p` (the read) is the same 8-byte `ELOAD64`.

## Proposed fix

A language decision — **the user's**, since it changes what existing programs do (a `*i32` store that today writes 8
bytes would write 4; `*p` reads would narrow and sign-extend): make `*p` / `*p = v` / `*p OP= v` element-width for a
narrow scalar `T` (`*i8`..`*i32`, `*u8`..`*u32`, `*f32` with the 6.7.6 f64 → f32 rounding), as a typed-array subscript
already is (`_arr_sub_load` / `_arr_sub_assign`). The conservative alternative inside the current rule: WARN on
`*p = v` / `*p OP= v` through a `*T` whose `sizeof(T) < 8` (the store writes past the element), and on an f64 value
stored through `*f32`. Either way, a `tests/tcyr/crossos/` row (x86, aarch64, PE, cx).
