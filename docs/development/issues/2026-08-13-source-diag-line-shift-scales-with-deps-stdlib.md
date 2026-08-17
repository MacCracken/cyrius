# `<source>` diagnostic line numbers shift by one per declared stdlib module

> ### ✅ RESOLVED — SHIPPED in v6.5.24
>
> cbt now writes **`#@srcline`** as the last thing before the entry file, and cycc
> re-anchors the `<source>` span to line 1 there. Verified end-to-end: the same probe with
> an error on its own line 3 reports `:3` with **0, 6 and 18** declared stdlib modules and
> with a subdirectory entry file (which adds `#@incdir`); before the fix those reported
> `:3`, `:10`, `:19` and `:7`.
>
> **This file's magnitude claim was right and load-bearing** — the changelog's "+1" framing
> was what made it look like a rounding error. The measured shift is one line per prepended
> line, and cbt prepends `#@incdir`, `#@pkgver`, one `include` per `[deps].stdlib` module,
> one `#define` per `-D`, **and the entire text of every `[build].modules` file**.
>
> ⚠ **Not the remedy proposed here.** Re-emitting `#@file` stayed foreclosed — v6.5.21
> neutralises user-authored `#@file` markers to close a forged-marker bypass of `private`.
> `#@srcline` cannot re-open that hole: it carries no filename and can only move line
> attribution, and it is honoured once.
>
> ⭐ **The marker carries NO COUNT, deliberately.** Having cbt declare "I prepended N lines"
> would make N a hand-maintained value duplicating a derivable fact — the shape that had
> silently drifted in three separate places this cycle — and it is unworkable once
> `[build].modules` is in play. cycc derives the bias from the marker's own line position.
>
> ⚠ **Setting the bias alone does nothing**, which cost a build cycle: the bias is only
> consumed when an `include` RETURNS, and cbt's prepended includes all sit ABOVE the marker,
> so the last re-anchor has already happened with the old bias. The marker must re-anchor
> outright. A bias-only first cut reported the RAW line (8) instead of the user's (3).
>
> Gate `tests/gates/diagnostics/srcline_no_line_shift.sh` — 0/6/**18** modules plus a subdir
> entry must all report the SAME line, so a fix that merely shifted the constant by one
> cannot pass. Mutation-proven: dropping cbt's write reproduces the filed signature exactly
> (+7 at 6 modules, +16 at 18, +4 for a subdir entry).
>
> **Not claimed / still true:** not measured on aarch64 / PE / cx (front-end line
> accounting, no reason to expect a difference), and `-D` scaling was not separately
> measured — though `-D` prepends go through the same path and now sit above the marker.

**Status:** ✅ RESOLVED in v6.5.24 — archive at slot close.
separate warning
**Severity:** Low-Medium — diagnostic only, but it points at a line that can be
**past EOF**, which reads as a compiler bug rather than a source defect
**Affects:** cycc 6.5.21 (and .20 per your own measurement)
**Repro:** [`repros/2026-08-13-f64-typed-binding-reassign-warns.cyr`](repros/2026-08-13-f64-typed-binding-reassign-warns.cyr)
(any file that emits a diagnostic works)

## Summary

⚠ **This is a known class, not a discovery.** The v6.5.21 changelog already
states it, under `CYRIUS_PKG_VERSION`:

> Every other cbt prepend shifts `<source>` diagnostics down by one — measured
> at 6.5.20, `-D FOO=1` moves a line-5 error to `:6` and a one-include
> `[deps] stdlib` does the same, uncompensated; only `#@incdir` was accounted
> for.

What this file adds is the **magnitude**: the shift is not "by one", it is **one
per declared stdlib module**, so a real project's diagnostics are off by the size
of its `[deps].stdlib` list. The one-include measurement understates it by the
module count.

## Measurement

Same 23-line file, same compiler, only the manifest differs.

| build context | statement at source line | reported as | shift |
|---|---|---|---|
| `cyrius.cyml` with `[deps].stdlib` of **18** modules | 13 | **30** | **+17** |
| no `cyrius.cyml` at all | 13 | **13** | 0 |

18 declared modules → +17. Consistent across every diagnostic in the file: a
67-line probe with three warnings at source lines 18, 26 and 47 reported them at
35, 43 and 64 — +17 on each.

**Line 30 does not exist**: the file is 23 lines. That is the part that costs
time — a diagnostic pointing past EOF looks like a compiler fault, so the reader
stops trusting the line numbers instead of adjusting them.

## Scope — `<source>` only

Included files are attributed correctly. In abaco proper the same warning
reported `src/eval.cyr:264`, and line 264 of that file is exactly the offending
statement. Only the top-level compiland, which the driver reports as `<source>`,
carries the shift.

That is consistent with the mechanism your changelog describes: the prepends go
in front of the entry file's buffer, and `#@file` markers fix attribution for
everything included after.

## Reproduction

```sh
# with a manifest — shifted
cd <dir with cyrius.cyml declaring 18 stdlib modules>
cyrius build probe.cyr out          # warning at :30, statement at :13

# same file, no manifest — correct
mkdir bare && cp probe.cyr lib -r bare/ && cd bare
cyrius build probe.cyr out          # warning at :13
```

## Why it is worth a slot despite being known

- The changelog frames it as "+1", which reads as a rounding error. At abaco's
  18 modules it is +17, and a project with a fuller stdlib list will be worse.
  Anyone reconciling a diagnostic against a file is off by a screenful.
- `CYRIUS_PKG_VERSION` was deliberately built to emit zero newlines *because*
  of this. That fix protects the one new prepend; the pre-existing ones —
  `[deps] stdlib` and `-D` — are still uncompensated, so the design principle is
  established and just not applied to them yet.
- The obvious fix is the one already used for includes: emit a `#@file` marker
  (or an equivalent line-directive) after the prepends so the entry file's
  numbering is restored. No new mechanism required.

## Not claimed

- Not measured on aarch64 / PE / cx, and no reason to expect a difference —
  this is front-end line accounting, not codegen.
- Not measured for `-D` scaling; your own note says `-D FOO=1` shifts by one,
  and I did not test multiple `-D` flags.
