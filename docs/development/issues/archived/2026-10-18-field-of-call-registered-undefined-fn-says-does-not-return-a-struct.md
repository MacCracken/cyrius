# A `.field` of an undefined fn's result after an earlier plain call to it reads "it does not return a struct" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-8, `5a4d011a1` — no decision needed: diagnostics only. `_call_field` sends a callee with no definition (`_fn_nodef`: no code and no owner) to `_call_undef`, not only an unregistered one. The audit this filing asked for found one definition pass 1 registers with no owner — an enum variant's payload constructor, whose code is emitted at its enum — and excludes it by name (`_fn_enum_var`). A generic instance is owned before its call returns, `#derive`'s fns are prescanned, and cyrius has no `extern`. The filed repro's first error is now "3:26: undefined function 'undefd'" at the field call (was "3:32: cannot take a field of the result of 'undefd': it does not return a struct"); the plain call keeps its own warning and end-of-compile refusal. The same holds for the for step, `var x = undefd().n;` and a method on the result, on the x86_64, aarch64, cx and PE compilers; a fn defined below, a generic's instance, a library fn and an enum constructor above its enum are unchanged. Rows: `tests/gates/frontend/call_ptr_field_store.sh` U16 (the filed repro verbatim) – U23; mutations RED 16 / RED 4. Still open, and not filed: a unit enum variant called as a fn, `Non(); var x = Non().n;`, still reads "does not return a struct" after the plain call; the constructor exclusion covers it. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S6) beside
issues/archived/2026-10-17-undefined-callee-field-assignment-names-no-undefined-fn.md, whose fix names an undefined callee
("undefined function 'undefd'") when the `.field` call is the fn's FIRST use. Pre-existing; x86_64 measured, the
frontend's (every target).
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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
