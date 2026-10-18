# A top-level untyped `var x = mk1();` (wrapped or not) infers no struct — `x.a` is "no struct type in scope for 'x'" — and at 9-16 B it silently binds the first word, where `var x: P2 = mk2();` is refused "needs storage in a fn's frame" — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-14, `ed1e01b1` — the user's decisions D29 (a) and D30 (a), 2026-10-16: an untyped top-level declaration of one whole free call (wrapped or not, in the declaration zone or after the first statement) binds the struct. The 8 B repro exits 33 (it was "no struct type in scope for 'x'"); `x + 1` dispatches `P1_add`, refused when there is none. The 16 B repro (exit 33, silent) is refused once, "'mk2' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn"; at 24 B the call's own refusal is the one error. On x86_64, aarch64, cx and PE (`_gu_late` after the first statement; `_gu_reg` / `_gu_sweep` at the end of pass 1 and `_gu_refuse` at the zone's replay). Rows: `frontend/struct_receive_inference_checked.sh` TU0 / TU0b (the repros verbatim, `docs/development/issues/repros/2026-10-16-top-level-untyped-struct-call-receive-infers-nothing{,-16b}.cyr`), TU1 – TU13 in both zones, TUK1 / TUK2, on four legs; `crossos/struct_receive_paren_call.tcyr` group "6.7.14 (D29)" (also on pi and cass); mutations N43 – N47 RED. Not closed here (filed, 6.7.15): a top-level method / operator / known `&f` result keeps the word (`2026-10-17-top-level-untyped-method-operator-or-known-callee-struct-result-keeps-word.md`), and a zone `var x = mkg1(33);` whose generic callee returns a generic struct instance binds nothing (`2026-10-17-zone-untyped-generic-struct-instance-call-binds-nothing.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05) and the lane base (f59668ad's `build/cycc`): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D29 — (a); D30 — (a).
**Severity:** Medium — the 9-16 B row is silent: an untyped top-level receive of a struct result holds its first word
with no diagnostic, where the annotated declaration is refused. The 8 B row is a refusal of valid code (Low).
**Discovered:** 2026-10-16, the receives lane's review of the 92b35796 bite (issues/
archived/2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md). That issue's filed surface is an untyped
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
