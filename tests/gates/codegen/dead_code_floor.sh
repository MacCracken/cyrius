#!/bin/sh
# dead_code_floor.sh — 6.6.20. The compiler's own dead code is a RATCHET, not a note.
#
# ⛔ WHY. cycc prints `note: N unreachable fns` on every build, and the closeout's dead-code pass
# "records the floor" — in prose, which nothing reads back. Measured at the 6.6.20 open: x86 cycc
# carried 73 unreachable fns / 36,937 B, 24 of them defined in src/ and dead in EVERY fork that
# compiles their file — the arm64 Mach-O writer (15.8 KB, 43 % of the dead bytes) compiled into
# every x86-family compiler, a TS JSX walker superseded at v5.7.6, x86-named stubs in the aarch64
# and cx backends whose comments claimed parse.cyr needed them (no shared file had referenced them
# for releases), and a helper only the cx fork calls living in shared parse_fn.cyr. None of it was
# a bug a test could see; all of it was something a reader had to wade through and trust.
#
#   axis 1  every unreachable fn DEFINED UNDER src/, in each of the 7 forks, is on that fork's
#           row of tests/fixtures/dead_code_floor.txt (stdlib fns pulled in from lib/ are
#           external API surface and are not counted). A fn that newly goes dead is NAMED: delete
#           it, move it to the backend/fork that calls it (the 6.6.20 `_gvar_bytes_named` /
#           emit_arm64.cyr fix), or — only if it is genuinely external surface, or dead here and
#           live in another fork that compiles the same file — add it to the floor. A floor
#           entry that is no longer dead is reported, not failed: drop it.
#           ⚠ A list, not a per-fork count: a count lets one fn going live hide another going
#           dead, and when it trips it can only print the whole floor.
#           ⚠ The parse is cross-checked against the compiler's own `note: N unreachable fns`,
#           so a change to the `dead:` line format cannot turn this gate into a silent pass.
#
# `--write` regenerates the floor from the tree (review the diff — it is the whole point).
# The fork commands mirror scripts/version-bump.sh; the two aarch64-hosted forks are built by
# the cross compiler this gate builds first (cycc_aarch64 is an x86 binary).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL dead_code_floor: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL dead_code_floor: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
FLOOR="$R/tests/fixtures/dead_code_floor.txt"
[ -x "$CC" ] || { echo "FAIL dead_code_floor: no build/cycc"; exit 1; }
fails=0

# ── axis 1 — per-fork floor of src/-defined unreachable fns ───────────────────────────────────
grep -rhoE '^[[:space:]]*\}?fn [A-Za-z_][A-Za-z0-9_]*\(' src --include='*.cyr' \
    | sed -E 's/^[[:space:]]*\}?fn //; s/\($//' | sort -u > "$T/srcfns"
[ -s "$T/srcfns" ] || { echo "FAIL dead_code_floor: found no fn definitions under src/"; exit 1; }
: > "$T/actual"

# _fork NAME ENV COMPILER SOURCE  — appends "FN FORK" for each src/-defined dead fn
_fork() {
    _n=$1; _e=$2; _c=$3; _s=$4
    if ! env $_e CYRIUS_DCE_VERBOSE=1 "$_c" < "$_s" > "$T/$_n.bin" 2> "$T/$_n.err"; then
        echo "FAIL dead_code_floor axis1: $_n ($_s) did not build"; sed -n 1,5p "$T/$_n.err"
        fails=$((fails + 1)); return 0
    fi
    # `|| true`: a fork with no dead fns prints neither line, and under `bash -eo pipefail` a
    # no-match grep would end the gate silently.
    { grep '^  dead: ' "$T/$_n.err" || true; } | awk '{print $2}' | sort -u > "$T/$_n.dead"
    _note=$({ grep -o 'note: [0-9]* unreachable fns' "$T/$_n.err" || true; } | awk '{print $2; exit}')
    _nd=$(wc -l < "$T/$_n.dead" | tr -d ' ')
    if [ "${_note:-0}" != "$_nd" ]; then
        echo "FAIL dead_code_floor axis1: $_n — the compiler reports ${_note:-no} unreachable fns but $_nd \`  dead: NAME\` lines parsed (CYRIUS_DCE_VERBOSE output changed?)"
        fails=$((fails + 1)); return 0
    fi
    comm -12 "$T/srcfns" "$T/$_n.dead" | sed "s/\$/ $_n/" >> "$T/actual"
}
_fork x86  ""                    "$CC" src/main.cyr
_fork a64  ""                    "$CC" src/main_aarch64.cyr
_fork cx   ""                    "$CC" src/main_cx.cyr
_fork win  "CYRIUS_TARGET_WIN=1" "$CC" src/main_win.cyr
_fork x86m "CYRIUS_MACHO=1"      "$CC" src/main_x86_macho.cyr
if [ -s "$T/a64.bin" ]; then
    chmod +x "$T/a64.bin"
    _fork a64n ""                   "$T/a64.bin" src/main_aarch64_native.cyr
    _fork a64m "CYRIUS_MACHO_ARM=1" "$T/a64.bin" src/main_aarch64_macho.cyr
