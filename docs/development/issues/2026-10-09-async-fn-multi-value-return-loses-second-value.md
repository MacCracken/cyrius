# An `async fn` declared `: (i64, i64)` compiles, and its Future carries only the first value — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc` 1,916,288
B, `CYRIUS_ASYNC=1`) on x86_64. `async fn g(): (i64, i64) { return (1, 2); }` compiles with no diagnostic, and `await
g()` yields 1. Both receives that would take the second value are refused: `var a, b = await g();` ("multi-value
destructure needs a call on the right-hand side") and `var t: (i64, i64) = await g();` ("cannot initialize tuple 't'
with a value that is not a tuple"). The documented `rethi()` read gets the second value only on the force that ran the
body. The repro forces once, calls another multi-value fn, forces again, and exits 19 where 12 is right. Same on the
6.7.6 tag, 6.7.0 and 6.6.10. Before 6.6.10's force-once memo every `await` re-ran the body, so the stale read did not
show (6.6.0, 6.6.4, 6.6.5 and 6.6.9 exit 12).
**Placement:** 6.7.12 — Break 2, repair 3, the frontend remainder (roadmap.md § *The releases after 6.7.7*) — placed
2026-10-09 — never 7.x. It is a refusal by name in the async lowering, in the lane that also refuses u128 returns by
name. The refusal stops a declaration that compiles today, so it is a one-line ask at 6.7.12's open (default: refuse).
**Discovered:** 2026-10-09 by the 6.7.7 B4 (tuples) lane, bite T5 (`return t;` of a tuple in an `async fn` is refused
there. A declared multi-value return is not).
**Severity:** High — a silent value loss. The declared second value is dropped with no diagnostic, and the one
spelling that reads it (`rethi()`) returns a stale register on a memoised or reactor-driven force.
**Affects:** cycc 6.5.21 (declared multi-value returns) – merged 6.7.7. Measured 6.6.0, 6.6.4, 6.6.5 and 6.6.9 (the
declaration compiles, the value is dropped by the Future; the `rethi()` read happened to be right), and 6.6.10, 6.7.0,
the 6.7.6 tag and the 6.7.7 tip (exit 19).

## Summary

An `async fn` hands its result back through ONE i64. `future_force` returns what the body left in `rax`, and a plain
Future memoises that one word (`lib/async.cyr:1403`, the `[done, value]` pair). Since 6.6.6 two return shapes are
refused at the declaration, naming the fn:

- a struct over 8 B, `rax:rdx` or a hidden retptr: "`async fn f` returns a struct by value, and a Future carries one
  i64 — return a pointer to it";
- a value-form vector.

A declared multi-value return `: (i64, i64)` / `: (i64, i64, i64)` is the same limit. Its values travel in
`rax:rdx[:r8]`, and the Future has no second word. It is not refused:

- `await g()` / `future_force(F)` yields the first value. The second is gone.
- Both receives that would take every value are refused: the destructure (`var a, b = await g();`), because `await`
  is not a call, and the tuple capture.
- The legacy `var b = rethi();` after `await` reads `rdx` at that moment. On the force that ran the body, that is
  the second value, by accident. On a memoised force (`await f` again), or after `async_run` / `task_join`, it is
  whatever the last call left there.

An undeclared `return (a, b);` and `return ret2(a, b);` in an `async fn` lose the second value the same way. The
6.7.7 tuple `return t;` from an `async fn` is already refused by name (B4 T5).

## Reproduction

`docs/development/issues/repros/2026-10-09-async-fn-multi-value-return.cyr`:

```cyrius
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
async fn g(): (i64, i64) { return (1, 2); }
fn h(): (i64, i64) { return (7, 9); }
fn main(): i64 {
    alloc_init();
    var f = g();
    var a0 = await f;
    var x, y = h();
    var a = await f;
    var b = rethi();
    return a * 10 + b;
}
syscall(60, main());
```

```sh
cat docs/development/issues/repros/2026-10-09-async-fn-multi-value-return.cyr | CYRIUS_ASYNC=1 build/cycc > /tmp/am \
  && chmod +x /tmp/am && /tmp/am; echo $?
# actual:   compiles clean, exit 19 (the second force returns the memoised 1; rethi() reads h's 9)
# expected: a compile error naming the multi-value return (as for a struct return), or 12
```

The same exit 19 follows under the reactor (`async_spawn_future(rt, g())`, `async_run(rt)`, an intervening
multi-value call, `task_join(rt, h)`, `rethi()`), with `g` a coroutine (one `await` in its body).

## Root cause

`_refuse_async_struct_return` (`src/frontend/parse_fn.cyr:5185`; merged-tree lines) keys on `_ret_agg_class`, which
answers only for a positive return struct id. `_refuse_async_vec_return` (`:5207`) keys on a vector descriptor. A
declared multi-value return records `MULTIRET_SID` (`0 - 40`, `src/frontend/parse_types.cyr:1053`), so neither
refusal fires. Both are called at `:14299`–`:14300`. Nothing in PARSE_RETURN refuses `return (a, b)` / `ret2` inside
an `async fn` body.

## Proposed fix

Default, one line at 6.7.12's open: refuse, as the struct and vector returns are refused.

- At the declaration, beside `:14299`: `GFRS(S, fi) == MULTIRET_SID` in an `async fn` gives "`async fn g` returns
  2 values, and a Future carries one i64 — return a pointer to a struct holding them".
- In the body: a `return (a, b);` or `return ret2(..);` in an undeclared `async fn`, refused by name in PARSE_RETURN's
  multi-value arm while `_is_async` is set.

The alternative is a feature, the user's call: a Future carries the extra values (more memo words), and `await g()`
becomes a multi-value source for the destructure and the tuple capture. That would need `lib/async.cyr`'s layout and
the four backends' `_async_step` to change in lockstep.

Gate: rows for the declared `: (i64, i64)` and `: (i64, i64, i64)`, the undeclared `return (a, b)` and `ret2`, in
both a plain and a coroutine `async fn`. Add a mutation per refusal.

## Consumer-side workaround

Return a pointer to a struct (or a heap block) holding both values, or split the fn into two `async fn`s.
