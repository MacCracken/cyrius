# A refused `var` annotation, then a tuple literal initializer, cascades "a tuple literal cannot initialize 'b' - its declared type is not a tuple" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F2, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc) for the unknown-type and
non-type-token spellings.
**Placement:** unplaced — filed from the 6.7.15 frontend lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — refused either way (rc 1); the first error is the right one, one invented error follows.
**Kind:** bug (diagnostic cascade).
**Discovered:** 2026-10-18, by unit F2 fixing issues/2026-10-16-var-missing-annotation-reported-as-expected-equals.md
(its new "expected a type for variable 'b', got '='" shape meets the same cascade with a tuple initializer). Same
class as issues/2026-10-17-refused-annotation-type-cascades-at-field-uses.md (receives lane), which covers a later
`.field` USE, not the declaration's own tuple-literal initializer.

## Reproduction

```cyrius
fn f(): i64 {
    var b: Nonexist = (1, 2);
    return 0;
}
syscall(60, f());
```

```
error:<source>:2:12: unknown type 'Nonexist' for variable 'b'
error:<source>:2:23: a tuple literal cannot initialize 'b' - its declared type is not a tuple
```

The same second error for a non-type token (`var b: 1 = (1, 2);`, 6.7.14's D15 (a) refusal at 2:12 then 2:16) and,
since 6.7.15, for a missing type (`var b: = (1, 2);` -> "expected a type for variable 'b', got '='" then 2:14), in a
fn, in the declaration zone (`var G: = (1, 2);` -> 1:8 then 1:10) and after the first statement.

Expected: one error, the annotation's; a refused annotation leaves the declaration untyped for its initializer's
checks (or the tuple check stands down when the annotation token was reported: `_tn_seen_at`).

## Root cause

`_tup_var_lit` (fn / after the first statement) and `_gvi_tuple` (the zone replay), src/frontend/parse_decl.cyr,
treat any annotation (`ann != 0` / the `:` at `sti + 2`) whose scale is not a tuple sid as a declared non-tuple type
and report R9; a refused annotation leaves pscale / gps at 0, which reads as "declared, not a tuple".
