# A stray top-level `}` silently ends the translation unit — everything after it is dropped, `OK` — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 2, l679-crit; CHANGELOG [6.7.9]) An unmatched `}` at module scope is refused in pass 1 — `error: <file>:<line>:<col>: unmatched '}' at module scope`, exit 1, before any body is parsed, so it is the only error (no "undefined" cascade in other files); gate `frontend/stray_brace_refused.sh`.

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above (filed OPEN by agnos, 2026-10-11, agnos 1.57.12 ZFS write bite B4; reproduced on 6.7.9 @ cda7fad9: every placement built rc 0 and dropped what followed).
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10/11 while building agnos's ZFS writer: a stray `}` left at top level in one kernel file made
cycc report 62 "undefined variable" errors in OTHER files and nothing at the real line; it cost a bisect.
**Severity:** High — silent truncation: a program that builds `OK` and runs is missing every definition after the brace.
**Affects:** cycc 6.6.6 (measured; later versions not checked from agnos).

## Summary

At top level, an unmatched `}` is accepted without a diagnostic and the parser stops there: every declaration after
it is discarded. A single-file program builds `OK`, its later functions are simply absent (so `main` is never
compiled and earlier functions are reported dead). In a multi-file build the dropped definitions surface as
"undefined variable" / "undefined function" errors in other files, pointing everywhere except at the brace.

## Reproduction

```
$ cat a.cyr
var counter = 0;
fn bump() { counter = counter + 1; return counter; }
}
fn main() { bump(); return counter; }
$ cyrius build a.cyr out          # cyrius 6.6.6, a cyrius.cyml pinning 6.6.6 beside it
compile a.cyr -> out [x86_64] note: 1 unreachable fns (92 bytes — ...)
OK (4456 bytes)
$ CYRIUS_DCE_VERBOSE=1 cyrius build a.cyr out
  dead: bump                       # main (its only caller) was never compiled
$ ./out; echo $?
0
```

A second file `b.cyr` with more code after the brace (`var later = 7; fn usel() {...}; fn main() { bump(); return
usel(); }`) also builds `OK (4456 bytes)` — byte-for-byte the same size as `a.cyr`: everything after the brace is gone.

Expected: `error: <file>:3: unmatched '}' at top level` (and a non-zero exit).

## Root cause (if known)

Not investigated from agnos. Speculation: the top-level declaration loop treats `}` as an end-of-block/end-of-input
token and returns instead of reporting it.

## Proposed fix

Refuse an unmatched top-level `}` with a positioned error, like an unbalanced `#endif` (agnos check.sh gate 35 had to
add a pure-text balance check for that case precisely because cycc dropped it without a diagnostic). A regression row:
the two files above must fail to build.

## Consumer-side workaround (if any)

None in the compiler. agnos's fmt gate (`scripts/check/fmt-check.sh`) does not catch it either; a brace-balance text
check per file (like `scripts/check/pp-balance-check.sh` for `#if`/`#endif`) would.

## Resolution (6.7.9)

**Root cause** — `PARSE_PROG` (src/frontend/parse.cyr) is also the block and fn-body parser, so a `}` ends its loop; at
module scope that loop is the fork's whole program, and it stopped there with nothing checking that the input was
used up. Pass 1 already met the same brace: `_tl_scan1` returns at the first token that is not a declaration, and
`_prescan_tail_loop` (src/frontend/parse_fn.cyr), which walks the rest of the stream consuming every statement and
definition with its braces balanced, stopped at a module-depth `}` under a comment naming it the stray brace.

**The fix** — that arm now calls `_tl_stray_brace`: `ERR_MSG` "unmatched '}' at module scope" at the brace (file, line,
column, the source excerpt), a hint line for the other way to get there (an extra `}` inside a fn ends it early and
the fn's own closing brace is the one left over), and exit 1. It runs in pass 1, before any body is parsed, so it is
the first and only diagnostic: the agnos symptom (the definitions after the brace reported "undefined" in files parsed
before it) cannot follow. One site, shared by all seven forks (`_tl_pass1`). The user's decision 3(a), 2026-10-11.

**Measured** — the reporter's `a.cyr` and `b.cyr` now fail with `error:<source>:3:1: unmatched '}' at module scope`;
every file in the tree (553 `.tcyr`, 113 `lib/`, 100 `programs/`, `cbt/`, `benches/`, `fuzz/` and the seven compiler
forks — 930 sources) compiles to byte-identical output and diagnostics before and after.

**Rows** — `tests/gates/frontend/stray_brace_refused.sh`: R (the two files verbatim), P (the brace first; after a
struct / enum / const / trait / impl / fn / var in the declaration zone; after an assignment, an if / elif / else, a
while, a switch, a `do .. while`, a closure declaration, a relaxed-ordering fn; two in a row), H (an extra `}` inside a
fn, with the hint), I (the agnos three-file shape — the user included before the brace's file, and after it), X
(`--syntax-only`), F (main_aarch64, main_cx, main_win, main_aarch64_native under qemu, the PE target), K (every
legitimate module-scope `}` still compiles and the program exits 42, on x86 plain / IR=3 / DCE=1 and every fork).
Mutation-proven four ways (the ledger is in the gate's header).
