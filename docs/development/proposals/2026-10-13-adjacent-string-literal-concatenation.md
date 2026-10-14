# Adjacent string-literal concatenation — `"abc" "def"` is one literal

**Filed:** 2026-10-13 from klug 0.2.1 (the audit pass of its 6.6.6 → 6.6.20 pin bump)
**Status:** 🟡 **PROPOSED** — an ergonomics gap with measured consumer workarounds, not a capability gap.
**Placement:** Unplaced — only the user places it.
**Severity:** Quality-of-life. Nobody is blocked, but every consumer that writes a long message, help text or test
fixture has to choose between a lint warning, a `#skip-lint` that mutes every rule on the line, text assembled at run
time, or wording cut down to fit the column.
**Affects:** `src/frontend/lex.cyr`, the string-literal arm of `LEX`. One concentrated change. No token-stream, parser,
IR or backend change, so every target inherits it. Tooling follow-ups: `programs/cyrfmt.cyr` (continuation indent)
and `programs/cyrlint.cyr` (an optional same-line warning).

## Summary

Cyrius has no way to split one string literal across source lines without changing its bytes:

- `\<LF>` **keeps** its LF. That is the v6.5.18 contract, gated by `tests/gates/toolchain/cyrfmt_string_continuation.sh`,
  and it stays.
- A raw LF inside a literal is a byte of the literal (6.6.11 counts the line).
- Two literals side by side are a parse error: `expected ';', got string` (6.6.20).

This proposal asks that two or more string literals separated only by whitespace lex as **one** literal: the bytes of
each piece in order, then one NUL terminator. C, C++, Python and D all spell it this way.

```cyrius
help_operands("With no operand, reads stdin. With several, a total line is printed. "
  "With no count option, lines, words and bytes are shown.");

var usage = "usage: klug [-w|--warn] [-e|--err] [-h|--help]\n"
    "  (no flags)   dump the whole kernel log\n";
```

## Motivation — the measured tax

`cyrlint` warns on any line over 120 characters (`programs/cyrlint.cyr:1233`), and `cyrius audit` reports every one
in its lint count. A literal longer than the space left on its line has no compliant spelling. What consumers do instead:

1. **`#skip-lint`.** It covers 536 code lines that hold a literal, in 23 repos (itihas 358, kriya 51, cyrius 24,
   bayan 18, varna 18, agnos 14, mabda 14, …). kriya's `help_operands("…")` lines are typical:

   ```cyrius
   help_operands("With no operand, reads stdin. With several, a total line is printed. With no count option, lines, words and bytes are shown.");  #skip-lint
   ```

   ⚠ `#skip-lint` "exempts [the line] from all rules" (`docs/guides/cyrius-guide.md:4339`). To dodge the column rule
   it also turns off every other check on that line, so it costs more than a column rule should.
2. **Runtime assembly.** klug 0.2.1's test suite builds three fixture logs with a `_cat(a, b)` helper: a 512-byte
   static buffer plus `memset`/`memcpy` at run time, written only so that no source line passes 120 columns. That is
   run-time code and a buffer cap paid for a formatting rule.
3. **Living with the warnings.** klug 0.2.0 shipped 13 column warnings in `tests/klug.tcyr`. Across `~/Repos`
   (excluding vendored `lib/`, `build/`, `dist/` and `archived/`), 21,918 code lines are over 120 characters and hold
   a literal of at least 30 characters, in 1,660 files and 73 repos. This is a heuristic scan, and generated tables
   (agnos, aethersafha, thoth) account for much of it, but the shape is everywhere.
4. **Shorter text.** You can't count this one, but it's real: diagnostics and help get terser to fit the column, and
   those messages are what an operator reads when something has gone wrong.

## Proposed semantics — hard rules

1. **Each piece is a complete literal, escapes resolved, before it joins.** A piece boundary can never complete or
   extend an escape. C's `"\x41" "B"` trap does not exist here, because `\x` takes exactly two hex digits inside its
   own piece. `"\x4" "1"` is still the `\x escape: bad hex digit` error.
