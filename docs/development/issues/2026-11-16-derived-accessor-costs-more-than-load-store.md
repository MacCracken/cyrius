# A `#derive(accessors)` accessor is inlined but costs more than the load64 / store64 it stands for — open (performance)

**Status:** 🟡 **OPEN** — measured on cyrius 6.7.18 (x86_64 Linux ELF), 2026-11-16.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-16, during svara 3.8.4 (its formant bank laid out one record per slot).
**Severity:** Low (performance). Every value is right; only the instruction count is not what the source suggests.
**Affects:** cyrius 6.5.71 (when getters began to auto-inline) through 6.7.18.

## Summary

A derived accessor is inlined, but it is not free. Each call retires more instructions than the `load64` / `store64`
it is shorthand for. On top of that, each keeps one branch, which a plain load or store does not have:
- **a setter** `T_set_f(p, v)`: 6 more instructions than `store64(p + OFF, v)`;
- **a getter** `T_f(p)`: 2 more than `load64(p + OFF)`.

The extra branch is a jump, not a call: a call and its return would add two branches.

svara's formant bank runs eight biquads per sample, and its slot record went through derived accessors. That cost
130 instructions a sample: 60 from 10 setter calls and 70 from 35 getter calls. Written as `load64` / `store64` at
`const` offsets, the bank retires 1,210 M instructions per million samples instead of 1,340 M.

The guidance that derived accessors "are inlined, so reading fields into locals buys nothing" is true for calls. It
does not cover this per-access overhead, and a hot loop pays that on every field it touches.

## Reproduction

`repros/2026-11-16-derived-accessor-costs-more-than-load-store.sh` builds four loops of 1,000,000 iterations, each
touching two fields of a `#derive(accessors)` struct. It counts retired user instructions and branches with
`perf_event_open`, from python3, so no `perf` binary is needed. It **exits 1 while either accessor loop retires more
than its twin**.

Cyrius 6.7.18, x86_64, 2026-11-16: exit 1.

```text
Rec_set_a + Rec_set_b     49.00 instructions, 4.00 branches per iteration
store64 x2                37.00 instructions, 2.00 branches per iteration
Rec_a + Rec_b             41.00 instructions, 4.00 branches per iteration
load64 x2                 37.00 instructions, 2.00 branches per iteration
```

A `const` offset (`const REC_A = 0;`) retires exactly what a literal one does, so the twins are not paying for a
named offset.

## Root cause (speculation)

The preprocessor registers both accessors for auto-inlining (`src/frontend/lex/pp/accessor.cyr:308` and `:320`, read
at `src/frontend/parse/fn/def.cyr:3676`), so they expand through the same inline replay `#inline` uses. The comments
at `src/frontend/parse/expr/intrin.cyr:65-90` describe that replay:
- it binds each parameter to a frame local;
- it turns each `return` into a jump to the end of the inlined block.

That would explain both costs:
- **the one branch**: the getter's single `return`, as a jump;
- **the setter's extra four instructions**: its second parameter's slot, and the `return 0;` its generated body ends
  with (`accessor.cyr:265`: `{ storeW(p + OFF, v); return 0; }`).

## Proposed fix

Any of these, cheapest first:
1. **No jump for a final `return`.** When the inlined body's only `return` is its last statement, it needs no jump to
   the end.
2. **No slot for a simple argument.** When an argument is a local or a constant, substitute it for the parameter
   instead of copying it into a new frame slot.
3. **No `return 0;` in a setter.** Emit the setter without it, or drop its value where the call is a statement.

The gate would be the repro exiting 0: each accessor loop retiring what its `load64` / `store64` twin does.

## Consumer-side workaround

Where a loop runs per sample, write the record as `const` offsets and `load64` / `store64`, with no derived
struct. One statement of the layout keeps the offsets and the accesses from disagreeing. svara 3.8.4 does this for
its formant bank (`src/formant.cyr`, `SV_FSLOT_*`), and keeps derived accessors everywhere else.

For a struct that keeps its derived accessors, because they are API or the struct is serialized, svara 3.8.5 declares
`const` offsets beside it for the fields its per-sample code touches. A test writes every field through its derived
setter and checks that each offset reads its own field, so the two statements of the layout cannot drift apart
silently. Over 84 accessor uses, glottal source to DC blocker, that took svara's synthesis chain to 0.952x its
retired instructions. A fix here would make those offsets unnecessary.
