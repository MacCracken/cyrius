# 2026-06-02 — macOS `alloc_macos.cyr` re-defines the common arena helpers → duplicate-fn warnings

**Discovered:** 2026-06-02 during the ai-hwaccel v2.3.6 macOS-arm64 wheel
build (consumer: **ai-hwaccel**, cyrius 6.0.43, on `ecb`). Surfaced once
the `[deps] stdlib` build path started working on Darwin
([`2026-06-02-macos-arm64-deps-stdlib-pin-check.md`](./2026-06-02-macos-arm64-deps-stdlib-pin-check.md),
RESOLVED).
**Severity:** Low — consumer-tagged **P4**. Cosmetic: "last definition
wins" selects an *identical* body, so behavior is correct and the binary
is verified working. The cost is build-log noise (5 warnings per macOS
build) + a latent divergence footgun if the two copies ever drift.
**Affects:** `lib/alloc_macos.cyr` on any `CYRIUS_TARGET_MACOS` build,
cycc/cyrius 6.0.x (observed 6.0.43). Linux and Windows builds are clean.

## Summary

On macOS, every build that pulls `lib/alloc.cyr` emits a cluster of:

```
warning: duplicate fn 'arena_new' (last definition wins)
warning: duplicate fn 'arena_alloc' (last definition wins)
warning: duplicate fn 'arena_reset' (last definition wins)
warning: duplicate fn 'arena_used' (last definition wins)
warning: duplicate fn 'arena_remaining' (last definition wins)
```

`lib/alloc.cyr` defines the arena allocator as **platform-agnostic,
un-gated** helpers (they only call `alloc()` / `load64` / `store64`, so
they work on top of whichever OS allocator is active). But
`lib/alloc_macos.cyr` — included by `alloc.cyr` under `#ifdef
CYRIUS_TARGET_MACOS` — **re-defines 5 of those same arena helpers**. So
on macOS both copies compile and collide. `lib/alloc_windows.cyr` does
*not* do this (it ships only the OS allocator), which is why Windows is
clean — Windows is the correct model.

## Reproduction

Any macOS arm64 build of a project that includes `lib/alloc.cyr` (e.g.
ai-hwaccel via `[deps] stdlib`), on `ecb`:

```sh
# on ecb (Darwin arm64), in a checkout with [deps] stdlib including alloc:
CYRIUS_DCE=1 cyrius build src/main.cyr out
#   ... warning: duplicate fn 'arena_new' (last definition wins)   (x5)
# build still succeeds; ./out runs correctly.
```

The duplication is static — confirmable from the lib sources alone:

```
$ grep -n 'fn arena_' lib/alloc.cyr          # common, un-gated (after the LINUX #endif@94)
130:fn arena_new(capacity): i64 {
140:fn arena_alloc(a, size): i64 {
152:fn arena_reset(a): i64 {
158:fn arena_used(a): i64 {
163:fn arena_remaining(a): i64 {
176:fn arena_free(a): i64 {
366:fn arena_allocator(capacity): i64 {

$ grep -n 'fn arena_' lib/alloc_macos.cyr     # redundant re-definitions
93:fn arena_new(capacity) {
103:fn arena_alloc(a, size) {
115:fn arena_reset(a) {
121:fn arena_used(a) {
126:fn arena_remaining(a) {

$ grep -n 'fn arena_' lib/alloc_windows.cyr    # (none — correct)
```

The two `arena_new` bodies are byte-identical apart from the `: i64`
return annotation on the `alloc.cyr` copy:

```
fn arena_new(capacity) {           # alloc_macos.cyr:93
    var a = alloc(24);
    var base = alloc(capacity);
    store64(a, base);
    store64(a + 8, base);
    store64(a + 16, base + capacity);
    return a;
}
```

## Root cause (known)

`lib/alloc.cyr` is structured as: a `#ifdef CYRIUS_TARGET_{WIN,MACOS,
LINUX}` block that selects the **OS-level allocator** (`alloc_init` /
`alloc` / `alloc_reset` / `alloc_used`), followed by an **un-gated common
section** (lines 130+) holding the platform-agnostic `arena_*` layer.
The macOS drop-in (`alloc_macos.cyr`) correctly replaces the OS-level
allocator, but *also* carries its own copy of the arena_* helpers
("Arena allocator — independent memory pools (same API as alloc.cyr)").
Those duplicate the common layer that already covers macOS. `alloc.cyr`
includes `alloc_macos.cyr` (early) and then defines its own arena_* again
(later) → "last definition wins" keeps the common copy; the macOS copy
is dead but still parsed, hence the warnings.

## Proposed fix

Delete the 5 redundant `arena_*` functions from `lib/alloc_macos.cyr`
(`arena_new`, `arena_alloc`, `arena_reset`, `arena_used`,
`arena_remaining`) — keep only the OS allocator there. The un-gated
arena layer in `alloc.cyr` already serves macOS unchanged (it bottoms out
on `alloc()`), and `alloc_windows.cyr` is the existing precedent for "OS
allocator only, inherit the common arena layer." No behavior change;
removes the 5 warnings.

Optional hardening: have the preprocessor/`duplicate fn` path treat
byte-identical redefinitions as silent (or error on *differing*
redefinitions instead) — but the targeted stdlib fix above is the clean
one.

## Consumer-side workaround (if any)

None needed — "last definition wins" already yields correct behavior and
the ai-hwaccel macОS arm64 wheel (v2.3.6) shipped with the warning. We
just filter `^warning:` lines in `build_remote.sh` output. Documented as
a known cosmetic warning in ai-hwaccel's CHANGELOG `[2.3.6]`.
