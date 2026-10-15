# `await f` keeps its operand's pointer step: with `f: *i32`, `(await f) + 1` adds 4 — RESOLVED

> ✅ **RESOLVED in v6.7.11** (GF-16: the force call (`_await_force`) and a coroutine's suspend landing reset the pointer step, so the value of `await f` is an untyped word. The filed repro exits 6 (it was 9) on x86_64 and qemu-aarch64, and inside a coroutine on x86_64 (aarch64 refuses a mid-body suspend by name, so that row cannot run there); `((await f) + 1) - q32` with `f: *u8` is `n - p`; the untyped control is unchanged. No new decision: 6.7.9's decision 1(a). Rows: `frontend/pointer_subscript_checked.sh` AW1-AW4d, AWc1-AWc3. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reported by the 6.7.9 critical lane (bite 5, the pointer-step reset) as a site it did not
sweep. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B): the repro exits 9
on x86_64 and on aarch64 (qemu) where 6 is right, and the same `(await f) + 1` inside a coroutine (an `async fn`
driven to completion by `future_force` / `future_pending`) gives 9 where its untyped control gives 6; the installed
6.7.8 compiler exits 9 too.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *The releases after 6.7.8*; a parser defect, the last arm of 6.7.9's
pointer-step reset — the class the user approved as 6.7.9's decision 1(a), "the pointer step resets after every
operator that does not produce a pointer", so no new ask) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 5, which reset the step after `== & | ^ * / % << >> - ~` and a
call result's untyped field, but not after `await`.
**Severity:** Low — a silent wrong value, but only when a Future handle is held in a TYPED pointer (lib/async's
handles are untyped words, so `var f = mk();` is right; `var f: *T = mk();` warns "assigning non-pointer to typed
pointer" at the declaration).
**Affects:** cycc 6.6.17 (the typed pointer step on locals) – 6.7.9, every target (frontend state).

## Summary

`await e` lowers to `future_force(e)` (outside a coroutine, `parse_expr.cyr:5306-5318`) or to a suspend whose landing
yields the value (inside one, `_await_coro_suspend`). Neither path resets the pointer-scale word the operand factor
left, so the awaited VALUE carries the Future pointer's step into the next operator: `(await f) + 1` scales the `1` by
`sizeof(T)`. Every other producer of a non-pointer value resets it since 6.7.9 (`_pexpr_bit_ps`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/async.cyr"
async fn five(): i64 { return 5; }
fn main(): i64 {
    alloc_init();
    var f: *i32 = five();
    var r = (await f) + 1;
    return r;
}
syscall(60, main());
```

```sh
CYRIUS_ASYNC=1 build/cycc < repro.cyr > /tmp/aw && chmod +x /tmp/aw && /tmp/aw; echo $?
# actual: 9 (5 + 1 * sizeof(i32)) · expected: 6 — what `var f = five();` (untyped) gives
```

## Root cause

The `await` factor arm (`src/frontend/parse_expr.cyr:5268`, typ 135) parses the operand with `PARSE_FACTOR` and then
emits the force call (or `_await_coro_suspend`) without `SPSC(S, 0)`; the call it emits is not a parsed call, so
`_call_scale_fix` never runs either.

## Proposed fix

`SPSC(S, 0)` after the force call and after `_await_coro_suspend` (both arms), as the unary `-` / `~` arms do (and no
pointer-kind stamp: the value is an untyped word). Rows in the 6.7.9 pointer-step gate: `(await f) + 1` with `f: *i32`
and `f: *u8` outside and inside a coroutine, x86_64 and qemu-aarch64; the untyped `var f = five();` control unchanged.
