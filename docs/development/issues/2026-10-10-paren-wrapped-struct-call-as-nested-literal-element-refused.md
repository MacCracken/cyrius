# A parenthesised struct-returning call as a nested-struct literal element is refused ("unexpected '}'") — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: `H { 7, (mkq(4, 9)), 8 }` is refused "unexpected '}'", where the same element without the parentheses
builds and exits 64. The same refusal with the installed 6.6.10, 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7
compilers. A 24-byte struct element (`(mkr(4, 9))`) is refused the same way; an 8-byte one is right.
**Placement:** 6.7.10 — repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never 7.x (the fix
is the user's call, asked at that release's open: refused source starts compiling).
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D4 (a dyn literal element; D4 refuses that form for
a dyn with its own two reports).
**Severity:** Low — valid source is refused loudly; no wrong value.
**Affects:** cycc 6.6.10 – 6.7.8 (every target: the literal is parsed in the shared frontend)

## Summary

A positional struct literal whose element is a NESTED struct field takes that element from a struct source when it
is one (a struct name, a call returning the struct, a method or operator result) and otherwise reads it leaf by
leaf. A free call returning a struct over 8 bytes is recognised only when the element STARTS with the call's name.
Wrapped in parentheses, the call is parsed as an ordinary scalar expression: its rax is carried into the nested
struct's first leaf, and the literal's next element is read for the second leaf — so the literal runs out of
elements one early and the closing `}` is "unexpected". A method or operator result in parentheses
(`H { 7, (a.dup()), 8 }`) has been taken since 6.7.6 (`_sc_pwrap`); the free call has no such arm.

Related, the same "a parenthesised free call is no struct source" class at another destination:
[`var x = (mk());` infers no struct](2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md) (shape
(a)) — one shared "peel the wrapping parentheses, then test for a whole struct call" helper serves both.

## Reproduction

`docs/development/issues/repros/2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
struct H { x; q: Q; z; }
fn mkq(a, b): Q { var q = Q { a, b }; return q; }
fn main(): i64 {
    var h = H { 7, (mkq(4, 9)), 8 };     # refused: "unexpected '}'"; without the parentheses: 64
    return h.x + h.q.a * 10 + h.q.b + h.z;
}
var rc = main();
syscall(60, rc);
```

```
actual:   error:<source>:6:35: unexpected '}'
expected: builds; exit 64 (7 + 40 + 9 + 8), as `H { 7, mkq(4, 9), 8 }` does today
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`_spi_src` (`src/frontend/parse_decl.cyr:2315`) tries `_spi_call` (`:2341`, the free-call arm: `f(..)` /
`f<..>(..)` followed by `,` or `}`) only when the element's first token is an IDENT. A `(`-headed element goes
straight to `_spi_expr` (`:2373`), whose struct-source arms are the method / operator record `_sc_whole`
(`src/frontend/parse_fn.cyr:4714`, with 6.7.6's `_sc_pwrap` peeling wrapping parentheses) and the field-load hit.
A free call inside the parentheses sets neither, so `_spi_expr` returns kind 2 — "a scalar left in rax for the
first leaf" — and the second leaf consumes the next element (`8`), leaving none for `z`.

## Proposed fix

In `_spi_src`, peel balanced wrapping parentheses before the free-call test (the same shape `_sc_pwrap` accepts for
a method record), or have `_spi_expr` recognise a whole free struct call inside them; the element is then a struct
source exactly as the unwrapped call is (a > 8 B result into a temp in a fn, refused by name at top level). Rows:
the repro; 16-byte and 24-byte elements; a generic call `(mk<Pt>(..))`; double parentheses; the same at top level
(the refusal by name the unwrapped call gets); an 8-byte element unchanged.

## Consumer-side workaround

Drop the parentheses (`H { 7, mkq(4, 9), 8 }`) or bind the call first (`var q = mkq(4, 9); var h = H { 7, q, 8 };`).
