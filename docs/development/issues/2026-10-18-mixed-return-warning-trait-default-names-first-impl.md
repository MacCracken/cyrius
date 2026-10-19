# The mixed `: stack` pair / single-value return warning for a trait default inherited by several impls names the first impl (`Pt.qd`), not the trait — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 receives lane (d5adfcd2a, which made the
warning judge impl methods and inherited trait defaults); measured on the lane after its review fixes (x86_64; the
frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 receives review, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — wording only: the warning fires once, at the right line; the name points at an impl that holds
no code.
**Kind:** bug (diagnostic wording).

## Reproduction

```cyrius
include "lib/result.cyr"
trait Dv { fn qd(self) { if (self.x > 0) { return Ok(self.x); } return 5; } }
struct Pt { x; y; }
struct Qt { x; z; }
impl Dv for Pt { }
impl Dv for Qt { }
fn main(): i64 { var p = Pt { 0, 0 }; var q = Qt { 0, 0 }; var t, v = p.qd(); var u, w = q.qd(); return t * 10 + u; }
syscall(60, main());
```

```
warning:<source>:2:65: `Pt.qd` returns a `: stack` pair on another path but a SINGLE value here — the tag is dropped,
so the caller reads this value as its TAG. Return a variant of the same enum on this path: `Err(x)` for a Result,
`None()` for an Option.
(exit 55)
```

The code lives in the trait `Dv` (line 2), and `Qt` inherits the same defect; `Pt.qd` sends the reader to an empty
`impl Dv for Pt { }`. This is stack_enum_mixed_return_warning.sh's im_default2 shape.

## Root cause

`_warn_mixed_default` (src/frontend/parse.cyr) judges the default through the first impl that inherits it
(`_warn_mixed_method(S, ii, m, p)`, then `_wmd_seen` keeps the others quiet), and the warning names that impl's
entry (`_fn_src_name`).

## Fix direction

For an inherited default, name the trait (`Dv.qd`, or "the default `qd` of trait `Dv`"); an override keeps its own
impl's name. A row beside im_default2 pinning the name.
