# `*fncall0(&bp)` with `bp: *u8` reads a WORD, and `fncall0(&bp)[1]` is "cannot subscript ... it does not return a *T" — a known `&f` callee's `: *T` result carries T's step (6.7.14, D26) but not its element kind — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (unit R3, after the D25 / D26 bite) with
`build/cycc` built from that tree (x86_64); the lane base gives the same for both rows.
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — the dereference is a silent wrong value (8 bytes read through a `*u8`); the subscript is
refused loudly with a diagnostic that is now false (the callee does return a `*T`).
**Discovered:** 2026-10-17, the receives lane, D26 (issues/archived/2026-10-16-known-callee-pointer-or-f64-result-untyped.md).
D26 (a) (the user, 2026-10-16): "Does `fncall0(&gp)` with `gp` declared `: *P2` carry the pointer type, as `gp()`
does? (a) yes, as the direct call: no warning, and `fncall0(&gp) + 1` steps one P2". The bite carries the STEP and the
typed-pointer check; the element KIND the direct call's result also carries (`*bp()` reads one byte, `bp()[i]`
subscripts a `*u8`, 6.7.8 C2-5) is outside its filed surface.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
var B: i64 = 0x0102030405060708;
fn bp(): *u8 { return &B; }
fn main(): i64 {
    var a = *bp();
    var b = *fncall0(&bp);
    return a * 10 + (b == a);
}
syscall(60, main());
```

```
rc 0, no diagnostic; exit 80: `*bp()` reads the byte 8, `*fncall0(&bp)` the whole word 0x0102030405060708
(81 is right). `*(fncall0(&ip) + 1)` with `ip: *i32` reads 8 bytes the same way.
```

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
var B: i64 = 0x0102030405060708;
fn bp(): *u8 { return &B; }
fn main(): i64 {
    var h = bp()[1];
    var g = fncall0(&bp)[1];
    return g;
}
syscall(60, main());
```

```
error:<source>:8:25: cannot subscript the result of 'fncall0': it does not return a *T
```

## Root cause

The element kind of a `*T` value is vouched for by the factor wrapper (`_pk_post`, src/frontend/parse_expr.cyr) only
when its producer is a name, a field or a DIRECT call whose callee's `_fn_rps` word equals the scale word
(`_sub_word` / `_sub_callee`); for `fncall0(&bp)` the callee those read is `fncall0` (no `*T` return) and for
`callptr` none, so the kind bits the known callee's step word carries (`_icall_scalar`, 6.7.14) are not vouched and
`*e` reads a word. The subscript (`_sub_post`) asks the same `_sub_word` and refuses. The known callee is recorded
against its fncallN / callptr token (`_icall_ps_beg`); `_sub_word` / `_pk_post` do not read that record.

## Fix (if the user confirms the kind is part of D26's "pointer type")

`_sub_word`'s call arm and `_pk_post`'s `callptr` test answer the known callee's record when the call's fncallN /
callptr token is `_icall_ps_beg`. Rows: `*fncall0(&bp)` / `*callptr(&bp)` read the byte, `*(fncall0(&ip) + 1)` an i32,
`fncall0(&bp)[1]` is 7, a callee in a variable stays a word (the subscript refused as today).
