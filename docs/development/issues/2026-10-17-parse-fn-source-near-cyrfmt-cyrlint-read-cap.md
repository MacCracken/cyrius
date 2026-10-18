# src/frontend/parse_fn.cyr is 3.3 KB under cyrfmt / cyrlint's 1028 KB read cap: past it both tools refuse the file and tracked_sources_canonically_formatted.sh goes RED — OPEN

**Status:** 🟡 **OPEN** — met 2026-10-17 by the 6.7.14 vectors lane (unit V5): its first cut of the D40 bite put
src/frontend/parse_fn.cyr at 1,054,367 bytes, and both tools refused it. The lane moved its new helpers to
src/frontend/parse_types.cyr instead; at the lane's tip (609c18166) parse_fn.cyr is 1,049,325 bytes.
**Placement:** 6.7.15 — repair 5 (on main, wave 0, before the lanes fork; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D25 — A: split parse_fn.cyr.
**Severity:** Low today, a RED gate the day it bites — every compiler lane adds to parse_fn.cyr, and a merge of two
lanes can cross the cap where neither lane alone does.
**Kind:** tooling limit (6.2.20's `_MAX_FILE`, the user's choice of 1028 KB "to be safe", issues/archived/
fmt-check-file-size-cutoff.md) meeting the largest compiler source.

## Reproduction

```sh
$ ls -l src/frontend/parse_fn.cyr          # the first cut of the D40 bite
-rw-r--r-- 1 macro macro 1054367 ... src/frontend/parse_fn.cyr
$ build/cyrfmt --check src/frontend/parse_fn.cyr; echo $?
cyrfmt: file too large to format-check (>1028KB) — raise _MAX_FILE
1
$ build/cyrlint src/frontend/parse_fn.cyr
=== cyrlint: src/frontend/parse_fn.cyr ===
cyrlint: file too large to lint (>1028KB) — raise _MAX_FILE
```

`_MAX_FILE` is 1,052,672 in programs/cyrfmt.cyr and programs/cyrlint.cyr. tests/gates/toolchain/
tracked_sources_canonically_formatted.sh requires every src/ file to pass `cyrfmt --check` (the src/ ratchet is gone),
so a parse_fn.cyr past the cap fails it. Sizes at the lane tip: parse_fn.cyr 1,049,325; the next largest frontend
file, parse_decl.cyr, 558,819.

## Fix direction (the user's call between them)

Split parse_fn.cyr along a seam it already has (the generics inference and instantiation block, the parameter
classifiers and the pass-1 prescan are each tens of KB and self-contained; fn order does not matter to cycc or cybs),
or raise `_MAX_FILE` in both tools in step (their own gates, cyrlint_cross_line.sh's large-file axis, pin the
fail-loud refusal at the cap).
