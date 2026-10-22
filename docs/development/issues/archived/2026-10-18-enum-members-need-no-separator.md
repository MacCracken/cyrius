# An enum's members need no separator: `enum E { A B }` and `enum E { A = 1 B = 5 }` compile — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-16, `372045567` — the user's decision D12 (2026-10-19, at the 6.7.16 open): "Refuse it by name". `_enum_sep` (src/frontend/parse_types.cyr) replaces PARSE_ENUM_DEF's optional separator step: a `;` / `,` is stepped, `}` / end of file left, a member name there is "expected ';' or ',' between enum members" (pass 1), the member read from there; `_enum_sep_end` releases the latch at the enum's `}`. The filed repro `enum E { A B }` (rc 0, exit 1) and `enum E { A = 1 B = 5 }` (exit 5) are now one error at B (1:12 / 1:16), rc 1, on x86_64, aarch64, cx, PE and Mach-O; `enum E: stack { Ok(x) Err(e) }` and one member per line with no separator too (a line break is no separator — ⚠ beyond the answer's named shapes; D69's reasons, 2026-10-20, restate it); once per enum, a second enum its own, `--syntax-only` too. A trailing separator and mixed `;` / `,` stay valid; `enum E { A 5 }` keeps "expected identifier". The lint fixture's `enum Bare` (named by D12) and tests/tcyr/derive/derive_body_shapes.tcyr's newline-separated `ENl` gained their commas, values unchanged. Rows: the new `tests/gates/frontend/enum_member_separator.sh` — S1 / S2 (the repros) – S8 on three compilers, A1 – A7 acceptances; mutations: the pre-bite compiler RED S1 – S7, no error RED S1 – S7, no latch release RED S5 / S6, erring on any token RED S8. Filed beside it (placed IN 6.7.16, D69): struct and union fields with no separator. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F2, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D12 — Refuse it by name.
**Severity:** Low — accepted bad syntax; the members get the values the separated form gives.
**Kind:** language (whether a missing separator is refused is the user's call — the struct-literal twin was decided
as 6.7.15's D1 (a), 2026-10-18).
**Discovered:** noted in passing by the 6.7.15 triage of issues/archived/2026-10-16-struct-literal-elements-need-no-comma.md
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
