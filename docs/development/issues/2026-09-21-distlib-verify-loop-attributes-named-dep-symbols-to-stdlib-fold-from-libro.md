# `cyrius distlib`'s verify loop attributes a named dep's symbols to the stdlib fold, and records the fold's leaves as the consumer's — OPEN

**Status:** 🟡 **OPEN** — over-reports one leaf on libro; the sidecar still resolves, so no consumer is blocked.
**Placement:** unpinned — 6.x-line backlog (distlib sidecar family; see the 2026-08-07 and 2026-09-11 archived filings).
**Discovered:** 2026-09-21 during libro's 2.10.2 bump to cyrius 6.6.6 / sigil 3.12.18 / patra 1.14.3
**Severity:** Low
**Affects:** the mechanism since 6.5.37 (the compile-verified sidecar); first visible at 6.6.6, whose sigil 3.12.18 fold is the first monolith to need a leaf the thin surface does not. libro's sidecar at 6.6.2 (sigil 3.12.17 fold) was clean for the same source.

## Summary

libro pulls sigil as a **thin** named dep (`dist/sigil-mldsa.cyr` + `src/{sha_ni,sha256,hex}.cyr`),
never the monolithic `lib/sigil.cyr` fold. `cyrius distlib` at 6.6.6 writes `sys` into
`dist/libro.deps` (27 → 28 leaves). Nothing in `dist/libro.cyr` references a `lib/sys.cyr` symbol:

```sh
for s in $(grep -oE '^(fn|var) [a-z_0-9]+' ~/.cyrius/versions/6.6.6/lib/sys.cyr | awk '{print $2}'); do
  grep -qw "$s" dist/libro.cyr && echo "$s"; done      # prints nothing
```

The leaf is an artifact of `_distlib_verify_leaves` (cbt/commands.cyr): the verify compile
splices the stdlib leaves + the bundle, but **not the named deps' resolved modules**, so every
symbol the bundle takes from the thin sigil surface (`SIG_ALG_HYBRID`, `ed25519_sign`,
`mldsa65_verify`, …) reads as undefined. `_distlib_leaf_defining` attributes them to
`lib/sigil.cyr` — the monolith — which round 1 splices in; round 2 then sees the monolith's
own `sys_uname` / `uname_release` (new in sigil 3.12.18's `sysinfo`) undefined and adds `sys`.
The sidecar writer drops `sigil` again as a named dep but keeps `sys`. Verbose output shows
the shape: `sidecar: re-added 2 leaf(s) the inference missed (compile-verified)` — the two
are `sigil` (filtered at write) and `sys` (kept).

The recorded requirement is therefore what the **fold** needs, not what the **bundle** needs.
On libro it is one harmless stdlib file. On a consumer whose thin dep's monolith pulls a
heavier leaf (tls, net, http) the over-report would copy and auto-include that leaf into every
downstream build.

## Reproduction

libro at tag `2.10.2` (or any commit after the 6.6.6 bump), toolchain 6.6.6:

```sh
rm -rf lib && cyrius lib sync --full && cyrius deps
cyrius distlib -v 2>&1 | grep sidecar
#   sidecar: +5 leaf/leaves from the declared [deps] stdlib
#   sidecar: re-added 2 leaf(s) the inference missed (compile-verified)
tail -1 dist/libro.deps      # sys
```

Expected: 27 leaves, matching `[deps].stdlib`; `sys` absent. Same result in a sibling-free
directory with sigil/patra resolved from git, so it is not a `path` artifact.

## Root cause (speculation, from reading cbt/commands.cyr at d55bd7ed)

`_distlib_verify_leaves` builds its entry from `root/<leaf>.cyr` for each leaf plus the bundle.
The named deps that `cyrius deps` already resolved into `lib/` (here `lib/sigil-mldsa.cyr`,
`lib/sigil_sha_ni.cyr`, `lib/sigil_sha256.cyr`, `lib/sigil_hex.cyr`, `lib/patra.cyr`) are not
spliced, so their symbols are free for `_distlib_leaf_defining` to claim on behalf of a
same-named stdlib fold. Splicing the resolved named-dep modules into the verify entry (they
are exactly what a consumer's build will have in scope) would leave those symbols defined and
the loop would only ever add leaves the bundle itself needs. Alternatively, skip attribution
to any leaf whose name is a named dep of the manifest — the writer already knows that set.

## Acceptance criteria

- libro's `cyrius distlib` emits 27 leaves with no `sys`.
- A bundle that genuinely calls a `lib/sys.cyr` function still gets `sys` re-added.
