# A bounded generic called at `f64` is refused unless the trait ALSO has `impl … for i64`: `gb(h)` with only `impl Show for f64` says "needs `impl Show for i64`" — OPEN

**Status:** 🟡 **OPEN** — reported by the 6.7.9 critical lane (bite 9, the generic f64 result) as pre-existing and
untouched. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B) on x86_64 and
`cycc_aarch64`: repro A (inferred) and B (explicit `gb<f64>(h)`) are both refused naming `impl Show for i64`; repro C
(no f64 impl, no i64 impl, a struct impl only) is refused naming `impl Show for i64` where `f64` is the type the call
binds. The installed 6.7.8 compiler refuses A the same way; 6.7.0 refuses it as "has no i64 (or other scalar)
instance". The 6.7.9 rows (`tests/tcyr/crossos/generic_f64_result.tcyr`, gate `frontend/generic_f64_result.sh`) always
declare both impls, so they never meet it.
**Placement:** 6.7.11 — repair 1, the generics / call-path lane (roadmap.md § *The releases after 6.7.8*) — placed
2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 9.
**Severity:** Medium — valid source (the guide's own rule) is refused, with a note that names the wrong type; the
workaround is a dummy `impl Show for i64`.
**Affects:** cycc 6.7.0 (measured, another message) – 6.7.9, every target (the check is frontend).

## Summary

The guide (§ Generics, 6.7.9): "A bound is then met at `f64`: `gb(h)` with `fn gb<T: Show>` calls `impl Show for
f64`'s method, and is refused without one, as `gb<f64>(h)` is." With an `impl Show for f64` and NO `impl Show for
i64`, both spellings are refused — the bound is checked against `i64`, the generic's base, not against the `f64` the
call binds. A struct type argument does not hit it (`gb(q)` with only `impl Show for Q` compiles and runs, exit 7), and
with both impls present the f64 call is right (the 6.7.9 rows). With neither the f64 nor the i64 impl, the refusal's
note names `i64`, so it points at the wrong impl to add.

## Reproduction

```cyrius
# A — inferred
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn main(): i64 { var h: f64 = 1.5; return gb(h); }
syscall(60, main());
```

```
error:<source>:5:46: generic 'gb': its type argument does not implement trait 'Show'
  note: the bound on type parameter 'T' needs `impl Show for i64`, and there is none
expected: compiles; exit 5
```

B is A with `return gb<f64>(h);` — the same refusal. C replaces the f64 impl with `struct Q { a; } impl Show for Q
{ … }` and keeps `gb<f64>(h)`: refused, but the note names `impl Show for i64` (expected: `impl Show for f64`).

## Root cause (speculation, from the messages)

The bound check (`_bnd_check_fn` at instantiation, 6.7.1) runs for the generic's i64 BASE as well as for the instance
the call reaches, or judges the f64 call against the base's type when the scalar instance is formed; a struct
instance skips the base check, which is why only scalar type arguments meet it.

## Proposed fix

Judge the bound once, at the type the call binds (`f64` here), and never against the base for a call that reaches a
concrete instance; a base that no call reaches is not bound-checked (it is dead). Rows in
`frontend/generic_f64_result.sh`: A and B compile and exit 5 (x86_64, qemu-aarch64, cxvm, PE under wine); C refused
naming `impl Show for f64`; the method spelling `p.bm(h)` with only the f64 impl; an i64-only impl with an i64 call
unchanged.
