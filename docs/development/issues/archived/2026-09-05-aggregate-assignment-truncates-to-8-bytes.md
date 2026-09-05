> ### ✅ RESOLVED v6.5.57 — and the reverted first attempt was right about the copy and wrong about the cause
>
> Three fixes, one defect surface:
> 1. **The assignment path got the multi-word copy** the declaration path has had since the
>    struct-byval work (`_try_aggregate_copy_assign`, `parse.cyr`).
> 2. **`_try_struct_copy_init` learned vector descriptors.** A `pscale` in the descriptor band is
>    not a struct sid, so `STRUCTSZ` returned nothing usable and `var B: f32v4 = src;` fell
>    through to a scalar init — the declaration form was broken for vectors too, which this
>    file's first draft did not know.
> 3. ⭐ **A LATENT REGISTER-ALLOCATOR BUG, which is what defeated the first attempt.** An
>    aggregate's fields are reached as `lea rcx,[rbp+base]` then `mov [rcx+off]`, so ONLY the base
>    slot ever appears as an `[rbp+disp32]` reference. The picker's safety scan reads rbp disps,
>    so an aggregate's second and later words were invisible to it and it could promote one to a
>    register while the field write that really sets it went through `rcx`. Latent for as long as
>    the picker has existed, because those words were referenced at most once — below the
>    `count > 1` candidacy threshold. The assignment copy supplies the second reference and trips
>    it, which is exactly why the first attempt made `b.y` read 11 instead of 22 and why
>    `CYRIUS_REGALLOC_PICKER_CAP=0` made the same source correct. Aggregates are now excluded
>    from the picker outright — their fields are addressed, not held.
>
> ⚠ **The "slot-layout question" this file gave as the reason for filing rather than fixing was
> wrong.** It was a register-allocator safety-scan gap, findable in one measurement
> (`CYRIUS_REGALLOC_PICKER_CAP=0`) that was not taken before filing.
>
> **Gate:** `tests/gates/codegen/aggregate_copy_all_words.sh` — 9 axes, mutation-proven three
> ways (assignment copy no-op → 5 axes red; picker exclusion removed → 4 red; vector descriptors
> removed from the declaration copy → 1 red). ⚠ Its probe exits with a FAILURE COUNT, not a
> bitmask: the first cut summed nine axes to 511 and the shell reported 255, the same 8-bit
> truncation that once scored 256 real failures as a PASS.

# Aggregate assignment `dst = src;` copies only the first 8 bytes — silent wrong values

**Status:** ✅ **RESOLVED v6.5.57** — reproduced on live code at v6.5.56. Pre-existing, not a recent regression.
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
