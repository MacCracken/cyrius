# A `*fn( .. )` type outside a parameter: a local, a global or a field is refused as a reserved-keyword identifier with a cascade, and a trait member's multi-value element compiles where a fn's is refused — RESOLVED

> ✅ **RESOLVED in v6.7.17** (genc lane, unit GB2, `343f710c7` (D8), `313adedb4` (D9), met `660ec3eaf`, `79a311056`, `37f70d4bb`; the finish pass's D93 `2c0dade0e`, D94 `9314c587e`, D105 `380fd7b65` and review fixes `720b4aee8`, `a490451bb`, `942781650`, `1a6539afe`): a `*fn( .. )` declares a local, a global, a struct / union field and a slice element as the one pointer word a parameter's does (D8), and `&f` / a closure literal are pointers to the typed-pointer check; a trait member's multi-value element `*fn( .. )` is refused with a fn's words, once, at its `*` (D9). The finish pass: a slice element takes any number of `*` (D93) and is any type valid elsewhere (D105), and `sizeof(*T)` is 8 (D94). Rows: fn_pointer_holders.sh, tests/tcyr fn_pointer_typed_holders.tcyr, traits_checked.sh. CHANGELOG [6.7.17])

**Status:** ✅ **RESOLVED in v6.7.17** (see the banner). Was: 🟡 **OPEN** — where a fn-pointer type may stand beyond a parameter is undecided; each option changes what
compiles.
**Placement:** 6.7.17 — the cleanup of the remaining issues (genc lane, wave 1, unit GB2; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D8 — Accept it as a one-word pointer.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D9 — Refuse it with the fn's words.
**Discovered:** the f16 lane — unit FG2 (the trait member's multi-value element; f16's FP7 / FP9 rows), unit FG3 (a
local, a global, a field).
**Severity:** Low — refused or accepted by position; nothing computes a wrong value.
**Kind:** decision.

## Summary

The guide documents `*fn( .. )` as a parameter type only. Elsewhere the readers disagree: as a local's, a global's or a
field's type it is refused as if `fn` were the declared name, with a cascade of follow-on errors; as a fn's return or a
fn's multi-value element it is refused by name ("a fn-pointer type `*fn( .. )` cannot be a fn return type", 6.7.16's
D9 for a trait member's plain return); as a TRAIT MEMBER's multi-value element it compiles.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B), x86_64;
the trait-member row also on aarch64, cx and PE: the same.

```cyrius
fn main(): i64 { var c: *fn(i64): i64 = 0; return 3; }
syscall(60, main());
```

```
error:<source>:1:26: expected identifier, got reserved keyword 'fn' (cannot be used as an identifier; rename the variable/field/fn)
error:<source>:1:32: undefined variable 'i64' (missing include or enum?)
warning:<source>:1:33: assigning non-pointer to typed pointer
```

```cyrius
var G: *fn(i64): i64 = 0;
syscall(60, 3);
```

```
error:<source>:1:9: expected identifier, got reserved keyword 'fn' (cannot be used as an identifier; rename the variable/field/fn)
error:<source>:1:11: expected '=', got '('
error:<source>:1:15: undefined variable 'i64' (missing include or enum?)
warning:<source>:1:15: assigning non-pointer to typed pointer
```

```cyrius
struct H { cb: *fn(i64): i64; k; }
syscall(60, 3);
```

```
error:<source>:1:17: expected identifier, got reserved keyword 'fn' (cannot be used as an identifier; rename the variable/field/fn)
```

A trait member's multi-value element compiles, rc 0, exit 3:

```cyrius
struct P { x; }
trait T { fn e(self): (*fn(i64): i64, i64); }
fn main(): i64 { return 3; }
syscall(60, main());
```

while the fn's is refused:

```cyrius
fn h(): (*fn(i64): i64, i64) { return (0, 1); }
```

```
error:<source>:1:10: a fn-pointer type `*fn( .. )` cannot be a fn return type
  note: a return type is a struct, i8/i16/i32/i64, f64, bool, a vector type, Result, Option, Tagged, cstring, a pointer *T, a multi-value (T1, T2[, T3]), dyn Trait or a generic fn's first or second type parameter; return an i64 (no annotation) for the others
```

## The decision

- **A local, a global, a field** — (a) accept `*fn( .. )` there as the 8-byte pointer a parameter's is (newly compiles;
  `callptr` / fncallN read it as they read a parameter's); or (b) refuse it by name, once, with no cascade ("a
  fn-pointer type is a parameter type only - hold it in an untyped variable").
- **A multi-value element** — (a) refuse the trait member's with the fn's (D9's) words (it stops compiling); or (b)
  accept the element on both, the fn's and the member's (newly compiles).

## Acceptance

Each repro gives the decided result on x86_64, aarch64, cx and PE, once; a `*fn( .. )` parameter (a fn's, a method's, a
trait member's, D91's bare `*fn`) unchanged.

## Root cause (as the lanes measured it)

The declaration readers take the token after `*` as a type name and meet the keyword `fn` (FG3); the trait member's
multi-value return reader does not apply the fn's return-set check to its elements (FG2; the f16 gate's FP9 pins the
member's acceptance as today's behaviour).
