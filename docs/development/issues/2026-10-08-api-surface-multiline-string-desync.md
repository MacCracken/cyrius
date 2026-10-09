# api-surface's line scanner resets its string state at every newline — a multi-line string hides or invents public fns — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `programs/cyrius_api_surface.cyr`
built by the tree's `build/cycc` and run `--update --scope project` on two three-fn scratch projects: a `{` on a raw
line of a multi-line string drops every later fn from the snapshot; a raw line starting `fn ghost(x, y)` inside a
string is snapshotted as public `m::ghost/2`. Both sources compile and run (the string prints across lines).
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** 6.7.3's attribute-lexing lane (`_asf_lexst_at`, 2026-10-07); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — the snapshot is silently wrong, so `cyrius api-surface` (and `removed_symbol_census.sh`, keyed on
it) miss a removed public fn or report a phantom one; no error is printed.
**Affects:** `cyrius_api_surface` through 6.7.6 (the per-line brace scan dates from v5.10.16).

## Summary

`_scan_file` walks a file one LINE at a time. Its brace counter (`programs/cyrius_api_surface.cyr:684-714`) skips
strings, char literals and comments, but each skip stops at the end of the line and the next line starts in code. A
string literal that spans lines (legal cyrius) therefore exposes its inner lines as code: a `{` there raises `depth`
for good (no matching `}` is ever seen in code), and every fn after it falls outside the `depth == 0` guard (`:576`);
a line beginning `fn name(` there matches the `fn ` test (`:642`) and is pushed as public surface. The same file
already has a lexer that carries string state across lines — `_asf_lexst` / `_asf_lexst_at` (`:404-428`), used by
`_asf_body_close` for `#derive` bodies.

## Reproduction

```sh
cat programs/cyrius_api_surface.cyr | build/cycc > $S/asf && chmod +x $S/asf
mkdir -p $S/p1/src $S/p1/docs $S/p2/src $S/p2/docs
printf 'fn before(a) { return a; }\nvar BANNER = "usage:\n{ opens nothing, this is string text\nfn ghost(x, y) — also string text\n";\nfn after(b) { return b; }\n' > $S/p1/src/m.cyr
printf 'fn before(a) { return a; }\nvar HELP = "usage:\nfn ghost(x, y)\n";\nfn after(b) { return b; }\n' > $S/p2/src/m.cyr
(cd $S/p1 && $S/asf --update --scope project && cat docs/api-surface.snapshot)
(cd $S/p2 && $S/asf --update --scope project && cat docs/api-surface.snapshot)
```

Expected, both: `m::after/1`, `m::before/1`. Actual:

```
p1: snapshot updated: 1 public fns   → m::before/1                         (after/1 lost)
p2: snapshot updated: 3 public fns   → m::after/1  m::before/1  m::ghost/2 (ghost/2 invented)
```

## Root cause

`programs/cyrius_api_surface.cyr:556-718` — the declaration test (`:576-680`) and the brace scan (`:684-714`) both
restart from lexical state 0 at `line_start`; nothing carries "inside a string / char literal" from one line to the
next. (Comments end at the newline anyway; strings do not.)

## Proposed fix

Carry one lexer state across the whole file: walk with `_asf_lexst_at` (as `_asf_body_close` does), count braces only in
state 0, and run the per-line declaration test only for lines that START in state 0. Pin both shapes above in a gate
(an api-surface row: a multi-line string holding `{` and a `fn x(` line must leave the snapshot equal to the two real
fns).
