# The seed (`bootstrap/asm`) truncates input at 131,072 B, overruns its 512-label table and its 65,536 B CODE buffer — all unchecked — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b (seed sha256 `8e096b4a…fbd20a2`, ==
`bootstrap/SHA256SUMS`) with `repros/2026-10-08-seed-asm-silent-caps-input-labels-code.sh`: a 144,052 B input
assembles with exit 0 to a 130 B program that segfaults (its tail was dropped); 522 labels fail with `label not found:
lbl5` for a label that is defined; 80,000 B of code assembles with exit 0 to a program whose tail is replaced
(SIGSEGV). Latent today: `bootstrap/cybs.cyr` is inside all three (112,175 / 131,072 B, 501 / 512 labels, cybs's code
21,660 / 65,536 B).
**Placement:** unpinned — 6.x-line backlog — never 7.x. (a new seed binary is a new trusted root — the user's call)
**Discovered:** 6.7.6 Break 1 (roadmap commit a29d1492, 2026-10-08; the input cap was probed then — "3 bytes over
assembled a cybs 1 byte short, silently"); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — silent miscompilation by the trust root, latent (no shipped input is over a cap; two of the
three are guarded by a gate, the CODE cap is not).
**Affects:** `bootstrap/asm` as committed (built from `bootstrap/asm.cyr`; cybs reproduces it byte-identically).

## Summary

The seed assembles `bootstrap/cybs.cyr`, which compiles `src/` → gen1 → gen2 == `build/cycc`. Its fixed heap
(`bootstrap/asm.cyr:10–16`) has three caps and checks none:

1. **Input — 131,072 B.** The read loop stops at the cap and the rest of stdin is dropped with exit 0.
2. **Labels — 512 entries.** `ADDL` writes entry `lc` with no bound; entry 512+k lands on the NEXT table (LNPOS[512+k]
   = LNLEN[k], LNLEN[512+k] = LOFF[k]), so the earliest labels' name lengths and offsets are overwritten. Observed: a
   loud but false `label not found: lbl5`; past 1,024 entries the overlap reaches the offsets of later tables.
3. **CODE — 65,536 B.** `EB` stores at `S + 0x20000 + cp` with no bound. Past 65,536 the bytes overwrite the label
   tables (0x30000–0x33000; a later label lookup then fails or mis-resolves); past 77,824 the code region reaches OUT
   (0x33000), and `EELF`'s copy reads back bytes it has already overwritten — the emitted tail is a copy of earlier
   output, silently (observed: the final `mov`/`syscall` came out as `A` bytes).

Gate row S of `tests/gates/toolchain/cybs_call_arity_named.sh` guards (1) and (2) for `cybs.cyr` (size < 131,072,
labels ≤ 512). Nothing guards (3) — cybs's assembled code size against 65,536.

## Reproduction

```sh
sh docs/development/issues/repros/2026-10-08-seed-asm-silent-caps-input-labels-code.sh   # from the repo root
# control    src=     52 B  seed exit=0  emitted=   142 B  program exit=42
# input      src= 144052 B  seed exit=0  emitted=   130 B  program exit=139
# labels     src=  12850 B  seed exit=1  emitted=     0 B  stderr=[label not found: lbl5 ]
# code       src=  80081 B  seed exit=0  emitted= 80147 B  program exit=139
```

Expected: each over-cap input refused by the seed with a message naming the cap, exit non-zero, nothing emitted.

## Root cause

- Input: `bootstrap/asm.cyr:1080–1088` — `syscall(0, 0, S + bl, 131072 - bl)` until `bl >= 131072`, then `done = 1`;
  no probe for remaining input.
- Labels: `ADDL`, `bootstrap/asm.cyr:329–336` — stores at `S + 0x30000 / 0x31000 / 0x32000 + lc * 8`, no `lc < 512`.
- CODE: `EB`, `bootstrap/asm.cyr:78–85` — `store8(S + 0x20000 + cp, …)`, no `cp < 65536`; `EELF` (asm.cyr:1026–1058)
  then copies `cp` bytes from CODE into OUT (0x33000), which aliases CODE past 77,824 B.

## Proposed fix

Bounds checks in `asm.cyr` (refuse: read one more byte after the cap and fail if it arrives; `lc >= 512` in `ADDL`;
`cp >= 65536` in `EB`), and possibly larger regions. **Any of it is a new `bootstrap/asm` — a new trusted root, the
USER's call**: the closure step (`cybs(bootstrap/asm.cyr) == bootstrap/asm`, seed-derive step 2) means asm.cyr and the
committed binary change together, with `bootstrap/SHA256SUMS`. Until then, the cheap interim that needs no new seed:
add a CODE row to gate row S (cybs's assembled size − 120 B ELF header < 65,536 — today 21,660), so all three caps are
guarded for the one input that matters.
