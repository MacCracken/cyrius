#!/bin/sh
# tests/gates/toolchain/check_sit_lookup_worktree.sh — 6.6.16 (G5)
#
# THE CHECK DRIVER FINDS sit FROM A GIT WORKTREE.
#
# THE DEFECT. The sit-fsck row (programs/checks/services.cyr `_sit_status_gate`) ran
# `$SIT_DIR/build/sit`, else `<ROOT>/../sit/build/sit`, where ROOT is the driver's cwd. A git
# worktree added outside ~/Repos (every release lane lives at ~/.cache/<lanes>/<x>) has no
# `../sit`, so the row SKIPped there while the main checkout's sibling sit sat built — every
# lane's check.sh ran without it. A worktree's `.git` is a FILE (`gitdir: <main>/.git/worktrees/<x>`)
# and that gitdir's `commondir` names the shared .git; nothing followed it.
#
# THE FIX. `_sit_find_dir()`: $SIT_DIR (an override — the only candidate when set), then
# <ROOT>/../sit, then the gitdir/commondir route's <main>/../sit (gitdir relative to ROOT,
# commondir relative to the gitdir, either may be absolute), then $HOME/Repos/sit; a candidate
# counts only when <dir>/build/sit exists. A miss names every path tried and the SIT_DIR
# override. `cyrius_check --sit-dir` prints the resolution (exit 0) or the miss (stderr, exit 1,
# stdout empty), so the lookup is gated here without the 100-commit fixture.
#
# AXES (a faked layout under a private dir; HOME is a fake so $HOME/Repos/sit never leaks in)
#   1  a worktree far from sit, ABSOLUTE gitdir + relative commondir `../..` -> <main>/../sit
#   2  RELATIVE gitdir + relative commondir                               -> the same
#   3  ABSOLUTE commondir, gitdir file with a CRLF line end                -> the same
#   4  SIT_DIR wins over a resolvable worktree; a SIT_DIR without build/sit is a miss that
#      names it (the override is not silently replaced by another sit)
#   5  a plain checkout next to sit resolves to that sibling (branch b, unchanged)
#   6  a miss: exit 1, stdout empty, stderr names the ../sit, worktree and $HOME/Repos/sit
#      candidates and SIT_DIR
#   7  $HOME/Repos/sit is the last resort; a `.git` file with no commondir (a
#      --separate-git-dir clone) is not followed and does not crash the lookup
#   8  LIVE: when this tree is itself a git worktree whose main checkout has a built sibling
#      sit, `--sit-dir` from the root names exactly that (git's own --git-common-dir is the
#      oracle); otherwise the axis says why it did not apply
#
# MUTATIONS (each RED; measured when this gate was written):
#   M1 `_sit_find_dir` drops the worktree branch (`_sit_worktree_candidate`)  -> axes 1, 2, 3, 6, 8
#   M2 the relative gitdir taken as absolute (no ROOT join)                    -> axis 2
#   M3 `_read_line1` keeps the CR                                              -> axis 3
#   M4 SIT_DIR falls through to the other candidates on a miss                 -> axis 4
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: check_sit_lookup_worktree: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=check_sit_lookup_worktree
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT
# getcwd() answers the PHYSICAL path, so every expected path is built from the physical $D.
T=$(cd "$D" && pwd -P)
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

[ -x "$CC" ] || { echo "FAIL: $NAME — no compiler at $CC"; exit 1; }
( cd "$ROOT" && cat programs/checks/main.cyr | "$CC" > "$T/drv" 2>"$T/drv.err" ) \
    || { cat "$T/drv.err"; echo "FAIL: $NAME — the check driver does not compile"; exit 1; }
chmod +x "$T/drv"

# A sit "build": the lookup only asks that <dir>/build/sit exists.
mksit() { mkdir -p "$1/build" && printf '#!/bin/sh\nexit 0\n' > "$1/build/sit" && chmod +x "$1/build/sit"; }
# A worktree <wt> of main checkout <main>, named <id>: the gitdir line and the commondir text
# are given verbatim.
mkwt() {  # <wt> <main> <id> <gitdir-line> <commondir-text>
    mkdir -p "$1" "$2/.git/worktrees/$3"
    printf '%s\n' "$5" > "$2/.git/worktrees/$3/commondir"
    printf '%s\n' "$4" > "$1/.git"
}
# Run `--sit-dir` from <dir> under a fake HOME with SIT_DIR unset; stdout -> $OUT, rc -> $RC.
sitdir() {  # <dir> [env assignments...]
    _d=$1; shift
    RC=0
    OUT=$(cd "$_d" && env -u SIT_DIR HOME="$T/home" "$@" "$T/drv" --sit-dir 2>"$T/err") || RC=$?
}
expect() {  # <axis> <expected path>
    if [ "$RC" -ne 0 ] || [ "$OUT" != "$2" ]; then
        _fail "axis $1: --sit-dir printed '$OUT' (rc $RC), expected '$2'; stderr: $(cat "$T/err")"
    else
        echo "  ok: axis $1 -> $OUT"
    fi
}

