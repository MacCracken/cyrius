# A temporary taken while an `#inline` fn's arguments are evaluated lies past the frame — `id(a) + id(a + 1)` (a u128) reads 84 for 83 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V2's base, `build/cycc` 2,416,992 B, the
lane after V1), x86_64 / x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine).
**Update 2026-10-17 (the vectors lane's review fix, commit 986123203):** half (2) below landed — a closure's frame is
sized from `max(GFLC, _flc_hwm)` (`_cl_frame_bytes`, src/frontend/parse_expr.cyr), because D31 / D32's newly accepted
sources as an `#inline` fn's argument inside a closure miscompiled through it (rows simd_pointer_param.sh VCi1-VCi5,
crossos/simd_pointer_param.tcyr `sp_irows`). Half (1) is what remains OPEN: both repros below still give the numbers
shown, re-measured on the review-fix tree (x86_64 / IR=3 / aarch64 / cx / PE: 84 / 84 / 84 / 83 / 84, and in the
closure 43 / 43 / 84 / 83 / 43) — the u128 temp is lost by the inline path's `SFLC`, which (2) cannot cover.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** High — a silent wrong value (no diagnostic) on x86_64, aarch64 and Windows from ordinary source: a u128
expression passed to an `#inline` fn whose result is an operand of a larger expression.
**Affects:** every frame-slot temporary taken while an inline candidate's arguments are evaluated that does not
record itself in `_flc_hwm` — `_w128_tmp` (a u128 operation's temporary), `_HTEMP` (hidden temps: `_dlo_park`, the
vector receives' parked pointers, ..) — on x86_64 / aarch64 / PE; in a closure body, every such temporary (below).
**Discovered:** 2026-10-17, the vectors lane (V2), while a captured vector's env copy (D31) first used a hidden temp
in `_inl_simd_arg` and faulted inside `|k| lanes(b) + k` on x86_64 (V2 copies through the stack instead).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
#inline
fn id(x): i64 { return x; }
fn main(): i64 {
    var a: u128 = 40;
    return id(a) + id(a + 1) + 2;
}
var rc = main(); syscall(60, rc);
```

```
x86_64: 84    x86_64 CYRIUS_IR=3: 84    aarch64 (qemu): 84    cx (cxvm): 83    PE (wine): 84
83 is right (40 + 41 + 2). The same two calls as separate statements (`var r1 = id(a); var r2 = id(a + 1);`) give
40 and 41 on every target.
```

In a closure body the plain-fn fix below is not enough:

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
#inline
fn id(x): i64 { return x; }
fn main(): i64 {
    var a: u128 = 40;
    var c = |k| id(a) + id(a + 1) + k;
    return fncall1(c, 2);
}
var rc = main(); syscall(60, rc);
```

```
x86_64: 43    IR=3: 43    aarch64: 84    cx: 83    PE: 43        (83 is right)
```

## Root cause

Two halves, both measured (scratch tree copies, 2026-10-17):

1. PARSE_FNCALL's inline path (src/frontend/parse_fn.cyr, "Set local count past the param slots") reserves the
   parameter slots, evaluates the arguments — which may take frame temporaries at `GFLC` and above — and then
   `SFLC(S, saved_flc + _ptot)`, releasing them, with `_flc_hwm` recording only `saved_flc + _ptot`. PARSE_FN_DEF sizes
   the frame from `max(GFLC, _flc_hwm)`, so a temporary at or past `saved_flc + _ptot` (here `a + 1`'s `_w128_tmp`, 2
   slots) can lie below the frame, where the pushed left operand (`id(a)`'s 40) lives: the temp's 41 overwrites it.
   Bumping `_flc_hwm` to `GFLC` before that `SFLC` makes the first repro 83 on every target (measured).
2. (FIXED in 986123203, see the update above.) A closure's frame was sized from `GFLC` alone (parse_expr.cyr,
   `cl_fsz = (GFLC(S) * 8 + 15) & (0 - 16)` after the body), never `_flc_hwm`, so even with (1) the second repro
   stayed 43 / 84 / 43. `_sarg_snap` (which bumps `_flc_hwm` for its hidden temp) and every other `_flc_hwm` user
   was exposed the same way inside a closure.

## Fix direction

(1) record `GFLC` in `_flc_hwm` before the inline path's `SFLC` back to its parameters (one line); (2) is in
(986123203). Rows: both repros on x86_64 / IR=3 / aarch64 / cx / PE, and a `*S`
dereference / struct operator temp in an inline argument inside a closure.
