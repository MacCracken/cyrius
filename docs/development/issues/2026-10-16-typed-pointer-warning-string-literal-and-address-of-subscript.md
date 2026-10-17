# "assigning non-pointer to typed pointer" fires on a string literal into a `*u8` (`var s: *u8 = "abc";`, `t = "xyz";`) and cascades beside the `&a[i]` refusal; D18 (a) carried both to the declaration zone and to a scalar `*T` local's assignment — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05, `build/cycc` its fixpoint) and the lane base (f59668ad's `build/cycc`): x86_64, aarch64 (qemu), cx (cxvm),
PE (wine), identically on all four.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D53 (item 6 of the 6.7.13 list) — Never warn for a string literal.
**Severity:** Medium — a false warning on valid code that compiles and runs right (`*u8` from a string literal is
the C-string idiom), which D18 (a) widened from one site to three; plus a second (warning) diagnostic beside a refusal.
Nothing miscompiles. The census at the D18 bite (lib / cbt / programs / .tcyr) found no hit.
**Discovered:** 2026-10-16, the receives lane's review of the D18 bite (fd3d5e61, issues/
archived/2026-10-12-typed-pointer-non-pointer-warning-gaps.md). That issue's filed surface is which `*T` SITES warn (decided
D18 (a): every site, the literal 0 exempt); which VALUES count as non-pointers is outside it.

## Reproduction

A string literal (compiles, rc 0, runs right; the warnings are false):

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 {
    var s: *u8 = "abc";
    var t: *u8 = 0;
    t = "xyz";
    return load8(s + 1) + load8(t);
}
var ec = main();
syscall(60, ec);
```

```
lane:  warning:<source>:3:23: assigning non-pointer to typed pointer      (var s: *u8 = "abc";)
       warning:<source>:5:14: assigning non-pointer to typed pointer      (t = "xyz";  — new with D18)
       exit 218 on x86_64 / aarch64 / cx / PE
base:  warning:<source>:3:23: assigning non-pointer to typed pointer
       warning:<source>:4:19: assigning non-pointer to typed pointer      (var t: *u8 = 0; — D18 fixed this one)
       exit 218
```

The declaration zone (new with D18 — the base is silent):

```cyrius
include "lib/syscalls.cyr"
var p: *u8 = "abc";
syscall(60, load8(p + 1));
```

```
lane:  warning:<source>:2:19: assigning non-pointer to typed pointer      exit 98 on all four
base:  (no diagnostic)                                                    exit 98
```

An address-of subscript: `&a[i]` is itself refused ("&a[i] is not supported"), and the warning is reported beside the
refusal. The lane adds the second diagnostic at a scalar `*T` local's assignment:

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: i64[4];
    var p: *i64 = &a;
    p = &a[1];
    *p = 7;
    return a[1];
}
var ec = main();
syscall(60, ec);
```

```
lane:  error:<source>:5:11: &a[i] is not supported - write &a + i * sizeof(T) (or p + i)
       warning:<source>:5:14: assigning non-pointer to typed pointer
base:  error:<source>:5:11: &a[i] is not supported - write &a + i * sizeof(T) (or p + i)
```

`p = &a[i];` and `p = &b[1];` (b: `*i64`) behave the same. The base already gave the warning beside the refusal at
`var q: *i64 = &a[0];` in a fn, `G = &a[1];` into a `*i64` global (in a fn and at top level, `P = &A[1];`) and
`pp = &ps[1];` into a `*Pt` local.

## Root cause

Each `*T` site warns when the right-hand side leaves the pointer scale 0: `aps == 0` in `_PARSE_STMT_IMPL`'s local and
global assignment arms (src/frontend/parse.cyr, `_tp_warn`), `expr_ps == 0` in PARSE_VAR's in-fn declaration
(src/frontend/parse_decl.cyr), `GPSC(S) != 0` in `_tp_warn_gv` (the zone's replay). A string literal's value is an
address but sets no pointer scale, so it reads as a non-pointer. The refused `&a[i]` leaves the scale 0 after its
error, so the site warns too.

## Fix

Treat a string literal (token type of a string constant, alone up to the terminator) as a pointer for a `*u8` / `*i8`
destination at every site (`_tp_null`'s neighbour: one predicate the four callers ask), and skip the warning when the
line already holds an error (the D24 zone arm already does this with `_scv_err` / `_tn_seen_at`). Rows: the three
string-literal sites quiet on four legs; each `&a[i]` site refused once; the D18 rows of typed_pointer_warn_sign.sh
unchanged.
