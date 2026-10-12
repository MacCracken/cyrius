# A pointer passed to a by-value `b: Box<T>` parameter runs the generic's i64 base — `b.n` read at the wrong offset — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 11, l679-crit; CHANGELOG [6.7.9]) A pointer passed to a by-value `b: G<T>` carrier binds T from what it points at, as the `*G<T>` carrier's has since 6.7.8 (the user's decision 2(b)): `_gsc_arg` (parse_fn.cyr) reads a value and a pointer alike for both carriers — `&name`, a `*G<X>` local / parameter / global, a `*G<X>`-returning call and a `*G<X>` field chain — and the pair scans' token readers (`_tok_gen_sc_sid` / `_tok_sc_ann`, parse.cyr) follow it too. The repro exits 248 (was 128) on x86 / IR=1 / IR=3 / DCE=1 / aarch64 (qemu) / cx / PE (wine); gate rows R18e (flipped, 8) / R18g / R18h (the repro verbatim) in `frontend/struct_arg_type_refused.sh` and G10 (21 rows, every pointer form) in `tests/tcyr/crossos/generic_struct_inference.tcyr` on the same legs, mutation-proven. A 1073-source differential compiles byte-identically, diagnostics included, except the repro and the values file.

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above and *Resolution* below (reproduced on the 6.7.9 lane tip @
b462800d before the fix: the repro exits 128). As filed: 🟡 OPEN — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
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

## Resolution (6.7.9, the critical lane's bite 11)

- **Direction (a)**, the user's decision 2(b): bind T from the pointee and run the `Box<Pt>` instance (128 → 248). The
  by-value carrier (over 8 B) is address-passed, so the instance receives the very address the base did; only the
  layout changes, to the right one. The explicit `gx<Pt>(..)` is the control for every form, and it already accepted
  each one (a typed pointer converts into an address-passed struct parameter, 6.7.3).
- **Both carriers now read the argument alike**: `_gsc_arg` lost its `ptr` parameter (and `_gsc_call`, `_gsc_name`
  theirs; `_gs_carrier` no longer records bit 9). Every pointer form the `*G<T>` carrier took binds the by-value one:
  `&b` of an inline local, a by-value parameter or a struct global, a `*Box<Pt>` local, parameter or global, a
  `*Box<Pt>`-returning call, a `*Box<Pt>` field through a chain (`h.bp`, `hp.bp`, `self.bp`, `G.bp`, two hops), by
  name, in a body that is not inlined; and through it a stub base (`T` used as a struct — was refused, now the
  instance), a `: T` return (`unbox(bp)` — was refused), `Box<i32>` (the scalar instance) and `Pr<T, U>` (both from
  one pointer).
- **The pair scans** (`_tok_gen_sc_sid`, `_tok_sc_ann`, parse.cyr) asked bit 9 before following `&name` or a `*G<..>`
  annotation; they follow both for either carrier, so a `?` caller above its wrapper `var p = unbox(bp); return
  p.hbx(d);` flags the pair (with the parser alone fixed it died, rc 139).
- **Unchanged**: an untyped pointer (`var u = &b; gx(u)`) binds nothing, as for `*Box<T>` (no static struct); `&bp` of
  a pointer is a `**` and binds nothing; an inline `Box<Pt>` field (`gx(h.b)`) keeps the base's refusal.
- **Met in passing, filed** (not this bite's: it is the user's call): a typed pointer passed to a by-value struct
  parameter of 8 B or less passes the address as the struct's value (`bs4(tp)` with `fn bs4(b: S4)`, `tp: *S4`) —
  issues/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md.
