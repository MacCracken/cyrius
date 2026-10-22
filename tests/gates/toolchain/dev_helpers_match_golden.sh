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
# runs the cyrius program on the same input and compares byte for byte. The one exception is named
# where it stands: run_ci's YAML axis checks a repair of the old runner against an oracle.
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
#   run_ci             the step list (with and without --include-release), a run of every step
#                      shape, and a run of one job (CI_JOB)
#   run_ci (YAML)      the YAML shapes run-ci.py misread — the 6.7.17 repair, whose goldens are a
#                      PyYAML oracle's output, not the old script's
#   sibci              an isolated run of a stand-in fold against a stand-in store slot (the summary,
#                      the step log, the path-commented manifest, the throwaway home's links) and the
#                      refusals (a path, no pin, a pin not in the store, a missing argument)
#   cymlcheck          116 TOML cases in [[entries]] blocks (every tomllib error class, mutated
#                      documents, nesting either side of Python's recursion limit), CR LF, the
#                      `---` terminator, and the git-tracked content/**.cyml walk
#   fixpoint           --fixpoint and --install (scripts/build-cycc-verify.sh's two modes until
#                      6.7.17) over stand-in compilers: a fixpoint, a divergence, a failure at each
#                      stage, an empty stage, an install that replaces and one that finds it equal
# FLOOR: the axis count is at least 12.
#
# MUTATION LEDGER (each measured RED, then restored):
#   regen_issue_index's automatic label inserted after the first LATER release   -> RED regen
#   keepboth's --sep fold dropped (the first side kept as it is)                   -> RED keepboth
#   probe run's error lines cut at 120 bytes, not 170                             -> RED probe run
#   xb's cx leg reporting its BUILD rc one high                                    -> RED xb
#   envprobe's ulimit line keyed `ulimit-n` (a key the script never printed)       -> RED envprobe
#   ab's "same input (<new> src)" row given the wrong pair                         -> RED ab
#   fixpoint's c2 == c3 compare made a byte count compare                          -> RED fixpoint
#   run_ci's step tail cut at 100 code points, not 110                             -> RED run_ci, sibci
#   run_ci's `- run: |-` header kept as the script's first line (run-ci.py's bug) -> RED run_ci (YAML)
#   run_ci's step env: not applied                                                 -> RED run_ci (YAML)
#   tomlcheck's "Unclosed array" raised one position early                         -> RED cymlcheck
#   tomlcheck's frame limit 1001, not 1000                                         -> RED cymlcheck
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
_build fixpoint programs/dev/fixpoint.cyr
_build run_ci programs/folds/run_ci.cyr
_build sibci programs/folds/sibci.cyr
_build cymlcheck programs/folds/cymlcheck.cyr

