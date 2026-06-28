# v6.2.x closeout — deferred items (→ v6.3.x)

**Filed:** 2026-06-27 (v6.2.51 closeout audit) · **Status:** RESOLVED in v6.2.52
EXCEPT the var-table migration → **v6.3.0** (user 2026-06-28).

The pre-v6.3.0 closeout's 6-dimension judgment-pass audit surfaced these. **v6.2.52
landed items 2 + 3 + the exit-code question (fail-loud); item 1 (var-table) opens
v6.3.0 — it changes codegen, can't be a byte-identical closeout patch.** The one P1
the audit found (CVE-32 modular path-traversal) was fixed in v6.2.51.

## 1. Finish the var-table growable migration — → **v6.3.0** (the minor opener; user 2026-06-28)
The v6.2.0 Phase-0 growable migration left the var tables fixed: `var_noffs` /
`var_sizes` / `var_types` (0x11A000 / 0x12A000 / 0x13A000, `SVCNT` cap 8192 at
`src/common/util.cyr:24`) are the last compile-time tables not migrated to the
growable scheme. Migrating them **changes codegen → breaks byte-identical
self-host**, so it is NOT closeout-safe. Not pressured this minor (element-typed
arrays consume 1 `SVCNT` slot via `vcnt+1`, not N). Pair with the var-table SoA
cluster as the consolidation target.

## 2. `distlib --modular` basename-collision guard — ✅ RESOLVED v6.2.52
`_distlib_modular_emit` (cbt/commands.cyr) keys per-module output + index entries
by basename. Two `[lib].modules` entries with the same basename in different
subdirs (`src/a/x.cyr` + `src/b/x.cyr`) overwrite each other's
`dist/<pkg>/x.cyr` (O_TRUNC) and emit duplicate `x = [...]` index keys; the
resolver `_dep_read_index_deps` (cbt/deps.cyr) is first-match-wins, so the second
module's transitive deps are lost. No live `--modular` consumers yet (.50), so no
rush. Fix: detect a duplicate basename → `_err_ctx` + non-zero, or qualify the
output name with the subdir.

## 3. Cosmetic ~4-byte heap over-read on manifest prefix scans — ✅ RESOLVED v6.2.52
The `[deps.` / name prefix scans (cbt/commands.cyr `_distlib_named_deps`, and the
`pi + 4` / `ndi + 6` reads) can read a few bytes past the 32KB manifest buffer
tail. The bump-arena means **no segfault**, and a real `cyrius.cyml` is far under
32KB, so it never bites — but guard with `ndi + 6 <= mlen` / `pi + 4 <= mlen` on
the next cbt cleanup pass.

## Open question — ✅ RESOLVED v6.2.52: make it fail-loud (user 2026-06-28)
`cyrius distlib` now exits **non-zero** when a `modules=` entry is missing (both
the flat and `--modular` paths), matching the consumer side (`cyrius deps`).
Was a warning + exit 0. CLI-only / byte-identical. Gate: `_distlib_failloud_gate`.
