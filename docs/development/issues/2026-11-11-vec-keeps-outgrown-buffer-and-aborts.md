# `vec_push_a` keeps every outgrown buffer even through a freeing Allocator, and `vec_get` / `vec_set` abort on a bad index — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64 Linux ELF), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M1 part 3, `ParticleSoa`).
**Reporter:** pravash 2.0.0 port (conversion ledger L13; `pravash/docs/development/pravash-port-plan.md` §8).
**Severity:** **Medium.** Nothing computes wrong. A library that wants a growable array can't use `vec` on a flat heap:
- it can't keep a step loop's memory flat;
- it can't release a vector's storage;
- it can't index without risking an abort, which library code must never do.

## Summary

pravash ports Rust's `ParticleSoa`, whose 18 fields are public `Vec<f64>` / `Vec<u8>`. Callers push to them, index
them and truncate them independently. `vec` would be the natural counterpart: its slots are 8-byte words, so f64
bits fit. Two things stop it.

1. **Growth never frees, even through an Allocator that can.** `vec_push_a(a, v, val)` allocates the doubled buffer
   with `alloc_via(a, ..)`, copies, and never calls `free_via(a, old)`. That is right for the bump and arena
   allocators, whose free is a no-op. It is not right for an Allocator with a real free, such as one over
   `fl_alloc` / `fl_free`. Every outgrown buffer stays allocated: a vector pushed to n elements holds about 2n slots
   of dead buffers. There is no `vec_free` either, so even the live buffer can't be returned.
2. **A bad index aborts.** `vec_get` and `vec_set` exit the process (status 1, "vec: index out of bounds") on an
   index outside the length. Rust's `v[i]` panics there too. But a Cyrius library may not abort: pravash's rule, and
   impetus's, is that every library function returns a value. So a library has to bounds-check every access itself,
   or not use `vec`.

## Reproduction

`docs/development/issues/repros/2026-11-11-vec-keeps-outgrown-buffer-and-aborts.cyr`:

```sh
cyrius build docs/development/issues/repros/2026-11-11-vec-keeps-outgrown-buffer-and-aborts.cyr /tmp/vecgrow
/tmp/vecgrow; echo "exit=$?"
```

It builds an Allocator over the freelist that counts its calls, pushes 4,096 words through `vec_push_a`, and
prints the counts. Then it calls `vec_get` one past the end:

```text
allocs through the Allocator: 10 (header, first buffer, then one per growth step); frees: 0
now vec_get(v, 4096), one past the end:
vec: index out of bounds
exit=1
```

## Ask

1. **Free on growth.** `vec_push_a` (and every other growing path) calls `free_via(a, old_data)` after the copy.
   It is a no-op for bump and arena, so nothing changes for them.
2. **`vec_free_a(a, v)`**, which releases the data buffer and the header through the Allocator.
3. **Non-aborting access.** Either `vec_get` returns a value on a bad index, or there are checked variants
   (`vec_try_get(v, i, out)`: 1 / 0; `vec_try_set`) for library code. The abort can stay the default for
   programs.

Until then pravash uses a 70-line freelist column of its own (`src/column.cyr`: push with doubling that frees the
old buffer, `drop`, and NaN / 0 on a bad index), marked `UPSTREAM(L13)`. It converts when `vec` can do this.

## Also needed: pramana (2026-11-15, cyrius 6.7.18)

`vec_select_nth` aborts the same way: "vec: select_nth k < 0" and "vec: select_nth out of bounds"
(`lib/vec.cyr:377–378`). pramana's library rule is pravash's and impetus's (no aborts: every error is a returned
code), so it can call none of `vec_get`, `vec_set` or `vec_select_nth` unchecked. Its data are raw f64 buffers in any
case, so its sort and selection stand-in (`src/sort.cyr`, ledger L3) works on `(ptr, n)`. The stable form it needs
is in `2026-11-11-no-stable-sort.md`.

## Also needed: pramana, the capacity abort reached through bayan (2026-11-15, cyrius 6.7.18)

`vec_push_a` has a third abort, and a JSON document reaches it. One element past `VEC_CAP_MAX` (2^28 by default), it
ends the process with "vec: capacity overflow" (`lib/vec.cyr:129`), although it returns −1 when the allocator
refuses. bayan's parser pushes every array element through `vec_push_a`, so `bayan_json_v_parse_buf_a` on a document
with an array of 2^28 + 1 elements ends the caller's process. That document is 512 MiB of text, but it is a peer's
text: pramana reads JSON written by anyone.

`VEC_CAP_MAX` is a `var`, so the abort shows at any size. Lowered to 64, a 131-byte document of 65 elements:

```text
document: 131 bytes, 65 elements; VEC_CAP_MAX = 64
bayan_json_v_parse_buf on the same document:
vec: capacity overflow
exit=1
```

**Ask:** past `VEC_CAP_MAX`, `vec_push_a` returns −1, as it does on an allocator refusal; bayan then reports "out of
memory in array" like any other exhausted arena.

