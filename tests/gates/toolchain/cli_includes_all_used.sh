#!/bin/sh
# Gate: every stdlib module the cyrius CLI includes is one it USES (6.6.20, CLN-13).
#
# THE FINDING. cbt/cyrius.cyr carried `include "lib/tagged.cyr"`, which pulls in lib/tagged.cyr,
# lib/result.cyr and lib/boxed.cyr. No fn of tagged.cyr was called by any cbt/*.cyr or by any
# other module the CLI includes (the one textual hit was a comment in cbt/commands.cyr) — it only
# added 18 dead fns (1,418 dead bytes) to every build of the CLI on every target. Removed.
#
# THE CHECK (static, no compile). For each `include "lib/X.cyr"` in the CLI's main (non-agnos)
# block whose module is NOT also reached through the CLI's other includes (so dropping the line
# really drops it): some fn that the line alone brings in — defined in X, or in the part of X's
# include closure nothing else reaches — must be referenced (called `name(` or taken `&name`) in
# cbt/*.cyr or in a module reached through the other includes. Comments are stripped and
# definition lines never count as uses. A redundant-but-harmless direct include (lib/syscalls.cyr,
# reached through lib/process.cyr too) is not judged.
#
# SELF-TEST. The census runs over a copy of cbt/cyrius.cyr with `include "lib/tagged.cyr"` put
# back and must flag exactly that — so a detector that has stopped seeing anything cannot read
# GREEN. MUTATION LEDGER (2026-10-06): restoring the include in the tree turns the main check RED
# naming lib/tagged.cyr; breaking the reference regex (no match ever) turns the main check RED on
# lib/args.cyr and lib/audit_walk.cyr and the self-test RED (it reports three, not one).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=cli_includes_all_used
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
cd "$ROOT" || { echo "FAIL: $NAME: cannot cd to $ROOT"; exit 1; }

# The `lib/*.cyr` a file includes, one per line (conditions ignored: a superset can only hide an
# unused include, never invent one).
incs_of() { sed -n 's/^[[:space:]]*include[[:space:]]*"\(lib\/[^"]*\.cyr\)".*/\1/p' "$1" 2>/dev/null; }

# The include closure of the roots on stdin, one path per line, sorted.
closure() {
    sort -u > "$W/cl.cur"
    while :; do
        : > "$W/cl.new"
        while IFS= read -r f; do [ -f "$f" ] && incs_of "$f" >> "$W/cl.new"; done < "$W/cl.cur"
        sort -u "$W/cl.cur" "$W/cl.new" > "$W/cl.next"
        cmp -s "$W/cl.next" "$W/cl.cur" && break
        mv "$W/cl.next" "$W/cl.cur"
    done
    cat "$W/cl.cur"
}

# census <cli source> — prints each unused direct include; the count of direct includes goes to
# $W/n and the ones actually judged (droppable, bringing in at least one fn) to $W/judged.
census() {
    _cli=$1
    # the main block: everything after the agnos guard's `#ifndef`
    awk '/^#ifndef CYRIUS_TARGET_AGNOS/ {on=1} on' "$_cli" > "$W/main.cyr"
    incs_of "$W/main.cyr" | sort -u > "$W/direct"
    for f in cbt/*.cyr; do [ "$f" = cbt/cyrius.cyr ] || incs_of "$f"; done | sort -u > "$W/cbt_incs"
    wc -l < "$W/direct" | tr -d ' ' > "$W/n"
    : > "$W/judged"
    while IFS= read -r X; do
        [ -f "$X" ] || { echo "$X (missing)"; continue; }
        grep -vxF "$X" "$W/direct" | cat - "$W/cbt_incs" | closure > "$W/others"
        # reached through another include: dropping this line drops nothing — not judged here
        grep -qxF "$X" "$W/others" && continue
        # what the line alone brings in: X and the part of its closure nothing else reaches
        echo "$X" | closure | grep -vxF -f "$W/others" > "$W/excl"
        for f in $(cat "$W/excl"); do
            sed -n 's/^[[:space:]]*\(pub[[:space:]]\{1,\}\|public[[:space:]]\{1,\}\|private[[:space:]]\{1,\}\)\{0,1\}fn[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\).*/\2/p' "$f"
        done | sort -u > "$W/fns"
        [ -s "$W/fns" ] || continue          # brings in no fn: nothing to judge by
        echo "$X" >> "$W/judged"
        # the corpus: cbt/*.cyr + the other modules, comments and definition lines removed
        for f in cbt/*.cyr $(cat "$W/others"); do [ -f "$f" ] && cat "$f"; done \
            | sed 's/#.*$//' | grep -v '^[[:space:]]*\(pub[[:space:]]*\|public[[:space:]]*\|private[[:space:]]*\)\{0,1\}fn[[:space:]]' > "$W/corpus"
        alt=$(paste -sd'|' "$W/fns")
        if ! grep -Eq "(^|[^A-Za-z0-9_])(${alt})[[:space:]]*\(|&(${alt})([^A-Za-z0-9_]|\$)" "$W/corpus"; then
            echo "$X"
        fi
    done < "$W/direct"
}

fail=0

# ── the tree ────────────────────────────────────────────────────────────────────────────
census cbt/cyrius.cyr > "$W/unused"
N=$(cat "$W/n")
J=$(wc -l < "$W/judged" | tr -d ' ')
if [ "$N" -lt 10 ]; then
    echo "  FAIL: the census found only $N direct includes in cbt/cyrius.cyr (floor 10) — the parse is broken"; fail=1
fi
# Most direct includes are ALSO reached through another module (lib/string.cyr through nearly
# everything) and are not judged; the ones that are must not shrink to nothing unnoticed.
if [ "$J" -lt 2 ]; then
    echo "  FAIL: only $J of $N direct includes could be judged (floor 2) — the closure walk is broken"; fail=1
fi
if [ -s "$W/unused" ]; then
    while IFS= read -r u; do
        echo "  FAIL: cbt/cyrius.cyr includes $u, and nothing in the CLI calls a fn it defines — remove the include"
    done < "$W/unused"
    fail=1
else
    echo "  ok: no include in cbt/cyrius.cyr brings in only dead code ($J of $N judged: $(tr '\n' ' ' < "$W/judged")— the rest are reached through other modules too)"
fi

# ── self-test: the detector still sees an unused include ───────────────────────────────
awk '{print} /^include "lib\/fs.cyr"/ {print "include \"lib/tagged.cyr\""}' cbt/cyrius.cyr > "$W/cli_probe.cyr"
grep -q '^include "lib/tagged.cyr"' "$W/cli_probe.cyr" || { echo "  FAIL: self-test could not plant the probe include"; fail=1; }
census "$W/cli_probe.cyr" > "$W/unused_probe"
if [ "$(cat "$W/unused_probe")" = "lib/tagged.cyr" ]; then
    echo "  ok: self-test — a planted include \"lib/tagged.cyr\" is flagged (and nothing else)"
else
    echo "  FAIL: self-test — a planted include \"lib/tagged.cyr\" gave: [$(tr '\n' ' ' < "$W/unused_probe")]"; fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME ($N direct stdlib includes, $J judged droppable, none dead; detector self-tested)"
