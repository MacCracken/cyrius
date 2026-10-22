# A suspending `async fn`'s narrow parameter holds the caller's word — D72 narrows every other parameter — OPEN

**Status:** 🟡 **OPEN** — narrowing it as D72 decided either refuses such a fn or makes a narrow coroutine-frame slot
compile; both change what compiles, so the s16 lane kept the word and stopped (its unit SS3's blocked item).
**Placement:** unplaced — filed at the 6.7.16 close (2026-10-21); the user places it — never 7.x.
**Discovered:** the s16 lane, unit SS3 (D72's bite, 179c315b1; the issue's filed surface, plain fns, is closed).
**Severity:** Medium — a silent wrong value: the parameter reads the caller's whole word.
**Kind:** decision.

## Summary

6.7.16's D72 narrows a narrow parameter in the fn (`wid(0x1FF)` with `y: u8` is 255; an `i16` `+= 1` wraps) — through fn
pointers, stack-passed parameters, `#inline`, captures, methods, defaults and a NON-suspending `async fn`. A SUSPENDING
`async fn` keeps its parameters in the coroutine frame, where a narrow slot is refused by name ("a sub-word local in an
`async fn` is not supported yet", pinned by closure_capture_narrow_scalar.sh A1), so the lane left its parameters
holding the caller's word (`_pnw_apply` skips `_pending_coro`; R7a pins the non-suspending fn narrowed).

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B), x86_64,
`CYRIUS_ASYNC=1`:

```cyrius
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
fn nopark(): i64 { return 0; }
async fn st(C, y: i16): i64 {
    var s1 = await nopark();
    y += 1;
    return y;
}
async fn st1(y: u8): i64 {
    var s1 = await nopark();
    return y;
}
async fn ns(y: u8): i64 { return y; }
fn sync16(y: i16): i64 { y += 1; return y; }
fn main(): i64 {
    alloc_init();
    var C = st(0, 0x17FFF);
    future_force(C);
    pr(future_force(C));
    var D = st1(0x1FF);
    future_force(D);
    pr(future_force(D));
    var E = ns(0x1FF);
    pr(future_force(E));
    pr(sync16(0x17FFF));
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var e = main();
syscall(60, 0);
```

Prints `98304 511 255 -32768`: the suspending `st` gives 98304 (D72's answer is -32768, as `sync16` gives) and `st1`
511 (D72: 255); the non-suspending `ns` is narrowed (255). A narrow LOCAL in such a fn is refused:

```cyrius
async fn st(C): i64 { var y: i16 = 5; var s1 = await nopark(); return y; }
```

```
error:<source>:5:37: a sub-word local in an `async fn` is not supported yet (its locals live in the coroutine frame)
```

## The decision

- (a) Refuse a narrow parameter in a suspending `async fn` by name, as its narrow local is ("a sub-word parameter in a
  suspending `async fn` is not supported yet") — `st` and `st1` stop compiling.
- (b) Add narrow coroutine-frame loads / stores (EFLLOAD_W / EFLSTORE_W's coroutine arms; the lane estimated a few
  hours on x86, with the other backends' arms) so the parameter is narrowed as D72 says: `st` gives -32768, `st1` 255 —
  which also makes the narrow LOCAL compile (A1's refusal goes), a change to what compiles.
- (c) Keep the word (today), and the guide names the exception.

## Acceptance

With (a) or (b): the repro gives the decided result on x86_64, aarch64, cx and PE (with (b): `-32768 255 255 -32768`),
under `CYRIUS_ASYNC=1`; a non-suspending `async fn` and every D72 path unchanged.
