# A parenthesised argument to a value-form vector parameter — `lanes((v))`, `lanes((mkv(4, 2)))` — is refused on x86_64 / aarch64 / cx and passed on PE — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-3, `47da68923`: parentheses wrapping a whole value-form vector argument are transparent on every target. `_sar_src` and the inline replay `_inl_simd_arg` read the argument through `_sar_take` / `_sar_one`, which peel the wrap and then take the local or the call; Win64's gate peels likewise (`_spv_one`). The filed repro (`lanesn((v))`) and `lanesn((mkv(4, 2)))` were refused on x86_64, IR=3, aarch64 and cx (`4:65` / `5:32` .. "got `(...)`") and gave 42 on PE. They now exit 42 on all five, through an `#inline` fn too. A vector of another class inside the wrap is refused with the local's words. A wrap that is not the whole argument (`(v) + 1`) keeps the `(...)` refusal. No decision needed (whole-argument parentheses are transparent: 6.7.6, 6.7.11, 6.7.13's D17 / D19). Rows: `simd_pointer_param.sh` VP1 (the filed repro verbatim) and VP2 – VP3 on five legs; VPY1 – VPY4 refused, PE word for word; `crossos/vector_param_forward_call.tcyr` W1 – W3 (FLOOR3 32). Mutation M-VP1 RED 31. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V2, after the D30 bite that passes a
vector call result to a value-form parameter) and, for the local, on the lane's base compiler (V1, `build/cycc`
2,270,080 B) alike.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — refused loudly on three targets; PE computes the right value. A per-target difference in what
compiles.
**Affects:** x86_64 / aarch64 / cx (refused), PE (accepted); every value-form vector parameter.
**Discovered:** 2026-10-16, the vectors lane (V2), probing D30's neighbours. D30 (the user, 2026-10-15: A) passes a
call declared to return the vector; its filing names the unwrapped call only.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn lanesn(x: f64v2): i64 { if (load64(&x) == 999) { return 0; } return load64(&x) * 10 + load64(&x + 8); }
fn main(): i64 { var v: f64v2 = f64v2_make(4, 2); return lanesn((v)); }
var rc = main(); syscall(60, rc);
```
```
base (V1): x86_64 / IR=3 / aarch64 / cx: error:<source>:4:65: value-form SIMD arg must be a local IDENT (caller-side
           scratch + addr-eval path not in v5.10.38 scope); PE (wine): 42
V2:        x86_64 / IR=3 / aarch64 / cx: error:<source>:4:65: a value-form vector argument to 'lanesn' is a local of
           its type or a call declared to return it (by name, a method, or fncallN / callptr with the callee written
           `&f`) - got `(...)`; PE: 42
```
The same with `lanesn((mkv(4, 2)))` (a call in parentheses) on V2: refused on the three, 42 on PE.

## Root cause

SysV / AAPCS64 / cx route a value-form vector argument through `_simd_arg_record` → `_sar_src` (parse_fn.cyr), which
takes a whole local name or a whole call (`_svc_rs`) and nothing in parentheses; the inline replay (`_inl_simd_arg`)
the same. Win64 passes the parameter by address through `_try_push_struct_addr_arg`, whose `_sarg_paren` (6.7.6) makes
parentheses wrapping the whole argument transparent, so the local's address — or the call's temp (`_sarg_vec_call`) —
is pushed.

## Proposed fix

Parentheses wrapping the whole argument are transparent for every other aggregate destination (6.7.6, 6.7.11): peel
them in `_sar_src` / `_inl_simd_arg` (`_pwrap_k`, closing with `_pw_close`) so the three targets take what PE takes —
or refuse on PE. A question for the user only if refusing is preferred; recommended: transparent. Rows beside
simd_pointer_param.sh's VC rows on x86_64 / IR=3 / aarch64 / cx / PE.
