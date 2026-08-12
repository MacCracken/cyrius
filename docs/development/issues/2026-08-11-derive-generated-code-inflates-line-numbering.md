# `#derive` generated code inflates line numbering inside the construct

> ### ✅ RESOLVED — v6.5.20, bite 2. Design 1 rebuilt, landed, measured.
>
> **Shipped mechanism** (`src/frontend/lex_pp.cyr`, `src/common/util.cyr`). The construct
> is made to occupy exactly the source lines it consumes, in three parts:
> 1. every consumed `#derive(...)` directive line is **PADDED** with one newline (the
>    `#ifdef` mechanism from .19), in `PP_PARSE_STRUCT_DEF`;
> 2. the struct is copied **byte-for-byte** — the field look-ahead scan used to *also*
>    copy the whitespace run after every `{` / field-terminating `;`, which the enclosing
>    loop then copied again, **duplicating a newline per field**. That was the whole `+N`:
>    `struct Z { a; b = ; }` over 4 source lines occupied **7** expanded ones;
> 3. the generated bodies are **FLATTENED** onto the struct's closing-`}` line
>    (`_pp_flatten`, honoured by `PP_EMIT_STR`), which is left unterminated by the struct
>    copy and closed by the entry-point handler.
>
> The six `PP_REANCHOR_SRC/CUR` calls at the derive sites are **gone** — one less file-map
> entry per derive against the 1024 cap. `PP_DERIVE_DESER`, which emits nothing, pads
> instead. `_err_excerpt` now windows lines over 200 bytes (a 10-field
> `#derive(Serialize)` flattens to ~9.5 KB; unwindowed that was ~19 KB of stderr per
> diagnostic); short lines take the original path byte-for-byte.
>
> **The blocking defect from the purged implementation is fixed, not avoided.** The tail
> of the closing-`}` line is **COPIED, not consumed** (`PP_COPY_TAIL`), stopping at a `#`
> outside a string and never copying the newline — so `struct Z { a; } fn helper() {…}`
> and `struct Z { a; b; } var g = 77;` survive, a trailing comment is dropped (it would
> otherwise eat the flattened block), and `} var s = "#!/bin/sh";` is not truncated.
> `#derive(Deserialize)` got the same treatment; it had been dropping its tail *and* the
> struct since forever. **Measured, not asserted** — the tail sub-cases are judged on the
> program's exit code, and the shadowing sub-case (`fn helper` defined before *and* after
> the struct) is the genuinely silent one: with the tail dropped it compiles clean, warns
> nothing and returns **1 instead of 2**.
>
> > ### 🔧 FINISH-OUT (same release) — two defects the paragraph above did not actually close
> >
> > **1. A MULTI-LINE tail produced a crashing binary.** The tail was copied FIRST and the
> > generated bodies appended BEHIND it — correct only while the tail is *self-contained*.
> > Every axis-11 sub-case put the whole tail on one line, which is exactly why this
> > survived a gate whose own header calls that axis "THE LOAD-BEARING AXIS". A tail that
> > OPENS a construct continuing onto later lines
> > (`struct Z { a; b; } fn helper() {` … `}`) had every generated fn spliced INSIDE the
> > body: `rc=0`, no diagnostic beyond the routine DCE note, **SIGSEGV (139)** at runtime.
> > **Before → after: exit `139` → exit `42`.** Fixed by ORDERING — bodies first, user's
> > tail LAST, so the opener is the final thing on the expanded line and the lines
> > continuing it follow verbatim. The tail offset travels in `_pp_tail_ip`;
> > `PP_PARSE_STRUCT_DEF` records it, the entry-point handler copies it. No look-ahead and
> > no guess about what the tail opens. New **axis 11b** covers `fn` / `if` / `while` /
> > `struct` openers and the shadowing form.
> >
> > **2. `#derive(Deserialize)` still DELETED the struct.** Only the tail half had been
> > repaired; the handler still hand-rolled "skip the directive line, scan to the first
> > `}`" instead of routing through `PP_PARSE_STRUCT_DEF`. Two halves, measured on the
> > shipped compiler:
> > (a) the type was unusable — `#derive(Deserialize) struct D { x; y; }` then
> > `var d = D { 12, 48 };` → **`error:<source>:4:15: undefined variable 'D'`**; now
> > compiles and returns **60**;
> > (b) the serious half — a malformed field was **SILENTLY ACCEPTED**:
> > `struct D { x; y = ; }` compiled **rc=0, zero diagnostics**, because the parser is what
> > checks field syntax and the parser never saw the text. Now
> > **`error:<source>:2:17: expected identifier, got '='`** with the caret, matching the
> > `Serialize` / `accessors` control byte for byte. Collateral fix: stacking in the
> > Deserialize-FIRST direction (`#derive(Deserialize)` above `#derive(accessors)`) never
> > collected the flag bits, so the stacked handler was dropped whole — the reverse order
> > always worked, which is why nobody noticed. New **axis 14** covers all of it.
> >
> > Two more mutants, built and run: **M9** (revert the ordering) → RED on axis 11b only,
> > 5 sub-cases; **M10** (revert `PP_DERIVE_DESER`, keeping the tail copy) → RED on axis 14
> > + the stacked 11b sub-case, while axis 11's one-line `Deserialize, fn after }` stays
> > GREEN — it only ever proved the TAIL survived, never the struct, which is how this
> > shipped.
>
> **Measurements (all re-run, none re-used):**
> * repro: `error:<source>:6:7` for the defect `grep -n` puts on **line 6** (was `7:7`).
> * synthesized duplicates, 14-line file: all four report **line 12**, the closing `}` of
>   the construct that generated them (was **15, 16, 17, 18** — every one past EOF).
> * randomized attribution sweep, **2304 cases** (5 derive kinds × field counts ×
>   one-line/multi-line × 4 tail shapes × leading pad × trailing pad × `#ifdef` × 3 defect
>   positions): **2304 exact**. The same sweep on 6.5.19: **256 wrong**, every one an
>   in-struct `+1`.
> * codegen neutrality: **790** files under `~/Repos` containing `#derive` compiled old vs
>   new — **790 binary-identical, 0 stderr differences** (237 of them produce a binary;
>   the rest are library modules whose stderr matched). ⚠ **Quote this number with the
>   command that derives it**, because two defensible counts exist and the difference is a
>   property of your *tooling*, not of the tree:
>
>   ```sh
>   find ~/Repos -path '*/.git' -prune -o \( -name '*.cyr' -o -name '*.tcyr' \
>       -o -name '*.bcyr' -o -name '*.fcyr' -o -name '*.scyr' -o -name '*.smcyr' \) \
>       -type f -print0 | xargs -0 /usr/bin/grep -l '#derive' | wc -l     # -> 790
>   ```
>
>   The same expression written with a bare `grep -rl … --include=…` returns **591** in an
>   agent shell, because `grep` there is a wrapper function routed to `ugrep
>   --ignore-files`, which honours `.gitignore` and drops ~199 ignored files. 790 is every
>   such file on disk; 591 is the tracked subset. **Both are real — neither is "the"
>   number — so name the tool.** (A finish-out pass re-ran the full differential
>   independently against a compiler with *both* v6.5.20 tail fixes reverted: **790 files,
>   790 identical, 0 binary differences, 0 stderr differences.**)
> * `tests/tcyr/derive/` — **10** files (this issue's "34" was wrong), 10/10 pass. Full
>   corpus 270/270 by exit code. `check.sh` **178 passed / 0 failed**. Self-host fixpoint
>   **1,154,768 B**, seed → cybs → cycc derivable. `SELFHOST_OK: ecb` + crossos 46/46.
> * **`cyrfmt --check` is NOT clean on the changed compiler sources, and no claim that it
>   is should stand.** Measured: `src/main.cyr`, `src/common/util.cyr`,
>   `src/frontend/lex_pp.cyr`, `src/frontend/parse.cyr` and `src/frontend/parse_fn.cyr`
>   each exit **1** (dirty), and each exits 1 at HEAD too — so nothing regressed, and
>   nothing is clean. cycc's own source is hand-formatted by design and cyrfmt disagrees
>   with it; the tool reports this SILENTLY (exit 1, no output), which is exactly how a
>   "fmt clean" claim gets written down without being run. The `.tcyr` files touched in
>   this release *are* clean (exit 0), which is the assertion worth making.
> * the `#` audit was exhaustive, not a spot check: **191** `PP_EMIT_STR` call sites, 178
>   with a string-literal argument, parsed escape-aware. **Exactly one** carried a `#` —
>   the `# nested struct — skip for single-pass` line in the generated `_from_json` —
>   deleted. The 13 non-literal arguments are struct/field/type names from source.
>
> **Gate:** `tests/gates/frontend/duplicate_fn_attribution.sh` axes **9–14** (in-struct
> defect, synthesized duplicate, no-silent-code-loss, **multi-line tails**, long-line
> windowing, nested-struct `#`, **`#derive(Deserialize)` keeps the struct**). Eleven new
> mutants built and run; **M3b** (drop only the tail copy, line accounting left perfect) is
> caught by **axis 11 alone**, **M6** (no flattening) by **axis 10 alone**, **M9** (tail
> copied before the bodies) by **axis 11b alone**, and **M10** (hand-rolled Deserialize
> skip) by **axis 14** plus one 11b sub-case. Design 2 (per-span delta table) was not
> needed and stays out of scope.
>
> **Measured non-discriminators, recorded rather than glossed** (a gate is only as honest
> as its known blind spots): an *unstacked* `#derive(Deserialize)` cannot catch M9 — it
> emits no bodies, so there is nothing to splice — and neither can an `if` or `while` tail,
> because cyrius hoists `fn` definitions out of a top-level block. The Deserialize sub-case
> was therefore rewritten as the stacked form; the `if`/`while` sub-cases stay as cover for
> the risk running the other way (the fix MOVES the tail, and a tail that opens a block must
> still open it).
>
> *Archive this file at slot close.*

**Status:** ✅ RESOLVED in v6.5.20 (bite 2). Was: 🔴 OPEN — the measured residual of the
v6.5.19 duplicate-fn attribution fix.
**Severity:** Low. Every diagnostic OUTSIDE a `#derive` construct is now exact; this is a
small, bounded offset for diagnostics that land inside one, and for warnings about fns the
derive SYNTHESIZED (which have no source `fn` line at all).
**Filed rather than fixed because:** closing it needs a **design decision about how
generated code is represented in the expanded stream**, and every candidate changes the
output of the three `#derive` handlers, which 34 `.tcyr` files under `tests/tcyr/derive/`
depend on. That is the maintainer's call, not a bug fix.
**Placement:** **v6.5.20, bite 2** — after the switch-case P1 (a silent miscompile outranks a
diagnostic offset), on the same four-host gate cycle. The two touch different files
(`parse.cyr` vs `lex_pp.cyr`) so they do not collide.

> ### ⛔ SIZING CORRECTION (re-triage 2026-08-11) — the implementation is NOT on disk
>
> The v6.5.19 handoff recorded design 1 (flatten each derive body onto ONE expanded line, then
> pad to the consumed source-line count) as **built and independently verified** — fixpoint
> held, all 589 `#derive` files across `~/Repos` byte-identical, 300 randomized derive programs
> with zero codegen diff, and a 240-case attribution sweep going 185-wrong → **0**-wrong — and
> instructed that it be **rebased, not 3-way applied**.
>
> **There is nothing to rebase.** The named scratchpad path does not exist, no `lex_pp*` variant
> exists anywhere under `/tmp`, and all 8 git worktrees carry an identical *older*
> `src/frontend/lex_pp.cyr` distinct from main's. `grep 'flatten' src/frontend/lex_pp.cyr`
> returns nothing; `PP_EMIT_STR` has no flatten mode.
>
> The **design** survives in this file and is not lost; only the code is. Size the slot for a
> **REBUILD**, and treat every verification as a **re-run, not a re-use** — the fixpoint, the
> 589-file byte-identity sweep, the 300 randomized programs, and the 240-case attribution sweep
> all have to happen again, plus new coverage for the remedy below.
>
> The blocking defect and its remedy remain well-specified: the closing-`}` tail changed from
> COPY to CONSUME, so `struct Z { a; } fn helper() { return 2; }` compiles clean, warns nothing
> and returns the WRONG answer — **silent code loss**. Remedy: copy the tail, stop at the first
> `#`, never copy the newline. The remedy needs its own negative fixture; a derive test that
> only checks line numbers will not see code go missing.

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
