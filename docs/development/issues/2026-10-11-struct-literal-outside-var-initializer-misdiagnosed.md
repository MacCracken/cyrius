# A struct literal anywhere but a `var` initializer (`G = P { 5 };`, `f(P { 5, 6 })`, `(P { .. })`) is refused as "undefined variable 'P'" — OPEN

**Status:** 🟡 **OPEN** — reported by the 6.7.9 critical lane (bite 1) as a refusal it did not check against the
docs. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B): an assignment to a
global, an assignment to a local, a call argument, a parenthesised initializer, a top-level assignment and a named
literal as another literal's element (`W { P { 2 } }`) are each refused with `undefined variable 'P' (missing include or enum?)` at the literal; `return P { 5, 6 };` from a `: P` fn
is refused by name ("… takes a local of that struct or a call returning it — got `P`"). The installed 6.6.0, 6.7.0
and 6.7.8 compilers refuse the assignment the same way. The guide shows struct literals only as `var` initializers and
never says other positions are unsupported.
**Placement:** 6.7.13 — repair 3, the diagnostics lane (roadmap.md § *The releases after 6.7.8*; part 2, the literal
as an expression, is the user's call, asked at that release's open) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 1 (the zero-size struct store), writing `G = P { 5 };`.
**Severity:** Low — a loud refusal with a message that names the wrong thing (`P` is a declared struct, not an
undefined variable); no wrong value.
**Affects:** cycc 6.6.0 – 6.7.9 (measured), every target (frontend).

## Summary

`P { … }` is parsed as a struct literal only as a declaration's whole initializer (`var x = P { … };`,
`var x: P = P { … };`, a global's). Anywhere an EXPRESSION is parsed, `P` is looked up as a variable, misses, and the
parser reports `undefined variable 'P' (missing include or enum?)` — and the `{` after it cascades into two to five
more errors at the same site. The `return` position alone has a by-name refusal. (A nested struct field takes a
positional run of its leaves or a struct VALUE — guide § Structs — not a named literal.)

## Reproduction

```cyrius
struct P { a; }
var G: P = P { 1 };
fn run(): i64 { G = P { 5 }; return 0; }
var r = run();
syscall(60, G.a);
# error:<source>:3:23: undefined variable 'P' (missing include or enum?)
```

The same message (and its cascade, three to six errors in all) for `l = P { 5 };` on a local, `f(P { 5, 6 })`,
`var q: P = (P { 5, 6 });`, a top-level `G = P { 5, 6 };` and `var w: W = W { P { 2 } };`.

## Proposed fix

Two parts:

1. **The diagnostic (this lane, no decision):** when an expression position meets `IDENT {` with `IDENT` a declared
   struct, refuse by name — "a struct literal is an initializer: declare it (`var t: P = P { .. };`) and assign /
   pass the local" — once, with the `{ … }` consumed so nothing cascades. The return arm keeps its message.
2. **The decision (the user's, at the open):** whether a struct literal becomes an expression in some of those
   positions — an assignment's right-hand side (`G = P { .. };`, a whole-struct copy as `G = l` is) and a by-value
   argument are the natural ones. A "yes" is a language addition with its own rows (every position, every struct size
   class, x86_64 / aarch64 / cx / PE).

Rows for part 1: the six refused positions above, each one error naming the struct; a `var` initializer and a
positional nested literal (`Rect { 0, 0, 10, 5 }`, `Rect { a, 10, 5 }`) unchanged.

## Consumer-side workaround

Declare a local from the literal and assign or pass the local (`var t: P = P { 5 }; G = t;`).
