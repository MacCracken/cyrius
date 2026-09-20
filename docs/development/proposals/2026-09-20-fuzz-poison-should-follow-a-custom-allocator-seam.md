# Proposal — let `cyrius fuzz --poison` follow a custom allocator seam, not only the freelist

**Filed:** 2026-09-20 · **Status:** 🟡 OPEN — for maintainer direction
**Filed by:** rekha (0.4.12), which parses untrusted font bytes and had to hand-build a 2,100-line
substitute. Measured against cyrius 6.6.6.

**Prompted by:** a roadmap cleanup that asked why rekha's hostile-input gate is a bespoke harness
rather than the toolchain fuzzer, and found the answer had never been filed.

## The bind

`--poison` puts redzones around blocks from **the freelist allocator**. rekha does not use it: every
byte rekha allocates goes through `sd_alloc`, sadish's allocation seam, so that a consumer can scope
one arena around a text draw and get the outlines, the paths and the coverage from it. That is a
deliberate and load-bearing design property — rekha 0.3.10 shipped it, and 20 `rekha_char_to_sdpath`
calls under an arena hook cost the global heap **exactly 0 bytes** (measured).

The consequence is that the one class of defect rekha most needs to catch is the one `--poison` is
blind to. A read past a table, a glyph span or an allocated block does not fault on a bump
allocator: it lands in mapped memory and silently changes an outline, a metric or a glyph id.
rekha's own source says it plainly:

```
# ⭐ WHAT THIS EXISTS TO PROVE. rekha parses untrusted font bytes, and a read past a table, a glyph
# span or an allocated block does not fault on a bump allocator — it lands in mapped memory and
# silently changes an outline, a metric or a glyph id. `cyrius fuzz --poison` cannot see it (its
# redzones live in the freelist allocator; rekha draws from sd_alloc).
```

`rekha/programs/hostile_test.cyr`, opening comment.

## What rekha built instead

An in-process **A/B sentinel differential**. Every `sd_alloc` is routed through a bump pool whose
unallocated bytes and trailing redzone hold a sentinel; every font sits in a buffer whose 256 bytes
either side hold the same sentinel. Each input is swept twice — sentinel `0xA5`, then `0x5A` —
through every public entry point, and every result is folded into an FNV-1a digest. A path that
reads a byte it does not own folds a value that differs between the sweeps, so the digests diverge.
A canary group proves the harness can see a one-byte overread of the font, of a block, and of the
pool frontier. On top of that sits a seeded mutation sweep over a real face.

It works — it is what 0.3.11 closed four out-of-bounds reads with. But it is ~2,100 lines of
test-only machinery reimplementing a toolchain capability, and it has admitted blind spots the
toolchain would not have:

> ⚠ WHAT IT CANNOT SEE. A read that lands inside memory rekha itself wrote (the next table, the next
> block) folds identical values under A and B.

## What is asked

A way to tell `--poison` which allocator to instrument. Sketch, in preference order:

1. **A registration hook** — a `fuzz_poison_hook(alloc_fn, free_fn)`-shaped seam, or a manifest
   line, that names the allocation entry point so redzones are placed around ITS blocks. rekha
   would point it at `sd_alloc` and delete most of the harness.
2. **Poison the caller, not the allocator** — instrument at the call site so any allocator gets
   redzones, at the cost of needing the block size at the return.
3. **Document the limit** — at minimum, say in the fuzz docs that `--poison` covers the freelist
   allocator only, so the next package with an allocation seam learns it from the manual rather
   than from a silent all-green run.

⚠ **Not asked for:** changing the freelist allocator, or making `--poison` understand arenas in
general. One hook that says "these are the blocks" is enough.

## Why it is worth a toolchain change

An allocation seam is the normal shape for a graphics or parsing library in this stack — sadish
defines one, rekha draws from it, and any consumer that scopes an arena inherits it. Every such
package is outside `--poison`'s reach today, and each one discovers that the way rekha did:
by writing its own fuzzer and finding out afterwards.

## Pointers

- The substitute harness: `rekha/programs/hostile_test.cyr` (sentinel differential, corpus,
  mutation sweep) and its `hb_hook`.
- The seam: `sadish`'s `sd_alloc` / `sd_alloc_set`.
- rekha's roadmap note: `rekha/docs/development/roadmap.md`, under *Blocked on a sibling*.
