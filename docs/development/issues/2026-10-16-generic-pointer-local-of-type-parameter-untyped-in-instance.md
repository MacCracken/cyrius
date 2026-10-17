# A `var t: *T` local in a generic instance is no struct receiver: `t.y` with T bound to `Pt` is "no struct type in scope for 't'", where the parameter `p: *T` and a non-generic `var t: *Pt` are — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G4) on the slot-open compiler (2600f67f's
build/cycc) and on the lane's tree: identical.
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G4, probing a carrier's `*T` field (`var t: *T = b.p; t.show()`).
**Severity:** Low — a loud refusal of valid source; workaround: use the `*T` parameter itself, or a by-value `var t: T`.
**Affects:** ≤ 6.7.13 through the 6.7.14 lane tree; every target (frontend).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
fn g<T>(p: *T): i64 { var t: *T = p; return t.y; }
fn go(): i64 { var q: Pt; q.x = 1; q.y = 9; return g<Pt>(&q) + g<Pt>(&q); }
syscall(60, go());
```

```
actual:   error:<source>:3:48: no struct type in scope for 't'; a '.field' access needs its struct declaration (missing include?)
expected: exit 18 (g$Pt reads t.y = 9, twice)
```

Controls: `fn g<T>(p: *T): i64 { return p.y; }` with `g<Pt>(&q)` exits 9 (the parameter is a `*Pt` receiver in the
instance); the non-generic `fn g(p: *Pt): i64 { var t: *Pt = p; return t.y; }` exits 9 (a `*Pt` local is a receiver);
the definition alone, uncalled, compiles (the base is the stub). A store through it, `t.y = 4;`, is refused the same way.

## Root cause (not traced to the line)

The instance's parameter `p: *T` resolves T to its binding when it is typed (`_param_ptr_head` / the bound type
parameters), but a LOCAL's `*T` annotation in the instance body does not record the bound struct as the local's
pointee, so `t` is a plain pointer and the field access finds no struct. The stub scan reads it right (`var t: *T` is a
T-typed name, `_gs_var`), so the base is skipped and only the instance is refused.

## Fix direction

Type a `var t: *T` local of an instance as `*<T's binding>` when T binds a struct, as `var t: *Pt` is typed. Rows: the
repro (18); a store `t.y = 4`; a method `t.m()`; `var t: *T = p;` at a scalar T stays a plain pointer.
