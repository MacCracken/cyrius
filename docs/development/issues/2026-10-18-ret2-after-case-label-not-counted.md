# A `ret2(..);` right after a `case N:` / `default:` label is not counted as a two-value exit: `var a, b, c = g2(1);` binds a stale register — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R1) while landing
issues/archived/2026-10-17-ret2-only-exits-in-a-loop-ending-body-not-counted.md (a body ending in an infinite loop whose
exits are `ret2(..);` statements). That fix counts a `ret2(..);` statement inside the loop, a nested while and a
switch's case BLOCK (`case 1: { ret2(1, 2); }`); a `ret2(..);` written directly after the label is outside its filed
surface and was filed rather than widened. Measured with the slot-open compiler (4862a462e's build/cycc) and the
lane after R1 (140fd4c3e): identical, on x86_64; the count is shared frontend state, so every target.
**Placement:** 6.7.16 — Break 2, repair 6 (receives lane, wave 3, unit R3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a silent wrong value on code that compiles clean (the third name reads whatever an earlier call
left in the third return register: 88 seeded), on a rare shape: a fn whose two-value exits include a `ret2(..);`
right after a `case` / `default` label, bound to three names or captured into a 3-tuple.
**Kind:** language — the reach of 6.7.14's D42 (the user's decision of 2026-10-16: "the 3-name bind and the 3-tuple
capture of a fn left only through `ret2(..);` / `return ret2(..);` / `return (a, b);` stop compiling"; kept by
6.7.15's D62). The same body with `return (1, 2);` after the label is refused today.

## Reproduction

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn g2(x) { switch (x) { case 1: ret2(1, 2); default: x = 1; } ret2(3, 4); }
fn main(): i64 { var x, y, w = h(); var a, b, c = g2(1); return c; }
syscall(60, main());
```

```
$ build/cycc < cs.cyr > cs && ./cs ; echo $?
88          (compiles clean, no diagnostic; the third name read the seeded r8)
```

The same body with `return (1, 2);` after the label (and `return (3, 4);` at its end) is refused:

```
error:<source>:3:51: multi-value destructure binds 3 names, but 'g2' returns 2 values - bind 2 names: `var a, b = f(..);`
```

Also 88, rc 0, no diagnostic: `default: ret2(1, 2);` (with `ret2(3, 4);` ending the body), and inside a loop-ending
body, `fn g2(x) { loop { switch (x) { case 1: ret2(1, 2); default: x = 1; } } }`. With the case's statement in a
block, `case 1: { ret2(1, 2); }`, it is refused (the R1 fix's r2_loop_switch row).

## Root cause

`_ret2_stmt` (src/frontend/parse_fn.cyr) decides a `ret2` is a whole statement by the token before it: `;`, `{` or
`}`. After a case label the token before is the label's `:`, so the `ret2` reads as one inside an expression, and
`_prescan_ret_arity`'s walk bails (`if (_ret2_stmt(S, j) == 0) { return 0; }`): nothing is recorded, and the
destructure's count check has no count to compare.

## Proposed fix

`_ret2_stmt` also accepts a `ret2` whose previous token is a case / default label's `:` (the `:` that closes a
`case <expr>:` or `default:` inside a switch body; a `:` elsewhere — a type annotation, a named argument — is not a
statement start). Rows beside destructure_one_value_refused.sh axis 7: the repro (refused), `default: ret2(..);`, the
loop-ending switch, and a two-name bind of the repro's fn running (1, 2) on x86_64 / qemu / cxvm / wine.
