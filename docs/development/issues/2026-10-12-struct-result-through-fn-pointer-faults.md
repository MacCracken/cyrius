# A struct result over 8 bytes through `fncallN` / `callptr` compiles with no diagnostic and faults: no hidden result pointer is passed, no register pair is received — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc` 2,057,744 B)
and the cross compilers built from it: `var p: P3 = fncall1(&mk3, 5);` for `fn mk3(a): P3` (24 B) compiles with no
diagnostic and exits 139 (SIGSEGV) on x86_64 and aarch64 (qemu), 1 on cx (cxvm: "guest address out of range: 5") and
5 on PE (wine: "page fault on write access to 0x0000000000000005"), where 18 is right. A 16 B and a 32 B struct, and
`callptr(fp, 5)` through a variable, fail the same way on all four. The installed 6.6.10, 6.7.0 and 6.7.9 compilers
give 139 on x86_64. The calling side has no hidden result pointer and no pair receive for an indirect call.
**Placement:** 6.7.11 — repair 1, the call-arguments lane (roadmap.md § *6.7.11*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the `docs/ffi/fncall-abi.md` re-verification, which now says
"`var p: P3 = fncall1(&mk3, 1)` for `fn mk3(a): P3` compiles and faults").
**Severity:** High. A crash on every target from source that compiles clean, and nothing refuses it.
**Affects:** cycc 6.6.10 – the 6.7.10 tree (measured at 6.6.10, 6.7.0 and 6.7.9 on x86_64, and at the tree on all four
targets; not bisected further). All struct results over 8 B through `fncall0`..`fncall8` or `callptr`, whether the
callee is written `&f` or held in a variable.

## Summary

A direct call of a struct-returning fn has the struct-result ABI on both sides. For a struct over 16 B, the caller
passes a hidden result pointer: int arg 0 on x86 / cx / Win64, X8 on aarch64. For a 9–16 B struct, the caller takes
the `rax:rdx` / `x0:x1` / `r0:r4` pair into the struct's two slots. A call through a fn pointer has neither:

- **Over 16 B.** The callee takes its first user argument (or a stale X8) as the result pointer and writes the struct
  through it. Every receive faults, inside the callee: `var p: P3 = fncall1(&mk3, 5);`, an untyped
  `var x = fncall1(&mk3, 5);` (exit 139), and a bare statement.
- **9–16 B.** The callee returns correctly in the pair. A struct-typed receive (`var p: P2 = fncall1(&mk2, 5);`) then
  takes the generic path for a non-struct source: the local becomes a handle holding `rax`, which is the struct's
  first word. The first field read dereferences 5 (PE: "page fault on read access to 0x5"). The documented two-word
  receive `var a, b = fncall1(&mk2, 5);` is right on all four targets.
- **8 B or less.** Right today: `var p: P1 = fncall1(&mk1, 5);` exits 8 on all four targets, because a ≤ 8 B struct
  local takes the word as its value.

