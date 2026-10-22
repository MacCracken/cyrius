# A struct literal's `*Str` field element from an inline `Str` (`W { gt, 1 }`, `W { t, 1 }`) stores the data word — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-9, `0696846c4` — 6.7.16's D19 (the user, 2026-10-19: a frame's inline `Str` into a `*Str` field is refused, a global's or a capture's takes its header's address) carried from the assignment to the literal, the filing's fix direction. `_sfw_set` records a `*Str` field (`_istr_pfs`) and EMIT_STRUCT_FIELD_W calls `_istr_pfld`. Repro 1 exits 7 (it was 0) and the top-level `var GW: W = W { gt, 1 };` 7 (0), on every leg; repro 2 (a frame's `W { t, 1 }`) is refused "cannot store the inline Str 't' into a field - its header lives in this frame and would dangle (store a handle: str_new(data, len))", one error, no binary (it compiled). Named, a nested leaf, the zone and after a statement the same. Rows: `inline_str_value.sh` PL1, PL2, PL2b, PL2c, PL3; `crossos/inline_str_value.tcyr` pl_* and R_TOP17; mutant s1 RED 33. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S2) while landing D19 (an inline `Str`
ASSIGNED into a `*Str` field takes its header's address; a frame's is refused). Pre-existing: the same output on the
lane's compiler before D19 (4acc6f7c4) and after it, x86_64. Not that filing's surface (its destinations are
assignments: `w.p = gt`, `GW.p = gt`, `pw.p = gt`, `*pp = gt`), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS2) — never 7.x.
**Severity:** Medium — silent wrong value: the `*Str` field holds the string's bytes read as a header (`str_len(w.p)` 0
here, a wild length for a longer string); a frame's `t` compiles silently where the same element into a `Str` field is
refused as would-dangle. Not a security id (the developer's own source).
**Kind:** bug — the struct-literal twin of D19 / 6.7.15's D16. A literal's `Str` field element takes the header's
address since 6.7.13's D7 (1) (`W { gt, 1 }` into `s: Str`, `_istr_lit`; a frame's `t` refused "into a field", the
gate's X8); `_istr_lit` asks `IS_STR_FIELD` only, so a `p: *Str` field keeps the one-word store.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
fn go(): i64 { var w: W = W { gt, 1 }; return str_len(w.p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < lit.cyr > lit && ./lit; echo $?
0           # want 7 (w.p = gt; gives 7 since 6.7.16's D19)
```

The same with a frame's inline `Str` — compiles with rc 0 and no diagnostic, exits 0:

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct W { p: *Str; n; }
fn go(): i64 { var t: Str = Str { "abc", 3 }; var w: W = W { t, 1 }; return str_len(w.p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
```

and a top-level `var GW: W = W { gt, 1 };` then `str_len(GW.p)` — 0, want 7.

## Root cause

`_istr_lit` (src/frontend/parse_decl.cyr, a struct literal's element just parsed) returns at `IS_STR_FIELD(S, ft) == 0`;
a `*Str` field's type is no `Str` field type (its pointee lives in the field step table, `_fld_ptr_sid` /
`_fld_ps_get`), so the element's first word is stored.

## Fix direction

Ask the field's `*Str`-ness as `_fst_on` does since D19 (`_istr_pfs(S, si, fi)`: pointee `Str`, step 16) in the literal
element paths (`_sfw_set` records the field): a global's or a capture's inline `Str` takes `_istr_ra`, a frame's is
refused with the field words (`_istr_fsc_err`), as D19 decided for the assignment. Rows beside the pa_fld_* rows of
tests/tcyr/crossos/inline_str_value.tcyr (a local's literal, a global's literal at top level, a nested literal) and a
refusal row beside X8 / X15 of tests/gates/frontend/inline_str_value.sh.
