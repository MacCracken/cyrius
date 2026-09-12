#!/bin/sh
# tracked_paths_portable.sh — v6.6.3. Every TRACKED path must be checkoutable on every OS
# this project claims to support.
#
# WHY THIS GATE EXISTS. A file named `c -l)|XX|` — the debris of a mis-quoted shell
# redirect — was committed. On Linux that is a legal filename and NOTHING noticed: the
# full release gate ran GREEN, all five steps, including the cross-OS self-host leg on
# real macOS / Windows / aarch64 hardware. It went green because that leg SCPs binaries
# to the hosts; it never checks the repository out on them. The Windows CI job did, and
# died before compiling a single byte:
#
#     error: invalid path 'c -l)|XX|'
#     The process 'git.exe' failed with exit code 128
#
# ⭐ The failure reported itself as "Windows PE32+ failing", which it was not — the
# toolchain was never reached. A whole platform's coverage was silently voided by a
# filename, and every compiler gate we own was structurally incapable of seeing it,
# because they all inspect FILE CONTENT and this defect lives in the FILE NAME.
#
# The rules below are git's own and Win32's, not a style preference: git refuses to
# check out a path containing <>:"|?* or a control byte, a component ending in a dot or
# space, or a reserved DOS device name. Case-insensitive collisions check out on
# Windows/macOS as ONE file, silently losing the other.
#
# The gate reads the INDEX, not the worktree, because the index is what CI checks out:
# deleting the offending file locally does not clear this until the deletion is staged.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 1
command -v git >/dev/null 2>&1 || { echo "FAIL tracked_paths_portable: git not available"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "FAIL tracked_paths_portable: not a git repo"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git ls-files > "$T/paths" 2>/dev/null
N=$(wc -l < "$T/paths")
# Anti-vacuous floor. An empty or truncated listing must not read as "all paths portable"
# — that is the unmatched-glob fake-PASS this project has been bitten by before.
[ "$N" -ge 500 ] || { echo "FAIL tracked_paths_portable: only $N tracked paths listed, expected >= 500 — the reader went blind"; exit 1; }

bad=0
report() { echo "  $1"; sed 's/^/      /' "$2"; bad=1; }

grep -P '[<>:"|?*]|[\x01-\x1f]' "$T/paths" > "$T/r1" 2>/dev/null
[ -s "$T/r1" ] && report 'path contains a character Windows forbids (< > : " | ? * or a control byte):' "$T/r1"

awk -F/ '{for(i=1;i<=NF;i++) if ($i ~ /[ .]$/) {print; next}}' "$T/paths" > "$T/r2"
[ -s "$T/r2" ] && report 'path component ends in a dot or a space (Windows strips it, then the path collides):' "$T/r2"

awk -F/ '{n=$NF; sub(/\..*$/,"",n); if (toupper(n) ~ /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/) print}' "$T/paths" > "$T/r3"
[ -s "$T/r3" ] && report 'path uses a reserved DOS device name:' "$T/r3"

tr 'A-Z' 'a-z' < "$T/paths" | sort | uniq -d > "$T/r4"
[ -s "$T/r4" ] && report 'paths differ only by case — Windows/macOS check these out as ONE file:' "$T/r4"

awk 'length($0) > 240 {print length($0)": "$0}' "$T/paths" > "$T/r5"
[ -s "$T/r5" ] && report 'path exceeds 240 characters (MAX_PATH headroom on Windows):' "$T/r5"

if [ "$bad" -ne 0 ]; then
  echo "FAIL tracked_paths_portable: the repository cannot be checked out on Windows."
  echo "  git aborts the checkout, so EVERY Windows job dies before it compiles anything —"
  echo "  and reports as whatever job name it was wearing, not as a path problem."
  exit 1
fi

echo "PASS tracked_paths_portable: $N tracked paths, all checkoutable on Windows/macOS/Linux"
exit 0
