#!/bin/sh
# scripts/folds/sibci.sh — run ONE fold release's full GitHub CI locally, the way GitHub would
# run it, fully isolated. A fold is a folded stdlib (docs/ecosystem.md); consumers are never run.
#   - a clean `git archive <commit>` copy (committed files only), with any `path = "../X"` dep
#     line commented out (a path dep beats a tag and would read the local worktree, not the
#     release);
#   - a throwaway CYRIUS_HOME holding a COPY of <store>/<the fold's pin> and an EMPTY deps/ (so
#     every dep tag is fetched from GitHub), and HOME pointed at a throwaway dir too — a CI
#     "Install Cyrius toolchain" step can never reach the live ~/.cyrius (the 6.6.12 incident);
#   - the steps run by run-ci.py (beside this script) with GitHub's shell semantics.
#
# Usage:  scripts/folds/sibci.sh <fold> <commit-or-tag> [workdir]
#         many at once:  awk '{print $1, $2}' list | xargs -P4 -n2 scripts/folds/sibci.sh
#   <fold> is the fold's NAME (its checkout is $CYRIUS_FOLDS_ROOT/<fold>), NOT a path: a path
#   exits 2 before anything is removed, and a bad fold or commit (no pin read from the archive's
#   cyrius.cyml) exits 2 before the store is copied, each with a named message. Read ok=N in the
#   summary, never rc=0 alone (a copy with no runnable step reads rc=0 ok=0). [workdir] (and
#   CYRIUS_SCRATCH) must be absolute: the run cd's into the copy.
#
# Inputs (environment; each default in parentheses):
#   CYRIUS_FOLDS_ROOT  where the fold checkouts live                ($HOME/Repos)
#   CYRIUS_STORE       the installed toolchain store, one slot per version
#                                                                   ($HOME/.cyrius/versions)
#   CYRIUS_SCRATCH     scratch root; the workdir is $CYRIUS_SCRATCH/sibci when no [workdir]
#                      argument is given                (${XDG_CACHE_HOME:-$HOME/.cache}/c6)
#   python3, and every tool a CI step calls, under /usr/local/bin:/usr/bin:/bin — the run's PATH
#   is reset to the slot's bin/, the qemu shim and those three (a CI image's shape);
#   qemu-aarch64 on the caller's PATH, optional, is shimmed as qemu-aarch64-static (the name CI
#   images use).
# Outputs:
#   stdout: one summary line, `<fold> @ <commit> (pin <v>): rc=N ok=N fail=N skip=N`;
#   <workdir>/<fold>/ci.log: the step log (run-ci.py's OK / FAIL / SKIP lines, CI_VERBOSE tails);
#   <workdir>/<fold>/ is left for inspection and wiped at the next run of the same fold.
#   Exit 2 when <fold> is a path, when no pin is read, or when the fold's pin is not installed in
#   the store; 1 when an argument is missing or the shim's mktemp / the cd into the copy fails;
#   otherwise 0 — the verdict is the summary line, not the exit status.
# Portability: POSIX sh; `cp -a` and `grep -m1` are GNU and BSD both (no GNU-only `sed -i`).
#
# Converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md
set -u
r=$1; c=$2
FOLDS=${CYRIUS_FOLDS_ROOT:-$HOME/Repos}
STORE=${CYRIUS_STORE:-$HOME/.cyrius/versions}
# A path here would make the `rm -rf "$W/$r"` below reach outside the workdir.
case "$r" in ''|.|..|*/*) echo "sibci.sh: <fold> is a fold NAME under $FOLDS, not a path: '$r'"; exit 2 ;; esac
W=${3:-${CYRIUS_SCRATCH:-${XDG_CACHE_HOME:-$HOME/.cache}/c6}/sibci}
T=$(cd "$(dirname "$0")" && pwd)
q=$(command -v qemu-aarch64 || true)
B=$W/$r
rm -rf "$B"; mkdir -p "$B/copy" "$B/home/versions" "$B/home/deps" "$B/fh"
git -C "$FOLDS/$r" archive "$c" | tar -x -C "$B/copy"
pin=$(grep -m1 '^cyrius *=' "$B/copy/cyrius.cyml" | sed 's/.*"\(.*\)".*/\1/')
# An empty pin would make "$STORE/$pin" the whole store, and the cp below would copy all of it.
[ -n "$pin" ] || { echo "$r @ $c: no pin read — git archive of $FOLDS/$r at $c failed, or its cyrius.cyml has no 'cyrius =' line"; exit 2; }
[ -d "$STORE/$pin" ] || { echo "$r @ $c: pin $pin is not installed in $STORE"; exit 2; }
cp -a "$STORE/$pin" "$B/home/versions/"
ln -s "versions/$pin/bin" "$B/home/bin"; ln -s "versions/$pin/lib" "$B/home/lib"; echo "$pin" > "$B/home/current"
ln -s "$B/home" "$B/fh/.cyrius"
# The qemu shim: a symlink made per run (a tracked symlink would pin one box's qemu path).
S=$(mktemp -d "$B/shim.XXXXXX") && [ -d "$S" ] || { echo "$r @ $c: mktemp -d failed under $B"; exit 1; }
[ -n "$q" ] && ln -s "$q" "$S/qemu-aarch64-static"
cd "$B/copy" || exit 1
sed 's/^\([[:space:]]*path *=.*\)$/# \1/' cyrius.cyml > cyrius.cyml.sibci && mv cyrius.cyml.sibci cyrius.cyml
git init -q && git add -A && git -c user.email=ci@local -c user.name=ci commit -q -m ci
export HOME="$B/fh" CYRIUS_HOME="$B/home" PATH="$B/home/bin:$S:/usr/local/bin:/usr/bin:/bin" \
       REPO_NAME="$r" CYRIUS_VERSION="$pin" RUNNER_TEMP="$B/rt" CI_VERBOSE=1
python3 "$T/run-ci.py" "$B/copy" > "$B/ci.log" 2>&1
rc=$?
echo "$r @ $c (pin $pin): rc=$rc ok=$(grep -c '^OK  ' "$B/ci.log") fail=$(grep -c '^FAIL' "$B/ci.log") skip=$(grep -c '^SKIP' "$B/ci.log")"
