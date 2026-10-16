# A typed closure parameter `|m: i64|` is refused "expected unknown, got ':'" plus cascade errors, never naming the rule — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane tree (`l6713-receives` @ `360a6d05`), x86_64.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16 by unit R4, writing the "typed parameter" control row the triage of
`issues/2026-10-14-nested-closure-parameter-taken-as-outer-capture.md` proposed (the triage assumed `|m: i64|` builds).
**Severity:** Low — diagnostics only, on source that is refused either way.
**Affects:** every target (the shared frontend's closure parameter loop, src/frontend/parse_expr.cyr).

## Reproduction

```cyrius
include "lib/fnptr.cyr"
fn f(): i64 { var g = |m: i64| m + 1; return fncall1(g, 4); }
syscall(60, f());
```

```
error:<source>:2:25: expected unknown, got ':'
    fn f(): i64 { var g = |m: i64| m + 1; return fncall1(g, 4); }
                            ^
error:<source>:2:30: undefined variable 'i64' (missing include or enum?)
    fn f(): i64 { var g = |m: i64| m + 1; return fncall1(g, 4); }
                                 ^
```

Nested in a closure beside an enclosing `m` it gets a third report (`|n| { var g = |m: i64| m + 1; .. }`):

```
error:<source>:2:88: a capturing closure needs include "lib/alloc.cyr" for its heap env
```

Expected: one error at the `:` naming the rule — a closure's parameters are untyped (the closure literal's parameter
loop and `_arg_next`'s comment say so) — and nothing after it for the same literal.

## Root cause

The parameter loop (`PARSE_FACTOR`'s closure arm, `if (PEEKT(S) == 31) .. else { cpgo = 0; }` then
`if (PEEKT(S) != 35) { ERR_EXPECT(S, 35); }`) reports the generic expectation; TOKNAME has no name for `|` (35), which
`issues/2026-10-08-tokname-operator-tokens-unnamed.md` already covers (the "unknown"). The loop does not step to the
closing `|`, so `i64` is parsed as the body ("undefined variable 'i64'"), and the outer pre-scan, which accepts only the
parser's `| IDENT, .. |` list as a literal (6.7.13), reads `m` as a capture. A refusal naming the rule (as `_pd_cl_refuse`
names "a closure's parameters take no defaults") that skips to the closing `|` would end the cascade.
