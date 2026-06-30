# Single-field struct segfaults (P2, pre-existing) — NOT a generics bug

**Discovered:** 2026-06-30 during v6.3.10 generic-struct premise-check.
**Severity:** P2 (a real codegen bug; narrow trigger — exactly one i64-shaped field).
**Affects:** cycc struct codegen, all targets (reproduced flag-off → not generics-related).

## Repro (minimal, non-generic)

```
struct B1 { val: i64; }
fn main(): i64 { var b: B1; b.val = 42; return b.val; }
```

Exits **139 (SIGSEGV)**. The 2-field analogue is fine:

```
struct B2 { a: i64; b: i64; }
fn main(): i64 { var b: B2; b.a = 40; b.b = 2; return b.a + b.b; }   # → 42
```

So the trigger is a struct with **exactly one 8-byte field** used as an
uninitialized stack local (`var b: B1;`) with field store/load. 2+ field
structs work; generic 2/3-field structs (`Pair<T>`, `Tri<T>` over i64) work.

## Why it surfaced now

v6.3.10 tested `struct Box<T> { val: T; }` (a single-field generic struct) and it
segfaulted — but the same failure reproduces **flag-off** and **non-generic**
(`B1`), so it is a standalone single-field-struct codegen bug, NOT a generics
defect. Generic structs over i64 otherwise work (the base-is-i64 pattern:
`val: T` registers as an untyped 8-byte field).

## Likely area

The `pscale < 0 && PEEKT == 5` uninitialized-struct-local path
(`parse_decl.cyr` ~1197): it reserves `ceil(STRUCTSZ/8)` slots with the last
slot named + `ltype = -sid`, and `&b` points at the deepest slot. For a
single-8-byte-field struct (`ceil(8/8) = 1` slot), there are zero filler slots
and exactly one named slot — an off-by-one in the slot reservation / `&b`
disp likely points one slot off, so `b.val = …` writes out of frame → fault.
Bisect the slot-reservation arithmetic for the `STRUCTSZ <= 8` (single-slot)
case.

## Status

Filed 2026-06-30. Independent of the generics arc; fix in a future codegen slot.
