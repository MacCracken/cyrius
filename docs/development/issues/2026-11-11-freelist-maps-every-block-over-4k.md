# `fl_alloc` maps and unmaps every block over 4 KB: a freed buffer is never reused, so each re-allocation pays an mmap and a page fault per page — open (performance finding)

**Status:** 🟡 **OPEN** — measured on cyrius 6.7.18 (x86_64 Linux ELF), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M1 part 3, its `ParticleArena` and `ParticleSoa`
benchmarks).
**Reporter:** pravash 2.0.0 port (`pravash/docs/benchmarks-rust-v-cyrius.md`, M1 part 3).
**Severity:** **Low–medium (performance).** Results are correct. But a library that allocates and frees buffers over
4 KB pays the kernel on every cycle. Examples: a particle arena of 1,000 records (144 KB), one SoA column of 1,000
f64s (8 KB), a grid field. glibc's malloc reuses such buffers from its heap.

## Summary

`lib/freelist.cyr` serves blocks of up to 4,096 bytes from size classes, and sends every larger one straight to
mmap / munmap. A freed large block goes back to the kernel at once. The next allocation of the same size is a fresh
mapping, whose every page faults on first touch. Timed pinned to one core on a quiet box, 10,000 iterations each:

| Body | Per iteration |
|---|---|
| `fl_alloc(144008)` + `fl_free` | 5.9 µs (mmap + munmap) |
| `fl_alloc(144008)`, one store per page (36 pages), `fl_free` | **60 µs** (≈1.5 µs per page fault) |
| `fl_alloc(8008)` + `fl_free` | 5.8 µs |

In pravash, the large-block cycle accounts for:
- **most of `ParticleArena::new(1000)` plus drop:** 104 µs, of which resetting the records is about 12 µs;
- **about 160 µs of the 205 µs `ParticleSoa::from_aos` of 1,000 particles:** 18 columns of 8 KB, each mapped and
  faulted.

The same bodies in Rust (glibc malloc) take 7.6 µs and 16 µs. pravash's solvers allocate their storage once, off the
step path, so this doesn't touch a simulation step. It is the cost of building and dropping solvers, arenas and SoA
stores repeatedly, as tests, benchmarks and tools do.

## Ask

Some reuse for large blocks. Any of these would do:
- **a small cache** of recently freed large mappings per size bucket (glibc raises its mmap threshold after a free,
  so later blocks of that size come from the heap);
- **a large-block arena**, with the 64 KB chunk refill extended to a few size classes past 4 KB (8 KB, 16 KB, …,
  64 KB);
- **`fl_reserve(bytes)`** for a caller that knows it will cycle a working set.

The measurements here are the before numbers to beat. Nothing in pravash waits on this: no stand-in, no ledger row
(an allocator of its own would be the wrong fix).
