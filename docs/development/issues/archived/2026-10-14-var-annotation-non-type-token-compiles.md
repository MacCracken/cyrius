# A `var` annotation that is not a type at all (`var b: 1 = 0;`, `var c: + = 2;`, `var G: 7 = 4;`) compiles silently — RESOLVED

> ✅ **RESOLVED in v6.7.14** (FE-20, `f793b013`: the user's decision D15 (a), 2026-10-16, "refused by name" — PARSE_VAR's and PARSE_GVAR_REG's annotation head is `_tn_head_var`, which reports "expected a type for variable 'b', got <token>" once at the token (`_tn_once`) and lets the declaration read on. The filed repro is refused with its four errors — `7:8 ... 'G', got number 7`, `2:12 ... 'b', got number 1`, `3:12 ... 'c', got '+'`, `4:12 ... 'd', got string` — and no binary (it built and exited 9); after the first statement and in a for-init likewise; `--syntax-only` and `cyrius lint` report it; a generic or `#inline` body reports it once. Rows: `diagnostics/type_name_refused.sh` va_ rows (va_repro the repro verbatim; local / zone / after a statement × number / operator / string; va_comma, va_for, va_gen, va_missing, va_ok), floor 107; mutations RED. Filed beside (6.7.15): a missing annotation `var b: = 0;` is one error but "expected '=', got number 0" (`2026-10-16-var-missing-annotation-reported-as-expected-equals.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G4, the compiler built from
the unit's tree, 2,189,720 B) and on the lane's base build/cycc (0155abc7): the repro builds with no diagnostic and
exits 9.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D15 — (a) Refused by name.
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
