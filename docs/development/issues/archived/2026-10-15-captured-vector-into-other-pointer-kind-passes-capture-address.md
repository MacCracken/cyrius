# Inside a closure, a captured vector passed to `p: *Pt` / `p: *i64` passes the capture's address (exit 42), where the same local outside the closure is refused by name under D27 — RESOLVED

> ✅ **RESOLVED in v6.7.13** (VC-8, `87e585b9`: the user's decision D32, 2026-10-15 (A — refused, as the local is). Both filed repros, `|k| ri(b) + k` and `|k| rp(b) + k`, are refused once on x86_64, IR=3, aarch64, cx and PE — "cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'ri' - pass &b for its address" — where they ran (42); a captured vector into `*u8` / `**T`, wrapped, into a `*V` of another type (A2's words) or into a by-value struct (D31's words) is refused too, and into a `*V` of its own type it still passes the captured copy's address. The triage's "found in passing" wrong-lane read was `load64(p + 8)` on a `*f64v2` (eight vectors on), not a defect. Rows: `simd_pointer_param.sh` CR1 (the repro verbatim), CR2, CRX (six lines), CRY1 / CRY2 / CRYw, `simd_pointer_param.tcyr` `sp_crows` (7 rows); mutations M-C1 / M-C2 RED. Filed beside it: a captured vector into a VALUE-form parameter is refused on every target (the user's call). CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — a question for the user. Measured 2026-10-15 on the 6.7.12 fixfirst lane (after D27, `2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md`) and on the slot-open compiler (`7f57e532`): both repros compile with no diagnostic and exit 42 on x86_64, x86_64 `CYRIUS_IR=3`, aarch64 (qemu), cx and PE (wine) — the same on the slot-open compiler (x86_64 measured). Outside a closure the lane refuses `ri(b)` / `rp(b)` by name.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D32 — A.
**Discovered:** 2026-10-15, the review of the 6.7.12 fixfirst lane (D27 inside a closure).
**Severity:** Low — no fault (the address is the capture's real storage, so the callee reads lane 0's value); an inconsistency with D27's refusal, not a wrong value.
**Kind:** language (decision) — D27's answer (B: "another pointer kind refused by name") against what a capture does today, which is option C's meaning (an address to any typed pointer), the option the user did not pick.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
fn rp(p: *Pt): i64 { return p.x; }
fn ri(p: *i64): i64 { return *p; }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var c = |k| ri(b) + k;       # outside a closure, ri(b) is refused by name (D27)
    return fncall1(c, 0);
}
var rc = main();
syscall(60, rc);
```

```
fixfirst lane: x86_64 42, IR=3 42, aarch64 42, cx 42, PE 42      (no diagnostic)
```

`var c = |k| rp(b) + k;` (with `p: *Pt`): the same, 42 on all five. The same calls outside the closure:

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
fn rp(p: *Pt): i64 { return p.x; }
fn ri(p: *i64): i64 { return *p; }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    return ri(b) + rp(b) - 42;
}
var rc = main();
syscall(60, rc);
```

```
error:<source>:8:15: cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'ri' - pass &b for its address
error:<source>:8:23: cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'rp' - pass &b for its address
(every target)
```

## Root cause

The review's reading (not instrumented): D27's two refusal sites, `_sarg_vec_other` and `_sarg_vec_ptr` (via the
vector-local arm), find the argument with `FINDLOCAL` / the local's SLTYPE (src/frontend/parse_fn.cyr), so a closure's
captured vector — reached through the capture path — never meets the refusal, and the capture's address is pushed.

## The question

Refuse the capture too ("cannot pass 'b' to a parameter that is not a pointer to its vector type"), so D27's rule does
not depend on whether `b` is a local or a capture — or keep the capture's address push (and document it)? Rows beside
simd_pointer_param.sh R5 / Y12 (`sp_vrows`' captured `*V` row is the `*pv` side, unaffected).
