# A generic call's own result as a struct-carrier argument (`gx(mk1(p))`) is not inferred — refused as a "different struct type" — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
2,053,536 B) with the tree's compiler: the repro is refused "cannot pass 'mk1' to a parameter of a different struct
type in a call to 'gx'"; `gx<Pt>(mk1(p))` and `var b: Box<Pt> = mk1(p); gx(b)` both compile and exit 8. The installed
6.7.4 and 6.7.7 compilers refuse it the same way; 6.6.20 compiled it and exited 4 (the base on the wrong layout —
refused since 6.7.3). The merged tree's guide states the limit (§ *Generics*, `docs/guides/cyrius-guide.md:4947`: "a
generic call's own result (`gx(mk(p))`) [is] not inferred — write `gx<Pt>(..)`"), but valid source is refused and the
message blames a struct mismatch where the gap is inference.
**Placement:** 6.7.10 — repair 1 (roadmap.md § *The releases after 6.7.7*; a call-path defect) — placed 2026-10-10 —
never 7.x (the fix is the user's call, asked at that release's open: refused code starts compiling).
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D3 (reported only, `~/.cache/c6/dyn_handoff.md` § D3
*Out of scope*).
**Severity:** Low — a refusal with a documented workaround (`gx<Pt>(..)`, or bind the result first); the message names
the wrong cause.
**Affects:** cycc 6.7.3 – 6.7.8 as a refusal (measured 6.7.4, 6.7.7, the merged 6.7.8 tip); a silent base call before.

## Summary

6.7.8 infers `T` for `fn gx<T>(b: Box<T>)` from a `Box<Pt>` argument — a name, a struct global, or a call returning
one. When that call is ITSELF generic (`mk1<T>(x: T): Box<T>`, called `mk1(p)`), the argument is typed by the callee
BASE's return — the generic `Box`, which is no instance — so no `T` binds, the call resolves to `gx`'s base, and the
struct-argument check refuses the real `Box<Pt>` against the base's `Box`. The direct carrier has the same limit:
`g(mk1(p))` with `fn g<T>(p: T)` mints `g$Box` and is refused.

## Reproduction

`docs/development/issues/repros/2026-10-10-generic-call-result-as-carrier-argument-refused.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n; }
fn go(): i64 {
    var p: Pt; p.x = 3; p.y = 4;
    return gx(mk1(p));
}
var rc = go();
syscall(60, rc);
```

```
expected: exit 8 (T = Pt, as `gx<Pt>(mk1(p))` and a bound `b: Box<Pt>` give)
actual:   error:<source>:13:15: cannot pass 'mk1' to a parameter of a different struct type in a call to 'gx'
```

The direct carrier: replace `gx` with `fn g<T>(p: T): i64 { return p.n; }` and call `g(mk1(p))` —
"cannot pass 'mk1' to a parameter of a different struct type in a call to 'g$Box'".

## Root cause

`_gen_infer_sc` (`src/frontend/parse_fn.cyr`, the struct-carrier inference) asks `_gsc_arg` (`:10494`) for the
argument's struct; a call argument goes to `_gsc_call` (`:10543`), which returns `GFRS` of `FINDFN(name)` — the generic
callee's BASE return (`Box`), never the instance that call resolves to (`mk1$Pt`, returning `Box<Pt>`). `_sinst_conc`
finds no type argument in a base, so inference falls back to i64. The direct carrier (`_infer_conc_at_cursor`) reads
the same base return.

## Proposed fix

In `_gsc_call` (and the direct carrier's call arm), when the argument's callee is generic, resolve that call as
PARSE_FNCALL will (`_gen_resolve_call` on the inner call's head, `:10694`) and return the INSTANCE's return struct, so
`_sinst_conc` reads `Box<Pt>`'s `Pt`. Rows: `gx(mk1(p))`, `g(mk1(p))`, a nested `gx(mk1(mk1(p)))` (or its refusal by
name), an explicit inner `gx(mk1<Pt>(p))`, a `*Box<T>` carrier with a `*Box<T>`-returning generic, at the four targets;
the guide's sentence updated. Until then, at least name the gap: "cannot infer T for 'gx' from a generic call's result
— write gx<Pt>(..)" instead of the struct-mismatch text.
