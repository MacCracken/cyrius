# A coroutine's reserved slot 0 keeps the previous fn's parameter name — a global of that name reads the frame address, and a local of that name is a "duplicate variable" — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B, `CYRIUS_ASYNC=1`) on x86_64. Repro 1 compiles clean and exits 99, which means the global `a` read as a
heap address; 5 is right. Repro 2 is refused with `error:<source>:11:14: duplicate variable`; it is valid and exits 3
once the trigger is removed. Each turns correct when the previous fn's parameter 0 is renamed, when another fn is
defined between the two, or when the body has no `await`. Same results on the 6.7.6 tag, 6.7.0, 6.6.10, 6.6.9, 6.6.5,
6.6.4 and 6.6.0.
**Placement:** 6.7.12 — Break 2, repair 3, the frontend remainder (roadmap.md § *The releases after 6.7.7*) — placed
2026-10-09 — never 7.x. This is async coroutine setup in `parse_fn.cyr`, a frontend fix. It is the same stale-table
class as
[the top-level closure's stale capture](2026-10-09-toplevel-closure-captures-stale-fn-local.md) (6.7.10), so whichever
lane lands first should check the other site.
**Discovered:** 2026-10-09 by the 6.7.7 B4 (tuples) lane, bite T5. The lane met the refusal while writing a coroutine
gate row. The silent read (repro 1) was found while verifying this filing.
**Severity:** High — a silent miscompile. A coroutine reading a global gets the coroutine frame's address, with no
diagnostic. It also refuses a valid local, a hard failure with a workaround.
**Affects:** cycc 6.5.70 (the slot-0 reservation for multi-parameter coroutines) – merged 6.7.7. Measured 6.6.0 –
6.7.7. x86 family only: coroutines are refused on aarch64 and cx.

## Summary

A suspending `async fn` (a coroutine) keeps its frame base, SELF, in stack slot 0. Its parameters and locals live in
the heap frame from slot 1 up. The slot is reserved before the parameter loop with `SFLC(S, 1)`, which sets the local
COUNT to 1 but leaves slot 0's NAME entry as it was. The local tables are not cleared between fns. So slot 0 still
carries the name of the previous emitted fn's local 0: its first parameter, or its first `var` when it has no
parameters (both verified).

`FINDLOCAL` scans the slots by name, so inside the coroutine body that name resolves to slot 0:

1. **A read of a global with that name reads SELF** (repro 1). `var a = 5;` and `fn m2(a)` are followed by a
   coroutine that returns `a`. The coroutine returns the frame's heap address, silently.
2. **A local with that name is a duplicate** (repro 2). `var a = 3;` in the coroutine finds slot 0 named `a` and
   reports "duplicate variable".

Only the immediately preceding fn's slot 0 matters. `fn m2(b, a)` (index 1), or another fn in between, does not
trigger it. A plain `async fn` without an `await` is not a coroutine and is unaffected.

## Reproduction

`docs/development/issues/repros/2026-10-09-coroutine-slot-zero-stale-name-1-read.cyr`:

```cyrius
include "lib/alloc.cyr"
include "lib/async.cyr"
var a = 5;
fn nopark(): i64 { return 0; }
fn m2(a): i64 { return a; }
async fn steps(C): i64 {
    var s1 = await nopark();
    if (a > 65536) { return 99; }
    return a;
}
fn main(): i64 { alloc_init(); var F = steps(0); var r = future_force(F); r = future_force(F); return r; }
syscall(60, main());
```

`docs/development/issues/repros/2026-10-09-coroutine-slot-zero-stale-name-2-duplicate.cyr` has the same shape,
with `fn m2(a, b)` and a coroutine local `var a = 3;`.

```sh
for n in 1-read 2-duplicate; do
  cat docs/development/issues/repros/2026-10-09-coroutine-slot-zero-stale-name-$n.cyr | CYRIUS_ASYNC=1 build/cycc > /tmp/cz \
    && chmod +x /tmp/cz && /tmp/cz; echo "$n rc=$?"
done
# 1-read:      compiles clean, exit 99 (a > 65536: SELF's address); expected 5
# 2-duplicate: error:<source>:11:14: duplicate variable; expected exit 3
# both: rename m2's parameter (e.g. `fn m2(z)`) -> 5 and 3
```

## Root cause

`src/frontend/parse_fn.cyr:13846` (merged-tree lines), in the fn-definition path before the parameter loop:

```cyrius
if (_fn_body_has_await_ahead(S) == 1) { _pending_coro = 1; SFLC(S, 1); }
```

This reserves slot 0, but its name is never written. Every other anonymous slot is marked with
`S64(S + 0x5D9D000 + i * 8, 0 - 1)`, as the Future constructor does for its own slots
(`_async_emit_constructor`, `:12641` and `:12664`). `FINDLOCAL` (`:580`) skips a name entry `< 0` and matches any other.
SELF is homed into that slot at `:14409` (`ESTOREPARM(S, 0, _coro_base, 1)`). A stale name resolving to it reads the
frame pointer.

## Proposed fix

Mark slot 0 anonymous where it is reserved:

```cyrius
if (_fn_body_has_await_ahead(S) == 1) {
    _pending_coro = 1;
    S64(S + 0x5D9D000, 0 - 1);   # slot 0 is SELF: no name
    SLDEP(S, 0, 0);
    SFLC(S, 1);
}
```

Check the other per-slot tables for the same reset (type, slice width, span), since a stale type on slot 0 is the
same class.

Gate (x86_64, plus the x86 Mach-O and PE coroutine targets on ach / cass): both repros, plus the
renamed-parameter control. Add a mutation that drops the name reset.

## Consumer-side workaround

Do not name a coroutine's locals, or the globals it reads, like the first parameter of the fn defined just above
it. Or define the coroutine first.
