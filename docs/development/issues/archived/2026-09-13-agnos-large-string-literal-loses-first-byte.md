# A string literal of even length ≥ 65536 is emitted shifted by one byte (first byte lost) on alternate literals — FIXED v6.6.4

**Status:** ✅ **FIXED in v6.6.4** — `src/frontend/lex.cyr` packed every string token as
`(pool offset << 16) | length`; a length ≥ 65536 OR-ed its high bits into the offset. Widened to
`(offset << 32) | length` in the producer and its four decoders. The repro exits 0; gated by
`tests/tcyr/frontend/string_literal_64k.tcyr` (6.6.3 fails 8 of 12). ⚠ The "even length" /
"odd-indexed" narrative below is an artefact of the pool layout: it is the literal whose own
pool OFFSET has bit 0 clear (bit 1 for ≥ 128 KB) that shifts — OR, not add — which is also why
131072 hit `lit0`. A same-class cx defect was found and fixed alongside (addresses past 0xFFFF
patched a `movhi` that was never emitted; `tests/gates/codegen/cx_addr_past_64k.sh`).
**Placement:** reproduced identically on **6.6.3**, **6.6.1** and **6.6.0** (rc=2 on each); not bisected further — the consumer
had never emitted a literal this large before, so no regression window is claimed.
**Discovered:** 2026-09-13, by an FNV‑1a‑64 of the assembled bytes disagreeing with the source file.
**Severity:** High — **silent.** `rc=0`, no diagnostic, the byte COUNT is intact; only the CONTENT is
wrong, and the wrong content is a plausible one-byte shift of the right content. Nothing short of
hashing the bytes detects it.

## Summary

```cyrius
fn lit0() { return "Aaaaa…"; }   # 65536 bytes — intact
fn lit1() { return "Xbbbb…"; }   # 65536 bytes — load8(lit1()) == 'b', NOT 'X': shifted by one
fn lit2() { return "Ycccc…"; }   # 65536 bytes — intact
```

The second literal comes back as its own bytes **minus the first one** (its last byte is the byte
that followed it — the terminating NUL — so a length-aware reader sees every byte moved down by one).

## Measured matrix

Same three-literal program, one literal length per row, raw printable bytes (no escapes — the
`\x##` form reproduces identically, which is how it was found):

| literal length | result |
|---|---|
| 65534 (even, < 64 KB) | all intact |
| 65535 (odd) | all intact |
| **65536 (even)** | **lit1 shifted** |
| 65537 (odd) | all intact |
| **65538 (even)** | **lit1 shifted** |
| 70001 (odd) | all intact |
| **70000, 100000 (even)** | **odd-indexed literals shifted** |
| **131072 (even)** | **lit0 shifted** |

Bisected over 4096…131072 on a 410,820-byte file split into equal chunks, checking each chunk's
FNV‑1a against Python: with chunk 65536 the bad chunks were **1, 3, 5**; with 70000, **1, 3**;
with 131072, **0**. Every odd chunk length and every length below 65536 (down to 4096) was
byte-exact for all 101 chunks.

⚠ The pattern that fits every row: literals are NUL-terminated in the pool, so an even-length
literal occupies an **odd** number of bytes and puts the NEXT literal at an odd pool offset; a
literal of ≥ 64 KB that starts at an odd offset is the one that loses its first byte. (131072
puts lit0's *successor* at an odd offset, but lit0 itself was the one reported bad — so the
hypothesis is not complete; it is offered as a lead, not a diagnosis.)

## Why it matters

`\x##` literals are the only way to carry binary data in a freestanding module (kernel:
`[deps] stdlib = []`), and the natural shape is one big literal. rekha now chunks at 4096 bytes
**and** ships the whole-face FNV‑1a so the consumer verifies what it assembled — that workaround is
in `rekha/scripts/face2cyr.py` with this filing named. Any other consumer that writes a ≥ 64 KB
literal gets silently wrong bytes and no way to notice.

## Suggested gate

A tcyr that emits two 65536-byte literals and asserts `load8` of each literal's first byte —
the repro is exactly that and can be dropped in as-is. Add one 131072 row for the lit0 case.
