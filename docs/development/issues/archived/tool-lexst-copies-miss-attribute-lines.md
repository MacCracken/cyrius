# cyaudit and cyrius_api_surface read an attribute line as a comment — the compiler does not

**Status:** ✅ **RESOLVED in 6.7.3** (repair lane tool-lexst). Both copies take the attribute-line rule — see *Resolution* below. The compiler half shipped in 6.6.20 (LEX-EXPR-02).
**Placement:** 6.7.3 repair lane (user, 2026-10-07).
**Discovered:** 2026-10-06, during the 6.6.20 s-pplex review round (LEX-EXPR-02)
**Severity:** Low. A tool misreport, not a miscompile. The compiler refuses the include itself.
**Affects:** `programs/cyaudit.cyr` `_au_lexst`, and `programs/cyrius_api_surface.cyr` `_asf_lexst`. Present in every version that has them.

## Summary

6.6.20 changed the preprocessor's lexical state machine. A `#` that spells one of the lexer's
ten attribute words (`LEXATTRWORD` in `src/frontend/lex.cyr`) no longer opens a comment. The
lexer keeps reading that line as code, so the preprocessor now does too (`PP_LEXST_AT`).

Two tools carry their own copy of the old `PP_LEXST`, without that rule:

- `cyaudit` `_au_lexst`, which `scan_includes` uses to decide which `include` lines are directives.
- `cyrius_api_surface` `_asf_lexst`, which `_asf_body_close` uses to find a struct body's closing `}`.

Each copy reads an attribute line as a comment. If that line opens a string literal that spans
lines, the tool falls one quote out of step with the compiler for the rest of the file.

## Reproduction

```sh
printf 'fn f(): i64 { return 1; }\n#assert 1 == 1, "x\ny"\ninclude "lib/missing_mod.cyr"\nsyscall(60, f());\n' > t.cyr
cyaudit vet t.cyr          # "no dependencies", rc 0
build/cycc < t.cyr > t.bin # error: cannot open include file: lib/missing_mod.cyr
```

Without the `#assert` line, `cyaudit vet` reports `MISSING  lib/missing_mod.cyr` and exits 1, as it should.

## Root cause

`_au_lexst` / `_asf_lexst` move to state 3 (comment) on any `#` in code. `PP_LEXST_AT`
consults `LEXATTRWORD` first, and an attribute word keeps the line in code.

## Proposed fix

Give both copies the attribute rule. Keep the word list from drifting away from `LEXATTRWORD`:
either derive it in a gate, as `lexer_attribute_word_boundary.sh` already does for cyrlint,
cyrfmt and cyrdoc, or share one list that the compiler and the tools all include. That choice
is why this is filed rather than fixed in the LEX-EXPR-02 lane. Add a `cyaudit vet` row using
the repro above.

## Resolution (6.7.3)

**Copied, not shared** (the user's call): nothing under `src/` changed.

- `programs/cyaudit.cyr`: `scan_includes` walks with `_au_lexst_at`, which is `PP_LEXST_AT` over
  cyaudit's own ten-row `_au_attr_len` (a copy of `LEXATTRBOUND` / `_lex_attr_is` / `LEXATTRWORD`,
  with the same `(` rule).
- `programs/cyrius_api_surface.cyr`: `_asf_body_close` walks with `_asf_lexst_at`, which wraps the
  tool's existing `_asf_attr_len`. That adds no new list.

Measured on 6.7.2 → 6.7.3:

- **The repro above.** vet went from `no dependencies` (rc 0) to `MISSING lib/missing_mod.cyr`
  (rc 1). All ten attribute words behaved the same way.
- **deny.** With `include "../escape.cyr"` after the `#assert` line, deny went from `0 violations`
  (rc 0) to `DENY: parent traversal` (rc 1). The compiler says `path traversal rejected`.
- **The reverse direction.** The file is `#assert 1 == 1, "x` / `include "; var t2 = 0; var u2 = "` /
  `y";` / `syscall(60, 7);`. It compiles and exits 7. vet went from a false
  `MISSING  ; var t2 = 0; var u2 = ` (rc 1) to `no dependencies` (rc 0).
- **This repo.** vet and deny output over all 901 `.cyr` / `.tcyr` files in the tree is byte-identical
  before and after.
- **api-surface.** No valid program can observe this half: an attribute inside a `#derive` body never
  compiles. On the refused fixture the compiler's DCE list names `after_two gh_a gh_set_a`, and the
  6.7.2 tool added `ghost`.

Gates:

- `tests/gates/toolchain/cyaudit_include_directives.sh` axis 7 (26 → 44 checks). It derives the
  attribute words and their `(` rule from `LEXATTRWORD`'s rows in `src/frontend/lex.cyr` and holds
  `_au_attr_len` to them, which is the drift guard. Mutations M9–M12 are in its header.
- `tests/gates/frontend/lexer_attribute_word_boundary.sh` F8 / F8b (49 → 51 axes). Mutation M19.
