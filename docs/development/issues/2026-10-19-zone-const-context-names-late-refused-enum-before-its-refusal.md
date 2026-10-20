# A declaration-zone global's array size or enum value naming a LATE (refused) enum is "unknown name 'E' in a const context", printed before the declaration's own error — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F4), fixing
issues/2026-10-18-refused-declaration-names-cascade-in-const-contexts-bounds-and-uninit.md. F4 enters a late
declaration's names in pass 1's tail walk (`_dl_fill`, before `_cst_sweep`), so a top-level const, an array size after
the first statement, a case label and an earlier fn's use stand down. The zone's own const contexts are evaluated
DURING the zone scan (`_tl_scan1` -> PARSE_GVAR_REG -> PARSE_GVAR_ARR; PARSE_ENUM_DEF's values), before the first
statement — and so the late declarations — is known. That issue's triage named PARSE_GVAR_ARR, but its filed repro's
array (`var arr: i64[E.B];`, line 5) is after the first statement (PARSE_VAR, pass 2), which F4 covers; the zone shape
below was in no repro. Measured on F4's lane head (x86_64; the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — refused (rc 1); the declaration's error is printed, after one invented error.
**Kind:** bug (diagnostic cascade).

## Reproduction

```sh
printf 'var arr: i64[E.B];\nvar a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:1:14: unknown name 'E' in a const context
# error:<source>:4:1: an `enum` declaration must come before the first top-level statement (line 3)
printf 'enum F { X = E.B }\nvar a = 1;\na = 2;\nenum E { A, B }\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:1:14: unknown name 'E' in a const context
# error:<source>:4:1: an `enum` declaration must come before the first top-level statement (line 3)
```

A zone `const C = E.B;` (swept after the tail walk) and a zone `#assert E.B == 1` are one error each.

## Root cause

The refused set (`_dlr`) is filled by `_dl_fill` in `_prescan_tail_loop`, which needs `_tl_stmt1` — the end of the
zone scan. A zone array size or enum value is evaluated inside that scan, when the set is still empty; at that point
a name declared later in the zone (valid, "declared after its use") and one declared after the first statement
(refused) look alike.

## Direction

Defer the zone's unknown-name report in a const context until the first statement is known (record (token, name) and
report it after `_dl_fill` unless the name is a refused declaration's), or find the late declarations by a
side-effect-free walk before the zone scan. Either must keep pass 1's order of the remaining reports. Diagnostics only.
