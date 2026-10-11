# `#inline` on an `async fn` is silently a no-op: no "#inline ignored" warning — OPEN

**Status:** 🟡 **OPEN**. Found 2026-10-11 while fixing
[`2026-10-09-coroutine-slot-zero-keeps-previous-fn-local-name.md`](2026-10-09-coroutine-slot-zero-keeps-previous-fn-local-name.md)
(6.7.9, the critical lane's bite 15). Its gate row N3 puts `#inline` on coroutines. Reproduced on that lane's tip and
with the installed 6.7.8 compiler (older installed compilers cannot compile the tree's current `lib/`). It was not fixed
in that bite: the fix adds a warning to builds that compile with no warning today, and it touches the fn-definition
path's inline classification, a separate site from the slot-0 reservation.
**Placement:** unpinned. For the user to place in the 6.x-line backlog.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 15 (the coroutine slot-0 reset).
**Severity:** Low. A diagnostic gap: no wrong value, and nothing is refused. It breaks v6.5.63's contract that an
ignored `#inline` says so ("a request that silently does nothing is that same defect with a token in front of it").
**Affects:** cycc 6.5.63 (`#inline`) – 6.7.9 crit tip. Measured on 6.7.8 and the 6.7.9 crit tip.

## Summary

The body of an `async fn` is compiled as `f$impl`. The user's name `f` becomes the Future constructor
(`_async_emit_constructor`, parse_fn.cyr), and the body is reached only through `future_force`'s fn pointer
(`fncallN`). No call ever names `f$impl`, so its inline replay can never run. The inline classification at the
fn's end still admits the body when nothing else disqualifies it, and it issues no warning. So `#inline` on
`async fn pl(x) { return x + 1; }`, or on a coroutine `async fn co(C) { return await nopark(); }`, does nothing
and says nothing. On a plain fn it cannot inline, the same directive is warned `#inline ignored: <reason>`.

Before 6.7.9 (bite 15), a coroutine could get a wrong reason instead: the previous fn's slot-0 flags or type made
`_inl_param_why` report a `*T` or struct parameter the coroutine does not have. That is fixed. The silent case below
is what remains.

## Reproduction

`docs/development/issues/repros/2026-10-11-inline-on-async-fn-silently-ignored.cyr`:

```cyrius
include "lib/alloc.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 7; }
#inline
async fn pl(x): i64 { return x + 1; }
#inline
async fn co(C): i64 { return await nopark(); }
#inline
fn sy(x): i64 { return x + 2; }
fn main(): i64 { alloc_init(); var F = pl(4); var r = future_force(F); var G = co(0); var q = future_force(G); q = future_force(G); return r + q + sy(1); }
syscall(60, main());
```

```sh
CYRIUS_ASYNC=1 build/cycc < docs/development/issues/repros/2026-10-11-inline-on-async-fn-silently-ignored.cyr > /tmp/ia \
  && chmod +x /tmp/ia && /tmp/ia; echo "rc=$?"
# Expected: a warning on `pl` and on `co` naming why (an async fn's body runs through its Future); rc=15.
# Actual:   no warning at all; rc=15.
```

## Root cause

`src/frontend/parse_fn.cyr`, the inline classification at the end of `_PARSE_FN_DEF_IMPL`
(`if (_INLINE_OK == 1 || _fn_inline_req == 1 || …)`) has a reason code for each disqualifier (1–7, warned at
`if (_inl_why == N) { WARN(S, "#inline ignored: …") }`), but none for an `async fn`. The fn being classified is
`f$impl`, which is never called by name.

## Proposed fix

When `_is_async == 1`, set `can_inline = 0` with a new reason (8) that is checked first, and warn
`#inline ignored: an async fn runs through its Future` when `_fn_inline_req == 1`. Keep it to two lines in that fn, or
route it through a helper: the fn is one of the giant fns that cybs compiles under per-fn reference ceilings, so
seed-derive must run. Gate: the repro's three fns. Each `async fn` is warned by name and the plain `sy` is not; with
the reason line dropped, the warnings disappear (the mutation). Note for the user: this adds a warning to builds that
compile with no warning today. It changes no exit code: cycc has no warnings-as-errors mode.

## Consumer-side workaround

None needed. `#inline` on an `async fn` can simply be removed: it has never had an effect.
