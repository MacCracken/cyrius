# A generic fn's `pp: **Box<T>` parameter (T its own type parameter) is refused "unknown type 'T' as a type argument", where `p: *Box<T>` compiles — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S2), probing the generic-call arm of the
`**pp` struct-value fix (issues/archived/2026-10-16-struct-double-pointer-dereference-is-no-struct-value.md). Pre-existing:
identical on f133fb2f's build/cycc (the 6.7.14 wave-2 base) and on the lane tree after S2 (9498bfb3).
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Medium — a valid program is refused (no workaround but a one-star `*Box<T>` and a cast); no miscompile.
**Kind:** bug — the generics' `**T` family (issues/archived/2026-10-16-generic-double-pointer-parameter-pointee-unbound.md: a
`pp: **T` parameter's pin unbound; issues/2026-10-16-double-pointer-generic-return-read-in-pass-one.md: a `: **Box<..>`
RETURN read in pass 1). Neither covers a `**G<T>` PARAMETER whose type argument is the fn's own T.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn nb<T>(pp: **Box<T>): i64 { var b: *Box<T> = *pp; return b.n; }
fn main(): i64 { var x: Box<i64>; x.n = 7; var p: *Box<i64> = &x; return nb(&p); }
syscall(60, main());
```

```
$ build/cycc < nb.cyr > nb; echo $?
error:<source>:3:21: unknown type 'T' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
    fn nb<T>(pp: **Box<T>): i64 { var b: *Box<T> = *pp; return b.n; }
                        ^
1
```

The same on the aarch64 and cx compilers (one error). Expected: compiles, exits 7. Control — one star, the same
program otherwise (`fn nb<T>(pp: *Box<T>)` with `var b: *Box<T> = pp;` and `nb(p)`): compiles, exits 7.

## Root cause (by the message; not traced to the line)

A `**T` parameter records its pointee's pin (`_ek_pin`, src/frontend/parse_fn.cyr ~12190 — the parameter's slot word;
`_pp_pin_at` -> `_pp_psid` -> `_ptr_ann_sid_tp`, src/frontend/parse_types.cyr), which parses the pointee's `Box<T>` as
a type argument list. That read runs where `T` is not bound (the one-star `*Box<T>` parameter reads its struct under the
base's binding), so `T` is refused as an unknown type. The `: **Box<..>` return's pass-1 read (the sibling issue) is
the same reader at another site.

## Fix direction

Read the parameter's pin under the binding the parameter scan gives the one-star `*Box<T>` (the base: T -> i64; an
instance: its own), or defer it to the instance as `_ret_ptr_annot` binds a `: *T` return. Rows: the repro (7); `**Box<T>`
inferred and explicit (`nb<i64>(&p)`); `**pp` of it as the struct value (6.7.14's `_hl_dref_psid`); a `**Box<Pt>`
parameter (concrete) unchanged.
