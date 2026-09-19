# The preprocessor executes `#ifdef` / `#endif` / `#define` lines that sit INSIDE a multi-line string — OPEN

**Status:** 🟡 **OPEN** — pre-existing (the installed 6.6.4 compiler gives the same bytes); found by the review of 6.6.5 bite 9
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
