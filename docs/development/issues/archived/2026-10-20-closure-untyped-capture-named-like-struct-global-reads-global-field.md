# A closure's untyped capture named like a struct GLOBAL reads the global's field: `var x = 5; |k| x.a + k` with a global `x: Q` returns the global's `x.a` — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FB-1, `7fd3db958` — the user's D96 (2026-10-20): refuse it, as outside the closure. `_cl_cap_fld_any` (src/frontend/parse_decl.cyr), the capture rung PARSE_FIELD_LOAD / PARSE_FIELD_STORE share, dropped its `FINDVAR >= 0` exit, so a capture with no struct type takes the untyped local's arms whatever global shares the name. The filed repro is refused once, `5:54: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)` — the words the same line gets in `main` — on x86_64 and from the aarch64, cx and PE compilers; it compiled and exited 7 (the GLOBAL's `x.a`). The acceptance's store and method on the same capture (`x.a = k; return x.m();`) are refused in the assignment / method wording (5:47 / 5:62); an `i64` capture, an untyped `var x = &q;` capture and a nested closure's capture of a capture likewise. A struct-typed capture still reads its own copy and a closure capturing no `x` the global. Rows: `struct_result_type_refused.sh` UCG0 (the filed repro verbatim) – UCG4 in `uc_rows` (x86_64 + CPX aarch64 / cx / PE), UC12's `--syntax-only` loop, controls UCG5 – UCG7; floor 327; the tree before RED 20; `tests/tcyr/crossos/closure_capture_struct_copy.tcyr` shadowf / shadowg (51 / 51 on x86_64, qemu-aarch64, cxvm, wine). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🔴 **OPEN** — found 2026-10-20 by the 6.7.16 genbind review (beside
issues/archived/2026-10-18-untyped-closure-capture-field-use-says-undefined-variable.md, bite ef63d4610). Measured on the lane
head and on the lane's base 41ca7d41c: identical.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind lane; placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; f16 lane, wave 4, unit FG4) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D96 — Refuse it, as outside the closure (the captured `x` is the untyped local; `x.a` gets "no struct type in scope for 'x'").
**Severity:** Medium. A silent wrong value: the closure reads a different variable than the one it captured.
**Kind:** bug (silent wrong value) — **needs the user's decision** (refusing it stops such programs compiling).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
var x = Q { 7, 8 };
fn main(): i64 { var x = 5; var f = |k| { return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
```

```
$ cat repro.cyr | build/cycc > a && ./a; echo $?
7
```

rc 0, no diagnostic, exit 7 — the GLOBAL `x`'s field `a`. Inside the closure, `x` is the captured local (`var x = 5`):
a plain `x` in the same closure reads 5, and the same `x.a` outside the closure, in `main`'s body, is refused
"no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)". So the closure's
`.field` resolves a name its own scope shadows.

## Why it is open

`_cl_cap_fld_any` (src/frontend/parse_decl.cyr) deliberately keeps today's reading: when a global of the name exists
(`FINDVAR(S, noff) >= 0`) it answers -1 and the field read falls through to the global. The capture-field bite
(ef63d4610) left it so because refusing it — the reading consistent with the local outside the closure — stops such a
program compiling. That is the user's call: (a) refuse it as the untyped local is refused ("no struct type in scope
for 'x'"), or (b) keep the global's field.

## Acceptance

The verbatim repro gives the decided result on x86_64, aarch64, cx and PE (struct_result_type_refused.sh UC rows and
CPX), with a row for a store (`x.a = k`) and a method (`x.m()`) on the same capture.
