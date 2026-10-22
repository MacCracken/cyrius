# Generic parameter and type-argument lists are judged by position: a parameter list takes any token, a trait member's bound is unchecked, `union U<T>` is refused only by pass 2, a type parameter's own `<..>` is unread (a parse error as a return), and an explicit call is "undefined function" under `CYRIUS_MONOMORPH=0` — RESOLVED

> ✅ **RESOLVED in v6.7.17** (genb lane, unit GB1, `84a9da229` (D3), `9444bd9a2` (D4), `8cdae35c6` (D5), `3e9a46cff` + `dd2ac95fc` (D6), `4de25d178` (D7), with the met fixes `44010cf5f`, `96415bd9d`, `81b74c14f`, `5ffeb0420`, `193c42f72`, `27f8d216a`, `d4e2f102d`, `ba69fd9d4`, `7e97a092c`, review fixes `9c7f1e370`, `202f58ccd`, `8dbc8ae44`, and the finish pass's D101 `aed26b207` / D102 `cf0d711e8`): a type-parameter list entry that is no name is refused at its token (D3); a trait member's bounds are looked up with the fn's words (D4), an enum's too (D101); a union's `<` is refused by name (D5); a type parameter written with type arguments is refused once at the name in every annotation and at the impl check (D6); an explicit type-argument call under CYRIUS_MONOMORPH=0 is refused by name at its `<` (D7), and a list on a non-generic is refused under the flag as by default (D102). `>>`-closed and nested lists are stepped whole by both passes; `&g<i32>` and an annotated destructure name are one line at the name. CHANGELOG [6.7.17])

**Status:** ✅ **RESOLVED in v6.7.17** (see the banner). Was: 🟡 **OPEN** — each fix changes what compiles beyond the decided answers (6.7.16's D5 / D7 / D88 / D92 judge
type-argument lists on names that declare none, or too many; none of them reaches these positions).
**Placement:** 6.7.17 — the cleanup of the remaining issues (genb lane, wave 1, unit GB1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D3 — Refuse it at the token.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D4 — Refuse with the fn's words.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D5 — Refuse it by name.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D6 — Refuse it once, in every position.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D7 — Refuse it by name.
**Discovered:** the f16 lane — unit FF3 (a parameter list taking any token; `union U<T>`), unit FG2 (a trait member's
unknown bound), unit FG3 (a type parameter given type arguments; an explicit call under `CYRIUS_MONOMORPH=0`).
**Severity:** Low — accepted junk and refused-by-position shapes; nothing computes a wrong value.
**Kind:** decision (one per row; each option names what stops or starts compiling).

## Summary

The same `<..>` grammar is read by different readers depending on where it sits, and they disagree: a declaration's
parameter list accepts a number where a name goes; a trait member's bound is never looked up where a fn's and an impl
method's are; pass 1 reads a union's `<T>` header while pass 2 refuses it; a type parameter's own `<..>` is stepped
unread in a parameter or local and is a parse error with a cascade as a return; and an explicit `g<i32>(..)` reads as an
undefined value when monomorphization is off.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B), x86_64;
rows 1 and 2 also on aarch64 (qemu-aarch64), cx (cxvm) and PE (wine), each compiler built from that tree: the same.

**1. A generic parameter list takes any token:**

```cyrius
struct P<5> { a; }
struct R<T, 5> { a; }
enum E<5> { A }
fn f<5>(): i64 { return 3; }
syscall(60, f());
```

rc 0, no diagnostic, exit 3.

**2. A trait member's bound naming an unknown trait:**

```cyrius
trait T { fn i<U, V: Nope>(self): i64; }
struct P { x; }
fn main(): i64 { return 3; }
syscall(60, main());
```

rc 0, exit 3. The fn's own spelling is refused:

```cyrius
fn i<U, V: Nope>(u: U): i64 { return 1; }
```

```
error:<source>:1:12: unknown trait 'Nope' in the bound on type parameter 'V'
```

**3. A generic union:**

```cyrius
union U<T> { a; }
syscall(60, 3);
```

```
error:<source>:1:8: expected '{', got '<'
```

rc 1. Pass 1 reads the header (PARSE_UNION_DEF's SKIP_GENERICS); pass 2's `_tl_skip_union` skips no `<..>` (befee5bc0
changed the words from "unexpected '<'").

**4. A type parameter given type arguments:**

```cyrius
fn g<U>(u: U<Nope>): i64 { var l: U<i8> = 0; return 0; }
fn main(): i64 { return g(1) + 3; }
syscall(60, main());
```

rc 0, exit 3; a trait member's `fn m<U>(self, u: U<Nope>): U<i64>;` compiles too (rc 0, exit 3). As a return:

```cyrius
fn g<U>(u: U): U<i64> { return u; }
```

```
error:<source>:1:17: expected '{', got '<'
error:<source>:1:23: undefined variable 'i64'
error:<source>:1:21: expected '=', got '>'
```

As a type ARGUMENT (`h<T<u8>>`) it is already refused (6.7.14): "a type parameter takes no type arguments".

**5. An explicit generic call under `CYRIUS_MONOMORPH=0`:**

```cyrius
fn g<T>(x: T): i64 { return 1; }
fn main(): i64 { return g(1) + g<i32>(3); }
syscall(60, main());
```

`CYRIUS_MONOMORPH=0`: rc 1, `error:<source>:2:32: undefined function 'g'`. The default build: rc 0, exit 2. Explicit type
arguments are gated on the monomorph flag since 6.3.10, so the name reads as a value.

## The decision

| # | refuse (stops compiling) | or |
|---|---|---|
| 1 | a parameter list entry that is no name: "a type parameter is a name, got number 5", once, at the token | keep |
| 2 | the member's bound with the fn's words ("unknown trait 'Nope' in the bound on type parameter 'V'") | keep |
| 3 | refuse a generic union by name ("a union takes no type parameters"), in pass 1 too | accept it: pass 2 skips the `<..>` as `_tl_skip_struct` does, and a union instance is laid out as a struct's |
| 4 | "a type parameter takes no type arguments" (6.7.14's words) in every annotation position, the return included, once | keep the parameter / local forms; make the return a single refusal |
| 5 | refuse by name ("explicit type arguments need monomorphization") | accept as the base call with the list stepped, as an annotation steps it under the flag |

## Acceptance

Each repro gives the decided result on x86_64, aarch64, cx and PE (row 5 under the flag), once, with the next statement
still reporting its own error; every valid list (`<T>`, `<T: Show>`, `<T, U>`) and the corpus unchanged.

## Root cause (as the lanes measured it)

- Row 1: not traced (speculation: the parameter-list reader records names and steps any other token).
- Row 2: the bound lookup that refuses "unknown trait" runs at a fn's and an impl method's definition, not at a trait
  member's (FG2; FP9 in the f16 gate pins today's acceptance).
- Row 3: the pass-1 / pass-2 readers of a union header disagree (FF3).
- Row 4: an annotation reader steps `U<..>` after a type-parameter name unread, while the return reader stops at the
  `<` (FG3's 27-position matrix, plain and under the flag; which helper steps it was not traced).
- Row 5: the explicit-call arm is compiled only under monomorphization (6.3.10).
