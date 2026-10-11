# A stray top-level `}` silently ends the translation unit — everything after it is dropped, `OK` — OPEN

**Status:** 🟡 **OPEN** — filed by agnos (2026-10-11, agnos 1.57.12 ZFS write bite B4).
**Placement:** 6.7.10 — Break 2, repair 1, the parser lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-11 — never 7.x. (High, consumer-reported by agnos; not a one-site fix — the top-level loop legitimately meets each fn definition's closing brace, so the stray one needs the scanners' brace accounting; checked 2026-10-11)
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
