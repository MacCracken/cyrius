# Proposal — let a package declare test-only stdlib leaves, instead of hiding them from the umbrella scan

**Filed:** 2026-09-16 · **Status:** 🟡 OPEN — for maintainer direction
**Filed by:** rekha (0.4.4), first consumer to hit it. Everything below is measured against
cyrius 6.6.4, not inferred.

**Prompted by:** rekha shipping `dist/rekha.deps` with **nine** stdlib leaves for a bundle whose
entire stdlib appetite is `strlen` + `memcpy`. Every consumer of `dist/rekha.cyr` was vendoring
eight leaves of nothing. The fix works and rekha 0.4.4 ships it — but the fix is *positional*,
and that is what this proposal is about.

## What `distlib` actually does today

`dist/<pkg>.deps` is built in `cbt/commands.cyr` from three sources, unioned:

| # | Source | Function |
|---|---|---|
| 1 | include scan of **`src/lib.cyr`** (path hardcoded) | `_distlib_scan_umbrella` (cbt/commands.cyr:3903) |
| 2 | the **`[deps] stdlib`** array | `_distlib_union_declared_stdlib` (:3527) |
| 3 | compile-verify fixpoint — splices leaves + bundle with `_skip_deps = 1`, re-adds the owner of each undefined symbol | `_distlib_verify_leaves` (:2586) |

Source 3 is excellent and did real work for rekha: it added `alloc` on its own, because
`lib/string.cyr` calls `alloc()` and declares no include for it. That is a true transitive
requirement no hand-written list would have caught. **This proposal does not touch source 3.**

The problem is sources 1 and 2, which are *over*-reporting channels with no way to opt out.

## The bind

A package's own test harness almost always wants more leaves than its library does. rekha's
suites want `fmt_int_fd`, `arena_*`, `str_same`, `assert_*`, `bench_*`; rekha's `src/` wants
`strlen` and `memcpy`. There is currently **no way to say that.** Both available channels are
published:

- put the leaf in `[deps] stdlib` → it lands in the sidecar (source 2);
- put the include in `src/lib.cyr` → it lands in the sidecar (source 1).

So the only way to keep a harness-only leaf out of the published sidecar is to **move the
include into a file the scan does not look at**. rekha 0.4.4 does exactly that: a new
`programs/prelude.cyr` holds the eight harness leaves and then includes `src/lib.cyr`; the
programs include the prelude. Sidecar went 9 → 2 (`string`, `alloc`), the base and profile
bundles came out **byte-identical**, and all 24 suites still build and run green under
`CYRIUS_DCE=0` and `1`.

### Why that fix is uncomfortable

It works, and rekha is keeping it. But what it means is:

> whether a leaf is published to every downstream consumer depends on **which file** its
> `include` line sits in — and the deciding filename, `src/lib.cyr`, is hardcoded in the tool
> and appears nowhere in the manifest.

That is invisible to the person editing. The regression is one keystroke and reads as an
improvement: adding `include "lib/fmt.cyr"` to `src/lib.cyr` for convenience. Measured on
rekha — that single line took the sidecar from `string alloc` to **`string fmt alloc vec`**,
three new leaves for every consumer, with `--check` staying green the whole time, because
`--check` verifies the sidecar *matches src/*, never that it has not **grown**. rekha now pins
the expected leaf list in CI by hand to catch it, which is a hand-maintained duplicate of a
derivable fact — the self-drifting shape the 2026-09-04 manifest proposal already names.

## The ask

A declarative channel for "leaves my own build needs that are **not** part of what I publish."
Shape is the maintainer's call; the requirement is only that it feed auto-prepend and `cyrius
deps` **without** feeding the sidecar union. Sketch:

```toml
[deps]
stdlib     = ["string"]                      # what the LIBRARY calls -> published
dev-stdlib = ["fmt", "alloc", "vec", "str",  # what the HARNESS calls -> never published
              "io", "syscalls", "assert", "bench"]
```

Two smaller variants, if a new key is unwanted:

1. **Make the umbrella path a manifest key** (`[lib] umbrella = "src/lib.cyr"`). Does not fix
   the bind, but at least the deciding file stops being invisible.
2. **Let `[lib]` opt out of source 2 entirely** (e.g. `sidecar = "verified"`), trusting source 3
   — the compile-verify fixpoint — as the sole authority. Given how well source 3 performed
   here, this may be the strongest option: it would have produced rekha's correct
   `string alloc` with no declaration discipline at all, and it deletes the over-reporting
   channels rather than adding a third.

## Two measured notes, offered as data

Neither is a request; both bear on any design here.

1. **Auto-prepend makes a package's own tree unable to check its sidecar.** Inside a resolved
   tree every leaf from every resolved sidecar is in scope, so a program compiles whether or not
   it includes what it calls — verified with a program containing no includes at all that calls
   `alloc`, `strlen` and `vec_new` and builds clean. So a "compile the bundle the way a consumer
   does" suite (rekha has two) **cannot** catch a sidecar that omits a needed leaf; it silently
   passes. `_distlib_verify_leaves` with `_skip_deps = 1` is the only thing that can, which is
   worth stating in the docs, because the suite looks like it is testing that and is not. rekha
   0.4.4 had to correct its own comments after measuring this.

2. **Under-reporting is not obviously the dangerous direction.** `_distlib_verify_leaves`'
   header reasons that over-reporting is safer because a bogus leaf name is a hard resolver
   error. True for a *misspelled* leaf — but a *real* leaf that is merely unnecessary is not an
   error at all, it is a silent tax, and it persisted across four rekha releases precisely
   because nothing complains. Over-reporting is quieter, not safer.

## What rekha does in the meantime

Ships the prelude split (0.4.4), pins both sidecars in CI, and documents the hardcoded
`src/lib.cyr` scan in three places so the next editor sees it. Nothing here blocks rekha; the
request is to make the intent declarable instead of positional.
