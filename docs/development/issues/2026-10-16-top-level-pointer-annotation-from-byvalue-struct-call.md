# A top-level `var X: *P2 = mkp();` (or `= B.mk();`, `= A + C;`, `= callptr(&mkp);`) after the first statement compiles under the typed-pointer warning and faults at `X.b`; in the declaration zone the free / `&f` call is refused in D24's scalar words and a method compiles silently — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane (unit R2, with D14 applied in a fn) with
compilers built from that tree: x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — the after-the-first-statement shapes compile with only a warning and crash (`*P2`) or hold a
value as an address (`*i64`); the zone's method shape compiles with no diagnostic at all.
**Discovered:** 2026-10-16, the receives lane, while repairing
`issues/archived/2026-10-14-pointer-annotated-local-from-byvalue-struct-call.md` (D14 (A), the user, 2026-10-15). That issue's
filed surface (its repros and its rows) is a declaration INSIDE a fn; D14 was applied there (free, wrapped, generic,
method, operator and known `&f` paths). Top level is outside it, so it was left as found, here.

## Reproduction

After the first top-level statement (PARSE_VAR's top-level arm):

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
var Z = 0;
Z = 1;
var X: *P2 = mkp();
syscall(60, X.b);
```

```
warning:<source>:6:19: assigning non-pointer to typed pointer
    var X: *P2 = mkp();
                      ^
```

Compile rc 0; exits 139 on x86_64 and aarch64, 14 on cx, 5 on PE (X holds rax, the struct's first word 333).
`var X: *P2 = callptr(&mkp);` and `var X: *i64 = B.mk();` (a 16 B method) after the first statement behave the same
(139 / the warning; `*i64` exits 77, 333 held as an address).

In the declaration zone (the same declaration with no statement before it):

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
var X: *P2 = mkp();
syscall(60, X.b);
```

```
error:<source>:4:14: cannot initialise 'X: *P2' from 'mkp', which returns the struct 'P2' - declare 'X: P2' or bind a field
```

— refused on all four, but in D24's scalar remedy ("or bind a field"), not D14's ("and take `&X`"): the zone replays a
pointer annotation with `gps` 0, so 6.7.13's `_scv_gcall_ann` (the structs lane's D24-at-top-level) judges it as a
scalar. `var X: *P2 = fncall0(&mkp);` in the zone is refused the same way. A METHOD in the zone is not refused at all:

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 3; return q; } }
var B = Q { 1, 2 };
var X: *Q = B.mk();
syscall(60, X.b);
```

compiles with no diagnostic and exits 139 / 139 / 14 / 5.

## Root cause

D14's refusals (`_rcv_ptr_ann`, `_scv_icall_ann`'s pointer arm and `_scv_rec_ann`'s, src/frontend/parse_decl.cyr) are
gated to `GINFN(S) == 1`, the issue's surface. At top level after the first statement PARSE_VAR's pointer pscale (> 0)
reaches neither D24's top-level call check (`_scv_gcall_ann` returns 0 for `pscale != 0`) nor a pointer one, so the
call's rax is stored as the pointer under the typed-pointer warning. In the declaration zone `_gvi_ann` gives a
pointer annotation `gps` 0, so the free / `&f` call reaches D24's scalar refusal (with its scalar remedy), and a
method / operator result reaches `_scv_rec_ann`, which leaves a `*T` annotation alone (`TOKTYP(ann) == 8`) to keep top
level as it was.

## Fix

D14 at top level is the user's scope call (its decision text says "every *T and every path", its filed surface is a
fn). Taking it: drop the `GINFN` gates on D14's three arms, give `_scv_gcall_ann` a `pscale > 0` arm, and in the zone
pass the pointer remedy when the annotation's first token is `*` (and let `_scv_rec_ann` take it); over 16 B a top-level
call keeps its one no-frame refusal. Rows: `*P2` / `*i64` / `*u8` from a 16 B free call, wrapped, `&f`, a method and an
operator, in the zone and after the first statement, each refused once in D14's words with no warning; the 8 B control
keeps the word and the warning.
