# `#pure`'s `#io` / `#alloc` check is silent for a generic callee called through an instance (`h<i32>(1)`) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend, unit F5, after 0190be81)
and on the lane's base compiler (f793b013), x86_64 (the frontend: every target alike).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-17 by the 6.7.14 frontend lane, unit F5, beside
issues/archived/2026-10-08-pure-check-misses-later-defined-callee.md (that issue's surface is a callee defined LATER; this one
is any order).
**Severity:** Low — a missing warning; nothing miscompiles.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
#io
fn h<T>(x: T): i64 { return 1; }
#alloc
fn a<T>(x: T): i64 { return 1; }
#pure
fn f(): i64 { var r = h<i32>(1) + a(2); return h<i32>(1) + r; }
syscall(60, f());
```

```
warning:<source>:6:37: #pure fn calls #alloc fn 'a'
```

Only `a(2)` warns: an all-i64 call binds the BASE `a`, which PARSE_FN_DEF marked `#alloc`. Both `h<i32>(1)` calls are
silent (expected: `#pure fn calls #io fn 'h<i32>'` at each), and so would `a<i32>(2)` be. The callees are defined
first, so this is not the pass-1 ordering issue above.

## Root cause

The check reads the callee's fn_flags bits 16 / 32 (`_pure_effect_warn` and the tail-call copy,
src/frontend/parse_fn.cyr). A generic call is resolved to its instance (`_gen_call_head` / `_explicit_generic_call`)
before the check, and the instance is a separate fn entry: `_instantiate_generic_fn` re-runs PARSE_FN_DEF with the
pending attributes parked (`_attr_park`, correctly: they belong to the next definition), so the instance never gets
the base's `#io` / `#alloc`. `_gen_inst_record` copies the base's bit 1024 and its arity bits, `_gen_inherit_dep` its
`#deprecated` bit — nothing copies bits 16 / 32. (`#must_use` is unaffected: its statement check looks the BASE
name up before the call is parsed.)

## Fix direction

In `_gen_inst_record` (or beside `_gen_inherit_dep`), OR the base's bits 16 / 32 onto the instance. A gate row with
the repro above: two `h<i32>` warnings, the `a(2)` one, no others.
