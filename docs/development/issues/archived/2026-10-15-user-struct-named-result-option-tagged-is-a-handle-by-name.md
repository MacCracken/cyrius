# A user struct named `Result`, `Option` or `Tagged` is a heap handle by NAME: its inline value into its by-value parameter passes the first field as the handle (SIGSEGV on every target) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-5, `6dbe998ff`: `_classify_param_type` answers the stdlib's handle classes for `Result` / `Option` / `Tagged` only while no program struct takes the name (`_cpt_byname`, FINDSTRUCT first, as the return classifier always did), and its readers follow. No decision needed. The filed repro and its `Option` / `Tagged` spellings give 7 on x86_64, IR=3, aarch64, cx and PE (were 139 / 139 / 139 / 252 / 5). A method with an untyped `self` in the program's `impl Result` compiles (it was "no struct type in scope for 'self'"). The stdlib's `: stack` enums build byte-identical, and `Str` stays a handle by name. Rows: new `struct_named_like_stdlib_handle.sh` (R the filed repro verbatim on five legs; C1 / C2 byte-identical builds) and `crossos/struct_named_like_stdlib_handle.tcyr` (19) / `_8b.tcyr` (10), green on ecb, ach, cass and pi; mutation RED 37. Also fixed by the same classifier, with no row: a heap handle of such a struct assigned from an inline value (`h = t`, 139 -> a copy) and returned (`return h;`, 0 -> 7). A handle passed by value is now a copy (the callee's writes no longer reach the caller's object), as for every struct (6.6.16). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 structs lane (unit S4), probing the other by-name types the
inline-`Str` issue never probed (issues/archived/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md: "`Result` /
`Option` / `Tagged` (the other by-name types) were not probed"). Measured on the lane tree after D7 (1) and on its
base (44ab2052), x86_64 / aarch64 (qemu) / cx (cxvm) / PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean and faults (or reads through the first field) on every target; the names are
plausible user struct names.
**Kind:** language — the stdlib's `Result` / `Option` (lib/result.cyr, lib/tagged.cyr) are `: stack` ENUMS, not
structs, so `Result { .. }` there is no struct literal; but `_classify_param_type` / `_classify_return_type` /
`_agc_plain_big` / `_psid_plain` classify a parameter, return or assignment by the type's NAME, so a program's own
`struct Result { .. }` (and `Option`, `Tagged`) is a handle by name everywhere `Str` is.

## Repro

```cyrius
include "lib/syscalls.cyr"
struct Result { a; b; }
fn g(x: Result): i64 { return x.b; }
fn main() { var t: Result = Result { 5, 7 }; return g(t); }
var r = main();
syscall(SYS_EXIT, r);
```

x86_64 139 (SIGSEGV), aarch64 139, cx 252 (a guest fault), PE 5 — want 7 (the same with `Option` or `Tagged` for
`Result`; the same before and after D7 (1)). `struct R2 { a; b; }` in its place exits 7 on all four (the parameter is
address-passed: `_param_wants_struct_ptr`).

## Root cause

`_classify_param_type` (src/frontend/parse_fn.cyr) answers 3 / 4 / 5 for the NAMES `Result` / `Option` / `Tagged`
whatever they declare, so `_param_wants_struct_ptr` leaves the 16-byte parameter value-passed (one word) and the
caller pushes `t`'s first slot (5); the callee reads `x.b` through it. The same by-name exclusion sits in
`_agc_plain_big` (assignment), `_local_is_sptr_param`, `_ret_local_inline` and the return classifier
(`_classify_return_type`'s -16 / -17 / -18).

## Proposed fix

Classify by name only when the name is the stdlib's (an enum, or no declaration): a program's own `struct Result`
(FINDSTRUCT > 0 for an enum-less name) takes the plain-struct rules. Or refuse the three names as struct names, by
name. (D7 (1) answered the inline `Str` only; whether `Str` itself stays a handle by name is settled.)
