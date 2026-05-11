# Issue: Parser cosmetic limits — bare `return;` in if-block + non-literal `var name[N]` array sizes

**Discovered:** Long-standing; vidya field-notes
`content/cyrius/field_notes/language/parser_syntax.cyml` entries
`bare_return_in_if_block_rejected` and `var_bracket_size_must_be_literal`.
Re-confirmed active at v5.8.46 during the v5.8.47 vidya audit.
**Component:** `cyrius` compiler — parser.
**Severity:** Low (mechanical workarounds exist; affects ergonomics
not correctness).
**Toolchain at filing:** `cyrius 5.8.46` (re-confirmed; entries date back to pre-v5.8.x).

## Summary

Two cosmetic parser limitations surface across the v5.8.47 vidya
audit. Both have one-line workarounds; both compile to the
"wrong shape" silently before tripping a downstream-construct
diagnostic with a confusing line number. Filed jointly because
the diagnostic-line problem is the same root cause for both —
when the parser rejects a token at position P, the error fires
at P+N where N is whatever tail-of-statement scan eats first.

## Reproductions (cyrius 5.8.46)

### `bare_return_in_if_block_rejected`

```cyrius
fn f(x) {
    if (x > 0) { return; }   # ← cyrius rejects bare `return;`
    return 0;
}
```

Compile output:

```
error:<source>:2: unexpected ';'
```

Workaround: write `return 0;` (cyrius has no void; every fn
returns an int).

### `var_bracket_size_must_be_literal`

```cyrius
var SIZE = 16;
var buf[SIZE];               # ← cyrius rejects ident as array size
```

Compile output:

```
error:<source>:3: expected number, got identifier 'SIZE'
```

Workaround: inline the literal — `var buf[16];`. For computed
sizes, switch to heap allocation: `var buf = alloc(SIZE);`.

## Why these are jointly tracked

Both are **parser-stage rejections** with **diagnostics that
fire at the offending token position**, not at a downstream
construct (so they're easier to debug than the v5.8.34-class
"fires at unrelated downstream line" bugs). Both have **trivial
mechanical workarounds**. Neither blocks any consumer today —
filed so the next premise-check sweep across vidya doesn't
re-discover them and so a future parser-grammar widening can
close them with a one-line tcyr each as the regression floor.

## Suggested fix (both)

**`bare_return_in_if_block_rejected`** — parser path that
handles `return` should accept either `return;` (synthesize
return-zero) or `return EXPR;`. Cyrius treats every fn as
returning int, so `return;` is sugar for `return 0;`.

**`var_bracket_size_must_be_literal`** — parser path that reads
the array size between `[` and `]` should accept either an
integer literal OR an ident that resolves to a top-level `var
NAME = LITERAL;` constant (compile-time-known value). Already
parses `var buf[16]`; just lift the literal-only restriction so
`var SIZE = 16; var buf[SIZE];` works.

## Acceptance gate

Two-line tcyr (one per shape) that compile cleanly OR error
with a specific diagnostic at the offending token. Bisection
results captured in the slot's CHANGELOG.

## Cross-reference

- vidya `content/cyrius/field_notes/language/parser_syntax.cyml`:
  `bare_return_in_if_block_rejected` + `var_bracket_size_must_be_literal`
  entries (both add a "Tracked at:" pointer to this file as part
  of the v5.8.47 audit so the cross-ref doesn't fall out of sync).
- v5.8.47 audit also flipped to ✅ FIXED:
  - `no_var_redecl_same_scope` (sibling if/elif var redecl works)
  - `multi_line_struct_enum_bodies_dont_parse` (multi-line bodies parse)
  - `global_init_order_silent_zero` (cyrlint warning v5.7.32 + string-lit awareness v5.7.36)
  - `no_comparisons_in_fn_args` (already flipped at v5.8.46 Part A)
