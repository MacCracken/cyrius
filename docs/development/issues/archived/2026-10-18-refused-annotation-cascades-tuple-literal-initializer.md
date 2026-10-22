# A refused `var` annotation, then a tuple literal initializer, cascades "a tuple literal cannot initialize 'b' - its declared type is not a tuple" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-6, `11c894842`, with the find met beside it FE-7, `e6c35814f` — no decision needed (diagnostics only; refused before and after). `_tup_r9` (src/frontend/parse_decl.cyr), R9's one reporter for the fn / post-statement and the zone paths, stands down when `_tup_ann_refd` says the annotation was refused at its token (a reported or refused-declaration name no type answers, or a reported non-type token), marking the literal so the factor's refusal stands down too — the filing's own alternative fix; its other (infer the tuple) was measured first and added new cascades. The filed repro is now one error, "2:12 unknown type 'Nonexist' for variable 'b'" (it added "2:23 a tuple literal cannot initialize 'b' - its declared type is not a tuple"); so are `var b: 1 =`, `var b: =` and a refused late struct's annotation, in a fn, the declaration zone and after the first statement, on x86_64, aarch64, cx, PE and Mach-O. An annotation that still names a type keeps R9 (`: i64`, `*Nope`, `i64<u8>`). FE-7: R9 on a `*T` declaration (`var b: *i64 = (1, 2);`) no longer adds "assigning non-pointer to typed pointer" about the refused literal. Rows: `tests/gates/frontend/tuple_checked.sh` CS9 (the repro verbatim) – CS9o, CS9p – CS9s; mutations: the pre-bite compiler RED 13, `_tup_ann_refd` without its `_dl_refd_at` arm RED CS9i / CS9j, without its `_tn_resolve_at` test RED CS9o, FE-7's mark dropped RED CS9p – CS9s. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F2, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc) for the unknown-type and
non-type-token spellings.
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — refused either way (rc 1); the first error is the right one, one invented error follows.
**Kind:** bug (diagnostic cascade).
**Discovered:** 2026-10-18, by unit F2 fixing issues/archived/2026-10-16-var-missing-annotation-reported-as-expected-equals.md
(its new "expected a type for variable 'b', got '='" shape meets the same cascade with a tuple initializer). Same
class as issues/archived/2026-10-17-refused-annotation-type-cascades-at-field-uses.md (receives lane), which covers a later
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
