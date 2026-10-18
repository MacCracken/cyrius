# A generic fn declared `: *Box<T>` is refused at its definition ("unknown type 'T' as a type argument") — RESOLVED

> ✅ **RESOLVED in v6.7.14** (GN-6 (`4a74fe60`): a generic's base reads its `: *..` return with T → i64 bound (`_ret_ptr_base_bind`), each instance its own `*Box<Pt>`, and pass 1 reads a `*G<..>` return only when its arguments resolve (`_ret_ptr_sid`). The filed repro exits 3 (it was refused twice at its definition); `gp(mkp(p))` 8, `mkp<Pt>(p).n` 8, `var q: *Box<Pt> = mkp(p);` reads fields (7), `mkp(5).n` 8; a genuinely unknown `: *Box<Zork>` is one error (two before; with calls, one since GN-18's per-instance latch); a struct declared below the fn (`: *Box<Later>`) is no longer refused by pass 1. Rows: `frontend/generic_struct_field.sh` PG0 (the repro verbatim) – PG7; `crossos/generic_ptr_struct_source.tcyr` `pb1` – `pb5` on seven legs; mutations MG1 and MG2 RED. Filed, 6.7.15: the `**Box<..>` sibling, read in pass 1. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G3, build/cycc 2,185,200 B):
the definition alone is refused, called or not, with the same error printed twice. The installed 6.7.0, 6.7.5, 6.7.9 and
6.7.10 compilers refuse it identically. `: Box<T>`, `: *T` and `: *Box<Pt>` returns of a generic all compile.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit G3, while adding the row "a `*Box<T>` carrier with a
`*Box<T>`-returning generic" that issues/archived/2026-10-10-generic-call-result-as-carrier-argument-refused.md lists: no such
generic can be declared, so that row could not be written.
**Severity:** Low — a loud refusal of valid source at the definition; workaround: return the pointer untyped or as
`*Box<Pt>` per concrete type, or return `Box<T>` by value.
**Affects:** cycc 6.7.0 – 6.7.11 (measured 6.7.0, 6.7.5, 6.7.9, 6.7.10, the 6.7.11 lane).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mkp<T>(x: T): *Box<T> { return 0; }
syscall(60, 3);
```

```
expected: compiles, exits 3
actual:   error:<source>:3:24: unknown type 'T' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
              fn mkp<T>(x: T): *Box<T> { return 0; }
                                     ^
          (the same error a second time)
```

With a caller (`fn gp<T>(b: *Box<T>): i64 { return b.n; }`, `return gp(mkp(p));` with `p: Pt`) the same two errors,
plus "assigning non-pointer to typed pointer" twice at the body's `alloc(32)`.

## Root cause

`_ret_ptr_annot` (src/frontend/parse_types.cyr) binds the fn's type parameters only for an INSTANCE re-emit
(`_inst_conc0 != 0`); the BASE's `: *Box<T>` is read by `_ret_ptr_record` -> `_ptr_ann_sid` / `_ptr_annot` with `T`
unbound, so `_type_arg_leaf` refuses `T` — in pass 1 (`_prescan_ret_type`, `quiet` 1, which does not silence it) and
again in pass 2 (`_ret_ann_alt`). A by-value `: Box<T>` goes through `_gtype_sid`, which answers the generic base for a
generic fn's base (`if (GFTP(S, fi) != 0) { if (_inst_conc0 == 0) { return base; } }`) and never parses the arguments.

## Fix direction

Read the base's `: *G<.., T, ..>` as `_gtype_sid` reads `: G<..>` — the generic struct's base (or bind `T -> i64` as
PARSE_FN_DEF does for the base body) — and keep the instance's binding. Rows: the repro; `gp(mkp(p))` exits 8 (the
`*Box<T>` carrier given a `*Box<T>`-returning generic call — 6.7.11's `_gsc_call` reads the INSTANCE's `_fn_rpsid`,
so the inference should follow once the base compiles; unverified, since nothing compiles today); `mkp<Pt>(p).n`; `var q: *Box<Pt> = mkp(p);`; one error, not two, for a
genuinely unknown name in a `: *G<..>` return.
