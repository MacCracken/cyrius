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

✅ **RESOLVED — v6.3.16.** Root cause confirmed via disasm + a cross-backend matrix
(x86 / aarch64 / cx): a single-≤8-byte-field inline struct local occupies exactly one
slot with no `-1` filler, so `PARSE_FIELD_LOAD`/`STORE`'s inline-vs-pointer
disambiguation ("is the previous slot the `-1` sentinel?") misclassified the named
slot as a single-slot **pointer-to-struct** → emitted `mov [slot]` (deref the slot's
value as a pointer) instead of `lea &slot` → SIGSEGV on **x86 AND aarch64** (cx was
already correct — it boxes structs as pointers, so pointer mode is right there).
**Fix (`parse_decl.cyr`, both disambiguation sites):** a struct-local whose type fits
in `STRUCTSZ <= 8` occupies one slot that HOLDS THE VALUE (inline) — never a pointer —
so force `is_ptr = 0` (`lea`). Only `STRUCTSZ > 8` single-slot locals are genuine
pointers (Str, 16 B via rax). **Gated on `_TARGET_CX == 0`** (inline-struct backends);
cx keeps pointer mode so its struct-byval parity test stays green. (A first attempt —
reserve a filler — was reverted: it perturbed the cx layout + the struct-return path.)
Verified field-access `struct{i64}` = 42 / `struct{i32}` = 7 and by-value
`var p:S=mkp()` = 42 on **x86 + aarch64 + cx**; 2-field control unchanged. Fixpoint +
seed-derive OK. See `tests/tcyr/struct_local_codegen.tcyr`, CHANGELOG [6.3.16].

(Note: an inferred/explicit **>8 B** struct-by-value on **cx** hard-errors "int-class
16B struct pair-return ABI not supported" — a pre-existing cx limitation, identical for
`var p: Pt = mk()` and `var p = mk()`, out of scope here.)
