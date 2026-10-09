# The lexer's `#`-attribute word list is hand-copied into six tools; five are held to `LEXATTRWORD` by no census — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 against 6.7.6 @ 2fb6ad8b by reading: `LEXATTRWORD`
(`src/frontend/lex.cyr:1024`) is the one list the lexer and the preprocessor share; six tools carry their own copy of
its ten rows, and only cyaudit's is compared with it (`tests/gates/toolchain/cyaudit_include_directives.sh` axis 7).
No gate derives the other five copies' rows from `LEXATTRWORD`.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.3 (cyaudit became the sixth mirror; roadmap commit 0619c262); filed 2026-10-08 from roadmap.md.
**Severity:** Low — no live divergence today; the defect is that the next attribute added to the lexer silently
desyncs five tools.
**Affects:** cyrlint, cyrfmt, cyrdoc, the `cyrius` CLI (srcscan), cyrius_api_surface — through 6.7.6.

## Summary

A `#` followed by one of ten attribute words (`assert`, `regalloc`, `deprecated`, `must_use`, `pure`, `io`, `alloc`,
`naked`, `inline`, `pe_import`; `(` is a boundary for `assert` / `deprecated` / `pe_import` only) is a TOKEN, not a
comment, and the lexer keeps lexing that line as code, strings included. Every tool that scans cyrius source must
know the same list, or it reads an attribute line as a comment and falls a quote out of step with the compiler (the
6.6.6 / 6.6.20 / 6.7.3 bugs). The copies:

| tool | copy | held to `LEXATTRWORD`? |
|---|---|---|
| `programs/cyrlint.cyr` | `_lx_attr_len` :175 (+ `_lx_attr_bound` :155) | no — group C probes words |
| `programs/cyrfmt.cyr` | `_cf_attr_len` :104 (+ `_cf_attr_bound` :89) | no — group C probes words |
| `programs/cyrdoc.cyr` | `_doc_attr_len` :85 (+ `_doc_attr_bound` :73) | no — group C probes words |
| `cbt/srcscan.cyr` | `_src_attr_len` :54 (+ `_src_attr_bound` :43) | no — group C probes words |
| `programs/cyrius_api_surface.cyr` | `_asf_attr_len` :270 (+ `_asf_attr_bound` :260) | no — group F probes words |
| `programs/cyaudit.cyr` | `_au_attr_len` :108 | yes — `cyaudit_include_directives.sh` axis 7 |

`tests/gates/frontend/lexer_attribute_word_boundary.sh` B0 is a census of `lex.cyr`'s token table against
`LEXATTRWORD`'s rows and the gate's probe table — the compiler side only. Its groups C / F probe chosen words
(`#ioctl`, `#io(fd)`, `#naked`, `#inline`, `#deprecated(`) through each tool; a word added to the lexer (and to the
probe table) is never asked of the five mirrors.

## Reproduction

```sh
grep -n 'pe_import' programs/cyrlint.cyr programs/cyrfmt.cyr programs/cyrdoc.cyr cbt/srcscan.cyr \
    programs/cyrius_api_surface.cyr programs/cyaudit.cyr          # six hand-written rows
grep -rn '_lx_attr_len\|_cf_attr_len\|_doc_attr_len\|_src_attr_len\|_asf_attr_len' tests/gates scripts programs/checks
# -> comments only; no gate compares these rows with LEXATTRWORD
```

Expected: adding an eleventh attribute to `LEXATTRWORD` turns a gate RED until every scanner knows it. Actual: only
`lexer_attribute_word_boundary.sh` B0 (its probe table) and cyaudit's axis 7 notice; cyrlint, cyrfmt, cyrdoc, srcscan
and api-surface keep reading the new attribute's line as a comment.

## Root cause

Each tool was given a copy so it "builds from anywhere" (the cyaudit comment, `programs/cyaudit.cyr:72-82`); the census
that keeps a copy honest was added only for cyaudit (6.7.3).

## Proposed fix

Either (a) move `LEXATTRWORD` (with `_lex_attr_is` / `LEXATTRBOUND`) into an includable pure file under `src/` that the
compiler forks and the six tools all include — the roadmap records this as measured byte-identical on all seven
compiler forks (not re-measured here), or (b) give each of the five tools cyaudit's census: derive the word list and the
`(` rule from `LEXATTRWORD`'s rows and compare each tool's rows to it in `lexer_attribute_word_boundary.sh`. (a)
removes the drift; (b) only detects it.