fi
sort -u "$T/actual" -o "$T/actual"

if [ "${1:-}" = "--write" ]; then
    [ "$fails" -eq 0 ] || { echo "FAIL dead_code_floor --write: a fork did not build; floor NOT written"; exit 1; }
    {
        echo "# dead_code_floor.txt — the unreachable fns DEFINED UNDER src/ that each compiler fork carries."
        echo "# Read by tests/gates/codegen/dead_code_floor.sh; regenerate with its --write and REVIEW the diff."
        echo "# One line per fn: NAME FORK... — x86 = cycc (main.cyr), a64 = cycc_aarch64 cross"
        echo "# (main_aarch64.cyr), cx = cyrius-x (main_cx.cyr), win = PE32+ (main_win.cyr), x86m = x86-macOS"
        echo "# (main_x86_macho.cyr), a64n = aarch64-native (main_aarch64_native.cyr), a64m = arm64-macOS"
        echo "# (main_aarch64_macho.cyr). Each is live in another fork that compiles the same file (IR"
        echo "# passes only the x86 backend drives, PE- or Mach-O-only emitters, ...) — except TS_PEEKLINE,"
        echo "# which tests/tcyr/frontend/ts_lex_combined.tcyr calls."
        awk '{ if ($1 != prev) { if (prev != "") print line; line = $1; prev = $1 } line = line " " $2 }
             END { if (prev != "") print line }' "$T/actual"
    } > "$FLOOR"
    echo "dead_code_floor: wrote $(grep -vc '^#' "$FLOOR") fns ($(wc -l < "$T/actual" | tr -d ' ') fork entries) to tests/fixtures/dead_code_floor.txt"
    exit 0
fi

[ -s "$FLOOR" ] || { echo "FAIL dead_code_floor: missing $FLOOR (generate it with --write)"; exit 1; }
grep -v '^#' "$FLOOR" | awk 'NF { for (i = 2; i <= NF; i++) print $1, $i }' | sort -u > "$T/allowed"
comm -23 "$T/actual" "$T/allowed" > "$T/new"
comm -13 "$T/actual" "$T/allowed" > "$T/gone"
if [ -s "$T/new" ]; then
    echo "FAIL dead_code_floor axis1: $(wc -l < "$T/new" | tr -d ' ') src/ fn(s) newly unreachable (FN FORK) — delete, move to the fork that calls it, or add to tests/fixtures/dead_code_floor.txt and say why in the commit:"
    sed 's/^/    /' "$T/new"
    fails=$((fails + 1))
fi
if [ -s "$T/gone" ]; then
    echo "  note: $(wc -l < "$T/gone" | tr -d ' ') floor entr(y/ies) no longer dead (FN FORK) — drop from tests/fixtures/dead_code_floor.txt (or rerun with --write):"
    sed 's/^/    /' "$T/gone"
fi

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "PASS dead_code_floor: $(wc -l < "$T/actual" | tr -d ' ') src/ dead-fn entries across 7 forks, all on the floor"
exit 0
