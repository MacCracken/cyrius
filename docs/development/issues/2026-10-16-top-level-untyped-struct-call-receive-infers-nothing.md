# A top-level untyped `var x = mk1();` (wrapped or not) infers no struct — `x.a` is "no struct type in scope for 'x'" — and at 9-16 B it silently binds the first word, where `var x: P2 = mk2();` is refused "needs storage in a fn's frame" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05) and the lane base (f59668ad's `build/cycc`): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives review, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — the 9-16 B row is silent: an untyped top-level receive of a struct result holds its first word
with no diagnostic, where the annotated declaration is refused. The 8 B row is a refusal of valid code (Low).
**Discovered:** 2026-10-16, the receives lane's review of the 92b35796 bite (issues/
2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md). That issue's filed surface is an untyped
receive IN A FN; top level is outside it.

## Reproduction

8 B, in the declaration zone (`var x = (mk1(30));` and a declaration after a first statement, `syscall(39);`, behave
the same):

```cyrius
include "lib/syscalls.cyr"
struct P1 { a; }
fn mk1(a): P1 { var r: P1 = P1 { a + 3 }; return r; }
var x = mk1(30);
syscall(60, x.a);
```

```
error:<source>:5:16: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)
```

The same lines in a fn (`var x = mk1(30); var y = (mk1(30)); return x.a + y.a - 33;`) exit 33 (the lane; the base
refused the wrapped one). `var x: P1 = mk1(30);` at top level builds and exits 33.

16 B:

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mk2(a): P2 { var r: P2 = P2 { a + 3, a }; return r; }
var x = mk2(30);
syscall(60, x);
```

```
rc 0, no diagnostic; exit 33 on all four (x holds the first word)
```

`syscall(60, x.a);` in its place gives the "no struct type in scope" refusal. The annotated `var x: P2 = mk2(30);` is
refused: "'mk2' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn".
At 24 B the untyped form gets that no-frame refusal and then the "no struct type in scope" one (two errors).

## Root cause

PARSE_VAR's untyped struct receive (`_rcv_*`, src/frontend/parse_decl.cyr; `_sc_var_receive`, parse_fn.cyr) runs in a
fn only. At top level an untyped initialiser is a scalar global: the call's rax is stored, and nothing records the
callee's struct type for the name (an 8 B struct is one word, so the value is right but `x.a` has no struct). Over 8 B
the annotated path reaches `_refuse_toplevel_struct_call` and the untyped one does not.

## The question

At top level, should an untyped `var x = mk1();` bind the 8 B struct (as the annotated form and the in-fn form do),
and an untyped receive over 8 B be refused as the annotated one is ("needs storage in a fn's frame")? Both follow
decision 12 (a whole struct result binds the struct at every size); the 16 B row's refusal makes compiling code stop
compiling, so it is the user's call. Rows: 8 B / 16 B / 24 B, wrapped and not, zone and after a first statement.
