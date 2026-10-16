# A `: stack` pair-returning trait DEFAULT method used above its trait / impl is not a pair: `p.m(d)?` SIGSEGVs, `var v = p.m(d);` binds the tag — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, the R3 tip that makes
the pair prescan visit `impl` methods — issues/archived/2026-10-10-pair-method-defined-after-use-not-flagged.md, D23). The
repro below compiles clean and exits 139 on x86_64, 139 on aarch64 (qemu), 1 on cx (cxvm: "guest address out of
range") and 5 on PE (wine); with the `trait` and its `impl` moved above `usediv` it exits 70 on all four.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** High — valid `?` code crashes at run time with no diagnostic, and the single bind keeps the tag in
silence (a lossy bind the same program refuses when the trait comes first).
**Affects:** cycc 6.7.0 (traits with default methods) – the 6.7.11 lane tip, every target (the pair flag is shared
frontend state).

## Summary

6.7.11 (D23) makes `_pair_prescan` scan every method an `impl` block defines, so a pair-returning method is flagged
(fn flag 256) before any caller is parsed, whatever the order. A method the impl INHERITS from its trait's default
body (`trait Dv { fn ddiv(self, d): i64 { .. } }` + `impl Dv for Pt { }`) has no `fn` in the impl block: it is
registered by `_tr_defaults` (pass 1, `T_m` with the trait's `fn` token as its definition start) and its body lives
in the `trait` block. Neither the depth-0 walk nor the new impl-method walk (`_pair_prescan_impls`, which reads
`_tim_tab`, the impl's own methods) visits it, so its flag is set only when pass 2 parses the default for that
impl — and every caller above that point reads the method as one value.

That was outside D23's filed surface (the issue names `impl` methods and their mangled `T_m` / `T_Tr_m` entries; a
trait default has neither an `impl` `fn` token nor a body in the impl), so it is filed, not fixed in that commit.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
enum MR: stack { MOk(v); MErr(e); }
struct Pt { x; y; }
fn usediv(p: Pt, d): i64 { var q = p.ddiv(d)?; return MOk(q + 1); }
fn main(): i64 {
    var p = Pt { 40, 2 };
    var t, v = usediv(p, 4);
    var t2, v2 = usediv(p, 0);
    return t * 100 + v + t2 * 50 + v2;
}
trait Dv { fn ddiv(self, d): i64 { if (d == 0) { return MErr(9); } return MOk(self.x / d); } }
impl Dv for Pt { }
var rc = main();
syscall(60, rc);
```

```
x86_64:   compile rc 0; run: Segmentation fault, rc 139
aarch64:  rc 139 (qemu-aarch64)
cx:       rc 1 (cxvm: guest address out of range: 0)
PE:       rc 5 (wine)
expected: 70 (Ok(11) and Err(9) folded: 11 + 50 + 9), as with the trait and impl above usediv
```

Variants measured on the same tip (x86 / aarch64 / cx / PE):

- the `trait` ABOVE `usediv`, the `impl Dv for Pt { }` below: 139 139 1 5;
- `var q = p.ddiv(d);` (no `?`), trait + impl below: compiles, 3 3 3 3 (q is the tag);
- the same single bind with the trait + impl above: refused "a `: stack` enum returns two values — bind both".

## Root cause

`_pair_prescan` (`src/frontend/parse.cyr`) visits depth-0 `fn`s and, since 6.7.11, each impl's own methods
(`_pair_prescan_impls` → `_pair_scan_method`, over `_tim_tab`). An inherited trait default (`_trm_tab`, default
`fn` token + 1 at `+16`, not overridden by the impl: `_tim_of(S, ii, m) < 0`) is registered per impl by
`_tr_defaults` but never scanned.

## Proposed fix

In `_pair_prescan_impls`, for each trait impl (`_ti_tab + 48` = the trait index >= 0), visit each trait method with a
default that the impl does not override: resolve the entry the default was registered under for this impl
(`_tr_prefix`'s name — `T_m`, or the cached `T_Trait_m` — matched with `_fn_by_defti` on the default's `fn` token,
read only, never REGFN) and run `_pair_body_scan` over the default's body with `_pbs_iself` set to the impl's struct.
Rows: the repro (70); the single bind refused with the trait below; the trait above / impl below; a default that
forwards `return self.other(d);`; a plain i64 default below its use (no false flag); a crossos row (the `?`
lowering differs per backend).
