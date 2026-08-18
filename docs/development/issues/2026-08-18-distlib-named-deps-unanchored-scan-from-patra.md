# `_distlib_named_deps` scans the manifest unanchored, so a `[deps.X]` written in COMMENT PROSE deletes X from the sidecar

**Status:** 🟡 **OPEN** — reproduced against **cyrius 6.5.27**, filed by **patra**
(v1.13.2) and confirmed in **libro** (v2.8.6).

**Severity:** **Medium** — silent packaging corruption. The bundle is correct; the
`.deps` sidecar under-declares, so a clean-room consumer that resolves from the
sidecar (which is what the sidecar is *for*) is short a stdlib leaf. `distlib`'s
own self-check structurally cannot catch it — see below.

> Distinct from
> [`2026-08-18-distlib-named-profile-sidecar-from-sit.md`](2026-08-18-distlib-named-profile-sidecar-from-sit.md),
> which is about a *named profile* writing to the base sidecar path
> (`cbt/commands.cyr:3168`). Same artifact, different function and different
> cause. Both are sidecar-leaf correctness; neither subsumes the other.

## Symptom

`dist/patra.deps` emitted **11** stdlib leaves against the **12** declared in
`[deps].stdlib`. The missing one was `sakshi` — while `dist/patra.cyr` calls
`sakshi_error` and `sakshi_set_level` and defines neither.

```console
$ grep -c '"' <<< "$(sed -n '/^\[deps\]/,/^\[/p' cyrius.cyml)"   # 12 declared
$ cyrius distlib && grep -cv '^#' dist/patra.deps                # 11 emitted
```

## Cause

`_distlib_named_deps` (**`cbt/commands.cyr:2486`**) builds the "this is a fold,
not a stdlib leaf" exclude set by scanning the manifest buffer for the literal
`[deps.` **with no line anchoring**:

```cyrius
while (ndi < mlen) {
    if (ndi + 6 <= mlen && memeq(mbuf + ndi, "[deps.", 6) == 1) {
        var nns = ndi + 6;
        var nne = nns;
        while (nne < mlen && load8(mbuf + nne) != 93) { nne = nne + 1; }   # to ']'
        ...
        vec_push(named_deps, nd);
```

So any `[deps.NAME]` appearing in `#` comment prose is read as a real named dep
and NAME is dropped from the sidecar. **A manifest's own documentation about a
dep deletes that dep's leaf.**

This is already known in the file. The neighbouring `_distlib_enum_profiles`
(**`:2364`**) is line-anchored *on purpose*, and its comment says so:

> ⚠ LINE-ANCHORED ON PURPOSE. The neighbouring `_distlib_named_deps` scans
> unanchored, which would match `[lib.x]` inside a comment or a string. Skip
> leading whitespace, skip `#` comment lines, then require the line to START
> with `[lib.`.

The warning was written and the sibling was never fixed.

## Proof it is the comments, not the dep graph

patra shipped this defect **with no git deps at all**. `dist/patra.deps` carried
11 leaves against 12 declared, missing `sakshi`, identically at **1.12.11,
1.12.12, 1.13.0 and 1.13.1** — i.e. unchanged straight through the release that
removed patra's `[deps.sakshi]` block. Removing the block changed nothing,
because the block was never the cause; the prose discussing it was.

libro reached the same conclusion independently after initially recording the
wrong root cause in its own manifest (blaming patra's removed block), which is
worth noting: **the misdiagnosis is what let the hole survive a release.**

## Why the self-check misses it

`distlib`'s bundle self-check downgrades **undefined functions** to warnings —
only an undefined *variable* fails a bundle. A missing stdlib leaf almost always
manifests as undefined *functions* (`sakshi_error`, `sakshi_set_level`), so the
check passes. There is no path by which the current self-check can catch an
under-declared sidecar.

## Reproducer

Any package with a stdlib leaf named in comment prose. Minimal:

```console
$ cd patra
$ grep -cv '^#' dist/patra.deps                  # 12 (after the workaround)
$ sed -i 's/^# 1\. Never write a bracketed deps.NAME/# 1. Example: [deps.sakshi] in prose./' cyrius.cyml
$ cyrius distlib && grep -cv '^#' dist/patra.deps
11                                                # sakshi silently gone
```

## Consumer workaround (in place)

Backtick every dep name in comment prose — `` `deps.NAME` `` instead of
`[deps.NAME]` — so the literal never appears. Applied in patra `cyrius.cyml`
(11 → 12 leaves) and libro `cyrius.cyml` (26 → 27), with `dist/*.cyr`
**byte-identical** in both cases: only the sidecar moves.

patra additionally added a CI gate (v1.13.7) asserting that the emitted leaf
count equals the number of names in `[deps].stdlib`, so the workaround cannot
silently regress. That gate is a consumer-side backstop, not a fix.

## Wanted

Mirror `_distlib_enum_profiles`: skip leading whitespace, skip `#` comment
lines, and require the line to **start** with `[deps.`. A three-line change in
`_distlib_named_deps`.

Worth checking the same pattern anywhere else a manifest is scanned by substring
rather than by line.

## Affected

Confirmed under-declared or at risk wherever a manifest documents its own deps in
prose: **patra**, **libro**, and by inspection **sigil**, **majra**, **bote**.
