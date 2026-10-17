# An error inside a generic fn's body is printed once per instance — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 on the 6.7.8 C2 lane (`l678-c2` @ 4d9eda56, its stage-1 cycc), on the
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
