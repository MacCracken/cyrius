# A comment that starts with an attribute name (`#ioctl …`, `#allocator …`) does not compile — FIXED

**Status:** ✅ **FIXED in 6.6.6 (bite 5)** — pre-existing (identical at 6.6.4); found while fixing 6.6.5 bite 9
(review round 2), where cyrlint and cyrfmt were taught to read attribute tokens the way the
lexer does.
**Placement:** unpinned — 6.x line (lexer). Not parked to 7.x.
**Discovered:** 2026-09-19.
**Severity:** Low–Medium — never silent in the measured cases (every one is a compile error),
but the diagnostic points at the comment's second word ("expected '=', got identifier
'numbers'"), not at the cause, and the set of words that break a comment is invisible.
**Affects:** `src/frontend/lex.cyr` — the `#` branch of the main lexer loop (the `#assert`,
`#regalloc`, `#deprecated`, `#must_use`, `#pure`, `#io`, `#alloc`, `#naked`, `#inline` and
`#pe_import` checks), every fork.

## Reproduction

```sh
printf '#ioctl numbers\nvar A = 1;\nsyscall(60, A);\n' | ./build/cycc > /tmp/p
# error:<source>:1:8: expected '=', got identifier 'numbers'
```

Measured at 6.6.5 with `build/cycc` (each line is the first line of a 3-line program):

| comment | result |
|---|---|
| `#ioctl numbers` | error: expected '=', got identifier 'numbers' |
| `#allocator notes` | error: expected '=', got identifier 'notes' |
| `#inlined by hand` | error: expected '=', got identifier 'by' |
| `#assertion holds` | error: #assert: expected number or sizeof() |
| `#purely local` | error: expected '=', got identifier 'local' |
| `#naked-eye check` | error: unexpected '-' |
| `#iota` | error (at the NEXT line: expected '=', got var) |
| `# ioctl numbers` | compiles |

## Cause

Each attribute check compares the bytes after `#` and, on a match, emits the token and keeps
lexing the SAME line — with no word boundary after the name. So `#ioctl` is `HASH_IO` + the
identifier `ctl`, and the rest of the "comment" is parsed as code.

## Fix direction

Require a non-identifier byte (or end of input) after the attribute name before emitting the
token; otherwise take the regular-comment path. Strictly more permissive — no program that
compiles today can contain `#io<ident-byte>`, because the tail is parsed as code and fails —
so nothing that builds changes meaning. `programs/cyrlint.cyr` (`_lx_attr_len`),
`programs/cyrfmt.cyr` (`_cf_attr_len`) and `programs/cyrdoc.cyr` (`_doc_attr_len`, bite 9 review
round 3) mirror the lexer's CURRENT prefix match on purpose and must take the same boundary in
the same change; `tests/gates/toolchain/cyrlint_cross_line.sh`
axes 8 and 13 pin the attribute reading.

## Acceptance

- Each commented line in the table above compiles, on every fork (x86, aarch64, PE, Mach-O,
  cx), and a program built with them is byte-identical to one with a space after the `#`.
- `#naked fn f() {`, `#inline fn g()`, `#pure`/`#io`/`#alloc`/`#must_use`/`#regalloc` before a
  fn, `#deprecated("…")`, `#assert …` and `#pe_import(…)` still arm exactly as before (an
  existing .tcyr per attribute stays green; `tests/tcyr/codegen/naked_fn_attribute.tcyr` on the
  cross-OS hosts).
- `_lx_attr_len` (programs/cyrlint.cyr), `_cf_attr_len` (programs/cyrfmt.cyr) and
  `_doc_attr_len` (programs/cyrdoc.cyr) take the same boundary; `tests/gates/toolchain/cyrlint_cross_line.sh` gains a row where `#ioctl notes` is a
  comment to both tools.
- `sh scripts/seed-derive-cycc.sh` stays machine-derivable.

## Why it was not packed into bite 9

Bite 9 is the cyrlint fix (no `src/` change). This one is a lexer change in the big
`#`-branch of the main lexer function — the seed compiler `cybs` fails SILENTLY on too many
refs in one function — so it needs its own seed-derive, full self-host and cross-OS cycle, and
a gate proving each attribute still arms on all targets while the prefixed comments compile.

## Corrections to this filing

Two places where the filing was wrong or incomplete, recorded because the fix had to
depart from it:

1. **The proposed boundary would not have satisfied the filing's own acceptance.** "Fix
   direction" says *require a non-identifier byte (or end of input) after the attribute
   name*. `-` is not an identifier byte, so under that rule `#naked-eye check` — row 6 of
   the filing's own table, which the Acceptance section requires to COMPILE — would still
   arm `#naked` and still fail with `unexpected '-'`. The boundary shipped is an
   ALLOWLIST: whitespace, end of input, or `(` (the only byte that legitimately follows
   `#deprecated` / `#pe_import`). That is what makes every row of the table compile. It is
   still strictly more permissive than the old prefix match, for the reason the filing
   gives.

2. **The acceptance asked for the new coverage as a row in
   `tests/gates/toolchain/cyrlint_cross_line.sh`.** It landed instead as a dedicated gate,
   `tests/gates/frontend/lexer_attribute_word_boundary.sh`, which covers the compiler and
   all three mirror readers (cyrlint, cyrfmt, cyrdoc) in one place — including the
   over-correction axis that cyrlint must still read `#naked fn f() {` as an attribute.
   Putting the compiler's boundary inside a cyrlint gate would have filed the lexer's
   coverage under the linter's name.

Also worth recording: the filing lists `#deprecated` as checked before `#must_use` "so
`#deprecated` doesn't trigger the lexer prefix check for `#must_use`". That ordering was
never load-bearing (`d` vs `m`), and with the boundary in place no attribute's prefix can
reach another's, so ordering is now purely cosmetic.

**Verification:** the filing's repro passes verbatim; all seven rows of its table compile
and each produces a binary BYTE-IDENTICAL to the same program written with a space after
the `#`. Self-host fixpoint + `seed-derive-cycc.sh` green; 0 of 330 pre-existing `.tcyr`
binaries changed a byte. Gate: `tests/gates/frontend/lexer_attribute_word_boundary.sh`
(22 axes, 6 mutations each RED). Cross-host: `tests/tcyr/crossos/attribute_word_boundary.tcyr`.
