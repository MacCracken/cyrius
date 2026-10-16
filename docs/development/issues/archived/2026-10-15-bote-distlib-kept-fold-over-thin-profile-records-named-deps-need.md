# `cyrius distlib` records a named dep's need as the bundle's own when `cyrius deps` kept the fold over that dep's thin profile: bote-core's sidecar gets `sigil` + `ct` — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-13: both kept-fold branches in `cbt/deps.cyr` — the named-dep module loop's, and `_dep_pull_submodule`'s `modular` form — now record the fold as pulled for the named dep (`_dep_note_nd_leaf`). So `cyrius distlib`'s verify splices the fold and its include closure as the dep's, and records neither; the bundle's own use is still recorded. Measured on the triage's synthetic analogue, without opening the producer's repository: before, `ct recorded for 'ct_eq_bytes_lens'` and dist/pp.deps = `ct`; after, `ct in scope (a named dep's)` and no sidecar. No decision needed. Rows: `distlib_named_dep_transitive.sh` K1 (a `modules` thin profile), K2 (a `modular` sub-module), K3 (a leaf the fold includes), K4 (the bundle's own call, still recorded); mutations RED. A producer in the filed shape gets a smaller sidecar and requires block at its next `cyrius distlib`. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-15 on the published 6.6.20 (bote 3.3.17's regen). The branch that causes it
is unchanged at HEAD `65cb14c6` (6.7.12 open).
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
[`2026-10-12-distlib-records-a-named-deps-transitive-leaf-as-the-bundles-own.md`](./2026-10-12-distlib-records-a-named-deps-transitive-leaf-as-the-bundles-own.md);
the same tools-lane slot would take both.
**Discovered:** 2026-10-15, regenerating bote's `dist/` at its 6.6.14 → 6.6.20 pin move (bote 3.3.17).
**Severity:** Low — every consumer still builds and runs. But a transport-free consumer of `dist/bote-core.cyr` is
held on the 28k-line sigil fold where libro's thin sigil would do, measured at +870 KB for a one-call consumer.
**Affects:** 6.6.20 (verified). Introduced by the interaction of 6.6.11 (S2, the fold is kept over a thin profile of
a package that is a stdlib leaf) with 6.6.18 (P4 option 2, the compile-verify is the only authority for a sidecar)
and a named dep shrinking its own sidecar under 6.6.18 (libro 2.10.7: 27 leaves → `hashmap`).

## Summary

bote declares `sigil` in its `[deps] stdlib` and `libro` as a named dep. libro declares a thin `deps.sigil`
selection (`dist/sigil-mldsa.cyr` + `src/sha_ni.cyr` / `sha256.cyr` / `hex.cyr`). Since 6.6.11, `cyrius deps` keeps
the fold over that thin profile in bote (`note: [deps.sigil] … not vendored — 'sigil' is a stdlib leaf here`). From
libro 2.10.7, libro's sidecar is just `hashmap`: its sigil needs are carried by `sigil-mldsa.cyr`'s own requires
block. In bote that file is never vendored. So when `cyrius distlib core` compiles the core bundle with the named
deps' modules in scope, libro's `ct_eq_bytes_lens` (`lib/libro.cyr:234`) and `SIG_ALG_ED25519` (`:3873`) are
undefined. The verify then records `ct` and `sigil` as needs of **bote-core**, which never references libro or sigil.

```
  sidecar verify round 1: sigil recorded for 'SIG_ALG_ED25519' (every target)
  sidecar verify round 1: ct recorded for 'ct_eq_bytes_lens' (every target)
dist/bote-core.deps: hashmap bayan sigil ct
```

Under 6.6.14 the same profile was `hashmap bayan string alloc vec str fnptr chrono`, with no sigil.

The full bundle (`dist/bote.cyr`) is not visibly affected: its `ws_server` leaf brings the sigil fold through
`sandhi`'s requires, so nothing is left undefined to record.

## Reproduction

On bote's tree at 3.3.17 (cyrius 6.6.20, `deps.libro` 2.10.8, `deps.majra` 2.9.3):

```sh
rm -rf lib && cyrius lib sync --full && cyrius deps
cyrius distlib core -v 2>&1 | grep -E 'recorded|in scope'
grep -v '^#' dist/bote-core.deps        # hashmap bayan sigil ct
```

