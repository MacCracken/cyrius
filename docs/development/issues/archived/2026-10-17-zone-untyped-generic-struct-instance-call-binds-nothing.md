# A declaration-zone untyped `var x = mkg1(33);` whose generic callee returns a generic struct instance (`: G1<T>`) binds nothing — `x.v` is "no struct type in scope for 'x'" (16 B: the D30 refusal and then that error) — where the same line after the first statement binds the instance (D29 (a)) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (RC-14, `14cc28034`, with RC-14r, `988c6d78f` — no new decision: 6.7.14's D29 (a) / D30 (a) (the user, 2026-10-16) cover a generic's instance at top level, and the line after the first statement already bound it. `_gu_zsid` / `_gu_gen` (src/frontend/parse_decl.cyr) read the type arguments from the tokens — an explicit list, else each type parameter's carrying argument — and mint the instance through `_instantiate_generic_struct` (deduplicated by name, so pass 2 reaches the same struct). The filed repro, refused "no struct type in scope for 'x'" (5:16), exits 33 on x86_64, aarch64, cx and PE; `mkg1<i64>(33)` the same; a 16 B `G2<T>` is the one 6.7.14 D30 refusal (it added the second error); `mkg1<i32>(30)` agrees with a `G1<i32>` parameter. x is that struct, so the zone's `x + 1` dispatches `G1_add` and is refused when there is none (it exited 34). Rows: `frontend/struct_receive_inference_checked.sh` GZ0 (the repro verbatim) – GZ9 and GZ10zone / GZ10after (RC-14r) on four legs; `crossos/struct_receive_paren_call.tcyr` TG1 / TG2 / tg_read; mutants RED. Not closed here (filed, 6.7.16): an expression argument, a struct carrier or a bounded G leaves the zone global untyped (`2026-10-18-zone-untyped-generic-call-instance-argument-shapes-unread.md`); `mkg1<*u8>(33)` / `mkg1(-3)` in the zone (`2026-10-18-zone-generic-instance-refused-type-argument-or-negated-literal-unbound.md`); a nested instance's field of field is judged a stub (`2026-10-18-generic-nested-instance-field-of-field-judged-a-stub.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives at ed1e01b1, unit R4), x86_64
(`build/cycc` the lane's fixpoint); a shared-frontend shape, every target the same.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a refusal of valid code (8 B), and a second error after the one refusal (16 B); nothing miscompiles.
The same declaration after the first statement, or annotated (`var x: G1<i64> = mkg1(33);`), works.
**Discovered:** 2026-10-17, the receives lane (unit R4), repairing
`issues/archived/2026-10-16-top-level-untyped-struct-call-receive-infers-nothing.md` (D29 / D30), whose filed repros are a plain
fn returning a plain struct.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var x = mkg1(33);
syscall(60, x.v);
```

```
error:<source>:5:16: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)
```

`var x = mkg1<i64>(33);` the same. With `var Z = 0; Z = 1;` before the declaration it builds and exits 33. A 16 B
`struct G2<T> { v: T; w: T; }` from `fn mkg2<T>(v: T): G2<T>` in the zone gives the D30 refusal ("'mkg2' returns a
struct by value, and a struct result needs storage in a fn's frame") and then the same "no struct type in scope"
error at `x.v` (after a first statement: the refusal alone).

## Root cause

A zone global is typed at the end of pass 1 (`_gu_sweep`, src/frontend/parse_decl.cyr), before pass 2 compiles the fn
bodies that read it, from the tokens (`_gz_call_rs`). A generic callee returning `: G1<T>` names the generic base; its
instance (`G1$i64`) is made by `_gen_resolve_call` in pass 2 (`_gz_gb` set, the sweep skips it). After the first
statement PARSE_VAR's global arm resolves the instance (`_gu_sid`).

## Proposed fix

Either resolve the instance at the sweep (if instantiating a generic fn at the end of pass 1 is safe — it was not
attempted), or type the global at the zone replay as well and make every pass-2 reader before the replay agree;
rows: 8 / 16 B, inferred and explicit type arguments, a fn body reading `x.v`, zone and after.