# _golden <golden path under $G> <actual file>: one case of the current axis.
_golden() {
    if [ ! -f "$G/$1" ]; then _fail "$1: no golden"; return; fi
    if ! cmp -s "$G/$1" "$2"; then
        _fail "$1 differs from the replaced script's output:"
        diff "$G/$1" "$2" | head -12 | sed 's/^/      /'
    fi
}
# _golden_as <golden path> <actual file> <old text> <new text>: as _golden, the golden read with
# <old text> spelled <new text> — the one deliberate difference, a replaced script's own file name
# in a message (sibci.sh: names no file once the script is gone).
_golden_as() {
    if [ ! -f "$G/$1" ]; then _fail "$1: no golden"; return; fi
    sed "s|$3|$4|g" "$G/$1" > "$T/golden_as"
    if ! cmp -s "$T/golden_as" "$2"; then
        _fail "$1 differs from the replaced script's output (with $3 read as $4):"
        diff "$T/golden_as" "$2" | head -12 | sed 's/^/      /'
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
(cd "$T" && "$BIN/regen_issue_index" regen_err > "$T/o" 2> "$T/e"); rc=$?
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
(cd "$T" && CYRIUS_SCRATCH="$T/abs" "$BIN/ab" nosuchref HEAD --repo ab_repo > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "ab/not_a_commit" "$T/rep"
CYRIUS_SCRATCH="$T/abs" "$BIN/ab" HEAD HEAD --runs 0 --repo "$AR" > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "ab/runs_zero" "$T/rep"
left=$(ls -A "$T/abs" 2>/dev/null | wc -l)
[ "$left" = 0 ] || _fail "ab left $left temp dir(s) in its scratch"
_axis_end "ab: the A/B table (times masked), a refusal, a signal death and the errors match the replaced script"

# ── fixpoint (build-cycc-verify.sh's --fixpoint / --install until 6.7.17) ──────────────────
# Each stand-in build/cycc is a shell "compiler" whose output is itself a compiler script: one that
# reproduces itself (a fixpoint at c1; installed: "already byte-identical"), one that grows each
# stage (c2 != c3), one that flips one byte each stage (c2 != c3 at the same size), one that fails
# at c1, one that writes nothing, one whose c1 fails at c2, and one whose c1 differs from build/cycc
# but is a fixpoint (installed: "replaced").
_axis_begin
for c in selfrep diverge flip fail1 empty1 fail2 lag; do
    for m in fixpoint install; do
        FR="$T/fp_${c}_$m"
        mkdir -p "$FR/build" "$FR/src"
        cp "$F/fixpoint/$c.sh" "$FR/build/cycc"
        chmod +x "$FR/build/cycc"
        printf 'var x = 1;\n' > "$FR/src/main.cyr"
        printf '[package]\n' > "$FR/cyrius.cyml"
        (cd "$FR" && CYRIUS_REPO="$FR" "$BIN/fixpoint" --$m "../st_${c}_$m" > "$T/o" 2> "$T/e"); rc=$?
        ls -A "$FR/build" > "$T/buildls"
        _rep "$T/rep" "$rc" "$T/o" "$T/e" build/ "$T/buildls" build/cycc "$FR/build/cycc"
        _golden "fixpoint/$c.$m" "$T/rep"
    done
done
_axis_end "fixpoint: --fixpoint and --install over seven stand-in compilers match build-cycc-verify.sh's modes"

# ── run_ci and sibci (scripts/folds' run-ci.py and sibci.sh until 6.7.17) ─────────────────
# A stand-in fold: every step shape the runner reads (a workflow default shell, a job default, a
# step's own, block and one-line runs, the dash form, a skipped name, a `uses:` with a run,
# continue-on-error, a sudo refusal, an empty failure, a timeout, CR LF output, a long Unicode
# name, ${{ }} expressions), a .yaml workflow, a release workflow and a hidden one; a store slot
# holding a stand-in `cyrius`.
FOLDS="$T/folds"
mkdir -p "$FOLDS"
_mkfold() {  # <name> <fixture dir>: a fold checkout, committed and tagged v1
    mkdir -p "$FOLDS/$1"
    cp -R "$2/." "$FOLDS/$1/"
    if [ -d "$FOLDS/$1/dot-github" ]; then mv "$FOLDS/$1/dot-github" "$FOLDS/$1/.github"; fi
    git init -q "$FOLDS/$1"
    git -C "$FOLDS/$1" -c user.email=gate@local -c user.name=gate add -A
    git -C "$FOLDS/$1" -c user.email=gate@local -c user.name=gate -c commit.gpgsign=false commit -q -m v1
    git -C "$FOLDS/$1" tag v1
}
_mkfold foldx "$F/sibci/fold"
_mkfold nopin "$F/sibci/nopin"
mkdir -p "$T/badpin_src"
printf '[package]\ncyrius = "0.0.1"\n' > "$T/badpin_src/cyrius.cyml"
_mkfold badpin "$T/badpin_src"
STORE="$T/store"
mkdir -p "$STORE"
cp -R "$F/sibci/store/." "$STORE/"
chmod +x "$STORE/9.9.9/bin/cyrius"
_axis_begin
RC="$T/rc_copy"
mkdir -p "$RC"
cp -R "$FOLDS/foldx/." "$RC/"
rm -rf "$RC/.git"
"$BIN/run_ci" "$RC" --list > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/list" "$T/rep"
"$BIN/run_ci" "$RC" --list --include-release > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/list_release" "$T/rep"
(cd "$T" && PATH="$STORE/9.9.9/bin:$PATH" HOME="$T/fh" CYRIUS_HOME="$T/fakehome" CI_TIMEOUT=3 CI_VERBOSE=1 \
    REPO_NAME=foldx RUNNER_TEMP="$T/rc_rt" "$BIN/run_ci" "$RC" > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/run" "$T/rep"
(cd "$T" && PATH="$STORE/9.9.9/bin:$PATH" HOME="$T/fh" CYRIUS_HOME="$T/fakehome" CI_JOB=other \
    RUNNER_TEMP="$T/rc_rt" "$BIN/run_ci" "$RC" > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/run_one_job" "$T/rep"
_axis_end "run_ci: the step list and a run of every step shape match run-ci.py"
_axis_begin
SW="$T/sibw"
(cd "$T" && PATH="$FB:$PATH" CYRIUS_FOLDS_ROOT="$FOLDS" CYRIUS_STORE="$STORE" CI_TIMEOUT=3 \
    "$BIN/sibci" foldx v1 "$SW" > "$T/o" 2> "$T/e"); rc=$?
{ echo "home/bin -> $(readlink "$SW/foldx/home/bin")"; echo "home/lib -> $(readlink "$SW/foldx/home/lib")"
  echo "home/current: $(cat "$SW/foldx/home/current")"; echo "fh/.cyrius -> $(readlink "$SW/foldx/fh/.cyrius")"
  ls "$SW/foldx/home/versions"; ls "$SW/foldx/home/deps" | wc -l; } > "$T/layout"
_rep "$T/rep" "$rc" "$T/o" "$T/e" ci.log "$SW/foldx/ci.log" copy/cyrius.cyml "$SW/foldx/copy/cyrius.cyml" layout "$T/layout"
_golden "sibci/run" "$T/rep"
for bad in "a/b" nopin badpin; do
    (cd "$T" && CYRIUS_FOLDS_ROOT="$FOLDS" CYRIUS_STORE="$STORE" "$BIN/sibci" "$bad" v1 "$SW" > "$T/o" 2> /dev/null); rc=$?
    : > "$T/e"   # stderr dropped: git's and tar's own complaints; the verdict is stdout and the status
    _rep "$T/rep" "$rc" "$T/o" "$T/e"
    _golden_as "sibci/bad_$(echo "$bad" | tr / _)" "$T/rep" "sibci.sh: " "sibci: "
done
(cd "$T" && "$BIN/sibci" onlyone > "$T/o" 2> /dev/null); rc=$?
[ "$rc" = 1 ] || _fail "sibci with a missing argument exited $rc (the script: 1)"
_axis_end "sibci: an isolated run (summary, step log, manifest, the throwaway home) and the refusals match sibci.sh"

# ── run_ci's YAML (6.7.17's repair of what run-ci.py misread) ─────────────────────────────
# Block scalar headers (`|-` / `|+` / `>` / `>-` / an indentation digit / a header comment) and
# folding, quoted and commented scalars, env: at the workflow, job and step (block and flow), the
# working-directory defaults and the step's, a nested mapping under a step. These goldens are NOT
# the old script's (it misread every one): they are PyYAML's reading of the same workflow run
# through run-ci.py's own loop and line format — an independent oracle, taken 2026-10-22.
_axis_begin
YC="$T/yc"
mkdir -p "$YC"
cp -R "$F/run_ci_yaml/." "$YC/"
mv "$YC/dot-github" "$YC/.github"
"$BIN/run_ci" "$YC" --list > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci_yaml/list" "$T/rep"
(cd "$T" && RUNNER_TEMP="$T/yc_rt" "$BIN/run_ci" "$YC" > "$T/o" 2> "$T/e"); rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci_yaml/run" "$T/rep"
_axis_end "run_ci: the YAML shapes run-ci.py misread now read as YAML reads them (a PyYAML oracle's output)"

# ── cymlcheck (scripts/folds/cymlcheck.py until 6.7.17) ────────────────────────────────────
# One hundred and sixteen TOML cases (tomllib's grammar and namespace rules, each error class and
# a run of mutated documents), one [[entries]] block each; nesting at Python's recursion limit
# either side; CR LF; `---` terminators with and without blanks; then the same tree tracked in git
# (no <file> arguments: content/**.cyml).
_axis_begin
CM="$T/cyml"
mkdir -p "$CM"
cp -R "$F/cymlcheck/." "$CM/"
"$BIN/cymlcheck" "$CM" content/cases.cyml content/sub/deep.cyml content/crlf.cyml content/valid.cyml > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "cymlcheck/named" "$T/rep"
git init -q "$CM"
git -C "$CM" -c user.email=gate@local -c user.name=gate add -A
git -C "$CM" -c user.email=gate@local -c user.name=gate -c commit.gpgsign=false commit -q -m cases
"$BIN/cymlcheck" "$CM" > "$T/o" 2> "$T/e"; rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "cymlcheck/tracked" "$T/rep"
_axis_end "cymlcheck: 116 TOML cases, the recursion limit, CR LF and the tracked-tree walk match cymlcheck.py (tomllib)"

# ── verdict ──────────────────────────────────────────────────────────────────────────────
[ "$AXES" -ge 12 ] || _fail "only $AXES axes ran (floor 12)"
if [ "$FAILS" -ne 0 ]; then
    echo "FAIL: $NAME: $FAILS case(s) differ from the replaced scripts' output"
    exit 1
fi
echo "PASS $NAME: $AXES axes — each helper byte-identical to the script it replaced on its fixture input (run_ci's YAML repair: to its oracle)"
