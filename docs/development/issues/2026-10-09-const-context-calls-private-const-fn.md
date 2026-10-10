# A const context calls another file's `private` const fn with no visibility check (and no `#deprecated` warning) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`/home/macro/.cache/c6/wt677/int`
@ 06bd8981, its `build/cycc`, 1,916,288 B). The repro builds and exits 3. A call to the same fn from a fn body, or
from `var X = pk();` at top level, is refused with "'pk' is private to its file". Every const context was measured
and each one accepts the call: a top-level `const`, a local `const`, a local or global array size, an enum value,
`#assert` and a `switch` `case` label. A `#deprecated` const fn called from a const context does not warn, while the
run-time call does. Identical on the installed 6.7.2 and 6.7.6 compilers.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x;
it is a const-evaluator call-resolution bug, placed beside the 6.7.7 call-argument follow-ons.
**Discovered:** 2026-10-09 by the 6.7.7 B6 lane (default and named arguments), bite 2, outside its scope. The 6.7.7
CHANGELOG draft records that no issue file existed; filed 2026-10-09.
**Severity:** Medium — the documented `private` boundary is defeated on one call path, silently. This is a visibility
bug, not a security issue: the code that crosses the boundary is the developer's own.
**Affects:** cycc 6.7.2 (`const fn`) through the merged 6.7.7.

## Summary

The guide's visibility section (cyrius-guide.md § "Visibility — `private` / `public`") says "the boundary covers
every way of reaching a fn, not just a direct call". The const evaluator is the exception. It reads a `private`
CONST of another file and refuses it, as gate `const_checked.sh` V1 requires. It calls a `private` CONST FN of
another file and runs it. The per-callee check that every other call path makes is skipped, so the `#deprecated`
warning is lost on the same path.

## Reproduction

`docs/development/issues/repros/2026-10-09-const-context-calls-private-const-fn/` (`a.cyr` includes `b.cyr`):

```cyrius
# b.cyr
private
const fn pk(): i64 { return 3; }
```

```cyrius
# a.cyr
include "b.cyr"
const X = pk();
syscall(60, X);
```

```
cd docs/development/issues/repros/2026-10-09-const-context-calls-private-const-fn
cat a.cyr | ../../../../../build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
actual:   builds; exits 3
expected: error:<source>:5:11: 'pk' is private to its file   (rc 1)
```

The same `include "b.cyr"` followed by each of these builds and runs:
- `fn main(): i64 { const L = pk(); return L; }`
- `var g: i64[pk()];`
- `fn main(): i64 { var a: i64[pk()]; return 1; }`
- `enum E { A = pk() }`
- `#assert pk() == 3, "x";`
- `switch (x) { case pk(): .. }`

These are refused, correctly:
- `var X = pk();`
- `fn main(): i64 { return pk(); }`

`#deprecated("old")` on a one-file `const fn dk()` produces these results:
- `fn main(): i64 { return dk(); }` warns "'dk' is deprecated: old".
- `const X = dk();` is silent.

## Root cause

All locations are in `src/frontend/parse_fn.cyr` at the merged tip.

- `_ce_name` (:7568) sends `NAME(` to `_ce_call` (:7572). `_ce_call` (:7670) resolves the callee with `FINDFN` and
  checks only that it is a `const fn` (`GFCFN`), then runs it. The named-argument form `_ce_call_named` (:7705) is
  reached from `_ce_call` after the same lookup, so it has the same gap.
- `_ce_call` never calls `_callee_site_checks` (:5345). That is the one per-callee check (`_vis_check` :5423 +
  `_DEPRECATED_WARN`), which every other path that resolves a name to a fn goes through (its comment: "A new call
  path is ONE call here").
- The const READ beside it has the check: `_ce_name` runs `_vis_check_var` on a top-level const (:7593-7602), with
  the cursor on the name, and turns a refusal into `_ce_err`.

## Proposed fix

In `_ce_call`, after the `GFCFN` test and before the named-call branch, call
`_callee_site_checks(S, fi, noff, _ce_ti)` with the call's NAME token, and turn a new refusal into `_ce_err` exactly
as the const read does (`_panic` compared before and after). Do it only when `_ce_infn == 0` and `_ce_skip == 0`:
- A call inside a const fn's body is compiled by the parser too, and the parser reports it once.
- The definition check runs in SKIP mode.

Because the caller's file is taken from the call's own token (`FM_FILEID(GTLINE(ti))`), a parameter default's call is
judged in the default's own file. Gate row `default_named_args_checked.sh` E2 must stay green: a default naming its
own file's private const fn, called from another file, exits 149.

Rows in `const_checked.sh` (beside V1):
- each const context above, refused once by name;
- the same-file call accepted;
- a `public const fn` in a private file accepted;
- the `#deprecated` warning in a const context, once.

This refusal makes code that compiles today stop compiling. It is the boundary the guide already documents, and the
one V1 enforces for a const read, so it needs no new semantics.