2. **Only whitespace may sit between pieces**: space, tab, CR, LF. A comment, a directive or any other `#` line between
   two pieces **ends the join**, and the next `"` is the same parse error as today. This rule is what keeps the change
   from reopening two fixed bug classes:
   - The lookahead can never cross a `#@file` marker (where an included file ends: the 6.6.12
     unterminated-at-marker class) or an `#ifdef` / `#endif` line.
   - The preprocessor's string state machine (`PP_LEXST`) sees exactly what it sees today: each piece opens and closes
     on its own, and nothing between the pieces is for it to classify. The 6.6.20 PP/lexer string-state desync (the
     `#@file` forge via an attribute line's literal) cannot come back through this door.
3. **Attribute lines do not join across their LF.** An attribute line (`#assert cond, "msg"`) is lexed as code on its
   own line (6.6.20). Pieces on that line may join; the scan stops at the line's LF, because the preprocessor owns the
   line structure of `#` lines.
4. **Line accounting.** The joined token keeps the FIRST piece's opening line, as a literal with a raw LF does today
   (6.6.11). LFs between pieces count as lines. An unterminated later piece is reported at its own opening quote.
5. **One NUL, one intern.** The terminator is written once, after the last piece. `_lex_intern` (6.6.19) runs once on
   the joined bytes, so `"ab" "c"` and `"abc"` are the same pointer, as two identical literals are today.
6. **The 2 MB `str_data` cap** applies to the joined bytes. The arm's existing per-byte check already enforces it.
7. **Character literals never join.** A `'x'` next to a string is not a join.
8. **Preprocessor operands are out of scope.** `include` paths, `#define` bodies and `#@file` markers never reach this
   arm and stay single-literal. If the preprocessor does not already refuse `include "a" "b"` by name, it should.
   Silently ignoring the second literal would be the worst outcome.

## Implementation sketch

All in `LEX`'s string arm (`src/frontend/lex.cyr`, the `else { if (c == 34) {` branch):

- At the closing quote (`if (sc == 34) { p = p + 1; sgo = 0; }`), call a helper before ending, something like
  `_lex_str_join(S, p, in_attr)`. It scans forward over space / tab / CR / LF and stops at the LF when `in_attr`. If the
  next byte is `"`, it returns the offset just past that quote plus the number of LFs it crossed. Otherwise it returns
  -1.
- On a join, commit the LF count (`SCLINE(S, GCLINE(S) + n)`), set `p` past the new opening quote, and leave `sgo = 1`
  and `spos` alone. The next piece's bytes append in place, and the NUL-plus-intern block below the loop runs once,
  unchanged.
- ⚠ **Commit the LFs only when the join happens.** On no join, `p` stays just past the closing quote and LEX's normal
  whitespace path counts those LFs. Counting them in both places would shift every later line number.
- Keep the scan in its own fn. The arm's comments already cite the cybs per-fn cap for the same reason
  (`_lex_unterm_str`, `_lex_str_lf`).

## Bootstrap

`src/` and the parts of `lib/` that are compiler source (`lib/alloc.cyr` is included by all seven `src/main*.cyr`)
cannot use the form until the seed → cybs → cycc chain lexes it. Land it in cycc, and in cybs if cybs lexes string
literals itself, and keep compiler source off it until the chain carries it. That leaves self-compile byte-identical,
which is itself a gate. Consumers can use it from the shipping release, behind their pin. A `dist/` bundle that uses it
needs its consumers on at least that pin, under the existing pin-floor rules.

## Tooling

- **cyrfmt** — inside parens, the continuation line of a join already formats correctly: the paren-depth rule (2 per
  open paren, 4 accepted) applies, and multi-line calls are verified at 6.6.20. At depth 0 (`var s = "a"<LF>"b";`)
  fmt needs a rule. Proposed: one continuation step, +4, matching the accepted alternative. fmt must never join or
  split pieces itself: the bytes belong to the author.
- **cyrlint** —
  - Warn on same-line adjacency (`"a" "b"` on one line). It is never needed to fit the column, and it is exactly the
    shape of a missing comma.
  - Leave the 120-column rule unchanged. The join is the fix.
  - Optionally, note a `#skip-lint` line that is long only because of a literal ("split the literal instead"), so the
    536 can be retired.
- **cyrius-lsp, cyrdoc, vet, coverage, and the tools with their own lexers** (cf.
  `issues/2026-10-08-attribute-word-list-hand-kept-in-five-tools.md`) — no change needed unless a tool reports literal
  values. Each piece is a complete `"…"` span, so tokenizers that skip string spans work as before. `coverage`'s
  whole-identifier rule (6.6.8) already skips literals.

## Hazards, and what bounds them

- **Missing comma.** `f("a" "b")` written for `f("a", "b")`. Direct calls are arity-checked at compile time
  (`'two' expects 2 arguments, got 1`, verified 6.6.20), so most such typos become an arity error. Single-line typos
  are caught by the lint warning above. What remains is a multi-line missing comma into a call that is not
  arity-checked (`fncallN` / `&fn` dispatch). That is real but narrow; the lint could flag a join that is an argument
  of an `fncallN`.
- **Escape across a boundary:** impossible by rule 1.
- **Preprocessor desync, and crossing an include boundary:** impossible by rules 2 and 3.

## Alternatives considered

- **`\<LF>` that drops the LF** (C's line splice). It reverses the 6.5.18 contract and silently changes the meaning of
  every existing literal that uses it. No.
- **Raw or multi-line string syntax** (`"""…"""`, `r"…"`). It solves embedding a block of text, not splitting a
  one-line message: the bytes still carry the LFs.
- **A `concat("a", "b")` builtin or const-eval.** Heavier than juxtaposition, noisier at every call site, and
  unfamiliar. Juxtaposition is what every C-family reader already knows.
- **Raise the lint column.** That only moves the line.
- **`#skip-lint`.** That is the status quo, and it disables every rule on the line.

## Consumer-side workaround (today)

- For test fixtures, assemble at run time from two literals. klug 0.2.1, `tests/klug.tcyr`, `_cat`:

  ```cyrius
  var _cat_buf[64];        # 512 B: a test log assembled from two literals, so no line passes 120 columns

  fn _cat(a, b): i64 {
      var na = strlen(a);
      memset(&_cat_buf, 0, 512);
      memcpy(&_cat_buf, a, na);
      memcpy(&_cat_buf + na, b, strlen(b));
      return &_cat_buf;
  }
  ```

- For production messages, either `#skip-lint` (with the all-rules cost above) or shorter text.

## Acceptance (proposed gate rows)

- **Byte-exact.** These must equal the single-literal spelling, by `strlen` / `memeq` and by pointer identity
  (interning): `"ab" "c"`, `"ab"<LF>"c"`, `"ab"<CR><LF><TAB>"c"`, three pieces, empty pieces (`"" "x" ""`), and
  pieces that carry `\0`, `\n`, `\x41` and `\u{1F600}` on either side of a boundary.
- **Diagnostics.**
  - An error two lines below a three-line join names the right line.
  - An unterminated second piece is named at its own quote.
  - `"a" # c<LF>"b"` gives today's `expected ';', got string` (no join across a comment).
  - `"\x4" "1"` gives the bad-hex-digit error.
- **Preprocessor.**
  - An `#ifdef` / `#endif` between pieces means no join.
  - An included file whose last token is a literal, followed in the includer by a literal, does not join across the
    `#@file` marker.
  - `#assert 1 == 1, "a" "b"` joins; `#assert 1 == 1, "a"<LF>"b"` does not.
- **Mutants that must go red.** LFs counted on every scan (line numbers drift); a NUL written per piece (`strlen`
  stops early); a scan that crosses `#` (the preprocessor rows); a join across the attribute-line LF.
- **Self-compile.** cycc byte-identical (compiler source does not use the form).