mkdir -p "$T/home"
mksit "$T/sit"
mkdir -p "$T/main"

# 1 — absolute gitdir, relative commondir; the worktree is two levels away from any sit.
mkwt "$T/lanes/a/wt" "$T/main" a "gitdir: $T/main/.git/worktrees/a" "../.."
sitdir "$T/lanes/a/wt"; expect 1 "$T/sit"

# 2 — relative gitdir (from the worktree root) and relative commondir.
mkwt "$T/lanes/b/wt" "$T/main" b "gitdir: ../../../main/.git/worktrees/b" "../.."
sitdir "$T/lanes/b/wt"; expect 2 "$T/sit"

# 3 — absolute commondir, CRLF line end on the .git file.
mkwt "$T/lanes/c/wt" "$T/main" c "gitdir: $T/main/.git/worktrees/c" "$T/main/.git"
printf 'gitdir: %s\r\n' "$T/main/.git/worktrees/c" > "$T/lanes/c/wt/.git"
sitdir "$T/lanes/c/wt"; expect 3 "$T/sit"

# 4 — SIT_DIR is an override.
mksit "$T/othersit"
sitdir "$T/lanes/a/wt" SIT_DIR="$T/othersit"; expect 4a "$T/othersit"
sitdir "$T/lanes/a/wt" SIT_DIR="$T/nosit"
if [ "$RC" -ne 1 ] || [ -n "$OUT" ]; then
    _fail "axis 4b: SIT_DIR=$T/nosit gave rc $RC and stdout '$OUT' — an override with no build/sit must be a miss, not another sit"
elif ! grep -q "$T/nosit" "$T/err"; then
    _fail "axis 4b: the miss does not name SIT_DIR's path: $(cat "$T/err")"
else
    echo "  ok: axis 4b -> miss naming $T/nosit"
fi

# 5 — a plain checkout beside sit (branch b), the shape the row was written for.
sitdir "$T/main"; expect 5 "$T/sit"

# 6 — no sit anywhere: a worktree whose main checkout has no sibling sit.
mkdir -p "$T/deep/main2"
mkwt "$T/lanes/d/wt" "$T/deep/main2" d "gitdir: $T/deep/main2/.git/worktrees/d" "../.."
sitdir "$T/lanes/d/wt"
if [ "$RC" -ne 1 ] || [ -n "$OUT" ]; then
    _fail "axis 6: with no sit anywhere --sit-dir gave rc $RC and stdout '$OUT' (expected rc 1, empty)"
else
    for want in "$T/lanes/d/sit" "$T/deep/sit" "$T/home/Repos/sit" "SIT_DIR"; do
        grep -q -- "$want" "$T/err" || _fail "axis 6: the miss does not name '$want': $(cat "$T/err")"
    done
    echo "  ok: axis 6 -> $(cat "$T/err")"
fi

# 7 — $HOME/Repos/sit last; a .git file with no commondir is not followed.
mksit "$T/home/Repos/sit"
sitdir "$T/lanes/d/wt"; expect 7a "$T/home/Repos/sit"
mkdir -p "$T/sep/repo.git" "$T/far/sep"
printf 'gitdir: %s\n' "$T/sep/repo.git" > "$T/far/sep/.git"
sitdir "$T/far/sep"; expect 7b "$T/home/Repos/sit"
rm -rf "$T/home/Repos"

# 8 — LIVE: this tree, when it is a worktree.
if command -v git >/dev/null 2>&1 && [ -f "$ROOT/.git" ]; then
    COMMON=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$COMMON" ] && [ -d "$COMMON" ]; then
        MAIN=$(cd "$COMMON/.." && pwd -P)
        LIVE=$(cd "$MAIN/.." && pwd -P)/sit
        if [ -f "$LIVE/build/sit" ] && [ ! -f "$ROOT/../sit/build/sit" ]; then
            sitdir "$ROOT"; expect 8 "$LIVE"
        else
            echo "  n/a: axis 8 — $LIVE/build/sit absent or ../sit present (a plain sibling)"
        fi
    else
        echo "  n/a: axis 8 — git cannot name this worktree's common dir"
    fi
else
    echo "  n/a: axis 8 — $ROOT is not a git worktree"
fi

if [ "$FAILS" -ne 0 ]; then
    echo "FAIL: $NAME — $FAILS axis failure(s)"
    exit 1
fi
echo "PASS: $NAME"
