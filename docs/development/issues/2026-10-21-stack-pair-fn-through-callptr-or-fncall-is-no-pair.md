# A `: stack`-pair fn called through `callptr(&f, ..)` / `fncallN(&f, ..)` with a known `&f` is no pair: `?` takes the boxed lowering (SIGSEGV) and a one-wide bind keeps the tag in silence — OPEN

**Status:** 🟡 **OPEN** — making the pair askers read a known `&f` through `callptr` / `fncallN` newly refuses `var v =
callptr(&f, 4);` ("bind both"), a change to what compiles beyond the decided answers; the s16b lane stopped on it.
**Placement:** 6.7.17 — the cleanup of the remaining issues (valc lane, wave 1, unit VC2; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D26 — Yes, as f(4).
**Discovered:** the s16b lane, unit SZ7 (met while landing it: the callee, not the chain receiver), and its review's
file_as_issue; staged as this file. Re-measured 2026-10-21 at the 6.7.16 close on the merged compiler (main
`4a3c510f3`; `build/cycc` 2,822,280 B) on x86_64, aarch64 (qemu-aarch64), cx (cxvm) and PE (wine 11.20).
**Severity:** Medium — a crash and a silently wrong value on a valid spelling of a known callee.
**Kind:** decision.

## Summary

A fn returning a `: stack` enum returns two values (tag, payload). Called by name, every pair asker knows it: `?`
propagates, `var v = f(4);` is refused "bind both". Called through `callptr(&f, ..)` or `fncall1(&f, ..)` with the callee
written `&f` — which the vector and struct receives already read (6.7.13's D16, 6.7.14's D26) — no pair asker answers, so
`?` takes the boxed lowering and dereferences the tag, and a one-wide bind keeps the tag.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
enum SR: stack { SOk(v); SErr(e); }
fn f(x): i64 { return SOk(x + 1); }
fn g(): i64 { var v = callptr(&f, 4)?; return SOk(v); }
fn main(): i64 { var t, v = g(); return t * 100 + v; }
syscall(60, main());
```

Exits 139 (SIGSEGV, the boxed `?` dereferences the tag); want 5. Measured at the close: x86_64 139, aarch64 SIGSEGV, cx
"guest address out of range: 0", PE an access violation (exit 5). `fncall1(&f, 4)?` in its place: the same on all four;
the by-name `f(4)?` exits 5 on all four.

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
enum SR: stack { SOk(v); SErr(e); }
fn f(x): i64 { return SOk(x + 1); }
fn main(): i64 { var v = callptr(&f, 4); return v; }
syscall(60, main());
```

Compiles and exits 0 on all four: the tag is kept and payload 5 is lost, where `var v = f(4);` is refused "a `: stack` enum returns two values — bind both: `var tag, val = f();`".

Measured by the lane with its build/cycc at ed17925c9, at its head after the review fixes (bfec3e0d4) and on base
0e2e41805's fixpoint: the same (139 / 0).

## The decision

- (a) The pair askers read a known `&f` through `callptr` / `fncallN`: `callptr(&f, 4)?` and `fncall1(&f, 4)?` propagate
  (the repro exits 5), `var t, v = callptr(&f, 4);` binds both, and `var v = callptr(&f, 4);` (and a one-wide store) is
  refused "bind both", as `var v = f(4);` is — it compiles today.
- (b) Keep: an indirect call is no pair (the `?` crash and the dropped payload stay); the guide says so.

## Root cause

The pair askers (`_pair_callee_at` / `_callee_returns_pair_at`, `?`'s `_tpair`, the lossy-bind refusals, the token passes' `_tok_ret_callee` / `_tok_q_is_pair`; src/frontend/parse.cyr) resolve `name(`, `name<..>(` and method calls; a `callptr(&f, ..)` / `fncallN(&f, ..)` head (token 137 / an `_IS_FNCALL_NAME` call) answers no callee, though the known `&f` is read elsewhere (`_icall_open_at`, `_hl_ic_psid`: 6.7.13's D16, 6.7.14's D26).

## Acceptance

With the user's decision applied: `callptr(&f, 4)?` and `fncall1(&f, 4)?` propagate (the repro exits 5) on every target, a destructure `var t, v = callptr(&f, 4);` binds both, and a one-wide bind / store of a known `&f` pair through `callptr` / `fncallN` is refused "bind both" as `f(4)` is (or, if the user decides otherwise, whatever the decision states). A callee held in a variable stays unknown.
