# An `impl T { fn m(self) .. }` written ABOVE `struct T` leaves the untyped `self` with no struct: `self.b` is refused "no struct type in scope for 'self'" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S1), probing the forward-call signature
re-read (issues/2026-10-17-forward-call-struct-parameter-of-struct-declared-below-fn.md) with a method. Not that
item's: the refusal does not depend on where the CALL is (the impl below `main` is refused too), and the unit's fix
does not change it (identical on 8b4d44602's build/cycc and on the lane tree after S1).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a false refusal of a valid program (the declaration section's order between a struct and an
impl of it), one error by name, no miscompile; `self: *T` written out, or the struct declared first, compiles.
**Kind:** bug.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 { var t: R2 = R2 { 5, 7 }; return t.get(); }
impl R2 { fn get(self): i64 { return self.b; } }
struct R2 { a; b; }
syscall(60, main());
```

```
error:<source>:3:44: no struct type in scope for 'self'; a '.field' access needs its struct declaration (missing include?)
    impl R2 { fn get(self): i64 { return self.b; } }
                                               ^
```

Want 7. The same on x86_64, the aarch64, cx and PE compilers built from the lane tree. With `main` after both
declarations (`impl R2 { .. }`, `struct R2 { .. }`, then `fn main`) the same error at 2:44. Controls, each 7: the
struct declared before the impl; `fn get(self: *R2)` written out, with the impl above the struct.

## Root cause

An untyped `self` in an impl is typed `*T` from a pass-1 record: `_iself_prescan` (src/frontend/parse_fn.cyr), called
by `_prescan_params_scan` while `_prescan_impl` walks the impl, asks `_iself_sid_for`, which asks
`FINDSTRUCT(_impl_tnoff)`. A struct declared below the impl is not registered yet, so nothing is recorded (`SFISELF`),
and pass 2 types `self` only from that record (`_iself_def_sid`: `GFISELF`), so the definition's `self` is a plain
word and `self.b` has no struct. The 6.7.15 signature re-read (`_psig_reread`, src/frontend/parse_fn_def.cyr) re-reads
only a signature whose own tokens name a struct registered after it; the impl's type is in the `impl R2 {` header,
not in `fn get(self)`.

## Fix direction

Read the impl's type once every struct is registered: e.g. `_psig_late` also asks the noted impl type
(`_impl_tnoff`, kept in the `_psig_note` record) when parameter 0 is an untyped `self`, so `_iself_prescan` records
`SFISELF` and the address bit at the re-read. Rows: the repro; `main` below both; a trait impl's method; a generic
impl; the struct-first control.
