# A narrow scalar LOCAL (`u8` / `i16` / `i32`) is a one-byte pointer to the step checks, and `n + &x` is no pointer where `&x + n` is — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-11 while fixing
[`2026-10-10-int-plus-byte-pointer-drops-step.md`](2026-10-10-int-plus-byte-pointer-drops-step.md) (6.7.9, the
critical lane's bite 6), and reproduced on that lane's tip with the tree's compiler and with the installed 6.6.20 and
6.7.0 compilers. Not fixed there: both halves change what compiles or what warns, which the 6.7.9 decisions do not
cover (decision 1(b) is the one-byte `*T` only).
**Placement:** unpinned — for the user to place (it changes what compiles).
**Discovered:** 2026-10-11 during 6.7.9's `n + p8` fix (the `_add_word` element-kind test is what keeps it out).
**Severity:** Low — a refusal of a rare valid expression and a missing / spurious warning; no wrong value.
**Affects:** cycc 6.6.17 – 6.7.9, every target (the pointer-scale word is frontend state).

## Summary

The pointer-scale word (GPSC) holds a value's pointer step. Two producers write a step of 1 for a value that is no
`*T`, or that `n + v` then drops:

1. **A narrow scalar local** — `var w: u8` / `i8` / `u16` / `i16` / `u32` / `i32` — loads with step 1
   (`src/frontend/parse_expr.cyr`, the local-load arm: `if (lt < 8) { SPSC(S, 1); }`, v6.3.34 — "its scale for
   `+` / `-` arithmetic must be 1, not its byte width"; 1 scales nothing, but every reader that asks "is this a
   pointer?" (`> 0`) answers yes). So the step checks treat the integer as a byte pointer: `w - q32` and
   `(w + 1) - q32` are REFUSED "pointer difference of pointers with different element sizes" (an integer minus a
   pointer is `n - p`, as it is for an `i64` local, a narrow global or a narrow parameter), and `var r: *u32 = w;` /
   `var r: *u8 = w + 1;` do not warn "assigning non-pointer to typed pointer", while `var r: *u8 = 1 + w;` does.
2. **`&x`** loads with step 1 and no element kind (v6.5.29: "`&x` IS a pointer", byte-addressed). `&x + n` keeps it,
   `n + &x` drops it (the left operand's word, the integer's 0): `var r: *u32 = 4 + &B;` warns where `&B + 4` is silent,
   and `(4 + &B) - q32` builds a byte difference where `(&B + 4) - q32` is refused. 6.7.9 made `n + p` keep a one-byte
   `*T`'s word (`_add_word`) and deliberately kept the element-kind test that excludes these two producers: without
   it, `(1 + w) - q32` would become a NEW refusal of valid code (half 1's defect spreading).

## Reproduction

```cyrius
var B: i64[4];
fn f(): i64 {
    var q32: *u32 = &B;
    var w: u8 = 5;
    var d1 = w - q32;             # error: pointer difference ... different element sizes (valid: n - p)
    var d2 = (w + 1) - q32;       # error, the same
    var r1: *u32 = w;             # silent (an integer into a typed pointer: should warn)
    var r2: *u8 = 1 + w;          # warning (the same value spelled w + 1 is silent)
    var r3: *u32 = 4 + &B;        # warning, where `&B + 4` is silent
    var d3 = (4 + &B) - q32;      # silent byte difference, where `(&B + 4) - q32` is refused
    return 0;
}
syscall(60, f());
```

```
actual (6.6.17 - 6.7.9):  errors at d1, d2; warnings at r2, r3; r1 and d3 silent
one consistent answer:    d1, d2 compile (n - p); r1 and r2 both warn (an integer); r3 and d3 as their
                          `&B + 4` spellings (silent / refused) — or the user's other choice for `&x`
```

## Root cause

Half 1: the narrow-scalar arm sets the scale to 1 instead of 0; no other reader needs a 1 there (EPTR_SCALE treats 0
and 1 alike). Half 2: `_add_word` (parse_expr.cyr, 6.7.9) writes back the right operand's word only when it carries
an element kind, which `&x` does not.

## Proposed fix

Half 1: `SPSC(S, 0)` for a narrow scalar local (a differential of the tree first — a `*T` declaration from such a
local starts warning, and `w - q32` starts compiling). Half 2: the user's call whether `n + &x` is a byte pointer like
`&x + n` (then `_add_word` also writes a kind-less step 1 once half 1 has removed the scalar producer), or whether
`&x + n` should stay a byte address that is no `*T` to the difference check. Rows beside the DXc / DXn rows in
`tests/gates/frontend/pointer_subscript_checked.sh`.

## Consumer-side workaround

Widen first (`var wi: i64 = w;`) or write the address first (`&B + 4`).
