# A pointer's step outlives the operator that consumed it: with `q: *i32`, `(x == q) + 100` adds 400 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
2,053,536 B) with the tree's compiler and the cross compilers built from it: the repro exits 255 (all eight rows wrong)
on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine), where 0 is right; its control row (`(0 - q) + 1`) is right. The
installed 6.7.4 and 6.7.7 compilers also exit 255. The merged tree's own source names the leak and leaves it
(`src/frontend/parse_expr.cyr:1694`–`1706`, C2-5's stamp comment: "6.6.17's step leaks the same way — `(x == q) + 1`
adds 4; reported, not changed").
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, reported only — bite C2-4b found the call-result field instance
(`mk(q).n + 1`), bite C2-5 measured the whole class (`~/.cache/c6/c2/changelog_handoff.md`, both bites' out-of-scope
sections).
**Severity:** High — silent wrong values on source that compiles clean, no diagnostic, every target.
**Affects:** cycc 6.6.17 (pointer arithmetic by the C rules) – 6.7.8: the installed 6.6.17, 6.7.4 and 6.7.7 compilers
and the merged 6.7.8 tip exit 255 (6.6.16 cannot parse the repro's `: *H` return).

## Summary

Since 6.6.17 `p + n` steps `n` by `sizeof(T)` for a typed pointer `p`, reading the left operand's step from the
pointer-scale word. That word is "the last factor's", not "this value's": nothing clears it when an operator CONSUMES
a pointer and produces a plain integer. So after any operator but `+` / `-` whose last operand was `q: *i32`, the next
`+ n` / `- n` steps by 4:

| Expression (`q: *i32`, `qq` its untyped copy) | Right | Computed |
|---|---|---|
| `(qq == q) + 100` | 101 | 401 |
| `(base && q) + 1` | 2 | 5 |
| `(1 * q) + 1` | qq + 1 | qq + 4 |
| `(m & q) + 1` (m = 0) | 1 | 4 |
| `(0 ^ q) + 1`, `(0 \| q) + 1` | qq + 1 | qq + 4 |
| `(~q) + 1`, `(-q) + 1` | ~qq + 1, -qq + 1 | + 4 |
| `mk(q).n + 1` (`fn mk(q: *i32): H`, `n` a plain field) | 1 | 4 |
| `mp(q).n + 1` (`fn mp(q: *i32): *H`) | 1 | 4 |

A method chain's field is right, and so is `(0 - q) + 1` (the `-` arm handles its own step).

## Reproduction

`docs/development/issues/repros/2026-10-10-pointer-step-leaks-through-operators.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
var HH = H { 0, 0 };
fn mk(q: *i32): H { var h: H; h.n = 0; h.m = 0; return h; }
fn mp(q: *i32): *H { return &HH; }
fn main(): i64 {
    var x: i32 = 0;
    var q: *i32 = &x;
    var qq: i64 = q;          # the same address, untyped
    var base = 1;
    var m = 0;
    var bad = 0;
    if ((qq == q) + 100 != 101) { bad = bad | 1; }       # 401
    if ((base && q) + 1 != 2) { bad = bad | 2; }         # 5
    if ((1 * q) + 1 != qq + 1) { bad = bad | 4; }        # qq + 4
    if ((m & q) + 1 != 1) { bad = bad | 8; }             # 4
    if ((0 ^ q) + 1 != qq + 1) { bad = bad | 16; }       # qq + 4
    if ((~q) + 1 != (~qq) + 1) { bad = bad | 32; }       # ~qq + 4
    if (mk(q).n + 1 != 1) { bad = bad | 64; }            # 4: a by-value struct result's field
    if (mp(q).n + 1 != 1) { bad = bad | 128; }           # 4: a `*H` result's field
    if ((0 - q) + 1 != (0 - qq) + 1) { bad = bad | 256; }   # control: right
    return bad;
}
var rc = main();
syscall(60, rc);
```

```
expected: exit 0
actual:   exit 255 (rows 1-128 wrong; bad >> 8 = 0, so the control is right) on all four targets
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

- `_PEXPR_IMPL` (`src/frontend/parse_expr.cyr:7203`) takes the left operand's step as `_pk_word(S)` (`:3630`), which
  strips a kind it cannot vouch for but returns `_ps_step(GPSC(S))` — the step of whatever factor wrote the scale word
  last. `_ptr_add` (`:6715`) and `_ptr_sub` then scale the integer by it.
- The comparison, logical, multiplicative and bitwise operators and unary `-` / `~` emit their result without
  resetting the word (`SPSC(S, 0)`), so `q`'s step survives as the step of `(x == q)`.
- A call result's field: `_field_load_type` (`src/frontend/parse_decl.cyr:1891`) writes the word only for a `*T`
  field (`:1897`), and `_call_scale_fix` (`parse_expr.cyr:2610`) resets it only when the factor is one whole call —
  `mk(q).n` continues past the `)`, so the last argument's step stays.

## Proposed fix

Make a value's step its OWN, as C2-5 did for the element kind: either reset the scale word in every operator that
produces a non-pointer (comparison, `&&` / `||`, `*` / `/` / `%`, the bitwise operators, unary `-` / `~`, a plain
field load — `SPSC(S, 0)` unconditionally in `_field_load_type` before the `*T` arm, the one-line fix C2-4b measured),
or strip the step from every word no producer stamped (`_pk_word`'s rule extended from the kind to the step). The
second needs every legitimate pointer producer stamped first — a `*Pt` pointer has kind 0 and is not stamped today —
so the per-operator reset is the smaller change. Rows: each table row, at `*i16` / `*i32` / `*i64` / `*Pt`, in a
`+` and a `-` position, plus `p + 1` / `p - q` / `*(p + 1)` unchanged, at the four targets.

Related (the same scale word, the opposite fault — a step that should be kept is dropped; filed the same day):
[`n + p` with a one-byte `*T` is no typed pointer](2026-10-10-int-plus-byte-pointer-drops-step.md). One lane should
take both.
