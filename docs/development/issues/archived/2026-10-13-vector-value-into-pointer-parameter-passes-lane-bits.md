# A vector VALUE that is not a named local, passed to a `*V` parameter (`rd(mkv(..))`, `rd(*pv)`), and a vector local passed to a non-vector pointer (`*Pt`, `*i64`) or to a `*f32v8`, pass lane 0's bits as the address — RESOLVED

> ✅ **RESOLVED in v6.7.12** (FX-1 and its review fix FX-1r, the user's decision D27, 2026-10-15: B — "pass the address for the *V shapes; another pointer kind refused by name". A vector value that is not a named local, passed to a `*V` parameter, passes an address: `rd(mkv(42, 7))` — by name, wrapped, through `fncall2(&mkv, ..)` / `callptr(&mkv, ..)`, an inferred generic, a method's argument, a tail position — is received into a frame temporary whose address is passed (on Win64 the temporary is the hidden result pointer), and `rd(*pb)` with `pb` a `*V` (a local, a parameter, a capture, a field, a global, a `: *V` call, `pb + n`) passes `pb`; a call result or a `*` of another vector type is refused with 6.7.11's words. Repro 1 exits 42 on x86_64, IR=3, aarch64 (qemu), cx and PE (wine) — it was 139 / 139 / 139 / 208 / 5, and x86_64's 6.7.11 regression (refused through 6.7.10) is closed. Repro 2: `rp(b)` (`*Pt`) and `ri(b)` (`*i64`) are refused by name, one line each ("cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'rp' - pass &b for its address"; `*u8` / `**T` too) — including Win64's `rp(b)`, which passed `&b` by accident and ran — and `*f32v8` is a `*V`: `r8(e) + r8(&e) - 42` is 42 on all five legs. A top-level `rd(mkv(..))` is refused by name (no frame). Rows: `codegen/simd_pointer_param.sh` R4 R5 R5e Y10-Y13 Yw2a-c (mutations M4-M7 each RED), `crossos/simd_pointer_param.tcyr` 29 → 51 rows on x86_64 / IR=1 / IR=3 / DCE=1 / aarch64 / cx / PE, and 292 / 292 crossos files on ecb, ach, cass and pi. Filed beside it (6.7.13, questions and neighbours): the value-form `v: f32v8` parameter, a vector call result or `*pv` into another pointer kind / a by-value struct, a struct into `*V`, a struct local into a word pointer, `rd(*&b)` / `rd(**ppb)`, a captured vector into another pointer kind. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — ⚠ **a 6.7.11 regression on x86_64** (the release-docs pass, 2026-10-14): the `*V` shapes were refused there through 6.7.10 and 6.7.11 ships them compiling to a fault (ARG-4, 528555c4) — fix first in 6.7.12 (the user, 2026-10-14). A decision for the user (refuse by name, or pass an address). Measured 2026-10-13 on the
6.7.11 callargs lane after unit A2 (`2026-10-10-pointer-to-vector-parameter-is-value-form.md`, the user's decision
(a): `p: *f64v2` is a pointer and a vector LOCAL passed to it passes its address): each shape below compiles with no
diagnostic and the callee dereferences lane 0's bits — x86_64 139, aarch64 139, cx 208 / 253 / 1 (a guest fault),
PE 5 (an access violation). Before A2 (A1's compiler) the `*V` shapes were the same on aarch64 / cx / PE and
were refused on x86_64 only, by the value-form path's text (`value-form SIMD arg: IDENT not found as a local`,
`value-form SIMD arg must be a local IDENT (inline-replay path)`); the non-vector-pointer and `*f32v8` shapes were the
same on all four before and after.
**Placement:** 6.7.12 — repair 2: the platform release (fixfirst lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D27 (fork) — B: pass the address for the *V shapes; another pointer kind refused by name.
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A2), probing beyond the filed surface (a named local).
**Severity:** High (6.7.11 regression on x86_64; Medium on the other targets, where it was never refused). Compiles clean and faults at run time; a type error the compiler does not name. Workaround: bind
the vector to a local first (`var t: f64v2 = mkv(..); rd(t);`), or pass `pv` itself (it is the pointer).
**Affects:** every target; every vector type.

## Reproduction

`*V` parameter, a vector value that is not a named local:

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn mkv(a, b): f64v2 { return f64v2_make(a, b); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var pb: *f64v2 = &b;
    var r1 = rd(mkv(42, 7));   # a vector call result: want 42 (or a refusal)
    var r2 = rd(*pb);          # a vector dereference: want 42 (or a refusal)
    return r1 + r2 - 42;
}
var rc = main();
syscall(60, rc);
```

```
A2 tree:  x86_64 139, aarch64 139, cx 208, PE 5     (want 42, or a refusal); each half alone: 139 / 139 / 253 / 5
A1 tree:  x86_64 refused "value-form SIMD arg: IDENT not found as a local" (the `*pb` half alone: "value-form SIMD
          arg must be a local IDENT (inline-replay path)"); aarch64 139, cx 208, PE 5
```

A vector local into a pointer parameter of another kind, and into a `*f32v8`:

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
fn rp(p: *Pt): i64 { return p.x; }
fn ri(p: *i64): i64 { return *p; }
fn r8(p: *f32v8): i64 { return load32(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var e: f32v8 = f32v8_make(42, 2, 3, 4, 5, 6, 7, 8);
    return rp(b) + ri(b) + r8(e) - 84;   # want 42, or refusals
}
var rc = main();
syscall(60, rc);
```

```
A1 and A2 trees alike: x86_64 139, aarch64 139, cx 1, PE 5
```

## Root cause

`src/frontend/parse_fn.cyr`, `_try_push_struct_addr_arg` (the address-passed argument arms):

- **A vector call result** into a `*V` parameter reaches the free-call arm (`_gcall_open` >= 0), where
  `_arg_call_class(S) == 0` (a vector result is no struct class) returns 0: the caller pushes the call's VALUE, lane 0.
- **`*pv`** reaches `_sarg_deref` -> `_push_struct_expr_arg`; `_dlo_park` parks only a STRUCT dereference, so
  `_dro_take` fails and the loaded lane 0 is pushed.
- **A vector local into `*Pt`** reaches the vector arm, where `_sarg_vec_ptr` finds no `*V` parameter (`_pvec_param`
  is 0) and returns `_TARGET_PE` — 0 off Win64, the value push. **Into `*i64`** the parameter has no address bit, so
  `_sarg_byval_small` declines and the value is pushed.
- **`*f32v8`**: `_classify_param_type` has no class for `f32v8` (nor for the value-form `v: f32v8`), so the `*V` rules
  (`_param_class` class 9, `_param_wants_struct_ptr`, `_pvec_param`) never see it.

## The question

6.6.20 passes a struct VALUE's address to a `*T` parameter — a call result through a frame temp
(`_struct_call_into_temp`), and 6.7.10's decision 6 passes `take(*p)`'s pointer. A2 applied the named-local half of
that to vectors (the user's decision (a), 2026-10-13). For the rest: should a vector call result / `*pv` into a `*V`
parameter pass a temp's address / the pointer (they would start working), or be refused by name ("a vector value is
not a pointer — bind it to a local")? And a vector local into a pointer of another kind (`*Pt`, `*i64`) — refused by
name, as a vector of another vector type is (A2's "cannot pass 'f' to a parameter of a different vector type")?
