# The arena is fixed-capacity, and exhausting one is a segfault in practice — so work of unbounded size cannot use an arena at all

**Status:** ✅ **SHIPPED v6.5.9** — All three requested fixes shipped as ONE policy field (NULL/GROW/SPILL/ABORT) plus arena_new_growable, arena_allocator_growable, arena_capacity_total, and an arena_free that actually invalidates a growable arena. Default is unchanged. Gate: tests/tcyr/vr01_arena_growable.tcyr.
**Filed as:** filed 2026-08-06.
**Filed as:** filed from agnosai, which hit both halves in one day: a reachable crash in shipped code, and a 97%-transient workload it cannot arena at all.
**Placement:** unpinned — stdlib surface (`lib/alloc.cyr`), no language change.
**Discovered:** 2026-08-06, measuring whether `orch_crew_runner` was worth threading onto an arena.
**Severity:** **Medium-high.** The capability gap is ordinary; the *failure mode* is what raises it. A consumer that adopts arenas correctly, measures correctly and tests correctly can still ship a crash, because every natural allocation measurement proves the common case and none of them probe the ceiling.
**Affects:** cycc 6.5.8 and earlier.

## The mechanism, stated accurately

`lib/alloc.cyr` offers exactly one arena: `arena_new(capacity)` / `arena_allocator(capacity)`, fixed size. There is no chunked, growable, or spilling form.

**The primitives handle exhaustion correctly.** `arena_alloc` returns 0 when full; `str_from_a` checks and returns 0; `vec_push_a` checks and returns -1. That is all reasonable and none of it is the bug.

The bug is what happens next. A `Str` of 0 is **indistinguishable from a valid `Str`** — there is no option type, no error channel, and no convention for propagating an allocation failure through the `_a` families. So the 0 flows on, and the next thing anyone does with it dereferences it:

```
$ cat repro.cyr
fn main(): i64 {
    alloc_init();
    var a = arena_allocator(256);
    while (alloc_via(a, 8) != 0) { }        # exhaust exactly
    var s = str_from_a(a, "hello");
    println_int(s);                          # prints 0 — correctly reported
    println_int(str_len(s));                 # SIGSEGV
    return 0;
}

$ cyrius build repro.cyr repro && ./repro
str_from_a on an exhausted arena -> 0
now str_len on it:
$ echo $?
139
```

So the *observable* behaviour of "arena too small" is a segfault several layers from the allocation, and the honest description is not "nothing checks" — it is that **checking is not expressible at the call sites that matter.** A route handler builds a JSON tree with a few hundred `_a` calls; guarding each one is not a thing anyone will do, and there is nowhere to return the failure to if they did.

## Half one: adopting arenas *correctly* introduced a reachable crash

agnosai threaded its HTTP read and write routes onto sandhi's 64 KiB per-request arena — the intended use, following the `_a` convention throughout. Every route's per-request allocation went to zero, measured and asserted.

Then:

```
GET /api/v1/dashboard/crews, 200 registered crews, 64 KiB arena  →  exit 139
```

The route renders one JSON object per registered crew. `MAX_RETAINED_CREWS` in that system is **1,000**, so this is an ordinary operating condition — not an attack, not a misconfiguration.

**The regression direction is what makes this worth filing.** Before threading, those allocations went to the no-free global bump: unbounded, so a large response was a *leak*. After threading — a change whose entire purpose is to stop leaking — the same response is a *crash*. Adopting the feature made the failure worse and quieter.

A 5,500-assertion suite did not catch it, because **allocation measurements are small-fixture by nature**: they assert `bytes == 0` over a handful of items. Nothing about that shape probes the ceiling. It took deliberately building a 200-crew fixture.

agnosai's local fix is a wrapper allocator whose `alloc` tries the arena and falls back to `alloc()` per allocation, so overflow degrades to the pre-threading cost instead of faulting. ~15 lines, and it works — but every consumer adopting arenas has to independently discover this, and most will discover it in production.

## Half two: unbounded work cannot use an arena at all

The measurement that started this:

| | bytes |
|---|---|
| allocated per 4-task crew run (audit + events on) | **33,008** |
| same run, audit chain and event bus disabled | **14,096** |
| retained *content*, serialised: crew state + 6 audit entries | **3,662** |

**⚠ Correction, added 2026-08-06 after this shipped.** An earlier revision said
"~97% transient", from comparing total allocation against the serialised crew
state alone (894 B). That was wrong twice: it ignored the audit chain — the
single largest consumer on this path, ~18 KB of a 4-task run — and it treated
*serialised* size as a proxy for *allocated* footprint, which excludes struct
overhead, 16-byte `Str` headers and vec capacity.

The defensible statement is weaker and still carries the case: retained content
serialises to 3.7 KB against 33 KB allocated, so **the majority is transient —
on the order of two thirds to four fifths.** Pinning it exactly needs the
retained structures allocated from a separate allocator, which is the work this
capability enables rather than a precondition for it. The ask was correct; the
headline number was not. That is precisely the workload an arena exists for, and it cannot have one: a crew's transient allocation scales with task count, prompt sizes and LLM response sizes, all unbounded at the type level. Any fixed capacity is either wasteful or a crash — and the spill wrapper does not help here, because you would spill most of it, which is the same as not having the arena.

So ~30 KB per crew run stays on the no-free bump indefinitely, in a long-lived server process, purely for want of an arena that can grow.

## What would fix it, in the order they are worth having

1. **A growable arena** — `arena_new_growable(initial)` that chains a chunk when the current one is full and frees all chunks on reset. This is the capability actually missing; it makes arenas usable for unbounded work, which is most of what a server does between requests. Callers keep the existing API — only construction differs.

2. **A spilling arena**, i.e. agnosai's workaround upstreamed: serve from the arena, fall back to the global allocator per allocation. Strictly weaker than 1 (spilled bytes are never reclaimed), but small, and it turns the crash into the old cost for everyone rather than for whoever finds it.

3. **An exhaustion policy on the allocator**, so a consumer can say what should happen instead of discovering it: abort with a diagnostic naming the allocator, spill, or return 0 as today. The current arrangement makes "return 0" the only option and makes it invisible.

1 and 3 are independent and both worth having: 1 removes the need to guess a capacity, 3 makes a wrong guess survivable and loud.

## Note on scope

This is **not** a request to change `arena_alloc`'s contract, nor a claim that the `_a` families are careless — they check, and they propagate what they can. The gap is structural: the only allocator that can fail is the one those families exist to serve, and the value they return on failure is indistinguishable from success at every call site downstream.
