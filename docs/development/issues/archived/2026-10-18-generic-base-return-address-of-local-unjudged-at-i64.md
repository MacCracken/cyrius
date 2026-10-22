# A generic `: S` fn's `return &n;` (n a local or parameter) is not judged in the generic's BASE, which is its `T = i64` instance — `h(3)` alone still returns the slot's address as the struct — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-19, `d2742a654` — the user's D1 (2026-10-19): refused as a generic with no scalar instance — and GB-20, `36658d107` — the user's D2 (2026-10-19): refused at the definition, as in a non-generic fn. D1: the stub scan marks `return &n;` with n typed by T in a fn returning a struct, so the filed repro's `h(3)` (a dead slot's low byte, varying) is refused at 5:46, "generic 'h' has no i64 (or other scalar) instance", with the note "'h' returns `&n` as a struct, and n is typed by its type parameter" (4:42), on x86_64, aarch64, cx and PE; `h<i32>(4)` (the slot's words before), `&h` and a forwarder `k(3)` the same; `h<S8>(s)` still 7. D2: `return &n;` of a name typed with no type parameter (`var n = 5;`, `var n: i64`, a `k: i32` or untyped parameter, `var n = sizeof(T);`, a `**S8`) is refused at the `&n` with 6.7.15's D18 words, called or not, in a parsed base and a stub's skipped base. Rows: `small_struct_return_type_refused.sh` RG1 (the filed repro verbatim, four compilers) – RG9, RG1n, RG4n, AG1 – AG5, R55 / R55b, RD1 – RD13, AD1 – AD4; mutations MRG1 – MRG5, MRD1 – MRD6. D1's other line is issues/archived/2026-10-18-generic-instance-t-annotation-takes-struct-first-word.md. Filed beside it: an untyped local from a T-typed value is no T-typed name for the stub's `.field` rule (issues/archived/2026-10-20-generic-untyped-local-from-type-parameter-value-refused.md, the user's D102, wave 4). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S5) landing the user's D18
(issues/archived/2026-10-17-return-address-of-scalar-or-non-struct-pointer-slot-in-struct-fn.md): `return &n;` of a name holding
no struct is refused by name at every size — in every non-generic fn and in every generic INSTANCE. A generic's base
body is parsed with its type parameters bound to i64 and is ALSO the code an i64 call runs; refusing there would refuse
`fn hg<T>(x: T): S8 { var n: T = x; return &n; }` used only at `<S8>` (valid: D4 (a)'s struct, exit 26), so the lane
leaves the base's locals / parameters / captures to the instances (`_ret_gen_base`, src/frontend/parse_fn.cyr). x86_64
(frontend: every target alike).
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D1 — Refused as a generic with no scalar instance.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D2 — Refused at the definition, as in a non-generic fn.
**Severity:** Medium — silent: an i64 call of such a generic returns a dead frame's address as the struct's field (the
pre-6.7.15 behaviour of every `return &n;`, now confined to this corner). Not a security id (the developer's own source).
**Kind:** language (generics x D18) — the established answer for a body invalid at `T = i64` is the dead-stub base
(`_gen_stub`: an i64 call refused "generic ... has no i64 instance"), which this shape does not yet trigger.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S8 { v; }
fn h<T>(x: T): S8 { var n: T = x; return &n; }
fn main(): i64 { alloc_init(); var c: S8 = h(3); return c.v; }
syscall(60, main());
```

```
$ build/cycc < g64.cyr > g64; echo $?; ./g64; echo $?; ./g64; echo $?
0
200
248                     # the low byte of &n, a dead frame's slot (ASLR); no diagnostic
```

`h<i32>(4)` / `h<i16>(5)` are refused ("... `&n` is the address of n's slot, not a struct", once); `h<U8>(u)` is refused
"got `&n` (a `*U8`)"; `h<S8>(s)` returns the struct (exit 7 for s.v = 7). A T-independent local
(`var n = 5; return &n;` in a generic body) called only at i64 is unjudged the same way.

## Fix direction

Either mark the body's `return &x` (x T-typed, in a fn returning a plain struct) as a struct use in `_gs_scan` mode 0,
so the base becomes the stub and `h(3)` is refused by name as `p.x` on a T-typed parameter makes it; or judge the base
only for names whose type cannot come from T (an explicit non-T annotation) — the user's call which words an i64 call
gets.
