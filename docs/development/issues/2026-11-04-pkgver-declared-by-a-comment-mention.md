# `CYRIUS_PKG_VERSION` is declared whenever any included file's COMMENT names it, and its literal heads `.rodata` — OPEN

**Status:** 🟡 **OPEN**. Verified 2026-11-04 against cyrius 6.7.18 on x86_64 Linux, with the repro below and with
hoosh's real builds. `PP_RESOLVE_PKGVER` (`src/frontend/lex/pp/pass.cyr:119`) still matches the name inside
comments.
**Placement:** unpinned — 6.x-line backlog. The user places it. Related:
[`2026-11-04-unaligned-literals-make-strlen-cost-layout-dependent.md`](2026-11-04-unaligned-literals-make-strlen-cost-layout-dependent.md),
which explains why the extra literal costs consumers time, not just bytes.
**Discovered:** 2026-11-04, hoosh 2.9.10 → 2.9.11. Three hoosh benchmark rows moved by up to 25% when the version
string grew from `2.9.9` to `2.9.10`, with no code change.
**Severity:** Low. Nothing breaks, and the binary is correct. But a consumer that never asked for the constant gets
it, and its length then shifts every string literal after it.
**Affects:** cycc from 6.7.6 (the reference scan moved to the finished unit) through 6.7.18.

## Summary

`PP_EMIT_PKGVER` writes `var CYRIUS_PKG_VERSION = "<version>";` at byte 0 of the unit. `PP_RESOLVE_PKGVER` then
blanks it unless the expanded unit contains the bytes `CYRIUS_PKG_`. That scan is a raw byte search: it matches a
comment as readily as a use.

Any bundle that merely documents the constant in a comment therefore declares it in every consumer that includes
the bundle. The constant's string is the first literal emitted, so it sits at the start of `.rodata`. Literals are
packed back to back, so every later literal's address now depends on the version's length.

**The case that found it:** ai-hwaccel's `dist/ai-hwaccel.cyr` has the comment `--version is compiled in
(CYRIUS_PKG_VERSION) since 2.5.5` (line 2520 at ai-hwaccel 2.5.6). cbt prepends each `[deps]` module to every
compile, so every hoosh binary, its test suite and its bench carry `var CYRIUS_PKG_VERSION = "2.9.11";`, though no
hoosh code reads it.

## Reproduction

```sh
mkdir -p pkgrepro/src && cd pkgrepro
cat > cyrius.cyml <<'EOF'
[package]
name = "pkgrepro"
version = "1.2.3"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "src/main.cyr"
output = "build/pkgrepro"

[deps]
stdlib = ["string", "alloc", "syscalls", "io"]
EOF
cat > src/main.cyr <<'EOF'
# A comment that only names CYRIUS_PKG_VERSION; no code uses it.
fn main() {
    var s = "hello";
    sys_write(1, s, 5);
    return 0;
}
EOF
cyrius lib sync && mkdir -p build
cyrius build src/main.cyr build/with
sed -i 's/only names CYRIUS_PKG_VERSION/names nothing/' src/main.cyr
cyrius build src/main.cyr build/without
grep -c -a '1\.2\.3' build/with build/without
```

**Expected:** neither binary contains `1.2.3`, because no code references the constant.
**Actual (6.7.18):** `build/with` contains it, and it is the first bytes of `.rodata`:

```
000139e8: 312e 322e 3300 0a00 616c 6c6f 635f 696e  1.2.3...alloc_in
```

`build/without` does not contain it.

**Confirmed on the consumer:** hoosh's bench built without ai-hwaccel in its manifest (a scratch copy; the bench
calls nothing in it) carries no version literal. Built at versions `2.9.9` and `2.9.10`, those bench binaries are
byte-identical. With ai-hwaccel included, the two differ in 310,791 bytes, all from the one-byte shift.

## Root cause

`src/frontend/lex/pp/pass.cyr:138-147`: the loop compares the 11 bytes `CYRIUS_PKG_` at every offset of the
expanded unit, skipping only the declaration's own bytes. Comments are still present in that buffer, as are string
literals. The scan correctly made the constant visible to included files (the 6.7.6 fix for agnostic's
`src/routes/health.cyr`). But "mentioned anywhere" is wider than "referenced".

## Proposed fix

1. **Scan tokens, not bytes.** Skip `#` comments to end of line, and skip the bodies of string literals, before
   matching `CYRIUS_PKG_`. That keeps the 6.7.6 behavior for real references in included files, and stops a doc
   comment from declaring the constant. `tests/gates/toolchain/auto_deps_verb_gate.sh` axis 5 already checks that an
   unreferenced build is byte-identical; a new axis could add a comment-only mention to that case.
2. **Independently, consider emitting this literal last,** or padding it to a fixed width, so a consumer that does
   use the constant does not shift every other literal with each release. That depends on how cycc orders
   `.rodata`. I haven't checked whether the declaration can move without breaking the line-neutral design
   `PP_EMIT_PKGVER` documents.

## Consumer-side workaround

hoosh 2.9.11 makes its benchmarks independent of literal placement: the strings its timed loops read are 8-aligned
heap copies (`tests/hoosh.bcyr`, `_b_s`). That hides the effect from the benchmarks; the declaration is still in
every hoosh binary. hoosh cannot remove the trigger, because `cyrius deps` re-vendors `lib/ai-hwaccel.cyr` and
`deps --verify` checks its hash. ai-hwaccel rewording its comment would remove it:
`ai-hwaccel/docs/development/issues/2026-11-04-comment-naming-cyrius-pkg-version-declares-it-in-consumers.md`.
