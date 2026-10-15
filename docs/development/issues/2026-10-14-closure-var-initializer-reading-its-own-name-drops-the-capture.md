# In a closure, `var a = a + n;` (and a destructure's FIRST name, `var a, b = f(a);`) reads a global `a`, or is refused "undefined variable", where the enclosing local `a` is meant — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F3: the lane's compiler
before the unit, 2,189,840 B, and after it, 2,193,936 B) and on the installed 6.6.0 and 6.7.9 compilers: identical
everywhere.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F3, while fixing
`issues/archived/2026-10-11-closure-prescan-reads-declared-names-as-captures.md` (a declared name read as a capture). This is the
opposite direction: a real read DROPPED from the capture set. Outside that issue's filed surface (it names the
`for … in` variable, a local `const` and a destructure's second and later names).
**Severity:** High — a silent wrong value when a global has the name; a refusal of valid source otherwise.
**Affects:** cycc 6.6.0 – the 6.7.11 genfe lane tree (measured 6.6.0, 6.7.9, the lane before and after F3). Every
target (the shared frontend).

## Reproduction

```cyrius
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn two(x): (i64, i64) { return (x, x + 1); }
var a = 100;
fn f(): i64 { alloc_init(); var a = 5; var cl = |n| { var a = a + n; return a; }; return fncall1(cl, 1); }
fn g(): i64 { alloc_init(); var a = 5; var cl = |n| { var a, b = two(a + n); return a * 10 + b; }; return fncall1(cl, 1); }
syscall(60, f());      # 101; expected 6
# syscall(60, g());    # 88 (1112: two(101)); expected 67 (two(6))
```

Without the global `var a = 100;` and lib/alloc.cyr:

```cyrius
include "lib/fnptr.cyr"
fn f(): i64 { var a = 5; var cl = |n| { var a = a + n; return a; }; return fncall1(cl, 1); }
syscall(60, f());
```

```
error:<source>:2:51: undefined variable 'a' (missing include or enum?)
    fn f(): i64 { var a = 5; var cl = |n| { var a = a + n; return a; }; return fncall1(cl, 1); }
                                                      ^
```

Expected: builds, exits 6 — what the same initializer gives in a plain fn's nested block:

```cyrius
fn f(): i64 { var a = 5; { var a = a + 1; return a; } }                                        # 6
fn g(): i64 { var a = 5; { var a, b = two(a + 1); return a * 10 + b; } }                       # 67
```

## Root cause

The parser binds a `var` AFTER its initializer: PARSE_VAR parses the right-hand side, then registers the slot (the
single form and the destructure alike), so `var a = a + n;` reads the enclosing `a`. The closure's capture pre-scan
(`_cl_prescan_body`, src/frontend/parse_expr.cyr) shadows the name from where it stands (`prev_var`): the `a` of the
initializer is never captured, so the parser's read of it finds no closure local, no capture, and falls to FINDVAR — a
global `a` (silently) or "undefined variable". The 6.7.11 fix for the destructure's second and third names
(`_cl_prescan_mvar`) shadows them after the right-hand side; the first name and the single `var` still shadow from the
name.

## Proposed fix

Shadow a `var`'s name after its initializer, as the parser binds it: in `_cl_prescan_body`, on `var IDENT`, walk the
declaration's tail (the annotation and the `=` right-hand side, mode 4 of `_cl_walk_stop`: to its depth-0 `;`) before
`_cl_shadow_add`; in `_cl_prescan_mvar`, add the first name with the others. Check `stack var` and a `var` in a classic
`for (` header the same way. Rows (x86_64, qemu-aarch64, cxvm): both repros with a same-named global (want 6 / 67) and
without lib/alloc.cyr (refused as a capture); a control where the initializer does not read the name (`var a = n;`,
compiles without lib/alloc.cyr); a read of the name after the declaration (the closure's own `a`).

## Consumer-side workaround

Rename the closure's local (`var a2 = a + n;`), or read the enclosing value into a differently named local first.
