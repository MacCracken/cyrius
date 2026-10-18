# Two refused pass-1 const contexts evaluated in place (enum values, global array sizes, top-level `#assert`) print only the first error — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend @ 4e858a94, after unit F1's
fix of `issues/archived/2026-10-09-const-sweep-swallows-later-const-errors.md`) and on the slot-open compiler (6.7.14 @ 2600f67f):
every input below is refused (rc 1, no binary), but only its FIRST const-context error is printed.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F1, probing past the const-sweep issue's table (its rows
are a const, a default or a pass-2 statement AFTER a pass-1 refusal; these are two pass-1 in-place refusals).
**Severity:** Low — every input is invalid and refused; the cost is a missing error (one compile per bad declaration).
**Affects:** cycc 6.7.2 (const contexts) through the 6.7.14 frontend lane.

## Reproduction

Each file is compiled with `build/cycc < f.cyr > /dev/null`.

| source (`\n` between lines) | lane tree after F1 | slot-open | expected |
|---|---|---|---|
| `enum E { Q = yy }` `enum F { R = ww }` `syscall(60, 0);` | `1:14 'yy'` only | the same | `1:14 'yy'` and `2:14 'ww'` |
| `var g: i64[yy];` `var h: i64[ww];` `syscall(60, 0);` | `1:12 'yy'` only | the same | `1:12 'yy'` and `2:12 'ww'` |
| `enum E { Q = yy }` `const A = 2;` `var g: i64[ww];` `syscall(60, 0);` | `1:14 'yy'` only | the same | `1:14` and `3:12` |
| `#assert yy == 1, "a";` `#assert ww == 1, "b";` `syscall(60, 0);` | `1:9 'yy'` only | the same | `1:9` and `2:9` |
| `var g: i64[yy];` `enum E { Q = ww }` `syscall(60, 0);` (control) | both (`1:12`, `2:14`) | `1:12` only | both |

(Each message reads `error:<source>:L:C: unknown name 'NAME' in a const context`.) Within ONE enum,
`enum E { Q = yy, R = ww }` also prints only `yy`; whether a second refusal inside one declaration should print is
the same question for the cascade latch, and is part of this filing's decision surface.

## Root cause

- The in-place evaluations (`_ce_eval_here` / `_ce_eval_int`, src/frontend/parse_fn.cyr; called for an enum value
  through `_enum_val` → `_cst_ctx_val`, for a global array size from `PARSE_GVAR_ARR`, src/frontend/parse_decl.cyr
  ~:3665, and for `#assert`) report through `_ce_bad` / `_ce_badn` → `ERR_MSG` / `ERR_IDENT`, which set the cascade
  latch `_panic`.
- Pass 1's declaration loop (`_tl_pass1` → `_tl_scan1`) never resyncs, so the latch is still set when the next
  declaration's in-place evaluation refuses: its message is swallowed. 6.7.14 F1 cleared the latch only around a
  const's / default's own evaluation (`_ce_top_expr`) and at the start of pass 2.
- Pass 2 does not re-evaluate an enum value: `_cst_ctx_val` memoises a refused value by token (`_clm_add`), so the
  swallowed error is never printed later either.

## Proposed fix

Evaluate a pass-1 in-place const context with the latch clear when the cursor is left in sync after a refusal (an
enum value whose `_cst_ctx_skip` reached a member boundary, a global array size whose `]` follows, a top-level
`#assert` ending at its `;`), restoring the caller's latch, as `_ce_top_expr` does since 6.7.14; a malformed
expression that leaves the cursor mid-declaration keeps the latch. Rows (tests/gates/frontend/const_checked.sh):
the table above, each error once, plus a malformed value (`enum E { Q = (1 + }`) that still reports one error.
