# Two included bundles that define the same function compile with a warning, and every caller, the first bundle's own included, gets the last — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-11. The repro exits 1. The behaviour is
documented ("duplicate fn … last definition wins", guide L5268); this files its consequence for libraries.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-11, by ushma's Rust → Cyrius port (M0 probe 6, `ushma/docs/development/port-parity.md` §3).
**Reporter:** ushma 2.0.0 port (`ushma/docs/development/ushma-port-plan.md` §8)
**Severity:** **High: silent wrong code across libraries.** A program that includes two bundles sharing a function
name and signature builds, and the first bundle's own internal calls go to the second bundle's function. Only a
warning says so, among a bundle's other warnings.
**Affects:** cyrius 6.7.18. The rule is older.

## Summary

Cyrius has one global namespace. Rust ports keep their Rust function names, and the AGNOS libraries overlap:
- ushma 1.4.0 and kimiya's bundle share **10** public names (`ideal_gas_pressure`, `reaction_enthalpy`,
  `equilibrium_constant`, …), and kiran uses both;
- prakash's ai client has `ai_*` names that other daimon clients would also take.

When two included bundles define the same non-private function:
- with **different** signatures, the build is an error, and the program at least can't build;
- with the **same** signature, it is a warning, and every call resolves to the last definition, including the calls
  inside the first bundle.

So whether a program computes the right answer depends on include order, with no error.

## Reproduction

`repros/2026-11-11-duplicate-fn-across-bundles-last-wins.sh`:
- bundle A defines `ideal_gas_pressure` in Pa, and `a_pressure_kpa`, which calls it;
- bundle B defines `ideal_gas_pressure` with the same signature, in kPa;
- the program includes A, then B, and calls A's `a_pressure_kpa`.

```
warning:src/b.cyr:2:1: duplicate fn 'ideal_gas_pressure' (last definition wins; first defined in src/a.cyr)
OK (81896 bytes)
a_pressure_kpa x 1000 = 2
```

The expected value is 2494, which A's own function gives. It exits 1.

## Root cause

By design: a later definition replaces an earlier one in the symbol table, and the call sites bind by name after
all definitions are seen.

## Proposed fix

Any one of these closes the hole; the first two are small:
1. Make a duplicate non-private function across **different files** an error by default, keeping last-wins only
   within one file, or behind an explicit opt-in such as an `#override` attribute.
2. An opt-in strict mode (`cyrius build --strict-dup`, or a manifest key) for projects whose gates are warning-free
   anyway.
3. The language fix: `mod` scoped to its file (`2026-11-11-mod-scope-runs-past-the-included-file.md`), so libraries
   can namespace themselves.

## Consumer-side workaround

Written prefixes on every public name (ushma: `us_*`, ADR 0001 amendment). It works only if every library does it,
and the Rust-named ones don't.
