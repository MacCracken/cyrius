# A destructure in the top-level declaration zone, `var ZA, ZB = mm3(1.5);` with mm3 written `(f64, i64)`, leaves ZA untyped: `ZA * 2.0` computes on the double's bits — OPEN

**Status:** 🔴 **OPEN** — found 2026-10-20 by the 6.7.16 genbind lane (unit GB6, beside
issues/2026-10-18-generic-multi-value-type-parameter-element-binds-i64.md) and re-measured by the genbind review on the
lane head and the lane's base 41ca7d41c: identical. No generic is involved.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind lane; placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; s16 lane, wave 4, unit SZ5) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D98 — ZA is f64, as in a fn (`f64_to(ZA * 2.0) + ZB` is 10).
**Severity:** Medium. A wrong value (with only an arithmetic warning): the same line computes differently by its position.
**Kind:** bug (miscompile) — **needs the user's decision** (typing the zone's destructure changes what such programs compute).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn mm3(x: f64): (f64, i64) { return (x, 7); }
var ZA, ZB = mm3(1.5);
var r = f64_to(ZA * 2.0) + ZB;
syscall(60, r);
```

```
warning:<source>:4:24: integer arithmetic with an f64 right operand
```

rc 0, exit **7** (ZA is an integer word holding 1.5's bits; `ZA * 2.0` is integer arithmetic). The same destructure
after the first top-level statement binds ZA as f64:

```cyrius
include "lib/syscalls.cyr"
fn mm3(x: f64): (f64, i64) { return (x, 7); }
var q = 1;
q = 2;
var ZA, ZB = mm3(1.5);
var r = f64_to(ZA * 2.0) + ZB;
syscall(60, r);
```

rc 0, no warning, exit **10** (3 + 7). In a fn, `var a, b = mm3(1.5);` binds f64 too.

## Why it is open

The declaration zone (the globals before the first top-level statement) is replayed by `EMIT_GVAR_INITS`, not
PARSE_VAR, and its destructure records no element type for its names; the kernel-mode replay runs after the program is
parsed. Typing ZA as f64 there changes what such programs compute (10 where they computed 7) and needs the zone's
pass-1 / kernel replay order settled — the user's call. A related untyped zone global, `var Y = mkf(1.5);` with mkf
`: f64`, is no f64 at top level either (the lane's handoff, GB6).

## Acceptance

The verbatim repro gives the decided result on x86_64, aarch64, cx and PE, at the zone and after the first statement
alike; a generic `mm2<f64>` element (multi_return.tcyr mv_* rows) the same.
