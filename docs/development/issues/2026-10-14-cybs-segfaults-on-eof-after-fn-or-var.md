# cybs segfaults with no message when the input ends right after `fn` or `var` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 infra lane (cybs.cyr @ 4e5d1f90, seed-assembled, 22,320 B)
and on the slot-open cybs (0f733aea's `bootstrap/cybs.cyr`, seed-assembled, 21,780 B): identical, so it predates
6.7.11. Latent: cybs only ever compiles `src/` and `bootstrap/asm.cyr`.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 infra review) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 infra lane's review, probing end-of-input shapes for the cybs bare-syntax-error
item (`issues/archived/2026-10-08-cybs-bare-syntax-error-no-location.md`, decision A). That item's table uses `fn bad( { }`,
not a keyword at the very end of the input, so this shape is beyond its filed surface.
**Severity:** Low — a crash (exit 139, nothing on stderr) on the developer's own malformed input to the bootstrap
compiler; no shipped input reaches it (a bug, not a vulnerability).
**Affects:** `bootstrap/cybs.cyr` (not bisected; pass 0's shallow scan predates 6.7.x).

## Summary

When the input ends right after the keyword `fn` or `var` (with or without trailing whitespace), cybs dies with
SIGSEGV, writes nothing and prints nothing. One more token (`fn main`, `var x`) gets the 6.7.11 class message with
its line and exit 1, as every other syntax error does. cycc refuses all of these with a located error.

## Reproduction

```sh
cat bootstrap/cybs.cyr | bootstrap/asm > cybs && chmod +x cybs
for inp in 'fn' 'var' 'fn ' 'fn main' 'var x'; do
  printf '%s' "$inp" > in.cyr; ./cybs < in.cyr > out.bin 2> err.txt
  printf '%-9s rc=%s out=%sB stderr=%s\n' "'$inp'" $? $(wc -c < out.bin) "$(tr '\n' '|' < err.txt)"
done
```

Output on the lane's cybs:

```
'fn'      rc=139 out=0B stderr=
'var'     rc=139 out=0B stderr=
'fn '     rc=139 out=0B stderr=
'fn main' rc=1 out=0B stderr=cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=), at: fn main|
'var x'   rc=1 out=0B stderr=cybs: syntax error, or a construct the bootstrap compiler does not support (const, loop, do/while, an if-expression, unary minus, >>>, >>=), at: var x|
```

The slot-open cybs gives the same three `rc=139` lines (and a bare `syntax error` for the last two).

Expected: exit 1 and the class message `at:` the last line (`fn` / `var`), nothing written — the end-of-input
behaviour decision A already gives `fn main() {` at the end of the input and a last line with no trailing LF.

## Root cause

Pass 0 (`parser` → `pass0_loop` in `bootstrap/cybs.cyr`) registers fns and globals with `shallow_fn` and
`shallow_global`, which consume the keyword AND the name with unconditional `inc r11` — they never check that the
token after `fn` / `var` is an IDENT. When the keyword is the last token, the name `inc r11` steps over the EOF token
(type 12), and every later EOF test (`skip_one_item`'s loop, `pass0_loop`) reads token slots past the end of the
token array and never sees EOF; cybs runs off into unmapped memory. The full parser (`parse_fn_def`,
`parse_var_stmt`) does check for IDENT and reaches `parse_err`, but pass 0 runs first.

Fix shape: in `shallow_fn` / `shallow_global`, test the name token's type before consuming it (not an IDENT -> stop
pass 0's item without stepping past EOF, so the full parse reports it through `parse_err`), or have `peek_tok_type`
clamp at the EOF index. Gate rows: the three crashing inputs above give rc 1, the class message, `at: fn` / `at: var`,
and nothing written (`tests/gates/toolchain/cybs_diagnostics_named.sh`); seed-derive and the closure unchanged.
