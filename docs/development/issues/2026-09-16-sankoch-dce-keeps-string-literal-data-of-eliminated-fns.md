# `CYRIUS_DCE=1` removes an unreachable fn's code but keeps its string-literal data — OPEN

**Status:** 🟡 **OPEN** — design gap; measured on cycc 6.6.4.
**Placement:** unpinned — 6.x-line backlog (DCE / .rodata).
**Discovered:** 2026-09-16, by sankoch (2.8.0 Brotli decoder, 122,784-byte static dictionary).
**Severity:** Medium — binary size only, no correctness impact; but it makes large data literals in a
shared library a cost for every consumer that never uses them.
**Affects:** cycc 6.6.4 (measured); the x86 ELF, aarch64, PE and Mach-O fixups all copy the whole pool.

## Summary

DCE eliminates the code of a function no live code reaches, but the string literals that function
referenced stay in the output: the whole `str_data` pool is emitted as `.rodata`. A library that
embeds a large table as a literal therefore adds that table to every consumer binary, reachable or
not, DCE or not.

## Reproduction

```sh
python3 -c "
big = ''.join(chr(0x41 + (i*7) % 26) for i in range(100000))
open('dce_with.cyr','w').write('fn unused_table() { return \"' + big + '\"; }\nfn main() { return 0; }\nvar rc = main();\nsyscall(60, rc);\n')
open('dce_without.cyr','w').write('fn main() { return 0; }\nvar rc = main();\nsyscall(60, rc);\n')
"
for f in dce_without dce_with; do
  cycc < $f.cyr > $f.bin; CYRIUS_DCE=1 cycc < $f.cyr > $f.dce.bin
  echo "$f: plain $(wc -c < $f.bin) B, CYRIUS_DCE=1 $(wc -c < $f.dce.bin) B"
done
```

```
dce_without: plain 4456 B, CYRIUS_DCE=1 4456 B
dce_with: plain 104464 B, CYRIUS_DCE=1 104464 B      # expected ~4456 with DCE
```

(The literal is NUL-free on purpose, so this is independent of the interning alias bug filed as
`2026-09-16-sankoch-string-literal-interning-aliases-overlapping-storage.md`.)

## Root cause

`src/backend/x86/fixup.cyr` ~1029 / ~1238 (and the aarch64 / PE / Mach-O equivalents) copy the pool
wholesale:

```cyrius
while (i < spos) { store8(O + op, load8(S + 0x21A000 + i)); op = op + 1; i = i + 1; }
```

`rod_size = spos` — there is no per-literal liveness; string tokens carry `(offset << 32) | len`
but nothing records which offsets survive DCE.

Suggestion (speculation): record the referencing fn for each ESADDR fixup; when DCE drops a fn,
drop pool ranges referenced only by dropped fns and compact `.rodata` before relocation (interned
literals shared with live code must stay).

## Why this needs a fix

- **Consumer stopgap in production right now:** sankoch's full bundle (`dist/sankoch.cyr`, shipped
  as the stdlib's `lib/sankoch.cyr`) gains the Brotli decoder in 2.8.0. Measured: a zlib-only
  consumer built with `CYRIUS_DCE=1` grows **74,272 B → 197,080 B** purely from the unreferenced
  dictionary literal. sankoch accepts that cost in the full bundle and routes size-sensitive
  consumers to lean per-codec profiles (`[lib.zlib]` etc.) that exclude the dictionary.
- The same applies to any stdlib module that embeds data (fonts, unicode tables, test fixtures):
  consumers pay for bytes they cannot reach, and DCE is the switch they already flipped to avoid it.
