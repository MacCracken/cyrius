# An inline `Str` assigned into a `*Str` FIELD or through a `**Str` (`w.p = gt`, `GW.p = gt`, `pw.p = gt`, `*pp = gt`) still stores the data word — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 structs lane (D16, bc2381c9f), re-measured by its
fix step on the lane head 342244fa8 and on the lane base 8b4d44602 alike (x86_64; the review measured aarch64 (qemu)
and cx (cxvm) the same). No diagnostic on any of them.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs review, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
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
