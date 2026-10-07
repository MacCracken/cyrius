# A tail call earlier in a loop body than the statement that takes a frame address keeps its `jmp` — OPEN

**Status:** 🟡 **OPEN** — the fix costs tail calls inside loops; which ones is a design choice (below).
**Placement:** unpinned — for integration to pin (6.6.x closeout or the 6.7.x line).
**Discovered:** 2026-10-07, review of lane s-ret (6.6.20 closeout, RPF-03).
**Severity:** Critical by this directory's guide (a silent wrong value from valid code), narrow in shape.
**Affects:** cycc 6.5.14 → 6.6.20 (every backend; measured x86 and aarch64-under-qemu).

## Summary

`_fn_local_addr` (src/frontend/parse.cyr) is the escape flag a tail call consults: once the fn
has put an address in its own frame into a value, `_tc_frame_divert` sends every later
`return f(..);` down the normal call path. The flag is set **so far** — at the moment the parser
reaches the `&` — so a `return f(..);` that comes EARLIER in a loop body than the statement taking
the address keeps its `jmp`, and on the next iteration it hands the callee a pointer into the frame
the `jmp` just freed. Silent wrong value, exit 0.

6.6.20 (lane s-ret) closed this for a callee with an ADDRESS-PASSED parameter (a struct over 8 B as
`p: T`, a struct of ANY size as `p: *T`, a Win64 vector): inside any loop such a call always
diverts, as on 6.6.19. It is still open for every other callee.

⚠ The `*T` at 8 B or less is new in that list: lane s-ptr (RPF-04, same release) made such a
parameter address-passed, so the integrated compiler diverts a tail call to it inside a loop, which
6.6.19 kept. Measured at integration: a 1,000,000-deep `while (1) { if (n == 0) { return acc; }
return walk1(p, n - 1, acc + p.v); }` with `p: *S1` (8 B) exits 64 on 6.6.19 and 139 (x86 /
aarch64; a stack overflow under wine) on 6.6.20; outside a loop it runs in constant stack on both.
Option (a) below would make every callee pay that price; until it is chosen, this one shape is the
documented cost (CHANGELOG [6.6.20], RPF-03).

## Reproduction

```cyrius
struct P3 { a; b; c; }
fn rd(p, k) {
    var j1 = 901; var j2 = 902; var j3 = 903; var j4 = 904; var j5 = 905; var j6 = 906;
    return load64(p) + load64(p + 8) + load64(p + 16) + k + (j1 + j2 + j3 + j4 + j5 + j6) - 5421;
}
fn f(k) {
    var s = P3 { 1, 2, 3 };
    var x = 0;
    var i = 0;
    while (i < 2) {
        if (i == 1) { return rd(x, k); }
        x = &s;
        i = i + 1;
    }
    return 0;
}
var rr = f(1); syscall(60, rr);
```

`build/cycc < lpu.cyr > p && ./p; echo $?` gives **5**; 7 is right (the non-tail twin
`var v = rd(x, k); return v;` gives 7). The same with `x = idp(s);` (an implicit `&s` pushed into a
`p: *P3` parameter, flagged since 6.6.20) in place of `x = &s;`.

## Root cause

The flag is a set-so-far question asked of a whole-body property. 6.6.7 fixed the identical defect
for `defer` by prescanning the body at its `{` (`_body_has_defer`). That is exact for `defer`
because the token says it all; it is not for a frame address, which since 6.6.20 is also created
WITHOUT a `&` — an inline aggregate argument, a struct call's or method's temp, a field of a frame
aggregate, a method's `self`, an operator's operand — and whether a token sequence does that depends
on types the prescan does not have (an operator on a struct value, a generic `T` local, a method
returning an aggregate).

Outside every loop the set-so-far answer IS the whole answer: the only backward jumps cyrius emits
are loop back-edges (a `defer` body and a coroutine already divert), so everything that can run
before a return outside a loop was parsed before it.

## Proposed fix (needs a choice)

- (a) Inside a loop, divert every tail call — exactly 6.6.20's rule for address-passed callees,
  widened to all. Sound, one line in `_tc_frame_divert`; costs TCO for every tail call inside a
  loop body (a state-machine `while (1) { .. return next(..); }` included). Measure cycc and the
  corpus before choosing it.
- (b) Inside a loop, divert when the OUTERMOST enclosing loop's token range contains a `&` or any
  construct that can push a frame address. Cheaper in TCO, but the construct list is the lexical
  enumeration that the 6.6.20 review showed to be the fragile part.
- (c) Two-pass: record per fn whether `_fn_local_addr` was ever set (a pass-1 shadow parse), and
  divert in a loop only for such fns. Exact, most work.

## Consumer-side workaround

Take the address before the loop, or write the call non-tail (`var v = f(..); return v;`).