**Meanwhile** pramana's JSON reader (`src/json.cyr`, M1 part d3a) refuses, unread, any document longer than
2·`VEC_CAP_MAX` − 1 bytes, which can't hold an array that long. It reads the variable at run time, so a lowered cap
tightens it (its test lowers the cap to 64 and opens 63- and 65-element documents). The guard is marked
`UPSTREAM(L13)` and goes when `vec_push_a` stops aborting.

## Also needed: svara, a vec sized before its first push (2026-11-16, cyrius 6.7.18)

On the bump allocator, ask 1 changes nothing: its free is a no-op, so every buffer `vec_push_a` outgrows stays in
the arena whatever `vec` does with it. Only a vec sized before its first push avoids that, and `lib/vec.cyr` has no
way to size one. `vec_new_a` starts at 16 slots and `vec_push_a` doubles from there.

svara renders each phoneme into a raw f64 buffer and returns it as a `vec`. Up to svara 3.8.2 it pushed the samples
into a vec from empty, so every render kept its samples about four times over:

| svara 3.8.2, bump allocator | kept | its samples |
|---|---:|---:|
| one 0.1 s phoneme, 4,410 samples | 169 KB | 35 KB |
| `svara_sequence_render`, per output sample | 81 B | 8 B |
| `svara_sequence_render_planned`, per output sample | 27 B | 8 B |

A server that renders all day (hoosh) never gets any of it back.

`docs/development/issues/repros/2026-11-16-vec-cannot-be-presized.cyr` pushes 4,410 words both ways:

```sh
cyrius build docs/development/issues/repros/2026-11-16-vec-cannot-be-presized.cyr /tmp/vecroom
/tmp/vecroom
```

```text
words: 4410
their bytes: 35280
vec_new + vec_push keeps: 130968
rendered buffer + adopting Allocator keeps: 65600
  the vec's data is the rendered buffer: 1
```

**Ask:** `vec_with_capacity_a(a, n)` and `vec_with_capacity(n)`, a vec whose first buffer holds n words, or
`vec_reserve_a(a, v, n)`. Better still for a renderer, a vec that takes an existing buffer as its data
(`vec_from_buf(buf, len, cap)`), so samples rendered in place need no copy at all. Any capacity should do, not just
a power of two: `vec_push_a` doubles from whatever capacity it finds.

**Meanwhile** svara 3.8.3 (`svara_vec_adopt`, `src/error.cyr`) builds the vec through `vec_new_a` and `vec_push_a`
with an Allocator of its own. That Allocator answers every data-sized request that fits with the buffer the samples
were rendered into. So the vec "grows" into that buffer, its copy writes each word over itself, and it ends up holding
the buffer. It relies on `lib/alloc.cyr`'s Allocator contract and not on the vec layout. The table above becomes
68 KB, 24 B and 10 B. What it can't remove:

- the buffer has to be the power-of-two capacity the vec would grow to, up to twice the samples;
- each vec carries a 40-byte Allocator and 16 bytes of state.

With `vec_with_capacity` or `vec_from_buf`, svara drops the Allocator, and each buffer shrinks to its samples.

**For ask 1:** an Allocator may hand back the same pointer for the larger buffer, as svara's does. Today's
word-by-word forward copy tolerates that. If `vec_push_a` starts freeing the old buffer, it should skip the free when
the new buffer is the old one. Otherwise an Allocator with a real free would release the live buffer. svara's free is
a no-op, so svara itself is safe either way.

## Also needed: rasayan, and the same abort in `str_builder` (2026-11-16, cyrius 6.7.18)

rasayan's library rule is pravash's (no aborts in library code; every error a returned code). Its M0 probe 3
(`rasayan/docs/development/port-parity.md` §3) measured its four `Vec`-shaped results (PTM sites, domain hits,
Chou-Fasman labels, composition) every way: a caller buffer with the count in `Ok(count)` is the fastest (6× a
refilled vec for the per-residue labels) and allocates nothing, so rasayan never calls `vec_push` in its library.
`vec_push` exits the process on a refused allocation or a capacity overflow (`_vec_abort`), and `vec_push_a` returns
−1 on the first but still aborts on the second.

The same shape is in `lib/str.cyr`, which every JSON writer and the shortest-digit printer (`fmtf.cyr`, vendored by
impetus, ushma, pramana and rasayan) write through: `str_builder_add`, `str_builder_add_cstr`, `str_builder_putc` and
`str_builder_add_int` call `_sb_die()` — "str_builder: alloc failed" and exit 1 — when the buffer cannot grow, while
their `_a` forms return −1. `str_builder_putc` has no `_a` form. A library that writes JSON (rasayan's 69 serde types
from M1, its MCP replies) either pre-sizes every builder so a put never grows, or accepts an abort it cannot report.

The ask, for both: a non-aborting form of every growing call (`str_builder_putc_a`, and `vec_push_a` returning −1 on a
capacity overflow too), so a library can return its out-of-memory error.
