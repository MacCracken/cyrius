#!/bin/sh
# build_output_confined.sh — 6.6.20 (SEC-02, the build-output quoting bug). A manifest's `[build] output` is the 0755
# binary `cyrius build` writes; on macOS it was handed UNQUOTED to `/bin/sh -c "codesign -s - -f
# <output>"` and on Windows it is cmd.exe's quoted redirect target, where a `"` ends the operand
# and the rest of the line runs (`out.exe" & echo X> pwned.txt & "y` ran under wine). On Linux the
# same value wrote the binary anywhere: `../escaped_out bin;touch PWNED`, an absolute path, and a
# path through a committed directory link each landed OUTSIDE the checkout.
# Now `_cfg_output_refused` confines a manifest output to the project (`_proj_path_bad`, the
# [embed] rules: no absolute path, `..`, `\`, `:`, `.git`, link on the path, control byte, `"`,
# `%`, `!`), codesign runs by argv with no shell, and every cmd.exe operand is checked
# (`_w_cmd_operand_ok`). An output given as an ARGUMENT is the operator's and is not confined.
# AXES: 1 each refused manifest output -> rc 1, the value named, nothing written outside;
#       2 a plain `build/main` still builds and runs; 3 an argument output outside the tree builds.
# Mutation: `_cfg_output_refused` returning 0 -> axis 1 red (measured at integration).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=build_output_confined
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
if [ -n "${CYRIUS_GATE_CLI:-}" ]; then cp "$CYRIUS_GATE_CLI" "$W/cyrius"; else
    "$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: $NAME: cbt/cyrius.cyr does not build"; exit 1; }
fi
chmod +x "$W/cyrius"
mkdir -p "$W/home/bin"; cp "$CC" "$W/home/bin/cycc"
P="$W/p"; mkdir -p "$P/src" "$P/real" "$W/out"
ln -s real "$P/lnk"
printf 'syscall(60, 7);\n' > "$P/src/main.cyr"
cli() { ( cd "$P" && env -u CYRIUS_DCE HOME="$W" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ); }
mf() { printf '[package]\nname = "p"\nversion = "0.1.0"\n[build]\nentry = "src/main.cyr"\noutput = "%s"\n' "$1" > "$P/cyrius.cyml"; }

# axis 1 — refused manifest outputs
for v in '../escaped_out bin;touch PWNED' "$W/out/abs" 'lnk/x' '.git/hooks/x' 'a\\b' 'out%PATH%' 'x!y' 'q\"r'; do
    mf "$v"
    rc=0; cli build > "$W/o" 2> "$W/e" || rc=$?
    [ "$rc" = 1 ] || fail "axis 1 [$v]: rc $rc, want 1"
    grep -q 'cyrius.cyml \[build\] output' "$W/e" || fail "axis 1 [$v]: refusal does not name [build] output: $(head -2 "$W/e")"
done
[ -e "$W/escaped_out bin;touch PWNED" ] && fail "axis 1: the ../ output was written outside the project"
[ -e "$W/out/abs" ] && fail "axis 1: the absolute output was written"
[ -e "$P/real/x" ] && fail "axis 1: the output was written through the directory link"
[ -e "$P/PWNED" ] || [ -e "$W/PWNED" ] && fail "axis 1: a shell ran the output"

# axis 2 — a plain project output still builds and runs
mf 'build/main'
rc=0; cli build > "$W/o" 2> "$W/e" || rc=$?
[ "$rc" = 0 ] || fail "axis 2: build/main: rc $rc: $(head -3 "$W/e")"
rr=0; "$P/build/main" || rr=$?
[ "$rr" = 7 ] || fail "axis 2: build/main ran rc $rr, want 7"

# axis 3 — an ARGUMENT output is the operator's: outside the tree is allowed
rc=0; cli build src/main.cyr "$W/out/argout" > "$W/o" 2> "$W/e" || rc=$?
[ "$rc" = 0 ] && [ -x "$W/out/argout" ] || fail "axis 3: argument output outside the tree: rc $rc: $(head -2 "$W/e")"

[ "$FAIL" = 0 ] || { echo "FAIL: $NAME: $FAIL failure(s)"; exit 1; }
echo "PASS: $NAME (a manifest [build] output is confined to the project: ../, absolute, a link, .git, \\\\, %, !, \" refused by name; a plain output builds; an argument output is the operator's)"
