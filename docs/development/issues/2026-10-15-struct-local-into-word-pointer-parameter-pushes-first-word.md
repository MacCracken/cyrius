# A struct local passed to a word-pointer parameter (`ri(s)` with `p: *i64`) pushes its first field as the address — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1) and on the slot-open compiler
(`7f57e532`): the repro below compiles with no diagnostic and faults — x86_64 139, x86_64 `CYRIUS_IR=3` 139, aarch64
(qemu) 139, cx 253 (a guest fault), PE (wine) 5.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D5 — (a).
**Discovered:** 2026-10-15, the triage of `2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md` ("also in
passing, same class but not this issue"), re-measured by the fixfirst lane.
**Severity:** Medium — compiles clean and faults (or reads through whatever the first field holds), no diagnostic.
**Affects:** every target; a struct-typed local (any size) into a `*T` parameter whose T is no struct (`*i64`, `*u8`,
`*f64`, `**T`, ...).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
fn ri(p: *i64): i64 { return *p; }
fn main(): i64 {
    var s: Pt;
    s.x = 42;
    s.y = 7;
    return ri(s);
}
var rc = main();
syscall(60, rc);
```

```
x86_64 139, IR=3 139, aarch64 139, cx 253, PE 5        (no diagnostic)
```

## Root cause

A `*i64` parameter has no address-passed bit (`_param_wants_struct_ptr` sets it for `*S` and, since 6.7.11, `*V`), so
`_try_push_struct_addr_arg` goes to `_sarg_byval_small`, which declines (GFPSID 0) — the caller's value push loads the
struct local's first word and passes it as the pointer. The vector twin of this shape (`ri(b)`, `b: f64v2`) is refused
by name since 6.7.12 (D27, `_sarg_vec_other`: "cannot pass 'b' to a parameter that is not a pointer to its vector
type"); the struct one is not.

## The question

Refuse by name ("cannot pass 's' to a parameter that is not a pointer to its struct type — pass &s"), as D27 refuses
the vector local and 6.7.3 refuses a struct of another type, or pass `&s` (6.6.20's rule for `*S`, extended to any
typed pointer)? A struct into an UNTYPED parameter is a word (its handle / first word) and is not this question.
