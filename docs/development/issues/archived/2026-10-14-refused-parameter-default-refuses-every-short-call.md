# A refused parameter default drops every default of its fn — each call that relies on one is refused again — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-5, no decision needed (a diagnostic cascade on refused input): a refused default keeps its row's minimum (`_pd_refuse_row`). D11 / D13's whole-list refusals set the minimum to the parameters before the first `=` (`_pd_record_at`), and D15 (defined twice) sets min = max itself. So a call that leaves a refused default, or a valid one after it, is not refused a second time by arity. All six filed inputs now give one error each, at the default: the three value refusals and the three D13 shapes (one default, two, `#inline`, its own warning kept). They gave 2, 3, 2, 2, 2 and 2 lines. D15 keeps its arity line, and a call over the maximum is still refused ("expects 0 to 3 arguments"). Rows: `frontend/default_named_args_checked.sh` RD1 – RD8 (RD1 – RD3 the filed inputs verbatim, RD4 – RD6 the addendum's D13 inputs, RD6b, RD7, RD8); mutations MRD1 – MRD3 RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, unit R5) with
`build/cycc < f.cyr` from the tree root, x86_64.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Low — every input is invalid and is refused at the default; the extra lines are a cascade, one per call.
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R5), while repairing shape 9 of
`2026-10-09-refusal-cascades-tuples-pairs-u128-d19.md` (a refused parameter TYPE dropped the fn's defaults; since
unit R5 such a default is kept). The same cascade follows a refusal of the default VALUE, which is outside that
shape's filed surface.

## Reproduction

```cyr
fn f(s: bool = 5): i64 { return 7; }
fn main(): i64 { return f(); }
syscall(60, main());
```
```
error:<source>:1:16: parameter 's' of 'f' is ': bool': its default must be a bool
error:<source>:2: 'f' expects 1 argument, got 0
```

A valid default after the refused one is lost with it, and each short call is refused again:
```cyr
fn f(a, b: bool = 5, c = 3): i64 { return a + c; }
fn main(): i64 { return f(1) + f(1, true); }
syscall(60, main());
```
```
error:<source>:1:19: parameter 'b' of 'f' is ': bool': its default must be a bool
error:<source>:2: 'f' expects 3 arguments, got 1
error:<source>:2: 'f' expects 3 arguments, got 2
```

A default on a type that takes none (D9) does the same:
```cyr
struct Pt { x; y; }
fn f(a, p: Pt = 0): i64 { return a; }
fn main(): i64 { return f(1); }
syscall(60, main());
```
```
error:<source>:2:17: parameter 'p' of 'f' is a struct: it takes no default
error:<source>:3: 'f' expects 2 arguments, got 1
```

## Addendum (the 6.7.11 returns review, 2026-10-14): a D13-refused trait method's direct call

The same cascade follows D13 — a default on a method that implements a trait. The refusal drops the row's
defaults (`_pd_refuse_row(row, 1)`), so a direct call that relies on one is refused a second time, by arity:

```cyr
struct P { a; b; }
trait Tr { fn m(self, b); }
impl Tr for P { fn m(self, b, k = 1): i64 { return k; } }
fn main(): i64 { var p = P { 1, 2 }; return p.m(5); }
syscall(60, main());
```
```
error:<source>:3:33: 'm' implements trait 'Tr': its parameters take no defaults (the trait's signature is the contract)
    impl Tr for P { fn m(self, b, k = 1): i64 { return k; } }
                                    ^
error:<source>:4: 'P_m' expects 3 arguments, got 2
```

The same with `#inline fn m(self, b, k = 1)` (plus its own "#inline ignored" warning) and with two defaults
(`fn m(self, b, k = 1, j = 2)`: "'P_m' expects 4 arguments, got 2"). Measured on the lane tip (4288c67f + the
review's doc fix); on the base 0f733aea a third line ("method 'm' takes a different number of parameters than its
declaration in trait 'Tr'") sat between them — the 6.7.11 returns lane's R5 removed only that trait-arity line
(`_tr_dflt_extra`). Same class as D7 / D9 above; the fix below covers it (rows: the three D13 inputs, one error
each, at the default).

## Root cause

`_pd_value` (src/frontend/parse_fn.cyr) answers a refused default (`_pd_eval` returning 0: D2, D3, D6-D9, D16, D20)
with `_pd_refuse_row(row, 0)`, which sets the row's min to its max: every parameter becomes required, so the arity
check (`_CHECK_ARITY`) refuses each call that omits one — the refused default's and every valid one after it.

## Fix

A refused default stays "filled" for the arity check — its calls are not judged short for it (the default's refusal
already stopped the build) — or the row keeps its min and its calls skip the count. One error per input. Rows: the
three inputs above in `tests/gates/frontend/default_named_args_checked.sh`, each with exactly one error, at the
default.
