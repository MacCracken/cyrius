# A generic's `pp: **Box<T>` parameter infers no `T` from a `**Box<Pt>` argument: `nb(&q)` runs the `i64` base and reads `Box<Pt>.n` at `Box<i64>`'s offset — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-15, `00ea63744` — no decision needed (a silent wrong layout). `_gs_param` records a `**G<..T..>` (and deeper) parameter as a struct carrier with GFGM bit 9, and `_gen_infer_sc` reads its argument through its pointers (`_ic_pp_arg`, one pointee down per extra star). The filed repro prints 99916 (it printed 92916: `nb(&q)` ran the i64 base and read `Pt.y` as `n`) on x86_64, IR=3, aarch64, cx and PE; the filing's rows — `nb(&p)` with `p: *Box<i64>` 7, a generic method, a `**Box<Pt>` parameter / field / `: **Box<Pt>` call, `ppp: ***Box<T>` — hold, and a forwarder into a stub `**Box<T>` generic compiles. Rows: `generic_double_pointer_infer.sh` G1 (the filed repro verbatim) – G3, GK1, GK2; `tests/tcyr/crossos/generic_ptr_struct_source.tcyr` pq_* (16 rows, `small_struct_handle_line.sh` R12 on seven legs); mutations MG1 – MG7. Met beside it: a `**G<..>` struct field minted its instance in the middle of the struct's field run (GB-14 `03f7ab003`, and GB-17 `a9832e680` dropping the write-only `_pp_late`); the token-scan twin is issues/archived/2026-10-18-generic-token-scans-miss-double-pointer-and-generic-pointer-call-binding.md (GB-16). Filed beside it: the filing's "met beside it", a non-generic `*Box<i64>` / `**Box<i64>` parameter taking a pointer to another instance unchecked (issues/archived/2026-10-20-pointer-to-other-struct-argument-unchecked.md, the user's D97, wave 4). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S2), landing
issues/archived/2026-10-17-generic-double-pointer-to-generic-struct-parameter-refused.md. Through 6.7.14 (and on the lane base,
fd2e325af) a `pp: **Box<T>` definition was refused, so this call could not be written; since that fix the definition
compiles and the inferred call is reachable. The filing's own rows (the repro `nb(&p)` with `p: *Box<i64>`, the
explicit `nb<i64>(&p)`, the explicit `nb<Pt>(&q)`) are right; the inferred call with a non-i64 instance is not. Not
that filing's surface (it asks the definition to compile), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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
(issues/archived/2026-10-18-generic-token-scans-miss-double-pointer-and-generic-pointer-call-binding.md).
