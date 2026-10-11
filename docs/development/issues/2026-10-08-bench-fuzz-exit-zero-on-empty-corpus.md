# Bare `cyrius bench` / `cyrius fuzz` exit 0 when they find nothing to run — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 14; CHANGELOG [6.7.9]) The bare verbs fail on an empty corpus, as
> bare `cyrius test` and an explicit empty directory already did: `error: no fuzz harnesses found (looked in fuzz/ and
> tests/, recursively)` / `error: no benchmarks found (looked in benches/ and tests/, recursively)` on stderr, the
> create-a-harness hint on stdout, rc 1. `cyrius audit`'s bench stage (the one other caller of the bare bench walk,
> a non-fatal perf measurement) says `skip: no benchmarks (benches/ and tests/ hold no .bcyr)` instead of printing an
> error under a passing audit — the walk is `_bench_all(empty_fails)`, 1 for the verb, 0 for the audit. Reproduced
> first on the 6.7.9 tree: bench rc 0, fuzz rc 0, test rc 1. `tests/gates/toolchain/corpus_walk_rules.sh` axis 6:
> fuzz / bench / test with every root absent, fuzz / bench with the roots present and holding no file of the verb's
> extension (rc 1, the error, no tally), and the audit's skip (rc 0, no `error:`). The 6.7.9-open source reddens 5
> checks; each of 4 mutants (either empty arm back to `return 0`, cmd_bench in the audit's mode, the audit in the
> verb's) reddens its own rows. `test_section.sh` N3 ran `cyrius fuzz --no-lock` over a project with no `.fcyr` and
> read the vacuous rc 0 as "the flag is accepted"; it now runs a real harness and requires `=== 1 passed, 0 failed ===`.
> The bite's review found the sibling verb with the same defect, and it ships in the same bite: a bare `cyrius smoke`
> with no `.smcyr` printed `No smoke harnesses found in tests/smcyr/ or smoke/` and exited 0; it now says `error: no
> smoke harnesses found (looked in tests/smcyr/ and smoke/, recursively)`, keeps the hint, rc 1 (axis 6 rows 6g / 6h;
> the check driver's v5.7.38 smoke check, which pinned the empty-directory rc 0, now requires rc 1 and the error).
> `cyrius soak` is not affected: it always runs its self-host loop.

**Status:** ✅ **RESOLVED** in v6.7.9 (the quick lane's bite 14). Filed OPEN — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b (CLI built from `cbt/cyrius.cyr` by the tree's
`build/cycc`, throwaway `HOME` / `CYRIUS_HOME`): in a project with no `.bcyr` / `.fcyr`, `cyrius bench` and
`cyrius fuzz` print "No … found" and exit **0**; `cyrius test` with no `.tcyr` exits 1. The roadmap bullet's other two
sub-items are ALREADY FIXED and were not filed (below).
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** the 6.7.6 review (2026-10-08; roadmap.md backlog, *Tooling* — "Test tooling"); filed 2026-10-08 from
roadmap.md.
**Severity:** Medium — a CI line running `cyrius bench` / `cyrius fuzz` over a tree whose harnesses moved or were
renamed passes vacuously: the silent-empty-corpus class the project bans for its own readers ("every gate carries a
corpus FLOOR").
**Affects:** the `cyrius` CLI through 6.7.8 (fixed in 6.7.9).

## Summary

`cmd_test` treats an empty corpus as a failure (`cbt/commands.cyr:737-742`: `No .tcyr files found under …`,
`_fail = _fail + 1`). The bench and fuzz drivers print the same kind of message and `return 0`
(`cbt/commands.cyr:1145-1150` and `:1015-1019`).

The roadmap bullet also listed two sub-items that no longer reproduce:

- "`cmd_test` labels any exit status above 128 a signal (a test exiting 232 prints `killed by signal 104`)" — fixed in
  6.7.6 by fa318500 (FXCL-8a, the signal is read from the wait status, `_run_last_signal`, `cbt/commands.cyr:520-545`).
  Live: a unit `syscall(60, 232);` prints `FAIL: tests/e232.tcyr (exit 232)`.
- "a `[test.embed]` name duplicating `[embed]`'s says 'declared twice' without naming `[embed]`" — fixed in 6.7.6 by
  59d87ff3 (FXCL-8b, `cbt/manifest.cyr:1088-1117`). Live: `error: cyrius.cyml [test.embed] BLOB: is declared twice —
  cyrius.cyml [embed] declares it too (a test unit compiles both)`.

## Reproduction

```sh
mkdir -p p/src && cd p
printf 'fn main(): i64 { return 0; }\nvar r = main();\n' > src/main.cyr
printf '[package]\nname = "ptt"\nversion = "0.1.0"\n\n[build]\nentry = "src/main.cyr"\n' > cyrius.cyml
cyrius bench; echo rc=$?   # "No benchmarks found (looked in benches/, tests/ and tests/bcyr/, recursively)." rc=0
cyrius fuzz;  echo rc=$?   # "No fuzz harnesses found (looked in fuzz/ and tests/)."                        rc=0
cyrius test;  echo rc=$?   # "No .tcyr files found under tests/"                                             rc=1
```

Expected: a non-zero exit when the corpus is empty, as `cyrius test` does. Actual: 0 — for the BARE verb only; an
explicit empty directory (`cyrius bench emptyd`) already exits 1.

## Root cause

`cbt/commands.cyr:1018` (`cmd_fuzz`) and `:1150` (`cmd_bench`): `return 0;` after the "found nothing" message.

## Proposed fix

Return 1 (and say so) on an empty corpus from the bare verb, matching `cmd_test` and what an explicit empty directory
already does (`cyrius bench emptyd` / `cyrius fuzz emptyd` → `error: no … found under: emptyd`, rc 1 — measured). A
project that deliberately has no benches or fuzz harnesses and runs the bare verb in CI goes red at its pin bump — name
it in the CHANGELOG / `ecosystem-migration.md`.
