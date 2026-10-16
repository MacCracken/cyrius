# A global first declared `= 0` and redeclared with another value is silent (no "conflicting value" warning), so two files' same-name globals merge unseen — RESOLVED

> ✅ **RESOLVED in v6.7.12** (FX-6, the user's decision D30, 2026-10-15: warn (option 1), and widen `fold_namespace_collisions.sh` (option 2). A prior constant zero is now a recorded constant (`_gv_lit` / `_gv_has_lit`, a lazily allocated byte per global), so the third repro line, `var a = 0; var a = 5;`, warns "duplicate symbol 'a' redefined with conflicting value (last definition wins)" with rc 0, as the first two did; the cross-file `_shared` pair warns at b.cyr (still one cell, exit 7); a folded zero and the chain's third link over a zero second warn too, and `var A = 0;` before an enum member `A` takes the conflicting-value wording. A same value stays silent. A diagnostic only: over 800 files on six targets no warning count changed, and the self-host prints no new warning. `fold_namespace_collisions.sh` now compiles every fold in docs/ecosystem.md together, both orders (axis 3, 12 folds), and refuses a top-level var / fn name two folds declare whatever its value (axis 4) — no shared name today, no fold patch needed. Rows: `frontend/global_redeclaration_one_definition.sh` W1-W9, XF1-XF3 (mutations w1, w2 and the pre-D30 compiler RED), `redefinition_layout_and_enum_over_var.sh` ev_zero, `toolchain/fold_namespace_collisions.sh` axes 3-4 (mutations f1-f3 RED). The new-value side still compares only an exact `= NUM ;` (filed: 2026-10-15-redeclared-global-folded-later-value-not-compared.md, 6.7.14). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 against the 6.7.11 wave-1 merge (`build/cycc` 2,168,800 B, x86_64).
**Placement:** 6.7.12 — repair 2: the platform release (fixfirst lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D30 — warn, and widen fold_namespace_collisions.sh.
(and, if refused, what compiles): the user's call — warn, refuse across files, or document the `= 0` exception.
**Severity:** Medium — a diagnostic gap, but it is how a real cross-fold collision shipped: sankoch 2.8.4's Brotli
encoder declared `var _bre_err = 0;`, niyama already declared `var _bre_err = 0;`, and a program including both
compiled clean with one cell for both. Found only by the 6.7.11 distlib owner-rule census
(`distlib_owner_rule_shared.sh` row C); fixed in the fold by sankoch 2.8.7's rename (`_bre_ovf`).

## Repro

```sh
printf 'var a = 5;\nvar a = 7;\nsyscall(60, a);\n' | build/cycc > /dev/null   # warning: duplicate symbol 'a' redefined with conflicting value (last definition wins)
printf 'var a = 5;\nvar a = 0;\nsyscall(60, a);\n' | build/cycc > /dev/null   # the same warning
printf 'var a = 0;\nvar a = 5;\nsyscall(60, a);\n' | build/cycc > /dev/null   # NOTHING — rc 0, no warning
```

Across files (`a.cyr`: `var _shared = 0; fn a_set(v): i64 { _shared = v; return 0; }`, `b.cyr`:
`var _shared = 5; fn b_get(): i64 { return _shared; }`, a main including both): compiles rc 0 with no warning;
`b_get()` reads 5 at start, and `a_set(7); b_get()` exits 7 — one cell.

## What the guide says

docs/guides/cyrius-guide.md § *Declaring a global twice (6.6.6)*: a conflicting value warns (`var a = 5; … var a = 7;`);
"A same-value redeclaration is silent; that is the usual way two files, or an `#ifdef` arm, end up declaring one
global." It does not list `= 0` followed by another value as silent.

## Why it matters

The same-value rule makes two files declaring one global the intended pattern, so a collision between two folds that
each picked a private-looking name (`_bre_err`) is indistinguishable from it. `tests/gates/toolchain/fold_namespace_collisions.sh`
looks for the compiler's duplicate / conflicting-value warnings across four folds (yukti, mabda, vani, sakshi) only, so
neither the `= 0` case nor any other pair of folds is covered; the distlib census caught this one because the owner rule
refuses a tie.

## Options (the user's)

1. Warn on `= 0` then another value, as on every other conflicting pair (a diagnostic only).
2. Additionally warn when a same-name top-level global is declared in two DIFFERENT files of `lib/` (the cross-fold case),
   or extend `fold_namespace_collisions.sh` to every fold and to same-value globals.
3. Keep it and document the `= 0` exception in the guide.
