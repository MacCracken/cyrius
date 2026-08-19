# `fmt_float` drops the carry when the fraction rounds up to a full unit

**Status:** 🟡 **OPEN** — found by ganita 1.1.3 while testing the linalg tier; not yet triaged.
**Placement:** unpinned — 6.5.x backlog. Stdlib (`lib/fmt.cyr`), not the compiler.
**Discovered:** 2026-08-19 during ganita's linalg test pass (every near-integer solver result printed wrong)
**Severity:** Low — display only, no wrong computation. See "Why this punches above Low" below.
**Affects:** cycc 6.5.28 (verified against the released tarball). The fraction/zero-pad
block is long-standing — `de22b4af` introduced the padding, and nothing since has
touched the carry case — so almost certainly every version that has had
`fmt_float_buf`.

## Summary

`fmt_float(v, decimals)` scales the fractional part by `10^decimals` and rounds it. When
that rounding carries — i.e. the fraction reaches a full unit — the carry is neither
applied to the integer part nor truncated, so the raw `10^decimals` is emitted verbatim as
the fraction field. The result has **one digit too many** and reads as a completely
different number.

| value | printed | expected |
|---|---|---|
| `3 - 1e-7` | **`2.1000000`** | `3.000000` |
| `2 - 1e-7` | **`1.1000000`** | `2.000000` |
| `1 - 1e-8` | **`0.1000000`** | `1.000000` |
| `-(3 - 1e-7)` | **`-2.1000000`** | `-3.000000` |
| `10 - 1e-7` | **`9.1000000`** | `10.000000` |
| `3` exactly | `3.000000` ✅ | `3.000000` |
| `0.5` | `0.500000` ✅ | `0.500000` |
| `123.456` | `123.456000` ✅ | `123.456000` |

The tell is the digit count: seven fraction digits for `decimals = 6`.

## Reproduction

[`repros/2026-08-19-fmt-float-carry.cyr`](repros/2026-08-19-fmt-float-carry.cyr)

```sh
cyrius build docs/development/issues/repros/2026-08-19-fmt-float-carry.cyr /tmp/fmtcarry
/tmp/fmtcarry
```

Output as of 6.5.28 — the first five lines are wrong, the last three are the contrast set:

```
3 - 1e-7     got='2.1000000'  want='3.000000'
2 - 1e-7     got='1.1000000'  want='2.000000'
1 - 1e-8     got='0.1000000'  want='1.000000'
-(3 - 1e-7)  got='-2.1000000'  want='-3.000000'
10 - 1e-7    got='9.1000000'  want='10.000000'
3 exactly    got='3.000000'  want='3.000000'
0.5          got='0.500000'  want='0.500000'
123.456      got='123.456000'  want='123.456000'
```

## Root cause

`lib/fmt.cyr`, `fmt_float_buf` (line 255). Not speculation — confirmed by patching it.

The integer part is emitted at **line 281**, before the fraction is computed at **line 287**:

```cyrius
var whole = f64_to(f64_floor(val));          # 278
var pos = 0;
if (neg == 1) { store8(buf, 45); pos = 1; }
pos = pos + fmt_int_buf(whole, buf + pos);   # 281  <- integer part already written
store8(buf + pos, 46); pos = pos + 1;
...
var frac = f64_to(f64_round(f64_mul(f64_sub(val, f64_from(whole)), scale)));   # 287
```

For `val = 2.9999999` and `decimals = 6`: `whole = 2` is written, then
`frac = round(0.9999999 * 1000000) = 1000000`. By then the carry has nowhere to go.

The zero-pad block at 290–299 cannot rescue it either — it only ever pads:

```cyrius
var flen = fmt_int_buf(frac, buf + pos);   # 7 digits for 1000000
var pad = decimals - flen;                 # 6 - 7 = -1
if (pad > 0) { ... }                       # skipped
```

so `1000000` is emitted as-is, giving `"2." + "1000000"`.

## Proposed fix

Compute the fraction **before** emitting the integer part, and carry:

```cyrius
var whole = f64_to(f64_floor(val));
# Fraction first — rounding it can carry into the integer part.
var scale = f64_from(1);
var di = 0;
while (di < decimals) { scale = f64_mul(scale, f64_from(10)); di = di + 1; }
var frac = f64_to(f64_round(f64_mul(f64_sub(val, f64_from(whole)), scale)));
if (frac < 0) { frac = 0 - frac; }
if (frac >= f64_to(scale)) { frac = 0; whole = whole + 1; }   # <- the fix
var pos = 0;
if (neg == 1) { store8(buf, 45); pos = 1; }
pos = pos + fmt_int_buf(whole, buf + pos);
store8(buf + pos, 46); pos = pos + 1;
var flen = fmt_int_buf(frac, buf + pos);
# ... existing zero-pad block unchanged ...
```

**Verified**: applying exactly this as a side-by-side `fixed_fmt_float_buf` in one
compilation unit gives

```
2.9999999    stock='2.1000000'   fixed='3.000000'
1.9999999    stock='1.1000000'   fixed='2.000000'
0.99999999   stock='0.1000000'   fixed='1.000000'
-2.9999999   stock='-2.1000000'  fixed='-3.000000'
9.9999999    stock='9.1000000'   fixed='10.000000'
0.5          stock='0.500000'    fixed='0.500000'
2.1          stock='2.100000'    fixed='2.100000'
123.456      stock='123.456000'  fixed='123.456000'
inf          stock='inf'         fixed='inf'
```

Every broken case corrected, every correct case byte-identical, non-finite path
untouched. `9.9999999 -> 10.000000` confirms the carry propagates through the integer
digit count correctly. The sign is handled before this point (`val = f64_abs(val)` at
line 260), so negatives carry on the magnitude and the `-` is prepended separately.

Worth a regression test in the `fmt` `.tcyr` — a value one ulp below an integer at
several `decimals` settings, including `decimals = 0`.

## Why this punches above Low

By the severity ladder this is display-only, so Low. In practice it misreports during
exactly the debugging where float digits matter, and it points the finger at the caller:

- ganita's `cholesky_solve` returned `3.0` (correct to 1e-9) and printed `2.1000000`.
- ganita's `least_squares` returned `1.0` (correct) and printed `0.1000000`.

A near-integer result is the *normal* outcome of a decomposition, so anyone reading
printed output would go hunting in the solver. Both were caught only because the tests
compare numerically rather than on text.

## Consumer-side workaround

Do not treat `fmt_float` output as authoritative when a value sits just below an integer —
compare numerically (`f64_abs(f64_sub(a, b)) < tol`). ganita 1.1.3's suite does this
throughout and is unaffected; the issue is tracked consumer-side at
`ganita/docs/development/issues/2026-08-19-fmt-float-missing-carry-on-round-up.md`.
