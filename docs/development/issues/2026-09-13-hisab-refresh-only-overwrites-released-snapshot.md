# `install.sh --refresh-only` writes the repo's in-progress `lib/` into an ALREADY-RELEASED version's snapshot — OPEN

**Status:** 🟡 **OPEN** — filed by hisab on its 3.0.1 toolchain bump (6.6.2 → 6.6.3). No fix
attempted here; the companion consumer-side filing is
`2026-09-13-hisab-deps-relocks-silently-under-unchanged-pin.md`.
**Placement:** unpinned — every release; verified on the tree at **6.6.3**.
**Discovered:** 2026-09-13. hisab's docs said ganita **1.2.4** under its 6.6.2 pin; its committed
`lib/ganita.cyr` agreed; a `cyrius build` under that unchanged pin rewrote the file to **1.2.5** and
re-locked it. The "pin's own snapshot" hisab byte-checks against had stopped being the pin's snapshot.
**Severity:** High — **a version-pinned snapshot is mutable, and the mutation is invisible from the
consumer side.** `~/.cyrius/versions/<v>/lib` is the thing a pin means. On a box that runs the cyrius
dev loop it silently becomes "whatever `lib/` looked like the last time `--refresh-only` ran with
VERSION still reading `<v>`", i.e. the NEXT release's stdlib under the OLD release's name.

## Summary

`scripts/install.sh --refresh-only` keys its destination on `$(cat VERSION)`:

```sh
VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null)"      # install.sh:36
mkdir -p "$CYRIUS_HOME/versions/$VERSION/lib"              # install.sh:211
dst="$CYRIUS_HOME/versions/$VERSION/lib/$rel"              # install.sh:436
```

and nothing checks whether `$VERSION` is **already a cut release**. During 6.6.3 development VERSION
read `6.6.2` from the 6.6.2 tag (2026-09-10) until the bump commit `8910cde2` at 11:43 on 09-12, and
the fold-in bite `8eb75cbe` (09:17) refolded twelve stdlibs — so every refresh in that window wrote
6.6.3's `lib/` into **`versions/6.6.2/lib`**, the slot for a release that had shipped two days earlier.

## Measured on this box

| | |
|---|---|
| `~/.cyrius/versions/6.6.2/` created | 2026-09-10 19:08 |
| `~/.cyrius/versions/6.6.2/lib/ganita.cyr` mtime | **2026-09-12 08:49** |
| files in `versions/6.6.2/lib` that differ from `git show 6.6.2:lib/<f>` | **12** — exactly the twelve refolded stdlibs (bayan, ganita, mabda, niyama, patra, sakshi, sandhi, sankoch, sigil, vani, yantra, yukti) |
| files in `versions/6.6.2/lib` that differ from `versions/6.6.3/lib` | **0** |
| files in `versions/6.6.3/lib` that differ from `git show 6.6.3:lib/<f>` | 0 |

So the installed "6.6.2" stdlib **is 6.6.3's**, byte for byte, while the installed 6.6.3 matches its
tag. The cyrius tag is the only trustworthy reference for what a pin ships; the install dir is not.

**Repro (safe — throwaway home, current tree, VERSION = 6.6.3 which IS tagged):**

```sh
cd ~/Repos/cyrius
git tag -l "$(cat VERSION)"                       # prints 6.6.3: this version is released
T=$(mktemp -d); CYRIUS_HOME=$T sh scripts/install.sh --refresh-only
ls $T/versions/                                   # 6.6.3  <- wrote into the RELEASED slot
ls $T/versions/6.6.3/lib | wc -l                  # 104 (110 stdlib files reported refreshed)
```

Pointed at the real store — which is what `version-bump.sh`'s post-hook and the documented
"snapshot-ping-pong" mitigation in `CLAUDE.md` both do — that is the mutation above.

## Why this is a defect and not the documented workflow

`CLAUDE.md` §"Snapshot-ping-pong protection" documents this write as a hazard **to cyrius's own
`lib/` edits** (the snapshot copying BACK over an edit). It never says what it does to a consumer:
every repo on the box pinned to `<v>` now resolves its stdlib from a snapshot that is not `<v>`,
and — per the companion filing — `cyrius build` in such a repo silently re-vendors and re-locks the
mutated files. hisab's 2.11.2 notes already record ganita being three releases stale behind a green
`deps --verify` from the *reverse* shape; this is the same class from the other side.

## Proposed fix (either half is sufficient; both is better)

1. **Refuse to refresh a released version.** In `--refresh-only`, if `git tag -l "$VERSION"` is
   non-empty (or the tag exists on the remote), abort with the reason and the fix (`bump VERSION
   first`), unless `CYRIUS_REFRESH_RELEASED=1`. Mirrors the 6.6.2 `funcgate-stage.sh` guard that
   refuses to `rm -rf` a live store — same principle: a script whose contract is "throwaway" or
   "in-progress" must not be able to reach a released artifact by default.
2. **Or key dev refreshes to a dev slot** (`versions/<VERSION>-dev`, or `versions/next`) that the
   wrapper only resolves when the manifest pins it explicitly, so a released slot is written exactly
   once, by `install.sh` proper, from a verified tarball.

A gate for it is cheap: stage a throwaway home, tag a scratch VERSION, run `--refresh-only`, assert
it refused. Mutation: drop the tag check, the gate reddens.

## Consumer stopgap (what hisab does now)

Byte-compare vendored `lib/` against **`git show <pin>:lib/<file>` in the cyrius repo**, not against
`~/.cyrius/versions/<pin>/lib`. hisab 3.0.1 does this for all 30 stdlib files; its memory note that
said "compare against the pin's own snapshot" is corrected to name the tag.
