# `cyrius deps` pulls a declared stdlib leaf from a NAMED DEP's own `lib/`, silently reverting the pinned snapshot's copy

**Status:** ✅ **FIXED at v6.5.39 — CLOSED.** `cyrius deps` now refuses to overwrite a stdlib leaf that Phase 1 already copied from the pinned snapshot, and says so, naming both the kept path and the skipped artifact. Both acceptance criteria pass: `deps` preserves the snapshot, and `lib sync` -> `deps` no longer reverts. Gate: `tests/gates/toolchain/deps_stdlib_leaf_not_clobbered.sh` (5 axes, hermetic — path deps only, no git or network; mutation-proven three ways, each reddening a different axis).

⚠ **THIS FILING'S NAMED MECHANISM WAS WRONG, and fixing what it points at would have changed nothing.** It concluded "from the named dep's own `lib/`" from a byte-identity, but several files share those bytes; a marker probe (a transitive tag present only in the git cache) shows the real source is the dep's **resolved artifact**, `~/.cyrius/deps/<name>/<tag>/dist/<name>.cyr`. The filing's second-ranked candidate — the fallback in `_dep_pull_module` — is not on this path at all.

⚠ **Two further corrections worth keeping.** (1) The report reads as though the consumer's direct dep is the culprit; in the filed chain the colliding package is **three hops down** and appears in no manifest the consumer authored, so no manifest edit on their side could have fixed it. (2) The "⚠ ORDER decides the winner / `_dep_stdlib_seen`" note aims at the wrong guard: for the transitive shape the outcome is **not** order-dependent, because Phase 3 is structurally last and the named dep always wins. `_dep_stdlib_seen`'s actual role is the opposite of what that note implies — it is what stops a later snapshot pull from repairing the file.

⭐ **The filing's own ⚠ about the version regex was CORRECT and was used:** `v?[0-9]+\.[0-9]+\.[0-9]+` matches an earlier unrelated string in these bundles, so the new warning names exact PATHS rather than parsed versions.
consumer (shabdakosh 3.0.6 resolving `[deps.svara]`).
**Placement:** `cbt/deps.cyr` — the named-dep / sidecar leaf-pull path. Next batch after `.37`.
**Severity:** **High.** Silent, self-reverting, and it propagates a stale copy of any folded
stdlib module — including security fixes — into every consumer of a dep whose vendored `lib/`
has fallen behind. `cyrius lib sync` cannot fix it: the next `cyrius deps` undoes the fix.
**Affects:** cycc 6.5.37 and, on the evidence below, every earlier release with named deps.

## Summary

A module declared in `[deps] stdlib` must be vendored from the **pinned snapshot**
(`~/.cyrius/versions/<pin>/lib/`). Instead, when a named dep also requires that leaf, the
resolver ends up copying the dep's OWN `lib/<leaf>.cyr` over it.

The two commands actively fight, and `deps` wins:

```
$ cd ~/Repos/shabdakosh                       # sakshi is in [deps] stdlib
  start              lib/sakshi.cyr  ->  2.4.11   61608 B
$ cyrius lib sync
  after 'lib sync'   lib/sakshi.cyr  ->  2.4.12   62400 B    # correct, from the snapshot
$ cyrius deps
  after 'deps'       lib/sakshi.cyr  ->  2.4.11   61608 B    # REVERTED
```

The reverted file is **byte-identical to `../svara/lib/sakshi.cyr`**, and **not** to
`~/.cyrius/versions/6.5.37/lib/sakshi.cyr`:

```
$ cmp -s lib/sakshi.cyr ../svara/lib/sakshi.cyr                    # -> identical
$ cmp -s lib/sakshi.cyr ~/.cyrius/versions/6.5.37/lib/sakshi.cyr   # -> differs
```

Every source of truth says 2.4.12 — upstream `sakshi/VERSION`, `sakshi/dist/sakshi.cyr`,
`cyrius/lib/sakshi.cyr`, and the 6.5.37 snapshot. Only `svara`'s vendored copy is 2.4.11, and
that is the one that lands.

## Why it matters beyond a version number

sakshi **2.4.12** fixes a negative-depth buffer underflow in `sakshi_span_enter` (the guard
checked only the upper bound, so a negative depth wrote *before* `_sk_span_stack`). A consumer
that declares `sakshi` in `[deps] stdlib`, pins 6.5.37, and runs `cyrius deps` gets **2.4.11**
— without that fix — and nothing in the output says so beyond a shadow-lib warning whose
suggested remedy (`cyrius lib sync`) is undone by the very next resolve.

⭐ **This is the same family as the v6.5.37 snapshot-corruption incident**: dep resolution
treating a repo-local copy as authoritative over the version-pinned snapshot. That one wrote
*into* the snapshot through a symlink; this one reads *around* it. Both make the pin advisory.

## Reproduction

Any consumer that (a) declares a leaf in `[deps] stdlib` and (b) has a `[deps.X]` named dep
whose own `lib/` carries an older copy of that same leaf. Live instance:

- consumer: `~/Repos/shabdakosh` (`sakshi` in `[deps] stdlib`, `[deps.svara] path = "../svara"`)
- dep: `~/Repos/svara` (`lib/sakshi.cyr` at 2.4.11)
- pin: `cyrius = "6.5.37"` (snapshot ships sakshi 2.4.12)

Run `cyrius lib sync` then `cyrius deps`, checking the header
(`Bundled distribution of sakshi vX.Y.Z`) after each.

⚠ **Use that header, not a bare version-looking regex.** `grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+'`
matches an unrelated string earlier in the file and reports 2.4.12 for a 2.4.11 file — it cost
a wrong reading while diagnosing this.

## Where to look

Not yet root-caused; these are the candidates, in the order worth checking:

1. `_dep_pull_leaves` / `_dep_copy_stdlib_recursive` — confirm `stdlib_dir` is the snapshot on
   the sidecar-driven path. `_dep_find_stdlib_dir()` looks correct in isolation (branch (a) is
   gated on `_dep_is_cyrius_source_repo()`, branch (b) resolves the pin), so the suspect is a
   caller passing a different directory.
2. The module-copy fallback (`cbt/deps.cyr`, the `[deps.X] modules` loop): when the declared
   module path is absent it retries `<dep_path>/lib/<basename>`. Verify it cannot fire for a
   stdlib leaf name.
3. `_dep_pull_submodule` for `modular` deps, which pulls from `<dep_path>/dist/<name>/`.

⚠ The `_dep_stdlib_seen` guard means ORDER decides the winner, so the fix must not simply be
"copy again later" — that trades one silent overwrite for another. v6.5.28 already shipped one
ordering artifact in this exact guard.

## Acceptance

- After `cyrius deps` in the shabdakosh/svara shape above, `lib/sakshi.cyr` is byte-identical
  to `~/.cyrius/versions/<pin>/lib/sakshi.cyr`.
- `lib sync` followed by `deps` is idempotent — the second command does not revert the first.
- A gate covering it: a fixture consumer with a named dep whose `lib/` holds a deliberately
  older copy of a declared stdlib leaf, asserting the SNAPSHOT copy wins. Mutation-prove by
  reverting the fix; the naive "assert the version string" form passes against the defect if it
  greps the wrong marker (see the warning above), so assert **byte-identity with the snapshot**.

## Discovered

2026-09-01, while re-pinning shabdakosh to 6.5.37 for the A9 cross-repo sweep. Surfaced by the
`./lib/ shadows version-pinned` warning refusing to clear after a successful `lib sync`.
