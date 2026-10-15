# cybs's preprocessor buffers are unchecked: an include over 2 MB that includes another file has its tail overwritten — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 infra lane (cybs.cyr @ 421a0db7, seed-assembled). Latent
for the inputs that matter: the largest file cybs includes for `src/main.cyr` is 300,447 B
(`src/backend/x86/emit.cyr`), the include depth is 2, and the expanded stream is ~1.7 MB.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13, checking that the token-position region 6.7.11 added at `r15 + 0xA000000` is free (it
sits where include depth 8's scratch would start).
**Severity:** Low — a silent bad input to the trust root's bootstrap compiler, latent (no shipped input is near any of
the caps), on the developer's own source (a bug, not a vulnerability).
**Affects:** `bootstrap/cybs.cyr` (not bisected; the layout predates 6.7.x).

## Summary

cybs's preprocessor reads each included file into a fixed scratch slot, `r15 + 0x9000000 + depth * 0x200000` (2 MB per
include depth; `pp_do_include`), with `pp_readfile` reading until EOF and no size check. A file over 2 MB runs into the
next depth's slot, and when it includes another file, that file is read into the next slot — over the tail of the
first file, which pp_expand is still walking. The same class: no depth cap (depth 8 reaches `0xA000000`, the 6.7.11
token-position region — dead while the preprocessor runs — and depth ~56 runs past the brk end), `read_input` stops at
15 MB and drops the rest of stdin with exit 0, and the 16 MB `expand_buf` (`0x8000000`) and the copy back to the 16 MB
input buffer are unbounded. Like [the seed's caps](2026-10-08-seed-asm-silent-caps-input-labels-code.md), none is
checked.

## Reproduction

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > cybs && chmod +x cybs
printf 'fn small() { return 1; }\n' > small.cyr
{ printf 'include "small.cyr"\n'; i=0; while [ $i -lt 33000 ]; do
    printf '# padding padding padding padding padding padding padding padding\n'; i=$((i+1)); done
  printf 'fn tail() { return 41; }\n'; } > big.cyr                   # 2,178,045 B
printf 'include "big.cyr"\nsyscall(60, tail() + small());\n' > main.cyr
./cybs < main.cyr > m; echo "cybs=$?"
# cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while,
#   an if-expression, unary minus, >>>, >>=), at: ng padding padding padding padding padding padding padding
# cybs=1          (6.7.10's cybs: "syntax error", exit 1)
build/cycc < main.cyr > mc && chmod +x mc && ./mc; echo "run=$?"     # run=42
```

The line cybs printed is not in big.cyr: small.cyr's 25 bytes were written over big.cyr at offset 2,097,152, the middle
of a comment line, so its `#` was gone. Where the overwrite lands on a line boundary the result parses, and the
program compiles from source the file does not contain.

## Root cause

- `pp_do_include` (`bootstrap/cybs.cyr`, the `add rsi, 0x9000000` / `shl rax, 21` block): the slot is
  `0x9000000 + depth << 21`, 2 MB; nothing bounds the file's size or the depth.
- `pp_readfile`: reads 1 MB at a time until EOF into the slot, unbounded.
- `read_input`: `mov rdx, 0xF00000` and stop — stdin past 15 MB is dropped, exit 0.
- `pp_expand` writes `expand_buf` (`0x8000000`, 16 MB, ending where slot 0 begins) and `pp_pre_copy` copies it back
  over the 16 MB input buffer, neither bounded.

## Proposed fix

Refuse, naming the cap: a file that does not fit its slot (read one byte past 2 MB), a depth past the slots, stdin past
15 MB, an expanded stream past 16 MB. Each refusal costs seed labels (cybs.cyr is at 506 / 512 after 6.7.11), so the
checks that do not fit ride the seed-rotation minor (roadmap_6.md). A cheap interim that needs no label, like gate row
S's CODE row: a row in `tests/gates/toolchain/cybs_call_arity_named.sh` that walks `src/main.cyr`'s include closure
and fails when a file reaches 2 MB, the depth reaches 8, or the expanded size reaches 15 MB.
