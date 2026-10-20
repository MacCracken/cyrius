# Forming a dyn repeats the impl's own "takes a different number of parameters" refusal as "the parameter count differs" — OPEN

**Status:** 🟡 **OPEN** — met 2026-10-20 by the 6.7.16 gensig review-fix step, on the review's probe dd5. Measured on
the lane head 7f3d2260d and the lane's base b73e8d5fe (x86_64; frontend only): identical, so this is pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig review, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; f16 lane, wave 4, unit FG1) — never 7.x.
**Severity:** Low. Diagnostics only: the compile already fails on the impl's own refusal.
**Kind:** bug (diagnostics). This is the same class as 6.7.15's D4 hand-off for a return type. A difference the
impl's own check refuses, formed or not, is that check's error and not the forming site's.

## Reproduction

```cyrius
struct P { a; b; }
trait T2 { fn sh(self): f64; }
impl T2 for P { fn sh(self): f64 { return 1.0; } }
struct Q { a; }
impl T2 for Q { fn sh(self, k): f64 { return 1.0; } }
fn f(q: *Q): i64 { var o: dyn T2 = q; return 0; }
fn main(): i64 { return 0; }
```

```
error:<source>:5:17: method 'sh' takes a different number of parameters than its declaration in trait 'T2'
error:<source>:6:36: cannot form dyn T2 from Q - its method 'sh' does not match its declaration in trait T2: the parameter count differs
```

Without the `fn f` line, there is one line (5:17). (Probe: /home/macro/.cache/c6/s6716/gensig/review/rev/p/dd5.cyr.)

## Root cause

`_dyn_pair_chk` (src/frontend/parse_types.cyr) reports every code `_dyn_sig_eq` returns except the two it hands off:
code 4 (the return, through `_dyn_ret_hand` since 6.7.16) and, since 6.7.16, a parameter type its reader refuses.
Code 5 (the count) is also the impl check's own refusal (`_tr_check_impl`'s parameter-count arm, an ERR_IDENT), and
that check runs for every impl, formed or not.

## Fix direction

Hand code 5 to the impl check, as code 4 is. Read `_tr_check_impl` first: its ERR_IDENT arms return early, so a
count mismatch on a method AFTER one of those refusals is not reported by the impl. The site must not stand down for
a method the impl check never reached. One safe form is to stand down only when the impl check reported this method.
The rows for dyn_checked.sh are dd5 (exactly 5:17) and a control where the impl check returns early before the method.
