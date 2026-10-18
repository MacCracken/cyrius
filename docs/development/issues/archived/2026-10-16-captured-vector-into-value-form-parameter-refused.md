# A closure's captured vector passed to a VALUE-form vector parameter (`|k| lanes(b)`, `fn lanes(x: f64v2)`) is refused on every target — the local `lanes(b)` is passed; accept the capture as the local is? — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-4, `87d93b03e`, and the review fix VC-4r, `986123203` (the user's decision D31, 2026-10-16: A — the capture is accepted as the local is). `_sar_one` takes a closure's captured vector (`_sar_cap`), checked by `_simd_arg_typecheck` in the local's words. x86_64, aarch64 and cx copy its env words where the argument stands. Windows pushes their address, copied first when a later argument may write the capture. The filed repro (`|k| lanes(b)`) was refused on every target (`7:23: .. - got `b``); it now exits 42 on x86_64, IR=3, aarch64, cx and PE. An f64v2 capture into `v: f32v4` and an f64v4 one into `x: f64v2` are refused with the local's words. An f32v4 capture into `x: f64v2` passes, as the f32v4 local does (the 16-byte class) — wider than D31's option text, and listed for confirmation. VC-4r: the review found the capture, as an argument of an `#inline` fn inside a closure (`|k| li(lanes(b), k)`), read a clobbered copy (40 / 139). A closure's frame is now sized from max(GFLC, `_flc_hwm`) and reads 42. Rows: `simd_pointer_param.sh` VCc1 (the filed repro verbatim), VCc2 (seven shapes), VCcY1 / VCcY2 and VCi1 – VCi5, on five legs; `crossos/simd_pointer_param.tcyr` `sp_crows` and `sp_irows` (FLOOR 95). Mutations M-VCc1 – M-VCc3 and M-VCi1 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — a question for the user. Measured 2026-10-16 on the 6.7.13 vectors lane (unit V3): refused once
on x86_64, x86_64 `CYRIUS_IR=3`, aarch64, cx and PE (`a value-form vector argument to 'lanes' is a local of its type or
a call declared to return it (..) - got `b``). At the lane open (f59668ad) it was refused on the four SysV / AAPCS64 /
cx legs ("value-form SIMD arg: IDENT not found as a local") and RAN on PE (42: the capture's address is what Win64's
by-pointer parameter takes); the D30 bite (5a6bd79b, `_sarg_pe_vword`) made PE refuse it as the other four do.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D31 — A.
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
