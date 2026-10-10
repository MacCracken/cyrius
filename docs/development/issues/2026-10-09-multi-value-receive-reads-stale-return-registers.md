# A multi-value receive reads a return register the callee never wrote — three shapes compile silently — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 on x86_64, aarch64 (qemu), cx (cxvm) and PE
(wine), and against the installed 6.6.0 on x86_64: each seeded repro below exits the value an EARLIER call left in
the register (77 or 88) on all four targets, with no diagnostic.
**Placement:** 6.7.10 — Break 2, repair 1, the multi-value receives lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 B4 (tuples) planners' probes (t7, d4, v1); filed 2026-10-09 by the B4 lane
(bite T0).
**Severity:** Medium — silent garbage in a binding; the declared-arity and one-value checks that exist do not reach
these shapes.
**Affects:** cycc 6.5.21 – 6.7.6 (declared `: (T1, T2[, T3])` returns and the arity-3 destructure are 6.5.21;
measured on 6.6.0 and 6.7.6)

## Summary

A destructure `var a, b[, c] = f();` reads its second and third values from rdx and r8 (x2 / x3 on aarch64, r4 / r5
on cx). It refuses a callee that cannot fill them when it can prove it: a declared `: (T1, T2[, T3])` whose arity
differs (v6.5.21), and a callee whose every `return` is one value (6.6.17, GFLG bit 1024). Three shapes get past
both and read a register the callee never wrote — whatever an earlier call left there:

1. **An undeclared callee whose `return (a, b);` has fewer values than the names bound** (t7). Pass 1 records no
   arity for an undeclared multi-value return, so `var q, r, z = dm(17, 5);` binds `z` to r8. The declared spelling
   `fn dm(a, b): (i64, i64)` is refused ("multi-value destructure count does not match the fn's declared return
   arity").
2. **A declared `: (T1, T2)` fn that returns ONE value** (d4). `fn f(): (i64, i64) { return 5; }` compiles; its
   caller's `b` is rdx.
3. **A declared `: (T1, T2)` fn that returns a named 9–16 B struct local** (v1). `return p;` takes the struct's first
   word (the documented first-word rule) into rax and leaves rdx alone, so `a` = `p.a` and `b` is rdx.

## Reproduction

The probes as the planners wrote them. Each compiles silently; t7 and d4 exit with their correct values (they only
show that the shape builds), v1 exits wrong. Unseeded, the stale `z` / `b` read 0 on x86_64, aarch64 and cx and 1
on PE:

```cyrius
# t7 — z is never written; exits 32 (q, r right)
fn dm(a, b) { return (a / b, a % b); }
fn main(): i64 { var q, r, z = dm(17, 5); return q * 10 + r; }
var r = main(); syscall(60, r);
```

```cyrius
# d4 — b is never written; exits 5 (a right)
fn f(): (i64, i64) { return 5; }
fn main(): i64 { var a, b = f(); return a; }
var r = main(); syscall(60, r);
```

```cyrius
# v1 — exits 30; 34 is what the source means (a = 3, b = 4)
struct P { a; b; }
fn f(): (i64, i64) { var p = P { 3, 4 }; return p; }
fn main(): i64 { var a, b = f(); return a * 10 + b; }
var r = main(); syscall(60, r);
```

Seeded, so the stale register is visible — an earlier three-value call leaves 77 in the second register and 88 in
the third:

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn dm(a, b) { return (a / b, a % b); }
fn main(): i64 { var x, y, w = h(); var q, r, z = dm(17, 5); return z; }
var r = main(); syscall(60, r);
```

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn f(): (i64, i64) { return 5; }
fn main(): i64 { var x, y, w = h(); var a, b = f(); return b; }
var r = main(); syscall(60, r);
```

```cyrius
struct P { a; b; }
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn f(): (i64, i64) { var p = P { 3, 4 }; return p; }
fn main(): i64 { var x, y, w = h(); var a, b = f(); return b; }
var r = main(); syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

| Seeded shape | x86_64 | aarch64 (qemu) | cx | PE (wine) | 6.6.0 x86_64 |
|---|---|---|---|---|---|
| 1 — `var q, r, z = dm(17, 5);`, `dm` undeclared, two values | 88 | 88 | 88 | 88 | 88 |
| 2 — `return 5;` in a `: (i64, i64)` fn | 77 | 77 | 77 | 77 | 77 |
| 3 — `return p;` (P is 16 B) in a `: (i64, i64)` fn | 77 | 77 | 77 | 77 | 77 |

Expected: a compile error naming the shape (see *Proposed fix*), as for the declared-arity control.

## Root cause

- `_dt_arity_check` (`src/frontend/parse_decl.cyr:5080`) checks a declared `MULTIRET_SID` arity and the one-value
  bit (GFLG 1024, set by `_prescan_ret_single`, `src/frontend/parse_fn.cyr:10029`). An undeclared fn whose returns
  are all `(a, b)` has neither, so any name count passes (shape 1).
- PARSE_RETURN in a fn declared `: (T1, T2[, T3])` (`_cur_fn_ret_scalar = MULTIRET_SID`, `parse_fn.cyr:12559`)
  takes a single-value `return x;` through the scalar tail, which sets rax only (shapes 2 and 3; for a struct local
  rax is its first word). Only the multi-value arm (`parse_fn.cyr:1009-1078`), `ret2` and a forwarded multi-value
  call write rdx / r8.

## Proposed fix

Default, pending the user's word (each refuses source that builds today):
1. Pass 1 records the arity of an undeclared fn whose every `return` is `(…)` of one arity (beside
   `_prescan_ret_single`), and `_dt_arity_check` refuses a different name count with the 6.6.17 wording ("binds 3
   names, but 'dm' returns 2 values"). This is the sibling of 6.6.17's one-value refusal.
2. A `return <expr>;` that is not `return (…)` with the declared arity, in a fn declared `: (T1, T2[, T3])`, is
   refused by name ("'f' returns 2 values - return (a, b)"). That covers shapes 2 and 3 together. It must keep a
   forwarded call to a multi-value fn of the same declared arity (`return g(x);` with `g: (i64, i64)` exits 56 on
   all four targets today — rax:rdx pass through).

Related:
- [`2026-10-08-loop-ending-fn-not-provably-single-return.md`](2026-10-08-loop-ending-fn-not-provably-single-return.md)
  — the one-value proof's own missed shapes (the same stale-register symptom).
- [`2026-10-08-pair-call-assigned-to-single-slot-keeps-tag.md`](2026-10-08-pair-call-assigned-to-single-slot-keeps-tag.md)
  — the opposite direction (more values than slots).
- The 6.7.7 tuple capture (`var t: (i64, i64) = f();`) is designed to mirror the destructure's checks exactly, so
  it inherits these three shapes and fixes none of them; a fix here covers both.

## Consumer-side workaround

Declare the callee's return arity (`fn dm(a, b): (i64, i64)`) so a wrong name count is refused, and in a declared
multi-value fn write every return as `return (a, b);`.
