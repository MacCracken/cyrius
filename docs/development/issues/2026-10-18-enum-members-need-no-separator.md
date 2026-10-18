# An enum's members need no separator: `enum E { A B }` and `enum E { A = 1 B = 5 }` compile — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F2, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** unplaced — filed from the 6.7.15 frontend lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — accepted bad syntax; the members get the values the separated form gives.
**Kind:** language (whether a missing separator is refused is the user's call — the struct-literal twin was decided
as 6.7.15's D1 (a), 2026-10-18).
**Discovered:** noted in passing by the 6.7.15 triage of issues/2026-10-16-struct-literal-elements-need-no-comma.md
("enum members also accept a missing comma ... outside this filing") and re-measured by unit F2, which implemented
D1 (a) for struct literals only.

## Reproduction

```cyrius
enum E { A B }
syscall(60, E.B);
```

rc 0, no diagnostic, exit 1 (as `enum E { A; B; }`). `enum E { A = 1 B = 5 }` then `syscall(60, B);` exits 5. The
guide (§ Enums) says "Variant separators may be `;` or `,`" and shows every enum with one; a trailing separator
(`enum E { A, B, }`) compiles (exit 1) and is not in question.

## Root cause (not bisected)

The enum member loop (PARSE_ENUM_DEF, src/frontend/parse_types.cyr) steps a `;` / `,` after a member when one is
there and reads the next member wherever the cursor is, as the struct literal's element store did before 6.7.15
(EMIT_STRUCT_FIELD_W's optional comma step, now `_slit_sep`).

## Fix

A decision first (it changes what compiles): refuse a missing separator between two members by name ("expected
';' or ',' between enum members") — the struct literal's D1 (a) applied to the other brace list — or document the
separator as optional in the guide's § Enums.
