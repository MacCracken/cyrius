# A duplicate fn whose LAST definition returns no `*T` keeps the first definition's `: *T` records — `gp() + 1` steps sizeof(H) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S4) while adding a per-fn `: *T` record
(`_fn_rpun`, issues/2026-10-18-syntax-only-pointer-return-of-sibling-struct-field-store-false-temporary.md). Pre-existing:
measured on the S3 lane head (ff6df9ff5's build/cycc) and its aarch64 (qemu) and cx (cxvm) compilers — identical.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Medium — a silent miscompile, but only of a program carrying the "duplicate fn" warning (last definition
wins).
**Kind:** bug (codegen: a call's pointer step).

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { a; b; c; }
fn gp(): *H { return 0; }
fn gp(): i64 { return 100; }
fn go(): i64 { return gp() + 1; }
syscall(60, go());
```

```
warning:<source>:4:1: duplicate fn 'gp' (last definition wins; first defined in <source>)
$ ./a.out; echo $?
124
```

Want 101: the last definition wins, so `gp()` is an `i64` and `+ 1` adds 1 — as the single definition `fn gp(): i64`
gives (101). It stepped `1` by sizeof(H) = 24. x86_64, aarch64 (qemu) and cx (cxvm) alike.

## Root cause

A `: *T` return is recorded per fn in side tables written only when a return IS `*T` (`_ret_ptr_record`,
src/frontend/parse_types.cyr): the step word `_fn_rps`, the pointee struct `_fn_rpsid`, the return sentinel GFRS -8,
and (6.7.16) the --syntax-only "T not declared here" byte `_fn_rpun`. A later definition of the same name with any
other return (`: i64`, `: Foo` by value with Foo unresolved, no annotation) never clears them, in pass 1
(`_prescan_ret_type`, parse_fn.cyr) or pass 2 (`_ret_ann_alt`'s caller), so every call — through `_call_ret_ps` /
`_fn_ret_ps`, `_call_ptr_field`, `_hl_fn_psid` — still sees the first definition's `*H`. (A later by-value struct
return of a KNOWN struct is refused — "duplicate fn 'gp' disagrees about its return type" —; a scalar one is only
warned, both returning in rax.)

The same staleness reaches 6.7.16's --syntax-only arm (measured on the S4 compiler): `fn gp(): *Foo { .. }` then `fn gp(): Foo { .. }` (Foo a
sibling's) accepts `gp().n = 5;` under `--syntax-only` (rc 0), where the last definition's by-value result is a
temporary.

## Proposed fix

Clear the per-fn `*T` records (`_fn_rps`, `_fn_rpsid`, `_fn_rpun`) wherever a definition's return is recorded and is
not `*T` — pass 1 and pass 2 — with care for pass 2's order: it re-reads the FIRST definition's `: *T` before the last
one (6.6.20's redefinition flag 2048 says which definition wins), so a call between the two must see the winner's.
