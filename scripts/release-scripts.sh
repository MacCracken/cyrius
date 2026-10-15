#!/bin/sh
# Copy every cyrius.cyml `[release] scripts` entry into a release staging bin/ directory.
# Usage: sh scripts/release-scripts.sh <stage-bin-dir>   (run from the repo root, as release-lib.sh is)
#
# The list is read from the manifest, never kept here: the macOS tarball builders hand-copied a
# subset (cyrius-prompt-info, cyrius-repl.sh) and left cyrius-watch.sh out of every macOS tarball,
# while the source install and the Linux x86_64 tarball shipped all three. The user's decision D4
# (2026-10-15): ship every entry. CHANGELOG [6.7.12]
#
# The lookup and the parse are release.yml's (the x86_64 Linux tarball) and install.sh's
# (_parse_release_array): the CLI shims live in scripts/shims/, the user-facing scripts flat in
# scripts/ — shims/ first. Every entry is checked before anything is copied, and a listed entry
# found in neither place, or a list that parses to nothing, FAILS: a skipped entry is a tarball
# that silently ships less than the manifest says.
set -e
DEST="${1:?usage: release-scripts.sh <stage-bin-dir>}"
# The same override release-lib.sh and install.sh's _parse_release_array honour.
CYML="${CYRIUS_CYML:-cyrius.cyml}"
[ -f "$CYML" ] || { echo "ERROR: release-scripts.sh: $CYML not found (run from the repo root)" >&2; exit 1; }

SCRIPTS=$(awk -v k="scripts" '
    /^\[release\]/ { in_r = 1; next }
    in_r && /^\[/ { exit }
    in_r && $1 == k {
        sub(/^[^=]+= \[/, ""); sub(/\].*$/, "")
        gsub(/[",]/, " "); gsub(/ +/, " ")
        sub(/^ +/, ""); sub(/ +$/, ""); print; exit
    }' "$CYML")
[ -n "$SCRIPTS" ] || { echo "ERROR: release-scripts.sh: $CYML has no [release] scripts list (or it parsed to nothing)" >&2; exit 1; }

_src() {
    if [ -f "scripts/shims/$1" ]; then echo "scripts/shims/$1"
    elif [ -f "scripts/$1" ]; then echo "scripts/$1"
    fi
}
for script in $SCRIPTS; do
    [ -n "$(_src "$script")" ] || { echo "ERROR: $CYML [release] scripts lists $script, found in neither scripts/shims/ nor scripts/" >&2; exit 1; }
done
mkdir -p "$DEST"
for script in $SCRIPTS; do
    cp "$(_src "$script")" "$DEST/"
    chmod +x "$DEST/$script"
done
