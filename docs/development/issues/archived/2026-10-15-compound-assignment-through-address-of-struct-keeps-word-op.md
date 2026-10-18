# `*(&s) OP= v` on a struct still adds to its first word, while `*p OP= v` through a `*S` is refused and `*(&s)` is now the struct value — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-10, `0d225f0ce`: the user's decision D17 (a), 2026-10-16. `*(&s) OP= v` on a struct value is refused as `s OP= v` is: "compound assignment to struct 's' is refused - a struct value is not an integer or a float (write `a = a + b`)", once. `_dst_struct` loses the 6.7.13 `_hl_damp` carve-out. The filed repro (134 on x86_64, aarch64, cx and PE: s.x 3 became 13) is refused, one error, on the x86_64, aarch64, cx, PE and cycc_win_cross compilers. So are a by-value parameter, a global, a capture, the top level, a for step, `*&s` and `*((&s))`. `*(&h) OP= v` of a handle and `*(&n)` of a scalar keep the word op. Rows: `struct_copy_type_checked.sh` A13 flipped to a refusal and C7 (the filed repro verbatim) - C16; A15 / A16 keep the word op; `field_compound_values.tcyr` Q4 moved into the gate (80 rows, 80 / 80 on ecb, ach, cass and pi); mutations RED 11 + 11. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN — a decision for the user** (refusing it stops code compiling). Measured 2026-10-15 on the
6.7.13 structs lane (`l6713-structs` after 74f3100e, the deref-of-address-of fix), x86_64 / aarch64 (qemu) / cx
(cxvm) / PE (wine) alike.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D17 — (a).
**Severity:** Low — a rule split, not a wrong value: the word op is what 6.7.5 specified and a crossos row pins it.
Not a security id (the developer's own source).
**Discovered:** 2026-10-15, the 6.7.13 structs lane (unit S2), fixing
issues/archived/2026-10-14-dereference-of-address-of-struct-faults.md: routing `_dst_struct` (parse.cyr) through the new
`_hl_dpsid` typed `*(&s)` as the struct `s`, which made `*(&s) += 10` hit 6.7.11's compound refusal and broke
`tests/tcyr/crossos/field_compound_values.tcyr` row Q4 ("Q4: through &h (its first word)"). That is a newly
refused shape beyond the filed issue's surface, so the fix keeps the old behaviour (`_dst_struct` returns 0 for an
`OP=` when the operand is the `&x` arm, `_hl_damp`) and this files the question.

## Reproduction

```cyrius
struct P3 { x; y; z; }
fn main(): i64 {
    var s: P3 = P3 { 3, 4, 5 };
    *(&s) += 10;
    var t: P3 = P3 { 3, 4, 5 };
    var p: *P3 = &t;
    return s.x * 10 + s.y;
}
syscall(60, main());
```

```
$ build/cycc < opeq.cyr > opeq && ./opeq; echo $?
134                     # x86_64, aarch64, cx, PE alike: s.x became 13 (the first word + 10)
```

The same statement through a typed pointer is refused (6.7.11, the user's decision (a) of 2026-10-13):

```cyrius
struct P3 { x; y; z; }
fn main(): i64 {
    var t: P3 = P3 { 3, 4, 5 };
    var p: *P3 = &t;
    *p += 10;
    return t.x;
}
syscall(60, main());
```

```
error:<source>:5:8: compound assignment to the struct 'p' points at is refused - a struct value is not an integer or a float (write `*p = *p + b`)
```

## Root cause

6.7.5 (B8-3) made `*expr OP= v` a word op at word width through `_deref_store`; 6.7.11's `_dst_struct` refuses
`*p OP= v` when `_hl_psid` types the operand `*S`. Since 74f3100e every other consumer reads `*(&s)` as the struct
`s` (`take(*(&s))`, `l = *(&s)`, `*(&s) = v` copies), but `*(&s) OP= v` keeps the 6.7.5 word op by the carve-out
above, pinned by field_compound_values.tcyr Q4 and struct_copy_type_checked.sh A13.

## Options

- **(a) refuse it by name, as `*p OP= v` and `s += v` are** — `*(&s) += 10` stops compiling (Q4 and A13 flip to
  refusal rows; an ecosystem-migration line). Remove the `_hl_damp` return in `_dst_struct`.
- **(b) keep the word op, documented** — nothing changes; the guide already says `*(&x) OP= v` still operates on
  x's first word (6.7.13 paragraph under *A dereference of an address-of is the struct it names*).
