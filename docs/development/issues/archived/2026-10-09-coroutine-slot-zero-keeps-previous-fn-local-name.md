# A coroutine's reserved slot 0 keeps the previous fn's parameter name — a global of that name reads the frame address, and a local of that name is a "duplicate variable" — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 15, l679-crit; CHANGELOG [6.7.9]) `_coro_slot0_reserve` (parse_fn.cyr) reserves slot 0 as an anonymous slot — name -1, depth word and type 0 — instead of `SFLC(S, 1)` alone: repro 1 exits 5 (was 99) and repro 2 compiles and exits 3, on x86_64 and PE (wine). Gate rows N1–N3 in `frontend/coroutine_fnptr_and_completion.sh` (PE N1, N2 too), each reset mutation-proven; the corpus differential is all-identical.

**Status:** ✅ **RESOLVED in v6.7.9**. See the banner above and *Resolution* below. Reproduced on the 6.7.9 lane tip
@ ca097350 before the fix: repro 1 exits 99, repro 2 is refused at 11:14. As filed: 🟡 OPEN — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B, `CYRIUS_ASYNC=1`) on x86_64. Repro 1 compiles clean and exits 99, which means the global `a` read as a
heap address; 5 is right. Repro 2 is refused with `error:<source>:11:14: duplicate variable`; it is valid and exits 3
once the trigger is removed. Each turns correct when the previous fn's parameter 0 is renamed, when another fn is
defined between the two, or when the body has no `await`. Same results on the 6.7.6 tag, 6.7.0, 6.6.10, 6.6.9, 6.6.5,
6.6.4 and 6.6.0.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
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

## Resolution (6.7.9, the critical lane's bite 15)

- **The fix, as proposed, in a helper.** `_coro_slot0_reserve` (`src/frontend/parse_fn.cyr`, beside
  `_fn_body_has_await_ahead`) writes slot 0's name as -1, its depth word (with the flag bits 32–63) and its type as 0,
  then `SFLC(S, 1)`. The fn-definition path calls it in place of `SFLC(S, 1)`, so that giant fn gains no reference.
  The slice width needs no write: it is trusted only behind the depth word's bit 62. The float flag needs none either:
  SFLC clears it.
- **The other per-slot tables were the same class, and observable.** The stale depth word and type reached
  `_inl_param_why`, which walks the parameter slots from 0. A `#inline` coroutine after `fn m(p: *i64)` was warned
  `#inline ignored: pointer (*T) parameter`, and one after `fn m2(s: Str)` was warned `struct/aggregate parameter`,
  though it has neither (row N3).
- **Rows** (`tests/gates/frontend/coroutine_fnptr_and_completion.sh`, N1–N3): N1 reads a global named like the
  previous fn's parameter 0 (the filing's repro 1, 5 not 99). It reads one named like a parameterless fn's first
  `var` (42 not 99), and writes one: 6 and 6, where the write landed on SELF before and left 0 and 5. A renamed
  parameter is the control. N2 is the filing's repro 2 (3) and a local declared after an await (42). N3 is the
  `#inline` warning. N1 and N2 also run on PE (wine). Before the fix the gate is red on N1, N2, N3, PE N1 and PE N2.
- **Mutation-proven** from scratch copies of src: dropping the name reset reddens N1, N2, PE N1 and PE N2. Dropping
  SLDEP reddens N3 (the pointer reason), and dropping SLTYPE reddens N3 (the struct reason).
- **Differential**: every `.tcyr` and `tests/fixtures/async/*.cyr` (569 sources), compiled with `CYRIUS_ASYNC=1` by the
  pre-fix and the fixed stage-1 compilers, is byte-identical. No corpus coroutine follows a fn whose local 0 it names.
  Rows N cover that shape.
- **Hosts**: the fix is in the frontend and the same on every coroutine target. x86 Mach-O runs at the release gate's
  ach leg.
- **Not this filing**: `#inline` on an `async fn` (a coroutine or a plain Future) is silently a no-op, because the body
  is reached only through `future_force`'s fn pointer. It is filed as
  `2026-10-11-inline-on-async-fn-silently-ignored.md`.
