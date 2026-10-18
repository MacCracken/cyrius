# A wrapped by-name call or method call of ANOTHER vector into a vector local — `var v: f64v2 = (mk4(41));`, `(s.mv())` — is refused in the receive's generic words ("got `(...)`"), not as the type mismatch the unwrapped call gets — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V3, after the indirect-call bite that
gives `(callptr(&mk4, 41))` the mismatch words) on x86_64, aarch64 (cross), cx and PE (cross); the lane base
(c3af65019) prints the same four lines.
**Placement:** 6.7.15 — repair 5 (vectors lane; filed from the 6.7.14 vectors lane, placed at the 6.7.14 wave-3 integration, 2026-10-17) — never 7.x.
**Severity:** Low — message text only: each shape is refused once, on the right line, and no binary is written.
**Kind:** bug (diagnostic).
**Discovered:** 2026-10-17, implementing issues/archived/2026-10-16-indirect-call-of-another-vector-into-vector-local-generic-words.md
(its filed surface is `callptr(&f, ..)` / `fncallN(&f, ..)`, wrapped or not; the by-name call and the method, wrapped, are
the same mismatch one shape over).

## Reproduction

```cyrius
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }
struct S { k; }
impl S { fn mv(self): f64v4 { var v: f64v4; return v; } }
fn run(): i64 { var s: S = S { 1 }; var v: f64v2 = (mk4(41)); var w: f64v2 = (s.mv()); return 1; }
fn run2(): i64 { var s: S = S { 1 }; var v: f64v2; v = (mk4(41)); var w: f64v2; w = (s.mv()); return 1; }
syscall(60, run() + run2());
```

```
x86_64 / aarch64 / cx / PE, identical (lane base c3af65019 and the V3 tree):
error:<source>:4:52: a value-form vector local is initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) or a dereference of a pointer to its type (`*p`) - got `(...)`
error:<source>:4:78: a value-form vector local is initialised only from .. - got `(...)`
error:<source>:5:56: a value-form vector local is assigned only from .. - got `(...)`
error:<source>:5:85: a value-form vector local is assigned only from .. - got `(...)`
```

Unwrapped, the same four sources are refused "vector return type does not match the declared type" / ".. the
assigned variable" (PARSE_VAR's by-name check, `_try_vector_call_assign`, `_vrcv_mbad`); since V3 so are
`callptr(&mk4, 41)` / `fncall1(&mk4, 41)` wrapped or not (`_vrcv_ibad`).

## Root cause

`_vrcv_src` (src/frontend/parse_decl.cyr) takes a wrapped by-name call (kind 1) or method (kind 3) only when its declared
vector EQUALS the local's type; another vector falls to kind 0, and the mismatch refusals look at the unwrapped token
only — PARSE_VAR's `_vcall_fi(S, GTI(S) + 1)` check and `_try_vector_call_assign`'s at `IDENT (`, `_vrcv_mbad` at the
method's first token (no `_ie_unparen`). The generic `_vrcv_err` then names `(...)`.

## What a fix needs

The wrapped twins of the two mismatch checks — peel whole-source parentheses (`_hl_dx_end` + `_ie_unparen`, as
`_vrcv_ibad` does) and ask `_vcall_fi` / `_vrcv_mty` there — so the four lines above read "vector return type does not
match the declared type" / ".. the assigned variable", once each, on x86_64 / aarch64 / cx / PE; rows beside
simd_return_shapes.sh's Q1-Q12.
