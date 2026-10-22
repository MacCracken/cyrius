#!/bin/sh
# tests/gates/toolchain/dev_helpers_match_golden.sh — 6.7.17
#
# THE DEVELOPER, FOLD AND RELEASE HELPERS ARE CYRIUS PROGRAMS, AND EACH ANSWERS WHAT THE SCRIPT IT
# REPLACED ANSWERED.
#
# WHY. scripts/dev, scripts/folds and scripts/release held Python and shell helpers (moved into
# the tree 2026-10-19); CLAUDE.md's sovereignty rule — no Python / bash / C as a shipped
# deliverable — read long term means the toolchain's own tooling is cyrius (the user: "scripts
# worth keeping will need to be converted at some point"). 6.7.17 converted them into
# programs/dev, programs/folds and programs/release
# (docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md). A conversion is
# only as good as its sameness: each golden under tests/fixtures/helpers/golden/ is the REPLACED
# script's own output on the fixture input, captured before the script was removed, and each axis
# runs the cyrius program on the same input and compares byte for byte.
#
# Hermetic: every external the helpers drive is a stand-in from tests/fixtures/helpers/stub/ (a
# compiler that writes shell scripts, qemu-aarch64, wine, cxvm, curl), the checkouts are scratch
# directories, and CYRIUS_SCRATCH / CYRIUS_REPO / HOME point into this gate's temp dir — no
# network, no sibling checkout, no live store.
#
# AXES (one per converted helper; a helper's axis passes when every case of it matches)
#   regen_issue_index  two issue sets (every group shape: hand labels kept at (0), an automatic
#                      label inserted in release order and one dropped empty, Unicode digits, a
#                      four-part release, CR LF, a README without group lines) and the missing-section
#                      error
#   keepboth           seven conflict files, each plain and --sep (rc, stdout, stderr, the file)
#   probe split        a `== name` file into probes (stale *.bin removed, other files kept)
#   probe run          the split probes run: default, OLD_CC before / after, a timeout, the errors
#   xb                 four programs on the four targets (stand-in compilers and runners)
#   envprobe           the line keys (the values are the machine's)
#   ab                 two refs of a scratch repository, times masked: a refusal (rc 4) and a
#                      signal death (rc -11, Python's spelling), and the usage errors
# FLOOR: the axis count is at least 7.
#
# MUTATION LEDGER (each measured RED, then restored):
#   regen_issue_index's automatic label inserted after the first LATER release   -> RED regen
#   keepboth's --sep fold dropped (the first side kept as it is)                   -> RED keepboth
#   probe run's error lines cut at 120 bytes, not 170                             -> RED probe run
#   xb's cx leg reporting its BUILD rc one high                                    -> RED xb
#   envprobe's ulimit line keyed `ulimit-n` (a key the script never printed)       -> RED envprobe
#   ab's "same input (<new> src)" row given the wrong pair                         -> RED ab
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: dev_helpers_match_golden: cannot cd to $ROOT"; exit 1; }
NAME=dev_helpers_match_golden
CC="$ROOT/build/cycc"
F="$ROOT/tests/fixtures/helpers"
G="$F/golden"
[ -x "$CC" ] || { echo "FAIL: $NAME: $CC missing"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
FAILS=0
AXES=0
AXIS_BAD=0
_fail() { echo "  FAIL: $NAME: $1"; FAILS=$((FAILS + 1)); AXIS_BAD=1; }

# ── the tools under test ─────────────────────────────────────────────────────────────────
BIN="$T/bin"
mkdir -p "$BIN"
# _build <name> <source>: the helper, compiled from the checkout root (its includes resolve there).
_build() {
    if "$CC" < "$2" > "$BIN/$1" 2> "$T/$1.build.err" && [ -s "$BIN/$1" ]; then
        chmod +x "$BIN/$1"
    else
        echo "FAIL: $NAME: $2 does not build:"; grep -v '^note' "$T/$1.build.err" | head -5
        exit 1
    fi
}
_build regen_issue_index programs/dev/regen_issue_index.cyr
_build keepboth programs/dev/keepboth.cyr
_build probe programs/dev/probe.cyr
_build xb programs/dev/xb.cyr
_build envprobe programs/dev/envprobe.cyr
_build ab programs/dev/ab.cyr

# _golden <golden path under $G> <actual file>: one case of the current axis.
_golden() {
    if [ ! -f "$G/$1" ]; then _fail "$1: no golden"; return; fi
    if ! cmp -s "$G/$1" "$2"; then
        _fail "$1 differs from the replaced script's output:"
        diff "$G/$1" "$2" | head -12 | sed 's/^/      /'
    fi
}
_axis_begin() { AXIS_BAD=0; }
_axis_end() { AXES=$((AXES + 1)); [ "$AXIS_BAD" = 0 ] && echo "  ok: $1"; }

# _rep <out> <rc> <stdout> <stderr> [<label> <file>]...: one report of a run, the scratch dir
# spelled @T@.
_rep() {
    o=$1; shift
    { echo "rc=$1"; echo "--- stdout"; cat "$2"; echo "--- stderr"; cat "$3"; } > "$o.raw"
    shift 3
    while [ $# -ge 2 ]; do
        { echo "--- $1"; cat "$2"; } >> "$o.raw"
        shift 2
    done
    sed "s|$T|@T@|g" "$o.raw" > "$o"
}

# stand-ins on PATH: qemu-aarch64 and wine run the stub's shell-script "binaries"; curl answers 200
FB="$T/fakebin"
mkdir -p "$FB"
cp "$F/stub/run_sh.sh" "$FB/qemu-aarch64"
cp "$F/stub/run_sh.sh" "$FB/wine"
cp "$F/stub/curl.sh" "$FB/curl"
chmod +x "$FB/qemu-aarch64" "$FB/wine" "$FB/curl"

# ── regen_issue_index ────────────────────────────────────────────────────────────────────
_axis_begin
for c in case1 case2; do
    R="$T/regen_$c"
    mkdir -p "$R/docs/development/issues"
    cp -a "$F/regen_issue_index/$c/." "$R/docs/development/issues/"
    "$BIN/regen_issue_index" --repo "$R" > "$T/o" 2> "$T/e"; rc=$?
    _rep "$T/rep" "$rc" "$T/o" "$T/e" README.md "$R/docs/development/issues/README.md"
    _golden "regen_issue_index/$c" "$T/rep"
done
R="$T/regen_err"
mkdir -p "$R/docs/development/issues"
printf '# Issues\n\n## Not the queue\n' > "$R/docs/development/issues/README.md"
"$BIN/regen_issue_index" "$R" > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "regen_issue_index/no_section" "$T/rep"
_axis_end "regen_issue_index: two issue sets and the missing-section error match the replaced script"

# ── keepboth ─────────────────────────────────────────────────────────────────────────────
_axis_begin
for c in c1 c2 c3 c4 c5 c6 c7; do
    for m in plain sep; do
        K="$T/kb_${c}_$m"
        mkdir -p "$K"
        cp "$F/keepboth/$c" "$K/f"
        if [ "$m" = sep ]; then (cd "$K" && "$BIN/keepboth" --sep f > "$T/o" 2> "$T/e"); rc=$?
        else (cd "$K" && "$BIN/keepboth" f > "$T/o" 2> "$T/e"); rc=$?; fi
        _rep "$T/rep" "$rc" "$T/o" "$T/e" file "$K/f"
        _golden "keepboth/$c.$m" "$T/rep"
    done
done
_axis_end "keepboth: seven conflict files, plain and --sep, match the replaced script"

# ── probe ────────────────────────────────────────────────────────────────────────────────
PR="$T/probe_repo"
mkdir -p "$PR/build" "$PR/src"
cp "$F/stub/cycc.sh" "$PR/build/cycc"
cp "$F/stub/cycc_old.sh" "$T/old_cc"
chmod +x "$PR/build/cycc" "$T/old_cc"
: > "$PR/src/main.cyr"
printf '[package]\n' > "$PR/cyrius.cyml"
_axis_begin
PD="$T/probes"
mkdir -p "$PD"
: > "$PD/stale.bin"; : > "$PD/stale.cyr"; : > "$PD/stale.err"; echo keep > "$PD/keep.txt"
"$BIN/probe" split "$PD" "$F/probe/probes.txt" > "$T/o" 2> "$T/e"; rc=$?
{ for p in $(ls "$PD" | LC_ALL=C sort); do echo "== $p"; cat "$PD/$p"; done; } > "$T/listing"
_rep "$T/rep" "$rc" "$T/o" "$T/e" files "$T/listing"
_golden "probe/split" "$T/rep"
_axis_end "probe split: a \`== name\` file splits into the probes the replaced script wrote"
_axis_begin
(cd "$PR" && CYRIUS_REPO="$PR" PROBE_TIMEOUT=1 "$BIN/probe" run "$PD" > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run" "$T/rep"
(cd "$PR" && CYRIUS_REPO="$PR" PROBE_TIMEOUT=1 OLD_CC="$T/old_cc" "$BIN/probe" run "$PD" > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_old_cc" "$T/rep"
mkdir -p "$T/noprobes"
(cd "$T" && CYRIUS_REPO="$PR" "$BIN/probe" run noprobes > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_none" "$T/rep"
(cd "$T" && CYRIUS_REPO="$PR" "$BIN/probe" run nosuchdir > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_nodir" "$T/rep"
(cd "$T" && CYRIUS_REPO="$PR" OLD_CC=no/such/cc "$BIN/probe" run "$PD" > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_bad_old_cc" "$T/rep"
_axis_end "probe run: the probes' lines (default, OLD_CC, a timeout) and the setup errors match the replaced script"

# ── xb ───────────────────────────────────────────────────────────────────────────────────
XR="$T/xb_repo"
mkdir -p "$XR/build" "$XR/src" "$XR/programs"
cp "$F/stub/cycc.sh" "$XR/build/cycc"
chmod +x "$XR/build/cycc"
cp "$F/stub/main_cx.sh" "$XR/src/main_cx.cyr"
cp "$F/stub/main_aarch64.sh" "$XR/src/main_aarch64.cyr"
cp "$F/stub/cxvm.sh" "$XR/programs/cxvm.cyr"
: > "$XR/src/main.cyr"
printf '[package]\n' > "$XR/cyrius.cyml"
_axis_begin
: > "$T/xb.out"
for p in p1.prog p2.prog p3.prog p4.prog; do
    (cd "$XR" && PATH="$FB:$PATH" CYRIUS_REPO="$XR" CYRIUS_SCRATCH="$T/xbs" "$BIN/xb" "$F/xb/$p" >> "$T/xb.out" 2> "$T/e"); echo "rc=$?" >> "$T/xb.out"
done
_golden "xb/four_programs" "$T/xb.out"
_axis_end "xb: four programs' four-target lines match the replaced script"

# ── envprobe ─────────────────────────────────────────────────────────────────────────────
_axis_begin
PATH="$FB:$PATH" "$BIN/envprobe" > "$T/o" 2> "$T/e"; rc=$?
{ echo "rc=$rc"; sed 's/[:=].*//' "$T/o"; } > "$T/keys"
_golden "envprobe/keys" "$T/keys"
_axis_end "envprobe: the inventory's lines are the replaced script's (keys; the values are the machine's)"

# ── ab ───────────────────────────────────────────────────────────────────────────────────
AR="$T/ab_repo"
mkdir -p "$AR"
_gitc() { git -C "$AR" -c user.email=gate@local -c user.name=gate -c commit.gpgsign=false "$@"; }
git init -q "$AR"
mkdir -p "$AR/build" "$AR/src" "$AR/lib"
# each ref's tree: its "compiler", src/main.cyr and a lib/ file (stored under other names, so no
# reader of tests/ takes them for cyrius sources); copied fresh, so git sees the new mtimes
for v in v1 v2; do
    cp "$F/ab/$v/cycc.sh" "$AR/build/cycc"
    cp "$F/ab/$v/main.txt" "$AR/src/main.cyr"
    cp "$F/ab/$v/lib.txt" "$AR/lib/x.cyr"
    chmod +x "$AR/build/cycc"
    _gitc add -A && _gitc commit -q -m "$v"
done
# the times masked: every number in a time, a delta or a run list, and the column padding
_abmask() { sed -e 's/[0-9][0-9]* ms/N ms/g' -e 's/delta [-+][0-9.]*%/delta D/' -e ':a' -e 's/\(: \[[N, ]*\)[0-9][0-9]*/\1N/' -e 'ta' "$1" | tr -s ' '; }
_axis_begin
CYRIUS_SCRATCH="$T/abs" "$BIN/ab" HEAD~1 HEAD --runs 2 --repo "$AR" > "$T/o" 2> "$T/e"; rc=$?
_abmask "$T/o" > "$T/om"
_rep "$T/rep" "$rc" "$T/om" "$T/e"
_golden "ab/two_refs" "$T/rep"
CYRIUS_SCRATCH="$T/abs" "$BIN/ab" nosuchref HEAD --repo "$AR" > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "ab/not_a_commit" "$T/rep"
CYRIUS_SCRATCH="$T/abs" "$BIN/ab" HEAD HEAD --runs 0 --repo "$AR" > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "ab/runs_zero" "$T/rep"
left=$(ls -A "$T/abs" 2>/dev/null | wc -l)
[ "$left" = 0 ] || _fail "ab left $left temp dir(s) in its scratch"
_axis_end "ab: the A/B table (times masked), a refusal, a signal death and the errors match the replaced script"

# ── verdict ──────────────────────────────────────────────────────────────────────────────
[ "$AXES" -ge 7 ] || _fail "only $AXES axes ran (floor 7)"
if [ "$FAILS" -ne 0 ]; then
    echo "FAIL: $NAME: $FAILS case(s) differ from the replaced scripts' output"
    exit 1
fi
echo "PASS $NAME: $AXES helpers, each byte-identical to the script it replaced on its fixture input"
