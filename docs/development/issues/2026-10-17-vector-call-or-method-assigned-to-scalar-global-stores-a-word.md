# A vector call assigned to a scalar GLOBAL (by name, a method, `fncallN(&f, ..)`), or `fncallN(&f, ..)` / `callptr(&f, ..)` into a scalar LOCAL, stores one word, silently, differently per target — where `x = mkv(41, 7);` into a local is refused — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (its review-fix tree), x86_64 / x86_64
`CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine). The by-name half is pre-existing (the lane base c3af6501 gives
the same, rows 1, 3 and 4 on x86_64 / cx / PE); the method half (row 2) is the global spelling of the local D38 now refuses.
**Placement:** 6.7.15 — repair 5 (vectors lane; filed from the 6.7.14 vectors review, placed at the 6.7.14 wave-3 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — compiles with no diagnostic; the global holds a word whose value differs per target.
**Discovered:** 2026-10-17, the review of the 6.7.14 vectors lane (probe m4), beyond D38's filed surface (`x = s.mv();`
into a LOCAL, `issues/archived/2026-10-16-vector-method-result-untyped-scalar-and-return-destinations.md`).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
var G = 0;
fn run(): i64 { G = mkv(41, 7); return G; }
syscall(60, run() % 256);
```

```
row 1 (above)                                                 x86_64 0   IR=3 0   aarch64 0   cx 41   PE 41
row 2 `fn run(): i64 { var s: S = S { 1 }; G = s.mv(); return G; }`
                                                              x86_64 0   IR=3 0   aarch64 0   cx 41   PE 41
row 3 `fn run(): i64 { G = fncall2(&mkv, 41, 7); return G; }` (with include "lib/fnptr.cyr")
                                                              x86_64 0   IR=3 0   aarch64 0   cx 41   PE 41
row 4 `fn run(): i64 { var x = 0; x = fncall2(&mkv, 41, 7); var y: i64 = callptr(&mkv, 41, 7); return x + y; }`
                                                              x86_64 0   IR=3 0   aarch64 0   cx 82   PE 82
(every row compiles with rc 0 and no diagnostic; rows 1, 3 and 4 the same on the lane base)
```

The same assignments into a LOCAL are refused on every target:

```
fn run(): i64 { var x = 0; x = mkv(41, 7); var s: S = S { 1 }; x = s.mv(); return x; }
error:<source>:5:32: vector return type does not match the assigned variable
error:<source>:5:68: vector return type does not match the assigned variable
```

## Root cause

`_try_vector_call_assign` (src/frontend/parse_decl.cyr) and its D38 method arm `_vasg_mscal` resolve the destination
with `FINDLOCAL(S, noff)` and return 0 when it is no local, so a global destination falls through to the scalar
assignment, which stores the call's result register (the first word on x86_64 / aarch64; cx and PE's conventions differ).
Row 4: the by-name check reads `_vcall_fi` (a by-name call or `g<T>(..)`) and D38's a whole method; a whole
`fncallN(&f, ..)` / `callptr(&f, ..)` is recognised only by the vector-local receives (`_vrcv_ity`, `_vrcv_ibad`, 6.7.14),
so into a scalar local or declaration it takes the scalar path.

## Fix direction

Refuse a vector call (by name, `g<T>(..)`, a method, `fncallN(&f, ..)` / `callptr(&f, ..)`) assigned to a global that
is not that vector, and the indirect spellings into a scalar local or declaration, with the local's words ("vector
return type does not match the assigned variable" / ".. the declared type"). (A vector global
of the call's type is a separate question: vector globals take no initializer but 0 and are set through `&g`.)
