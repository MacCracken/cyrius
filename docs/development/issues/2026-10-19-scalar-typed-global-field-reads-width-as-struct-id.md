# A scalar-typed GLOBAL's `.field` reads its width (or float type id) as a struct id: `var g: i32 = 5; g.d` compiles, `var g: f64; g.a` crashes the compiler — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend, unit F2, x86_64), identical
on the slot-open compiler (480de63eb's build/cycc); the frontend, every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF2) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D68 — Refuse it with the local's words.
**Severity:** Medium — `.field` on an integer-typed global compiles (rc 0) and reads / writes the global through an
unrelated struct's field offset; on an `f64` / `f32` global the COMPILER segfaults (rc 139, no diagnostic). The local
form is refused ("no struct type in scope for 'g'").
**Kind:** bug (accepted bad source + compiler crash).
**Discovered:** unit F2, fixing issues/2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md — the same
class (a global's var type that is no struct id taken as one) in a different band, beyond that filing's surface (its
`*T` step band, 6.7.16 returns 0 for it in `_gv_recv_sid`).

## Reproduction

```sh
printf 'include "lib/syscalls.cyr"\nstruct P { a; }\nstruct Q { b; }\nstruct R { c; }\nstruct S { d; }\nvar g: i32 = 5;\nsyscall(60, g.d);\n' | build/cycc > /tmp/sc1; echo rc=$?
# rc=0 — the binary exits 5: `g.d` is S's field `d` (struct id 4 = i32's width 4), read at offset 0 of g
printf 'include "lib/syscalls.cyr"\nstruct P { a; }\nstruct Q { b; }\nstruct R { c; }\nstruct S { d; }\nvar g: i32 = 5;\ng.d = 9;\nsyscall(60, g);\n' | build/cycc > /tmp/sc5; echo rc=$?
# rc=0 — exits 9: the store went through S's `d` into g
printf 'include "lib/syscalls.cyr"\nstruct P { a; }\nvar g: u8 = 5;\nsyscall(60, g.a);\n' | build/cycc > /tmp/sc3; echo rc=$?
# rc=0 — exits 5 (u8's width 1 = struct id 1 = P)
printf 'include "lib/syscalls.cyr"\nstruct P { a; }\nvar g: f64 = 5;\nsyscall(60, g.a);\n' | build/cycc > /tmp/sc4; echo rc=$?
# warning:<source>:3:15: an integer stored into an f64/f32 slot keeps its integer bits (write a float literal)
# rc=139 — the compiler itself SIGSEGVs (F64_TYID read as a struct id: out of the struct tables)
printf 'include "lib/syscalls.cyr"\nstruct P { a; }\nvar y = 1;\ny = 2;\nvar g: f64 = 5.0;\nsyscall(60, g.a);\n' | build/cycc > /tmp/sc7; echo rc=$?
# rc=139, no output (after the first statement: PARSE_VAR's global arm, the same)
```

Controls: the local form `fn f(): i64 { var g: i32 = 5; return g.d; }` is refused, "no struct type in scope for 'g';
a '.field' access needs its struct declaration"; a `bool` global (`var g: bool = true; g.a`) is refused the same way
(its var type stays 0).

## Root cause

`_gv_recv_sid` (src/frontend/parse_types.cyr), PARSE_FIELD_LOAD's and PARSE_FIELD_STORE's global arm, returns the
global's GVTYPE when it has no `*T` struct. For a struct global that is the struct id; for a narrow integer global it
is the WIDTH (`SVTYPE(S, vcnt, scalar_type)`: 1 / 2 / 4), for a float global F64_TYID / F32_TYID (0x40000001..), so
`_field_load_on` / `_fst_on` index the struct tables with `sid - 1` — a small width lands on an unrelated declared
struct (or an empty slot), a float type id far outside the tables (the crash). 6.7.16 made the negative `*T` step band
answer 0 (the filed global-pointer item); the positive non-struct values are this filing.

## Fix (sketch)

Return 0 from `_gv_recv_sid` for a GVTYPE that is no struct id — a global whose var type is a scalar width or a float
type id (the narrow-integer / float registrations), keeping real struct ids — so the `sid == 0` arms refuse it as the
local is refused. It newly refuses source that compiles today (`g.d` on an `i32` global), so it is a refusal of
accepted bad source, the local's rule; check lib/ and the corpus have no such use.
