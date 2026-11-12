# `memcpy` / `memset` move one byte per iteration: 6–7× slower than 8-byte chunks, and they dominate frame-sized copies — OPEN

**Status:** 🟡 **OPEN** — measured 2026-11-02 against cyrius 6.7.18 on x86_64 Linux with
[`repros/2026-11-02-memcpy-memset-byte-loops.bcyr`](repros/2026-11-02-memcpy-memset-byte-loops.bcyr).
`lib/string.cyr:61` (`memcpy`) and `:72` (`memset`) are still the pure-Cyrius byte loops that replaced the
`rep movsb` / `rep stosb` asm.
**Placement:** unpinned — 6.x-line backlog. The user places it. It is related to the
[`memmove` proposal](../proposals/2026-10-14-memmove.md), which measured the same byte-loop cost and deliberately
left speeding up `memcpy` as "a separate decision". This is that decision, filed.
**Discovered:** 2026-11-02, ranga 2.3.1's benchmark pass (all 134 Rust benchmarks ported, plus GPU), and the
mabda native GPU buffer copies it exposed.
**Also reported:** 2026-11-09, by impetus's Rust → Cyrius port (M2, the 2D backend's types). It covers the
small-copy regime, the struct-sized copies a library makes on every call, with its own repro
([below](#the-small-copy-regime-impetus-2026-11-09)).
**Severity:** Medium — no wrong value, but a silent > 2× performance cost on every large copy and fill, in every
program that links `lib/string.cyr`.
**Affects:** `lib/string.cyr` from 5.3.15, where the CHANGELOG records the asm removal (the 5.11.41 entry calls it
"pre-v5.0", but the removal entry itself is under 5.3.15), through 6.7.18. 4.1.2 had added the asm ("~30x faster
for 128-byte copies").

## Summary

`memcpy(dst, src, n)` is `store8(dst + i, load8(src + i))` once per byte, and `memset` the same with a constant.
On a 1080p RGBA frame (8,294,400 bytes), measured back to back on cyrius 6.7.18, x86_64 (Ryzen 7 5800H, not a
quiesced machine):

| Operation | Stdlib (byte loop) | 8-byte chunks + byte tail | Speedup |
|---|---:|---:|---:|
| copy 8,294,400 B | 13.2 ms (≈630 MB/s) | 2.04 ms (≈4.1 GB/s) | 6.5× |
| fill 8,294,400 B | 11.5 ms | 1.67 ms | 6.9× |

The `memmove` proposal measured the same ratio at 4 KiB on x86_64 (7.5 µs against 0.95 µs) and on qemu-aarch64
(49.6 µs against 6.8 µs).

## What it costs consumers (measured)

- **impetus** (physics; the 2.0.0 port, `impetus/docs/benchmarks-rust-v-cyrius.md`, M2 part 2). Adding a ball
  collider's mass to a body takes 545 ns. Rust's whole `add_body_with_collider` takes 253 ns on the same machine,
  arena and map inserts included. The collider's copy of its shape record takes 349 ns of the 545, and about
  290 ns of that is one 184-byte `memcpy`. The port also `memcpy`s every arena insert and get (a body record is
  224 B), the spatial hash sort's 24-byte records (once per record per merge pass), and every JSON reader's result
  struct.

- **ranga** (image processing; `bench-history.csv`, `docs/benchmarks-rust-v-cyrius.md`). Against the same
  operations in Rust 1.0.1 on the same machine, the worst ratios outside upstream code are copy and fill bound:
  - `buffer_pool_acquire_release`: 127× (re-zeroes an 8.3 MB buffer per acquire);
  - `crop_1080p_to_720p`: 53×, and `flip_vertical`: 32× (row `memcpy`);
  - `fill_solid` and `flip_horizontal`: about 18×.
  The library-wide median is 7.9×.
- **mabda** (native GPU backends). `gpu_buffer_write` / `gpu_buffer_read` are each one `memcpy` into a mapped
  BO. A 1080p GPU operation copies 16.6 MB and spends about 30 ms doing it, whatever the kernel. wgpu runs the
  same operation in 2.4–3 ms on the same iGPU. Filed on the mabda side as
  `mabda/docs/development/issues/2026-11-02-native-buffer-copies-are-byte-loops.md`.

## Reproduction

```sh
cyrius bench docs/development/issues/repros/2026-11-02-memcpy-memset-byte-loops.bcyr
```

It checks first that the chunked copy and fill match `memcpy` / `memset` byte for byte at an odd length and an odd
source offset, then times all four on 8,294,400 bytes. It is pure Cyrius with no asm.

## The small-copy regime (impetus, 2026-11-09)

The byte loop costs about 1.5 ns per byte at every size, so struct-sized copies pay the same ratio as frames.
[`repros/2026-11-09-memcpy-small-struct-copies.bcyr`](repros/2026-11-09-memcpy-small-struct-copies.bcyr) times
`memcpy` against the same `copy8` at the sizes a struct copy has. Measured on cyrius 6.7.18, x86_64 Linux ELF, not
a quiesced machine; two runs, 200,000 copies per size (20,000 at 4 KiB):

| Bytes | What it is in impetus | `memcpy` (byte loop) | `copy8` | Speedup |
|---:|---|---:|---:|---:|
| 24 | a broadphase record | 42–44 ns | 11 ns | 4× |
| 184 | a `ColliderShape` | 287–296 ns | 43–45 ns | 6.6× |
| 224 | a rigid body record | 341–361 ns | 51–54 ns | 6.7× |
| 4,096 | a page | 6.08–6.45 µs | 0.86–0.91 µs | 7.1× |

```sh
cyrius bench docs/development/issues/repros/2026-11-09-memcpy-small-struct-copies.bcyr
#   memcpy_24B: 44ns ...    copy8_24B: 11ns ...
#   memcpy_184B: 287ns ...  copy8_184B: 43ns ...
#   memcpy_224B: 341ns ...  copy8_224B: 51ns ...
#   memcpy_4096B: 6.077us ... copy8_4096B: 862ns ...
#   copy8 matches memcpy byte for byte at 23, 183, 223 and 4,095 bytes, odd offset
```

It checks `copy8` against `memcpy` first, at each size minus one byte and from an odd source offset (so the tail
and the unaligned chunks run), and exits 1 on a difference. Proposed fix (1) closes this regime too: even 24 bytes
are 3 chunks and no tail.

## Root cause

Not a defect, a trade-off that was never revisited. The CHANGELOG entry that removed the asm says why: the 15-byte
x86 `cld; mov …; rep movsb` block was pasted byte for byte by the aarch64 backend, which misaligned every
downstream aarch64 instruction (SIGILL). The fix was a pure-Cyrius loop, with the note "`rep movsb` was a
micro-optimisation; measurements in `lib/bench.cyr` never depended on it". Since then, consumers that copy images,
GPU buffers or large arenas have found that it is load-bearing for them.

## Proposed fix

1. **Pure Cyrius, both arches:** copy and fill in 8-byte `load64` / `store64` chunks with a byte tail, as in the
   repro (`copy8` / `fill8`). There is no asm, so the aarch64 alignment hazard that removed `rep movsb` cannot
   recur. The chunks are unaligned. That is fine on x86_64, and the `memmove` proposal's qemu-aarch64 run used
   unaligned chunks too; native aarch64 and agnos should be confirmed before landing, as that proposal notes.
2. **Land it with, or after, `memmove`.** A forward chunked `memcpy` corrupts an overlapping right shift
   differently from today's byte loop. The `memmove` proposal found 20 `memcpy` sites that may overlap, 19 of
   them unaudited. It also wants `memcpy`'s comment to say the ranges must not overlap. That sentence should land
   no later than the faster `memcpy`.
3. **Optional, x86_64 only:** an architecture-guarded `rep movsb` / `rep stosb` (with `cld`), if the compiler can
   emit an asm block for one target only. This is speculation: I haven't checked whether per-target asm selection
   exists. It would beat 8-byte chunks on large copies, but (1) alone recovers most of the gap.

## Consumer-side workarounds (shipped)

- `programs/cxvm.cyr` already zeroes its 8 MiB guest segment with a `store64` loop ("lib's `memset` is a byte
  loop: 8 MiB cost ~10 ms a run, now ~4 ms", cyrius CHANGELOG).
- sankoch's brotli decoder hand-unrolls 8-byte chunks (per the `memmove` proposal).
- ranga plans a word-at-a-time copy and fill for its own hot paths (roadmap 2.6.x) unless this lands first.
- impetus ships none: its port measures speed rather than tuning around the stdlib, so it keeps `memcpy` and records
  the cost (`impetus/docs/benchmarks-rust-v-cyrius.md`, M2 part 2; its port plan §8, S5).

## Also measured: pravash (2026-11-11)

pravash's Rust → Cyrius port (M1 part 3) moves 144-byte particle records. It had a conditional ledger row (L12) for
a record copy of its own if `memcpy` turned out to dominate. Measured pinned on x86_64 Linux, 6.7.18, 500 copies of
a 144-byte record per iteration:

| Copy | Per 144-byte record |
|---|---|
| `memcpy(dst, src, 144)` | **245 ns** |
| an 18-word `load64` / `store64` loop | 37 ns |
| struct assignment `*dst = *src` (the compiler's own copy) | **11.7 ns** |

Struct assignment already copies word-wise and is 21× faster than `memcpy`. So pravash moves its records by
assignment (`ParticleArena::compact`, the record resets), needs no copy of its own, and closed L12. `memcpy` stays
only where a buffer grows (a column's doubling), off the hot path. The 21× gap is one more data point for the
chunked `memcpy`: a caller that copies raw bytes, without a struct type to assign, pays it in full.
