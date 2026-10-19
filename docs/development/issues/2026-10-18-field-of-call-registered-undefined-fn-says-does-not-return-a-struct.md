# A `.field` of an undefined fn's result after an earlier plain call to it reads "it does not return a struct" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S6) beside
issues/2026-10-17-undefined-callee-field-assignment-names-no-undefined-fn.md, whose fix names an undefined callee
("undefined function 'undefd'") when the `.field` call is the fn's FIRST use. Pre-existing; x86_64 measured, the
frontend's (every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — refused code (nothing compiles), the end-of-compile refusal names the fn; the first error's reason
is misleading.
**Kind:** diagnostics.

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { undefd(); undefd().n += 1; return 0; }
syscall(60, go());
```

```
error:<source>:3:32: cannot take a field of the result of 'undefd': it does not return a struct
warning: undefined function 'undefd'
warning: undefined function 'undefd' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

Without the earlier `undefd();` the line is one error, "3:16: undefined function 'undefd'" (6.7.15, `_call_undef`).

## Root cause

The plain call `undefd();` registers the name (PARSE_FNCALL's REGFN, offset -1, no owner), so `_call_field`
(src/frontend/parse_expr.cyr) resolves the later `undefd()` to that entry (fi >= 0) and, its return struct being 0,
takes `_call_fld_err`'s "does not return a struct". `_call_undef` is asked only for an unregistered callee (fi < 0).

## Proposed fix

Route a callee with no definition (`_fn_nodef`: offset < 0 and no owner pass 1 recorded — `_warn_undefined_prepass`'s
test) to `_call_undef` in the full compile too, after checking no legitimately-defined fn (a generic instance minted
at the call, an `extern`, a derive- or trait-generated fn) can be in that state at a call — a false "undefined
function" there would refuse valid code.
