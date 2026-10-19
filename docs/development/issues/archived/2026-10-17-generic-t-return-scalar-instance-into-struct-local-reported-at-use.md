# A `: T` generic that reaches a scalar instance, received into a struct-annotated local, is reported at the first field use as "no struct type in scope" — or not at all — rather than at the declaration — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-25, `0ca743007` (the user's decision D13 (a), 2026-10-18, asked on its own at the open: a handle, as the non-generic call), and GN-25r, `1fd1525fa` (the call-site comment): `_gen_decl_reset` keeps the annotation when the fn the call reaches returns no struct by value. The filed repro 1, refused at `a.z` "no struct type in scope for 'a'", compiles and runs as its `wid(w.v)` twin (139 on x86_64, IR=3 and aarch64, 254 on cx, 5 on PE); repro 2 exits 5 as before, `a` now a handle; `gid(alloc(24))` then `a.z = 4` writes the record (4); `gid(p3)` is still a copy and `gid(q)` of another struct is still refused at the declaration; a refused stub call's one error no longer cascades. This file proposed a refusal at the declaration — D13's option (b); the user chose (a). Beyond D13's text: such a local passed to another struct's parameter is now refused, as for `wid(5)` (it compiled). Rows: the new `generic_t_return_decl.sh` R1 / R2 (the filed repros verbatim), T1 - T5, K1 - K4, TV (the new `tests/tcyr/crossos/generic_t_return_handle.tcyr`, 9 / 9 also on pi, ecb, ach and cass) and MO; `struct_receive_inference_checked.sh` GHT1 - GHT4 moved to the handle; mutation MT1 RED. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 generics lane's review fix step, x86_64, on the lane tree
after the review fix that restored PARSE_VAR's reset for a `: T` return (`_gen_decl_reset`, the review of 3e2031db);
the same output on the slot-open compiler (2600f67f). Pre-existing.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G6; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D13 — (a) A handle, as the non-generic call.
**Discovered:** 2026-10-17, the 6.7.14 generics lane review, beside
issues/archived/2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md.
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
