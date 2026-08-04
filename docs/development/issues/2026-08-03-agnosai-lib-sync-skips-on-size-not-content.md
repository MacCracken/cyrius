# `cyrius lib sync` decides "already up to date" by file SIZE, so a same-size change is silently never synced

**Status:** 🟡 **OPEN** — filed 2026-08-03, worked around consumer-side with a content-diff gate.
**Placement:** unpinned — 6.x-line backlog. Small fix, low blast radius; pick it up when convenient.
**Discovered:** 2026-08-03 bumping agnosai's pin 6.5.5 → 6.5.6.
**Severity:** Low — ergonomic. See the impact note below before prioritising this.
**Affects:** cycc 6.5.6 and earlier (behaviour is long-standing; 6.5.6 is where it was pinned down).

## Impact — low, and worth stating up front

The consumer that found this lost **nothing**: the stale file was `lib/vani.cyr`,
which agnosai neither declares nor calls, and the difference was a version
comment. Nothing was miscompiled and nothing was at risk.

The realistic failure mode is narrow. A real code change almost always changes
file length, so sync works. What reliably slips through is the **size-neutral**
case — overwhelmingly a version stamp — which is cosmetic. A behaviourally
meaningful edit that happens to preserve byte count is possible but rare.

So this is a papercut: `lib sync` says "copied" when it means "considered", and
a consumer diffing trees by hand sees a mismatch they cannot explain. Worth
fixing because the fix is small and the confusion is recurring — not worth
displacing anything.

## Summary

`cyrius lib sync` (with or without `--full`) treats a vendored `lib/*.cyr` as
current when its **byte size** matches the snapshot's, without comparing
content. Any change that does not alter file length is therefore **never
vendored**, while the command prints `copied 99 .cyr files (full snapshot)` and
exits 0.

The most common size-neutral change is the one that happens on **every patch
release**: a version stamp in a header comment. `# Version: 1.1.2` →
`# Version: 1.1.3` is exactly the same number of bytes. So a stdlib module whose
patch release is "bump the stamp, fix a few lines" can land in the snapshot and
never reach a consumer's `lib/`, with every command reporting success.

This is almost certainly the mechanism behind the already-known and
already-documented symptom that `lib sync --full` "reports success and leaves
files stale" — observed on the bayan repo (five files) and recorded in
agnosai's `docs/development/state.md` as a standing warning to diff the trees by
hand. It was treated as flaky; it is deterministic and size-keyed.

**`cyrius deps --verify` does not catch it**, and structurally cannot:
`cyrius.lock` is *written from* `lib/` on disk, so a stale file simply gets its
stale hash recorded. In the case that surfaced this, `deps --verify` reported
`105 verified, 0 failed` against a `lib/vani.cyr` that was a release behind.

## Reproduction

Deterministic, in any project with a pinned toolchain. `lib/assert.cyr` is used
because it is small; nothing about it is special.

```sh
cd <any-project-root>
SNAP="$HOME/.cyrius/versions/$(grep '^cyrius = ' cyrius.cyml | sed 's/.*"\(.*\)"/\1/')/lib"

# --- A: same-size mutation (swap one character) ---
python3 -c "
p='lib/assert.cyr'; d=open(p,'rb').read(); i=d.index(b'#')
open(p,'wb').write(d[:i]+b'@'+d[i+1:])"
cyrius lib sync --full            # prints: copied 99 .cyr files (full snapshot)
cmp -s lib/assert.cyr "$SNAP/assert.cyr" && echo RESTORED || echo "NOT restored"

# --- B: size-changing mutation (append one byte) ---
cp "$SNAP/assert.cyr" lib/assert.cyr
printf '\n' >> lib/assert.cyr
cyrius lib sync --full
cmp -s lib/assert.cyr "$SNAP/assert.cyr" && echo RESTORED || echo "NOT restored"
```

Verified on cycc 6.5.6, x86-64 Linux, 2026-08-03:

| case | `lib/` size | snapshot size | after `lib sync --full` |
|---|---|---|---|
| A — one character swapped | 5698 | 5698 | **NOT restored** |
| B — one byte appended | 5699 | 5698 | **restored** |

The real-world instance that led here, same run:

```
$ cyrius lib sync --full
synced from ~/.cyrius/versions/6.5.6/lib — copied 99 .cyr files (full snapshot)

$ diff lib/vani.cyr ~/.cyrius/versions/6.5.6/lib/vani.cyr
2c2
< # Version: 1.1.2
---
> # Version: 1.1.3

$ stat -c '%s' lib/vani.cyr ~/.cyrius/versions/6.5.6/lib/vani.cyr
82799
82799
```

Both 82799 bytes, 2251 lines, differing only in the stamp — and a second and
third `--full` did not fix it either. `cyrius deps` did not revert it; the file
was simply never copied.

## Root cause (speculation — flag as such)

Whatever staleness predicate `lib sync` uses compares size (possibly size +
mtime) rather than content. Note an mtime component alone would not explain case
A: the mutated `lib/assert.cyr` had a *newer* mtime than the snapshot and was
still skipped, and `lib/vani.cyr`'s mtime (2026-07-29) was *older* than the
snapshot's (2026-08-03) and was also skipped. Size is the field consistent with
both observations.

## Proposed fix

Compare content, not size. A sha256 (or any full-content hash) per file is the
obvious form and matches what `cyrius.lock` already computes, so the machinery
exists. If the size check is a fast-path, keep it as a *negative* test only —
different size ⇒ definitely copy — and fall through to a content compare when
sizes match, rather than treating equal size as proof of equality.

Worth considering alongside: `lib sync` prints a count of files it *considered*,
not files it *changed* (`copied 99 .cyr files` was printed on a run that copied
none of them). Reporting "N synced, M already current" would have made this
visible years earlier.

## Consumer-side workaround

agnosai's `scripts/check-clean.sh` gained a content-diff gate that compares
every `lib/*.cyr` against `~/.cyrius/versions/<pin>/lib`, because no existing
command does:

```sh
_snap="$HOME/.cyrius/versions/$(grep '^cyrius = ' cyrius.cyml | sed 's/.*"\(.*\)"/\1/')/lib"
for f in "$_snap"/*.cyr; do
    b=$(basename "$f")
    cmp -s "lib/$b" "$f" || { echo "lib: $b differs from the snapshot"; fail=1; }
done
```

Mutation-verified (it catches case A above). Repairing a skipped file is a
manual `cp` from the snapshot, after which `cyrius deps` must be re-run so
`cyrius.lock` stops describing the stale bytes.
