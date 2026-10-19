# An operator after a by-name vector call into a vector local (`var w = mk2(41, 7) + 1;`, `: f64v2`, `w = ..`) is dropped silently on x86_64 / aarch64, applied to a lane on cx, and a parse error on Windows — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (unit V3's final tree, 89fd5ad53), x86_64 /
x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine); the lane's tree before V3 (024a5e421) gives the same on
x86_64. Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 vectors lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Medium — x86_64 / aarch64 compile clean and drop `+ 1` (the local holds the call's vector), cx adds 1
to a lane, Windows refuses with a parse error naming the `+`: one source, three behaviours.
**Kind:** bug (the receive's acceptance test reads the call, not the source it starts).
**Discovered:** 2026-10-18, probing the neighbours of D28 / D29 (unit V3).

## Reproduction

```cyrius
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
fn r(): i64 { var w = mk2(41, 7) + 1; return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
```

The same header with `fn r()` replaced by each row:

```
row 1 (above)  var w = mk2(41, 7) + 1;              x86_64 / IR=3 / aarch64 161, cx 165, PE error "expected ';', got '+'"
row 2          var w: f64v2 = mk2(41, 7) + 1;       x86_64 / IR=3 / aarch64 161, cx 165, PE error "expected ';', got '+'"
row 3          var w: f64v2; w = mk2(41, 7) + 1;    x86_64 / IR=3 / aarch64 161, cx 165, PE error "expected ';', got '+'"
row 4          var s: Mv = Mv { 1 }; var w = s.m2() + 1;
                                                    x86_64 / IR=3 / aarch64 11, cx 165, PE 205 (one word)
row 5          var s: Mv = Mv { 1 }; var w: f64v2 = s.m2() + 1;
                                                    refused on all five: "a value-form vector local is initialised
                                                    only from .. - got `s`"
```

And at top level, where 6.7.15's D26 refuses the WHOLE call (`var w = mkv(41, 7);`: "'mkv' returns a vector by value,
and a vector result needs storage in a fn's frame"), a call that STARTS the untyped initialiser is taken as a word:

```
row 6  fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
       var w = mkv(41, 7) + 1;
       syscall(60, w % 256);                        x86_64 / IR=3 / aarch64 1, cx 42, PE 42 (the result's word + 1)
```

## Root cause (partial — suspected, not traced to the instruction)

PARSE_VAR's vin block infers / checks the callee's vector from a by-name call that STARTS the initialiser
(`_vcall_fi(S, GTI(S) + 1)`), and the inline 16 / 32-byte receives below it (`_is_simd128` / `_is_simd256`, the
`IDENT (` lookahead; `_try_vector_call_assign`'s by-name arm for the assignment) take that call as the source without
checking that it is the whole source (`_vrcv_src` checks it for every other spelling): the x86_64 / aarch64 receive
stores the vector registers and the `+ 1` changes no lane, cx's receive adds it to one, and the Win64 arm emits its own
call and then expects `;`. The method spelling is refused as a source (row 5) or binds a word (row 4: D37 infers only
from a whole call). At top level (row 6) D26 refuses only a whole call, so the starting one is scalar code.

## Fix direction

The by-name receives take the call only when it is the whole source (as `_vrcv_src` checks for every other spelling);
an operator on a vector call's result is then whatever the language says an operator on a vector value is — refused by
name ("a value-form vector local is initialised only from ..") as row 5 is, unless an operator fn applies.
