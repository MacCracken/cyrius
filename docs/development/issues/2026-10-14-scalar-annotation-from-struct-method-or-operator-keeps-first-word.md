# `var x: i64 = b.mk();` / `var y: u8 = a + b;` take a struct METHOD's or OPERATOR's first word, narrowed, where the free-call form is refused since 6.7.11 — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user** (does 6.7.11's decision A for
`2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md` (b) reach a method and an operator?).
Reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, unit R4, after its first commit) on x86_64, aarch64
(qemu), cx (cxvm) and PE (wine), identically on all four.
**Placement:** 6.7.13 — repair 3: struct values (receives lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D13 — (A).
**Severity:** Medium — silent: a scalar holds the struct's first word (narrowed to its annotation); nothing crashes.
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R4), while repairing shape (b) of
`2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md`. That issue's filed surface is PARSE_VAR's
receive of a FREE call (`mkp()`); the user decided (2026-10-13, A) to refuse an annotation that names no struct there,
by name. A method call and an overloaded operator reach the declaration through another path, outside that surface.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn Q_add(l: *Q, r: *Q): Q { var q: Q; q.a = l.a + r.a; q.b = l.b + r.b; return q; }
fn main(): i64 {
    var b = Q { 1, 2 };
    var x: i64 = b.mk();          # 333 — the first word
    var a = Q { 300, 2 };
    var c = Q { 33, 2 };
    var y: u8 = a + c;            # 333 narrowed to 77
    return x % 256 + y - 77;      # 77 on every target
}
syscall(60, main());
```

Measured, one declaration per file (x86_64 / aarch64 / cx / PE):

| declaration | exit |
|---|---|
| `var x: i64 = b.mk();` (16 B `Q`) | 77 / 77 / 77 / 77 (333, the first word) |
| `var y: u8 = b.mk();` then `y > 255` | 0 x4 (y is 77) |
| `var x: i64 = b.mk3();` (24 B `Q3`) | 77 x4 |
| `var x: i64 = a + c;` (`Q_add` returns a 16 B `Q`) | 77 x4 |
| `var y: u8 = a + c;` | 0 x4 |
| `var x: f64 = b.mk();` | builds, 0 |
| `var x: bool = b.mk();` | refused: "cannot initialize bool 'x' with a value that is not a bool" |
| the free call `var x: i64 = mkp();` (6.7.11) | refused: "cannot initialise 'x: i64' from 'mkp', which returns the struct 'P2' - declare 'x: P2' or bind a field" |

## Root cause

`_rcv_scalar_ann` (src/frontend/parse_decl.cyr, 6.7.11) sits in PARSE_VAR's free-call receive (`IDENT (` or a
generic `IDENT < .. > (`, `_var_rhs_call`). A method or operator initialiser is parsed by PCMPE into its struct temp
and offered to `_sc_var_receive` (parse_fn.cyr), which takes the temp only for no annotation (`ext == 0`) or a
matching struct one; with a scalar annotation it returns 0 and the scalar path stores the temp's first word (narrowed
by the annotation's width). The 6.7.8 dyn lane refuses the same shapes for a dyn there (`_scv_dyn_chk`).

## The question

Extend decision A — refuse `var x: <scalar> = <method or operator returning a struct over 8 B>` by name, with the
same text — or keep the first word (option B) for these paths? A refusal is frontend-only (`_sc_var_receive`, beside
`_scv_dyn_chk`); the free call and these would then agree.
