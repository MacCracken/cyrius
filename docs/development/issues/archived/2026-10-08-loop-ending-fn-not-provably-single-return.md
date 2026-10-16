# A fn whose body ends in `loop { … }` / `do … while` / `while (1)` is not "provably one value" — RESOLVED

> ✅ **RESOLVED in v6.7.11** (RET-1, commit 48155669: a body whose last statement is `loop { }`, `while (1) { }` or `do { } while (1);` — its block closing the body, holding a `return`, with no `break` that leaves it — is proved one value, as a final `return` is. The repro and both variants are refused on x86_64, aarch64, cx and PE with the 6.6.17 message, *multi-value destructure binds 2 names, but 'one' returns 1 value - bind it to one name* (they built and bound a stale rdx: 0 / 0 / 0 / 1). A loop a `break` can leave stays silent; a break in a nested loop, switch or match, a closure or a nested fn does not count. The condition must be the literal `1`: `while (true)` is filed (issues/archived/2026-10-13-while-true-ending-fn-not-provably-single-return.md). The user's decision D18 (2026-10-13): refuse. Rows: `destructure_one_value_refused.sh` axis 3 (six refused, four run, seven mutations), `tuple_checked.sh` R16x. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`: `var a, b = one(1);` is
refused for `fn one(x) { return x + 1; }` but builds silently (b = stale rdx) when `one`'s body is
`loop { return x + 1; }`, a final `do { … } while (1);`, or `while (1) { return x + 1; }`.
**Placement:** 6.7.11 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 decisions pass (roadmap commit 68de8001); filed 2026-10-08 from roadmap.md.
**Severity:** Low
**Affects:** cycc 6.6.17 – 6.7.6 (the 6.6.17 (a5) single-return prescan)

## Summary

6.6.17 refuses `var a, b = f();` when pass 1 proves `f` returns ONE value (GFLG bit 1024): `b` would otherwise
take whatever rdx held. The proof requires the body's LAST statement to be a `return`. A body that ends in an
infinite loop exits only through its `return`s, but its last statement is the loop, so the bit stays clear and
the refusal is missed. Conservative — a missed refusal, never a false one.

## Reproduction

```cyrius
fn one(x) { loop { return x + 1; } }
fn main() {
    var a, b = one(1);
    return b;
}
var r = main();
syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected: `multi-value destructure binds 2 names, but 'one' returns 1 value - bind it to one name`, as for
`fn one(x) { return x + 1; }` (control, refused on the same compiler). Actual: builds, exits 0 (`b` = stale rdx).
Same for `fn one(x) { var i = 0; do { i = i + 1; if (i > x) { return i; } } while (1); }` and
`fn one(x) { while (1) { return x + 1; } }`.

## Root cause

`_body_ends_in_return` (`src/frontend/parse_fn.cyr:10059`) records the first token of the body's last top-level
statement and answers 1 only for `return` (token 33). For `loop { … }` that token is `loop`; for
`do { … } while (c);` the `}` closing the `do` block resets the statement start, so the last statement is read as
`while`. `_prescan_ret_single` (`parse_fn.cyr:10029`) then leaves bit 1024 clear and `_dt_arity_check`
(`src/frontend/parse_decl.cyr:5080`) returns early.

## Proposed fix

In `_body_ends_in_return`, also accept a final `loop { … }`, `while (1) { … }` or `do { … } while (1);` (a
constant-true condition) whose block contains no `break` that leaves it (a `break` inside a nested loop or a
closure does not count). Every `return` inside is already checked single by `_prescan_ret_single`'s walk. It only
adds refusals of programs that bind a stale rdx today; a `tests/gates` row per shape (and a `break`-containing
negative row that stays silent) pins it.
