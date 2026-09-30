#!/bin/sh
# tests/gates/toolchain/check_driver_builds_its_tools.sh — 6.6.10 (bite 12)
#
# THE CHECK DRIVER RUNS ONLY TOOLS IT BUILT FROM THE TREE UNDER TEST, IN THAT RUN.
#
# THE DEFECT. programs/checks/ executed NINE build products it never built — cyrfmt, cyrlint,
# cyrdoc, cyrius_api_surface, cyrld, cyrius-init, cyrius-lsp, the cyrius CLI and cycc_aarch64 —
# trusting whatever sat at build/<tool> on EXISTENCE alone, and for cyrfmt/cyrlint/cyrdoc it
# fell back to the RELEASED store's `$HOME/.cyrius/bin`. Those binaries are gitignored and
# rebuilt only by install.sh, on an mtime rule that never looks at build/cycc or src/, so a
# row's verdict could be about a binary from a different tree (v6.4.81 fixed this for
# cycc_win_cross alone). Now `_tool()` builds each one with build/cycc from its source into
# the run's private dir the first time a row asks, a compile failure is a FAIL row that names
# the tool, and there is no ~/.cyrius/bin fallback. A root with NO source for a tool (a gate's
# scratch root) runs the build/<tool> it was given and says so — the fail-closed gates inject
# their fakes that way.
#
# AXES
#   1  a scratch TREE (every top-level entry of the repo linked in, build/ holding only cycc
#      and a logging STUB for each of the nine tools): `--tool-path` answers a path inside the
#      run's private dir for all nine, never build/<tool>, and no stub ever runs
#   2  END TO END in the same tree: the `linker`, `fmt` and `lint` rows PASS although every
#      stub prints a wrong verdict, and still no stub runs
#   3  the RELEASED STORE is never consulted: a root with no source and no build/cyrld, whose
#      $HOME/.cyrius/bin holds a cyrld/cyrfmt stub, SKIPs the rows (build/cyrld not present)
#      and runs no stub
#   4  the injection contract: a root with no source but a planted build/cyrld runs THAT, and
#      prints the note naming it
#   5  a tool that does not compile is a FAIL row naming it (a broken programs/cyrld.cyr)
#   6  STATIC ratchet: programs/checks/*.cyr names none of the nine as `_root_path("build/<t>")`
#      and never builds a `.cyrius/bin` path
#   7  6.6.12 (S5): `--tool-path <unknown>` exits 1 AND says so on stderr, naming the tool and
#      both places it looked (it used to exit 1 with both streams empty); stdout stays empty,
#      and a KNOWN name in the same root still answers 0 (anti-vacuous)
#
# MUTATIONS (each RED, measured when this gate was written):
#   M1 `_tool_build` returns build/<name> whenever it exists (the old trust)   -> axes 1, 2
#   M2 the ~/.cyrius/bin fallback restored in `_tool_build`                   -> axis 3
#   M3 a failed compile returns 0 silently (no FAIL row)                     -> axis 5
#   M4 the `_tool_path_unknown(tn)` call dropped from the --tool-path arm     -> axis 7
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=check_driver_builds_its_tools
[ -x "$CC" ] || { echo "FAIL: $NAME — no compiler at $CC"; exit 1; }
case "$(uname -s)" in Linux) : ;; *) echo "SKIP: $NAME — the check driver is a Linux program"; exit 77 ;; esac
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }
# 6.6.11 (K2): + cc_win, the main_win.cyr PE driver the cli-cross row builds cyrsign with.
TOOLS="cyrfmt cyrlint cyrdoc cyrius_api_surface cyrld cyrius-init cyrius-lsp cyrius cycc_aarch64 cc_win"
NTOOLS=$(echo $TOOLS | wc -w)

( cd "$ROOT" && cat programs/checks/main.cyr | "$CC" > "$D/drv" 2>"$D/drv.err" ) \
    || { cat "$D/drv.err"; echo "FAIL: $NAME — the check driver does not compile"; exit 1; }
chmod +x "$D/drv"
mkdir -p "$D/rt" "$D/nohome"

LOG="$D/stub.log"
: > "$LOG"
stub() {   # $1 path — a tool that logs that it ran and prints a WRONG verdict
    printf '#!/bin/sh\necho "RAN $0 $*" >> "%s"\necho "5 warnings"\necho "garbage"\nexit 0\n' "$LOG" > "$1"
    chmod +x "$1"
}
drive() {  # $1 root, $2 out, rest = driver args
    _r=$1; _o=$2; shift 2
    DRC=0
    ( cd "$_r" && HOME="$D/nohome" TMPDIR="$D/rt" timeout 300 "$D/drv" "$@" ) > "$_o.raw" 2>&1 || DRC=$?
    strip_ansi < "$_o.raw" > "$_o"
}

