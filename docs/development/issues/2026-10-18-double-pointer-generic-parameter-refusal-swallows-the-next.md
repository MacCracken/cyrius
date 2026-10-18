# A `**G<..>` parameter's type-argument refusal swallows the next parameter's error (`fn ap(p: **Box<Zork>, q: Nope)` reports one line) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), writing the `**Box<Zork>` row of
D7's gate. Pre-existing: identical on the lane's compiler before G3 (373ab3d29).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a second error in the same signature is not reported (the build still fails; one fix-and-rebuild
round more).
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn ap(p: **Box<Zork>, q: Nope): i64 { return 0; }
syscall(60, 4);
```

```
$ build/cycc < f2.cyr > /dev/null
error:<source>:3:20: unknown type 'Zork' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
    fn ap(p: **Box<Zork>, q: Nope): i64 { return 0; }
                       ^
```

`q: Nope` is not reported. With one `*` (`fn ap(p: *Box<Zork>, q: Nope)`) both are: `3:19 unknown type 'Zork' as a
type argument` and `3:25: unknown type 'Nope' for parameter 'q'`.

## Root cause (measured by the shapes; the exact writer not instrumented)

The `**` parameter's pointee pin is read while the slot is marked (`_mark_ptr_param` -> `_ek_pin` -> `_pp_psid` ->
`_gen_ann_sid`, src/frontend/parse_fn.cyr / parse_types.cyr / parse_decl.cyr), and `_gen_ann_sid` refuses the type
argument through the error writers that set the panic latch (`ERR_IDENT`), which then swallows the rest of the
signature. The one-star form is read by `_gtype_sid_def` -> `_targ_chk`, which puts the latch back.

## Fix direction

Read the pin's list quietly (or with the latch put back, as `_targ_chk` does) where a `**` parameter is marked, so the
refusal stands at its token and the next parameter is read. Rows: the repro gives two lines; `**Box<Zork>` alone one
line (tests/gates/frontend/generic_type_arg_unknown_refused.sh SR4 keeps it once); `**Box<Pt>` unchanged.
