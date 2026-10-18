# A `: **Box<..>` return is read in pass 1: `: **Box<Zork>` is reported twice and `: **Box<Later>` (a struct declared below) is refused — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G2), fixing
issues/archived/2026-10-14-generic-pointer-to-generic-struct-return-refused.md, whose one-star shape (`: *Box<Zork>` twice,
`: *Box<Later>` refused by pass 1) 6.7.14 fixed (`_ret_ptr_sid`, 4a74fe60). Pre-existing: identical on the slot-open
compiler (2600f67f's build/cycc) and on the lane tree (596d1a89).
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a duplicated diagnostic, and a valid program refused (a pointer-to-pointer return naming a
struct declared after the fn as its type argument); workaround: declare the struct above the fn.
**Kind:** bug.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mkz(x): **Box<Zork> { return 0; }
syscall(60, 3);
```

```
$ build/cycc < fb.cyr > fb; echo $?
error:<source>:3:22: unknown type 'Zork' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
error:<source>:3:22: unknown type 'Zork' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
1
```

Expected: the error once (`fn mkz(x): *Box<Zork>` reports it once since 6.7.14).

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Box<T> { v: T; n; }
fn mk(): **Box<Later> { var b: *Box<Later> = alloc(64); b.n = 2; var pp: **Box<Later> = alloc(8); store64(pp, b); return pp; }
struct Later { x; y; }
fn main(): i64 { var q: **Box<Later> = mk(); var b: *Box<Later> = *q; return b.n; }
syscall(60, main());
```

```
error:<source>:4:21: unknown type 'Later' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
```

Expected: compiles, exits 2 — as `fn mk(): *Box<Later>` does since 6.7.14 (generic_struct_field.sh PG7) and
`fn mk(): *Later` always has. Control: the same program with `struct Later` moved above `mk` compiles and exits 2.

## Root cause

`_ret_ptr_record` (src/frontend/parse_types.cyr) reads a `**T` return's pointee pin through `_ek_pin` ->
`_pp_pin_at` -> `_pp_psid` -> `_ptr_ann_sid_tp`, which parses the pointee's `Box<..>` (`_gen_ann_sid` ->
`_parse_one_type_arg`) in pass 1 (`_prescan_ret_type`, `quiet` 1) as well as in pass 2. 6.7.14's `_ret_ptr_sid`
gates only the one-star read on `_targs_resolvable`; the pin read has no `quiet`. In pass 1 a struct declared
below the fn is not registered yet, so its name is refused there.

## Fix direction

In pass 1 skip the pin read too when the pointee's arguments do not resolve (pass 2 reads and refuses it), e.g. a
`_ret_ptr_unres(S, quiet)` that skips the stars and tests the `<..>` with `_targs_resolvable`, used for both the
psid and the pin. Rows: both repros; `**Box<Pt>` with Pt declared above unchanged (its pin, `**q` reads).
