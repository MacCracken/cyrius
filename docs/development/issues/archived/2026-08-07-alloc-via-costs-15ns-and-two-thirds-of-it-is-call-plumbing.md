# `alloc_via` costs 15.1 ns and roughly two-thirds of that is call plumbing, not allocation

**Status:** ✅ **SHIPPED v6.5.10** — Suggested fixes 1 and 2 both shipped: the four dispatch helpers read the vtable inline, and arena_allocator* registers &arena_alloc/&arena_reset instead of pass-through trampolines. Measured 15-16 -> 12 (inlining) -> 11 ns. Fix 3 (monomorphic fast path) NOT taken — the filing itself rates it not worth the design change, and 1+2 got most of it. Gate: tests/alloc_via_no_plumbing.sh.
**Filed as:** filed 2026-08-07.
**Filed as:** filed 2026-08-07 from agnosai, whose HTTP routes are fully
allocator-threaded and where `alloc_via` is now the single largest line item on
every request. Measured on live 6.5.9.
**Placement:** unpinned — 6.x-line backlog. No language surface, no API change;
the two cheapest fixes are edits to three functions in `lib/alloc.cyr`.
**Severity:** **Medium.** Nothing is incorrect. It is a straight tax on the
`_a`-threading pattern the stdlib spent 5.8.35–6.5.5 building out: the more
faithfully a consumer threads its allocator, the more it pays.
**Affects:** cycc 6.5.9 and earlier.

## Summary

`alloc_via(a, size)` on an arena costs **15.1 ns marginal**. `arena_alloc`'s
fast path is about eight instructions — align, load, add, compare, store — so
that number is not the bump. It is the **five-call chain** the bump sits at the
bottom of, three levels of which are pure plumbing:

```cyrius
fn alloc_via(a, size): i64 {
    return fncall2(allocator_alloc_fn(a), allocator_state(a), size);
}
```

- `allocator_alloc_fn(a)` — a call, to do `load64(a)`
- `allocator_state(a)` — a call, to do `load64(a + 32)`
- `fncall2` — the indirect call, which lands on…
- `_arena_alloc(state, size)` — a trampoline whose entire body is
  `return arena_alloc(state, size);`
- `arena_alloc` — the actual work

Cyrius does not inline, so each of those is a real frame.

## Measured

cycc 6.5.9, x86-64. Ten allocations of 24 bytes per iteration against an
`arena_allocator(1048576)`, 200,000 iterations, minus a `reset_via`-only control
of 16 ns. Per-allocation figures are `(total - 16) / 10`.

| form | ns/iter | **ns/alloc** | vs `alloc_via` |
|---|---|---|---|
| `alloc_via(ar, 24)` | 167 | **15.1** | — |
| `fncall2(load64(ar), load64(ar+32), 24)` | 116 | **10.0** | **−34%** |
| `arena_alloc(state, 24)` direct | 76 | **6.0** | **−60%** |

So of the 15.1 ns:

- **5.1 ns** is the two accessor calls. Removable by inlining two `load64`s into
  `alloc_via`. No API change, no behaviour change, no caller affected.
- **4.0 ns** is the vtable indirection plus the `_arena_alloc` trampoline.
- **6.0 ns** is `arena_alloc` itself, and that part looks right.

## Why this is worth a few nanoseconds of attention

Because `_a` threading multiplies it by the size of the object graph, and the
whole point of the `_a` families is that consumers build **whole response trees**
on an arena.

agnosai, counted exactly with a counting allocator wrapped around the arena's
own vtable (`allocator_new(&counting_alloc, .., arena)`):

| route | allocations | at 15.1 ns | share of request |
|---|---|---|---|
| `GET /api/v1/dashboard/crews` | 112 | 1,691 ns | of 5,217 ns — **32%** |
| `GET /api/v1/crews/{id}` | 59 | 891 ns | of 2,492 ns — **36%** |
| `POST /mcp` `tools/list` | 40 | 604 ns | of 2,870 ns — 21% |

Those counts are already **after** a hoisting pass that removed 48 allocations
from the dashboard route and 5 from `/mcp`. What remains is structural: it is
what a JSON tree costs. `bayan_json_v_obj_new_a` alone is three `alloc_via`
calls (node, vec struct, vec data) and every key/value pair is two more, so an
object with four fields is eleven allocations before any nesting.

At the measured split, the inline-the-loads fix alone would take **~300 ns off
`GET /crews/{id}`** and **~570 ns off the dashboard route** — 12% and 11% — for
a change that cannot alter behaviour. Dropping the trampoline too roughly
doubles that.

This is not specific to agnosai. Any consumer that took the `_a` guidance
seriously has the same shape.

## Repro

```cyrius
fn main(): i64 {
    alloc_init();
    var ar = arena_allocator(1048576);
    var st = allocator_state(ar);
    var n = 200000;

    var b1 = bench_new("ctl_reset_only");
    bench_batch_start(b1);
    for (var i1 = 0; i1 < n; i1 = i1 + 1) { reset_via(ar); }
    bench_batch_stop(b1, n); bench_report(b1);

    var b2 = bench_new("v1_alloc_via_x10");
    bench_batch_start(b2);
    for (var i2 = 0; i2 < n; i2 = i2 + 1) {
        alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24);
        alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24);
        reset_via(ar);
    }
    bench_batch_stop(b2, n); bench_report(b2);

    # ... v2 with fncall2(load64(ar), load64(ar+32), 24)
    # ... v3 with arena_alloc(st, 24)
    return 0;
}
var r = main();
syscall(60, r);
```

## Suggested fix, in the order they are worth having

1. **Inline the two accessor loads.** The largest single win, and the safest
   change in the file — `allocator_new` already fixes the layout these read.

   ```cyrius
   fn alloc_via(a, size): i64 {
       return fncall2(load64(a), load64(a + 32), size);
   }
   ```

   `realloc_via`, `free_via` and `reset_via` have the identical shape and should
   move together. `reset_via` at 16 ns is the same story on a hotter path than it
   looks — a request loop calls it once per request, but so does every `_a`
   benchmark's inner loop.

2. **Register the real function, not a trampoline.** `arena_allocator` passes
   `&_arena_alloc`, whose whole body is `return arena_alloc(state, size);` —
   identical signature `(a, size)`. Passing `&arena_alloc` directly removes a
   frame per allocation. `_arena_reset` → `arena_reset` is the same. Worth
   checking the other constructors for the same pattern.

3. **Only if 1 and 2 are not enough:** a `bump_alloc`-style monomorphic fast path
   that skips the vtable when the allocator is known statically. That is a real
   design change and probably not worth it — 1 and 2 get most of the way for
   almost nothing.

Related in kind: [`2026-07-26-agora-fs-dir-list-per-call-alloc.md`](./2026-07-26-agora-fs-dir-list-per-call-alloc.md)
and [`2026-07-28-sock-send-result-allocates-per-call.md`](./2026-07-28-sock-send-result-allocates-per-call.md)
are both "the per-call overhead is the cost". This one is underneath all of them.
