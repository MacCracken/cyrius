# A fn parameter's type annotation is read as ONE token: `fn f(a: 5)` / `fn f(a: +)` compile, `fn f(p: **i64)` does not — OPEN

**Status:** 🟡 **OPEN** — both halves reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f,
`cycc_merged` 2,053,536 B) with the tree's compiler: repro (a) compiles with rc 0 and exits 42; repro (b) is refused
"expected ')', got identifier 'i64'". The installed 6.7.4 and 6.7.7 compilers give the same two results. A `**i64`
local and a `**i64` struct field compile on the same tip, and a trait's required signature (`_trs_type`, 6.7.8) reads
`**T` and refuses `5` / `+` ("expected identifier") — only the fn definition's parameter list is wrong.
**Placement:** 6.7.10 — repair 1 (roadmap.md § *The releases after 6.7.7*; a parser defect) — placed 2026-10-10 —
never 7.x (the fix is the user's call, asked at that release's open: half (a) stops code compiling, half (b) starts
compiling code refused today).
**Discovered:** 2026-10-10 by the 6.7.8 lanes, reported only — (a) the checked-`dyn` lane's bite D2, (b) the C2 lane's
bite C2-4a (`~/.cache/c6/dyn_handoff.md` § D2, `~/.cache/c6/c2/changelog_handoff.md` § *C2-4a — out of scope*).
**Severity:** Medium — (b) refuses valid source (workaround: an untyped or `*i64` parameter, losing the `**T` step);
(a) accepts non-types silently (no wrong value: the token is skipped and the parameter is a plain word).
**Affects:** cycc 6.7.4 – 6.7.8 measured (both halves); not bisected further.

## Summary

After `name:` the parameter loop of `_PARSE_FN_DEF_IMPL` skips at most ONE `*`, runs the type checks only when the
next token is an identifier (or a tuple's `(`), and then steps over exactly one token whatever it is. So:

- **(a) any single token is accepted as a type** — a number, an operator, a string literal, even `;`
  (`fn g(a: +, b: ;)`). An unknown identifier IS refused by name ("unknown type 'Nonexist' for parameter 'a'"), so the
  gap is every token that is not an identifier.
- **(b) `**T` does not parse** — the second `*` is the "one token", which leaves `i64` where `,` / `)` is expected.
  `_mark_ptr_param` already has a `**T` arm (a step of 8), and `**T` locals and fields have worked since 6.6.17.

## Reproduction

`docs/development/issues/repros/2026-10-10-param-type-annotation-reads-one-token-a-non-type-accepted.cyr`:

```cyrius
include "lib/syscalls.cyr"
fn f(a: 5): i64 { return a + 1; }
fn g(a: +, b: ;): i64 { return a + b; }
fn h(a: "s"): i64 { return a; }
fn main(): i64 { return f(10) + g(20, 10) + h(1); }
var rc = main();
syscall(60, rc);
```

```
expected: each definition refused by name (as `fn f(a: Nonexist)` is)
actual:   rc 0, exit 42
```

`docs/development/issues/repros/2026-10-10-param-type-annotation-reads-one-token-b-double-pointer.cyr`:

```cyrius
include "lib/syscalls.cyr"
fn f(p: **i64): i64 { var q: *i64 = *p; return *q; }
fn main(): i64 {
    var x = 42;
    var px: *i64 = &x;
    var ppx: **i64 = &px;
    return f(ppx);
}
var rc = main();
syscall(60, rc);
```

```
expected: exit 42
actual:   error:<source>:6:11: expected ')', got identifier 'i64'
```

Run each from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`src/frontend/parse_fn.cyr`, `_PARSE_FN_DEF_IMPL`'s parameter loop (merged 6.7.8 tip):

- `:14651` `if (PEEKT(S) == 49)` (the `:`), then `:14653` skips ONE `*` (`_mark_ptr_param`).
- The type is classified and checked (`_classify_param_type`, `_tn_param_check` at `:14719`) only inside
  `if (PEEKT(S) == 2)` — an identifier.
- `:14726` `_param_type_step(S)` (`:9924`) then steps one token unconditionally (a `[` slice is the one exception,
  refused by name since C2-6a).

Pass 1's `_prescan_params_scan` (`:12235`) has the same shape (one `*` skipped, `_param_type_step_q` steps one token),
so it agrees with pass 2 on the wrong reading.

## Proposed fix

Read a parameter's type with a real type reader in both passes — the shape `_trs_type` (`parse_fn.cyr:6749`, the
trait-signature reader) already has: any number of `*`, then `u128`, a tuple, `*fn(..)`, or an identifier with its
`<..>`; anything else refused by name ("expected a type for parameter 'a', got '+'"). Every `*` after the first
records a pointer step of 8, as `_mark_ptr_param`'s `**T` arm does. Rows: each token class in (a) refused once, with
no cascade; `**T` / `***T` parameters on a fn, an impl method and a generic; `*p` / `**p` through one at the four
targets; pass 1 and pass 2 agree (a forward call to a `**T` fn).

Related, in the same branch (C2-4a's other report):
[a pointer-to-vector parameter is taken as a by-value vector](2026-10-10-pointer-to-vector-parameter-is-value-form.md)
— the `*` skipped at `:14653` is dropped for a vector element type. Whoever fixes one should run the other's repro.