What it costs a consumer. A scratch consumer of the core bundle declares
`stdlib = ["string", "fmt", "alloc", "vec", "str", "syscalls", "io", "freelist"]` and
`[deps.bote] modules = ["dist/bote-core.cyr"]`. Its `main` makes a registry and a dispatcher, then answers one
`ping` through `codec_process_message`. All three builds below print 0 `undefined` lines and print the same
`{"jsonrpc":"2.0","id":1,"result":{}}`:

| bote core bundle | consumer pin | sigil in the consumer's unit | binary |
|---|---|---|---|
| 3.3.16 (`hashmap bayan string alloc vec str fnptr chrono`; libro 2.10.6's 27-leaf sidecar brings sigil) | 6.6.14 | the fold | 2,628,808 B |
| 3.3.17 as `distlib` writes it (`hashmap bayan sigil ct`) | 6.6.20 | the fold | 2,079,184 B |
| 3.3.17 with `sigil` and `ct` removed from the requires block and the sidecar | 6.6.20 | libro's thin `sigil-mldsa` 3.13.10, vendored because `sigil` is no longer a leaf there | 1,209,096 B |

The third row is what the sidecar should give. libro's needs are met in the consumer through libro's own resolution:
the thin profile and its requires block (`ct`, `keccak`, `random`, `thread_local`, …).

## Root cause

`cbt/deps.cyr`, the module loop (HEAD line 3522, 6.6.20 line 2510):

```
var _kf = _dep_keep_fold_over_profile(dep_name, dst, wdst, mod_path);
if (_kf < 0) { return 1; }
if (_kf == 1) {
    dep_had_success = 1;
    mi = mi + 1;
    continue;          # ← the fold now stands in for this named dep's module, but nothing records that
}
```

The fold is already in scope as a stdlib leaf. But it is not pushed to `_dep_nd_leaves`, the stdlib leaves pulled
on behalf of named deps, and nothing stands in for the skipped module in `_dep_nd_modules`. distlib's verify splices
`_dep_nd_leaves` without recording them (the 6.6.9 rule: "a named dep's own need is kept out of the sidecar"). It
never learns that the fold is libro's sigil, so it treats libro's sigil symbols as unowned and records them.

## Proposed fix

In the `_kf == 1` branch, record the fold leaf (`dep_name`) through the same once-only helper that records a leaf
pulled for a named dep (`cbt/deps.cyr`, "Record a stdlib leaf pulled on behalf of a named dep", ~line 1105 at
6.6.20). The verify then splices `lib/sigil.cyr` as libro's, and records neither it nor what it reaches (`ct`).
That matches what happens in a consumer: there, libro's sigil arrives through libro, as the fold or the thin
profile, never through bote-core's sidecar.

A regression row: a producer that declares leaf `L` and a named dep with a thin `deps.L` selection whose module
calls into `L`. The producer's own pure profile must get an empty sidecar.

## Consumer-side workaround

None shipped, by choice. bote's CI gates `dist/` byte-for-byte against `cyrius distlib`, and hand-editing a
generated sidecar is the drift that gate exists to stop. bote 3.3.17 ships `hashmap bayan sigil ct`. Against 3.3.16
this costs a core consumer nothing it was not already paying (row 1 vs row 2). It only blocks the drop to the thin
sigil (row 3).

## Severity rationale

Low: nothing fails, and the over-report is no worse than the leaves libro's old sidecar used to put in scope. Raise it
if a second producer meets the shape: any package that lists a fold leaf and also depends on a named dep with a thin
profile of the same package. sigil thin profiles are the common case: libro, and through libro every libro consumer
that publishes a bundle.

## Related

- [`2026-10-12-distlib-records-a-named-deps-transitive-leaf-as-the-bundles-own.md`](./2026-10-12-distlib-records-a-named-deps-transitive-leaf-as-the-bundles-own.md)
  — the same class (a named dep's need written into the bundle's sidecar), a different hole: there the verify
  misses a dep leaf's transitive include (`tagged` → `boxed`). Its proposed include-closure fix would not reach this
  case, because libro's sidecar never names `sigil` at all.
- `docs/development/ecosystem-migration-6.6.18.md` — "a sidecar names exactly the leaves the bundle needs".

## Pointers

- bote `CHANGELOG.md` [3.3.17] (the measurement above) and `DEPS-PATTERN.md` (the core-profile contract).
- libro `CHANGELOG.md` [2.10.7]: the 27 → 1 sidecar shrink, and "sigil-mldsa and patra now carry their own
  `# Requires` blocks, and those supply everything else".
