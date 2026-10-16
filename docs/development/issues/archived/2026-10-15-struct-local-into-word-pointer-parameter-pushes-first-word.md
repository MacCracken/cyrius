# A struct local passed to a word-pointer parameter (`ri(s)` with `p: *i64`) pushes its first field as the address — RESOLVED

> ✅ **RESOLVED in v6.7.13** (ST-12, `5e488400`: a struct value passed to a pointer of another kind is refused by name — the user's decision D5 (a), 2026-10-15. The filed repro reports "cannot pass 's' to a parameter that is not a pointer to its struct type in a call to 'ri' - pass &s for its address", one error, no binary, on x86_64, aarch64, cx and PE (was 139 / 139 / cx 253 / PE 5): into `*i64` / `*u8` / `*f64` / `**T`, with `s` a local of any size, a by-value parameter, a value global (in a fn and at top level), a closure capture, wrapped, `rg<i64>(s)` and a method's parameter. A handle, a `*Pt`, a `Str` and an untyped parameter pass as before. One kind of the filed "any `*T` whose T is no struct": a struct into a `*V` (`p: *f64v2`) still compiled silently at the lane's head (exit 42); on the merged tree the vectors lane's D33 (`f2279be5`) refuses it in its own words ("cannot pass 's' to a parameter that is a pointer to a vector type in a call to 'rd'"). Rows: `struct_arg_type_refused.sh` P1-P17, PK1, PK2 (87 refusal / 35 acceptance rows); mutations RED. Filed beside it (6.7.14): a field, a call result or a dereference (`ri(w.s)`, `ri(mk())`, `ri(*pp)`) still passes the first word. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1) and on the slot-open compiler
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
