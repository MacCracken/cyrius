# Aggregate assignment `dst = src;` copies only the first 8 bytes — silent wrong values

**Status:** 🔴 **OPEN** — reproduced on live code at v6.5.56. Pre-existing, not a recent regression.
**Severity:** P1 — silent wrong values, exit 0, no diagnostic, and structs are used everywhere.
**Found:** v6.5.56 slot-entry premise-check, while chasing a report that `f32v4` assignment
truncates. It does — but the report was too narrow, and that is the important part.

## The defect

For any aggregate wider than one 8-byte slot, the **assignment** form copies only the first word:

```cyrius
struct P2 { x; y; }
var a: P2;  a.x = 11;  a.y = 22;
var b: P2 = a;      # DECLARATION form — correct, copies both words
var c: P2;  c.x = 0;  c.y = 0;
c = a;              # ASSIGNMENT form — copies x only; c.y stays 0
```

Measured at 6.5.56: `b.x`✓ `b.y`✓ `c.x`✓ **`c.y`✗**. Same for vectors — a `f32v4` local-to-local
assignment keeps lane 0 and drops lanes 2–3.

## ⭐ It is NOT a SIMD bug, and that is why it stayed hidden

It was reported as `f32v4` assignment truncating. That is true, but a plain **two-field struct
truncates identically**, and structs are far more widely used than SIMD. Fixing only the vector
arm would have left the common case live. Any fix must cover both, and the gate must assert the
struct case first.

## Root cause, located

The declaration form has had a correct multi-slot copy since the struct-byval work —
`_try_struct_copy_init` (`src/frontend/parse_decl.cyr:1394`), which reserves `nslots` and emits a
word-by-word `EFLLOAD`/`EFLSTORE` pair per word. Its own header comment describes exactly this
failure for the case it fixed: *"b got a SINGLE slot holding a's first 8 bytes (truncated)"*.

The **assignment** path never got the equivalent. It falls through to the scalar store at
`src/frontend/parse.cyr:1573-1581`, where `lt < 0` (a struct sid or a vector descriptor) takes the
`else { EFLSTORE(S, idx); }` arm — one 8-byte word.

## ⛔ Why the obvious fix does not work — MEASURED, do not repeat it

A `_try_aggregate_copy_assign` helper hooked into the plain-`=` branch (before `PCMPE`, mirroring
`_try_struct_copy_init`: match `= IDENT ;`, require both sides be locals of the same aggregate
type, take the width from `STRUCTSZ` or from `_vec_desc`/`GVEC_NSLOTS`, emit the word-by-word
copy) was implemented and **it works in isolation** — `a`/`c` alone gives all four fields correct,
and the `f32v4` assignment case goes from lane-0-only to correct.

**But it CORRUPTS AN EARLIER LOCAL when a third aggregate is present.** With
`a` → `var b: P2 = a;` → `var c: P2;` → `c = a;`, `b.y` becomes 11 instead of 22. The regression is
caused by the new path: removing just the `c = a` line makes both compilers correct, so it is not
a pre-existing interaction. Disassembly shows the *declaration* copy then emitting
`movq -0x38(%rbp),%rax` / `movq %rax,-0x48(%rbp)` / `movq %rax,-0x40(%rbp)` — storing word 0 into
**both** destination slots, i.e. its second load is gone. `CYRIUS_RELOADELIM=0` does not change
it, so the reload-elimination peephole is not the cause.

The change was reverted rather than shipped, because an incomplete fix here is worse than none.

## What the fix needs

The unexplained part is why adding a statement-level path that consumes its own tokens perturbs an
**earlier** declaration's emitted copy. The likely area is slot/temp accounting: the scalar
assignment path allocates hidden temps (the same class of slot that `?` and `match` consume —
`parse_expr.cyr:2994-2996`, `parse.cyr:683-685`), and bypassing it shifts what later code assumes.
Settling that is a **slot-layout question**, which is why this is filed rather than packed into
v6.5.56 — not because it is "a different subsystem".

## Acceptance

- `c = a` copies every word, for a struct AND for each vector width.
- The three-local shape above (`a`, `var b: T = a`, `var c: T`, `c = a`) leaves `b` intact —
  this is the case the first attempt broke, so it is the gate's load-bearing axis.
- A control that a *scalar* assignment still emits one store (so the fix cannot pass by making
  every assignment a multi-word copy).
- Corpus coverage is currently **ZERO** for aggregate assignment — no `.tcyr` assigns a struct or
  a vector local to another. That absence is why this shipped.

## Repro

```sh
printf 'include "lib/syscalls.cyr"\nstruct P2 { x; y; }\nfn main(): i64 {\n    var a: P2;\n    a.x = 11; a.y = 22;\n    var c: P2;\n    c.x = 0; c.y = 0;\n    c = a;\n    syscall(60, c.y, 0, 0, 0, 0);\n    return 0;\n}\n' > /tmp/agg.cyr
build/cycc < /tmp/agg.cyr > /tmp/agg.bin && chmod +x /tmp/agg.bin && /tmp/agg.bin; echo "exit=$?  # want 22, gives 0"
```
