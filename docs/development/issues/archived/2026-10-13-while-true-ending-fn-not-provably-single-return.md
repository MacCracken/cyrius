# A fn ending in `while (true) { .. }` / `do { .. } while (true);` is not proved to return one value — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-16 (the user's decision D27, 2026-10-15: A, `true` counts as `1`, 6.7.11's D18): `_cond_is_one` accepts `( true )`, so a body ending in `while (true) { .. }` or `do { .. } while (true);` that no `break` leaves is proved to end in its returns. This holds for the one-value proof and for pass 1's arity record. Both filed repros bound a stale register (77 on x86_64, aarch64, cx and PE). Both are refused at 3:48 on all four: "multi-value destructure binds 2 names, but 'one' returns 1 value". A loop a `break` leaves stays silent, and an undeclared 2-value fn ending in such a loop has its count checked. Rows: `diagnostics/destructure_one_value_refused.sh` axis 3 (while_true_end / dowhile_true_end the repros verbatim, while_true_top, while_true_brk, dowhile_true_brk), axis 4 cnt_while_true, and `frontend/tuple_checked.sh` R16x-true; mutation (the `true` arm dropped) RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 returns lane (l6711-returns, after the loop-ending
repair) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): every repro below builds and exits 77, a stale register.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D27 — A.
**Severity:** Low — the same missed refusal 6.7.11 closed for `loop { }`, `while (1) { }` and `do { } while (1);`,
in the `true` spelling; conservative (a missed refusal, never a false one).
**Discovered:** 2026-10-13, the 6.7.11 returns lane (unit R1), while repairing
`2026-10-08-loop-ending-fn-not-provably-single-return.md`. The user's decision there named the three literal-`1`
shapes, so `true` was left out of that repair and is filed here.

## Reproduction

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn one(x) { while (true) { return x + 1; } }
fn main(): i64 { var x, y, w = h(); var a, b = one(1); return b; }
var r = main(); syscall(60, r);
```

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn one(x) { do { if (x > 0) { return x + 1; } x = x + 1; } while (true); }
fn main(): i64 { var x, y, w = h(); var a, b = one(1); return b; }
var r = main(); syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

| Repro | x86_64 | aarch64 (qemu) | cx | PE (wine) |
|---|---|---|---|---|
| `while (true) { return x + 1; }` | 77 | 77 | 77 | 77 |
| `do { .. } while (true);` | 77 | 77 | 77 | 77 |

Expected: `multi-value destructure binds 2 names, but 'one' returns 1 value - bind it to one name`, as for
`while (1) { return x + 1; }` (refused on the same compiler since the 6.7.11 repair). The undeclared-arity proof
(`_prescan_ret_arity`, which shares `_body_ends_in_return`) misses the same two spellings.

## Root cause

`_cond_is_one` (`src/frontend/parse_fn.cyr`, called by `_body_ends_in_loop`) accepts only the condition `( 1 )`: a
number token whose value is 1. `true` is token 169, so the loop is not recognised as infinite and
`_body_ends_in_return` answers 0.

## Proposed fix

Accept `( true )` (token 169) in `_cond_is_one`, and add `while (true)` / `do..while (true)` rows to
`tests/gates/diagnostics/destructure_one_value_refused.sh` axis 3 (and a capture row in `tuple_checked.sh` R16x).
It only adds refusals of programs that bind a stale register today.
