# Declaration-zone generic instance call: a refused type argument (`mkg1<*u8>(33)`) or a negated-literal carrier (`mkg1(-3)`) leaves the global untyped — a second error, or a refusal, the after-statement line lacks — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 receives lane (14cc28034, which reads a zone
generic call's type arguments from the tokens, `_gu_gen` / `_gu_tp`); measured on the lane after its review fixes
and on the lane base 4862a462e (x86_64; the frontend, every target): the same. Beside the staged
2026-10-18-zone-untyped-generic-call-instance-argument-shapes-unread.md (an expression, a struct carrier, a bounded
G), which does not name these two.
**Placement:** 6.7.16 — Break 2, repair 6 (zone lane, wave 2, unit Z2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — valid code refused (the negated literal) or one invented error after the real one (the refused
type argument); no miscompile.
**Kind:** bug (the zone and after-the-first-statement typings disagree).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var x = mkg1(-3);
syscall(60, x.v);
```

```
error:<source>:5:16: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)
```

With `var Z0 = 0; Z0 = 1;` before `var x` it builds and exits 253.

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var x = mkg1<*u8>(33);
syscall(60, x.v);
```

```
error:<source>:4:14: a type argument is a type name, got '*'
error:<source>:5:16: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)
```

After a first statement the same line gives the first error alone (6:14).

## Root cause

`_gu_tp` (src/frontend/parse_decl.cyr) reads a carrying argument only as a struct, a LONE integer literal or a lone
global name, so `-3` (unary minus, then the literal) binds nothing and the global stays untyped; pass 2's
`_gen_infer_tp` binds it as i64. For the explicit list, `_targs_resolvable` fails on the refused argument and the
sweep keeps today's answer (untyped), where after the first statement the declaration takes the struct the parse
reached despite the refusal, so its use adds nothing.

## Fix direction

Read a negated integer literal (and, with the staged sibling, any integer expression) as i64 in `_gu_tp`; for a
refused type argument, type the global as the after-statement path does (or mark it with the refused-annotation
stand-down) so its uses add no second error. Rows in struct_receive_inference_checked.sh beside GZ0-GZ10.
