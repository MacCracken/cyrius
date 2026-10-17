# `*pu` through a `*u128` reads and writes only the low 8 bytes, silently — a declaration, a comparison, an if-expression branch and a store — where `pu[0]` is refused by name — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane's review (unit S3, beside
issues/2026-10-15-vector-dereference-as-if-expression-branch-is-lane-zero.md, 896c2d32) as "a `*u128` dereference as an
if-expression branch yields the low word where a `u128` name branch is refused"; the premise check the review asked for
was run by the lane's fix step: `*pu` is the low word at EVERY use, not only as a branch. Measured on the lane's tree
and at the lane base f133fb2f (the same output on both): x86_64, aarch64 (qemu) and cx (cxvm) alike. Pre-existing.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs review, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — silent: `var x: u128 = *pu;` drops the high 64 bits, `*pu = b` writes half the value and leaves
the old high word. (The review rated the branch alone Low.) Not a security id (the developer's own source).
**Kind:** language (decision) — one question: is `*pu` of a `pu: *u128` the 16-byte `u128` (as `*p` of a narrow `*T` is
the element since 6.7.8, "a read loads T's bytes"), or refused by name as `pu[0]` is ("a `u128` element, which does not
fit one register (use `load64` / `store64` on its two halves)")? Today it is neither: the guide's 6.7.8 rule lists the
narrow pointers and the word pointers (`*i64` / `*u64` / `*f64` / `*bool`) and does not name `*u128`.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    var a: u128 = 0;
    a = a - 1;
    var b: u128 = 5;
    var pa: *u128 = &a;
    var pb: *u128 = &b;
    var x: u128 = *pa;
    fmt_int(x == a);
    fmt_int(*pa == a);
    var c = 1;
    var y = if (c == 1) { *pa } else { *pb };
    fmt_int(y == 0 - 1);
    var z: u128 = if (c == 1) { *pa } else { *pb };
    fmt_int(z == a);
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < u1.cyr > u1 && ./u1
0010        # a = 2^128 - 1: `var x: u128 = *pa;` is 2^64 - 1 (x == a 0), `*pa == a` 0, the branch is the low
            # word (y == -1: 1), `var z: u128 = if .. { *pa } ..` 2^64 - 1 (z == a 0)
```

The store:

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    var a: u128 = 0;
    a = a - 1;
    var b: u128 = 5;
    var pa: *u128 = &a;
    *pa = b;
    fmt_int(a == b);
    fmt_int(load64(&a + 8));
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < u2.cyr > u2 && ./u2
0-1         # a == b 0: the high word is still -1
```

Contrast: `var x = if (c == 1) { a } else { b };` with `u128` names is refused ("an if expression branch cannot be a
vector, u128 or slice value - branch on a pointer (&x)"), and `pa[0]` is refused by name. No diagnostic for any `*pa`
line above.

## Root cause

The dereference reader types `*p` by its pointer's element for the narrow pointers (6.7.8) and for a struct / vector
pointee (6.7.10 / 6.7.13); a `*u128` falls to "every other operand is a WORD address, read and written 8 bytes", so
`*pa` is an 8-byte load (and `*pa = v` an 8-byte store) typed as an integer. The u128 consumers (a declaration, `==`,
the if-expression branch check `_ie_*`, which refuses a u128 NAME) never see a u128 operand.

## Fix direction

The user's decision first (16-byte `u128` value, or refused by name as `pu[0]` is). Either way the branch shape the
review found follows: refused as a `u128` name branch is (if `*pu` is the u128), or refused with `*pu` itself. Rows in
a frontend gate and a tests/tcyr/crossos/ file for the declaration, `==`, the branch and the store.
