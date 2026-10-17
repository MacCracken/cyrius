# A `: T` generic that reaches a scalar instance, received into a struct-annotated local, is reported at the first field use as "no struct type in scope" — or not at all — rather than at the declaration — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 generics lane's review fix step, x86_64, on the lane tree
after the review fix that restored PARSE_VAR's reset for a `: T` return (`_gen_decl_reset`, the review of 3e2031db);
the same output on the slot-open compiler (2600f67f). Pre-existing.
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-17, the 6.7.14 generics lane review, beside
issues/2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md.
**Severity:** Low — the field form is refused (rc 1) but at the wrong place with the wrong reason; the no-field form
compiles with the annotation silently dropped (the local holds the scalar).

## Reproduction

```cyrius
struct P3 { x; y; z; }
struct W { n; v: P3; }
fn gid<T>(x: T): T { return x; }
fn f(): i64 { var w: W; var a: P3 = gid(w.v); return a.z; }
syscall(60, f());
```

```
error:<source>:4:57: no struct type in scope for 'a'; a '.field' access needs its struct declaration (missing include?)
    fn f(): i64 { var w: W; var a: P3 = gid(w.v); return a.z; }
                                                            ^
```

`gid(w.v)` infers T = i64 (the guide's whole-argument rule: a field chain is not a whole struct argument), so the call
reaches `gid`'s i64 base. The refusal names neither the call nor the instance, and points at `a.z`, not at the
declaration. The same for `gid(5)`, `gid<i32>(5)` and `gid(h)` with `h: f64` (`4:45`-style carets at the field use).
Without a field use the program compiles and the annotation is dropped silently:

```cyrius
struct P3 { x; y; z; }
fn gid<T>(x: T): T { return x; }
fn f(): i64 { var a: P3 = gid(5); return a; }
syscall(60, f());
```

compiles (rc 0) and exits 5 — `a` is an untyped word holding 5, not a `P3`.

Right (by analogy with 6.6.11's `_sc_decl_mismatch`, which refuses the `: Box<T>` analogue at the declaration naming
the instance — `var r: Box<Pt> = mk(p.x);` is "fn return struct-id differs from declared var type" at the call): a
refusal at the declaration naming the call and the scalar instance it reached, e.g. "'gid' returns i64 here (its
type argument is i64), not struct 'P3'".

## Root cause

PARSE_VAR's B-explicit reset (`pscale = 0`, src/frontend/parse_decl.cyr, `_gen_decl_reset`) drops the annotation of
`var a: P3 = g(..)` for a generic callee and re-derives the receive from the callee; for a `: T` generic the re-derive
(`_tok_gen_ret_sid`) binds a struct only when T's argument is a whole struct, and otherwise leaves the local untyped
with no diagnostic. `_gen_decl_check` refuses a mismatch only for a callee with a by-value struct return
(GFRS > 0); a `: T` return records none, so a scalar instance reaching a struct annotation is never checked at the
declaration.

**Fix direction:** in `_gen_decl_check`, for a generic whose return is its own `: T` (`_gen_ret_tp >= 0`), resolve T at
the call (`_tok_gen_ret_sid`, or the explicit argument) and refuse at the declaration when it binds no struct of the
annotation's type, naming the call and the instance — the `_sc_decl_mismatch` shape.
