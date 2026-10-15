# An unknown name followed by `<..>` is accepted as a type argument (`g<Nonexist<u8>>`, `Box<slice<u8>>`) and runs as the i64 base — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: the repro builds clean and exits 11 — `g<Nonexist<u8>>(0)` runs the i64 base (`sizeof(T)` = 8) and
`var c: Box<Nonexist<u8>>;` declares a `Box` of the base — while `g<Nonexist>(0)` and `var c: Box<Nonexist>;` are
refused "unknown type 'Nonexist' as a type argument". Spelled `slice<u8>` (the built-in slice's word form) the same
program also builds and exits 11, although 6.7.8 refuses the `[u8]` spelling there by name. The installed 6.6.20,
6.7.0, 6.7.5 and 6.7.7 compilers build the repro and exit 11 too.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
(roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never 7.x (the fix is the user's call, asked at
that release's open: programs that compile today are refused).
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-6a (slices refused as type arguments; gate row K3 in
`tests/gates/frontend/slice_position_refused.sh` pins `g<slice<u8>>(0)` compiling, "reported, unchanged").
**Severity:** Medium — a misspelled or unknown type compiles silently and the code runs at the wrong type (8-byte
`T`, the base's layout).
**Affects:** cycc 6.6.20 – 6.7.8 (every target; 6.6.10 cannot compile the repro's `sizeof(T)`)

## Summary

A type argument is a struct, a scalar, a type parameter in scope — or, followed by `<`, a generic struct
instantiation. Since 6.6.8 an unknown plain name is refused by name ("unknown type 'X' as a type argument"). An
unknown name FOLLOWED BY `<..>` is not: the parser asks whether it names a generic struct, and when it does not,
classifies the name as a return type, skips its argument list and returns the class — 0 for an unknown name (and
for `slice`), which is "unbound": the base instance. The same class as the 6.6.8 defect, through the one branch
that fix did not reach. The sibling issue linked above is the parameter-annotation path (`Mp<K, V>` with `K` / `V`
undeclared), a different site.

## Reproduction

`docs/development/issues/repros/2026-10-10-unknown-generic-name-accepted-as-type-argument.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn g<T>(x): i64 { return sizeof(T); }
fn main(): i64 {
    var c: Box<Nonexist<u8>>;            # accepted (`Box<Nonexist>` is refused by name)
    c.n = 3;
    return g<Nonexist<u8>>(0) + c.n;     # accepted: runs the i64 base, sizeof(T) = 8; `g<Nonexist>(0)` is refused
}
var rc = main();
syscall(60, rc);
```

```
actual:   compile rc 0; exit 11
expected: error: unknown type 'Nonexist' as a type argument (both lines), as for the spelling without `<u8>`;
          for `slice<u8>`, the 6.7.8 refusal the `[u8]` spelling gets ("a slice cannot be a type argument")
```

## Root cause

`_parse_one_type_arg` (`src/frontend/parse_fn.cyr:11171`): when the name is followed by `<` and is not a generic
struct (`base_sid <= 0 || GSTP(..) == 0`), it calls `_classify_return_type`, `_reject_special_type_arg` (which
refuses only the special classes), skips the nested list (`_skip_targ_list`) and returns the class — 0 for an
unknown name, never reported. The no-`<` arm (`_type_arg_leaf`) is the one that refuses an unknown name.

## Proposed fix

In that branch, refuse a name that is neither a generic struct nor a known type taking arguments (`Vec<..>` and the
other classified generics stay accepted, as today) with the same message as the plain unknown name, and route
`slice<..>` to the 6.7.8 slice refusal (`_sl_err`, "a slice cannot be a type argument"). Rows: the repro (both
lines refused, once each); `g<slice<u8>>(0)` (K3 inverted) and `Box<slice<u8>>`; nested `Box<Box<Nonexist<u8>>>`;
`g<Vec<i64>>(0)` and `Box<Box<Pt>>` unchanged; a type parameter written with arguments (`T<u8>` inside a generic —
not measured here; measure it at the fix).

## Consumer-side workaround

None needed — write the type argument correctly; the compiler will not catch this misspelling.
