# Proposal — let `cyrius coverage` take RUN programs as a corpus, not just `.tcyr` suites

**Filed:** 2026-09-20 · **Status:** 🟡 OPEN — for maintainer direction
**Filed by:** rekha (0.4.12), which has 25 test programs, ~13,000 lines of assertions, and no
coverage number at all. Measured against cyrius 6.6.6.

**Prompted by:** a roadmap cleanup that went looking for rekha's coverage figure and found that
none exists, and that the absence had been recorded only in a CI comment.

## What happens today

`cyrius coverage` builds its corpus from `tests/**/*.tcyr`. rekha has no such directory: every
assertion it owns lives in a `programs/*_test.cyr` **RUN program** — a self-checking binary that
draws or parses, compares against an expected value, and exits non-zero on any mismatch. CI builds
each one under `CYRIUS_DCE=0` and `1`, fails on any build-log warning, and requires rc 0.

So the tool reports **~0%** for an API that is, in fact, exercised hard. rekha's CI says so in as
many words:

```yaml
# ⚠ `cyrius coverage` is NOT a gate here: it builds its corpus from tests/**/*.tcyr only
# and is blind to programs/, so it reports ~0% for a fully exercised API. The gates are
# these RUN suites and the hostile corpus.
```

`.github/workflows/ci.yml`, the build job.

## Why rekha tests this way, and is not going to stop

A `.tcyr` suite asserts on a function's return value. rekha's unit of correctness is not a return
value — it is a **decoded outline**, several thousand points long, compared against an independent
reference decoder, and reached only by driving a whole font container through the library. The
suites that matter are shaped like programs because the thing under test is a pipeline:

| suite | what one "assertion" is |
|---|---|
| `programs/cff_test.cyr` (697 checks) | a Type 2 charstring built byte by byte, run, and its points compared |
| `programs/gvar_test.cyr` (207) | a variable font built in memory, instanced at four weights, every point compared |
| `programs/hostile_test.cyr` (~2,100 lines) | a seeded mutation sweep over a real face, with an A/B sentinel differential across the allocator seam |

None of those decomposes into `.tcyr` cases without losing the property being tested.

## What is asked

A way for `coverage` to treat a **built and run program** as a corpus entry. Sketch, in
preference order:

1. **A manifest channel** — `[coverage] programs = ["programs/*_test.cyr"]`, each built with
   instrumentation, run once, exit code respected, counters merged. This is the smallest change
   that fits how packages already declare things.
2. **A flag** — `cyrius coverage --programs 'programs/*_test.cyr'`, same semantics, nothing
   persisted.
3. **Merge-only** — `cyrius coverage --merge <profraw...>`, and let a package arrange its own
   instrumented runs. Most work for the package, least for the toolchain, and it unblocks
   everyone who does not fit the `.tcyr` mould.

⚠ **Not asked for:** changing what `.tcyr` means, or making `coverage` a gate. rekha's gates are
the RUN suites and the hostile corpus, and would stay so. What is missing is the *number* — the
thing that says which branches of `src/cff.cyr`'s 1,102 lines no suite has ever entered.

## Why it is worth a toolchain change

The blind spot is not rekha's alone: any library whose correctness is a pipeline rather than a
function will test with programs. And the cost of having no number is specific and already
observed — rekha 0.4.10 found that `units_per_em`, `char_to_sdpath` and `char_advance` appeared
nowhere in a 678-check CFF suite, with the whole upem-scaled path dark on CFF faces, and found it
by accident while writing an unrelated test. A coverage report would have named it on day one.

## Pointers

- rekha's suites: `programs/*_test.cyr`, 25 of them, all globbed by CI.
- The CI comment quoted above: `rekha/.github/workflows/ci.yml`, "Build & run" step.
- rekha's roadmap note: `rekha/docs/development/roadmap.md`, under *Blocked on a sibling*.
