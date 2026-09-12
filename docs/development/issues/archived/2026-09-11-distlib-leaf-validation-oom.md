# `cyrius distlib` allocates ~30 GB in leaf validation and OOM-kills the CI runner

**Status:** ✅ **FIXED in v6.6.3** — the stdlib snapshot is read ONCE per root instead of
once per undefined symbol. bote's full profile: **20,320 MB → 57 MB**, and it now completes
inside a 4 GB cap where it previously died at 20 GB. Gated by
`tests/gates/toolchain/distlib_leaf_lookup_memory.sh`, mutation-proven.
**Discovered:** 2026-09-11, migrating bote to 6.6.2 during the ecosystem sweep.
**Severity:** High — **takes the whole CI runner down, and the log says nothing.**
GitHub reports the kernel OOM-kill as `Error: The operation was canceled`, two steps
before any assertion runs, so it reads as an infrastructure hiccup rather than a
toolchain defect. It cost a release cut to diagnose.

## Symptom

`cyrius distlib` on bote's default (full) profile peaks at **RSS 31,214 MB** — measured
on a 59 GB box, where it survives by swapping and takes ~125 s. A standard GitHub runner
has ~7 GB, so the kernel OOM-killer takes the runner down mid-step. The step's existing
`cyrius distlib || true` does not help: the process is not exiting non-zero, the *runner*
is being killed.

The blow-up is in the **leaf-validation** pass — `_distlib_verify_leaves`
(`cbt/commands.cyr:2586`), which splices every stdlib leaf plus the emitted bundle into
one buffer and compiles it to collect undefined symbols.

## It is NOT driven by module count

This is the part worth not re-deriving. Measured under `ulimit -v 7GB` on the same
6.6.2 toolchain:

| repo | `[lib]` modules | leaves | result |
|---|---|---|---|
| kavach | 44 | 20 | **completes** |
| sankhya | 36 | 20 | **completes** |
| hisab | 35 | 15 | **completes** |
| t-ron | 18 | 28 | completes, peak **208 MB** |
| **bote (full)** | **30** | **41** | **dies** |
| bote (`[lib.core]`) | 12 | 11 | completes, `rc=0` inside a **2 GB** cap |

Three repos with *larger* profiles finish. What bote's full profile has and they do not
is **`tls_native`** in its leaf set (with `ws_server`, `sigil`, `sha1`, `sync`), dragged
in by `transport_http` / `transport_ws` / `transport_streamable` / `bridge`. bote's own
`core` profile excludes exactly those modules and finishes in 2 GB. **The trigger is a
specific leaf graph, not size.**

## Reproduce

```sh
cd ~/Repos/bote && git checkout 3.3.8
( ulimit -v 7340032; cyrius distlib ); echo "rc=$?"    # rc=139
( ulimit -v 2097152; cyrius distlib core ); echo "rc=$?"  # rc=0  — the control
```

Vary the pin in `cyrius.cyml` to 6.6.1 or 6.6.0 and the full profile dies identically,
so the regression predates 6.6.0. bote 3.3.7 shipped green at pin **6.5.35**, which
brackets it to **6.5.36 – 6.6.0**.

## The bundle is emitted BEFORE the validation pass

This is what makes a workaround possible, and it is worth preserving if the pass is
restructured. At caps of **2, 3, 4 and 6 GB** the emitted `dist/bote.cyr` came out
**byte-identical every time**. So bounding the address space converts a runner-killing
OOM into a contained non-zero exit while still producing a correct bundle, and a
freshness gate (`git diff --exit-code dist/…`) — the thing those CI steps actually
assert — keeps working.

## Consumer stopgap (shipped, bote 3.3.8)

Both `ci.yml` and `release.yml` wrap the full-profile call:

```sh
( ulimit -v 2097152; cyrius distlib ) \
  || echo "::warning::distlib (full) hit the 2 GB cap - bundle emitted, leaf validation skipped"
```

The `core` profile is left uncapped in effect — it completes inside the cap anyway, so it
keeps full validation. The cost of the stopgap is that the full profile's undefined-symbol
report is skipped; that output was already treated as informational by those gates
("the stdlib is supplied by the consumer"), so nothing they assert is lost.

## Blast radius

Ten repos run `cyrius distlib` in CI with a `[lib]` profile at or above bote's 30:
sigil 65, mabda 56, kavach 44, avatara 43, sandhi 43, naad 39, ai-hwaccel 38, goonj 37,
sankhya 36, hisab 35. kavach / sankhya / hisab are measured above and are fine. The
remaining six (sigil, mabda, avatara, sandhi, naad, goonj, ai-hwaccel) are **not yet
measured** and are still on 6.5.x / 6.6.0 — any of them whose leaf graph reaches
`tls_native` will hit this the moment it migrates. Worth measuring before those
migrations rather than one red release at a time.

## Acceptance

- `cyrius distlib` on bote 3.3.8's full profile completes inside a 7 GB address space.
- The bundle it emits stays byte-identical to the one the capped run produces today.
- The `ulimit -v` wrappers come out of bote's two workflows in the same change.

---

## Root cause (v6.6.3) — it was never the compile

The filing located the blow-up in the leaf-validation pass, which is right, but the cost is
NOT in the `compile()` it performs. `compile()` forks and execs a child `cycc`, so that
memory is reclaimed at every round. Measured live: the 20 GB sits in the **`cyrius` CLI
process itself** (`VmData: 20,709,728 kB`), not in any child.

`_distlib_leaf_defining(root, name)` `dir_list`s the whole stdlib snapshot and `alloc`s +
reads **every** `.cyr` file — and the fixpoint loop calls it **once per undefined symbol**.
cyrius's allocator is an arena that never frees, so every call RETAINS another full copy:

    110 files / 7 MB snapshot  x  ~2,900 undefined symbols  ≈  20 GB

⭐ **That is exactly why it tracked the leaf graph and not module count**, which the filing
measured but could not explain: what scales is the number of symbols left UNDEFINED, not
the number of modules. kavach (44), sankhya (36) and hisab (35) leave few; bote's full
profile with `tls_native` leaves thousands. The same repo's `core` profile — fewer leaves,
same machinery — finished in 2 GB.

### Fix

A per-root cache (`_distlib_snap_cache`) reads each snapshot file once and keeps the
buffers; lookups then scan memory. Entries are kept in `dir_list` order so symbol
attribution is byte-for-byte unchanged.

### Verification

| | before | after |
|---|---|---|
| bote full profile, peak RSS | 20,320 MB (rc=139 at a 20 GB cap) | **57 MB** |
| cap it completes within | died at 20 GB | **4 GB** |
| `dist/bote.deps` | — | **byte-identical** |
| `dist/bote.cyr` | — | **byte-identical** |
| bote `core` profile control | 2 GB | rc=0 inside 2 GB |

The output being byte-identical is the load-bearing check: this is a pure memory fix and
must not move a single leaf in any consumer's sidecar.

⚠ **bote's `ulimit -v` workaround can be retired** once it moves to 6.6.3 — in both
`ci.yml` and `release.yml`. Harmless to leave; it now has 70x headroom rather than none.

### Noted, not fixed here

`_distlib_leaf_defining` returns the FIRST leaf (in `dir_list` order) that declares a
symbol. If two leaves declare the same name, which one wins is therefore readdir-dependent
and can differ between machines — the same class as
`2026-09-12-cyrius-lock-unstable-order.md`. The cache preserves the existing order
deliberately, so this fix changes nothing there. Sorting it would be correct but is a
behaviour change to symbol attribution that needs its own verification pass.
