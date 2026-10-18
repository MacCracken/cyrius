# A top-level untyped `var w = mkv(..);` / `var v = s.mv();` (and `var x: i64 = mkv(..);`) binds one word of a vector result, silently, differently per target — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (its review-fix tree; the lane base c3af6501
behaves the same on every row), x86_64 / x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine).
**Placement:** 6.7.15 — repair 5 (vectors lane; filed from the 6.7.14 vectors review, placed at the 6.7.14 wave-3 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — compiles with no diagnostic and reads garbage lanes: an untyped top-level global initialised from
a whole vector call (by name or a method) holds one word, and its value differs per target.
**Discovered:** 2026-10-17, the review of the 6.7.14 vectors lane (probes m1 / m2), beyond D37's in-fn surface (an
untyped `var v = s.mv();` inside a fn is the f64v2 local since D37; `var v = mkv(..);` inside a fn since 6.7.11).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
var s: S = S { 1 };
var w = mkv(41, 7);
syscall(60, (load64(&w) * 10 + load64(&w + 8)) % 256);
```

```
row 1 (above, by name)                         x86_64 0   IR=3 0   aarch64 0   cx 154   PE 195
row 2 `var v = s.mv();` read the same way      x86_64 0   IR=3 0   aarch64 0   cx 195   PE 195
row 3 `var x: i64 = mkv(41, 7); syscall(60, x % 256);`
                                               x86_64 0             aarch64 0   cx 41    PE 41
(every row compiles with rc 0 and no diagnostic; 161 is the vector, (41 * 10 + 7) % 256, in rows 1 and 2)
```

Compare, in a fn: `var w = mkv(41, 7);` and (D37) `var v = s.mv();` are the f64v2 local (161 on every target), and
`var x: i64 = mkv(41, 7);` is refused "vector return type does not match the declared type". At top level the
annotated `var w: f64v2 = mkv(41, 7);` is refused "vector global 'w' takes no initializer but 0; set it through its
address", and a top-level vector call result into a `*V` parameter is refused "'mkv' returns a vector by value, and a
vector result needs storage in a fn's frame - call it inside a fn" (6.7.13's D40). The untyped and the scalar
declarations are the only top-level vector destinations that take the call.

## Root cause

PARSE_VAR's vector-call block (src/frontend/parse_decl.cyr: `_vin_fi = _vcall_fi(S, GTI(S) + 1)`, which takes the
callee's vector type for an untyped declaration and refuses another declared type) sits under `if (GINFN(S) == 1)`, and
the untyped receive's inference (`_vrcv_decl` → `_vrcv_ity` / `_vmc_whole`) serves a fn's locals. A top-level
declaration takes the global path, which has no vector arm, so the call's result (the first word on x86_64 / aarch64;
cx and PE's own conventions differ) is stored as the global's one word.

## The question

Is a top-level untyped `var w = mkv(..);` / `var v = s.mv();` refused as the annotated vector global and the `*V`
argument are (a vector result needs a fn's frame), or a vector global initialised from the call? And is the top-level
`var x: i64 = mkv(..);` refused as it is in a fn?
