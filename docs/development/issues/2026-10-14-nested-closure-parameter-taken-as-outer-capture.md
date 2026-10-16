# A nested closure's parameter named like an enclosing local is taken as a capture by the closure around it — refused without lib/alloc.cyr, or a needless heap env — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit F3: the lane's compiler after
the unit, 2,193,936 B) and on the installed 6.6.0 and 6.7.9 compilers: identical everywhere.
**Placement:** 6.7.13 — repair 3: struct values (closures lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F3, checking "every other declaration form the closure body
can hold" for `issues/archived/2026-10-11-closure-prescan-reads-declared-names-as-captures.md` (whose triage said none exist
beyond `var`, `const`, `for … in` and a destructure; a nested closure literal's parameter list is one more). Outside
that issue's three filed forms, and a separate mechanism: telling a closure literal's `|` from a bitwise or.
**Severity:** Medium — valid source is refused; with lib/alloc.cyr the value is right, but the outer closure carries a
heap env holding a copy of a local it never reads.
**Affects:** cycc 6.6.0 – the 6.7.11 genfe lane tree (measured 6.6.0, 6.7.9 and the lane after F3). Every target.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
fn f(): i64 { var m = 5; var cl = |n| { var g = |m| m + 1; return fncall1(g, n); }; return fncall1(cl, 1); }
fn h(): i64 { var m = 5; var cl = |n| { var g = |m| { return m * 2; }; return fncall1(g, n); }; return fncall1(cl, 3); }
syscall(60, f() * 10 + h());
```

```
error:<source>:2:83: a capturing closure needs include "lib/alloc.cyr" for its heap env
    fn f(): i64 { var m = 5; var cl = |n| { var g = |m| m + 1; return fncall1(g, n); }; return fncall1(cl, 1); }
                                                                                      ^
error:<source>:3:95: a capturing closure needs include "lib/alloc.cyr" for its heap env
    fn h(): i64 { var m = 5; var cl = |n| { var g = |m| { return m * 2; }; return fncall1(g, n); }; return fncall1(cl, 3); }
                                                                                                  ^
```

Expected: builds without lib/alloc.cyr, exits 26 (f 2, h 6) — what it gives with lib/alloc.cyr included and
`alloc_init()` called, and with the enclosing `m` renamed.

## Root cause

The outer closure's capture pre-scan (`_cl_prescan_body`, src/frontend/parse_expr.cyr) walks the nested closure's
tokens as its own: the parameter `m` between the nested literal's `|` `|` is an identifier, so `_cl_prescan_ident`
captures the enclosing `m`, and so does every read of the parameter in the nested body. The nested literal's own
pre-scan (`_cl_prescan_captures`) seeds its parameters into ITS shadow set, but the outer walk never does.

## Proposed fix

In `_cl_prescan_body`, at a closure literal's opening `|` (factor position: after `=`, `(`, `,`, `return`, an operator
or the start of an expression body — not after an operand, where `|` is a bitwise or; and `||`, a thunk with no
parameters), shadow the parameter names for the nested body only: a block body through `_cl_prescan_nested` with the
mark taken before the parameters, an expression body to the `;` / `,` / unmatched closer that ends it (mode 0). Rows
(x86_64, qemu-aarch64, cxvm): both repro closures without lib/alloc.cyr; controls where the nested body reads an
enclosing name that is NOT its parameter (still a capture, through both levels), and `a | b` bitwise or beside a closure.

## Consumer-side workaround

Rename the nested closure's parameter, or include lib/alloc.cyr and call `alloc_init()`.
