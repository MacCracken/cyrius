# ADR-004: Convention-Based Method and Trait Dispatch

**Status**: Accepted — **amended by [ADR-007](007-traits.md) (6.7.0)**: real `trait` declarations, checked impls, defaults, inherent impls, the `T_Trait_m` qualified names and the typed `self`. The convention below (static, by-name dispatch) stands.
**Date**: 2026-04-05
**Context**: Need OOP-like method calls without a type system or vtable infrastructure.

## Decision

Method dispatch uses naming conventions: `point.scale(2)` resolves to `Point_scale(&point, 2)`. No vtables, no dynamic dispatch, no runtime type checks.

## Rationale

- **Zero overhead**: Direct function call, no indirection
- **No type system needed**: The compiler just mangles names at compile time
- **Extensible**: Trait impls will add trait name to mangling: `Point_Display_format`
- **Already proven**: 5 crate rewrites use this pattern successfully

## Convention

```
struct Point { x; y; }
fn Point_scale(self, factor) { ... }    # Define
point.scale(2);                          # Call → Point_scale(&point, 2)
```

- `self` is always the first parameter (pointer to struct)
- The compiler builds `StructName_method` in tok_names scratch area (offset 30000)
- Statement context: parser peeks ahead after `ident.name` to distinguish method call from field store

## Consequences

- Method names must be globally unique per struct (no overloading)
- No dynamic dispatch — caller must know the concrete type
- Trait objects (fat pointers) remain a library pattern (trait.cyr), not compiler-native
- Future `impl` blocks will be syntactic sugar over this convention
