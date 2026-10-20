# `cyrius lint` (`--syntax-only`) passes an impl whose return differs from a trait member's `: u8` / enum / `*Pt<i64>` return — OPEN

**Status:** 🟡 **OPEN** — raised 2026-10-20 by the 6.7.16 gensig review (file_as_issue 1) and measured by the lane's
review-fix step on the lane head 7f3d2260d against the lane's base b73e8d5fe (x86_64; frontend only, so every
target is the same).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig review, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low. A full compile still refuses every program below. Lint passes them.
**Kind:** tooling / diagnostics. What lint should report here is the user's call.

## Reproduction

```cyrius
struct P { a; b; }
trait T2 { fn sh(self): u8; }
impl T2 for P { fn sh(self): i64 { return 1; } }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
fn main(): i64 { return 0; }
```

```
$ cycc --syntax-only < dd2.cyr          # lane base b73e8d5fe
error:<source>:3:30: 'P.sh' returns i64, trait 'T2' declares u8      (rc 1)
$ cycc --syntax-only < dd2.cyr          # lane head 7f3d2260d
                                                                      (rc 0, no line)
$ cycc < dd2.cyr                        # lane head, full compile
error:<source>:2:25: type 'u8' cannot be a fn return type            (rc 1)
```

The review's other probes behave the same way: the base's lint line and the head's silence (rc 0).

| probe | member | impl | base `--syntax-only` |
|---|---|---|---|
| dd1 | `: u8` | none | `4:20: 'P.sh' returns i64, trait 'T2' declares u8` |
| dd3 | `: *Pt<i64>` | `: *Pt` | `5:30: 'P.sh' returns *Pt, trait 'T2' declares *Pt<i64>` |
| dd4 | `: Color` (an enum) | `: i64` | `4:30: 'P.sh' returns i64, trait 'T2' declares Color` |

The probes are in /home/macro/.cache/c6/s6716/gensig/review/rev/p/ (dd1-dd4).

## Root cause

6.7.16's D9 (a member's `: u8`..`: u64`, `: f32` or enum return) and D7 (a member's `Pt<i64>` / `*Pt<i64>`) refuse at
the member. That refusal is silent under `--syntax-only`, as decided: a fn's own `: u8` return is silent there too,
because lint resolves no names. `_tr_rt_bad` (src/frontend/parse_fn.cyr) answers "the reader refuses this side" for
those shapes (its `_tr_rt_nonret` head arm and the `_ngt_tail` arm in `_ty_rd_scan`) whether or not the reader
reported anything. So `_tr_ret_differs` stands down, and the impl's "returns .., trait declares .." line, which lint
printed before, is suppressed. Nothing else reports.

The review-fix step's D5 arm (`_ta_over`, a generic struct given too many type arguments) is counted only when
`_syntax_only == 0`. D5's refusal is silent under lint too, so lint keeps the impl's line for that shape
(traits_checked.sh TRR6). The D9 and D7 arms are not guarded that way.

## Fix direction

The user decides what lint reports for these programs. If lint should keep the impl's line, count the member-side D9
names and the `_ngt_tail` shapes in `_tr_rt_bad` only when `_syntax_only == 0`, as the D5 arm already does. Then
traits_checked.sh TM3 / TM3b (lint is silent on the member alone) still hold, and a new row pins dd2's lint line.
