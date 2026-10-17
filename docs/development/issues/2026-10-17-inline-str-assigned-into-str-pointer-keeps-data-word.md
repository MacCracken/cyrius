# An inline `Str` ASSIGNED into a `*Str` (`p = t`, `GP = t`, `GP = gt`) keeps its data word, where `var p: *Str = t;` takes the header since 6.7.14 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S4) on the lane's tree after the D18 (c)
commit (`11dc74b4`), x86_64; the same on c778c981 (before the unit). Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
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
