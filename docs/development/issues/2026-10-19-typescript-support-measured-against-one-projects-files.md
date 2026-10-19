# The TypeScript front end is measured against one project's files (secureyeoman's corpus), not the language — it needs true, in-tree language support — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-19 with [the cross-project gates issue](2026-10-19-gates-read-other-projects-checkouts.md).
The user, 2026-10-19: "I get TS corpus from SY but in effect that needs to convert into true language support not just
SY corpus there was tons of work relates to that."
**Placement:** open by design — a feature / arc, not a bug: roadmap.md § *Placed arcs* — the TypeScript language-support arc, its own
arc AFTER the 6.7.17 audit (the user, 2026-10-19); sized at its open, its release set with the 6.7.17 review follow-ups — never 7.x.
**Decision (user, 2026-10-19):** its own arc after the audit. Until then the secureyeoman rows leave the gate with the
6.7.16 cross-project rip, and the 40 in-tree fixtures are the measure.
**Severity:** Medium — the front end's only broad conformance measure is "how much of one consumer's code parses", which
says nothing about TypeScript constructs that project does not use, gates the release on that project's checkout, and
ties the front end's shape to one codebase.
**Kind:** language support (src/frontend/ts/, src/backend/js/, ~7,800 lines) + its corpus and gates.

## Where it stands (measured 2026-10-19)

- **The front end**: `cycc --lex-ts` / `--parse-ts` / `--emit-js` (type-strip, JSX → `h`, ESM), on every compiler but
  `cycc_cx` since 6.7.15 (D38); `cyrius build --target=js`; `programs/ts_test_runner.cyr`.
- **The broad measure** (check driver, programs/checks/ts.cyr `_ts_corpus_gate`, main.cyr:898 / :902): "cycc --parse-ts
  vs SY .ts corpus ≥98 % baseline (v5.7.3 P3.1)" over 2,053 `.ts` and "… .tsx corpus" over 435 `.tsx` files of
  `~/Repos/secureyeoman` (`SY_CORPUS`). The v5.7.x P3 work (2026-04 / 05: `asserts` predicates, mapped types,
  stage-3 decorators, variadic tuples, `const` type parameters, `satisfies` / conditional types, …) was driven by what
  that corpus contained and by secureyeoman's `yeo-cy-test` port probe (CHANGELOG [5.7.x]).
- **In-tree coverage**: 40 fixtures in eight directories (tests/fixtures/ts_asserts, ts_mapped, ts_decorators,
  ts_variadic_tuples, ts_const_type_params, ts_advanced_pin_audit, ts_lex, ts_emit), each a parse-acceptance row
  (`_parse_ts_dir_gate`), plus the lex and walk rows. No in-tree corpus covers the language as a whole, and the JS emit is
  checked on a handful of shapes.

## What "true language support" means here (the arc's scope, sized at its open)

1. **An in-tree TypeScript conformance corpus, organized by the LANGUAGE**, not by one project: the lexical grammar
   (template literals, numeric separators, regex vs divide, ASI); types (unions, intersections, literal / template-literal
   types, conditional and `infer`, mapped with modifiers and `as`, indexed access, `keyof` / `typeof`, generics with
   constraints and defaults, tuples incl. variadic and labelled, function / constructor types, `unique symbol`,
   assertion and type predicates); declarations (interfaces with merging, type aliases, enums incl. `const enum`,
   namespaces / modules, `declare` / ambient, abstract classes, accessors, parameter properties, overloads, index
   signatures, decorators); expressions (optional chaining, `??`, `as` / `satisfies` / `!`, explicit type arguments in
   calls, arrows, async / generators, class fields incl. `#private`); JSX / TSX; every ESM import / export form incl.
   type-only. Each fixture has an expected PARSE verdict and an expected JS output (the type-strip / JSX emit, byte for
   byte), and the refusals are rows too (what the front end does not support is refused by name, never mis-emitted).
2. **The gate is that corpus** — every fixture's verdict and emitted JS on x86_64 and the other compilers that carry the
   front end (the D38 set), counted with a floor; the secureyeoman rows leave the gate (a local, opt-in smoke at most).
3. **A support matrix in the guide** (or its own doc): what TypeScript is supported, what is refused, against which
   TypeScript version's grammar — so "supported" means a list a user can read, not a consumer's pass rate.
4. Gaps the corpus finds are fixed in the arc (a front end failing valid TypeScript is the compiler's bug), or each
   filed with its placement.

## Acceptance

- The TypeScript corpus lives in the cyrius tree and is the front end's gate; no gate reads secureyeoman (or any other
  project).
- The guide / support document names the supported TypeScript surface and the refused one, each with a fixture.
- The corpus's emit rows are byte-checked on every compiler that carries the front end (6.7.15's D38 set).