# ── the scratch TREE ─────────────────────────────────────────────────────────────────────
T="$D/tree"
mkdir -p "$T/build"
for e in "$ROOT"/* "$ROOT"/.[!.]*; do
    [ -e "$e" ] || continue
    b=$(basename "$e")
    case "$b" in build|.git) continue ;; esac
    ln -s "$e" "$T/$b"
done
cp "$CC" "$T/build/cycc"
for t in $TOOLS; do stub "$T/build/$t"; done

echo "axis 1: --tool-path builds all $NTOOLS into the run's private dir"
NOK=0
for t in $TOOLS; do
    drive "$T" "$D/a1_$t" --tool-path "$t"
    line=$(grep -E "^$t " "$D/a1_$t" | tail -1)
    p=${line#"$t "}
    case "$p" in
        "$D/rt/cyrcheck."*"/tree/build/$t") NOK=$((NOK + 1)) ;;
        *) _fail "axis 1: $t resolved to '${p:-<nothing>}' (rc $DRC), not a path in the run's private dir"
           sed 's/^/      /' "$D/a1_$t" | tail -5 ;;
    esac
    [ "$DRC" = 0 ] || _fail "axis 1: --tool-path $t exited $DRC"
done
[ "$NOK" = "$NTOOLS" ] || _fail "axis 1: $NOK of $NTOOLS tools came from the run's private dir"
[ -s "$LOG" ] && { _fail "axis 1: a planted build/ stub RAN:"; sed 's/^/      /' "$LOG"; }
[ -z "$(ls -A "$D/rt")" ] || _fail "axis 1: --tool-path left its run dir behind: $(ls "$D/rt")"

echo "axis 2: the linker, fmt and lint rows pass on the built tools, and no stub runs"
for row in linker fmt lint; do
    : > "$LOG"
    drive "$T" "$D/a2_$row" "$row"
    [ "$DRC" = 0 ] || { _fail "axis 2: row '$row' exited $DRC in the stub tree"; grep -E 'FAIL|SKIP' "$D/a2_$row" | sed 's/^/      /' | head -5; }
    grep -qE '^[1-9][0-9]* passed, 0 failed, 0 skipped' "$D/a2_$row" \
        || _fail "axis 2: row '$row' tally is '$(grep -E 'passed,' "$D/a2_$row" | tail -1)'"
    [ -s "$LOG" ] && { _fail "axis 2: row '$row' ran a planted stub:"; sed 's/^/      /' "$LOG" | head -3; }
done

echo "axis 3: no ~/.cyrius/bin fallback"
N="$D/nosrc"
mkdir -p "$N/build" "$D/fakehome/.cyrius/bin"
cp "$CC" "$N/build/cycc"
ln -s "$ROOT/lib" "$N/lib"
ln -s "$ROOT/tests" "$N/tests"
for t in cyrld cyrfmt cyrlint; do stub "$D/fakehome/.cyrius/bin/$t"; done
: > "$LOG"
DRC=0
( cd "$N" && HOME="$D/fakehome" TMPDIR="$D/rt" timeout 120 "$D/drv" linker ) > "$D/a3.raw" 2>&1 || DRC=$?
strip_ansi < "$D/a3.raw" > "$D/a3"
grep -q '^  SKIP: cyrld cross-module link — build/cyrld not present$' "$D/a3" \
    || _fail "axis 3: with no source and no build/cyrld the linker row did not SKIP naming build/cyrld: $(grep -E 'PASS|FAIL|SKIP' "$D/a3" | head -2)"
DRC=0
( cd "$N" && HOME="$D/fakehome" TMPDIR="$D/rt" timeout 120 "$D/drv" fmt ) > "$D/a3f.raw" 2>&1 || DRC=$?
[ -s "$LOG" ] && { _fail "axis 3: the driver ran a tool from \$HOME/.cyrius/bin:"; sed 's/^/      /' "$LOG" | head -3; }

echo "axis 4: a root with no source runs the build/<tool> it was given, and says so"
stub "$N/build/cyrld"
: > "$LOG"
drive "$N" "$D/a4" linker
grep -q '^  note: this root has no programs/cyrld.cyr — running the build/cyrld it was given$' "$D/a4" \
    || _fail "axis 4: no note naming the planted build/cyrld"
[ -s "$LOG" ] || _fail "axis 4: the planted build/cyrld did not run in a root without its source"

echo "axis 5: a tool that does not compile is a FAIL naming it"
B="$D/broken"
mkdir -p "$B/build" "$B/programs"
for e in "$ROOT"/* "$ROOT"/.[!.]*; do
    [ -e "$e" ] || continue
    b=$(basename "$e")
    case "$b" in build|.git|programs) continue ;; esac
    ln -s "$e" "$B/$b"
done
for e in "$ROOT"/programs/*; do ln -s "$e" "$B/programs/$(basename "$e")"; done
rm -f "$B/programs/cyrld.cyr"
printf 'fn main(): i64 { return (; }\n' > "$B/programs/cyrld.cyr"
cp "$CC" "$B/build/cycc"
drive "$B" "$D/a5" linker
[ "$DRC" != 0 ] || _fail "axis 5: a cyrld that does not compile left the linker run green (exit 0)"
grep -q '^  FAIL: the check driver builds cyrld from programs/cyrld.cyr$' "$D/a5" \
    || _fail "axis 5: no FAIL row naming cyrld: $(grep -E 'PASS|FAIL|SKIP' "$D/a5" | head -3)"

echo "axis 6: no row names one of the $NTOOLS as build/<tool>, and nothing builds a .cyrius/bin path"
NH=0
for t in $TOOLS; do
    h=$(grep -n "_root_path(\"build/$t\")" "$ROOT"/programs/checks/*.cyr || true)
    [ -z "$h" ] || { _fail "axis 6: a row resolves build/$t directly:"; echo "$h" | sed 's/^/      /'; NH=$((NH + 1)); }
done
# A string literal that IS a store path segment (the old `"/.cyrius/bin/"`), not prose that
# mentions one inside a row description.
h=$(grep -nE '"/?\.cyrius/bin/?"' "$ROOT"/programs/checks/*.cyr | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
[ -z "$h" ] || { _fail "axis 6: programs/checks names .cyrius/bin in code:"; echo "$h" | sed 's/^/      /'; }
NT=$(grep -hcE '_tool\("' "$ROOT"/programs/checks/*.cyr | awk '{s+=$1} END {print s+0}')
[ "$NT" -ge 20 ] || _fail "axis 6: only $NT _tool(\"…\") uses in programs/checks (floor 20) — the rows stopped asking the driver"

echo "axis 7: --tool-path <unknown> exits 1 and names the tool on stderr"
U=zz_no_such_tool
URC=0
( cd "$T" && HOME="$D/nohome" TMPDIR="$D/rt" timeout 120 "$D/drv" --tool-path "$U" ) \
    > "$D/a7.out" 2> "$D/a7.err" || URC=$?
[ "$URC" = 1 ] || _fail "axis 7: --tool-path $U exited $URC, expected 1"
grep -qF "error: --tool-path: no tool named '$U' (neither programs/$U.cyr nor build/$U exists)" "$D/a7.err" \
    || _fail "axis 7: stderr does not name '$U' and where it looked: '$(head -2 "$D/a7.err")'"
[ -s "$D/a7.out" ] && _fail "axis 7: stdout is not empty for an unknown tool: '$(head -2 "$D/a7.out")'"
[ -z "$(ls -A "$D/rt")" ] || _fail "axis 7: --tool-path $U left its run dir behind: $(ls "$D/rt")"
# Anti-vacuous: the message is for UNKNOWN names only — a known one in the same root answers 0
# with nothing on stderr.
KRC=0
( cd "$T" && HOME="$D/nohome" TMPDIR="$D/rt" timeout 300 "$D/drv" --tool-path cyrld ) \
    > "$D/a7k.out" 2> "$D/a7k.err" || KRC=$?
[ "$KRC" = 0 ] || _fail "axis 7: control --tool-path cyrld exited $KRC"
[ -s "$D/a7k.err" ] && _fail "axis 7: control --tool-path cyrld wrote stderr: '$(head -2 "$D/a7k.err")'"

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed"
    exit 1
fi
echo "PASS: $NAME ($NTOOLS tools built per run from the tree, stubs ignored, no ~/.cyrius/bin fallback, a broken tool is a named FAIL, an unknown one is named on stderr)"
