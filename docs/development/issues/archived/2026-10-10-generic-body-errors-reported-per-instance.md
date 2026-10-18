# An error inside a generic fn's body is printed once per instance — RESOLVED

> ✅ **RESOLVED in v6.7.14** (GN-18 (`3bf60734`) and GN-18r (`fff3b8bb`): the error emitters (ERR, ERR_EXPECT, ERR_IDENT, ERR_MSG, ERRDUPVAR) record each report by its token and message (`_err_once`, `_edup`) and print a repeat as nothing; the five "undefined variable" writers share ERR_UNDEF (`_err_dup`; one path with the frontend lane's `_undef_var_report` since the merge `a273b27e`); a note after a repeated error stays quiet with it (`_err_quiet`). The filed repro prints one `3:40: expected ';', got number 2` (it printed three), and every row of the filed table one error line; two different errors in one body print once each; a generic struct's field-type refusal and a bound refusal met again in another instance print one error and one note. Error output only: the corpus compiles with identical binaries and stderr. Rows: `frontend/generic_body_error_once.sh` R (the repro verbatim), T1 – T9 (the table), D, E1 – E6 (E5 one line since `25987863`), N, V, C, S1 – S4, B; ledger ME1 – ME6 RED. Not closed here: the 61 direct error writers outside util.cyr still print once per instance (an arity error, a second subscript — filed, 6.7.15), and a warning in a generic body still prints once per instance (not filed). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-10 on the 6.7.8 C2 lane (`l678-c2` @ 4d9eda56, its stage-1 cycc), on the
lane's previous bite (bad7b32e) and on the installed 6.7.7 `cycc`: the same counts (the for-step rows below are
errors only from 4d9eda56 on). A generic fn with a syntax error in its body, called at three distinct type arguments,
prints the error three times, at the same file:line:col.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-2b (the for-step `)` check), outside its scope: a junk
for-step inside a generic body instantiated twice printed its new "expected ')'" twice — as the existing statement
`;` check and the 6.7.5 field-step check already did.
**Severity:** Low — every input is invalid and refused (rc 1, no binary). The cost is repeated lines; a gate that
counts error lines in a generic body sees one per instance.
**Affects:** cycc 6.7.7 and the 6.7.8 C2 lane (older releases not bisected).

## Summary

A generic fn's body is parsed for its base and again for every distinct instance. The refusals routed through
`_err_in_sync` (parse_expr.cyr) print once, because 6.7.5's review gave them a per-token latch (`_tn_once`,
parse_types.cyr: "a generic base and its instances parse the same tokens: report once"). The plain error emitters
have no such latch — `ERR_EXPECT`, `ERR_IDENT`, `ERR_MSG` (util.cyr) and the statement's own "undefined variable"
print — so their message is printed by every parse of the body that reaches it. The cascade latch `_panic` does not
suppress the repeats (each instance's parse prints again).

| Shape (body of `fn g<T>(v: T): i64`) | Calls | Error lines |
|---|---|---|
| `var i = 0; i += 1 2; return i;` | none (only the base parse) | 1 |
| same | `g(1)` | 1 |
| same | `g(1) + g(x)` (`x: I`) | 2 |
| same | `g(1) + g(x) + g(y)` (`x: I`, `y: J`) | 3 |
| same | `g(1) + g(x) + g(2) + g(x)` (two distinct instances) | 2 |
| `return zz;` (`zz` undeclared) | `g(1) + g(x)` | 3 |
| `for (i = 0; i < 3; i += 1 2) { }` | `g(1) + g(x)` | 2 |
| a field step `c.n += 1 2` (6.7.5) | `g(1) + g(x)` | 2 |
| `#inline fn h(n)` with the junk step | `h(1) + h(2)` | 1 |

## Reproduction

```cyrius
struct I { a; b; }
struct J { c; }
fn g<T>(v: T): i64 { var i = 0; i += 1 2; return i; }
fn main(): i64 { var x = I { 1, 2 }; var y = J { 3 }; return g(1) + g(x) + g(y); }
syscall(60, main());
```

```sh
build/cycc < repro.cyr > /dev/null; echo $?
```

Expected: one `error:<source>:3:40: expected ';', got number 2`, rc 1. Actual: that line three times, rc 1.

## Proposed fix

Give the plain emitters the latch the refusals already have: an error at a token that was already reported is not
printed again (`_had_error` and `_panic` still set). One place for it is `_err_head`'s callers in util.cyr, keyed on
the token index as `_tn_once` is — but `_tn_once`'s byte map is shared with the type-name and `_err_in_sync`
refusals, so a separate map (or a second bit) keeps a refusal and a later, different error at the same token apart.
Check every gate that counts `^error` lines in a generic body (`field_compound_checked.sh` R17 / R18 already expect
1). Rows: the table above, each exactly one error line, plus a generic with two DIFFERENT errors in its body (both
printed once).
