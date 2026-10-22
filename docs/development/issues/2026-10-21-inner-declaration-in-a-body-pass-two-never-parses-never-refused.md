# A struct, enum or trait declared inside a body pass 2 never parses — a trait default no impl inherits, an uninstantiated bounded generic — is never refused — OPEN

**Status:** 🟡 **OPEN** — refusing it newly refuses source that compiles today; the f16 lane's fix step stopped on it.
**Placement:** 6.7.17 — the cleanup of the remaining issues (feg lane, wave 1, unit FA3; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D33 — Refuse it wherever it sits.
**Discovered:** the f16 lane's fix step (beside must_fix 1, b2ae86cc5) and its review's file_as_issue; not staged by the
lane (no crash, miscompile or silent wrong value).
**Severity:** Low — an inner declaration the rule refuses everywhere else compiles where its body is never compiled.
**Kind:** decision.

## Summary

The declaration-section rule ("a `struct` declaration belongs to the declaration section at top level, not inside a fn
body", `_decl_inner`) is applied when pass 2 parses the body. A trait default that no impl inherits, and the base of a
bounded generic that is never instantiated, are never parsed by pass 2, so a declaration inside them is never judged.
Since the f16 lane's b2ae86cc5 such a declaration IS reported once its name is used (the end-of-parse flush
`_dl_pw_end`).

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B); the first
also on aarch64, cx and PE: the same.

```cyrius
trait T { fn d(self): i64 { struct Q { y; } return 1; } }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
```

rc 0, no diagnostic, exit 3.

```cyrius
trait Show { fn s(self): i64; }
fn gg<T: Show>(x: T): i64 { struct Q { y; } return 1; }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
```

rc 0, exit 3.

The parsed twins are refused. With `struct P { k; }`, `impl T for P { }` and a call of `p.d()` added to the first (the
default inherited):

```
error:<source>:1:29: a `struct` declaration belongs to the declaration section at top level, not inside a fn body
```

and a plain `fn h(): i64 { struct Q { y; } return 1; }` gives the same line at 1:15.

## The decision

- (a) Refuse it wherever it sits, parsed or not — once, at its keyword, in `_decl_inner`'s words. The two programs above
  stop compiling. (Speculation: the end-of-parse flush `_dl_pw_end`, which already reports a used declaration from such a
  body, is where every declaration in them could be judged.)
- (b) Keep: a declaration in a body that is never compiled is judged only once its name is used (today's behaviour since
  b2ae86cc5).

## Acceptance

With (a): both repros refused once on x86_64, aarch64, cx and PE, a trait default that IS inherited and a plain fn
unchanged (one error each), and a valid trait default / bounded generic with no inner declaration unchanged.
