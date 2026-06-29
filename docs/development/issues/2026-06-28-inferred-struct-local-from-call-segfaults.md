# `var p = struct_returning_call()` (inferred local type) segfaults

**Discovered:** 2026-06-28 while building the v6.3.5 CO-01 forward-call regression
test ([`2026-06-10-monomorphization-substrate-prereqs.md`](2026-06-10-monomorphization-substrate-prereqs.md)).
**Severity:** P2 (silent runtime crash; clean compile)
**Affects:** cycc front-end — the `var X = <expr>;` local-type inference path for a
struct-returning callee (`parse_decl.cyr` var-decl handling + the struct-return
retptr ABI). **NOT a CO-01 / forward-call issue** — it reproduces with the callee
defined *before* the caller.

## Repro

```cyrius
struct Pt { x: i64; y: i64; }
fn mk(): Pt { var p: Pt; p.x = 10; p.y = 20; return p; }   # defined FIRST
fn caller(): i64 { var p = mk(); return p.x + p.y; }        # inferred local type
alloc_init();
print_num(caller());   # exits 139 (SIGSEGV)
```

- `var p = mk();` (no annotation) → compiles cleanly (rc 0) → **SIGSEGV at runtime**.
- `var p: Pt = mk();` (explicit annotation) → works (prints 30).

So the inferred form mis-sets up the hidden struct-return pointer (the callee writes
the aggregate to a wild/garbage address). The explicit-type form allocates the local's
struct space and passes `&p` as the retptr correctly.

## Why it surfaced now

v6.3.5 CO-01 added a pass-1 fn-signature prescan that records struct-return ABI
(`SFRS`) so a *forward* call to a struct-returning fn emits the retptr convention.
That fixed the explicit-type forward case (`var p: Pt = mk()` — was a segfault on a
forward callee, now correct). The inferred-type case (`var p = mk()`) still crashes,
but it crashes **regardless of definition order**, so it is a separate, pre-existing
defect in the var-decl inference / retptr-space allocation, not part of CO-01.

## Fix direction

When `var X = <call>;` infers the local's type from the callee's struct return
(`GFRS(callee) > 0`), the var-decl path must allocate the local's aggregate slot and
pass `&X` as the hidden retptr — the same as the explicit `var X: T = <call>;` path.
Today the inferred path appears to allocate a scalar slot, so the callee's retptr
points at a too-small / mis-placed slot. Unify the two paths through the
explicit-annotation codegen once the struct sid is known.

## Workaround

Annotate the local: `var p: Pt = mk();`.

## Status

Filed 2026-06-28. Not blocking CO-01 (covered the explicit-type retptr ABI). Triage
for a v6.3.x front-end slot.
