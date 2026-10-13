# After a `[deps.NAME]` tag changes, `cyrius.lock` keeps the old tag's `commit` row beside the new one, and `deps --locked` accepts it — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the published 6.7.9 (the run below). Found independently by two agents bumping darshana in bannermanor and darshini, then re-run by hand.
**Placement:** Unplaced — filed from darshana 1.3.0's consumer releases (2026-10-12). Only the user places it.
**Discovered:** 2026-10-12, moving consumers' `[deps.darshana]` from 1.0.0 / 1.2.1 to `tag = "1.3.0"`.
**Severity:** Low — `lib/` gets the new tag's files, so the build is right. But the lock names two commits for one dep, its own summary counts one, and the integrity check that exists to catch a lock that disagrees with the manifest passes.
**Affects:** 6.7.9 (verified). Earlier releases were not checked.

## Summary

`cyrius deps` records a named dep as a `commit` row — `commit <sha> <name> <git> <tag>`. When the manifest's `tag`
changes, `deps` vendors the new tag and appends its row, but never removes the row for the tag that is gone; `deps
--lock` re-hashes `lib/` and keeps both. The summary line still says `1 commit-pinned`, and `deps --locked` reports
"lib/ and cyrius.lock are exactly what the tags resolve". Each later bump adds another stale row.

## Reproduction

```sh
mkdir p && cd p
cat > cyrius.cyml <<'EOF'
[package]
name = "lc"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.9"

[build]
entry = "main.cyr"
output = "build/m"

[deps]
stdlib = ["syscalls", "io"]

[deps.darshana]
git = "https://github.com/MacCracken/darshana.git"
tag = "1.2.1"
modules = ["dist/darshana.cyr"]
EOF
printf 'include "lib/darshana.cyr"\nsyscall(SYS_EXIT, 0);\n' > main.cyr
cyrius deps                                   # 1 commit-pinned
sed -i 's/tag = "1.2.1"/tag = "1.3.0"/' cyrius.cyml
cyrius deps && cyrius deps --lock             # still "1 commit-pinned"
grep '^commit' cyrius.lock
cyrius deps --locked
```

Actual (6.7.9):

```
commit	43a1d12dc93badeb356bff19387a45fae887c0d0	darshana	https://github.com/MacCracken/darshana.git	1.2.1
commit	7e9d557e9f8e4ddee1c25c103a38aa59a54d3503	darshana	https://github.com/MacCracken/darshana.git	1.3.0
--locked: lib/ and cyrius.lock are exactly what the tags resolve
```

`lib/darshana.cyr` is 1.3.0's (`# Version: 1.3.0`). Expected: one `commit` row per declared dep, the one for the tag
the manifest names, and `--locked` failing while a row names a tag the manifest no longer declares.

## Proposed fix

When `deps` writes a named dep's `commit` row, drop any existing row for the same `<name>`. Separately, `--locked`
can reject a `commit` row whose `<name>`/`<tag>` pair is not in the manifest.

## Consumer-side workaround

Delete `cyrius.lock` and re-run `cyrius deps` after changing a dep's tag (both consumer releases did this).

## Related

[`2026-10-12-deps-keeps-a-removed-stdlib-leaf-vendored-and-locked.md`](2026-10-12-deps-keeps-a-removed-stdlib-leaf-vendored-and-locked.md)
— the same "nothing is ever removed" shape, for stdlib leaves.
