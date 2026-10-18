# `gx<Box<i64>>(bx)` with `bx: Box<i64>` is refused "different struct type" — the explicit type argument mints `Box$i64`, the annotation binds the base `Box` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend, unit F5) and on the lane's
base compiler (f793b013), x86_64 (the frontend: every target alike).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-17 by the 6.7.14 frontend lane, unit F5, while writing rows for
issues/archived/2026-10-15-call-diagnostics-name-method-by-mangled-name.md.
**Severity:** Medium — valid source is refused (rc 1, no binary); the inferred spelling `gx(bx)` builds.
**Kind:** bug (generics).

## Reproduction

```cyrius
struct Pt { x; }
struct Box<T> { v: T; }
fn gx<T>(b: T): i64 { return 7; }
fn gy<T>(a, b: T): i64 { return 8; }
fn main(): i64 { var bx: Box<i64> = Box<i64> { 1 }; return gx<Box<i64>>(bx); }
syscall(60, main());
```

```
error:<source>:5:75: cannot pass 'bx' to a parameter of a different struct type in a call to 'gx$Box$i64'
```

(On the F5 compiler the callee is named `'gx<Box<i64>>'`; the refusal is the same.) The same with `gx<Box<i64> >(bx)`,
with `var bx = Box<i64> { 1 };`, and for `gy<Box<i64>>(1, bx)`. Not refused: `gx(bx)` (exit 7), `gx<Pt>(p)`,
`gx<Box<Pt>>(bx)` with `bx: Box<Pt>`.

## Root cause (by reading; to confirm)

An all-i64 type-argument list on a generic struct ANNOTATION binds the base struct (`var bx: Box<i64>` is the base
`Box`, whose `v: T` is already an i64 — the 6.6.10 rule in parse_decl.cyr), but `_parse_one_type_arg`
(src/frontend/parse_fn.cyr) instantiates a nested `Box<i64>` type argument unconditionally
(`_instantiate_generic_struct(S, base_sid - 1, in0, in1)`), minting `Box$i64`. The instance `gx$Box$i64` records
`Box$i64` as its parameter's struct (GFPSID), the argument carries the base `Box`'s sid, and `_sarg_type_err` refuses
the pair. `Box<Pt>` mints the same instance on both sides, so it passes.

## Fix direction

Apply the annotation's all-i64 rule in `_parse_one_type_arg`'s nested arm (an all-i64 inner list is the base sid), so
the explicit and the annotated spelling name one struct; rows: the repro (exit 7), `gy<Box<i64>>(1, bx)` (exit 8),
the instance name unchanged for `Box<Pt>`.
