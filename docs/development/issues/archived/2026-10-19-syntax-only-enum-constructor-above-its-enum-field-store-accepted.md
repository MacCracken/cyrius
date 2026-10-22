# `--syntax-only`: `Some(5).n = 1;` in a fn ABOVE its enum is accepted, where a full compile refuses it — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-2, `b08e5f265` — no decision needed (the full build already refuses the line, and `--syntax-only` refused it with the enum above; the filing's "the user's call" concerned what lint accepts — nothing that compiled changes). `_cf_unres_fn` excludes an enum variant's payload constructor (`_fn_enum_var`), as the build's `_call_nodef` does, the filing's first fix. The filed repro under `cycc --syntax-only` is rc 1, "3:26: cannot assign to a field of a call result: the result is a temporary" (it was rc 0); the full build unchanged ("3:20: ... does not return a struct"). Rows: `call_ptr_field_store.sh` S23 (the repro, `--syntax-only` and full), S23a – S23d (a for step, `+=`, a `: stack` enum's constructor, a nested field), S23e / S23f (controls: the enum above; a unit variant keeps a sibling's path), on the x86_64, aarch64, cx and PE compilers; mutation e1 RED 20. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S4) while auditing which fns can be in
`_fn_nodef`'s state at a call (issues/archived/2026-10-18-field-of-call-registered-undefined-fn-says-does-not-return-a-struct.md).
Pre-existing since 6.7.15's `_cf_unres` arm; measured on the S3 lane head (ff6df9ff5's build/cycc) and on the S4
compiler alike (x86_64; the frontend's, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS1) — never 7.x.
**Severity:** Low — `cyrius lint` (`--syntax-only`) misses an error a full build reports; nothing compiles wrongly.
**Kind:** diagnostics (--syntax-only).

## Repro

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn go(): i64 { Some(5).n = 1; return 0; }
enum Opt { Some(v); Non; }
syscall(60, go());
```

```
$ cycc < r.cyr            # rc 1
error:<source>:3:20: cannot take a field of the result of 'Some': it does not return a struct
$ cycc --syntax-only < r.cyr
                          # rc 0, no error
```

With the enum declared ABOVE `go`, `--syntax-only` refuses it (rc 1, "4:26: cannot assign to a field of a call result:
the result is a temporary" — its own imprecise reason, as for any defined callee returning no struct).

## Root cause

An enum variant's payload constructor is registered by pass 1 (`REGFN`, src/frontend/parse_types.cyr, the enum's
`has_ctor` arm) with no owner (no `SFFI`), and its code is emitted only when pass 2 reaches the enum. A call from a fn
above the enum therefore sees an entry with no code and no owner — `_fn_nodef`'s "no definition this file shows"
(src/frontend/parse_expr.cyr) — and `_call_field`'s silent --syntax-only branch arms `_cf_unres`, so the statement
parses the store as a sibling module's (`_synonly_fld_tail`). The full compile's `_call_nodef` (6.7.16) excludes an enum
variant's name (`_fn_enum_var`) for the same reason; the --syntax-only arm does not.

## Proposed fix

Exclude an enum variant's name from the --syntax-only `_cf_unres` arm too (`_fn_enum_var`), so the statement takes the
defined callee's path; or give the constructor an owner at its pass-1 registration (wider: `_fn_def_slot`, `_vis_check`
and the nested / refused-declaration marks read the owner). It changes what `--syntax-only` accepts: the user's call.
