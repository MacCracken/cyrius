# A body ending in an infinite loop whose only exits are `ret2(..);` statements is not counted: `var a, b, c = g2(1);` binds a stale register — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 receives lane (unit R5) while landing D42
(issues/archived/2026-10-15-ret2-body-not-counted-three-names-read-stale-register.md, commit b773a56a: `ret2(a, b)` is two
values to pass 1's count). Measured with the lane tip (l6714-receives at 9245e108) on x86_64; the count is shared
frontend state, so every target.
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a silent wrong value on code that compiles clean (the third name reads whatever an earlier call
left in the third return register: 88 seeded), on a rare shape: a `ret2` exit inside a `loop { }` / `while (1) { }`
/ `do { } while (1);` that ends the body.
**Kind:** language — the reach of D42 (the user's decision, 2026-10-16: "the 3-name bind and the 3-tuple capture of a
fn left only through `ret2(..);` / `return ret2(..);` / `return (a, b);` stop compiling"). The filed shapes (a
final `ret2(..);`, `return ret2(..);`, an if / else of them) are counted since b773a56a; this one is outside the
filed table, so it was filed rather than widened.

## Reproduction

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn g2(x) { loop { if (x > 0) { ret2(1, 2); } x = x + 1; } }
fn main(): i64 { var x, y, w = h(); var a, b, c = g2(1); return c; }
syscall(60, main());
```

```
$ build/cycc < lp.cyr > lp && ./lp ; echo $?
88          (compiles clean; the third name read the seeded r8)
```

The same body with `return (1, 2);` in place of `ret2(1, 2);` is refused (6.7.11's loop-ending count):

```
error:<source>:3:51: multi-value destructure binds 3 names, but 'g2' returns 2 values - bind 2 names: `var a, b = f(..);`
```

## Root cause

`_prescan_ret_arity` (src/frontend/parse_fn.cyr) now counts every `ret2(..);` statement as a two-value exit, and its
end check `_ar_exits` accepts a body ending in `return`, in an infinite loop (both through `_body_ends_in_return`),
in `ret2(..);`, or in an if / elif / else of those. The loop arm is `_body_ends_in_loop` → `_loop_exits_by_return`,
which proves the loop is left only through an exit by finding a `return` TOKEN (33) inside it and no `break`; a
loop whose exits are `ret2(..);` statements has no `return` token, so it is "not provably left" and nothing is
recorded.

## Proposed fix

`_loop_exits_by_return` also counts a `ret2(..);` statement (`_ret2_stmt`) as an exit. Its other caller,
`_prescan_ret_single`, bails on any `ret2` token before its end check, so nothing else changes. Rows beside
destructure_one_value_refused.sh axis 7: the repro above (refused), `while (1)` / `do { } while (1);` / `while (true)`
spellings, a loop a `break` leaves (still uncounted), on x86_64 / qemu / cxvm / wine.
