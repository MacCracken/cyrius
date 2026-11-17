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

## Notes from the consumer (pravash M7 part a, 2026-11-12)

`PackedParticles::from_soa` of 1,000 particles takes 52.6 µs, against Rust's 10.2 µs (pinned, interleaved). It
allocates three f32 buffers of 16 KB, 16 KB and 8 KB per call, as Rust's does, and those three `fl_alloc` / `fl_free`
cycles alone take **37 µs** on the same core, before a page is touched. Since the packing is a per-upload step for a
GPU backend, this is the first pravash call on a repeated path that the large-block cycle dominates. A size-class
cache to 64 KB, or `fl_reserve`, would take most of it.

## Notes from the consumer (selah M6, 2026-11-14)

selah runs each request of its MCP server and HTTP clients in a scratch arena on the freelist (`selah/src/scratch.cyr`):
64 KB chunks, freed when the request ends. Every chunk was a fresh mapping, so each request paid the large-block
cycle. x86_64, 5,000 iterations each, at a load average of 3–5 on 16 cores:

| Body | Per iteration |
|---|---|
| arena created, one 100-byte block, freed (one 64 KB chunk: `fl_alloc` + `fl_free`) | 6.2 µs |
| arena created, 16 blocks of 1,000 bytes (four pages touched), freed | 13.8 µs |

selah now keeps one spare chunk between arenas, taken and given back with `atomic_cas` (ledger row L24), and the
same bodies take 0.18 µs and 2.9 µs. The MCP server's `selah_annotate` call went from 280 to 257 µs, and
`selah_history` from 112 to 103 µs. The spare leaves when the freelist reuses large blocks: a size-class cache up to
64 KB, as asked above, would cover it.

## Notes from the consumer (pramana M0 probe P4, 2026-11-15)

pramana's owned objects keep their buffers in one freelist block, freed by `_drop` (its decision D11). Its probe P4
(`pramana/docs/development/port-parity.md` §6.2) measured the large-block cycle, pinned, at a load average of 5–7:

| Soak | Block | Per iteration |
|---|---|---|
| 10⁴ × `MultivariateNormal` new + `_drop`, d = 4 | 160 bytes, a size class | 380 ns |
| 10³ × `MultivariateNormal` new + `_drop`, d = 32 | 8,448 bytes, so mmap + munmap | 36 µs |
| 100 Metropolis–Hastings runs of 10⁴ samples, d = 2, + `_drop` | a 160 KB result per run | once per run |

The heap stays flat in every soak, so the cycle costs time, not memory. An MVN's block is 8(d² + d) bytes, so a
size-class cache to 16 KB would cover one up to d = 44; the MH result is a once-per-run cost.
