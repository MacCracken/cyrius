# ADR-007: Traits — Checked Method Sets over Convention-Based Dispatch

**Status**: Accepted
**Date**: 2026-10-07 (cyrius 6.7.0)
**Amends**: [ADR-004](004-convention-based-dispatch.md) — its naming section, and its "Future `impl`
blocks will be syntactic sugar" consequence, which this ADR fulfils.

## Context

Until 6.7.0, `impl Show for Point { … }` was syntax with no trait behind it: there was no `trait`
keyword, `PARSE_IMPL` skipped the trait name unread (so `impl NoSuchTrait for P` compiled), a
method no trait declared compiled, and two impls giving `Point` a `size` both became `Point_size`
(a duplicate-fn warning; the last definition bound). An untyped `self` was a bare address, so
methods read `load64(self)` and `self.x` was "no struct type in scope". There was no inherent
`impl T { … }`. The language-minor plan (roadmap.md, arc A) asked for real, checked traits that
keep ADR-004's zero-overhead static dispatch.

## Decision

1. **`trait NAME { … }` declares a method set.** A member is `fn m(params)[: Ret];` (required) or
   `fn m(params)[: Ret] { body }` (a **default**). A trait body holds only `fn` members; a trait or a
   member declared twice is an error.
2. **`impl X for T { … }` is checked against `trait X`.** An undeclared trait, a method the trait
   does not declare, a parameter count that differs from the declaration, and a required method left
   out are each a compile error naming the trait. A default the impl does not define is
   **instantiated for T**: parsed from the trait's own tokens with T as the impl type, exactly as a
   generic instance is parsed from its base's.
3. **Inherent `impl T { … }`** — methods with no trait — mangle as a trait impl's do (`T_m`).
4. **Names (user decision, 2026-10-07: the mangled form).** Every trait method is reachable as
   `T_Trait_m`. While one trait (or an inherent impl) gives T an `m`, it is also the plain `T_m`,
   so `p.m()` and the `T_new(..)` constructor idiom are unchanged. When **two traits** give T an `m`,
   each is defined as `T_Trait_m`, and the plain `T_m` / `p.m()` is an ambiguity error naming a
   qualified spelling — except inside an impl (or a default) of one of those traits, where
   `self.m()` means that trait's own. An **inherent** `m` keeps `T_m`, so `p.m()` picks it and the
   trait's is `T_Trait_m`. No new call syntax: choosing is calling the qualified name.
5. **`self`.** An untyped `self` inside `impl … for T` (or `impl T`) is a `*T`: it reads and writes
   fields (`self.x`), and `T_m(o)` / `T_m(&o)` / `o.m()` agree (a bare struct passed to a `*T`
   parameter passes its address, 6.6.20). Arithmetic on an untyped `self` (`self + n`, `self[i]`,
   `self += n`, …) is **refused** (user decision, 2026-10-07): a `*T` steps `sizeof(T)`, so
   `load64(self + 8)` would otherwise have changed meaning silently. An explicit `self: *T` keeps its
   arithmetic; an explicit `self: T` keeps its by-value meaning.
6. **`var q: T = p;` with `p: *T` copies `*p`** at every size (user decision, 2026-10-07). Aliasing
   is spelled `var q: *T = p;`.
7. **Dispatch stays static (ADR-004).** No vtables are generated. Trait objects remain the
   `lib/trait.cyr` library pattern for now. **Decided 2026-10-07 (user, at 6.7.1): 6.7.x adds
   compiler-CHECKED trait objects** later in the minor — `o: dyn Show` an ordinary 16-byte
   `{data, vtable}` struct whose vtable the compiler builds and verifies from `impl Show for T`; static
   dispatch stays the default (roadmap.md, open question 5). This ADR is its prerequisite.

8. **Trait bounds (6.7.1, roadmap.md § C3).** `fn f<T: Show + Eq>` and `struct Box<T: Show>`.
   User decisions (2026-10-07): a bound is a **contract** — on a bounded `T`-typed parameter or
   local, `v.m()` must be a method of a bound's trait (checked at the generic's definition) and
   calls that trait's `m` for `T`'s impl, so the bound chooses on a collision exactly as an impl's
   own `self.m()` does (decision 4); `T: A + B` requires every impl; any type satisfies a bound
   through its impl, a scalar included. Every instantiation is checked, the i64 base included.
   Dispatch stays static. An unbounded `T` keeps per-instance resolution.

## Implementation notes

- One token pre-scan at the start of pass 1 (`_tr_prepass`) records every trait (members, parameter
  counts, default bodies) and every impl (type, trait, methods), so a trait declared **below** its
  impl and a collision with an impl further down are both known before the first method is
  registered. Tables are allocated on the first trait or impl — a program with neither pays nothing.
- A method's mangled name is decided per method (`_tr_prefix`): its type, or `T_Trait` on a
  collision. `FINDFN`'s miss path resolves `T_Trait_m` for a non-colliding method and reports an
  ambiguous `T_m` (`_tr_fallback`); the undefined-function report adds the same explanation for a
  direct `T_m(..)` call.
- Pass 1 records an impl method's untyped `self` per function (`_fnt_iself`), so pass 2 and every
  generic instance (re-parsed from its call site, outside the impl) type it identically.
- (6.7.1) Bounds are captured with the type-parameter names (`_capture_tparams`) and resolved once
  per definition. Pass 1 walks a bounded generic's parameters and body (`_bnd_sites`): every
  `v.m(` on a bounded receiver is checked against the bound and recorded by its method-name TOKEN —
  the base, each instance and each inline replay re-parse those same tokens, so the call resolves to
  the impl's own method (`_tr_prefix`) in all of them. A base whose bounds i64 fails is the dead stub,
  as a struct-using generic's is.

## Consequences

- `trait` is a reserved word (no identifier use anywhere in cyrius or its ecosystem, surveyed
  2026-10-07).
- cyrius's own tests used trait names as labels on impls of undeclared traits (84 sites, 32 files);
  they are inherent impls now. The ecosystem has no `impl` blocks.
- Collision-free code is unchanged at the ABI level: the same `T_m` symbols, the same direct calls.

## Tests

`tests/tcyr/crossos/traits_checked.tcyr`, `impl_self_typed.tcyr`, `impl_inherent.tcyr`,
`struct_from_pointer_copies.tcyr`, `method_on_nested_field.tcyr` (every cross-OS host);
`tests/gates/frontend/traits_checked.sh`, `impl_self_typed.sh` (the refusals, mutation-checked).
Bounds (6.7.1): `tests/tcyr/crossos/trait_bounds.tcyr`, `tests/gates/frontend/trait_bounds_checked.sh`.
