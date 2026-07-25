# `iv_add`/`iv_sub`/`iv_mul` reserved SIMD intrinsics shadow variable names with a misleading error — RESOLVED

> **✅ RESOLVED in v6.4.77** (`src/common/util.cyr`; CHANGELOG [6.4.77]).
>
> `var iv_add = 1;` now reports
> `reserved keyword 'iv_add' (cannot be used as an identifier; rename the variable/field/fn)`.
>
> **Scope was 67 tokens, not the 3 filed.** Root cause: `IS_KEYWORD_TOK` *and* `TOKNAME` both stopped
> at token 111, so `ERR_EXPECT` could neither classify nor name anything above it. Fixed for the whole
> class (`syscall`, `load8/16/32/64`, `store8/16/32/64`, all `f64_*`/`f64v_*`/`f32_*`/`f32v_*`/
> `f32v8_*`/`iv_*`, `union`, `defer`, `secret`, `async`, `await`, `u128`, `bitget/bitset/bitclr`,
> `ret2/rethi`) — a filing enumerates what it hit, not the class. Names live in a new
> `TOKNAME_BUILTIN` and `IS_KEYWORD_TOK` **derives** from it, so the two sets cannot drift.
>
> **Two corrections to this document:**
>
> 1. **`iv_div` was not "never reserved" for the reason given.** The doc reasons "there is no integer-
>    vector divide instruction, so `iv_div` was never reserved" — correct conclusion, but the pattern is
>    broader than `iv_*`: 67 unrelated names had the identical failure, so the apparent randomness was
>    not about the `iv_` prefix at all.
> 2. **The cascade is a SEPARATE, pre-existing defect and is NOT fixed here.** This doc attributes the
>    downstream `expected '(', got ')'` / `undefined variable` noise to the desync from this bug. At
>    6.4.77 a well-formed file with reserved names reports cleanly (1–2 errors, no flood). The real
>    cascade needs input that ends **mid-construct**, produces **166,670 lines**, and reproduces
>    identically on 6.4.76 — root-caused to unbounded `PEEKT`/`TOKTYP` reads and filed as
>    [`2026-07-24-truncated-input-166k-line-error-cascade.md`](../2026-07-24-truncated-input-166k-line-error-cascade.md).
>    It was deliberately not bundled: not a prerequisite, and `PEEKT` is the parser's hottest fn.
>
> **Also fixed, found while mapping this:** the diagnostic actively named the WRONG keyword for the two
> double-assigned token numbers — `var f64_sqrt` said "reserved keyword 'object'" (token 79) and
> `var callptr` said "'stack'" (token 111). Both now name both spellings.
>
> **Gate:** `_reserved_kw_diag_gate` extended 6 → 19 subcases, mutation-proven in both halves, with a
> negative control asserting `got unknown` never appears for a reserved name.
>
> hisab may revert its `iv_sum`/`iv_diff`/`iv_prod` rename — though note these names remain **reserved**
> (they are real intrinsics); the fix makes the compiler *say so* clearly, it does not free the names.

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
