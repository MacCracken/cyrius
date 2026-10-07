#!/bin/sh
# Gate: `cyrius clean` never deletes a binary the repo TRACKS (6.6.20, CBT-04).
#
# THE DEFECT. cmd_clean's keep-set (cbt/commands.cyr) was cc, cycc, cybs, asm, cycc_aarch64 and
# cyrius. The repo tracks three build/ binaries — .gitignore's `!/build/...` whitelist: cycc,
# cc5 and cycc-native-aarch64 — so `cyrius clean` in the repo unlinked cc5 and
# cycc-native-aarch64. The second is the one cross-bin that cannot be regenerated without ARM
# hardware (CLAUDE.md: "Do not remove build/cycc-native-aarch64"; release-gate step 1b keeps it
# in lockstep), recoverable only by `git checkout`.
#
# AXES
#   0  the tracked set is DERIVED from .gitignore's whitelist (a floor of 3 names, and it must
#      name cycc-native-aarch64), and agrees with `git ls-files build/` when this is a checkout —
#      so a binary tracked later joins the gate without an edit here.
#   1  `cyrius clean --dry-run` lists the junk and no tracked name
#   2  `cyrius clean` removes the junk and every tracked binary is still there, byte-identical
#   3  the toolchain names the CLI runs from (cycc, cybs, asm, cycc_aarch64, cyrius) survive too
#
# MUTATION: cbt/commands.cyr's `_clean_keeps` without the cc5 / cycc-native-aarch64 rows (the
# 6.6.19 keep-set) fails axes 1 and 2 for both names.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=clean_keeps_tracked_binaries
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$T/cyrius" 2> "$T/build.err" ) || {
    echo "FAIL: $NAME — could not build cbt/cyrius.cyr"; sed -n '1,5p' "$T/build.err"; exit 1; }
chmod +x "$T/cyrius"

echo "axis 0 — the tracked build/ binaries, derived from .gitignore:"
TRACKED=$(sed -n 's|^!/build/\([^/*]*\)$|\1|p' "$ROOT/.gitignore" | sort)
n_tr=$(printf '%s\n' "$TRACKED" | grep -c . || true)
check "the .gitignore whitelist names at least 3 build/ binaries" "yes" "$([ "$n_tr" -ge 3 ] && echo yes || echo no)"
check "it names cycc-native-aarch64" "yes" "$(printf '%s\n' "$TRACKED" | grep -qx 'cycc-native-aarch64' && echo yes || echo no)"
if git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    IDX=$(git -C "$ROOT" ls-files build/ | sed 's|^build/||' | sort)
    check "git ls-files build/ == the .gitignore whitelist" "$TRACKED" "$IDX"
else
    echo "  note: not a git checkout — the index cross-check is skipped"
fi

P="$T/proj"; mkdir -p "$P/build" "$T/hh" "$T/cyhome"
for b in $TRACKED cycc cybs asm cycc_aarch64 cyrius; do
    printf 'tracked-%s\n' "$b" > "$P/build/$b"
done
printf 'junk\n' > "$P/build/junk.o"
printf 'junk\n' > "$P/build/main"

cy() {
    ( cd "$P" && HOME="$T/hh" CYRIUS_HOME="$T/cyhome" timeout 120 "$T/cyrius" "$@" ) > "$T/o" 2>&1
}

echo "axis 1 — clean --dry-run lists the junk and no tracked binary:"
cy clean --dry-run
check "dry run rc 0" 0 "$?"
check "junk.o would be removed" "yes" "$(grep -q 'would remove: build/junk.o' "$T/o" && echo yes || echo no)"
for b in $TRACKED; do
    check "build/$b is NOT in the would-remove list" "no" "$(grep -q "would remove: build/$b\$" "$T/o" && echo yes || echo no)"
done

echo "axis 2 — clean removes the junk and keeps every tracked binary byte-for-byte:"
cy clean
check "clean rc 0" 0 "$?"
check "build/junk.o removed" "no" "$([ -e "$P/build/junk.o" ] && echo yes || echo no)"
check "build/main removed" "no" "$([ -e "$P/build/main" ] && echo yes || echo no)"
for b in $TRACKED; do
    check "build/$b kept, unchanged" "tracked-$b" "$(cat "$P/build/$b" 2>/dev/null || echo MISSING)"
done

echo "axis 3 — the toolchain the CLI runs from is kept too:"
for b in cycc cybs asm cycc_aarch64 cyrius; do
    check "build/$b kept" "yes" "$([ -f "$P/build/$b" ] && echo yes || echo no)"
done

if [ "$fails" = "0" ]; then
    echo "PASS: $NAME — cyrius clean keeps every tracked build/ binary ($(echo $TRACKED))"
    exit 0
fi
echo "FAIL: $NAME — $fails assertion(s) failed"
exit 1
