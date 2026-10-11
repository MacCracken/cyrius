# A pointer-to-vector PARAMETER (`p: *f64v2`) is taken as a by-value vector: `rd(&b)` is refused, `rd(b)` builds and SIGSEGVs — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: with `fn rd(p: *f64v2)`, `rd(&b)` is refused "value-form SIMD arg must be a local IDENT (inline-replay
path)" (plus a cascade "expected ')', got identifier 'b'"); `rd(a)` with an untyped `a = &b` is refused "value-form
SIMD arg must be a 16-byte vector"; and `rd(b)` — a vector VALUE into the pointer parameter — compiles clean and dies
of SIGSEGV (rc 139). A `var pl: *f64v2 = &b;` LOCAL reads the vector correctly. Both repros behave the same with the
installed 6.6.10, 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers.
**Placement:** 6.7.11 — repair 1, the call-arguments lane (roadmap.md § *The releases after 6.7.7*) — placed
2026-10-10 — never 7.x (the fix is the user's call, asked at that release's open: refused calls start compiling, and
`rd(b)`, which compiles today, is refused).
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-4a (`p[i]` on a `*T` parameter; the repros are in its
handoff).
**Severity:** Medium — valid source is refused loudly; the shape that does compile is a type error that crashes at
run time with no diagnostic.
**Affects:** cycc 6.6.10 – 6.7.8, x86_64 measured (the parameter classification is shared; the SysV / Win64 halves
differ only in how a value-form vector arrives)

## Summary

A parameter annotated `*V` for a vector type V (`f64v2`, `f64v4`, `f32v4`, the integer 128-bit vectors) should be a
pointer: one integer word, like `*Pt` or `*i64`. Both parameter scans consume the `*`, but then classify the bare
type NAME and, finding a vector, make the parameter a VALUE-form vector — two or four frame slots filled from XMM
registers on SysV / aarch64, a by-pointer copy-in on Win64 — and mark the fn's SIMD mask so every caller routes that
argument as a vector. A caller's `&b` is then refused (a value-form vector argument must be a named local), and a
vector value is accepted and arrives in the callee as a vector the body then dereferences as an address.

## Reproduction

`docs/development/issues/repros/2026-10-10-pointer-to-vector-parameter-is-value-form.cyr` (the valid call, refused):

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(f64_from(5), f64_from(6));
    var w0 = load64(&b);                 # lane 0's bits
    var pl: *f64v2 = &b;
    if (load64(pl) != w0) { return 3; }  # a `*f64v2` LOCAL is right
    if (rd(&b) == w0) { return 1; }      # refused: "value-form SIMD arg must be a local IDENT (inline-replay path)"
    return 2;                            # want exit 1
}
var rc = main();
syscall(60, rc);
```

`docs/development/issues/repros/2026-10-10-pointer-to-vector-parameter-is-value-form-value.cyr` (the type error that
compiles):

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(f64_from(5), f64_from(6));
    var r = rd(b);                       # compiles clean; SIGSEGV (rc 139) — want a type error
    return 0;
}
var rc = main();
syscall(60, rc);
```

## Root cause

Both scans drop the pointer before classifying:

- pass 2, `_PARSE_FN_DEF_IMPL`'s parameter loop (`src/frontend/parse_fn.cyr:14653`: `if (PEEKT(S) == 8) { STI(..);
  _mark_ptr_param(S); }`), then `_classify_param_type(S, tnoff)` (`:14668`) → `pt_simd_class` / `pt_simd_sid` for
  classes 6 / 7 / 8 / ≤ -2048, which allocate the multi-slot value-form parameter regardless of `_ptrp_now(S)`;
- pass 1, `_prescan_params_scan` (`:12235`, run from `_prescan_fn_sig`; its parameter arm sets `_pptr = 1` for the
  `*`, then the same classes set `simd_mask` / Win64's `struct_mask` without reading `_pptr`), which is what the call
  site routes by.

`_mark_ptr_param` itself records the step of `*T` correctly, and a `*f64v2` LOCAL is right — only the parameter
classification ignores the `*`.

Related, the same parameter branch: [a parameter's type annotation is read as one token](2026-10-10-param-type-annotation-reads-one-token.md)
(`fn f(p: **i64)` refused, `fn f(a: 5)` accepted) — fix the two together.

## Proposed fix

In both scans, skip the vector classes when the parameter is behind a `*` (`_ptrp_now(S) == 1` / `_pptr == 1`): it is
an ordinary pointer parameter (one int slot, its step = the vector's size, as `_mark_ptr_param` already computes).
Then a vector value passed to it is the type error it is (refused by name, as a struct value into a `*T` of another
type is), and `&b` / a `*f64v2` name are accepted. Rows: the two repros; `*f64v4`, `*f32v4`, `*i32v4`; `p[1]` and
`p + 1` stepping 16 / 32 bytes; a mixed signature `(v: f64v2, p: *f64v2)` (the XMM ordinals must count only the
value-form one); PE under wine and on cass (the Win64 by-pointer path); aarch64.

## Consumer-side workaround

Declare the parameter untyped (`fn rd(p)`) or as a byte pointer, and pass `&b`.
