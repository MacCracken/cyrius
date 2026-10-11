# A pointer passed to a by-value `b: Box<T>` parameter runs the generic's i64 base — `b.n` read at the wrong offset — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
2,053,536 B) with the tree's compiler and the cross compilers built from it: the repro exits 128 on x86_64, aarch64
(qemu), cx (cxvm) and PE (wine), where 248 is right. The installed 6.7.4 and 6.7.7 compilers also exit 128. The
merged tree's guide (§ *Generics*, `docs/guides/cyrius-guide.md:4945`) states the behaviour ("A pointer passed to a
by-value `b: Box<T>` binds nothing (the base runs, as before)"), and gate row R18e
(`tests/gates/frontend/struct_arg_type_refused.sh:283`) pins it at 4 — but the base reads a `Box<Pt>` with
`Box<i64>`'s layout, which is a silent wrong value, not a rule.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D3 (reported only, `~/.cache/c6/dyn_handoff.md` § D3
*Out of scope*). The user's fork F1 (2026-10-10) approved the value change for the `*G<T>` carrier only, so D3 left
this by-value half as it was.
**Severity:** High — a silent wrong value on source that compiles clean, on every target.
**Affects:** cycc 6.6.10 – 6.7.8: the installed 6.6.10, 6.6.20, 6.7.0, 6.7.2, 6.7.3, 6.7.4 and 6.7.7 compilers and the
merged 6.7.8 tip all exit 128 (not bisected below 6.6.10).

## Summary

For `fn gx<T>(b: Box<T>)` (a by-value generic struct parameter, address-passed because it is over 8 B), 6.7.8 infers
`T` from a `Box<Pt>` VALUE argument (`gx(b)` calls `gx$Pt`). A POINTER to that value — `gx(&b)`, `gx(bp)` with
`bp: *Box<Pt>` a local or a parameter — passes the struct-argument check (a typed pointer to the right struct is
accepted where the struct is address-passed) but binds no `T`, so the call reaches the i64 base `gx`, whose `b` has
`Box<i64>`'s layout: `b.n` is read at offset 8, which in a `Box<Pt>` is `b.v.y`. Nothing is reported.

## Reproduction

`docs/development/issues/repros/2026-10-10-pointer-into-byvalue-generic-carrier-runs-base.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n; }
fn viaparam(bp: *Box<Pt>): i64 { return gx(bp); }
fn go(): i64 {
    var p: Pt; p.x = 3; p.y = 4;
    var b: Box<Pt> = mk1(p);
    var bp: *Box<Pt> = &b;
    var r2 = gx(&b);       # a `&` of a Box<Pt> local
    var r3 = gx(bp);       # a `*Box<Pt>` local
    var r4 = viaparam(&b); # a `*Box<Pt>` parameter
    return (r2 + r3 + r4) * 10 + 8;
}
var rc = go();
syscall(60, rc);
```

```
expected: exit 248 (each call reads b.n = 8, as gx(b) and gx<Pt>(&b) do)
actual:   exit 128 (each reads 4 = p.y) — x86_64, aarch64 (qemu), cx (cxvm), PE (wine)
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

The struct-carrier inference (6.7.8, D3) reads the argument with `_gsc_arg` (`src/frontend/parse_fn.cyr:10494`). For
a by-value carrier (`ptr == 0`) it returns "binds nothing" for `&name` (`:10497`) and for a pointer-typed local
(`_gsc_name`, `:10561`, `GLPTRP == 1`). With no binding the call infers i64 and resolves to the base; the
struct-argument check then accepts the `*Box<Pt>` as the address-passed `Box` (the typed-pointer acceptance), so the
base runs on the instance's bytes.

## Proposed fix

Infer through the pointer for the by-value carrier too, as the `*G<T>` carrier does since F1: in `_gsc_arg` /
`_gsc_name`, `ptr == 0` also accepts `&name` and a `*G<X>` name, parameter or call, returning what it points at (the
reporter measured it as a one-line change). The by-value parameter is address-passed, so the instance receives the
same address the base does — only the layout changes, to the right one. Flip gate row R18e to an acceptance at 8;
rows for `&b`, a `*Box<Pt>` local, a `*Box<Pt>` parameter and a `*Box<Pt>`-returning call, at the four targets.
If the user keeps "binds nothing" instead, the call must be refused by name (a pointer into a by-value generic
carrier cannot pick its instance), never run the base on the wrong layout.
