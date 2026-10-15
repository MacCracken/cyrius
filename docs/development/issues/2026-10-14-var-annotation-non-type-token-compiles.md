# A `var` annotation that is not a type at all (`var b: 1 = 0;`, `var c: + = 2;`, `var G: 7 = 4;`) compiles silently — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G4, the compiler built from
the unit's tree, 2,189,720 B) and on the lane's base build/cycc (0155abc7): the repro builds with no diagnostic and
exits 9.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x. The fix stops programs that compile
today, so it is the user's call; the precedent is 6.7.11's parameter rule (a parameter's `fn f(a: 5)` / `(a: +)` /
`(a: "s")` are refused by name since the user's decision (b), 2026-10-13).
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit G4 (comparing how each type position refuses a token that is
no type, for the `Vec<1 + 2>` message).
**Severity:** Low — the variable is declared as a plain i64 and the token is dropped; nothing else is miscompiled, but
a typo in an annotation (`var n: 8 = ..`, a stray operator) is never reported.
**Affects:** the lane base (0155abc7) and the unit G4 tree; older releases not bisected.

## Reproduction

```cyrius
fn f(): i64 {
    var b: 1 = 0;
    var c: + = 2;
    var d: "s" = 3;
    return b + c + d;
}
var G: 7 = 4;
syscall(60, f() + G);
```

```
actual:   builds ("note: 1 unreachable fns" only), exits 9 — every annotation token ignored
expected: each refused by name at its token, once, as a parameter's is:
          "expected a type for parameter 'a', got number 1" (6.7.11) — here "... for variable 'b' ..."
```

## Root cause

PARSE_VAR's annotation ladder (src/frontend/parse_decl.cyr, the `else` arm after `*`, `[`, `u128` and `slice`) only
resolves the type when `_tn_head(S)` is true (an identifier or a tuple's `(`); for any other token it steps one token
(`STI(S, GTI(S) + 1)`) and declares a plain i64. PARSE_GVAR_REG's `_gvar_ann_head` arm does the same for a
declaration-zone global.

## Proposed fix

In both ladders, when the annotation's first token is neither a type head nor one of the arms above, report "expected a
type for variable 'b', got <token>" (the parameter reader's `_pty_err` shape) once at the token and step the token, so
the declaration reads on as today. Rows: a local and both global zones × a number, an operator, a string; one error each.
