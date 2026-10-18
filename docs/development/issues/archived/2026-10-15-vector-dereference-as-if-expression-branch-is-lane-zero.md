# A vector dereference as an if-expression branch is an integer — lane 0's word — where a vector name branch is refused — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-9, `896c2d322`: a whole dereference of a `*V` as an if-expression branch is the vector, and is refused as `{ a } else { b }` is: "an if expression branch cannot be a vector, u128 or slice value - branch on a pointer (&x)". No new decision: 6.7.13's D34 makes `*pv` the vector, and the existing rule refuses the branch. The filed repro (42 on x86_64, aarch64, cx and PE) is refused at compile time, once per branch, on the four compilers. So are `{ (*pa) }`, `{ *gpv() }`, f32v4 / f64v4 / i32v4, `{ *&a }`, `{ **ppa }`, a `*V` field, `*(pa + 0)`, and the top level. A `*i64` dereference stays an integer. Rows: `if_expr_checked.sh` D9 (the filed repro verbatim, flipped from 42 to refused, also on aarch64 / cx / PE), D12 - D21, controls D22 / D23; mutation RED 12. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 structs lane (`l6713-structs`, the struct-dereference
branch fix in progress) and on its base (the lane's commit before it): identical, x86_64.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean with no diagnostic and silently drops the other lanes; the plain spelling
`if (c) { a } else { b }` with vector names is refused by name. Not a security id (the developer's own source).
**Discovered:** 2026-10-15, the 6.7.13 structs lane (unit S2), giving the if-expression a struct-dereference arm
(issues/archived/2026-10-14-dereference-as-if-expression-branch.md): the brief asked for a `*pv` row to show the arm skips a
vector dereference; it does, and the row shows what the branch is today.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn main(): i64 {
    var a: f64v2 = f64v2_make(42, 7);
    var b: f64v2 = f64v2_make(5, 6);
    var pa: *f64v2 = &a;
    var pb: *f64v2 = &b;
    var c = 1;
    var x = if (c == 1) { *pa } else { *pb };
    return x;
}
syscall(60, main());
```

```
$ build/cycc < iev.cyr > iev && ./iev; echo $?
42                    # lane 0 of a; no diagnostic
```

The same if-expression over the vector NAMES is refused:

```
var x = if (c == 1) { a } else { b };
error: an if expression branch cannot be a vector, u128 or slice value - branch on a pointer (&x)
```

(tests/gates/frontend/if_expr_checked.sh R16 / V2 refuse the name forms.)

## Root cause

`_ie_struct_sid` (src/frontend/parse_ctrl.cyr) answers -1 (a vector / u128 value) only for a NAME
(`_ie_wide_name`) or a whole call returning a vector; a dereference `*pv` of a `*V` is no name, and its operand's
typing (`_hl_psid` / `_hl_dpsid`) answers 0 for a vector pointer (its step word carries the vector in bits 48-55
since 6.7.12, `_ps_vdesc`), so the branch is an integer and `_deref_read` loads lane 0's word.

## Proposed fix

Give the if-expression's vector test a dereference arm: a whole `* E` branch whose operand's step word names a
vector (`_ps_vdesc(_pk_word(S))` after the branch's parse, as `_dlo_vec` reads it) answers -1, so `_ie_kind` refuses
it with the vector message, as `{ a }` is. tests/gates/frontend/if_expr_checked.sh D9 pins today's lane-0 value and
flips to a refusal row with it. Rows: `{ *pa } else { *pb }`, `{ (*pa) } else { a }`, a `: *V` call, f32v4 / f64v4,
top level.
