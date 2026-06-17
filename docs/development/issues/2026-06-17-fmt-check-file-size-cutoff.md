# 2026-06-17 — `cyrius fmt` (format check) has a file-size cutoff that drops large files from reporting

> **Target:** v6.2.20 (user 2026-06-17 — "review of fmt check and its file size max
> cut offs from reporting as a part of 6.2.20"). Triage; not started.

## Problem

The format check (`cyrius fmt`, the `check.sh` Format gate) appears to **cap the
file size it will report on** — the user recalls a small limit, "like 128 KB or
something." Files larger than the cutoff are silently excluded from format
checking, so a formatting / line-length regression in a big file escapes the gate.

This matters now because several files have grown past any small cap:
- `src/frontend/parse_expr.cyr` — the LSP already reports `large static data
  (~197000 bytes)` (~192 KB) for the translation unit; the source file is large.
- The folded ecosystem libs (`lib/mabda.cyr`, `lib/sigil.cyr`, `lib/yukti.cyr`,
  `lib/sandhi.cyr`, …) are sizable distfiles.

So the exact files most likely to need the format/line-length guard are the ones
the cutoff is excluding.

## v6.2.20 work

1. **Locate the cutoff.** Find the size limit in the fmt path (likely a READFILE /
   input-buffer cap in `programs/cyrfmt.cyr`, or a guard in the `check.sh` Format
   step, or the `file_map` read cap). The grep for `131072` / `0x20000` / `128*1024`
   didn't surface it immediately — it may be an indirect buffer size or a silent
   truncation rather than an explicit `> N` test. Pin the actual value + mechanism.
2. **Decide the guard.** Either raise the cap to cover the real file sizes, or
   stream/chunk the fmt read so there is no hard cap, or at minimum **fail loud**
   (report "file too large to format-check: <path> (<size> > <cap>)") instead of
   silently skipping — silent skip reads as "passed" when it didn't (the same
   silent-truncation class as the `.39` byte-length / em-dash misses).
3. Same review for `cyrius lint` if it shares the cap.

## Why it's a guard gap, not cosmetic

A silently-skipped large file means format/line-length drift (and the
cyrfmt-continuation-indent / >120-char rules) goes uncaught precisely in the files
that are hardest to eyeball. The fix is the "no silent caps — log what was dropped"
principle applied to the fmt gate.
