# `var v: f64v2 = *p;` / `v = *p;` with `p: *f64v2` — refused since 6.7.11 (it stored one word); copy the vector through the pointer, as a struct's `*p` is? — OPEN

**Status:** 🟡 **OPEN** — a decision for the user. Measured 2026-10-13: on the slot-open compiler (`0f733aea`) the
repro below compiled with no diagnostic and read wrong lanes — x86_64 210, aarch64 74, cx 98, PE 146 where 161 is right
(`*p` was read as one word, the high lane stale); the assignment `v = *p;` gave 156 on all four (lane 0 replaced, lane 1
stale). Since the 6.7.11 callargs lane (unit A1, `2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md`, the
user's decision (a): every source into a value-form vector local that is not a local of its type or a call declared
to return it is refused by name) both are refused: `a value-form vector local is initialised only from a local of its
type or a call declared to return it .. - got `*p``.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A1).
**Severity:** Low. Refused loudly since 6.7.11 (it read wrong lanes before, silently); the workaround is to use the
vector through its pointer (the `*_ptr` forms), or to copy its lanes with `load64` / `store64` on the address.
**Affects:** every value-form vector type, declaration and assignment, all four targets.

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    var w: f64v2 = mkv(41, 7);
    var p: *f64v2 = &w;
    var v: f64v2 = *p;
    return lanes(v);
}
syscall(60, run() % 256);
```
A1 tree: `error:<source>:6:20: a value-form vector local is initialised only from a local of its type or a call
declared to return it (by name, or fncallN / callptr with the callee written `&f`) - got `*p`; through a fn pointer
held in a variable, give the target an out-pointer` on all four targets. Slot-open compiler: 210 / 74 / 98 / 146.

## The question

6.7.10's decision 6 made `*p` with `p: *T` a struct VALUE at every size (`var q: T = *p;` copies through the pointer).
A vector is the guide's other value-form aggregate. Should `var v: V = *p;` / `v = *p;` with `p: *V` copy the 16 / 32
bytes through the pointer (it would start compiling, right on every target), or stay refused? `_try_struct_copy_init`
already routes a `*p` declaration whose `p` is a pointer-mode local (`_sci_star`); the vector `*V` local is not marked
pointer-mode (GLPTRP), so it falls to the scalar path. The pointer-to-vector PARAMETER arm is
`2026-10-10-pointer-to-vector-parameter-is-value-form.md` (6.7.11, A2), which makes `p: *f64v2` a pointer.
