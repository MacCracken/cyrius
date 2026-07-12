# cx: pre-existing correctness gaps surfaced by the v6.4.54 forward-call fix (fmt_int digit-shift + high-half 64-bit immediates load as 0)

**Filed:** 2026-07-11 (during the v6.4.54 cx finish-out; surfaced by the forward-call/alignment fix de-masking).
**Severity:** P2 (cx-only; two distinct correctness bugs, both **pre-existing** — NOT introduced by v6.4.54).
**Backend:** cx (cyrius-x bytecode) only. x86/aarch64/PE unaffected.

## Context — why these surfaced now

v6.4.54 fixed cx code-stream misalignment (the 3-byte DCE stub) + the forward-call resolver.
Before that, any cx program pulling in DCE-dead module-0 fns derailed mid-chain to a `00`=HALT
and returned a "lucky 0", so a whole class of programs never actually *ran* their body. With the
fix they run for real — and expose two pre-existing cx gaps that were previously hidden.

## Symptom A — `fmt_int` prints a right-shifted decimal

`fmt_int(12345)` prints **`01234`** on cx (x86 prints `12345`) — drops the last digit and
prepends a `0`. This is why de-masked assert-framework tcyr on cx print e.g. `0 passed, 0 failed
(0 total)` where the true counts are `1/0/1`. **Control flow / exit codes are CORRECT** — the
globals hold the right values (verified: `return _assert_pass` after two passes exits 2 on cx);
only the decimal-digit *render* path (`lib/fmt.cyr` `fmt_int`) is wrong on cx.

Repro: `fn main(): i64 { fmt_int(12345); return 0; }` → cx stdout `01234`, x86 `12345`.

## Symptom B — high-half-only 64-bit immediates load as 0

`var x = 0x4018000000000000;` loads **0** on cx (x86: the real value). But `4294967297`
(`0x1_0000_0001`) loads **correctly**. So it is specific to 64-bit constants whose significant
bits live only in the high word — the cx `movi`/`movhi` large-constant emission sequence drops
them. This makes f64 *bit-pattern* SIMD tests (`f64v2_make`/`f64v4_make` with float hex
constants like `0x4018000000000000` = 6.0) spuriously read 0 on cx.

Repro: `fn main(): i64 { var x = 0x4018000000000000; if (x == 0) { return 1; } return 0; }`
→ cx exit 1 (BUG), x86 exit 0.

## Why not fixed in v6.4.54

v6.4.54 is scoped to the two filed cx bugs (value-form SIMD params/returns + the
"var-capture"/misalignment). A and B are **separate pre-existing defects** in different code
paths (`lib/fmt.cyr` digit loop; cx immediate codegen), correctly kept out per one-bug-one-fix.
They do not block v6.4.54: the cx gate `vr01_simd_cx.tcyr` uses `f64_from(int)` + small ints and
is genuinely green; assert-framework exit codes are correct despite the `fmt_int` misprint.

## Acceptance

- `fmt_int(N)` renders `N` correctly on cx for multi-digit N (differential vs x86).
- `var x = 0x4018000000000000` (and other high-half constants) loads the true value on cx.
- Investigate whether A and B share a root (cx large-value handling) or are independent.
- Regression `.tcyr` under the cx path; cx self-host byte-identical; x86 unaffected.
