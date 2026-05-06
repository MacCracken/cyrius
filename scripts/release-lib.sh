#!/bin/sh
# Copy stdlib + dep bundles into a release staging directory.
# Usage: sh scripts/release-lib.sh <stage-lib-dir>
#
# Copies real .cyr files from lib/, follows valid symlinks,
# fetches dep bundles from GitHub when symlinks are broken (CI).
#
# Dep tags are parsed from cyrius.cyml — NEVER hardcode them here.
# v5.4.12 shipped sigil 2.8.3 instead of 2.8.4 because this script
# used to keep its own parallel DEPS list that drifted every time
# cyrius.cyml bumped a dep. Fixed in v5.4.12-1: tags now come from
# the [deps.NAME] blocks in cyrius.cyml at release time.

set -e
DEST="$1"
if [ -z "$DEST" ]; then echo "Usage: release-lib.sh <dest-dir>"; exit 1; fi
mkdir -p "$DEST"

# 1. Copy all real files and valid symlinks.
#
# v5.9.2: walk subdirs recursively so nested stdlib (e.g.
# `lib/unicode/*.cyr`) reaches the release tarball. Pre-fix, the
# flat `for f in lib/*.cyr` glob silently dropped subdir files —
# the v5.9.1 release tarball was missing lib/unicode/*.cyr,
# breaking downstream `cyrius deps` resolution for any consumer
# that pulled unicode modules. Mirrors the v5.8.49 fix in
# scripts/install.sh's --refresh-only path; the bug existed in
# both packaging entry points and only one was fixed at the time.
while IFS= read -r f; do
    [ -e "$f" ] || continue                # skip broken symlinks (deps fetched below)
    rel="${f#lib/}"
    dst="$DEST/$rel"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$f" ]; then
        cp -L "$f" "$dst"
    else
        cp "$f" "$dst"
    fi
done <<EOF_LIB
$(find -L lib -type f -name '*.cyr')
EOF_LIB

# 2. Dep bundles — single source of truth is cyrius.cyml.
CYML="${CYRIUS_CYML:-cyrius.cyml}"
if [ ! -f "$CYML" ]; then
    echo "  WARN: $CYML not found, skipping dep fetch"
else
    awk '
        /^\[deps\./ {
            name = $0
            gsub(/\[deps\.|\]/, "", name)
        }
        /^tag = / {
            gsub(/[" ]/, "")
            sub(/^tag=/, "")
            tag = $0
        }
        /^modules = / {
            gsub(/^modules = \[|\]$/, "")
            gsub(/"/, "")
            gsub(/,/, " ")
            if (name != "" && tag != "") {
                printf "%s %s %s\n", name, tag, $0
                name = ""; tag = ""
            }
        }
    ' "$CYML" | while read -r REPO TAG MODS; do
        [ -z "$REPO" ] && continue
        for MOD in $MODS; do
            BASE=$(basename "$MOD")
            if [ ! -f "$DEST/$BASE" ]; then
                URL="https://raw.githubusercontent.com/MacCracken/$REPO/$TAG/$MOD"
                printf "  fetch: %s@%s → %s\n" "$REPO" "$TAG" "$BASE"
                curl -sfL "$URL" -o "$DEST/$BASE" || echo "  WARN: failed to fetch $BASE"
            fi
        done
    done
fi

COUNT=$(find "$DEST" -type f -name '*.cyr' 2>/dev/null | wc -l)
echo "  $COUNT stdlib files staged"
