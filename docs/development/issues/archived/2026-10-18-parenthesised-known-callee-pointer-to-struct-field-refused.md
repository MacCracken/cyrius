# `(fncall0(&gp)).b` and `(*fncall0(&gp)).b` with `gp: *P2` are refused "the value in these parentheses is not a struct" where `fncall0(&gp).b`, `(gp()).b` and `(*gp()).b` read the field — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-6, `dff6a5d54` — no decision needed: 6.7.14's D26 (a) / D24 (a) and 6.7.13's D16, a known `&f` callee's result is the direct call's and a wrap is transparent before `.name`. The token typers learn the known callee: `_hl_pchain` / `_hl_cw` take a first arm for `fncallN(&f, ..)` / `callptr(&f, ..)` (`_hl_ic_psid`, `_hl_ic_fi`), and `_hl_psrc` admits a `callptr` source. The filed repro exits 44 (was refused at 9:28 "the value in these parentheses is not a struct"), and `(fncall0(&gp)).b` / `(*callptr(&gp)).b` read the field, on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine). The same gap's silent shapes, which the triage found unfiled, are fixed and pinned: `var t: P2 = *fncall0(&gp);` 22 (was 139 / 139 / 0 / 5 on x86_64 / aarch64 / cx / PE), `l = fncall0(&gp)`, `o.s = fncall0(&gp)` and `m = *fncall0(&gp)` 22 (were 0), `take(*fncall0(&gp))` and `return *fncall0(&gp);` compile and run. A callee held in a variable stays refused (6.7.11's D31), and `&gp` of a local named gp is that variable. Rows: `tests/gates/frontend/paren_field_access.sh` KC1 (the filed repro verbatim) – KC5 and A2, the new `tests/tcyr/crossos/known_callee_struct_pointer_source.tcyr` (24 rows), on every leg; five mutations each RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (unit R3, after the D31 bite, 0e135f5e3) with
`build/cycc` built from that tree (x86_64); the lane before the bite (d5adfcd2a) refuses both the same.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — valid-looking source refused loudly, by name (a false diagnostic); no wrong value. Workaround: drop
the wrap (`fncall0(&gp).b`) or bind it (`var q: *P2 = fncall0(&gp); q.b`).
**Discovered:** 2026-10-18, the receives lane, D31 (issues/2026-10-17-known-callee-narrow-pointer-result-deref-reads-a-
word-and-subscript-refused.md), probing a `*S` element of a known callee next to the narrow `*T` rows. Outside D31's
filed surface (a narrow scalar element's width and the subscript).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P2 { a; b; }
var G: P2 = P2 { 11, 22 };
fn gp(): *P2 { return &G; }
fn main(): i64 {
    var x = (*gp()).b;
    var y = (*fncall0(&gp)).b;
    return x + y;
}
syscall(60, main());
```

```
error:<source>:9:28: a field is read only from a struct value - the value in these parentheses is not a struct (or a pointer to one)
        var y = (*fncall0(&gp)).b;
                               ^
```

The same line with `(fncall0(&gp)).b`: `error:<source>:9:27: ... the value in these parentheses is not a struct (or a
pointer to one)`. With `(*callptr(&gp)).b`: the same at 9:28. The unwrapped `fncall0(&gp).b` (6.7.13's D16), `(gp()).b`
and `(*gp()).b` each compile and the program exits 44 (22 + 22).

## Root cause

6.7.14's D24 `( .. ) . name` route (`_paren_field`, src/frontend/parse_expr.cyr) types the inside of the wrap from the
TOKENS before it is parsed: `*E` by `_hl_dstar_t` (E a `*S` name / field / call by name) and a `*S` value by
`_hl_psid` (a call or method declared `: *T`, a `*T` field, pointer arithmetic on one). Neither reads a known `&f`
callee (`fncallN(&f, ..)` / `callptr(&f, ..)`, whose `*S` is `_fn_rpsid` of the fn `_icall_rs_at` / `_icall_fti`
finds), so the inside falls to `_pf_value`, whose struct records (`_lsc_*`) a `*S` scalar result never sets — refused
"not a struct".

## The fix (a sketch)

`_hl_dstar_t` / `_hl_psid` answer a known callee's `_fn_rpsid` for a whole `fncallN(&f, ..)` / `callptr(&f, ..)` (the
token route `_icall_sid_at` already takes for a struct by value), so both wraps take `_pf_deref` / `_pf_ptr` as
`(*gp()).b` / `(gp()).b` do. A callee held in a variable stays refused (6.7.11's D31: its result is a word).
