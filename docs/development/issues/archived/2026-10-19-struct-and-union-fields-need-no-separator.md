# A struct's (and a union's) fields need no `;`: `struct P { a b }` and `struct Q { x: i64 y: i64 }` compile — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-33, `ca0baea38`, with FF-34 `48cbe6783` and FF-35 `3482cd42e` — the user's D69 (2026-10-20): refuse it by name. `_fld_sep` (src/frontend/parse_types.cyr) replaces the field loops' optional `;` step in PARSE_STRUCT_DEF / PARSE_UNION_DEF. The filed repro is rc 1, "1:14: expected ';' between struct fields" + "2:19: expected ';' between struct fields" (it compiled and exited 46); `union U { a: i64 b: i32 }` "1:18: expected ';' between union fields"; a field-per-line struct one error at its second field; once per declaration; the last field may omit its `;`; a `,` keeps "expected identifier, got ','". The in-tree fixtures that relied on it (tests/tcyr/derive/derive_body_shapes.tcyr, two gate fixtures) gained their `;`s. Met: an unknown field type with a type-argument list is its one "unknown type" (FF-34), and field-type refusals point at the type's name (FF-35). Rows: new tests/gates/frontend/struct_field_separator.sh S1 (the filed repro verbatim) – S10 and A1 – A5 (run on x86_64, qemu-aarch64, cxvm, wine) on five legs (floor 80); struct_field_type_unknown_refused.sh UL / UC; mutants RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64; the
shared front end, every target), identical on the lane's compiler before F5 (11dfa7bff). Met while implementing
6.7.16's D12 (the enum member separator, issues/archived/2026-10-18-enum-members-need-no-separator.md).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF6) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D69 — Refuse it by name.
**Severity:** Low — accepted bad syntax; each field gets the offset the separated form gives.
**Kind:** language (whether a missing field separator is refused is the user's call — the twins were decided as
6.7.15's D1 (a), struct literal elements, and 6.7.16's D12, enum members: "Refuse it by name").

## Reproduction

```cyrius
struct P { a b }
struct Q { x: i64 y: i64 }
fn f(): i64 { var p = P { 3, 4 }; var q = Q { 5, 6 }; return p.b * 10 + q.y; }
syscall(60, f());
```

```
$ build/cycc < sd.cyr > sd; echo $?; ./sd; echo $?
0
46          # p.b = 4, q.y = 6: as `struct P { a; b; }` / `struct Q { x: i64; y: i64; }` give
```

`union U { a: i64 b: i32 }` compiles too (rc 0). A `,` between fields is refused (`struct P { a, b }`: "expected
identifier, got ','" + "unexpected '}'"), so `;` is the only separator and it is optional. The guide (§ Structs) shows
every field with its `;` and states no rule.

## Root cause

PARSE_STRUCT_DEF (src/frontend/parse_types.cyr, the member loop's tail `if (PEEKT(S) == 5) { STI(S, GTI(S) + 1); }`)
and PARSE_UNION_DEF (the same line) step a `;` when one is there and read the next field wherever the cursor stands —
the shape `_enum_sep` (6.7.16, D12) replaced for enums and `_slit_sep` (6.7.15, D1 (a)) for struct literals.

## Fix

A decision first (it changes what compiles): refuse a missing `;` between two fields by name ("expected ';' between
struct fields", once per declaration, at the second field) — D1 (a) / D12 applied to the third brace list — or document
the separator as optional in § Structs. Note for the fix: #derive's PP_DFIELD_TAIL (src/frontend/lex_pp.cyr) and
cyrlint's / cyrdoc's struct scans also accept a missing separator; a fixture with `{ a b }` must be searched for first
(6.7.16's D12 met tests/tcyr/derive/derive_body_shapes.tcyr's newline-separated enum that way).
