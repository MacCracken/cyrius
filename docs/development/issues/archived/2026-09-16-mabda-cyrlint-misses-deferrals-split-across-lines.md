# cyrlint's untracked-deferral check misses a multi-word term wrapped across two comment lines — FIXED

**Status:** ✅ **FIXED in 6.6.5 (bite 9)** — with a different pointer scope than proposed here,
and together with three siblings of the same per-line shape (one of them a real silent zero).
See "Corrections to this filing" at the bottom.
**Placement:** shipped — `CHANGELOG.md` [Unreleased]/6.6.5; gate
`tests/gates/toolchain/cyrlint_cross_line.sh`.
**Discovered:** 2026-09-16, mabda 4.1.3 deferral audit. `cyrlint --strict-deferrals` reported 0
untracked deferrals across mabda's 186 files while three untracked ones sat in `src/`, each
wrapped across a line break.
**Severity:** Low. It hides deferral markers from the gate; it breaks nothing at build or run time.
**Affects:** cyrlint in cyrius 6.6.4; unchanged at HEAD 4f3731e8. Component: `programs/cyrlint.cyr`.

## Summary

`_line_deferral_term` (`programs/cyrlint.cyr:93`, called per line at `:275`) matches each term
against one line at a time. The multi-word terms (`for now`, `not yet`, `later bite`,
`future bite`, `out of scope`) are missed when a comment wraps between the two words, which is
exactly where a formatter or a 120-column limit tends to break them. The tracking-pointer check
has the same per-line scope, so the fix has to join both.

## Reproduction

```sh
cat > split.cyr <<'EOF'
# The immediate-offset form is a later
# bite.
# Uniform operands are rejected for
# now.
fn main() { return 0; }
var rc = main();
syscall(60, rc);
EOF
cyrlint --strict-deferrals split.cyr; echo "rc=$?"     # rc=0: both deferrals missed
printf '# The immediate-offset form is a later bite.\nfn main() { return 0; }\nvar rc = main();\nsyscall(60, rc);\n' > one.cyr
cyrlint --strict-deferrals one.cyr; echo "rc=$?"       # rc=2: same text on one line is caught
```

Real cases in mabda at tag 4.1.2: `src/gfx9_compile.cyr:326-327` and `:532-533` ("a later /
bite"), `src/compute.cyr:346-348` ("not / yet", "for / now").

## Root cause (if known)

Per-line scanning in `_line_deferral_term` and `_line_has_tracking_ptr`; there is no notion of a
comment block.

## Proposed fix

Treat consecutive `#` comment lines as one block: join them with single spaces, match terms on the
joined text, accept a tracking pointer anywhere in the same block, and report the first line of the
block. Single-line behaviour stays the same.

## Consumer-side workaround

mabda 4.1.3 ships `scripts/check-split-deferrals.py`, which joins adjacent comment lines and runs
the same term list, wired into `make test-all` and CI next to a per-file
`cyrlint --strict-deferrals` loop.

## Corrections to this filing

- **The proposed pointer scope would have hidden one of the filing's own three cases.**
  "Accept a tracking pointer anywhere in the same block": compute.cyr's block (344-348) carries
  `docs/archive/proposals/v3-native-api-principles.md` on line 346, so that block's `for` / `now`
  (347-348) would read as tracked — measured, block scope reports only the two gfx9 sites. It
  also silently un-flagged 98 of the 179 single-line notes this repo had at 6.6.4 (pointers ten
  lines away, often the loose words `issue` or `See `), so "single-line behaviour stays the same"
  did not hold under it either. **Shipped:** a pointer counts only on a physical line the term
  occurrence itself touches. That catches all three cases, keeps every single-line verdict, and
  gives compute.cyr exactly one note, at 347 (`not yet` is tracked by the `docs/` path on its own
  first line, 346).
- **"Report the first line of the block"** — blocks run to 30+ lines here. The note goes on the
  line where the occurrence STARTS (what mabda's own script reports), one note per physical line
  at most.
- **The term list misses one wrap.** `follow-up` splits too, as `follow-` / `up` (a hyphenated
  wrap, which must join with NO space). Also missed per line and now matched: `For now` /
  `NOT YET` / `Deferred` (the seven prose terms fold case; the five markers stay exact, since
  `todo_list` is an identifier), runs of spaces or tabs inside a term, and CRLF line ends.
- **The line numbers in "Real cases" are right** (gfx9_compile.cyr:326-327 and 532-533 at tag
  4.1.2). The premise-check that preceded the fix called them off by one; it was wrong.
- **"Severity: Low — it breaks nothing at build or run time"** holds for the deferral half only.
  The same one-line-at-a-time design hid a real miscompile shape from the init-order rule:
  `var A = 1 +` / `    B;` against a later `var B = g();` got no warning while the compiled
  program reads B as 0 (exit 1; the same program in declaration order exits 3). It also made
  every brace tracker forget a string at each line end (a false `unclosed braces` on 6 of the 7
  src/main*.cyr forks), and cut the sys_open / getdents / error-enum notes short at the line end.
  All fixed in the same bite; see the CHANGELOG entry.
- **The version pointer** was the literals `v5.` and `v6.`, although the policy says "version":
  consumer versions (`deferred to v0.8.0`, `TODO(v0.5)`) never counted, and cyrius's own `v7.`
  pointers would have stopped counting at 7.0. It is now `v<digits>.<digit>`.
- **The consumer-side workaround can stay or go** — mabda's `scripts/check-split-deferrals.py`
  flags split terms regardless of pointer, which is stricter than the shipped rule; retiring it
  is mabda's call once its pin is ≥ 6.6.5.
- **The per-line shape was wider than the first cut found** (review round 2, same bite): an
  initializer whose `=` opens the next line, `pub var` / `public var`, a second decl on a line
  as a forward-ref TARGET, `sys_open (` / `syscall` + `(` on the next line, whitespace inside a
  multi-line string, and `#naked fn f() {` — a `#` the lexer reads as an attribute token, which
  cyrlint (15 false brace warnings) and cyrfmt (rewrote the fn body flush left) both took for a
  comment. All fixed in bite 9; the lexer's own no-word-boundary match (`#ioctl …` does not
  compile) is filed separately as `2026-09-19-lexer-attribute-prefix-swallows-comments.md`.
- **Round 3 widened it again** (same bite): a declaration header wrapped anywhere (`var` /
  `A = …`, `var A:` / `i64 = …`, `var A` / `: i64 = …`), a declaration after a `}` or after the
  `;` of a wrapped initializer, and two declarations on one line (now ordered by offset) — each a
  runtime-proved silent zero the rule missed. cyrdoc had the same `pub fn` / `#inline fn` blind
  spot plus a fixed 64 KB read (sigil's doc gate judged 6 % of its bundle), and cyrfmt's output
  buffer had no bound (it segfaulted on deeply unclosed input). All fixed in bite 9. The
  preprocessor's own copy of the per-line defect (it executes `#ifdef` lines inside a
  multi-line string) is filed as `2026-09-19-preprocessor-executes-directives-inside-multiline-strings.md`.
