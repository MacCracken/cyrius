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

✅ **RESOLVED — v6.3.16.** `parse_decl.cyr` asv detection: broadened the gate to
`pscale <= 0` and, for an inferred `var p = mk();` whose callee returns a struct,
**inferred `pscale = -callee_sid`** so the existing explicit-annotation codegen runs
— `asv_try` (>16 B → retptr / X8) or `asv_pair` (9-16 B non-Str → rax:rdx). Str /
≤8 B returns keep the scalar/pointer-mode inferred path (byte-identical). Verified:
`var p = mk()` (16 B) = 30, `var t = mk3()` (24 B) = 21, inferred i64 call = 4,
inferred Str = 5 — x86 + aarch64 (qemu). Fixpoint + seed-derive OK. See
`tests/tcyr/struct_local_codegen.tcyr`, CHANGELOG [6.3.16].
