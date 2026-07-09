# cx: `var x = <call>` mis-captures when the callee returns a global and the caller previously mutated other globals

- **Filed**: 2026-07-09 (surfaced during v6.4.32 cx-SIMD gate bring-up)
- **Severity**: P2 (cx-only correctness; does not affect x86/aarch64/PE)
- **Status**: OPEN — pre-existing, NOT a v6.4.32 regression (reproduces on v6.4.31 with zero SIMD/arrays)
- **Backend**: cx (cyrius-x bytecode) only
- **Affected**: `src/backend/cx/emit.cyr` local-capture / return-value path (exact site TBD)

## Symptom

The canonical assert-based tcyr ending mis-captures on cx:

```cyrius
include "lib/assert.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    assert_eq(1, 1, "a");        # pass → _assert_pass=1, _assert_total=1, _assert_fail=0
    var ec = assert_summary();   # assert_summary returns _assert_fail (0)
    return ec;
}
var rc = main(); syscall(60, rc);
```

- **cx**: exit **1** (WRONG — captures `_assert_pass`/`_assert_total`, both 1)
- **x86 / aarch64 / PE**: exit **0** (correct — `_assert_fail`)

`return assert_summary()` **directly** (no `var ec` intermediate) returns 0 correctly on cx —
so the callee is fine; the bug is in the caller-side `var x = <call>` capture.

## Boundary (what does / doesn't reproduce)

Reproduces only with the *combination* below; each in isolation is correct on cx:

| Case | cx result |
|------|-----------|
| `return assert_summary()` direct (no local) | ✅ 0 |
| `var ec = assert_summary()` with **no** prior `assert_eq` | ✅ 0 |
| `assert_eq(...); var ec = ret5()` (callee returns a literal) | ✅ 5 |
| `bump_one_global(); var ec = fn_returning_other_global()` (hand-rolled) | ✅ 0 |
| `assert_eq(1,1,"a"); var ec = assert_summary()` | ❌ 1 |

The hand-rolled minimal (single global mutated, callee returns a different global via one
syscall) does **not** reproduce — the trigger needs assert.cyr's specific shape:
`assert_eq` mutates **two** globals (`_assert_total` + `_assert_pass`), then `assert_summary`
does nested `fmt_int` calls reading all three globals and `return _assert_fail`.

## Suspected root cause

cx codegen for `var x = <call>` appears to mis-resolve either (a) the store target for `x`
or (b) the value in the return register, when the callee's `return <global>` follows a chain
of nested calls + global reads and the caller has itself recently mutated globals. Likely a
scratch-register or global-slot aliasing between the return-value load and the local store.
The specific emit site is not yet localized.

## Why it's not blocking v6.4.32

The v6.4.32 cx-SIMD emitters + frame-addressing fix are proven correct independently
(manual exit-code checks over local + global arrays, `f64v_*`/`f32v_*`/`iv_*` all
byte-correct; x86 self-host byte-identical; no general 4-array `var = <call>` regression —
verified against the v6.4.31 baseline). The cross-OS SIMD gate
`tests/tcyr/vr01_simd_cx.tcyr` sidesteps this bug by ending with `return assert_summary()`
directly, and passes on all four backends (cx/x86/PE/aarch64).

## Acceptance criteria

- [ ] The minimal repro above returns **0** on cx.
- [ ] `var x = assert_summary()` (the standard tcyr ending) is byte-safe on cx so
      assert-based tcyr can run under the cx backend without the direct-return workaround.
- [ ] Root cause localized to the specific `emit.cyr` site + a one-line field note in
      `vidya/content/cyrius/field_notes/compiler.toml`.

## Roadmap pin

Track under the cx-backend hardening tail (roadmap-future / cx portable target arc
follow-ons). Not urgent: the cx round-trip verification fixture and the SIMD gate both avoid
the pattern; normal tcyr runs execute on x86.
