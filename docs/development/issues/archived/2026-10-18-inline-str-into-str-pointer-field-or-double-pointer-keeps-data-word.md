# An inline `Str` assigned into a `*Str` FIELD or through a `**Str` (`w.p = gt`, `GW.p = gt`, `pw.p = gt`, `*pp = gt`) still stores the data word — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-4, `918dd5e89` — the user's D19, 2026-10-19: "Refuse it, as a Str field store is refused"; a global's or a capture's inline `Str` stores its header's address, as 6.7.15's D16 does for names. `_fst_on` reads whether its leaf field is a `*Str` (`_istr_pfs`) and `_istr_pfld` takes `_istr_at`'s answer; `_istr_dsto` gains `_istr_dspp` for a `**Str` operand. Repro 1 exits 9 (777 % 256; was 0) and repro 2 exits 7 (was 0) on x86_64, IR=1, IR=3, DCE, aarch64 (qemu), cx (cxvm) and PE (wine) — nested fields, a `: *W` call's field, a for step, `*GPPS` / `*gpps()`, a `pp: **Str` parameter and top level alike. A frame's inline `Str` is refused by name into any `*Str` field — a local struct's (D19's decided shape), a global's, through a `*W`, a for step — "cannot store the inline Str 't' into a field - its header lives in this frame and would dangle (store a handle: str_new(data, len))", and through a `**Str` ("… through a pointer …"); all compiled before. The refusals beyond the local struct's field go past D19's answer text (its reason calls them the same under both options; 6.7.13's D7 (1)). Rows: `tests/tcyr/crossos/inline_str_value.tcyr` pa_fld_* (8), pa_pp_* (6), R_TOP13 / R_TOP14, `tests/gates/frontend/inline_str_value.sh` FD1 / FD2 (the two filed repros verbatim, seven legs) and X15 – X19 (the refusals, four compilers); mutations RED 41 / 30 / 18. Not this filing's surface, filed beside it (placed IN 6.7.16, the s16 lane): a struct literal's `*Str` element (`W { gt, 1 }`) still takes the data word (`docs/development/issues/archived/2026-10-19-struct-literal-str-pointer-field-from-inline-str-stores-data-word.md`). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 structs lane (D16, bc2381c9f), re-measured by its
fix step on the lane head 342244fa8 and on the lane base 8b4d44602 alike (x86_64; the review measured aarch64 (qemu)
and cx (cxvm) the same). No diagnostic on any of them.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D19 — Refuse it, as a Str field store is refused.
**Severity:** Medium — silent wrong value: the `*Str` holds the string's bytes read as a header (`str_len` 0 here, a
wild length for a longer string). Not a security id (the developer's own source).
**Kind:** bug — the field / pointee twin of what 6.7.15's D16 decided for NAMES (`p = t`, `p = gt`, `GP = gt` take the
header's address). D16's filed surface is the `*Str` local, parameter and global name (`_istr_dst` 3 / 4); a `*Str`
field destination and a `*pp` destination through a `**Str` were outside it.

## Reproduction

A `*Str` field — a local struct, a global struct, through a `*W`:

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
var GW: W = W { 0, 0 };
fn go(): i64 { var w: W = W { 0, 1 }; w.p = gt; GW.p = gt; var pw: *W = &w; pw.p = gt; return str_len(w.p) * 100 + str_len(GW.p) * 10 + str_len(pw.p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < d16i.cyr > d16i && ./d16i; echo $?
0           # want 777 % 256 = 9
```

Through a `**Str`:

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
struct W { p: *Str; n; }
fn go(): i64 { var q: *Str = 0; var pp: **Str = &q; *pp = gt; return str_len(q); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < d16h.cyr > d16h && ./d16h; echo $?
0           # want 7
```

Controls (since D16): `var q: *Str = 0; q = gt; return str_len(q);` gives 7; `var p: *Str = gt;` gives 7.

## Root cause

D16 (bc2381c9f) arms `_istr_dst` (src/frontend/parse_decl.cyr) for a `*Str` NAME only — 3 for a local or parameter,
4 for a global (`_istr_pdst`, which reads a name's step word) — and `_istr_asg` takes the header's address
(`_istr_ra`) for those answers. A field store (`w.p = ..`, `GW.p = ..`, `pw.p = ..`) goes through the field-store path,
and `*pp = ..` through the `*p = v` destination (`_agc_ovr`, which the D16 commit says "never takes the new answers");
neither asks whether the source is an inline `Str` while the destination is a `*Str`, so both store the source's first
word (t.data).

## Fix direction

Apply D16's rule at the two other destinations: a `*Str` field (its field type read as `_istr_pdst` reads a name's)
and a `*pp` whose pointee is a `*Str` take the inline source's header address; a frame's inline `t` stored into a
global's field keeps the would-dangle refusal `GP = t` gives. Rows beside tests/tcyr/crossos/inline_str_value.tcyr's
pa_* rows (a local field, a global field, through a `*W`, `*pp`, a for step) and tests/gates/frontend/inline_str_value.sh
(the two repros verbatim, every leg).
