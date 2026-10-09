# A struct-typed FIELD as an operator's LEFT operand never dispatches — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`: `h.p - s` (and `+`, `*`)
with `p: P2` is an INTEGER op on the field's first word, the operator fn is never called; the right-operand form
`s - h.p` dispatches correctly. ⚠ The roadmap's symptom ("passes the containing struct's address, `h.p - s` → -8, want
-6") does **not** reproduce at HEAD in any shape tried: the -6 it called right is the integer subtraction of first words
(3 - 9) — with a distinctive operator body the call never happens. Same result on the installed 6.6.20 – 6.7.5.
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** the 6.7.6 review (pre-existing; roadmap commit d2d5309b); the "never dispatches" form was already
listed in CHANGELOG [6.6.20]'s pre-existing finds (`h.w + w2`); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — a silent wrong value on code that compiles clean; workaround: name the field first
(`var q: P2 = h.p; q - s`).
**Affects:** cycc 6.6.20 – 6.7.6 at least (not bisected further)

## Summary

`a OP b` dispatches `S_op` when the LEFT operand's recorded type is struct `S`. A local, global or capture name is
typed; since 6.7.6 a struct-returning call / method / operator result is too. A whole struct-typed field (`h.p`,
`hp.p`, `GH.p`, `self.p`, `o.h.p`, `(h.p)`, a captured `h`'s `h.p`) records no struct type, so the expression falls to
the integer arm: the field's first word is combined with the right operand's value and no operator fn is called.
Every struct size (8, 16, 24 B) and both `*S` and by-value operator parameters behave the same.

## Reproduction

```cyrius
struct P2 { x; y; }
struct H { n; p: P2; }
fn P2_sub(a: *P2, b: *P2): i64 { return 100 + a.x * 10 + b.x; }
fn main(): i64 {
    var h: H = H { 1, 3, 4 };
    var s: P2 = P2 { 9, 9 };
    return h.p - s;
}
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected: 139 (`P2_sub(&h.p, &s)` = 100 + 3·10 + 9). Actual: **250** (= 3 - 9, an integer subtraction of the first
words). `return s - h.p;` gives 193 (= 100 + 9·10 + 3, correct). `h.p + s` gives 12, `h.p * s` 27 (first words), and
`h.p - s + 10` with a `P2_add` defined calls `P2_add(&s, 10)` (the integer-arm type leak filed in
[`2026-10-08-struct-operator-results.md`](2026-10-08-struct-operator-results.md) item 2).

Matrix run (all 250, want 139): `W { x; }`, `P2 { x; y; }`, `P3 { x; y; z; }` × `fn S_sub(a: *S, b: *S)` / `(a: S,
b: S)` × a typed local `h`, an untyped `var h = H { .. }`, `h: *H` and `h: H` parameters, a global, a `*H` local,
`self.p` in a method, `var r = h.p - s;`, `(h.p) - s`, and `o.h.p - s` (nested). Inside a closure capturing `h`,
`h.p - s` is an integer op as well, and `s - h.p` is right.

## Root cause

The `+ - * /` arms decide dispatch from `_op_lst(S, beg)` (`src/frontend/parse_expr.cyr:5715`), which returns the
6.7.6 call-result stamp or `_FBR_ST` — the operand's estype. A whole struct-typed field read (PARSE_FIELD_LOAD,
`src/frontend/parse_decl.cyr:1191`) loads the field's first word and records its struct only PASSIVELY, for a reader
that armed it: `_fpk_note` (`parse_decl.cyr:1096`, a by-value argument) and `_fla_take` (`parse_decl.cyr:1115`, a
destination or the operator's RIGHT operand, armed by `_op_rhs` at `src/frontend/parse_fn.cyr:3365`). Nothing arms
it for the left operand, so the estype stays 0 and the integer arm runs. (The comment above `_op_lst` says it: "Only a
NAME typed the left operand".)

## Proposed fix

Arm the field record at the start of each term / additive operand (as `_op_rhs` does for the right), and in `_op_lst`
take a whole struct-typed field spanning `[beg, cursor)` — wrapped in parentheses or not — as the left operand's
struct; `_op_lhs_sv` then passes the field's own address (the `_fla_addr` path the right operand uses since 6.6.20), and
a field of another struct type is refused by name through `_op_lhs_check`. ⚠ This changes what `h.p - s` computes
today (an integer op becomes the operator call); the user's 2026-10-08 decision covered call / method / operator results
as the left operand, not fields — **confirm it extends to fields before landing**. Gate rows in
`tests/gates/codegen/struct_value_codegen.sh` (a new family beside L) for each base shape above, with the `s - h.p`
control.
