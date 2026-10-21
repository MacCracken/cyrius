# A closure's untyped capture named like a struct GLOBAL reads the global's field: `var x = 5; |k| x.a + k` with a global `x: Q` returns the global's `x.a` — OPEN

**Status:** 🔴 **OPEN** — found 2026-10-20 by the 6.7.16 genbind review (beside
issues/2026-10-18-untyped-closure-capture-field-use-says-undefined-variable.md, bite ef63d4610). Measured on the lane
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
