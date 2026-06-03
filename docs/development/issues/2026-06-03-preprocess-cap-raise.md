# Preprocess-output cap raise: 2 MB → 6–8 MB

**Filed:** 2026-06-03
**Severity:** P2 (capacity / future-proofing)
**Status:** queued for the cap-sweep bundle (joins
`2026-05-28-type-table-256-cap.md`, `2026-05-27-secret-defer-block-per-fn-cap.md`,
`2026-06-02-struct-field-cap-raise.md`)

## Context

The compiler's `preprocess_out` buffer is capped at **2 MB** (since v5.6.40).
The cap forces a "keep dep code opt-in" policy in `cyrius.cyml` (`[deps].stdlib`
auto-prepend union stays minimal so consumers' expanded source doesn't blow the
buffer). This surfaced again folding **mabda 3.0.1** (2026-06-03): mabda's dist
is 515 KB and it newly needs `mmap` + `dynlib` + `sakshi`. Rather than enlarge
the auto-prepend union (which every consumer pays into the 2 MB buffer), mabda
was kept fully opt-in (consumers `include` its deps explicitly). User direction:
keep opt-in now, **and raise the preprocess cap to 6–8 MB during cap-sweep work**
so the union policy is driven by good architecture, not the buffer ceiling.

## Target

- Raise `preprocess_out` cap **2 MB → 6 MB or 8 MB** (pick during the sweep;
  8 MB gives the most headroom, 6 MB is the conservative step).
- Self-host must stay byte-identical; verify the larger static buffer doesn't
  shift the heap map / cycc size unexpectedly (it's a `.bss`-style region).
- After the raise, re-evaluate whether large opt-in distlibs (mabda, sigil) can
  move into the auto-prepend union for ergonomics without cap pressure.

## Where

The 2 MB constant lives at the `preprocess_out` region in the compiler source
(introduced v5.6.40). Locate via the heap-map region for `preprocess_out` and
the bound-check that emits the "preprocess buffer overflow" diagnostic.

## Verify

- `sh scripts/check.sh` green; cycc self-host byte-identical (x86 + cross-OS gate).
- A synthetic consumer that auto-prepends the full union + a large opt-in distlib
  compiles where it previously hit the 2 MB ceiling.
