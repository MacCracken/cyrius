# String-literal interning aliases a literal onto pool storage that overlaps its OWN bytes — silent wrong data — OPEN

**Status:** 🟡 **OPEN** — reproduced on cycc 6.6.2, 6.6.3 and 6.6.4; no fix in tree.
**Placement:** unpinned — suggest the next 6.6.x repair release (same class as the 6.6.4 ≥ 64 KB literal fix).
**Discovered:** 2026-09-16, by sankoch (2.8.0 Brotli decoder work) — 4 of 109 embedded test-vector
literals failed their CRC-32; bisected to the lexer's interning loop.
**Severity:** **High** — silent miscompile of DATA: the build succeeds with no diagnostic, the
literal's address and length are plausible, and the bytes read back are another literal's.
**Affects:** cycc 6.6.2, 6.6.3, 6.6.4 (measured); likely every release since interning was added.

## Summary

When the lexer interns a new string literal L, it compares `slen + 1` bytes (L plus its NUL
terminator) against candidate offsets in `str_data`. The candidate window is allowed to run past
the start of L's own freshly written bytes. If L is periodic with a period whose position holds a
NUL, the comparison "matches" part of the previous literal plus L's own storage, L is aliased to
the earlier offset, `spos` is not advanced — and the NEXT literal is written over the bytes L now
points into. Reading L returns the next literal's bytes.

This is not limited to runs of zeros: a 15-byte alternating `07 00 07 00 … 07` lookup table read
back 13 wrong bytes.

## Reproduction

`intern.cyr` — all-NUL table after a literal ending in NUL:

```cyrius
fn a() { return "\x00\x00\x00\x00"; }
fn b() { return "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"; }
fn c() { return "\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD\xDD"; }
fn main() {
    var p = b();
    var i = 0;
    var bad = 0;
    while (i < 22) { if (load8(p + i) != 0) { bad = bad + 1; } i = i + 1; }
    load8(a()); load8(c());
    return bad;
}
var rc = main();
syscall(60, rc);
```

`intern2.cyr` — a non-degenerate alternating table:

```cyrius
fn a() { return "\x00\x07"; }
fn b() { return "\x07\x00\x07\x00\x07\x00\x07\x00\x07\x00\x07\x00\x07\x00\x07"; }
fn c() { return "QQQQQQQQQQQQQQQQQQQQQQQQ"; }
fn main() {
    var p = b();
    var i = 0;
    var bad = 0;
    while (i < 15) {
        var want = 7;
        if ((i & 1) == 1) { want = 0; }
        if (load8(p + i) != want) { bad = bad + 1; }
        i = i + 1;
    }
    load8(a()); load8(c());
    return bad;
}
var rc = main();
syscall(60, rc);
```

```
$ cycc < intern.cyr > intern.bin && ./intern.bin; echo $?
17        # expected 0 — 17 of 22 bytes are c()'s 0xDD
$ cycc < intern2.cyr > intern2.bin && ./intern2.bin; echo $?
13        # expected 0 — 13 of 15 bytes wrong
```

Control: change only `a()` to `return "zz";` → `intern2` exits **0**. Both repros exit 17 / 13
identically under `~/.cyrius/versions/6.6.2/bin/cycc` and `6.6.3/bin/cycc`. Both builds print no
warning.

## Root cause

`src/frontend/lex.cyr` ~2046–2071 (6.6.4), the interning loop:

```cyrius
var si = 0;
while (si < sstart) {
    var eq = 1;
    var sk = 0;
    while (sk <= slen) {
        if (load8(S + 0x21A000 + si + sk) != load8(S + 0x21A000 + sstart + sk)) { eq = 0; break; }
        sk = sk + 1;
    }
    if (eq == 1) { interned = si; si = sstart; }
    ...
```

The candidate range `pool[si .. si + slen]` is compared without requiring it to end before
`sstart`. With `d = sstart - si < slen + 1`, the comparison reads L's own bytes, so it succeeds
exactly when `L'[d-1] == 0` (the candidate must follow a NUL) and `L'` (L plus terminator) is
d-periodic. L is then aliased to `si`, `spos` is not advanced, and the next literal overwrites
`pool[sstart ..]` — which is where the aliased range's tail lives.

Suggested fix (speculation — the Cyrius agent verifies): only accept a candidate whose whole
compared window precedes the new literal, i.e. require `si + slen < sstart` (skip or stop the
candidate loop otherwise). A genuinely identical earlier literal always satisfies that, so
pointer-identity interning is unaffected.

## Why this needs a fix (and is not a sankoch-side quirk)

- It corrupts program DATA with no diagnostic, the same failure class as the 6.6.4 ⛔ ≥ 64 KB
  literal bug: rc=0, plausible pointer, wrong bytes.
- Binary lookup tables embedded as literals are the natural shape for codec tables, font data
  (rekha's `face_data.cyr`) and test vectors; runs of NUL and short periods are common in them.
- **Consumer stopgap in production right now:** sankoch 2.8.0 forbids NUL bytes in every string
  literal it ships except the Brotli static dictionary, whose generator proves the dictionary
  cannot satisfy the alias condition (every NUL position p: `data + b"\0"` is not (p+1)-periodic)
  and which a tcyr cell CRC-checks (`0x5136cb04`). The earlier test-vector workaround prefixed every
  literal chunk with a unique tag so no two literals could line up.
