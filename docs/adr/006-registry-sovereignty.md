# ADR-006: Registry Sovereignty — Ark Replaces crates.io as Default

**Status**: Implemented
**Date**: 2026-04-03
**Deciders**: Robert MacCracken
**Renumbered**: 2026-05-05 (was ADR-001 in the dropped `docs/architecture/adr/`
sub-tree; consolidated into `docs/adr/` at v5.8.x cycle close. ADR-001
through ADR-005 already existed in `docs/adr/`.)

## Context

Cargo hardcodes crates.io as the default registry in ~20 locations across 8 files. This means:
- `cargo publish` with no flags targets crates.io
- All deps without explicit registry default to crates.io
- Git/path deps are rejected during publish even if the dep is `publish = false`
- Cross-registry deps are blocked when publishing to crates.io

Cyrius requires sovereign package management through Ark, where names belong to builders and there is no external governance dependency.

## Decision

We patch cargo to make Ark the default registry while keeping crates.io as a recognized fallback. Specifically:

### Phase 1a — Constants and Defaults

**New constants** added alongside existing ones in `sources/registry/mod.rs`:
- `ARK_INDEX` = `https://github.com/aspect-os/ark-index`
- `ARK_HTTP_INDEX` = `sparse+https://ark.agnosticos.org/index/`
- `ARK_REGISTRY` = `ark`
- `ARK_DOMAIN` = `ark.agnosticos.org`

**Default fallbacks** changed (8 locations):
- `get_initial_source_id()` → tries Ark first, falls back to crates.io
- `validate_registry()` → defaults to `ARK_REGISTRY`
- `SourceConfigMap::empty()` → registers Ark as primary built-in
- `prepare_transmit()` → dep default registry is Ark

**New methods** on `SourceId`:
- `ark()`, `ark_maybe_sparse_http()` — factory methods for Ark source IDs
- `is_ark()`, `is_default_registry()` — detection methods

### Phase 1b — Relaxed Publish Validation

**`verify_dependencies()`**: For non-crates.io registries (including Ark), git/path deps are allowed. The cross-registry block only applies when publishing TO crates.io.

**`check_dep_has_version()`**: Git/path deps without version requirements are allowed when they don't target crates.io. This means `publish = false` deps with only a path or git source work fine.

## Files Changed

| File | Changes |
|------|---------|
| `sources/registry/mod.rs` | Added ARK_* constants |
| `sources/mod.rs` | Exported ARK_* constants |
| `core/source_id.rs` | Added `ark()`, `ark_maybe_sparse_http()`, `is_ark()`, `is_default_registry()`, updated `alt_registry()` |
| `sources/config.rs` | Registered Ark in `SourceConfigMap::empty()` |
| `ops/registry/mod.rs` | Default source ID falls back to Ark |
| `ops/registry/publish.rs` | Default registry is Ark, relaxed dep validation |
| `ops/mod.rs` | Relaxed `check_dep_has_version()` for non-crates.io |

## Consequences

### Positive
- `cargo publish` defaults to Ark — no `--registry` flag needed
- Git/path deps work when publishing to Ark
- `publish = false` deps no longer require registry versions
- All existing Rust code still compiles (backward compatible)
- `--registry crates-io` still works for publishing to crates.io

### Negative
- Ark doesn't exist yet as a live service — these changes are structural preparation
- Diverges from upstream cargo (must be maintained across upstream merges)

### Neutral
- crates.io is still fully functional as an explicit registry
- The registry infrastructure (RegistrySource, RegistryData) is untouched — it's generic

## Notes

This is the minimal cut. No registry infrastructure was modified — only defaults and validation policy. The 4 constants + 8 default changes + 2 validation relaxations are the complete diff.
