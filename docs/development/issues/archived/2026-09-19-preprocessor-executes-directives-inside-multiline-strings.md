# The preprocessor executes `#ifdef` / `#endif` / `#define` lines that sit INSIDE a multi-line string — FIXED

**Status:** ✅ **FIXED in 6.6.6 (bite 4)** — pre-existing (the installed 6.6.4 compiler gives the same bytes); found by the review of 6.6.5 bite 9
(round 2), whose fix taught cyrlint that a string's state crosses a line break.
**Placement:** unpinned — 6.x line (preprocessor). Not parked to 7.x.
**Discovered:** 2026-09-19.
**Severity:** Medium — SILENT. The program compiles, and its string data is not what the source
says. No diagnostic of any kind.
**Affects:** `src/frontend/lex_pp.cyr` — the line-oriented directive pass (`#ifdef`, `#ifndef`,
`#else`, `#endif`, `#define`), every fork.

## Reproduction

A cyrius string literal may hold a raw newline (src/main.cyr's own error strings do). The
preprocessor runs line by line BEFORE the lexer and does not know that a line starts inside one:

```sh
printf 'var s = "ab\n#ifdef NOPE\ncd\n#endif\nef";\nsyscall(1, 1, s, 40);\nsyscall(60, 0);\n' \
    | ./build/cycc > /tmp/pp && chmod +x /tmp/pp && /tmp/pp | od -c | head -2
# 0000000   a   b  \n  \n  \n  \n   e   f  \0 …
```

The string the source spells is `ab\n#ifdef NOPE\ncd\n#endif\nef`; the binary holds
`ab\n\n\n\nef` — the two directive lines were EXECUTED (the `cd` between them was dropped as a
false branch) and blanked. Measured at 6.6.5 with `build/cycc`:

| line inside the string | result |
|---|---|
| `#ifdef NOPE` … `#endif` | both lines blanked, everything between them removed |
| `#define FOO 9` | the line removed from the string data (FOO not substituted after it) |
| `#include \"inc_me.cyr\"` | kept verbatim (the escaped quotes stop the directive parse) |
| `# plain comment-looking text` | kept verbatim |

Census: 0 instances in 18,946 ecosystem sources (review round 2), so nothing that ships today
depends on either reading.

## Cause

The directive pass decides "is this line a directive?" from the line's first non-space byte and
carries no lexical state between lines, so a string opened on an earlier line is invisible to
it. It is the preprocessor's copy of the per-line defect bite 9 removed from cyrlint (the brace
counter there took the `}` after a raw-newline string's closing quote for string content).

## Fix direction

Carry "inside a string literal" across lines in the directive pass (the same rule the lexer
applies: `"` opens and closes, `\` escapes the next byte, a `#` comment ends at the line, a
char literal is single-line) and treat a line that STARTS inside a string as data. Either keep
the directive semantics outside strings exactly as today, or — if a directive inside a string
is judged worth a diagnostic — reject it loudly; silently executing it is the one wrong answer.

## Acceptance

- The reproduction above prints `ab\n#ifdef NOPE\ncd\n#endif\nef` (or fails to compile with a
  diagnostic naming the line), on every fork (x86, aarch64, PE, Mach-O, cx).
- `#ifdef` / `#define` OUTSIDE strings behave byte-identically: the full tcyr corpus exit codes
  unchanged, `build/cycc` reproduces itself, and `sh scripts/seed-derive-cycc.sh` stays
  machine-derivable (the pass is compiled by `cybs`, which fails silently on large functions).
- A gate compiles the table's four shapes and checks the string bytes at runtime.

## Why it was not packed into bite 9

Bite 9 is the cyrlint fix and changes no `src/` file. This is a compiler (preprocessor) defect
in a different program: bundling it into bite 9's commit would break the one-change-per-commit
rule, and it needs its own seed-derive, self-host and cross-OS cycle.

## Resolution — 6.6.6 bite 4

`src/frontend/lex_pp.cyr` gained `PP_LEXST`, one lexical state machine shared by all FOUR
line-oriented passes, whose string state CROSSES a newline. Three of them previously carried their
own inlined copy and reset `in_string` at every newline; the reset's written justification was the
premise *"cyrius source uses single-line strings (`\n` escape, not literal LF inside a string)"*,
which is false about this repo's own source. The fourth, `PP_IS_HOST_ONLY`, had no lexical state
at all — see the correction below.

The reset was only ever a blast-radius bound for a `"` the machine mis-read, so removing it meant
turning both real sources of that into STATES: a `"` inside a `#` comment (already handled since
v5.9.34) and a `"` inside a char literal such as `var q = '"';`
(`tests/fixtures/lint_lexical/escapes.cyr` — never handled, and the reason this was not a
three-line deletion). `PP_REF_PASS`, which had no lexical state at all, got the same gate.

Gates: `tests/gates/frontend/pp_directive_inside_multiline_string.sh` (10 axes, mutation-proven
four ways, registered in `programs/checks/main.cyr`) and
`tests/tcyr/crossos/pp_directive_inside_multiline_string.tcyr` (9 assertions, in `crossos/` so
the release gate executes it on real ecb / ach / cass / pi).

Verification: the filing's repro prints `ab\n#ifdef NOPE\ncd\n#endif\nef`; all 328 pre-existing
`.tcyr` exit codes identical to the pre-fix compiler; `build/cycc` self-host fixpoint; `seed-derive-cycc.sh`
machine-derivable; all seven forks compile. cycc unchanged at 1,310,856 B.

## Corrections to this filing

- **The reproduction table was incomplete in both directions.** Four more shapes were damaged and
  are now covered: `#ifplat` / `#endplat` (executed, body dropped), `#@file` (PP_PASS's v6.5.21
  forgery guard INJECTED A SPACE into the string data, `#@file` → `# @file`), `#@srcline` (broke
  the build outright with `undefined variable 'source'`), and a continuation line beginning
  `#ref ` whose closing quote follows it (`error: cannot open #ref file: ;` — PP_REF_PASS, a pass
  the filing does not mention at all and which carried no lexical state whatsoever).
- **"`#include \"inc_me.cyr\"` kept verbatim" is right but for a reason worth stating**: the shape
  is UNREACHABLE inside a string, because a literal `"` after the directive name would close the
  string. The same is true of `#derive(...)`'s parenthesised form only by accident — `#derive(Serialize)`
  needs no quote and WAS damaged (it compiled to `error: #derive(...) applies to a struct or an enum`).
- **"Affects: `src/frontend/lex_pp.cyr` — the line-oriented directive pass"** understates it:
  there are FOUR such passes (`PP_PASS`, `PP_IFDEF_PASS`, `PP_REF_PASS`, `PP_IS_HOST_ONLY`), and
  `PP_IFDEF_PASS` is the one that sees directives inside INCLUDED files — so a fix to
  `PP_PASS` alone would have left half the defect live. Gate axis 5 exists for exactly that.
- **The first cut of the fix said THREE and missed `PP_IS_HOST_ONLY`** (found by review of bite 4,
  fixed as bite 4b). That pass scans a freshly-read include's first 4096 bytes for a column-0
  `#host_only`, with no lexical state at all — and its own comment gives the column-0 requirement
  as the safeguard "so prose that merely mentions the directive cannot trip it". A raw LF inside a
  string is precisely what defeats a column-0 rule, so an included file holding
  `var doc = "intro` / `#host_only` / `end";` was recorded as host-only and every
  `--target=<arch>-bare-metal-elf` build that pulled it died with
  `error: bare-metal build includes host-only module`. Unlike every other shape in this filing
  that one is LOUD, which is why the corpus never caught it. Gate axes 9 (the defect) and 10
  (a real column-0 `#host_only` still annotates) pin it. **The lesson: when a line-oriented pass
  is fixed, grep for the SHAPE (`bol` / first-byte-of-line) rather than the names already known —
  the fourth instance was 2,300 lines up in the same file.**
- **The fix direction's parenthetical "a char literal is single-line" is load-bearing, not an
  aside.** Without teaching the machine char literals, removing the newline reset converts
  `var q = '"';` from a one-line annoyance into a whole-file poisoning. Mutation M3 in the gate's
  ledger is that exact build.
