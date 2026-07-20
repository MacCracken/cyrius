# `fmt_hex` / `fmt_hex0x` / `fmt_hex_buf` silently print nothing for any high-bit-set value — OPEN

**Discovered:** 2026-07-19 while dumping f64 bit patterns during **samay** M4 JSON work
(the `-0.0` pattern `0x8000000000000000` printed as bare `0x`).
**Severity:** Medium — silent wrong output, no diagnostic. Not data corruption on disk,
but it silently destroys exactly the values you reach for hex to inspect: negative
numbers, error codes, pointers with the high bit set, and IEEE-754 patterns for negative
floats / `NaN` / `-Inf`. Trivial workaround once you know (mask and print halves), but
the failure is invisible — you get a plausible-looking `0x` and no error.
**Affects:** cycc **6.4.67** (only version tested; the code looks long-standing).
`lib/fmt.cyr`.

## Summary

`fmt_hex(n: i64)` loops `while (n > 0)` over a **signed** i64. For any `n` with bit 63
set the loop body never executes, and the `if (n == 0)` zero-special-case doesn't fire
either — so the function emits **zero digits**. `fmt_hex0x` prints its `0x` prefix and
then nothing; `fmt_hex_buf` returns length `0` and writes only a NUL.

Every negative i64 and every u64 ≥ 2^63 is affected. There is no error, no truncation
marker, no partial output — just silence.

## Reproduction

`docs/development/issues/repros/2026-07-19-fmt-hex-high-bit-prints-nothing.cyr`

```
$ cyrius build docs/development/issues/repros/2026-07-19-fmt-hex-high-bit-prints-nothing.cyr /tmp/hexbug
$ /tmp/hexbug
-- high bit clear (works) --
1                  fmt_hex0x -> 0x1   fmt_hex_buf len=1
0x7fffffffffffffff fmt_hex0x -> 0x7fffffffffffffff   fmt_hex_buf len=16
0                  fmt_hex0x -> 0x0   fmt_hex_buf len=1

-- high bit set (broken) --
0x8000000000000000 fmt_hex0x -> 0x   fmt_hex_buf len=0  <-- WROTE NOTHING
-1                 fmt_hex0x -> 0x   fmt_hex_buf len=0  <-- WROTE NOTHING
0xfff0000000000000 fmt_hex0x -> 0x   fmt_hex_buf len=0  <-- WROTE NOTHING

empty-output count: 3
$ echo $?
1
```

Deterministic.

## Root cause (verified)

`lib/fmt.cyr:50` — `fmt_hex`:

```cyrius
fn fmt_hex(n: i64): i64 {
    var buf[16];
    var bi = 15;
    if (n == 0) { store8(&buf + bi, 48); bi = bi - 1; }
    while (n > 0) {                 # <-- signed compare: false for every high-bit-set n
        var nib = n & 0xF;
        ...
        n = n >> 4;
    }
    syscall(1, 1, &buf + bi + 1, 15 - bi);
    return 0;
}
```

`lib/fmt.cyr:115` — `fmt_hex_buf` has the identical `while (n > 0)` guard, so it returns 0
and writes an empty string.

The signed comparison is the **whole** bug. Cyrius `>>` is a **logical** (zero-fill) shift,
verified: `(0 - 1) >> 63` evaluates to `1`, and `while (m != 0) { m = m >> 4; }` starting
from `-1` terminates after exactly **16** iterations. So the shift is already correct for
high-bit-set inputs — only the loop guard is wrong.

## Proposed fix

One word, in two places: change the guard from `while (n > 0)` to `while (n != 0)` in
both `fmt_hex` (`lib/fmt.cyr:54`) and `fmt_hex_buf` (`lib/fmt.cyr:119`).

Because `>>` is logical, the existing body then walks all 16 nibbles of a high-bit-set
value and terminates. `fmt_hex`'s `var buf[16]` is exactly wide enough for the 16 digits
of a full-width value, and `bi` lands at `-1` — so `&buf + bi + 1` is `&buf` and the
length `15 - bi` is `16`. No buffer change needed. (Worth a second reviewer's eye on that
boundary: it is exactly-fits, with no slack.)

Also check whether `fmt_sprintf`'s `%x` path (`lib/fmt.cyr:146`) shares the defect — it
was not examined here.

Worth adding a regression test over `{0, 1, 0x7fffffffffffffff, 0x8000000000000000, -1,
0xfff0000000000000}` — the repro above is that matrix.

## Consumer-side workaround

Print the two halves separately:

```cyrius
fmt_hex((n >> 32) & 0xFFFFFFFF);   # high word
fmt_hex(n & 0xFFFFFFFF);           # low word (zero-pad to 8 manually if needed)
```

samay hit this only in throwaway debug output, so nothing shipped around it.

**Reporting on:** cycc 6.4.67.

## Related

Found while investigating
[`2026-07-19-f64-json-roundtrip-6-decimal-cap.md`](./2026-07-19-f64-json-roundtrip-6-decimal-cap.md)
(f64 JSON serialization is lossy). Independent bug — same file, unrelated cause.
