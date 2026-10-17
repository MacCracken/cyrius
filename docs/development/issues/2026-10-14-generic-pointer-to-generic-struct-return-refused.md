# A generic fn declared `: *Box<T>` is refused at its definition ("unknown type 'T' as a type argument") — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G3, build/cycc 2,185,200 B):
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
