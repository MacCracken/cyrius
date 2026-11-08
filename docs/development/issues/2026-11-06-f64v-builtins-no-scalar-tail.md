# `f64v_*` and `f64v256_*` write past the end of `dst` when `n` isn't a multiple of their lanes

**Status:** 🔴 **OPEN.**
**Placement:** unpinned.
**Where the fix lives:** `EMIT_F64V_LOOP` and `EMIT_F64V4_LOOP` in
`src/backend/x86/float.cyr`, and the matching loop in `src/backend/aarch64/emit.cyr`.
**Discovered:** 2026-11-06, writing row kernels for goonj's grid solvers.
**Reporter:** goonj v2.3.0
**Cyrius version at time of report:** 6.7.18
**Severity:** High for anyone calling these with a variable `n`. A silent heap overrun: up
to 1 element for `f64v_*` and 3 for `f64v256_*`, with no diagnostic, and reads overrun too.
**Affects:** cyrius 6.7.18, x86_64 and aarch64 (NEON, run under qemu). Earlier versions not
checked. `f32v_*` is described as a mirror of the same loop at `float.cyr:280`, and wasn't run.
What's said about cx below comes from its source: the repro built for cx, but timed out under
`cxvm` with no output, and that wasn't looked into.

## Summary

The builtins take a length, `f64v_add(dst, a, b, n)`, but the emitted loop steps a whole
register at a time and has no scalar tail:

```
xor rsi, rsi
loop: cmp rsi, n ; jge done
      movupd xmm0, [a + rsi*8]
      movupd xmm1, [b + rsi*8]
      addpd  xmm0, xmm1
      movupd [dst + rsi*8], xmm0
      add rsi, 2
      jmp loop
```

So `n` rounds up to the next multiple of the lanes. `f64v_add(dst, a, b, 1)` writes two
elements, and `f64v256_add(dst, a, b, 5)` writes eight.

Nearly every in-tree caller passes a literal 2 or 4, which is why it rarely shows. The rule
is known, but it isn't written where a caller would look:

- **hisab already works around it by hand.** `_lext_gf_loop`, the one variable-length caller
  found outside goonj, passes an even `ne` and adds the last entry itself: "Both step in
  pairs, so an odd n's last entry is added alone".
- **`lib/simd.cyr`** says "n is 4 here and MUST stay a multiple of 4", about the `f64v4`
  wrappers only.
- **`docs/stdlib-reference.md:1196` says the opposite.** It calls these "pointer+count" verbs,
  "the portable form that runs identically on every backend". At a length that isn't a
  multiple they don't: `src/backend/cx/emit.cyr:1601` describes the cx backend as "a per-lane
  scalar loop driven by `n`", so cx stops at `n` where x86_64 and aarch64 run past it.

## Reproduction

`repros/2026-11-06-f64v-builtins-no-scalar-tail.cyr` fills a buffer with a guard, runs each
builtin over `n` elements, and counts writes past `n`. The exit code is the number of calls
that overran.

```
cyrius build docs/development/issues/repros/2026-11-06-f64v-builtins-no-scalar-tail.cyr /tmp/f64vtail
/tmp/f64vtail; echo "exit=$?"      # -> 9 on x86_64 with AVX2, 5 without it or on aarch64; should be 0
```

| call | elements written | past `n` |
|---|---:|---:|
| `f64v_add(dst, a, b, 1)` | 2 | 1 |
| `f64v_add(dst, a, b, 3)` | 4 | 1 |
| `f64v_scale(dst, a, s, 1)` | 2 | 1 |
| `f64v_mul(dst, a, b, 3)` | 4 | 1 |
| `f64v_sub(dst, a, b, 5)` | 6 | 1 |
| `f64v256_add(dst, a, b, 1)` | 4 | 3 |
| `f64v256_add(dst, a, b, 3)` | 4 | 1 |
| `f64v256_add(dst, a, b, 5)` | 8 | 3 |
| `f64v256_add(dst, a, b, 7)` | 8 | 1 |

## How it showed up

goonj's first row kernels called `f64v_*` with row lengths from the grid size. On odd rows
each call overran by one element, and every test suite passed, because they compare within a
tolerance. The elements inside `n` are all correct, so a parity check that only reads those
sees nothing: a bit-parity sweep of lengths 1 to 33 passed too. It was caught only by hashing
whole solver results against the previous release, where a receiver trace had changed.

Whether an overrun does damage depends on what the allocator placed next, so it can pass for a
long time and move with unrelated changes.

## Proposed fix

**Give the x86_64 and aarch64 emitters a scalar tail.** After the packed loop, one `addsd`-style
step, or up to three for `f64v256_*`, finishes the remainder. That makes `n` mean what the
signature says and what cx already does. The cost for an exact multiple is one compare, and a
literal `n` could skip it. Bits don't change: packed and scalar IEEE operations round the same.

If a tail isn't wanted in these kernels:

- Refuse a literal `n` that isn't a multiple at compile time.
- Correct `docs/stdlib-reference.md:1196`, and state the rule there.
- Have `--bounds` check it at run time.

## Workaround

goonj 2.3.0 wraps them in `_row_add`, `_row_sub`, `_row_mul` and `_row_scale` (`src/error.cyr`),
which run the largest multiple through the builtin and finish with a scalar op. Its
`tests/hardening.tcyr` checks exactly `n` elements are written at every length to 80, on each
path. See its ADR-0008.
