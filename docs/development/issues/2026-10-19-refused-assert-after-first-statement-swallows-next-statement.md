# A refused `#assert` after the first top-level statement swallows the NEXT statement and its error — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F4) while adding rows for
issues/2026-10-18-refused-declaration-names-cascade-in-const-contexts-bounds-and-uninit.md (an `#assert E.B == 1` row
of a refused enum lost the following statement's `zz`). Identical on the lane before F4 (b2053aff7's build/cycc)
for any refused `#assert`; not that issue's surface. x86_64; the frontend, every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF2) — never 7.x.
**Severity:** Low — refused (rc 1); the next statement's own mistake is reported only after the `#assert` is fixed.
**Kind:** bug (diagnostic).

## Reproduction

```sh
printf 'var a = 1;\na = 2;\n#assert zz9 == 1\nsyscall(60, zz);\n' | build/cycc > /dev/null
# error:<source>:3:9: unknown name 'zz9' in a const context
#                                                   <- no "4:15: undefined variable 'zz'"
printf 'var a = 1;\na = 2;\n#assert zz9 == 1\nvar y = 1;\nsyscall(60, zz);\n' | build/cycc > /dev/null
# error:<source>:3:9: unknown name 'zz9' in a const context
# error:<source>:5:15: undefined variable 'zz' (missing include or enum?)
```

The array-size form of the same refusal (`var arr: i64[zz9];` in place of the `#assert`) reports both errors (4:15
`zz` included): it closes in sync.

## Root cause

PARSE_PROG takes the `#assert` through `_tl_directive` / PARSE_STMT; its const-context refusal latches the panic flag
and the directive (no `;` of its own) leaves the cursor on the next statement's first token, so that statement is
parsed under the latch (its error printed as nothing) or skipped by the resync. The const-context close
(`_ce_ctx_close`, 6.7.16 F3) gives an array size, an enum member and a case label their in-sync end; `#assert` at top
level after the first statement has none.

## Direction

The `#assert` directive's refusal ends in sync at the directive's own end (its line, or its optional `;`), so the next
statement is parsed with the latch clear. Diagnostics only.
