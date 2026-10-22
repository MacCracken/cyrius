# A struct element of a declared multi-value return (`fn mv(): (Pt, i64)`) hands back the struct's first word, untyped: `return (b, 5)` drops `b.y`, and passing the binding on as a `Pt` faults — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-46, `7ec606f70`, with FF-47 `e9e41abb3` and FF-52 `b7dcf25da` — the user's D90 (2026-10-20): refuse the element at the return. `_mret_sval` (src/frontend/parse_expr.cyr), in the multi-value element evaluator, refuses a struct value over 8 bytes at the element's first token. mv.cyr is rc 1, "3:59: 'mv' returns struct 'Pt' (16 bytes) as a multi-value element - return its pointer, or its fields as elements" (it compiled, exit 14, `b.y` gone); the `take(b)` program the same line (it SIGSEGVed); `return (mk(), 5)` in a `(i64, i64)` fn and an undeclared fn's `return (b, 5)` one line each; the `b.y`-binding program is refused at its declaration's return; an 8-byte struct element still exits 9; a word, `&b`, a `*Pt`, `b.x` and a `Str` compile. FF-52: a HANDLE named whole (a struct local initialised from an address, a pointer-mode global) stays an element — its word is the address and it computed right (FF-46's first cut refused it; lane f16b's FB-5 fixed the same, the merge kept FF-52). Rows: new tests/gates/frontend/mret_struct_element_refused.sh M1 / M2 / M2b (the filed programs verbatim) – M12, K1 – K4 on five legs, K run on x86_64, qemu-aarch64, cxvm, wine (floor 120); small_struct_handle_line.sh C5; mutants RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — met 2026-10-20 by the 6.7.16 gensig lane (unit GS4) while writing a control row for
issues/archived/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md (the control passed a destructured
`(Box<i64>, *i32)` element on as a `Box<i64>` argument and faulted). Measured on the lane head (eafa5a40d) and on the
lane's base (1e3aad696), x86_64, identical. Not this lane's surface (the element's type-argument reading is; what a
struct element carries is not).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; f16 lane, wave 4, unit FG3) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D90 — Refuse the element at the return.
**Severity:** Medium — silent: a 16 B struct element loses every word past its first, with no diagnostic; the binding
is a plain word, and handing it to a by-value struct parameter reads it as an address (SIGSEGV).
**Kind:** bug (codegen / typing: what the declared signature says).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
fn mv(): (Pt, i64) { var b: Pt; b.x = 9; b.y = 4; return (b, 5); }
fn main(): i64 { var b, c = mv(); return b + c; }
syscall(60, main());
```

```
$ build/cycc < mv.cyr > mv && ./mv; echo $?
14
```

`b` is 9 — `b.x`, the struct's first word — and `b.y` (4) is gone. The binding is untyped:

```cyrius
fn main(): i64 { var b, c = mv(); return b.y; }
```

```
error:<source>:4:45: no struct type in scope for 'b'; a '.field' access needs its struct declaration (missing include?)
```

and passing it on as the declared struct faults:

```cyrius
fn take(p: Pt): i64 { return p.y; }
fn main(): i64 { var b, c = mv(); return take(b); }
```

```
exit 139 (SIGSEGV: the word 9 is read as the struct's address)
```

## What the guide says

The Multi-Return section: "Declaring the return type is what lets the compiler check a FORWARD call's arity and type
the bindings", and a struct is in the element vocabulary (`(Box<i64>, i64)` is cited as a multi-value element). A
single-value multi fn's `return p;` ("a struct local (its first word)") is refused for exactly this loss; an element
`return (p, x)` is not.

## Root cause

Not located. The element's value is evaluated as a word (a struct local's first word lands in the first return
register), and the destructure types bindings only for scalar / f64 element kinds.

## Fix direction

The user's call between: (a) refuse a struct element over 8 bytes by name, at the declaration or at the `return`
(as `return p;` is: "return its pointer, or its fields as elements"), keeping an 8 B struct as one word; or (b) carry it
(a hidden result slot, as a > 16 B single struct return does). Rows: the three programs above; an 8 B struct element;
`(Pt, i64)` on aarch64 / cx / PE.
