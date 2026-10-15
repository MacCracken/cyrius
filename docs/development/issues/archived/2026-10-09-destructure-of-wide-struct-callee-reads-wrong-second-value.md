# `var a, b = f();` from a struct callee wider than 16 B reads a wrong second value, silently, on every target — RESOLVED

> ✅ **RESOLVED in v6.7.11** (RET-4, commit 76eaea61: a destructure judges a struct callee by its declared return — over 16 B (a hidden result pointer) is *cannot destructure 'mk' - it returns struct 'Q', which is not in registers - bind it to one name*, three names from a 9-16 B struct are *cannot destructure 'mk' into 3 names - it returns struct 'P', whose 2 words are its return registers - bind 2 names*, and an 8 B struct or a `Str` is one value; two names from a 9-16 B struct (6.7.7's crossing) keep working. The repro (50 / 50 / 55 / 55 on x86_64 / aarch64 / cx / PE) is refused on all four, and so is it at top level in both zones, from a method and from a generic instance. The user's decision D19 (2026-10-13, A). Rows: `struct_pair_multi_value_crossing.sh` D1-D10 (the x86_64, aarch64 and cx compilers); `crossos/struct_pair_multi_value_crossing.tcyr` drops `dt_loc3`. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro exits 50 where 56 is meant (x86; the 6.7.7 aarch64 lane saw the same on every target).
**Placement:** 6.7.11 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*); the fix is a decision asked at its open (refusing a struct callee in the destructure stops code that compiles today — the B4 `a, b = f()` form already refuses it) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.7 aarch64-registers lane (out of scope); filed 2026-10-09.
**Severity:** High — a silent wrong value on valid-looking code
**Affects:** cycc ≤ 6.7.7

## Summary

`_dt_arity_check` accepts a struct-returning callee in a destructure as one that "can carry a second word". A struct
over 16 B returns through a retptr, so the second binding reads whatever the multi-value register held.

## Reproduction

```
struct Q { a; b; c; }
fn mk(x): Q { var q: Q; q.a = x; q.b = x + 1; q.c = x + 2; return q; }
fn main(): i64 { var a, b = mk(5); return a * 10 + b; }
var r = main(); syscall(60, r);
```
Exits 50 (want 56 if the destructure meant the first two fields — or a refusal).

## Proposed fix

Refuse a struct callee in `var a, b = f();` by name, as B4's `a, b = f();` and the tuple capture already do
(`_masg_callee` / `_tup_cap_class`) — the user's call at 6.7.10's open, asked with the stale-receive shapes.
