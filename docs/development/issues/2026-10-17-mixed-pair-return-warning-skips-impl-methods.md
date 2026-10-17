# The mixed-return warning ("returns a `: stack` pair on another path but a SINGLE value here") never judges an impl method or an inherited trait default — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 receives lane (unit R5) while adding the `?` route to
`_pair_body_scan` (issues/2026-10-15-pair-fn-through-question-mark-used-above-its-definition-not-flagged.md): the
impl-method rows of that fix (stack_enum_lossy_context.sh axis QF7 / QF8) compiled with NO warning where the same
body as a free fn warns. Measured with the lane tip (l6714-receives at 9245e108) on x86_64; the warning is shared
frontend state, so every target.
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — a silent wrong value on code that compiles clean: a method that returns a `: stack` pair on
one path and a plain value on another hands its caller that value AS THE TAG and a stale payload, the exact
dropped-tag class the v6.6.0 warning exists for (19 real defects in one stdlib, CHANGELOG [6.6.12]); for a free fn
the compiler says so, for a method it says nothing.
**Kind:** a diagnostic gap (a warning, not a refusal — no semantics change).

## Reproduction

```cyrius
include "lib/result.cyr"
struct Pt { x; y; }
impl Pt { fn qm(self) { if (self.x > 0) { return Ok(self.x); } return 5; } }
fn main(): i64 { var p = Pt { 0, 0 }; var t, v = p.qm(); return t * 10 + v; }
syscall(60, main());
```

```
$ build/cycc < mw3.cyr > mw3 ; echo $? ; ./mw3 ; echo $?
0                      (no warning)
50                     (t = 5: the plain `return 5;` read as the TAG; v stale)
```

The same body as a free fn warns:

```cyrius
include "lib/result.cyr"
fn qm(x) { if (x > 0) { return Ok(x); } return 5; }
fn main(): i64 { var t, v = qm(3); return t * 10 + v; }
syscall(60, main());
```

```
warning:<source>:2:41: `qm` returns a `: stack` pair on another path but a SINGLE value here — the tag is dropped, so the caller reads this value as its TAG. …
```

A method whose only pair route is a `?` (`impl Pt { fn qm(self) { var v = parse(self.x)?; return v; } }`) is
silent too; the free fn `fn qb(x) { var v = parse(x)?; return v; }` warns.

## Root cause

`_warn_mixed_pair_returns` (src/frontend/parse.cyr) walks depth-0 `fn` tokens only (`if (d == 0)` on `t0 == 32`),
plus every closure body (`_warn_closure_block`). An impl method is a `fn` at depth 1 inside `impl T { .. }`, and an
inherited trait default has no `fn` in the impl at all — so neither is ever judged, though both are flagged 256 by
`_pair_prescan_impls` / pass 2. The 6.7.11 / 6.7.13 fixes that taught the pair PRESCAN about impl methods
(`_pair_scan_method`, `_pair_scan_defaults`, `_impl_method_entry`) never reached this warning pass.

## Proposed fix

Judge each impl method (and each inherited default, under the impl's entry) as a top-level fn is: resolve its entry
the way `_pair_scan_method` does (`_impl_method_entry`, read only — never REGFN, the axis-13 rule), and when its flag
has 256, warn at its first plain `return` (`_ret_is_variant`, with the method's unit for name resolution and
`_pbs_iself` for an untyped `self`). Rows: the two repros above (one warning each, at the plain return), a method
returning a variant on every path (silent), a trait default inherited by two impls (one warning, not one per impl —
or the user decides), on x86_64 (the warning is frontend state).
