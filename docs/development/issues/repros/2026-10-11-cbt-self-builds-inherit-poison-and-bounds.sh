#!/bin/sh
# 2026-10-11 — the CLI's own self-builds hand an inherited CYRIUS_POISON / CYRIUS_BOUNDS to the
# compiler they build: `cyrius pulsar` (src/main.cyr -> the TRACKED build/cycc) and the on-demand
# cx compiler build (src/main_cx.cyr -> build/cycc_cx). Read-only for the tree: the CLI is built
# from cbt/cyrius.cyr into a mktemp directory, and each probe runs in a scratch "repo" there whose
# build/cycc is a stub that logs the two variables it sees and emits itself (so pulsar's stage 1
# == stage 2 and it moves on). HOME / CYRIUS_HOME are throwaways; pulsar stops at its install step
# (the scratch repo has no scripts/install.sh), so no store is touched.
# Run from the repo root: sh <this file>
# Expected: every self-build line reads "POISON=unset BOUNDS=unset" (the cx line for x.cyr — the
#           user's program — keeps the variables: that compile is the user's).
# Actual (6.7.9 quick lane, 2026-10-11): every line reads "POISON=1 BOUNDS=1".
set -u
ROOT=$(pwd)
[ -x build/cycc ] && [ -f cbt/cyrius.cyr ] || { echo "run from the cyrius repo root"; exit 2; }
T=$(mktemp -d) && [ -d "$T" ] || exit 1
trap 'rm -rf "$T"' EXIT
build/cycc < cbt/cyrius.cyr > "$T/cyrius" 2> /dev/null && chmod +x "$T/cyrius" || { echo "cbt/cyrius.cyr did not build"; exit 1; }
mkstub() {
    mkdir -p "$1/build" "$1/src" "$T/home"
    printf '#!/bin/sh\necho "  $STUBWHAT: POISON=${CYRIUS_POISON-unset} BOUNDS=${CYRIUS_BOUNDS-unset}" >> "$STUBLOG"\ncat > /dev/null\ncat "$0"\n' > "$1/build/cycc"
    chmod +x "$1/build/cycc"
}
# 1. cyrius pulsar: stage 1 and stage 2 of the cycc rebuild.
mkstub "$T/p"
echo 'var x = 1;' > "$T/p/src/main.cyr"; echo 6.7.9 > "$T/p/VERSION"
(cd "$T/p" && STUBWHAT="pulsar self-build" STUBLOG="$T/log" CYRIUS_POISON=1 CYRIUS_BOUNDS=1 \
    HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" "$T/cyrius" pulsar > /dev/null 2>&1)
# 2. the cx compiler, built on demand from src/main_cx.cyr (then it compiles x.cyr: the user's).
mkstub "$T/c"
echo 'var x = 1;' > "$T/c/src/main_cx.cyr"; echo 'var y = 2;' > "$T/c/x.cyr"
(cd "$T/c" && STUBWHAT="cx compiler build, then x.cyr" STUBLOG="$T/log" CYRIUS_POISON=1 CYRIUS_BOUNDS=1 \
    HOME="$T/home" CYRIUS_HOME="$T/home/.cyrius" PATH="$T/c/build:/usr/bin:/bin" \
    "$T/cyrius" build --target=cx x.cyr out.cyx > /dev/null 2>&1)
echo "what each compiler child saw (CYRIUS_POISON=1 CYRIUS_BOUNDS=1 inherited):"
cat "$T/log"
[ -x "$T/p/build/cycc" ] && echo "pulsar installed its self-build over the scratch build/cycc"
[ -x "$T/c/build/cycc_cx" ] && echo "the cx build left build/cycc_cx (install.sh --refresh-only installs a fresh one as it is)"
