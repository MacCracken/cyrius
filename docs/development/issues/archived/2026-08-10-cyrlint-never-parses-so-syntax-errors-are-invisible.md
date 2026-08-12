# `cyrius lint` reports "0 warnings" on a file that does not parse

**Status:** ✅ **RESOLVED — v6.5.19. Option 1 (shell out to cycc) was chosen**, implemented in
`cmd_lint` (`cbt/commands.cyr`) as a syntax pre-pass whose verdict keys on the **message class**,
never on the exit code.

**Why not option 2 (a real front end):** `src/frontend/` is 17,703 lines carrying ~1,040
`E*(S, …)` emitter call sites and threads `S` (the compiler heap base) through every function —
the parser IS the emitter, so there is no parse-only slice to lift. A forked copy is a second
parser to keep in step forever, in the repo whose thesis is one toolchain; the v6.5.17
dead-fn-body bug was fork-divergent across the 7 `main*` forks and shipped green for months.
Option 3 leaves the linter still unable to answer the question.

**The filing's objection to option 1 is real and is what the implementation is built around.**
Lint must not need a resolvable project, so the pre-pass runs under `_skip_deps = 1` with
`--allow-undef` and only reports messages on a positive syntax allow-list (`unexpected `,
`expected `, `unterminated `, the escape family, `non-ASCII byte `, `multi-byte char literal`,
`nested @unsafe`). Measured: **38 of the 191 files this repo lints exit non-zero standalone, 27
of them with `undefined variable`** through the same `_err_head` and the same exit 1 — so
exit-code gating would have made lint refuse 20 % of the stdlib. Anything not on the list falls
back to today's behaviour, so the failure direction is under-report, never false accusation.
`cyrius audit` is unaffected — `audit_lint_walk` execs the `cyrlint` binary directly.

All three acceptance criteria met, gate at
`tests/gates/frontend/lint_reports_unparseable.sh`; its axis 3 (`lib/fs.cyr` alone in a bare
directory, proven unresolvable there by `cyrius check`, must still be linted) is what rejects
the exit-code implementation. See CHANGELOG [Unreleased].

**Status (as filed):** 🔴 **OPEN** — the residual half of the hisab dead-fn-body filing.
**Placement:** unpinned — 6.5.x line. Not blocking a consumer; it is a trust problem.
**Discovered:** 2026-08-09 (hisab), re-confirmed 2026-08-10 while fixing the compiler half.
**Severity:** **Medium** — no miscompilation. A linter that says "0 warnings" about a file
the compiler rejects is worse than one that says nothing, because the number is believed.
**Affects:** cycc **6.5.16** and **6.5.17** (the compiler fix does not reach it).

## Summary

```
# src/g.cyr — g_g is never called
fn g_g() { var x = ; this is not cyrius at all ]] ((
    return 0; }
fn main() { return 0; }
var r = main();
```

```
cyrius build src/g.cyr build/g     exit=1   error:<source>:3:20: unexpected ';'
cyrius lint  src/g.cyr             exit=0   0 warnings
```

The build rejects it. Lint reports it clean. That was true for BOTH the underscore and
underscore-free variants even before v6.5.17 fixed the compiler's dead-body skip, which
is what identifies this as a second, independent defect rather than a symptom of the
first: lint was never looking.

## Root cause

`programs/cyrlint.cyr` (929 lines) is a **line-based lexical scanner**. It tracks brace
depth, skips string and char literals and comments, and pattern-matches a fixed rule set.
It has no parser and constructs no AST, so "this file does not parse" is not a question it
is capable of asking. `0 warnings` is an honest report of its own rules; it just is not
the report a reader takes it for.

## Why this is filed rather than packed into v6.5.17

Per the repo's own rule, filing needs a named reason. This one is **a design decision that
is the maintainer's**, and it is a fork with real cost either way:

1. **Shell out to cycc.** Cheap to write, but a lint of a consumer file would then need dep
   resolution to get past the first `include` — lint deliberately does not do that today,
   which is exactly why it can lint a single file in isolation. Making lint require a
   resolvable project changes what the verb means.
2. **Give cyrlint a real front end** (share `src/frontend/lex.cyr` + `parse.cyr`, or a
   parse-only mode of cycc). Correct, and it would unlock the rules a lexical scanner
   cannot express — but it makes the linter carry the compiler's frontend, and needs a
   decision about what `cyrius lint` reports when a file legitimately cannot be resolved.
3. **Say so instead.** Have lint print `not parsed — lint is lexical` in its summary so the
   `0 warnings` line stops implying more than it means. Smallest change, no new
   capability, and it removes the sharp edge the filing actually named.

Option 3 could have been packed; 1 and 2 could not, and picking 3 unilaterally would
foreclose the other two.

## Acceptance criteria

- `cyrius lint` on the repro above does not report a bare `0 warnings`.
- Whatever it reports is true for a file it cannot resolve, not only for one it can.
- A gate under `tests/gates/frontend/` that is mutation-proven against the current
  behaviour (today's cyrlint must make it RED).

## Related

- `docs/development/issues/archived/hisab-dead-fn-bodies-never-syntax-checked.md` — the
  compiler half, fixed in v6.5.17.
