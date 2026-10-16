# `x = mkp();` / `x = b.mk();` / `x = a + c;` — a struct over 8 B ASSIGNED to a scalar local or global stores its first word, where the declaration `var x: i64 = mkp();` is refused by name (D24 / D13) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05) and the lane base (f59668ad's `build/cycc`): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives review, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — silent wrong value: the scalar holds the struct's first word (narrowed to its width); no
diagnostic, nothing crashes.
**Discovered:** 2026-10-16, the receives lane's review of the D13 bite (6ab2a9c8, issues/
archived/2026-10-14-scalar-annotation-from-struct-method-or-operator-keeps-first-word.md). D24 (6.7.11, the free call) and D13
(6.7.13, a method / operator) refuse a scalar ANNOTATION's initialiser; their filed surface is the declaration. The
assignment is outside it, so it was left as found, here.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn main(): i64 {
    var x: i64 = 0;
    x = mkp();
    return x;
}
syscall(60, main());
```

```
rc 0, no diagnostic; exit 77 on x86_64 / aarch64 / cx / PE (333, the first word, mod 256)
```

A method and an operator, into an `i64` local, a `u8` local and an `i64` global:

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn main(): i64 {
    var b = Q { 1, 2 };
    var x: i64 = 0;
    x = b.mk();
    return x;
}
syscall(60, main());
```

```
rc 0, no diagnostic; exit 77 on all four
```

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn Q_add(l: *Q, r: *Q): Q { var q: Q; q.a = l.a + r.a; q.b = l.b + r.b; return q; }
var G: i64 = 0;
fn main(): i64 {
    var a = Q { 300, 2 };
    var c = Q { 33, 2 };
    var x: i64 = 0;
    x = a + c;
    var y: u8 = 0;
    y = a + c;
    G = a + c;
    return x - 333 + y + G - 333;
}
syscall(60, main());
```

```
rc 0, no diagnostic; exit 77 on all four (x = 333, y = 77, G = 333)
```

The declarations are refused (lane; the base refuses the free call, D24, and keeps the method's first word):

```
var x: i64 = mkp();   -> error:<source>:5:18: cannot initialise 'x: i64' from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field
var x: i64 = b.mk();  -> error:<source>:6:18: cannot initialise 'x: i64' from 'Q_mk', which returns the struct 'Q' - declare 'x: Q' or bind a field
```

## Root cause

D24's refusal lives in PARSE_VAR (`_rcv_scalar_ann`, `_scv_rec_ann`, src/frontend/parse_decl.cyr). The assignment
(`_PARSE_STMT_IMPL` → the struct-receive tail in src/frontend/parse.cyr, `_sc_whole` / `_agc_operand`) takes a struct
temp only when the destination is a struct (`_agc_t == 0 - _sc_sid`); for a scalar destination it returns and the
plain store keeps rax, the struct's first word.

## The question

Whether D24 / D13 reach the assignment (refuse `x = <struct over 8 B>` into a scalar by name, same words) is the
user's call: it makes compiling code stop compiling. A refusal is frontend-only, beside `_AGG_ASSIGN_TYPE_ERR` in the
assignment's struct tail. Rows: free / method / operator / `&f` callee into an `i64` / `u8` / `f64` local and an `i64`
global; the 8 B and `Str` controls keep the word.
