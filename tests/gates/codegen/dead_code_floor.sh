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
#   axis 1  per fork, the unreachable fns DEFINED UNDER src/ (stdlib fns pulled in from lib/ are
#           external API surface and are not counted) stay at or under that fork's ceiling. When
#           this fails it lists the fork's src/ dead fns: either delete the newcomer, move it to
#           the backend/fork that calls it (the 6.6.20 `_gvar_bytes_named` / emit_arm64.cyr fix),
#           or — only if it is genuinely external surface (a test or tool calls it) — raise the
#           ceiling here and say why. A fork that drops BELOW its ceiling is reported, not
#           failed: lower the number in the same change.
#
# The fork commands mirror scripts/version-bump.sh; the two aarch64-hosted forks are built by
# the cross compiler this gate builds first (cycc_aarch64 is an x86 binary).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL dead_code_floor: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL dead_code_floor: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL dead_code_floor: no build/cycc"; exit 1; }
fails=0

# ── axis 1 — per-fork ceiling on src/-defined unreachable fns ─────────────────────────────────
_ceiling() {
    case $1 in
        x86)  echo 1 ;;   # cycc                       (src/main.cyr)
        a64)  echo 72 ;;   # cycc_aarch64 cross          (src/main_aarch64.cyr)
        cx)   echo 72 ;;   # cyrius-x                    (src/main_cx.cyr)
        win)  echo 39 ;;   # PE32+                       (src/main_win.cyr, CYRIUS_TARGET_WIN=1)
        x86m) echo 69 ;;   # x86-macOS                   (src/main_x86_macho.cyr, CYRIUS_MACHO=1)
        a64n) echo 72 ;;   # aarch64-native              (src/main_aarch64_native.cyr)
        a64m) echo 76 ;;  # arm64-macOS                 (src/main_aarch64_macho.cyr, CYRIUS_MACHO_ARM=1)
    esac
}
grep -rhoE '^[[:space:]]*\}?fn [A-Za-z_][A-Za-z0-9_]*\(' src --include='*.cyr' \
    | sed -E 's/^[[:space:]]*\}?fn //; s/\($//' | sort -u > "$T/srcfns"
[ -s "$T/srcfns" ] || { echo "FAIL dead_code_floor: found no fn definitions under src/"; exit 1; }

# _fork NAME ENV COMPILER SOURCE
_fork() {
    _n=$1; _e=$2; _c=$3; _s=$4
    if ! env $_e CYRIUS_DCE_VERBOSE=1 "$_c" < "$_s" > "$T/$_n.bin" 2> "$T/$_n.err"; then
        echo "FAIL dead_code_floor axis1: $_n ($_s) did not build"; sed -n 1,5p "$T/$_n.err"
        fails=$((fails + 1)); return 0
    fi
    grep '^  dead: ' "$T/$_n.err" | awk '{print $2}' | sort -u > "$T/$_n.dead"
    comm -12 "$T/srcfns" "$T/$_n.dead" > "$T/$_n.srcdead"
    _got=$(wc -l < "$T/$_n.srcdead" | tr -d ' ')
    _max=$(_ceiling "$_n")
    if [ "$_got" -gt "$_max" ]; then
        echo "FAIL dead_code_floor axis1: $_n ($_s) has $_got unreachable fns defined under src/, ceiling $_max — delete the newcomer, move it to the fork that calls it, or raise the ceiling with a reason:"
        sed 's/^/    /' "$T/$_n.srcdead"
        fails=$((fails + 1))
    elif [ "$_got" -lt "$_max" ]; then
        echo "  note: $_n is at $_got src/ dead fns, below its ceiling $_max — lower the ceiling in tests/gates/codegen/dead_code_floor.sh"
    fi
}
_fork x86  ""                   "$CC"     src/main.cyr
_fork a64  ""                   "$CC"     src/main_aarch64.cyr
_fork cx   ""                   "$CC"     src/main_cx.cyr
_fork win  "CYRIUS_TARGET_WIN=1" "$CC"    src/main_win.cyr
_fork x86m "CYRIUS_MACHO=1"     "$CC"     src/main_x86_macho.cyr
if [ -s "$T/a64.bin" ]; then
    chmod +x "$T/a64.bin"
    _fork a64n ""                   "$T/a64.bin" src/main_aarch64_native.cyr
    _fork a64m "CYRIUS_MACHO_ARM=1" "$T/a64.bin" src/main_aarch64_macho.cyr
fi

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "PASS dead_code_floor: 7 forks at or under their src/ dead-fn ceilings"
exit 0
