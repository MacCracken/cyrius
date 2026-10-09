# cybs reports a bare "syntax error" (or "undefined variable") with no file, line or construct — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with cybs assembled from the seed
(`bootstrap/asm < bootstrap/cybs.cyr`, == `build/cybs`): each construct below exits 1 with the single line `syntax
error` — no file, no line, no token, no name of the construct; a top-level `const` and an undefined function called
in an expression print a bare `undefined variable`.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.6 Break 1 (roadmap commit a29d1492, 2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Low — every case is refused; nothing miscompiles. The cost is time: a cycc-only construct that reaches
`src/` fails seed-derive (release gate step 2) with two words for a 1.7 MB input spliced from 20+ files.
**Affects:** `bootstrap/cybs.cyr` as of 6.7.6 (not bisected; its token tables carry no source position).

## Summary

cybs (the hand-assembly bootstrap compiler the 29 KB seed assembles) supports a subset of cyrius. When `src/` uses
syntax outside it, cybs prints `syntax error` and exits 1. Only two refusals are named — a lone `!` and an unlexable
byte (6.7.6; `err_bang` / `err_char`, cybs.cyr:5523–5525); the rest are not.

| construct | cybs 6.7.6 |
|---|---|
| `const N = 3;` (top level) | `undefined variable` |
| `const N = 3;` (in a fn) | `syntax error` |
| `loop { … }` | `syntax error` |
| `do { … } while (c);` | `syntax error` |
| `var x = if (a == 1) { 3 } else { 4 };` | `syntax error` |
| unary minus: `-a`, `-3` | `syntax error` |
| `a >>> 2` | `syntax error` |
| `a >>= 2` | `syntax error` |
| `var x = nosuch(1);` (undefined fn) | `undefined variable` |
| a syntax error anywhere (e.g. `fn bad( { }` after valid code) | `syntax error` |

## Reproduction

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > cybs && chmod +x cybs
printf 'fn main() { var x = 0; loop { x = x + 1; if (x == 3) { break; } } return x; }\nvar r = main();\nsyscall(60, r);\n' > l.cyr
./cybs < l.cyr > /dev/null; echo $?
# 6.7.6: "syntax error", exit 1     expected: e.g. "cybs: src/x.cyr:1: `loop` is not supported by the bootstrap compiler"
```

(The other rows: substitute the construct into `fn main() { … }`.)

## Root cause

- `parse_err` (`bootstrap/cybs.cyr:4567`) writes the 13-byte `err_syntax` string (cybs.cyr:5519) and exits; every
  unsupported construct reaches it with no context. `err_undef` (cybs.cyr:5521) is the same for a name miss.
- cybs keeps no source position per token: token types live at `r15 + 0x1400000`, values at `r15 + 0x2400000`
  (`peek_tok_type` / `peek_tok_value`, cybs.cyr:4574–4597) and there is no offset or line array, so it has nothing to
  print. Its input is the preprocessed stream (`pp_expand` splices includes), so a line number would also need the
  include boundaries to name a file.

## Proposed fix

(a) Name the unsupported constructs as 6.7.6 did for `!`: a keyword check where `const` / `loop` / `do` / an `if` in
expression position / a leading `-` / `>>>` / `>>=` is met, each "cybs: `X` is not supported by the bootstrap
compiler; write …" (the cheap half — a few strings and branches). (b) A position: record each token's byte offset in
the expanded stream in a third parallel array, print the expanded-stream line on `parse_err` / `err_undef`, and the
token's text; mapping to `file:line` needs the include boundaries pp_expand already walks. Both are bounded by the
seed's caps — cybs.cyr is at **501 / 512 labels** and **112,175 / 131,072 input bytes** (gate row S,
`tests/gates/toolchain/cybs_call_arity_named.sh`; see `2026-10-08-seed-asm-silent-caps-input-labels-code.md`), so
the label budget decides how much of (b) fits. Seed-derive + closure after. No change to what cycc compiles.

## Seed headroom (2026-10-09)

Changing `bootstrap/cybs.cyr` needs no new seed, but the seed assembles it under three unchecked caps; the label
table is the tight one (501 / 512). Size this fix's new labels against that headroom before placing it: if it needs
more than is left, it rides the seed-rotation minor (roadmap_6.md § *A seed-rotation minor*), never a patch.
