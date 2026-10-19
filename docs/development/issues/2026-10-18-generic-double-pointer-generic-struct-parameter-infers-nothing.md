# A generic's `pp: **Box<T>` parameter infers no `T` from a `**Box<Pt>` argument: `nb(&q)` runs the `i64` base and reads `Box<Pt>.n` at `Box<i64>`'s offset — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S2), landing
issues/2026-10-17-generic-double-pointer-to-generic-struct-parameter-refused.md. Through 6.7.14 (and on the lane base,
fd2e325af) a `pp: **Box<T>` definition was refused, so this call could not be written; since that fix the definition
compiles and the inferred call is reachable. The filing's own rows (the repro `nb(&p)` with `p: *Box<i64>`, the
explicit `nb<i64>(&p)`, the explicit `nb<Pt>(&q)`) are right; the inferred call with a non-i64 instance is not. Not
that filing's surface (it asks the definition to compile), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Medium — silent: the i64 base runs on a `**Box<Pt>` and reads its fields at `Box<i64>`'s offsets (`b.n`
reads `Pt.y`); no diagnostic. Not a security id (the developer's own source).
**Kind:** bug (generics inference) — the `**G<T>` twin of 6.7.14's D40 A (`pp: **T` binds T from a `**S` argument,
`_gen_infer_ind` / `_pp_tparam`, which takes a parameter declared exactly `**T`) and of 6.7.8's carrier inference
through `p: *Box<T>` (`_gen_infer_sc`, which reads one `*`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn n1<T>(p: *Box<T>): i64 { return p.n; }
fn nb<T>(pp: **Box<T>): i64 { var b: *Box<T> = *pp; return b.n; }
fn np<T>(pp: **T): i64 { return sizeof(T); }
fn main(): i64 {
    var y: Box<Pt>; y.v.x = 1; y.v.y = 2; y.n = 9; var q: *Box<Pt> = &y;
    var pt: Pt; pt.x = 1; var ppt: *Pt = &pt;
    fmt_int(n1(q)); fmt_int(nb(&q)); fmt_int(nb<Pt>(&q)); fmt_int(np(&ppt));
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < nb3.cyr > nb3 && ./nb3
92916       # n1(q) 9 (T = Pt through *Box<T>), nb(&q) 2 (the i64 base: Pt.y), nb<Pt>(&q) 9, np(&ppt) 16 (D40)
```

Want 99916. The same on aarch64 (qemu), cx (cxvm) and PE (wine), the lane tree after S2. On the lane base the
program is refused at nb's definition ("unknown type 'T' as a type argument").

Met beside it (one line, not swept): a NON-generic `fn nc2(pp: **Box<i64>)` called with `&q` (a `**Box<Pt>`), and
`fn nc1(p: *Box<i64>)` called with `q` (a `*Box<Pt>`), compile with no argument-type refusal — the instance mismatch
behind a pointer is not checked at a call.

## Root cause

Inference reads a generic struct carrier through one `*` (`_gen_infer_sc`) and a pointer-to-pointer only when the
parameter is exactly `**T` (`_pp_tparam` / `_pp_is_tp`, src/frontend/parse_types.cyr); `pp: **Box<T>` is neither, so T
is unbound at the call and the base (T -> i64) is called.

## Fix direction

Carry T through `**G<..T..>` as `_gen_infer_sc` carries it through `*G<..T..>`: the argument's pin names the pointee
`*Box<Pt>` (`_ic_pp_arg` / `_pp_sid`), whose instance binds T in its slot. Rows: `nb(&q)` 9, `nb(&p)` 7 unchanged, a
generic method, a `**Box<Pt>` parameter / field / `: **Box<Pt>` call as the argument, the token scans' twin
(issues/2026-10-18-generic-token-scans-miss-double-pointer-and-generic-pointer-call-binding.md).
