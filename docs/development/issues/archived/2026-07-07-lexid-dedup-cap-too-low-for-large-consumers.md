# Identifier dedup table cap (16384) too low for large multi-bundle consumers — RESOLVED

> **RESOLVED v6.4.21 — archived 2026-07-08.** Cap raised **16384 → 65536** (4×). Not a
> one-line bump: `lexid_entries` was boxed in by `preprocess_out`, so it was relocated to
> a fresh arena-top region @ `0x7300000` and all 7 forks' arenas extended to `0x7400000`
> (lazy-mapped → no cost on the aarch64/macho/cx forks). Two-step bootstrap, cycc
> byte-identical, differential 340/340, cross-OS ecb/cass/pi SELFHOST_OK; proven with a
> 20000-identifier program (fails on old cycc, compiles on new). See CHANGELOG [6.4.21].


- **Filed**: 2026-07-07 (hit while wiring stiva's run path + logging; adding ~4
  test functions to `tests/stiva.tcyr` tipped the compile over the cap).
- **Severity**: P2 (scaling wall). Not a miscompile — a hard ceiling that a large,
  correct program legitimately reaches, with no consumer-side lever to raise it.
- **Component**: `lex.cyr` — the identifier dedup table (`LEXID` cap = 16384 entries).

## Symptom

```
error: identifier dedup table full (16384 entries) - raise LEXID cap in lex.cyr
  FAIL: tests/stiva.tcyr (compile error)
```

The message itself directs the fix to `lex.cyr` — i.e. a **compiler change**, which
a consumer cannot make. The build had been green at 806 test assertions; adding a
handful of `test_build_sandbox_*` functions (each contributing its fn name + a few
already-interned symbols) pushed the unique-identifier count past 16384 and the
whole compilation unit failed.

## Why a legitimate program hits it

`tests/stiva.tcyr` is a single compilation unit that `include`s all 25 stiva
`src/*.cyr` domain modules, which in turn pull in the full AGNOS dep set —
`kavach` (~9k lines), `agnodrm`, `nein`, `majra`, `bote-core`, `libro`, `sakshi`,
`sankoch`, `bayan` — plus the opt-in stdlib. The dep bundles alone dominate the
identifier count; stiva's own modules + ~800 test functions sit on top. The cap is
a per-**compilation-unit** ceiling, so the more bundles a consumer composes, the
less headroom remains for its own code. Any multi-bundle consumer (stiva, and
plausibly daimon/sutra downstream) will approach it.

Note `src/main.cyr` (the program entry) compiles fine — it lacks the ~800 test
functions, so it has headroom. The ceiling bites the **test** compilation unit
specifically, i.e. exactly where a project accumulates the most symbols over time.

## Consumer-side workaround applied (stiva)

Split the monolithic test file: moved the run-path tests into a second
`tests/runpath.tcyr` (its own `include` header + `main`) and run both via
`cyrius tests tests/` (the recursive runner compiles each `.tcyr` as its own unit,
so each stays under the cap). This works but:
- fragments the suite across files purely to dodge a compiler limit,
- only defers the wall — each split file re-accretes identifiers as tests grow,
- forces a move away from the documented single-file `cyrius test tests/stiva.tcyr`.

## Suggested directions (compiler-side — not consumer)

1. **Raise the cap** (cheapest): 16384 → 65536 (or make it a build-time constant).
   A dedup table is a hash set of interned strings; the memory cost of a larger cap
   is modest next to the AGNOS bundles already resident.
2. **Grow dynamically**: resize the dedup table on load-factor instead of a fixed
   array — removes the ceiling entirely.
3. **Per-include scoping / symbol GC**: if identifiers from fully-resolved includes
   could be dropped from the live dedup set, multi-bundle consumers wouldn't pay the
   union cost in one flat table.
4. At minimum, surface the current count in the error (`N/16384`) and in a
   `--verbose` symbol-budget report so consumers can see how close they are before
   the wall.

Filed from the stiva port; the language was not modified. Companion consumer note:
stiva's `tests/` is now split (`stiva.tcyr` + `runpath.tcyr`) as the workaround.
