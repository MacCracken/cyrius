#!/bin/sh
# cbt_readers_recursive.sh — 6.7.18 (the refactor review: cbt/commands.cyr and cbt/deps.cyr split into
# cbt/commands/ and cbt/deps/).
#
# EVERY READER OF THE CLI'S SOURCE READS cbt/ RECURSIVELY.
#
# THE DEFECT. Twenty-two gates read the CLI's source through a flat `cbt/*.cyr` glob (or
# `"$ROOT"/cbt/*.cyr`, `ls cbt/*.cyr`, python's `'cbt/*.cyr'`): the fork-site, exec-site, temp-name,
# write-length, manifest-read, scp-pillar, raw-syscall and tool-lookup scans, the auto-deps verb
# graph, the include census. The verb and stage split moves the bulk of the CLI one level down, and a
# flat glob skips a subfolder in silence: each of those scans would have read core.cyr, build.cyr and
# the rest, found nothing wrong in what it read, and passed over the two files that hold most of the
# CLI. A floor of "8 files" or "10 files" does not notice — the top level still holds that many. The
# same class as the flat `tests/tcyr/*.tcyr` glob CLAUDE.md forbids. CHANGELOG [6.7.18]
#
# WHAT IS PINNED (static): no line of a gate, a script or a workflow — comments excluded — spells a
# flat glob over cbt/ (`cbt/*.cyr`, with any prefix). The readers use `find cbt -name '*.cyr'` (or
# `cbt/**/*.cyr` with python's recursive glob). The scanner is self-tested on a fixture: the four
# flat spellings are flagged, a comment and the two recursive spellings are not. Floor: the census
# reads every tracked gate (>= 500 files), so a broken reader cannot read green.
#
# MUTATION LEDGER (measured at 6.7.18):
#   M1  the parent of this gate (the 22 flat readers)                        -> RED, 35 lines named
#   M2  one reader turned back (cbt_fork_sites_have_pe_arm.sh `scan cbt/*.cyr`) -> RED, that line
#   Real tree -> GREEN.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
NAME=cbt_readers_recursive
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0

# flat <file>... — every non-comment line that globs cbt/ one level deep, as file:line:text.
flat() {
    awk '{ c = $0; sub(/^[ \t]*/, "", c); if (substr(c, 1, 1) == "#") next
           if (index($0, "cbt/*.cyr") > 0) printf "%s:%d:%s\n", FILENAME, FNR, $0 }' "$@"
}

# ── self-test ────────────────────────────────────────────────────────────────────────────
cat > "$W/fx.sh" <<'FX'
scan cbt/*.cyr > "$T/sites"
for f in "$ROOT"/cbt/*.cyr; do :; done
nfiles=$(ls cbt/*.cyr | wc -l)
files = glob.glob('cbt/*.cyr')
# a comment naming cbt/*.cyr is prose
for f in $(find cbt -name '*.cyr' | LC_ALL=C sort); do :; done
files = glob.glob('cbt/**/*.cyr', recursive=True)
FX
got=$(flat "$W/fx.sh" | cut -d: -f2 | tr '\n' ' ')
if [ "$got" = "1 2 3 4 " ]; then
    echo "  ok: self-test — the four flat spellings are flagged; a comment and the two recursive readers are not"
else
    echo "  FAIL: self-test — the scanner flagged lines [$got], want [1 2 3 4 ]"
    fail=1
fi

# ── the census ──────────────────────────────────────────────────────────────────────────
git ls-files 'tests/gates/*.sh' 'scripts/*.sh' 'scripts/*' '.github/workflows/*.yml' 2>/dev/null \
    | LC_ALL=C sort -u > "$W/files"
nf=$(grep -c . "$W/files" || true); [ -n "$nf" ] || nf=0
ng=$(grep -c '^tests/gates/' "$W/files" || true); [ -n "$ng" ] || ng=0
if [ "$ng" -lt 500 ]; then
    echo "  FAIL: the census read only $ng tracked gate(s) (floor 500) — the reader is not reading"
    fail=1
fi
: > "$W/hits"
while IFS= read -r f; do
    [ -f "$f" ] || continue
    # this file spells the flat glob on purpose: its fixture and its matcher
    [ "$f" = "tests/gates/toolchain/$NAME.sh" ] && continue
    flat "$f" >> "$W/hits"
done < "$W/files"
if [ -s "$W/hits" ]; then
    echo "  FAIL: a reader globs cbt/ one level deep — it skips cbt/commands/ and cbt/deps/ in silence (use find cbt -name '*.cyr'):"
    sed 's/^/    /' "$W/hits"
    fail=1
else
    echo "  ok: no flat cbt/ glob in $nf gates, scripts and workflows ($ng gates)"
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL $NAME"
    exit 1
fi
echo "PASS $NAME: every reader of the CLI's source reads cbt/ recursively ($nf files censused, scanner self-tested)"
exit 0
