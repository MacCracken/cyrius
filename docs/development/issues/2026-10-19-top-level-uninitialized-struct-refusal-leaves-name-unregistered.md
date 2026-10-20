# `var c: S;` at top level after the first statement is refused, swallows the next statement and leaves `c` unregistered ("undefined variable 'c'" at its uses) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F1) while measuring the bare-declaration
fix (issues/2026-10-18-bare-declaration-refusal-reads-next-statement-as-initializer.md: `var c;` / `var c: ;` now end
at their `;` and register `c`). This shape takes a different PARSE_VAR arm (the uninitialized-struct one) and is
outside that filing. Measured on the slot-open compiler (480de63eb's build/cycc) and on the lane head 814a8fb36
(x86_64; the frontend, every target): identical.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF2) — never 7.x.
**Severity:** Low — refused either way (rc 1); the first error is the right one; the next statement is lost or one
invented error follows.
**Kind:** bug (diagnostic cascade).

## Reproduction

```cyrius
struct Str { p; n; }
var q = 0;
q = 1;
var c: Str;
var d = 9;
c = 4;
syscall(60, zz);
```

```
$ build/cycc < tl12.cyr > /dev/null
error:<source>:4:11: uninitialized struct locals only allowed inside a function
error:<source>:6:6: undefined variable 'c'
error:<source>:7:15: undefined variable 'zz' (missing include or enum?)
```

Without the `var d = 9;` line, `c = 4;` directly after the declaration is swallowed instead (two errors: 4:11 and
`zz`). The same declaration in a fn body compiles (an uninitialized struct local is allowed there).

## Root cause

PARSE_VAR's uninitialized-struct arm (`pscale < 0 && PEEKT(S) == 5`, src/frontend/parse_decl.cyr, the
"uninitialized struct locals only allowed inside a function" ERR_MSG) refuses at top level and then goes on to register
the name as a FN-LOCAL slot (GFLC / the 0x5D9D000 name table / SFLC) and consume the `;`. Outside a fn FINDLOCAL is not
consulted, so every later use of `c` is "undefined variable 'c'". And the refusal latches without the in-sync mark
(`_refuse_in_sync`, 6.7.16), so PARSE_STMT's resync skips the statement after it.

## Direction (not decided here)

Both halves together: mark the refusal in sync and register `c` as a global (or enter it as reported) so its uses add
nothing. Marking alone would turn the swallowed `c = 4;` into an invented "undefined variable 'c'". Rows: the repro gives
two errors (4:11 and zz); `c = 4;` directly after it is parsed with no error of its own.
