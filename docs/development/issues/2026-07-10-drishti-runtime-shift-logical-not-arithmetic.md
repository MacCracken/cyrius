**Status (2026-07-10): RESOLVED in cyrius 6.4.46** — added a dedicated arithmetic
(sign-preserving) right-shift operator **`>>>`** (`x >>> n` = floor(x / 2^n)); `>>`
stays LOGICAL. NOTE the convention is the REVERSE of JS/Java (there `>>`=arith, `>>>`=logical):
in Cyrius `>>` must stay logical because it is load-bearing for crypto rotates
`(x<<n)|(x>>(64-n))` (keccak/sha/chacha) and the compiler's own union flag
`ISUNION() = fcount >> 63` — making `>>` arithmetic corrupts all of those (verified: it
broke SHA-3→TLS and union sizeof). x86 `sar`, aarch64 `asrv`, cx op 37; two-step-free
self-host + byte-identical. drishti can replace `dr_ashr` with `>>>`. Test:
`tests/tcyr/shift_right_arithmetic.tcyr`.

# `>>` is a logical (unsigned) shift with no arithmetic alternative — silently corrupts signed right-shifts

**Discovered:** 2026-07-10 during drishti (video codec lib) AV1 inverse-transform + frame-header work
**Severity:** High (silent wrong results — corruption-class — but confined to code that right-shifts negative values, and there is a clean consumer workaround)
**Affects:** cycc 6.4.43–6.4.45 (verified on 6.4.45; drishti hit it across the 6.4.43–6.4.45 wrapper span, and `>>` has presumably always been logical)

## Summary

Cyrius's `>>` operator performs a **logical (unsigned)** right shift on
the (signed) i64 value type, at both compile-time-fold and runtime, and
there is no arithmetic (sign-preserving) shift operator or intrinsic.
Right-shifting a negative value therefore silently yields a large
positive garbage value instead of `floor(x / 2^n)`. Because Cyrius's only
integer type is a signed i64, and C-family code assumes `>>` on a signed
value is arithmetic, this is a quiet footgun: `(-8) >> 1` returns
`9223372036854775804`, not `-4`. No error, no warning — just a wrong
number.

drishti transcribes AV1 spec algorithms whose `>>` is defined as an
arithmetic shift (the inverse DCT/ADST `Round2`, the Walsh-Hadamard
transform, `read_global_param`'s `PrevGmParams >> precDiff`). Every one
of those silently corrupted its output until we routed signed shifts
through a hand-rolled helper.

## Reproduction

```
fn shr(x, n): i64 { return x >> n; }     # runtime shift on a parameter
fn main() {
    var f  = (0 - 8) >> 1;               # constant-folded  -8 >> 1
    var rt = shr(0 - 8, 1);              # runtime          -8 >> 1
    var rc = 0;
    if (f  == (0 - 4))            { rc = rc + 1; }   # folded  == arithmetic (-4)
    if (f  == 9223372036854775804) { rc = rc + 2; }  # folded  == logical (0x7FFFFFFFFFFFFFFC)
    if (rt == (0 - 4))            { rc = rc + 4; }   # runtime == arithmetic (-4)
    if (rt == 9223372036854775804) { rc = rc + 8; }  # runtime == logical
    syscall(60, rc);
}
var z = main();
```

```
$ cyrius build shr_exact.cyr shr_exact.bin && ./shr_exact.bin; echo $?
10
```

`rc == 10` = bit1 (folded is logical) + bit3 (runtime is logical). So
**both paths give the logical result** `0x7FFFFFFFFFFFFFFC`
(9223372036854775804); neither gives the arithmetic `-4`. (Note: the
result is *consistent* between fold and runtime — an earlier drishti
probe wrongly suspected a fold/runtime mismatch, but that was a low-byte
exit-code collision: `0xFC` is the low byte of both `-4` and the logical
value. Checking the sign / full value shows they agree, both logical.)

## Root cause (speculation — flag for the Cyrius agent to confirm)

Presumably the x86 backend emits `shr` (logical) for the `>>` operator
where a signed value type would want `sar` (arithmetic). Since Cyrius has
one integer type and no signedness annotation, the operator has to pick
one behavior; it picked logical, which is the surprising choice for
`floor`-division-by-power-of-two idioms. I don't know the IR/codegen
internals well enough to point at the emit site.

## Proposed fix

Not blocking on a specific choice — options, roughly in order of least
surprise:

1. **Make `>>` arithmetic** for the i64 value type (emit `sar`). This
   matches C's signed `>>` and every spec that writes `x >> n` meaning
   floor-shift. Risk: any code relying on the current logical behavior of
   `>>` on values it *knows* are bit-patterns (e.g. `(v >> 8) & 0xFF`
   byte extraction) is unaffected, because the `& mask` discards the
   high-bit difference — so an arithmetic `>>` is backward-compatible for
   the masked-extraction idiom that dominates real code.
2. **Add an explicit arithmetic-shift** operator (e.g. `>>>` for one of
   the two, or an `ashr(x, n)` builtin) and keep `>>` logical. Lower blast
   radius, but leaves the footgun for anyone who writes `x >> n` expecting
   signed semantics.
3. **At minimum**: document the logical semantics prominently and add a
   `dr`/stdlib `ashr` helper so consumers stop re-rolling it.

If option 1 is taken, a sweep for `>>` used as intentional
unsigned/logical extraction (rare — usually paired with `& mask`, which
is safe either way) would de-risk it.

## Consumer-side workaround (shipped in drishti 0.7.5)

A core helper, used everywhere a possibly-negative value is shifted:

```
# Arithmetic (sign-preserving) right shift = floor(x / 2^n).
fn dr_ashr(x, n): i64 {
    if (x >= 0) { return x >> n; }
    return 0 - (((0 - x) + (1 << n) - 1) >> n);   # -ceil((-x)/2^n)
}
```

drishti audited all 89 `>>` sites: only genuinely-signed shifts (transform
`Round2`, WHT, `read_global_param`) needed it; the rest are non-negative
operands or `(v >> k) & mask` byte/bit extractions where the shift kind
is irrelevant. Fix landed in drishti CHANGELOG 0.7.5 ("Cyrius's runtime
`>>` is a LOGICAL shift").

**Consumer version:** drishti is on cycc 6.4.45. No minimum-floor bump is
needed on drishti's side (the workaround is pure Cyrius) — this is filed
so the sharp edge gets sanded upstream rather than re-discovered by the
next consumer doing signed fixed-point maths.
