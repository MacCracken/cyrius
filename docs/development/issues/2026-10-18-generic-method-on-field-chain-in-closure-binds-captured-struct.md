# A generic method on a FIELD-CHAIN receiver inside a closure, given the closure's own parameter, binds T to the captured head's struct (`|k| w.s.gs(k)` calls `S_gs` at T = W: "undefined function 'W_add'") — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (unit V2), x86_64, with the lane's compiler
before V2's commits (the V1 tree) and after them: identical. Pre-existing, independent of V2's chained-receiver vector
recogniser (the method here returns a scalar).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 vectors lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Medium — valid source is refused at link time naming an operator the program never wrote (`W_add`); a
struct type with an `add` method would be called silently with the wrong instance.
**Kind:** bug (generic inference).
**Discovered:** 2026-10-18, probing the chained-receiver vector method fix
(issues/2026-10-17-chained-receiver-vector-method-binds-a-word-annotated-refused.md) at a closure-capture head.

## Reproduction

```cyrius
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct S { k; }
struct W { s: S; j; }
impl S { fn gs<T>(self, a: T): i64 { return a + self.k; } }
fn run(): i64 { alloc_init(); var w: W; w.s.k = 1; var g = |k| w.s.gs(k); return fncall1(g, 41); }
syscall(60, run());
```

```
warning: undefined function 'W_add'
warning: undefined function 'W_add' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

Expected: exit 42 (T = i64, `a + self.k` = 41 + 1).

The matrix (same program, one change each):

| spelling | result |
|---|---|
| `|k| w.s.gs(k)` (the repro; the head an inline-struct local captured) | `W_add` undefined |
| `|k| p.s.gs(k)` with `p: *W` captured | `W_add` undefined |
| `|k| w.s.gs(41)` (a literal argument) | 42 |
| `|k| s.gs(k)` with `s: S` captured (a single-name receiver) | 42 |
| `w.s.gs(k)` in a plain fn with a local `k` | 42 |

## Root cause (partial)

The method arm resolves a generic method's instance from its arguments (`_mcall_gen_x` -> `_mcall_gen` ->
`_mcall_infer` -> `_ic_arg` -> `_infer_conc_at` on the argument's token, parse_fn.cyr). Inside a closure, after a
field-chain receiver whose head is a capture (`_load_inline_hop` / `_load_hop`, parse_decl.cyr), the closure's own
parameter `k` is typed as the captured head's struct (W): the binding T = W instantiates `S_gs` with `a + self.k` an
operator call `W_add`. A single-name capture receiver and a non-closure chain bind i64. Suspect: the capture lookup the
chain's head resolution leaves behind (`_CL_CAP_FIELD_IDX` sets `_cap_fld_sid`), read by the name inference for `k`.

## Fix direction

`k` binds what it is (an untyped closure parameter: i64), whatever receiver spelling precedes it; a row in the closure
generic tests with the head a captured inline struct and a captured `*W`.
