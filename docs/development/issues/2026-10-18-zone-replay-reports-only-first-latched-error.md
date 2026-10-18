# The declaration zone's replay reports only the FIRST latched error: every later zone declaration's error is silent — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F2, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 frontend lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — the build is refused (rc 1) and the first error is right; each later zone mistake is reported
only after the earlier one is fixed.
**Kind:** bug (diagnostic).
**Discovered:** 2026-10-18, by unit F2 adding rows for issues/2026-10-16-struct-literal-elements-need-no-comma.md
(two commaless zone literals gave one error; the fn-local and after-the-first-statement forms give one per
declaration). Not that issue's surface: every latched error class behaves this way in the zone.

## Reproduction

```cyrius
fn g(): i64 { return 1; }
var p = g(1 2);
var q = g(3 4);
syscall(60, 0);
```

```
error:<source>:2:13: expected ')', got number 2
```

One error. The same two declarations in a fn, or after the first top-level statement (`syscall(39);` first), give
two (`expected ')', got number 2` and `... got number 4`). Likewise `var p = P { c: 1, b: 2 }; var q = P { d: 1, b:
2 };` (two "unknown struct field in initializer", one printed) and, since 6.7.15, `var p = P { 3 4 }; var q = P { 5
6 };` (two "expected ',' between struct literal elements", one printed).

Expected: one error per declaration, as in a fn — each zone entry starts with the panic latch clear.

## Root cause

EMIT_GVAR_INITS (src/frontend/parse_decl.cyr) replays the zone's deferred entries one after another without
clearing `_panic` between them (only the destructure arm's own zone check, `edz`, clears it), and nothing calls
`_sync_skip` there; after the first ERR_EXPECT / ERR_MSG / ERR_IDENT latch, `_err_once` swallows every later report
of the replay.
