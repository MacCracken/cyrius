# `iv_add`/`iv_sub`/`iv_mul` reserved SIMD intrinsics shadow variable names with a misleading error — OPEN

**Discovered:** 2026-07-17 while bumping the **hisab** math library to cycc 6.4.66 (its
`tests/modules.tcyr` suite would not compile).
**Severity:** Medium — hard failure on a shipping consumer's build; workaround available
(rename the variable). The underlying issue is a **misleading diagnostic** (Low-class), but
it presented as an opaque whole-suite compile failure.
**Affects:** cycc **6.3.11 → 6.4.66** (every version tested: 6.3.11, 6.4.5, 6.4.6, 6.4.65,
6.4.66 — reproduces on each version's own compiler, deterministically 8/8).

## Summary

The packed-integer SIMD intrinsics `iv_add`, `iv_sub`, `iv_mul` (and `iv_dp8`) are reserved
keyword tokens in the lexer. When one of those names is used as an ordinary **variable name**
(`var iv_add = ...`), the parser reports:

```
error:<source>:1:5: expected identifier, got unknown
    var iv_add = 1;
        ^
```

The diagnostic is misleading twice over: (1) it points at a syntactically clean identifier,
and (2) it labels the reserved-intrinsic token as `unknown` rather than saying the name is
reserved. The parse then desyncs — subsequent lines cascade into `expected '(', got ')'` and
`undefined variable <name>`, so in a large file the *real* line is buried and only found by
bisection. `iv_div`, `iv_neg`, `iv_abs`, and any other `iv_*` name are unaffected (there is no
integer-vector divide instruction, so `iv_div` was never reserved) — which is what makes the
failure look random rather than name-based.

Consumer impact: hisab's interval-arithmetic test named its result vars `iv_add`/`iv_sub`/
`iv_mul`; the whole 312-assertion `modules.tcyr` suite failed to compile with no actionable
error. Renaming to `iv_sum`/`iv_diff`/`iv_prod` fixed it.

## Reproduction

`docs/development/issues/repros/2026-07-17-iv-intrinsic-var-name.cyr` (two lines):

```cyrius
include "lib/syscalls.cyr"
var iv_add = 1;
```

```
$ cyrius test docs/development/issues/repros/2026-07-17-iv-intrinsic-var-name.cyr
error:<source>:1:5: expected identifier, got unknown
    var iv_add = 1;
        ^
```

Deterministic 8/8. `var iv_sub` / `var iv_mul` behave identically; `var iv_div` /
`var iv_neg` / `var iv_xyz` compile clean. No stdlib beyond `syscalls` is needed — the
intrinsic is reserved at the lexer level, independent of whether `lib/simd.cyr` is included.

## Root cause (known)

`src/frontend/lex.cyr` (~lines 991-997) tokenizes these names unconditionally as intrinsic
tokens:

```
# v6.4.6 (Phase 3a) — packed integer ops iv_add/iv_sub/iv_mul(dst,a,b,n,w):
if (kw & 0xFFFFFFFFFFFF == 0x6464615F7669) { ADDTOK(S, 143, 0); return p; }  # iv_add
if (kw & 0xFFFFFFFFFFFF == 0x6275735F7669) { ADDTOK(S, 144, 0); return p; }  # iv_sub
if (kw & 0xFFFFFFFFFFFF == 0x6C756D5F7669) { ADDTOK(S, 145, 0); return p; }  # iv_mul
if (kw & 0xFFFFFFFFFFFF == 0x3870645F7669) { ADDTOK(S, 146, 0); return p; }  # iv_dp8
```

So `iv_add` always lexes as token 143 (not an identifier token). In `var <name>` position the
parser wants an identifier, gets token 143, and falls through to the generic
`expected identifier, got unknown` path — the "unknown" label is the parser's catch-all for
an unexpected keyword token here. `parse.cyr` / `parse_expr.cyr` consume these tokens in
call position only, so nothing rebinds them as identifiers elsewhere. (Empirically the
reservation predates the `v6.4.6` annotation — 6.3.11 rejects it too — so the comment marks a
refinement of the op, not the introduction of the reserved name.)

## Proposed fix

Two independent options; (1) is the minimum:

1. **Diagnostic** — when the parser expects an identifier and finds one of the intrinsic
   keyword tokens (143-146, and any sibling in that block), emit a specific message, e.g.
   `error: 'iv_add' is a reserved SIMD intrinsic and cannot be used as a name` — and don't
   desync (recover as if it were an identifier so following lines don't cascade). This alone
   would have turned a multi-hour bisection into a one-line fix.
2. **Contextual keywords** — treat `iv_add`/`iv_sub`/`iv_mul`/`iv_dp8` as *contextual*
   intrinsics: keyword only when immediately followed by `(` in call position, otherwise a
   normal identifier. This removes the footgun entirely (user code can name variables/fields
   `iv_add`), at the cost of a one-token lookahead in the lexer/parser. Matches how many
   languages handle soft keywords.

## Consumer-side workaround (shipped)

hisab renamed the three variables to `iv_sum` / `iv_diff` / `iv_prod` (hisab v2.6.9), with a
`NOTE:` comment guarding the names and a mirror issue at
`hisab/docs/development/issues/2026-07-17-cyrius-interval-ident-lex.md`. Any consumer hitting
`expected identifier, got unknown` on an obviously-clean `var`/field name should check the
name against the `iv_*` intrinsic set before chasing syntax, includes, or file size.

**Reporting on:** cycc 6.4.66. **Recommended floor for the fix:** whatever release lands the
improved diagnostic — the reservation itself is not going away, so option (1) is the durable
win for consumers.
