# `find_files` / `find_files_with_prunes` silently return 0 matches — RESOLVED

> **✅ RESOLVED in v6.4.72** (`lib/fs.cyr`; CHANGELOG [6.4.72]).
>
> **The speculated root cause in this document was WRONG** — it was not allocator aliasing and
> not a "heap regime" issue. `find_files(path, ext)` had an **untyped `ext` param**, and the
> compiler's literal→`Str` auto-coercion in `PARSE_FNCALL` fires only for a param declared
> `: Str`. So a bare `".cyr"` arrived as a raw cstring POINTER, and `str_ends_with` read its
> length from `load64(ptr + 8)` — garbage — so every entry failed the suffix test. The
> ingredients each worked in isolation precisely because `str_ends_with` IS typed `: Str` and
> therefore coerced the literal at its own call boundary. `find_files(path, str_from(".cyr"))`
> always returned the full set.
>
> Fixed by annotating `path`/`ext` as `: Str` on `find_files`, `find_files_with_prunes`, and
> `path_has_ext`. Verified 2026-07-23 on 6.4.73: all four forms (bare literal, `str_from`,
> `dir_walk` control, and `find_files_with_prunes`) agree at **34 matches** over `src/`.
>
> **The caller audit this issue asked for came back clean.** The TS-corpus release gates
> (`programs/checks/ts.cyr:408`, `programs/ts_test_runner.cyr:206`) already passed
> `str_from(...)` for both args, so they were **never** silently vacuous — the placebo risk was
> real as a class but did not materialize. `programs/vidya.cyr:186` and
> `programs/cyrius-init.cyr:892` likewise wrap. `cbt/quality.cyr`'s `cmd_coverage` keeps its
> `dir_walk` + inline `str_ends_with` form as the equivalent simplest shape.
>
> **The residual worth remembering is the language-level footgun, not this one function:** an
> untyped param silently receives an un-coerced cstring pointer wherever a `Str` is expected.
> That is a silent-wrong-value class across any stdlib fn with an untyped string param.


**Discovered:** 2026-07-23 while fixing `cyrius coverage` (`cbt/quality.cyr`, issue
`2026-07-23-hoosh-coverage-reports-stdlib-not-local-repo.md`). The coverage rewrite had to
abandon `find_files`/`find_files_with_prunes` and use `dir_walk`/`dir_walk_with_prunes` +
an inline `str_ends_with` filter to work at all.
**Severity:** **Medium–High** — silent wrong output with a **placebo risk**: these helpers
back the TS-corpus release gates (per the `lib/fs.cyr` comment), and a gate that walks a
tree with `find_files_with_prunes` and finds 0 files would **pass vacuously**.
**Affects:** `lib/fs.cyr` (`find_files` `:255`, `find_files_with_prunes` `:311`; verify
line numbers). Observed on cycc 6.4.72.

## Summary

`find_files(path, ext)` returns **0 matches** even when, on the same path in the same
program:
- `dir_walk(path, vec)` returns the files (e.g. 34 for `src/`), and
- `str_ends_with(<a walked path>, ".cyr")` / `path_has_ext(<same>, ".cyr")` returns `1`
  in isolation.

So both of `find_files`'s ingredients work, but the composed function returns nothing.

## Reproduction

From the cyrius repo root, a program including
`syscalls/string/alloc/vec/str/fmt/io/fs` and calling, as the **first** fs call:

```cyrius
var a = find_files(str_from("src"), ".cyr");   // vec_len(a) == 0   (WRONG; src/ has 34 .cyr)
```

whereas:

```cyrius
var all = vec_new();
dir_walk(str_from("src"), all);                // vec_len(all) == 34  (correct)
str_ends_with(vec_get(all, 0), ".cyr");        // == 1               (correct)
```

Deterministic. A manual filter loop over `all` with `str_ends_with` gives 34 matches — so
only the `find_files` wrapper is broken.

## Root cause (speculation — not yet bisected)

`find_files` does `dir_walk(path, all)` then `var matched = vec_new()` and filters `all`
via `path_has_ext(fp, ext)`. Candidates:
- **Allocator aliasing:** `all` holds `path_join` outputs (heap `Str`s); a subsequent
  `vec_new()` / `vec_push` (or `dir_walk`'s recursion) may clobber that string data, so the
  filter reads garbage and every entry fails the ext test. There is precedent for exactly
  this class in `dir_list`'s own `v5.9.6` comment (borrowed getdents buffer pointers).
- Or a bug in the filter/`matched` handling itself.

Not root-caused here (out of scope for the coverage fix, which worked around it).

## Proposed fix

1. Root-cause it (allocator aliasing vs filter logic). If aliasing, ensure `path_join`
   results survive across later allocations, or clone before filtering.
2. Fix `find_files` + `find_files_with_prunes` so they match `dir_walk` + inline filter.
3. **Audit every caller** — especially the TS-corpus release gates that use
   `find_files_with_prunes` — and **mutation-check** that they actually see files (a gate
   currently finding 0 is a green placebo, the exact class CLAUDE.md warns about).

## Consumer-side workaround

`cbt/quality.cyr`'s `cmd_coverage` (6.4.72) uses `dir_walk` / `dir_walk_with_prunes` +
inline `str_ends_with` instead — the proven-correct path. Any other code hitting a
0-result from `find_files` should do the same until this is fixed.
