# A closure's captured vector passed to a VALUE-form vector parameter (`|k| lanes(b)`, `fn lanes(x: f64v2)`) is refused on every target — the local `lanes(b)` is passed; accept the capture as the local is? — OPEN

**Status:** 🟡 **OPEN** — a question for the user. Measured 2026-10-16 on the 6.7.13 vectors lane (unit V3): refused once
on x86_64, x86_64 `CYRIUS_IR=3`, aarch64, cx and PE (`a value-form vector argument to 'lanes' is a local of its type or
a call declared to return it (..) - got `b``). At the lane open (f59668ad) it was refused on the four SysV / AAPCS64 /
cx legs ("value-form SIMD arg: IDENT not found as a local") and RAN on PE (42: the capture's address is what Win64's
by-pointer parameter takes); the D30 bite (5a6bd79b, `_sarg_pe_vword`) made PE refuse it as the other four do.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane; filed from the 6.7.13 vectors lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — a refusal by name on every target, no wrong value; the workaround is to copy the capture into a
local inside the closure (`var c = |k| { var w: f64v2 = b; return lanes(w) + k; }`).
**Kind:** language (decision) — D32 A (the user, 2026-10-15) gave a captured vector the LOCAL's rules for pointer
parameters (`|k| ri(b)` refused as `ri(b)` is); whether a capture is "a local of its type" for a value-form parameter
(D30's accepted set) is not decided. The 6.7.13 V3 brief's D32 plan listed "a Win64 value-form parameter gets the
address" for the capture arm; V3 did not apply it (it would accept on PE alone, where the other four refuse).
**Discovered:** 2026-10-16, the 6.7.13 vectors lane (V3), probing D32's capture arm.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
include "lib/fnptr.cyr"
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(4, 2);
    var c = |k| lanes(b) + k;
    return fncall1(c, 0);
}
var rc = main();
syscall(60, rc);
```

```
6.7.13 V3, every target:
error:<source>:7:23: a value-form vector argument to 'lanes' is a local of its type or a call declared to return it
(by name, a method, or fncallN / callptr with the callee written `&f`) - got `b`
lane open f59668ad: x86_64 / IR=3 / aarch64 / cx refused ("value-form SIMD arg: IDENT not found as a local"), PE 42
the local (`return lanes(b);` in main): 42 on every target
```

## Root cause

SysV / AAPCS64 / cx: the value-form argument record (`_simd_arg_record` → `_sar_src`, src/frontend/parse_fn.cyr) takes
a FINDLOCAL local or a vector call; a capture lives in the closure's env, so it falls to `_sar_err`. PE: `_sarg_pe_vword`
refuses any non-local word the same way.

## The question

Accept a captured vector as a value-form argument (the env copy loaded into the vector registers on SysV / AAPCS64 /
cx — the capture's words are `&env[woff]`, `_CL_CAP_WORDS_RA` — and its address passed on Win64), or keep the refusal
(and name the capture in its words)?
