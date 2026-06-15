# Diagnostic `syscall(SYS_WRITE)` byte-length audit — 27 miscounted message lengths

**Filed:** 2026-06-12 (flagged during the v6.1.38 F3 adversarial review)
**Severity:** P3 (cosmetic — wrong stderr output; no crash, no codegen impact)

## Summary

The compiler/stdlib emit diagnostics via `syscall(SYS_WRITE, 2, "literal", LEN)`
with a **hand-counted** `LEN`. A sweep of all 539 such string+length pairs in
`src/` + `lib/` found **27** where `LEN` ≠ the literal's true UTF-8 byte length
(`\n` = 1 byte, em-dash `—` = 3 bytes):

- **16 em-dash undercounts** — `—` counted as 1 (or 0) byte instead of 3 → `LEN`
  too small → the message is **truncated** (drops trailing bytes, often `s\n` or
  the newline, so warnings run together).
- **11 others** — mostly off-by-one. Undercounts truncate; **over-counts**
  (`coded > true`) make `write` **read past the literal** into adjacent `.rodata`
  (appends garbage to the message). All cosmetic.

## The 27 sites

| file:line | coded | true | Δ | kind |
|---|---|---|---|---|
| `src/backend/aarch64/emit.cyr:154` | 60 | 61 | +1 | em-dash |
| `src/backend/aarch64/emit.cyr:1426` | 67 | 66 | −1 | over-read |
| `src/backend/aarch64/emit.cyr:1446` | 67 | 66 | −1 | over-read |
| `src/backend/macho/emit.cyr:299` | 45 | 44 | −1 | over-read |
| `src/backend/x86/emit.cyr:84` | 58 | 61 | +3 | em-dash |
| `src/backend/x86/fixup.cyr:1088` | 24 | 25 | +1 | undercount |
| `src/common/ir.cyr:226` | 28 | 27 | −1 | over-read |
| `src/common/ir.cyr:247` | 28 | 27 | −1 | over-read |
| `src/common/util.cyr:25` | 66 | 68 | +2 | em-dash |
| `src/common/util.cyr:56` | 53 | 54 | +1 | em-dash |
| `src/frontend/lex.cyr:643` | 31 | 32 | +1 | undercount |
| `src/frontend/lex.cyr:899` | 70 | 72 | +2 | em-dash |
| `src/frontend/lex.cyr:915` | 70 | 72 | +2 | em-dash |
| `src/frontend/lex_pp.cyr:272` | 67 | 70 | +3 | em-dash |
| `src/frontend/lex_pp.cyr:493` | 92 | 95 | +3 | em-dash |
| `src/frontend/parse.cyr:846` | 37 | 38 | +1 | undercount |
| `src/frontend/parse_fn.cyr:98` | 48 | 49 | +1 | em-dash |
| `src/frontend/parse_fn.cyr:1070` | 47 | 46 | −1 | over-read |
| `src/frontend/parse_fn.cyr:1427` | 72 | 74 | +2 | em-dash |
| `src/main.cyr:616` | 27 | 28 | +1 | undercount |
| `src/main.cyr:1882` | 44 | 45 | +1 | em-dash |
| `src/main.cyr:1888` | 47 | 49 | +2 | em-dash |
| `src/main.cyr:1894` | 35 | 37 | +2 | em-dash |
| `src/main_aarch64_macho.cyr:166` | 33 | 34 | +1 | undercount |
| `src/main_win.cyr:910` | 44 | 45 | +1 | em-dash |
| `src/main_win.cyr:916` | 47 | 49 | +2 | em-dash |
| `src/main_win.cyr:922` | 35 | 37 | +2 | em-dash |

## Fix

Set each `LEN` to the true byte length (the table's `true` column). Mechanical;
no codegen change → cycc self-hosts byte-identical (these strings are data). The
audit script (regex extract + escape-aware byte count) is reproducible; re-run it
as a check after the fix → expect 0 mismatches. Consider a permanent `check.sh`
gate that fails on any `syscall(WRITE,…,"…",LEN)` whose `LEN` ≠ true bytes, so
this class can't recur.

## Status

OPEN. Several sites are in compiler `src/` (incl. `aarch64`/`macho`/`win` cross
targets) → the fix is a compiler change and needs the cross-OS self-host gate
even though it's data-only.

## Resolution (cyrius 6.2.9, 2026-06-15)

CLOSED. The 27 documented sites were corrected in a prior release (this issue was
never archived). A UTF-8-accurate, **DOTALL/multi-line-aware** re-derivation
(scanning all 425 `syscall(SYS_WRITE, …, LEN)` sites in `src/`) confirmed those
27 are fixed AND surfaced **one more the original single-line audit could not
see**: `src/main.cyr:825` — a multi-line `"\n        "` debug literal (newline +
8 source-indent spaces) with `LEN=1` (the indentation was never written but broke
the LEN==true-byte-length invariant). Cleaned to `"\n"` (runtime unchanged).
Sweep now reports **425 sites, 0 miscounts** — the audit is complete. cycc
self-hosts byte-identical at 1,063,784 B (−16). See CHANGELOG [6.2.9].
(Lesson reaffirmed: re-derive with a DOTALL/byte-accurate sweep, don't trust a
single-line regex — cf. the v6.1.41 closeout note.)
