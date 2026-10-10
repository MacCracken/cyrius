# A closure made inside a suspending `async fn` captures a multi-word struct or tuple with its words reversed — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B, `CYRIUS_ASYNC=1`) on x86_64. The repro compiles clean and exits 91: the 2-word `P2 { 1, 2 }` read 12
and the 3-word `P3 { 1, 2, 3 }` read 123, where 21 and 321 are right (exit 73). A captured tuple `(1, 2)` reads 12 the
same way. With the `await` removed (no coroutine) the repro exits 73. A direct read of the struct in the coroutine
(no closure) is right, and so is a scalar capture. It does not matter whether the closure is made before or after
the `await`. Same results on the 6.7.6 tag, 6.7.0, 6.6.10 and 6.6.8; 6.6.0 – 6.6.7 crash (rc 139) on the same
source.
**Placement:** 6.7.12 — Break 2, repair 3, the frontend remainder (roadmap.md § *The releases after 6.7.7*) — placed
2026-10-09 — never 7.x. It is the closure-capture copy (`_cl_emit_cap_word`), the same code as the u128 capture fix
placed in that lane. Hosts: the three coroutine targets, x86_64 Linux, ach (x86 Mach-O) and cass (PE, wine first).
**Discovered:** 2026-10-09 by the 6.7.7 B4 (tuples) lane, bite T6 (`scratchpad/b4t6/as4.cyr`). Because of it, no B4
gate row pins a closure capture across an `await`.
**Severity:** High — a silent miscompile: a wrong value with no diagnostic.
**Affects:** cycc 6.6.8 – merged 6.7.7 (wrong value; measured 6.6.8, 6.6.10, 6.7.0, the 6.7.6 tag and the 6.7.7
tip). 6.6.0 – 6.6.7 crash on it instead. The tuple shape exists only from 6.7.7. x86 family only: coroutines are
refused on aarch64 and cx.

## Summary

A coroutine's locals live in its heap frame. The coroutine frame and the stack frame run in OPPOSITE directions.
On the stack a higher slot index is a lower address. In the coroutine object the offset ascends with the index.
6.6.5 made this work for aggregates with `_ECORO_AGG_OFF`, which bases a multi-word local at its lowest-index slot.
So the word ORDER inside the block is reversed relative to the stack, which its comment calls invisible:

> every consumer either addresses the block through this one base (field load/store, method self, by-value push,
> zero-fill, `&name`) or walks BOTH sides by slot index (`_try_aggregate_copy_assign`, `_try_struct_copy_init`), and
> a permutation applied identically to source and destination copies the same word to the same word.

(`src/backend/x86/emit.cyr:5182`–`5193`; merged-tree lines.)

The closure capture breaks that invariant. It walks the SOURCE by slot index (word `k` from slot `base - k`, the
stack layout) and writes the DESTINATION, the closure's heap env, by word offset (env word `k` = field `k`). On the
stack the two agree. In a coroutine, slot `base - k` holds field `n - 1 - k`, so the env receives the struct's
words in reverse.

## Reproduction

`docs/development/issues/repros/2026-10-09-coroutine-closure-capture-words-reversed.cyr`:

```cyrius
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
struct P2 { x; y; }
struct P3 { x; y; z; }
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
    var p = P2 { 1, 2 };
    var q = P3 { 1, 2, 3 };
    var s1 = await nopark();
    var c = || p.y * 10 + p.x;
    var d = || q.z * 100 + q.y * 10 + q.x;
    return fncall0(c) * 1000 + fncall0(d);
}
fn main(): i64 {
    alloc_init();
    var F = steps(0);
    var r = future_force(F);
    r = future_force(F);
    return r;
}
syscall(60, main());
```

```sh
cat docs/development/issues/repros/2026-10-09-coroutine-closure-capture-words-reversed.cyr | CYRIUS_ASYNC=1 build/cycc > /tmp/cc \
  && chmod +x /tmp/cc && /tmp/cc; echo $?
# actual:   91  (12 * 1000 + 123 = 12123; & 255)
# expected: 73  (21 * 1000 + 321 = 21321; & 255) — what the same file gives with the `await` line removed
```

The tuple shape: `var t = (1, 2); var s1 = await nopark(); var c = || t.1 * 10 + t.0; return fncall0(c);` gives 12
where 21 is right.

## Root cause

`_cl_emit_cap_word` (`src/frontend/parse_expr.cyr:553`; merged-tree lines) copies capture word `k` of an enclosing
local:

```cyrius
if (base < nl) { EFLLOAD(S, base - k); return 0; }
```

That is the slot `base - k`. `EFLLOAD` of a coroutine slot is `[r11 + _ECORO_OFF(slot)]` (ascending), so for a
2-word local named at slot `base`, `k = 0` reads slot `base`, which holds field 1 in the coroutine layout, and `k = 1`
reads slot `base - 1`, field 0. The read inside the closure takes env word `k` as field `k`, so the order flips. A
capture of an enclosing closure's capture (`base >= nl`) reads the env by word offset and is unaffected.

## Proposed fix

Read a multi-word local's words through its base address, as every other consumer of a coroutine aggregate does:
`EFLADDR(S, base)`, then `EADDRA_IMM(S, k * 8)`, then `ELOAD64(S)`. On the stack, `&base + k * 8` is slot `base - k`,
so the bytes are unchanged there. Do it either only when `_ECORO_SLOT(S, base)` is set, which keeps the stack path
byte-identical, or always if the differential corpus shows no change. Check the u128 capture (two words, the same
copy) against the same layout when the u128 capture issue's fix lands in the same lane.

Gate (x86_64, plus ach and cass): the repro's three shapes (2-word, 3-word, tuple), with the closure before and after
the `await`. Add a mutation that restores the slot walk. Then the B4 gate can pin a tuple capture across an `await`.

## Consumer-side workaround

Inside a suspending `async fn`, capture the fields as scalars (`var px = p.x; var py = p.y; || py * 10 + px`), or
capture a pointer to the struct.
