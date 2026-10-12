# `n + p` with a one-byte `*T` (`*u8` / `*i8`) is no typed pointer, where `p + n` is — `(1 + p8) - q32` builds, `var r: *u8 = 1 + p8;` warns — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 6, l679-crit; CHANGELOG [6.7.9]) `n + p` with a one-byte `*T` on the right keeps p's word, as `p + n` does (the user's decision 1(b); `_add_word` in parse_expr.cyr — a step of 1 with no element kind, `&x` or a narrow scalar, is no `*T` and is not written): `(1 + p8) - q32` is the different-sizes error, `var r: *u8 = 1 + p8;` is silent, `(1 + p8) - p8` stays an element count; the dereference-only stamp 6.7.8 added for `*(1 + p8)` is folded into the word and removed. No emitted byte changes (a 1098-source corpus differential is identical, diagnostics aside from the repro's). The repro gives exactly d1, d2, d3 refused and no warning; rows: `frontend/pointer_subscript_checked.sh` DXc1-5 (DXc inverted, from each one-byte source), DXn, DXR and `tests/tcyr/crossos/typed_pointer_step.tcyr` `onebyte_rows` on every leg, mutation-proven.

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above (reproduced on the 6.7.9 lane tip @ 7566a428 before the fix: the warning at 8:24, d1 and d3 refused, d2 silent). As filed: 🟡 OPEN — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: in the repro `var r: *u8 = 1 + p8;` warns "assigning non-pointer to typed pointer" (the same line
spelled `p8 + 1` is silent), and `(1 + p8) - q32` builds as a plain byte difference, while `(p8 + 1) - q32` and
`(1 + q32) - p8` are both refused "pointer difference of pointers with different element sizes". The same with the
installed 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers (6.6.10 warns the same and has no different-sizes
refusal yet). The dereference half the lanes also reported — `*(1 + p)` through a `*u8` read a WORD — is FIXED in
6.7.8 (commit 963a6d2f, the C2 review: the element kind rides a dereference-only stamp; gate rows DX / DXr).
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bites C2-3a and C2-5 (`_ptr_add` writes back only the left
operand's step word); gate row DXc pins today's behaviour.
**Severity:** Low — a missed refusal and a spurious warning; no wrong value (the difference is the byte difference
this shape has always computed).
**Affects:** cycc 6.6.10 – 6.7.8 (every target: the step word is shared frontend state)

## Summary

A `*T` operand carries a step word (sizeof(T), and since 6.7.8 its element kind). `p + n` keeps p's word, so the
result is still a `*T`. `n + p` with a step OVER 1 goes through `_int_plus_ptr`, which scales `n` and keeps p's word
too. `n + p` with a step of 1 (`*u8`, `*i8`, the only pointers whose step needs no scaling) takes the plain integer
add instead, and that add writes back the LEFT operand's word — the integer's, 0. So `1 + p8` is an untyped word: it
warns when stored into a `*u8`, and a pointer difference against a `*u32` is not checked — the two spellings of one
pointer disagree. 6.7.8 already gives `*(1 + p8)` the element's width through a separate dereference-only stamp
(`_PKD_MARK`); it deliberately left the step word alone because restoring it changes what compiles.

Related, the opposite direction of the same step-word bookkeeping: [a pointer's step outlives the operator that
consumed it](2026-10-10-pointer-step-leaks-through-operators.md) (`(x == q) + 100` adds 400) — this one DROPS a word
that should survive; that one KEEPS a word that should not. One lane, one set of rows.

## Reproduction

`docs/development/issues/repros/2026-10-10-int-plus-byte-pointer-drops-step.cyr`:

```cyrius
include "lib/syscalls.cyr"
var B: i64[4];
fn f(): i64 {
    var p8: *u8 = &B;
    var q32: *u32 = &B;
    var q: *u8 = p8 + 1;                 # silent
    var r: *u8 = 1 + p8;                 # warning: assigning non-pointer to typed pointer
    var d1 = (p8 + 1) - q32;             # error: pointer difference of pointers with different element sizes
    var d2 = (1 + p8) - q32;             # silent: a byte difference
    var d3 = (1 + q32) - p8;             # error (a step-4 `n + p` keeps its step)
    return d2;
}
syscall(60, f());
```

```
actual:   warning at r; errors at d1 and d3; d2 silent
expected: r silent (as q); d2 refused like d1 and d3
```

## Root cause

`_ptr_add` (`src/frontend/parse_expr.cyr:6715`): `if (ps == 0) { if (_ps_step(rs) > 1) { return _int_plus_ptr(S, rs);
} }` — a right-hand step of 1 falls through to `EPTR_SCALE` / `EADDR` and `_pk_set(S, ps)` with `ps` the LEFT
operand's word (0 for an integer). `_pkd_add` (`:6731`) then marks only the dereference kind.

## Proposed fix

When the left operand has no step and the right one has a step word (of any size), write the RIGHT operand's word
back (`_pk_set(S, rs)`) — step 1 needs no scaling, only the word. That turns `(1 + p8) - q32` into the
different-sizes error and silences the warning (the user's call), and makes the dereference-only stamp for this
shape redundant (keep `_pkd_add` for the `(n + p) + m` chains it also covers, or fold it into the word). Rows: the
repro; `1 + p8` into a `*u8` parameter and an if-expression; `(1 + p8) - p8` (stays legal: the same element size);
`*(1 + p8)` still one byte; `*i8` too; DXc inverted.

## Consumer-side workaround

Write the pointer first: `p8 + 1`.
