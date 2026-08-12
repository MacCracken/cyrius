# `#derive` generated code inflates line numbering inside the construct

**Status:** 🔴 OPEN — the measured residual of the v6.5.19 duplicate-fn attribution fix.
**Severity:** Low. Every diagnostic OUTSIDE a `#derive` construct is now exact; this is a
small, bounded offset for diagnostics that land inside one, and for warnings about fns the
derive SYNTHESIZED (which have no source `fn` line at all).
**Filed rather than fixed because:** closing it needs a **design decision about how
generated code is represented in the expanded stream**, and every candidate changes the
output of the three `#derive` handlers, which 34 `.tcyr` files under `tests/tcyr/derive/`
depend on. That is the maintainer's call, not a bug fix.

## What v6.5.19 fixed, and what it did not

v6.5.19 made `FM_LOOKUP`'s span arithmetic exact by keeping the expanded stream
line-faithful with the source: the `#ifdef` family pads one newline per consumed or
skipped line, and `#derive` — which ADDS lines and cannot be padded — re-anchors with a
`#@file` marker **after** the expansion. Everything after a derive is therefore exact, and
drift no longer accumulates across a file.

Inside the construct it is still off, because the expansion is longer than the source it
replaces. Measured on cycc 6.5.19 (`…/scratchpad/b2/instruct.cyr`, the bad field on
**source line 6**):

| | 6.5.18 | 6.5.19 |
|---|---|---|
| error inside a `#derive`d struct | `7:7` (+1) | `7:7` (+1) — unchanged |
| duplicate SYNTHESIZED accessor, 12-line file | `17`–`20` (5–8 past EOF) | `12`–`15` (0–3 past EOF) |

Two sources of inflation, both inside `PP_PARSE_STRUCT_DEF` / the derive bodies
(`src/frontend/lex_pp.cyr`):

1. the `#derive(...)` **directive line** is consumed and never re-emitted (−1 line), while
2. the struct is re-emitted with **extra whitespace lines**, and the accessor / serializer
   **body** adds 2 lines per field against the struct's 1 (+N lines).

They partially cancel, which is why the struct-internal error is only +1.

## Why the obvious repairs do not work — both tried and measured

* **Re-anchor BEFORE the expansion, based at the `#derive` line.** Implemented, measured,
  **reverted**: the struct's re-emitted lines then inherit that base, so a diagnostic
  inside the struct moved from +1 to **+2**. It improves the synthesized-fn case and
  regresses the more common one.
* **Pad the consumed directive line** (the `#ifdef` mechanism). Implemented, measured,
  **reverted**: it removes the −1 that was cancelling part of the struct's +N, so the
  struct-internal error also moved to **+2**.

Neither is a matter of picking a better base — the block simply occupies more expanded
lines than the source it came from, and a linear `expanded − start + base` map cannot
represent that.

## The two designs that would close it

1. **Emit each derive body on ONE expanded line**, then pad to the consumed source-line
   count. Line accounting becomes exact with NO markers, and every synthesized fn reports
   the line of the construct that produced it. Needs a flatten mode in `PP_EMIT_STR`
   (newline → space) plus an audit that no generated text contains a `#` comment (a `#`
   on a flattened line would comment out everything after it). Long lines then reach
   `_err_excerpt`, which prints the offending source line — acceptable for machine-written
   code, but it is a visible change.
2. **A per-span line-delta table** consulted by `FM_LOOKUP`, so a span can carry
   adjustment points instead of one linear base. Exact for every construct, but it is a
   new heap region ⇒ **heap LAYOUT change ⇒ two-step bootstrap**.

## Acceptance criteria

- A diagnostic inside a `#derive`d struct reports the line `grep -n` finds.
- A `duplicate fn` warning for a derive-SYNTHESIZED name reports a line inside the file,
  attributable to the construct that generated it.
- Extend `tests/gates/frontend/duplicate_fn_attribution.sh` with a synthesized-duplicate
  axis (a `struct X` declared twice, both `#derive(accessors)`), mutation-proven.

## Repro

```sh
printf 'fn pad_a() { return 1; }\nfn pad_b() { return 2; }\n#derive(accessors)\nstruct Z {\n    a;\n    b = ;\n}\nfn main() { return 0; }\nvar r = main();\n' > /tmp/d.cyr
build/cycc < /tmp/d.cyr > /dev/null 2> /tmp/d.err; head -1 /tmp/d.err   # says 7, the defect is on 6
```
