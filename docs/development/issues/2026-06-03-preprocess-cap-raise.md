# Preprocess-output cap raise: 2 MB → 6–8 MB

> **ALREADY SATISFIED — premise-check 2026-06-03 (v6.0.46 cap-sweep entry).**
> `preprocess_out` is already **8 MB**: raised v5.11.33 (relocated from the
> old 2 MB region at 0x44A000). `src/frontend/lex_pp.cyr` uses `8388608`
> throughout — READFILE bound (1598/1962), overflow check `if (op > 8388608)`
> (1689/2014), and the tmp scratch buffer (1775/2027). The remaining `2097152`
> checks in `src/frontend/lex.cyr` (154/1451/1610) guard a DIFFERENT buffer —
> the `str_data` region at `S+0x21A000` ("string data overflow (2MB limit)") —
> which is out of this issue's scope. **No code change needed for the
> preprocess cap.** (If `str_data` 2 MB ever bites, that's a separate item.)
> Leaving in the active queue until the rest of the cap-sweep lands, then
> archive with the bundle.

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
