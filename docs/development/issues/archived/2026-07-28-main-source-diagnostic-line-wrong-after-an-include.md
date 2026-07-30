# RESOLVED at v6.5.3

**Status:** ✅ **RESOLVED v6.5.3.** All 10 shapes in `tests/diag_line_after_include.sh` pass;
8 of them fail on the 6.5.2 binary.

**The disproved theory in this file was actually CORRECT.** "Carry the resume line in the
marker" was the right fix and it had been implemented properly. It appeared to do nothing
because `lex_pp.cyr` had a SECOND, hand-rolled marker emitter — the `source_marked` one-shot
this file itself flagged as "a partial, earlier attempt … fold it into whatever lands" —
which fired at the same point and wrote a base-less duplicate that `FM_LOOKUP` matched
instead. The fix was overwritten, not wrong.

**Lesson worth more than the fix:** before concluding a change "does not work", check
whether something else writes the same record afterwards. The verification that it was
"present in the built compiler" was true and irrelevant.

Also fixed en route: include-once skips left the base stale by one per skip; nested includes
reported expanded lines (`lib/mid.cyr:2` as `:4`) because `PP_IFDEF_PASS` reads already-expanded
text. See CHANGELOG [6.5.3].

---

# Diagnostics report the wrong LINE for the main source once any `include` is present

**Status:** 🟡 **OPEN** — pre-existing, reproduced against released **6.4.86** and against the
`privatefns` branch. **Not** introduced by the v6.5.0 visibility arc.
**Severity:** **Medium** — the FILE is named correctly and the source excerpt + caret are correct, so
the error is still findable; only the line NUMBER is wrong. But it is wrong on essentially every real
program, since almost every file has an include.
**Placement:** v6.5.x, ideally before `public`/`private` reaches consumers — every visibility error is
cross-file by construction, so this is the diagnostic users will see most of.

## Reproduction

```
lib/inner.cyr:  fn inner_ok(): i64 { return 1; }

m.cyr:          include "lib/inner.cyr"        <- line 1
                fn outer_bad(): i64 { return 1 + ; }   <- line 2, the error
```

```
$ cat m.cyr | cycc
error:<source>:1:34: unexpected ';'      <- says line 1, should be line 2
    fn outer_bad(): i64 { return 1 + ; }
                                     ^
```

The excerpt and caret are right; only the number is wrong. An error *inside* an include is reported
correctly (`lib/inner.cyr:2:34`), so this is specific to the main source after an include.

## What I tried, and why it was reverted

The obvious theory is that the preprocessor's RESUME marker (added in the v6.5.0 Phase 1 file-id
work) restarts the enclosing file's line count at 1, because `FM_LOOKUP` computes
`expanded_line - start + 1`. I implemented the apparent fix and **it did not change the output**:

- extended the marker to `#@file "NAME" LINE`, carrying the line to resume at
- `_pp_line_at(S, ip)` computes the enclosing file's line by scanning forward from an anchor, so the
  total cost is O(input) across a build rather than O(input x includes) — and, importantly, it does
  not thread a counter through the **17** distinct `ip`-advance sites in `PP_PASS`'s loop, which is
  where an off-by-one would hide
- `FM_BUILD` parsed the trailing number and packed it into the HIGH 32 bits of the `line_count` word
  (the v6.4.60 `tok_lines` precedent) — the entry must stay 24 B or 1024 entries no longer fit the
  `0x71A040..0x721000` band
- `FM_LOOKUP` used it: `expanded_line - start + base`

All of that was verified present in the built compiler, and the reported line was still 1.

**So the resume-line theory is wrong, and that is the useful result.** The remaining explanation is
that the two line-numbering schemes do not agree: `FM_BUILD` counts newlines over `preprocess_out`
(`src/frontend/lex.cyr`), while `_err_head` passes `GTLINE(S, ti)` — the LEXER's per-token line from
`tok_lines`. If the lexer does not count the `#@file` marker lines the same way `FM_BUILD` does, every
lookup is off by the number of markers preceding the token, and no amount of correcting the marker
payload will fix it.

**Reverted rather than shipped** because it added preprocessor risk immediately before a release
without demonstrable benefit. The work is described here in full so the next attempt starts from the
disproved theory rather than repeating it.

## Where to start

1. Instrument both numbers for one token: `GTLINE(S, ti)` versus the expanded line `FM_BUILD` believes
   that token sits on. The delta should equal the number of `#@file` markers emitted before it — if so,
   the fix is to make one side agree with the other, not to change the marker format.
2. Check whether `ADDTOK`/`LEX` skip or count marker lines (`src/frontend/lex.cyr`), and whether
   `_tok_start`'s byte offset (v6.4.60) is a more reliable anchor than the line at all — the excerpt
   and caret are derived from the OFFSET and they are correct, which is strong evidence the offset
   path is sound and the line path is not.
3. `source_marked` (`lex_pp.cyr`) is a one-shot and was a partial, earlier attempt at the same
   problem; fold it into whatever lands rather than leaving two mechanisms.

## Acceptance criteria

1. The repro above reports `<source>:2:34`.
2. An error inside an include still reports its own file and line correctly.
3. An error after the SECOND top-level include is also correct (the `source_marked` one-shot means
   one include may work by accident where two do not).
4. 253/253 tcyr byte-identical — this must be diagnostics-only.
5. Self-host fixpoint + seed-derive green; the preprocessor is in cybs's path.
