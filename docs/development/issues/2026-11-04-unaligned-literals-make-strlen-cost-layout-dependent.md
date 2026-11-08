# String literals are packed unaligned and `strlen` walks bytes to the next 8-byte boundary, so a literal's cost depends on unrelated data before it — OPEN

**Status:** 🟡 **OPEN**. Measured 2026-11-04 against cyrius 6.7.18 on x86_64 Linux (Ryzen 7 5800H, load 1.4) with
[`repros/2026-11-04-strlen-alignment.bcyr`](repros/2026-11-04-strlen-alignment.bcyr). `lib/string.cyr:12`
(`strlen`) still has the byte-by-byte alignment prologue.
**Placement:** unpinned — 6.x-line backlog. The user places it. Related:
[`2026-11-04-pkgver-declared-by-a-comment-mention.md`](2026-11-04-pkgver-declared-by-a-comment-mention.md), the
trigger in hoosh's case, and
[`2026-11-02-memcpy-memset-byte-loops-dominate-frame-copies.md`](2026-11-02-memcpy-memset-byte-loops-dominate-frame-copies.md),
the same byte-loop cost in `memcpy` / `memset`.
**Discovered:** 2026-11-04, hoosh 2.9.11, tracing why 2.9.10's one-byte longer version string moved
`cache_get_hit` from 119 to 146 ns.
**Severity:** Low to Medium. No wrong value. But `strlen`, and `streq`, which calls it twice, cost up to 1.8× more
depending on where a literal happens to land. That makes benchmark rows move when unrelated data changes length.
**Affects:** `lib/string.cyr` `strlen` / `streq` with cycc's `.rodata` layout, through 6.7.18.

## Summary

Two things combine:
1. **cycc packs string literals into `.rodata` back to back, with no alignment.** A literal's offset modulo 8 is
   decided by the total length of every literal emitted before it.
2. **`strlen` reads byte by byte until `s + n` is 8-aligned,** then 8 bytes at a time, then byte by byte again
   inside the word holding the NUL. An aligned 13-byte string takes two word reads. The same string starting at
   offset 1 takes seven single-byte steps first.

So the cost of `strlen(literal)` depends on data the code never touches. In hoosh, one byte more of version string
moved the bench's hot keys from `% 8 == 0` to `% 8 == 1`: `"prompt-hash-1"` (`cache_get_hit`) and
`"http://localhost:11434"` (`cost_record_local_free`, via `streq`). No literal crossed a cache line; the whole
effect was the prologue.

| hoosh bench row | literal at `% 8 == 0` (2.9.9 layout) | at `% 8 == 1` (2.9.10 layout) |
|---|---:|---:|
| `cache_get_hit` | 119 ns | 146 ns |
| `cost_record_local_free` | 109 ns | 136 ns |
| `route_matches_model` (`% 8` 4 → 5) | 32 ns | 36 ns |

Both builds were byte-identical code apart from the shifted data. The two binaries were alternated over three
rounds.

The same effect gave hoosh's constant-time token compare a 10 ns gap, 92 against 102 ns, between a wrong token that
differs early and one that differs late. That reads like a timing leak, and it was only the two literals'
alignment: aligned, both rows read 81 ns.

## Reproduction

```sh
cyrius bench docs/development/issues/repros/2026-11-04-strlen-alignment.bcyr
```

It copies the same 13-byte string to offsets 0–7 of an 8-aligned heap buffer and times `strlen` at each. Three
runs agreed to the nanosecond:

| offset | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ns per `strlen` | 17 | 30 | 29 | 19 | 19 | 18 | 17 | 17 |

## Root cause

- `lib/string.cyr:15-18`: the alignment prologue is a byte loop of up to 7 iterations.
- `lib/string.cyr:28-30`: the NUL's position inside the matching word is found with a second byte loop of up to 8.
- cycc's `.rodata` emitter: literals are concatenated with no padding. I haven't located the exact function; this
  is inferred from the hoosh binaries, where the version literal and the next literals follow each other with only
  their NUL between.

## Proposed fix

Either change removes most of the variance; both would remove it entirely.

1. **`strlen` without a byte prologue.** Read the 8-aligned word that contains `s`, then force the bytes before `s`
   to non-zero before the zero-byte test, e.g. `v | ((1 << (8 * (s & 7))) - 1)` on little-endian. An aligned
   8-byte read never crosses a page boundary, so it cannot fault where the byte loop would not. Then find the NUL
   in the hit word from the zero-byte mask with a trailing-zero count, if cycc has one, instead of a byte loop.
   Every caller gains, not only literals.
2. **Align string literals of 8 bytes or more to 8 in `.rodata`.** That costs up to 7 bytes per literal. Short
   literals could stay packed.

## Consumer-side workaround (shipped)

hoosh 2.9.11: every string a timed bench loop reads is an 8-aligned heap copy (`tests/hoosh.bcyr`, `_b_s`; `alloc`
rounds allocations to 8). Built at versions `2.9.9` and `2.9.11`, the fixed bench gives the same rows
(`cache_get_hit` median 120 ns for both over eight alternated rounds). The gateway itself is less exposed: its hot
keys are heap strings, and across its many literals the misalignments average out.
