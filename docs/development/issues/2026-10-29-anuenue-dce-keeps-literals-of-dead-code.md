# `CYRIUS_DCE=1` removes a dead fn but keeps the string literals only it reads: 307 KB of Unicode tables in every agnostik consumer — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-29 against cyrius 6.7.18 on x86_64 Linux with
[`repros/2026-10-29-dce-keeps-literals-of-dead-code.sh`](repros/2026-10-29-dce-keeps-literals-of-dead-code.sh).
**Placement:** unplaced — for the user to place.
**Source:** anuenue (`/home/macro/Repos/anuenue`), found while cutting its 1.5.1 (cyrius 6.7.9 → 6.7.18, agnostik
1.12.0 → 2.0.0).
**Discovered:** 2026-10-29, attributing anuenue's binary-size step at the toolchain move.
**Severity:** Low — no wrong value; a size cost. anuenue's DCE binary goes from 248 288 B to 532 448 B, and 307 252 B
of it is data no live code reads.
**Affects:** cyrius 6.7.18 (the repro). The Unicode tables reach consumers from 6.7.13, when `bayan`'s fold began
including `lib/unicode/` (per agnostik's 1.12.1 CHANGELOG). Earlier releases not checked.

## Summary

With `CYRIUS_DCE=1`, a function nothing reaches is eliminated, but a string literal that only that function reads stays
in `.rodata`. That holds for a literal used as a global's initializer and for one inside the dead function's body.

The large case is `lib/bayan.cyr`. It includes the seven `lib/unicode/` files, whose `_*_data.cyr` hold the Unicode
17.0.0 normalization, case-fold and category tables as global string literals (`var _UNICODE_CAT_PIECE_0 = "…";` and
so on). agnostik's `dist/agnostik.deps` lists `bayan`, because since 6.7.17 the `#derive(Serialize)` expansion calls
`bayan_json_get_by_str`. So every consumer of agnostik carries the tables, though DCE drops every function that reads
them.

In anuenue 1.5.1's binary, all three tables are present byte for byte: `_normalize_data` 154 002 B, `_casefold_data`
95 234 B, `_categories_data` 58 016 B. anuenue calls no `bayan_*` or Unicode function, and none survives DCE.
agnostik's own x86_64 DCE build shows the same `.rodata` growth at 6.7.18 (+341 994 B, its 1.12.1 CHANGELOG), and its
CHANGELOG records that "DCE drops the fns that read those tables but keeps their literals". This file is the issue for
that sentence; none was found in `issues/` or `archived/`.

## Reproduction

```sh
sh docs/development/issues/repros/2026-10-29-dce-keeps-literals-of-dead-code.sh
```

**Actual** (cyrius 6.7.18, x86_64 Linux):

```
without      4456 B   literal in image: 0
global     104472 B   literal in image: 1
fnlocal    104464 B   literal in image: 1
```

`global` and `fnlocal` each report `note: 1 unreachable fns (60 / 64 bytes NOPed)` and `dead code eliminated`, yet the
100 000-byte literal only that fn reads is still in the image.

**Expected:** the literal goes with the last code that reads it, and `global` / `fnlocal` come out near `without`'s
4 456 B.

**Downstream, pinned:** anuenue at commit `8c7c76c` (tag 1.5.0) plus its uncommitted 1.5.1 pin move
(`cyrius = "6.7.18"`, agnostik `2.0.0`). `CYRIUS_DCE=1 cyrius build src/main.cyr build/anuenue` gives 532 448 B. Section
sizes against 1.5.0 on 6.7.9: `.text` 125 616 → 126 704 B, `.rodata` 38 790 → 381 221 B. The same tree on 6.7.18 with
the *old* dep tags (agnostik 1.12.0) is already 531 824 B, so the step is the toolchain's snapshot, not a dep tag.

## Root cause (if known)

Not investigated by the consumer. Speculation, flagged as such: DCE works at function granularity, and the data
section is emitted whole, so string literals are not tied to the functions that reference them.

## Proposed fix

None — just surfacing.

## Consumer-side workaround (if any)

None. anuenue cannot drop `bayan`: agnostik's sidecar requires it. anuenue tracks binary size and does not cap it, so it
records the step (its `state.md` § Binary) and ships.
