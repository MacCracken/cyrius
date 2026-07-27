# sankoch batch gzip encoder duplicates bytes at every 1 MiB block boundary — RESOLVED

> **✅ RESOLVED in sankoch 2.7.6, folded into cyrius v6.4.79** (CHANGELOG [6.4.79]).
>
> Your root-cause analysis was **exactly right** and was confirmed line-for-line — including the
> observation that the streaming encoder is immune because `_denc_consume` carries its reached offset
> forward. That is precisely the contract the batch path now has: each block encoder publishes where
> it really stopped (`_deflate_block_reached`) and the chunker resumes there instead of at
> `block_end`.
>
> **Fixed upstream first, then folded** — sankoch was at 2.7.5, identical to what cyrius vendored, so
> the bug was live there too. A fix applied only to cyrius's `lib/sankoch.cyr` would have evaporated
> at the next re-vendor. sankoch 2.7.6 = fix + regression test + CHANGELOG + all **10** dist profiles
> regenerated (the sub-profiles do not rebuild with the main bundle — `sankoch-gzip.cyr` and friends
> would otherwise have shipped the buggy encoder at a 2.7.6 version string).
>
> **Two subtleties beyond the filed analysis**, either of which would have left a partial fix:
> 1. The fixed path's **trailing lazy-match flush** writes a match that *starts* at `sp - 1`, so the
>    consumed end is `sp - 1 + prev_match`, not `sp`. Missing it would have left the duplication for
>    lazy-matched input only.
> 2. `BFINAL` is decided from `block_end` **before** encoding, so a block with `block_end < src_len`
>    can now consume through to `src_len` when the tail is shorter than a max match — every byte
>    encoded, but no block carrying `BFINAL`, i.e. a stream a decoder treats as truncated. The chunker
>    now closes that with an empty final fixed block.
>
> **Verified:** your 2 MB repro goes from `-5` (ERR_CHECKSUM_MISMATCH) to byte-exact 2000000 →
> 2000000; **GNU `gunzip` accepts the stream and its output is byte-exact** (previously `differ: char
> 1048797`). Gate `tests/tcyr/deflate_block_boundary.tcyr` (21 assertions, levels 1/6/9 + boundary
> shapes + the gzip wrapper) is mutation-proven — restoring `sp = block_end` gives `2000153` decoded
> with first divergence at 1048729.
>
> **Why sankoch's ~160K assertions missed it:** every pre-existing deflate/gzip test used an input
> *smaller* than `DEFLATE_BLOCK_SIZE` (largest 80000 bytes), so the outer chunker never took a second
> iteration. That gap is what the new file closes.
>
> stiva picks this up by bumping its cyrius pin to 6.4.79 and re-resolving.

**Discovered:** 2026-07-25 while shipping stiva's container image import
**Severity:** High (silent data corruption; every consumer compressing > 1 MiB with the batch API)
**Affects:** sankoch as vendored in cyrius 6.4.78 (`lib/sankoch.cyr`); earlier versions unverified

## Summary

`gzip_compress` / `deflate_compress` produce a **stream that does not decode back to the input**
whenever the input exceeds `DEFLATE_BLOCK_SIZE` (1 MiB). Bytes at each block boundary are emitted
twice, so the decoded length exceeds the original and the gzip trailer's CRC-32 no longer matches.
GNU `gunzip` rejects the same stream at the same offset, so this is a genuine encoder defect and
not a sankoch decoder disagreement.

Nothing errors at compress time. The corruption surfaces later, at decompression, as a checksum
failure — arbitrarily far from the code that caused it.

In stiva this meant **every container image larger than ~1 MiB was written to disk corrupt**.
`stiva import` succeeded, and `stiva run` then failed with `layer unpack error`, leaving the layer
directory created but empty. 849 KB worked; 1.69 MB did not.

## Root cause

`_deflate_compress_level_inner` (`lib/sankoch.cyr:4814`) splits the input into 1 MiB outer blocks
(`DEFLATE_BLOCK_SIZE`, `:4792`) and resumes each next block at `block_end`.

The per-block encoders — `_deflate_compress_fixed_block` (`:4845`, levels 1–3) and
`_deflate_compress_dynamic_block` (`:5100`, levels 4–9) — deliberately match against the **full**
`src`, not just their slice. That is correct for compression ratio, but it means a match beginning
just below the boundary can extend up to `LZ77_MAX_MATCH` (258) bytes **past** `block_end`.

The chunker discards that overshoot and starts the next block at `block_end` regardless, so the
overshot bytes are encoded a second time. Both Huffman paths are affected, so lowering the
compression level is not an escape.

The streaming encoder does **not** have this bug: `_denc_consume` (`:5373`) stores the offset its
LZ77 loop actually reached back into the encoder context, so an overshoot carries into the next
consume instead of being re-encoded.

## Reproduction

Measured on a 2 MB input (stiva's regression harness):

```
input length        2000000
decoded length      2000220        <- 220 bytes too many
first divergence    offset 1048576 == DEFLATE_BLOCK_SIZE
gzip_decompress()   -5  (ERR_CHECKSUM_MISMATCH)
GNU gunzip          "differ: char 1048797"
```

Round-tripping a stream produced by GNU `gzip` through sankoch's decoder is byte-exact, which
isolates the fault to the encoder.

Minimal shape:

```
var src = <2 MiB of compressible bytes>
var out = alloc(cap)
var n = gzip_compress(src, 2000000, out, cap)     # succeeds
var back = alloc(4000000)
var m = gzip_decompress(out, n, back, 4000000)    # -5 ERR_CHECKSUM_MISMATCH
```

## Proposed fix

Have the chunker resume at the position the block encoder **actually reached**, not at the
precomputed `block_end` — i.e. give `_deflate_compress_fixed_block` /
`_deflate_compress_dynamic_block` a way to report their final input offset, and use it as the next
block's start. That is what `_denc_consume` already does on the streaming path, so the pattern
exists in the file.

(Speculation, flagged as such: an alternative is to clamp the match length so it cannot cross
`block_end`, but that would cost ratio at every boundary and diverges from the streaming path's
behaviour. Resuming at the true offset seems strictly better.)

## Consumer-side workaround (shipped)

stiva 3.0.14 routes both of its compress call sites (`image_import` and `_il_docker_add_layer`,
`src/imagelayout.cyr`) through a `_stor_gzip_compress` helper that drives the **streaming** encoder
— `gzip_enc_init` / `gzip_enc_write` / `gzip_enc_finish` — instead of the batch API. Note
`gzip_enc_init` takes sankoch's mutex and `gzip_enc_finish` releases it, so the helper must run
finish on every path including a write error.

Cost: compressing 2 MiB is ~42.7 ms streaming vs ~33.3 ms batch (~28% slower), paid once per import
rather than on any hot path. Output is marginally *smaller* (4904 vs 4943 bytes on that input) —
RFC 1951 caps back-references at 32 KiB regardless, so the 1 MiB outer chunk never bought extra
match reach to lose.

Any other consumer compressing more than 1 MiB through the batch API should assume its output is
corrupt and switch to the streaming encoder until this is fixed.

**Already-written data is not repaired by the workaround.** A blob produced by the batch encoder
stays corrupt, and in a content-addressed store its digest is over the bad bytes.
