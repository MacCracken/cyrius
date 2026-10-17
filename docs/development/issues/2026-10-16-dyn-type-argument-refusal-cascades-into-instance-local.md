# `var a: Box<dyn Show>;` reports a second error after the dyn type-argument refusal, naming the instance `Box$dyn Show` — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G2), probing the tokens a type argument
can hold (issues/2026-10-14-type-argument-non-name-reported-with-garbage-name.md). Pre-existing: identical on the
slot-open compiler (2600f67f's build/cycc) and on the lane tree (596d1a89).
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a second, misleading error on input already refused (no binary either way); the second line
names a compiler-internal instance name and asks for an initialiser the type can never have.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Box<T> { v: T; }
fn main(): i64 {
    var a: Box<dyn Show>;
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < fc.cyr > fc; echo $?
error:<source>:5:16: dyn Show cannot be a type argument - a collection holds pointers to records that hold a dyn
error:<source>:5:12: declare Box$dyn Show 'a' with its value - it holds a dyn, struct locals are not zeroed, and a dyn's vtable is formed, never left to the frame
1
```

Expected: the first line only.

## Root cause

The dyn type-argument refusal is made in the dyn pre-pass (`_dyn_pos` -> `_dyn_targ`, src/frontend/parse_types.cyr),
which leaves the `dyn Show` token an identifier naming the dyn's struct. `_parse_one_type_arg` then reads it as a
struct type argument and `Box$dyn Show` is minted — a struct holding a dyn — so the declaration meets
`_dyn_uninit`'s refusal of an uninitialised dyn-holding local, at the annotation's `Box` (another token, so the
`_tn_once` latch does not apply).

## Fix direction

Read a refused dyn type argument as the i64 base (`0 - 8`) in `_parse_one_type_arg` — the pre-pass already reported
it — and set the explicit-call latch `_ta_refd` (6.7.14) so `g<dyn Show>(o)` mints no instance either. Rows: the
repro (one line); `g<dyn Show>(o)` once; a `dyn Show` field / parameter / local unchanged.
