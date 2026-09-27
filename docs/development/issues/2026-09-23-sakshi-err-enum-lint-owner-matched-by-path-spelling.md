# cyrlint: the error-enum namespace rule decides "is this sakshi?" from how the path is spelled — it notes sakshi's own `src/error.cyr`, and exempts any leaf whose path happens to contain "sakshi" — OPEN

**Status:** 🟡 **OPEN**: `_lint_path_is_err_owner` substring-matches `"sakshi"` against the path
exactly as the caller typed it, so the rule's verdict on a file changes with how the path is spelled
(relative vs absolute, the names of its parent directories), not with what the file is.
**Placement:** unpinned, but it must land **before or with** the planned note → `warn` flip of
`lint_error_enum_namespace` (CHANGELOG `[6.4.51]`: "flips to a hard warn after the ecosystem
migration window"). Harmless until then.
**Discovered:** 2026-09-23 during sakshi's 2.5.3 bump to 6.6.6, while checking whether sakshi's
`ERR_*` ownership issue (Option B) could close.
**Severity:** Low today. The rule is note-level, `cyrlint` exits 0 with `0 warnings`, and sakshi's CI
lint gate fails only on `^\s*warn `. **Medium at the flip**: sakshi's own CI lint gate would then fail
on sakshi's own canonical set. The gate built to protect the owner would fail the owner first, while a
colliding leaf could still pass unflagged.
**Affects:** `programs/cyrlint.cyr` at 6.6.6 (unchanged at HEAD): `_lint_path_is_err_owner`
(`:700`–`:709`, the `memeq(path + i, "sakshi", 6)` at `:705`), consulted by
`lint_error_enum_namespace` (`:815`) with the `path` that `_lint_one` received (`:1790`). The owner
check is byte-identical to the one that shipped in 6.4.51. `cyrius lint <f>` passes the path
through as typed (its banner reads `=== cyrlint: src/error.cyr ===`).

## Summary

The owner of the unprefixed `ERR_*` set is sakshi. The archived proposal
`2026-07-11-error-enum-namespace-lint-gate` was decided as option 1b, "owner matched by path". The
match is a substring search for `sakshi` in the path string, and that string is whatever the caller
typed:

- **False positive.** sakshi's own CI, and anyone working in the sakshi repo, runs
  `cyrius lint src/error.cyr`. That string has no `sakshi` in it, so **every member of both of sakshi's
  enums** (`ErrCat` lines 8–16, `ErrCode` lines 21–28) gets the "reserved for the sakshi base logger"
  note. The same two enums in `dist/sakshi.cyr` get none, and so does the same file spelled
  `$PWD/src/error.cyr`.
- **False negative.** Any file whose path merely *contains* `sakshi` is exempt. That includes a leaf
  lib checked out under a directory named after sakshi, a CI workspace or scratch dir, a consumer's
  `src/sakshi_glue.cyr`, and anything under `~/.cyrius/deps/sakshi/`.

The rule was verified in the cyrius tree (6.4.51: "only `lib/sankoch.cyr` in cyrius today"), where
sakshi appears only as `lib/sakshi.cyr`. The in-repo, relative-path case never ran.

## Reproduction

Reproduced with `cyrlint` 6.6.2 and 6.6.6 (`~/.cyrius/versions/6.6.6/bin/cyrlint`) on a sakshi 2.5.2
checkout:

| Invocation (cwd = sakshi repo) | notes |
|---|---|
| `cyrlint src/error.cyr` | **17** |
| `cyrlint "$PWD/src/error.cyr"` | 0 |
| `cyrlint dist/sakshi.cyr` (the same two enums, bundled) | 0 |

The false negative, using a leaf enum with yukti's real colliding value:

```cyrius
enum LeafErr {
    ERR_TIMEOUT = 9;
}
```

The file sat in a scratch directory whose absolute path contains `-Repos-sakshi`
(`/tmp/claude-1000/-home-macro-Repos-sakshi/…/leafdemo/leaf.cyr`):

| Invocation | notes |
|---|---|
| `cd …/leafdemo && cyrlint leaf.cyr` | 1 |
| `cyrlint /tmp/claude-1000/-home-macro-Repos-sakshi/…/leafdemo/leaf.cyr` | **0** |

The file and its bytes are the same in both rows. Only the spelling of the path differs, and that is
enough for a colliding leaf to pass.

## Root cause

`_lint_path_is_err_owner` (`:700`) answers "is this file sakshi?" from a property of the *argument
string*, which the linter does not control. Relative vs absolute, the checkout directory's name, and
every ancestor directory's name all change the answer. A path substring is neither necessary (sakshi's
own sources do not carry the name) nor sufficient (unrelated files do).

## Options (the maintainer's call)

1. **Match the package, not the path [recommended].** Walk up from the file to the nearest
   `cyrius.cyml` and treat the file as the owner iff `[package] name = "sakshi"`. Also accept a file
   whose **basename** is exactly `sakshi.cyr`, which covers the vendored `lib/sakshi.cyr` in a
   consumer, whose nearest manifest is the consumer's. This fixes both directions, keeps option 1b's
   "cyrius-side config", and needs no consumer change.
2. **Ownership pragma (the proposal's option 1a).** sakshi's `src/error.cyr` carries
   `#lint-owns-prefix ERR_`. The claim travels with the text into `dist/sakshi.cyr` and every vendored
   `lib/sakshi.cyr`, because sakshi's `scripts/bundle.sh` strips only `include` lines. It is robust to
   any path spelling. It needs a one-line comment in sakshi, and a policy on who may claim a prefix.
3. **`realpath` before matching — not recommended.** It fixes the relative-path false positive but
   widens the false negative: every file under any directory named after sakshi becomes exempt.

Whichever option lands, the regression test should cover both directions: the owner file spelled
relative gives 0 notes, and a leaf file under a `sakshi`-named directory is noted.

## What sakshi does meanwhile

Nothing. The notes do not fail sakshi's gate: `cyrius lint` exits 0, and the CI step fails only on
`^\s*warn `. sakshi will **not** `#skip-lint` its enums. That would frame the canonical set as
*exempted* rather than *owned*, which is option 1c, and the proposal set it aside. It would also
silence every other rule on those lines. If the note → warn flip lands before this fix, sakshi's CI
lint gate fails on `src/error.cyr`.

## Cross-references

- Proposal (archived): `docs/development/proposals/archived/2026-07-11-error-enum-namespace-lint-gate.md`.
  Its header still reads "FILED for review … No decisions committed", although the rule's comment
  (`programs/cyrlint.cyr:696`–`:697`) and CHANGELOG `[6.4.51]` record option 1b as shipped.
- CHANGELOG `[6.4.51]` "Added — error-enum namespace lint gate". In `[6.6.5]` the enum body became
  token-scanned; that rework changed member detection, not the owner check.
- sakshi `docs/development/issues/archive/2026-06-23-err-timeout-enum-collision-namespace.md`
  (Option B: sakshi keeps the bare set, and leaves prefix theirs).
