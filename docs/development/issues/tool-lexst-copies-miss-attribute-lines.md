# cyaudit and cyrius_api_surface read an attribute line as a comment — the compiler does not

**Status:** 🟡 **OPEN**. The compiler half shipped in 6.6.20 (LEX-EXPR-02). These two tool-side copies of the preprocessor's state machine were left out of that lane's scope.
**Placement:** unpinned, 6.x-line backlog. Integration may pack it into 6.6.20 if the gate cycle allows.
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
