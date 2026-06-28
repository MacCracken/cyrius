# v6.2.x closeout — deferred items (→ v6.3.x)

**Filed:** 2026-06-27 (v6.2.51 closeout audit) · **Status:** DEFERRED → v6.3.x

The pre-v6.3.0 closeout's 6-dimension judgment-pass audit surfaced these; none
are closeout-safe (each changes byte-identical codegen, needs its own slot, or is
cosmetic). The one P1 it found (CVE-32 modular path-traversal) was fixed in v6.2.51.

## 1. Finish the var-table growable migration (P3 → v6.3.x, paired with AR-03)
The v6.2.0 Phase-0 growable migration left the var tables fixed: `var_noffs` /
`var_sizes` / `var_types` (0x11A000 / 0x12A000 / 0x13A000, `SVCNT` cap 8192 at
`src/common/util.cyr:24`) are the last compile-time tables not migrated to the
growable scheme. Migrating them **changes codegen → breaks byte-identical
self-host**, so it is NOT closeout-safe. Not pressured this minor (element-typed
arrays consume 1 `SVCNT` slot via `vcnt+1`, not N). Pair with the var-table SoA
cluster as the consolidation target.

## 2. `distlib --modular` basename-collision guard (P3 → v6.3.x)
`_distlib_modular_emit` (cbt/commands.cyr) keys per-module output + index entries
by basename. Two `[lib].modules` entries with the same basename in different
subdirs (`src/a/x.cyr` + `src/b/x.cyr`) overwrite each other's
`dist/<pkg>/x.cyr` (O_TRUNC) and emit duplicate `x = [...]` index keys; the
resolver `_dep_read_index_deps` (cbt/deps.cyr) is first-match-wins, so the second
module's transitive deps are lost. No live `--modular` consumers yet (.50), so no
rush. Fix: detect a duplicate basename → `_err_ctx` + non-zero, or qualify the
output name with the subdir.

## 3. Cosmetic ~4-byte heap over-read on manifest prefix scans (nit → v6.3.x)
The `[deps.` / name prefix scans (cbt/commands.cyr `_distlib_named_deps`, and the
`pi + 4` / `ndi + 6` reads) can read a few bytes past the 32KB manifest buffer
tail. The bump-arena means **no segfault**, and a real `cyrius.cyml` is far under
32KB, so it never bites — but guard with `ndi + 6 <= mlen` / `pi + 4 <= mlen` on
the next cbt cleanup pass.

## Open question (raised to user, not yet decided)
Should `cyrius distlib` exit **non-zero** when a `modules=` entry is missing?
Today the producer reports success (exit 0) + a warning, while the consumer side
(`cyrius deps`) IS fail-loud — a producer/consumer exit-code asymmetry. Making it
fail-loud is CLI-only / byte-identical but an **exit-code behavior change** that
could trip CI tolerant of the warning. User to decide (own follow-up, not folded
into the byte-identical closeout).
