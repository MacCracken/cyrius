# The mixed-return warning ("returns a `: stack` pair on another path but a SINGLE value here") never judges an impl method or an inherited trait default — RESOLVED

> ✅ **RESOLVED in v6.7.15** (RC-8, `d5adfcd2a` — no decision needed (a diagnostic gap; "one warning, not one per impl" is the filed proposal; no binary changes). `_warn_mixed_pair_returns` (src/frontend/parse.cyr) factors its per-fn walk into `_warn_mixed_body` and then judges each `impl` method (`_impl_method_entry`, read only; `_pbs_iself` for an untyped `self`) and each inherited trait default not overridden, deduplicated by the default's `fn` token. The filed method repro, silent through 6.7.14 (exit 50), now warns once at 3:64 naming `Pt.qm`; the `?`-only method warns (4:49); a default inherited by two impls warns once (2:65); exits unchanged; the same from the aarch64, cx, PE and Mach-O compilers; cycc's source and the corpus warn nothing new. Rows: `frontend/stack_enum_mixed_return_warning.sh` im_repro (verbatim), im_free (the free-fn twin verbatim), im_q, im_variant, im_default2, im_override, im_override_ok, im_generic, im_iself, im_annot, im_closure; mutations RED. Filed from the review (6.7.16): the inherited default's warning names the first impl, `Pt.qd`, not the trait (`2026-10-18-mixed-return-warning-trait-default-names-first-impl.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 receives lane (unit R5) while adding the `?` route to
`_pair_body_scan` (issues/archived/2026-10-15-pair-fn-through-question-mark-used-above-its-definition-not-flagged.md): the
impl-method rows of that fix (stack_enum_lossy_context.sh axis QF7 / QF8) compiled with NO warning where the same
body as a free fn warns. Measured with the lane tip (l6714-receives at 9245e108) on x86_64; the warning is shared
frontend state, so every target.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
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
