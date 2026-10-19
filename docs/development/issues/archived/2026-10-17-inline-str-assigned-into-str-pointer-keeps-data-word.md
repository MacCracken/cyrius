# An inline `Str` ASSIGNED into a `*Str` (`p = t`, `GP = t`, `GP = gt`) keeps its data word, where `var p: *Str = t;` takes the header since 6.7.14 — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-6, `bc2381c9f` — the user's decision D16, 2026-10-18: "Take the header's address". `_istr_dst` answers for a `*Str` local, parameter or global, and `_istr_asg` stores the header's address typed as the pointer's step word. The filed repro `p = t; return str_len(p);` exits 7 (was 0); the table's `GP = gt` exits 7 with no warning (was 0 + "assigning non-pointer to typed pointer"), `p = gt` 7 (was 0), and `GP = t` from a frame's inline `Str` is refused "cannot store the inline Str 't' into a global - its header lives in this frame and would dangle (store a handle: str_new(data, len))" (was 0, no diagnostic) — on x86_64, IR=1, IR=3, DCE, aarch64, cx and PE (the repro also on ecb, ach, pi and cass). Also wrapped, a `p: *Str` parameter, a for step and top level; a closure's captured copy is not refused. Rows: `frontend/inline_str_value.sh` D16a (the repro verbatim), D16b, X14; `crossos/inline_str_value.tcyr` pa_* and R_TOP7; mutations RED. Not closed here (filed, 6.7.16, by the lane's review): a `*Str` FIELD destination (`w.p = gt`) and `*pp = gt` through a `**Str` still store the data word (`2026-10-18-inline-str-into-str-pointer-field-or-double-pointer-keeps-data-word.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S4) on the lane's tree after the D18 (c)
commit (`11dc74b4`), x86_64; the same on c778c981 (before the unit). Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D16 — Take the header's address.
**Severity:** Medium — silent: `str_len(p)` reads the string's bytes as a header (0 here). Not a security id (the
developer's own source).
**Kind:** language (decision) — 6.7.14's D18 (c) (issues/2026-10-15-inline-str-into-untyped-or-other-pointer-position-
passes-data-word.md, "only where a type says Str") named the stdlib methods' operand and the DECLARATION `var p: *Str
= t;`; an ASSIGNMENT into a `*Str` local, parameter or global is a position typed `*Str` too, outside the filed table.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
var gt: Str = Str { "abcdefg", 7 };
var GP: *Str = 0;
fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var p: *Str = 0; p = t; return str_len(p); }
fn main(): i64 { alloc_init(); return go(); }
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < sD.cyr > sD && ./sD; echo $?
0           # p = t stored t's data word; `var p: *Str = t;` exits 7 since 6.7.14
```

| `go()` body | exit | note |
| --- | --- | --- |
| `var p: *Str = 0; p = t; return str_len(p);` | 0 | no diagnostic |
| `GP = t; return str_len(GP);` (t a frame's inline Str) | 0 | no diagnostic — and t's header would outlive the frame |
| `GP = gt; return str_len(GP);` | 0 | warns "assigning non-pointer to typed pointer" |
| `var p: *Str = 0; p = gt; return str_len(p);` | 0 | no diagnostic |
| control `var p: *Str = t; return str_len(p);` | 7 | D18 (c) |

## Root cause

`_istr_asg` (src/frontend/parse_decl.cyr) takes the header only into a `Str` HANDLE destination (`_istr_dst`: GLTYPE
`0 - Str`, no GLPTRP; a global GVPM 1 with no `_gv_ptr_sid`); a `*Str` local / parameter (GLPTRP 1) or global
(`_gv_ptr_sid` Str) answers 0, so the factor's word is stored. 6.7.14's `_istr_pdecl` covers the declaration only.

## The question

Should `p = t` / `GP = t` into a `*Str` take t's header as the declaration does (then `GP = t` from a frame's inline
`Str` would need D7 (1)'s would-dangle refusal, as `G = t` into a `Str` global has), or keep the word (documented)?
