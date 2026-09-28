# `cyrius distlib <profile>` keeps a stdlib leaf in `.deps` when one of its names appears only in a comment or a string — RESOLVED

**Status:** ✅ **RESOLVED v6.6.9** (bite 8) — the profile prune blanks the bundle's comments, strings and char literals (the shared `_src_blank_noncode`) and reads a kept `include "lib/<leaf>.cyr"` line as a reference; the repro prints `syscalls alloc` for all three forms. Residual, documented: a parameter or local that reuses a stdlib top-level name still keeps that leaf (names, not resolutions). Gate: `tests/gates/toolchain/distlib_profile_sidecar.sh` axes 8-10.
**Placement:** **6.6.9 bite 8** — distlib: the profile prune ignores comments and strings; the verify unit splices named-dep modules and fails loudly; cbt _file_size works on PE. Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-26 during vani's busy-PCM open fix, when comment text added to
`src/alsa.cyr` — vani's whole `core` profile — grew `dist/vani-core.deps` from 3 leaves to 8.
**Severity:** Low — it over-reports, the safe direction: nothing fails to build. But a profile's
sidecar silently grows, which defeats what a profile is for, and the distlib drift gate cannot see
it. A consumer workaround exists (below).
**Affects:** profile `.deps` pruning since v6.4.48 (`_distlib_prune_profile_leaves`). Verified on
6.6.2 and 6.6.6.

## Summary

For a `[lib.<profile>]` bundle, `cyrius distlib` starts from the fold's stdlib leaves and keeps a
leaf if any top-level `fn` / `var` that the leaf (or one of its own private peers) declares appears
as a whole word anywhere in the bundle. The scan is plain text, so a name inside a `#` comment or a
string literal counts as a reference. One ordinary English word is enough: `run` is `fn run` in
`lib/process.cyr`, and keeping `process` brings `vec`, `str` and `fmt` with it.

## Reproduction

```sh
d=$(mktemp -d) && cd "$d" && mkdir src
cat > cyrius.cyml <<'EOF'
[package]
name = "demo"
version = "0.1.0"
language = "cyrius"
cyrius = "6.6.6"

[lib]
modules = ["src/a.cyr"]

[lib.core]
modules = ["src/a.cyr"]

[deps]
stdlib = ["syscalls", "string", "alloc", "process"]
EOF
printf 'include "lib/syscalls.cyr"\ninclude "lib/string.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/process.cyr"\ninclude "src/a.cyr"\n' > src/lib.cyr
cat > src/a.cyr <<'EOF'
# Closes fd. Safe to run twice.
fn demo_close(fd): i64 { return sys_close(fd); }
EOF
cyrius distlib core > /dev/null; grep -v '^#' dist/demo-core.deps | tr '\n' ' '; echo
sed -i 's/Safe to run twice/Safe to call twice/' src/a.cyr
cyrius distlib core > /dev/null; grep -v '^#' dist/demo-core.deps | tr '\n' ' '; echo
```

**Expected:** both lines read `syscalls alloc`. The only change is one word in a comment.

**Actual** (6.6.6):

```
syscalls process alloc vec str string fmt
syscalls alloc
```

A string literal does the same: with `fn demo_label(): i64 { return "run"; }` in `src/a.cyr` and no
comment, the sidecar again lists `process` and the three it brings.

### In a real project

vani's `core` profile is `src/alsa.cyr` alone, and cyrius-doom, polyomino, bb and mishran vendor
it. Adding `_audio_open_pcm` with an explanatory comment took `dist/vani-core.deps` from
`syscalls string alloc` to eight leaves (`+ io process fmt vec str`):

- `O_WRONLY` / `O_RDONLY` in comments kept `lib/io.cyr`, which declares `var O_WRONLY` /
  `var O_RDONLY`. Making the code use literals did not help while a comment still named them.
- "before any PREPARE can run" kept `lib/process.cyr` (`fn run`), and with it `vec`, `str`, `fmt`.

Bisected on a scratch copy; rewording only the comments restored the 3 leaves. The drift gate
passed at every step, because it compares the committed sidecar with a regenerated one, and the
regenerated one is what gets committed.

## Root cause

`cbt/commands.cyr` at HEAD `d5697d73`:

- `_distlib_prune_profile_leaves` (line 3907) keeps a leaf when `_distlib_leaf_referenced`
  returns 1.
- `_distlib_leaf_referenced_d` (line 3739) walks the top-level `fn ` / `var ` lines of the leaf
  and its own private peers, and asks `_distlib_bundle_refs` about each name.
- `_distlib_bundle_refs` (line 3718) runs `memeq` at every offset of the bundle with
  identifier-boundary checks. It has no notion of a comment or a string.

Not traced: how `process` brings `vec` / `str` / `fmt`. Speculation — the verify pass resolving
what `process.cyr` itself references.

Same shape as
[`2026-09-23-samay-coverage-counts-substrings-and-comments-as-references.md`](archived/2026-09-23-samay-coverage-counts-substrings-and-comments-as-references.md)
(`cyrius coverage`, `cbt/quality.cyr`): a reference scan over raw text. One comment- and
string-aware scanner could serve both.

## Proposed fix

Blank out string literals and `#`-to-end-of-line comments in the bundle buffer once, in
`_distlib_prune_profile_leaves` before the leaf loop, and keep `_distlib_bundle_refs` a plain
matcher. Strings first, so a `#` inside a string does not start a comment. `#ifdef` / `#else` /
`#endif` lines would be blanked too; they name macros, not stdlib `fn` / `var`s.

Removing comments cannot drop a leaf the code references, so the prune's never-drop-a-real-dep rule
holds. Whether any Cyrius construct can reference a symbol from inside a string is for the Cyrius
side to confirm before strings are blanked.

A regression test can be the reproduction above: a comment-only (or string-only) mention must not
keep a leaf, and a code reference must.

## Consumer-side workaround

Keep stdlib top-level `fn` / `var` names out of a profile module's comments and strings, and read
the profile's `.deps` whenever it changes in a diff. vani spells the two access modes as literals
in `src/alsa.cyr`, reworded its comments, and documents the constraint in
`docs/architecture/002-distlib-deps-counts-comment-words.md`, with this check for a word:

```sh
grep -nE '^(fn|var) +WORD\b' ~/.cyrius/versions/<pin>/lib/*.cyr
```

A hit in a module outside the profile's leaves means the word will keep that module.
