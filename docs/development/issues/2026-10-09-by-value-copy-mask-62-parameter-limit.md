# `_pm_copies` answers 0 past parameter 61: a by-value struct at parameter 62+ is neither snapshotted nor treated as copied — OPEN

**Status:** 🟡 **OPEN** — reported 2026-10-09 by the 6.7.7 call-arguments lane from the code (GFBVCP is a 62-bit mask); not reproduced with a 63-parameter fn.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** the 6.7.7 call-arguments lane (out of scope); filed 2026-10-09.
**Severity:** Low — needs a fn with 62+ parameters
**Affects:** cycc ≤ 6.7.7

## Summary

The callee-copies mask `GFBVCP` has 62 bits, so `_pm_copies` cannot answer for a parameter ordinal past 61: the
6.7.7 by-value argument snapshot and `_sarg_escapes` both skip such a parameter. fns take any number of arguments
(CLAUDE.md), so the representation is the limit.

## Proposed fix

A per-parameter-row bit (the parameter table) instead of the fixed mask, with a 64-parameter row.
