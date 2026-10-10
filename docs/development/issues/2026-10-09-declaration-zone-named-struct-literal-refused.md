# A named-field struct literal in the declaration zone is refused ("undefined variable 'a'") — the guide's own Structs example fails as written — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 on x86_64, aarch64, cx and PE (all four
compilers refuse it at the same token), and on every installed 6.6.0 – 6.7.6 compiler and `build/cc5` (5.11.69).
The same literal compiles and runs (exit 2) inside a fn, and as a top-level `var` after the first statement.
**Placement:** 6.7.12 — Break 2, repair 3, the globals lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 B4 (tuples) planners (probes n1, g816); filed 2026-10-09 by the B4 lane
(bite T0).
**Severity:** Medium — a hard failure on documented syntax with a known workaround.
**Affects:** cycc ≤ 6.7.6 (measured back to cc5 5.11.69)

## Summary

`var p = P { a: 1, b: 2 };` at top level, before the first statement (the declaration zone), is a compile error:
`undefined variable 'a' (missing include or enum?)` at the first field name. The positional form `P { 1, 2 }` in the
same place works, and so does the named form inside a fn or after the first top-level statement. The guide's
*Structs* section (`docs/guides/cyrius-guide.md:816`) teaches exactly the failing shape at top level, and
`guide_examples_compile.sh` does not catch it because an "undefined" name in an include-less block is excused as an
illustrative fragment.

## Reproduction

n1:

```cyrius
struct P { a; b; }
var p = P { a: 1, b: 2 };
syscall(60, p.b);
```

g816 — the guide's Structs example as written (`docs/guides/cyrius-guide.md:812-817`):

```cyrius
struct Point { x; y; }
var p = Point { 10, 20 };
var q = Point { x: 10, y: 20 };
var sum = p.x + p.y;
syscall(60, sum + q.y);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Actual: `error:<source>:2:14: undefined variable 'a' (missing include or enum?)` (n1) and
`error:<source>:3:18: undefined variable 'x' …` (g816), on every target. Expected: n1 exits 2; g816 exits 50.

| Shape | Result (all four targets) |
|---|---|
| n1 — named literal in the declaration zone | refused, `undefined variable 'a'` |
| the same with an annotation, `var p: P = P { b: 2, a: 1 };` | refused, `undefined variable 'b'` |
| the same in a `kernel;` build (x86_64 only) | refused, `undefined variable 'a'` |
| positional `var p = P { 1, 2 };` in the declaration zone | 2 |
| named literal inside a fn (`var p = P { a: 1, b: 2 }; return p.b;`) | 2 |
| named literal as a top-level `var` after the first statement (`k = k + 1;` first) | 2 |

## Root cause

The declaration-zone replay (`EMIT_GVAR_INITS`, `src/frontend/parse_decl.cyr:4453`) handles a `Name {` initialiser
by calling `_emit_struct_positional_init(S, idx, sid)` directly (`parse_decl.cyr:4547`). The named-field form is
detected only in `_STRUCT_INIT_BODY` (`parse_decl.cyr:2281`, the `IDENT :` test at :2287), which the fn-local path
and the after-the-first-statement path (`PARSE_STRUCT_INIT`, :2349 → :2363) go through. The positional walk then
parses `a` as an expression. The constant baker the replay runs first (`_spc_try`, :4316) already declines a
named-field list, so only the replay's store path is wrong.

## Proposed fix

Route the replay's struct-literal arm through `_STRUCT_INIT_BODY(S, idx, sid)` (or its named branch) as
`PARSE_STRUCT_INIT` does — speculation: the `_sl_base_li` save / reset PARSE_STRUCT_INIT wraps around it may be
needed here too. Optionally teach `_spc_walk` the named form so an all-constant named literal is baked like a
positional one (a `kernel;` build then needs no late store for it). Gate rows: n1, the annotated form, the `kernel;`
form, and g816 compiled and run (exit 50), so the guide example is pinned by a run, not by the excusing gate.

## Consumer-side workaround

Use the positional form in the declaration zone (`var p = P { 1, 2 };`), or move the named literal into a fn or
after the first top-level statement.