⚠ **This interacts with 6.7.10's handle line** (roadmap.md § *6.7.10*, decided 2026-10-12: "a struct local of 8 B or
less initialised from anything that is not a struct value of its type is a HANDLE"). The compiler types an indirect
call's result as an untyped word, not a struct value. So unless B7 counts `fncallN(&f, ..)` / `callptr(&f, ..)` with a
known struct-returning `f` as a struct value, the 8 B row above flips from exit 8 to a dereference of address 8.
The 8 B row below is the regression row for that.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
struct P3 { a; b; c; }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
fn main() {
    var p: P3 = fncall1(&mk3, 5);
    return p.a + p.b + p.c;
}
var r = main();
syscall(60, r);
```

```sh
cd /home/macro/Repos/cyrius
cat /tmp/s24.cyr | build/cycc > /tmp/s24 && chmod +x /tmp/s24 && /tmp/s24; echo $?   # 139, want 18
cat src/main_aarch64.cyr | build/cycc > /tmp/cc_a64 && chmod +x /tmp/cc_a64
cat /tmp/s24.cyr | /tmp/cc_a64 > /tmp/s24a && chmod +x /tmp/s24a && qemu-aarch64 /tmp/s24a; echo $?   # 139
```

Every row below compiles with no diagnostic. "want" is the right exit, measured on x86_64 / aarch64 (qemu) / cx (cxvm) /
PE (wine):

| shape | want | x86_64 | aarch64 | cx | PE |
|---|---|---|---|---|---|
| `var p: P3 = fncall1(&mk3, 5);` (24 B) | 18 | 139 | 139 | 1 (guest address 5) | 5 (write fault at 0x5) |
| `var fp = &mk3; var p: P3 = callptr(fp, 5);` | 18 | 139 | 139 | 1 | 5 |
| `var p: P4 = fncall1(&mk4, 5);` (32 B) | 26 | 139 | 139 | 1 | 5 |
| `var x = fncall1(&mk3, 5); return 3;` (24 B, untyped) | 3 | 139 | 139 | 1 | 5 |
| `var p: P2 = fncall1(&mk2, 5);` (16 B) | 11 | 139 | 139 | 1 | 5 (read fault at 0x5) |
| `var a, b = fncall1(&mk2, 5);` (16 B, documented) | 11 | 11 | 11 | 11 | 11 |
| `var p: P1 = fncall1(&mk1, 5);` (8 B, `mk1` returns `a + 3`) | 8 | 8 | 8 | 8 | 8 |

## Root cause

- **The call.** `_PINDIRECT_CALL_IN` (`src/frontend/parse_expr.cyr:821`) marshals exactly the written arguments. When
  the callee is written `&f`, it knows `f` (`_icall_callee`, `:804`). It uses that only for the defaults check
  (`_pd_icall_short`, `:866`) and to type an f64 result (`_icall_result`, `:812`), never for `f`'s struct return
  (`GFRS(S, cfi) > 0`). So nothing reserves a result temporary or pushes its address as int arg 0 (`_sc_pre`,
  `src/frontend/parse_fn.cyr:4549`), nothing loads X8 (`_sc_x8`, `:4567`), and nothing receives the pair
  (`_sc_post`, `:4574`). Through a variable (`callptr(fp, ..)`) the callee is unknown, `cfi` is -1, and nothing is
  known at all.
- **The receive.** PARSE_VAR's struct receive (`asv_try` / `asv_pair`, `src/frontend/parse_decl.cyr:6600` / `:6604`,
  taken at `:6614` / `:6692`) recognises only `IDENT (` naming a fn with a declared struct return. `fncall1` names
  `lib/fnptr.cyr`'s untyped fn and `callptr` is a builtin token. So `var p: P3 = fncall1(..)` falls to the generic
  declaration: a struct over 8 B initialised from a word binds it as a pointer (guide § *Returning a struct by
  value*: "A source that is not a struct or vector still binds as a pointer").

The trait-object call already does this whole job for an indirect call: `_dyn_call` / `_dyn_call_in`
(`src/frontend/parse_types.cyr:2033` / `:2065`) carry "a struct result of any size" through `_sc_pre_m` / `_sc_x8` /
`_sc_post` with the member's prototype as the fn. A `fncallN` / `callptr` with a known callee has the same
information in `cfi`.

## Proposed fix

1. **A known callee (`fncallN(&f, ..)` / `callptr(&f, ..)`, `f` returning a struct over 8 B) carries the result**
   through the struct-call hooks, as `_dyn_call_in` does. Reserve the temp and push its address as int arg 0 before
   the user arguments (x86 / cx / Win64), load X8 on aarch64, receive the 9–16 B pair, and type the call's result as
   the struct. PARSE_VAR's receive, the assignment `p = fncall1(&mk3, 5)`, an argument, a field store and
   `return fncall1(&mk3, 5);` then see a struct value, as they do for a direct call. Small separate fns: `_PINDIRECT_CALL_IN`
   and PARSE_VAR sit near cybs's per-fn reference ceiling, so the seed-derive gate (seed → cybs → cycc) is part of
   every bite.
2. **An unknown callee (a fn pointer in a variable, a closure) cannot be checked at the call.** What a struct-typed
   receive of it means is the user's call: one-line question, *should `var p: P3 = callptr(fp, ..)` be refused by
   name, or should the annotation be taken as the callee's return type (carrying the result pointer / the pair, as in
   1)?* The same question covers `&f` taken of a struct-returning fn and stored for a later call, which is the only
   way such a value reaches an unknown-callee site. Refusing makes code stop compiling that compiles today (and faults).
3. **Rows**, mutation-proven (each fix reverted → RED), on x86_64, aarch64 (qemu, then pi), cx (cxvm) and PE (wine,
   then cass): the table above, with 16 / 24 / 32 B through `fncall1(&f, ..)` and `callptr(&f, ..)`; the assignment,
   argument, field and `return` forms; a `callptr(fp, ..)` row for whatever the user picks in 2; the documented
   `var a, b = fncall1(&mk2, 5)`, which must stay 11. Keep the **8 B row**, `var p: P1 = fncall1(&mk1, 5)` → 8, GREEN
   across 6.7.10's handle line. `docs/ffi/fncall-abi.md`'s "compiles and faults" sentence moves to the CHANGELOG.

## Consumer-side workaround

Call a struct-returning fn directly (`var p: P3 = mk3(5);`). When the target must be indirect: for 9–16 B, receive
the two words (`var a, b = fncall1(&mk2, 5);`, right on all four targets); for any size, give the target an
out-pointer and have it store the fields (`fn mk3p(a, out: *P3): i64`, then `var p: P3; var ig = fncall2(&mk3p, 5, &p);`),
also right on all four targets.
