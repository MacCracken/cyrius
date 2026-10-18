# A constant left operand, then `+ - & | ^` and a literal followed by `*%`, `*|`, `*?` or `>>>`, is refused "expected ';'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F3, after the
const-init item-2 fold rewrite, which kept this reading unchanged on purpose) and on every installed compiler from
6.6.0 through 6.7.14 and `build/cc5` (5.11.69): all refuse the repro.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F3, reading the run-time fold arms for
`issues/archived/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md` item 2.
**Severity:** Medium — valid code does not compile (a codegen bug: the compiler fails valid cyrius); no wrong value is
produced (the build stops).
**Kind:** bug (frontend, the run-time constant fold).

## Reproduction

```cyrius
fn f(): i64 { return 2 + 3 *% 4; }
syscall(60, f());
```
```
error:<source>:1:28: expected ';', got '*%'
```
rc 1, no binary. The same with `>>>`, `*|`, `*?`, and after `- & | ^`:

```cyrius
fn f(): i64 { return 2 + 16 >>> 2; }      # error: expected ';', got '>>>'
fn g(): i64 { return 1 | 2 *% 4; }        # error: expected ';', got '*%'
```

Controls that compile and give the right value: a variable on the left (`var x = 3; return 2 + x *% 4;` → 14), a
constant NAME on the right (`const C = 3; return 2 + C *% 4;` → 14, since 6.7.14's item 2), the literal `*` / `/`
/ `%` / `<<` / `>>` (`return 2 + 3 * 4;` → 14), and the same initializer in the declaration zone (`var x = 2 + 16
>>> 2;` → 6, the pass-1 folder).

## Root cause

The `+ - & | ^` arms of `_PEXPR_IMPL` (src/frontend/parse_expr.cyr) fold a literal right operand into the armed
constant left one (`_cfo`) when the token after the literal is not a term operator — but the test (`_cf_excl` since
6.7.14, the inline `nt != 8 / 9 / 34 / 38 / 39` chain before it) lists only `* / % << >>`. For `*%` (119), `*|`
(120), `*?` (121) and `>>>` (152) the arm folds `2 + 3`, steps over the `3`, and `_PEXPR_IMPL`'s loop then meets a
term operator it has no arm for: the expression ends and the statement reports "expected ';'".

## Fix

Add 119, 120, 121 and 152 to `_cf_excl` (the arm then reads the whole right term with `_cf_term_at`, which folds `*%`
like `*` and leaves `*|`, `*?`, `>>>` to run time). Rows: the four operators after each of `+ - & | ^`, by value, on
x86_64 / aarch64 / cx (beside `tests/gates/frontend/const_init_bake_and_fold.sh` F16-F21).
