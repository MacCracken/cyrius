# An `impl T { fn m(self) .. }` written ABOVE `struct T` leaves the untyped `self` with no struct: `self.b` is refused "no struct type in scope for 'self'" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-13, `eafa5a40d`, and GS-13r `7f3d2260d` — no decision needed for the fix (the guide's untyped-`self` and `T_m(x)` / `x.m()` rules carry no order caveat); the arithmetic refusal is the user's decision D6, 2026-10-19 at the 6.7.16 open: refuse it, as with the struct declared first. The end of pass 1 re-reads a method whose impl type names a struct registered after it (`_psig_late_impl`), so its untyped `self` is recorded as a `*T` with the struct-pointer ABI mark. The filed program, verbatim, exits 7 on x86_64, aarch64, cx and PE (it was `3:44: no struct type in scope for 'self'`); `R2_get(t)` with `load64(self)` and the impl above exits 5 (it faulted: 139 on x86_64 and aarch64, "guest address out of range" on cxvm); `load64(self + 8)` there is refused once, "arithmetic on an untyped `self` is refused" (it compiled, exit 7). Rows: `impl_self_typed.sh` F0 (the filed program verbatim) – F5 and the controls; `tests/tcyr/crossos/impl_self_typed.tcyr` (21 / 21 on x86_64, qemu-aarch64, cxvm and wine), run on cx by `cx_crossos_rows_run.sh` R27 (GS-13r). Mutants: the lane's previous compiler → RED 7; GS-13's src reverted → R27 RED on both legs. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S1), probing the forward-call signature
re-read (issues/archived/2026-10-17-forward-call-struct-parameter-of-struct-declared-below-fn.md) with a method. Not that
item's: the refusal does not depend on where the CALL is (the impl below `main` is refused too), and the unit's fix
does not change it (identical on 8b4d44602's build/cycc and on the lane tree after S1).
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D6 — Refuse it, as with the struct declared first.
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
