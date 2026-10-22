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
# It reaches its verdict under `sh` (check.sh) and under `bash -eo pipefail` (GitHub's run:
# shell), red rows included: a helper's expected non-zero exit is read as `… && rc=0 || rc=$?`,
# and a pipeline whose status means nothing (a diff tail, a grep that may match nothing) ends
# `|| true`.
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
#   envprobe           the line keys (the values are the machine's; a value's continuation line
#                      is not a key)
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
#   place              Placement / Decision lines, a special re-placement, --dry, the refusal; a
#                      missing input and a missing key end it with exit 1 (as place.py's exceptions)
#   briefs             every brief shape (notes, extra decisions, cross-lane, a group-less lane), --dry
#   archive            banners, titles, Status lines, git mv, every repointed link, --dry, a missing file
#   assemble           the CHANGELOG entry and the migration section, --dry, both refusals
#   roadmap_state      --derive, every template operation dry and real (a Python regex, a Python
#                      format string, difflib's diff), the refusals
#   no Python          `find scripts -name '*.py'` is empty, and no file under scripts/ has a
#                      python #! line (the issue's acceptance: scripts/ holds no Python); and no
#                      string in programs/{dev,folds,release} names a script they replaced (a
#                      message pointing at a file that is gone)
#   fixpoint           --fixpoint and --install (scripts/build-cycc-verify.sh's two modes until
#                      6.7.17) over stand-in compilers: a fixpoint, a divergence, a failure at each
#                      stage, an empty stage, an install that replaces and one that finds it equal
#   default checkout   with no CYRIUS_REPO / --repo: a project named someapp (src/main.cyr and a
#                      cyrius.cyml, as `cyrius init` makes) is never the cyrius checkout — the
#                      resolver walks past it, and regen_issue_index, ab, place, fixpoint, xb and
#                      probe refuse it and write nothing; one named cyrius is found from a subdir
#   stat fields        every stat buffer the helpers read goes through lib's STAT_* constants (the
#                      macOS layouts differ), never a numeric offset
# FLOOR: the axis count is at least 20.
#
# MUTATION LEDGER (each measured RED, then restored):
#   regen_issue_index's automatic label inserted after the first LATER release   -> RED regen
#   keepboth's --sep fold dropped (the first side kept as it is)                   -> RED keepboth
#   probe run's error lines cut at 120 bytes, not 170                             -> RED probe run
#   xb's cx leg reporting its BUILD rc one high                                    -> RED xb
#   envprobe's ulimit line keyed `ulimit-n` (a key the script never printed)       -> RED envprobe
#   envprobe's key filter dropped (every line head compared, as first committed)   -> RED envprobe
#   ab's "same input (<new> src)" row given the wrong pair                         -> RED ab
#   fixpoint's c2 == c3 compare made a byte count compare                          -> RED fixpoint
#   run_ci's step tail cut at 100 code points, not 110                             -> RED run_ci, sibci
#   run_ci's `- run: |-` header kept as the script's first line (run-ci.py's bug) -> RED run_ci (YAML)
#   run_ci's step env: not applied                                                 -> RED run_ci (YAML)
#   place's Decision lines put before the placement's continuation lines           -> RED place
#   briefs' cross-lane note taken from the lane itself, not the `from` lane        -> RED briefs
#   archive's bare-name rule applied in archived/ too                              -> RED archive
#   assemble's migration parts joined without the blank line                       -> RED assemble
#   pyre's lazy repeat made greedy                                                 -> RED roadmap_state
#   a scripts/x.py planted (and, apart, an extension-less #!/usr/bin/env python3)  -> RED no Python
#   roadmap_state's refusals back to "roadmap-state.py: …" (as first committed)    -> RED no Python
#   tomlcheck's "Unclosed array" raised one position early                         -> RED cymlcheck
#   tomlcheck's frame limit 1001, not 1000                                         -> RED cymlcheck
#   _hc_is_cyrius_checkout back to the filename probe (src/main.cyr + cyrius.cyml) -> RED default checkout
#   release/common.cyr's prefix back to `hc_ccat(RC_PROG, ": ")` (a C string as a Str) -> RED place
#   xb's mtime read back at `&st + 88` / `&st + 96`                                -> RED stat fields
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: dev_helpers_match_golden: cannot cd to $ROOT"; exit 1; }
NAME=dev_helpers_match_golden
CC=${CYCC:-"$ROOT/build/cycc"}
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
        echo "FAIL: $NAME: $2 does not build:"; grep -v '^note' "$T/$1.build.err" | head -5 || true
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
_build place programs/release/place.cyr
_build briefs programs/release/briefs.cyr
_build archive programs/release/archive.cyr
_build assemble programs/release/assemble.cyr
_build roadmap_state programs/release/roadmap_state.cyr

# _golden <golden path under $G> <actual file>: one case of the current axis.
_golden() {
    if [ ! -f "$G/$1" ]; then _fail "$1: no golden"; return; fi
    if ! cmp -s "$G/$1" "$2"; then
        _fail "$1 differs from the replaced script's output:"
        diff "$G/$1" "$2" | head -12 | sed 's/^/      /' || true
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
        diff "$T/golden_as" "$2" | head -12 | sed 's/^/      /' || true
    fi
}
_axis_begin() { AXIS_BAD=0; }
_axis_end() { AXES=$((AXES + 1)); if [ "$AXIS_BAD" = 0 ]; then echo "  ok: $1"; fi; }

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
    "$BIN/regen_issue_index" --repo "$R" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    _rep "$T/rep" "$rc" "$T/o" "$T/e" README.md "$R/docs/development/issues/README.md"
    _golden "regen_issue_index/$c" "$T/rep"
done
R="$T/regen_err"
mkdir -p "$R/docs/development/issues"
printf '# Issues\n\n## Not the queue\n' > "$R/docs/development/issues/README.md"
(cd "$T" && "$BIN/regen_issue_index" regen_err > "$T/o" 2> "$T/e") && rc=0 || rc=$?
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
        if [ "$m" = sep ]; then (cd "$K" && "$BIN/keepboth" --sep f > "$T/o" 2> "$T/e") && rc=0 || rc=$?
        else (cd "$K" && "$BIN/keepboth" f > "$T/o" 2> "$T/e") && rc=0 || rc=$?; fi
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
"$BIN/probe" split "$PD" "$F/probe/probes.txt" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
{ for p in $(ls "$PD" | LC_ALL=C sort); do echo "== $p"; cat "$PD/$p"; done; } > "$T/listing"
_rep "$T/rep" "$rc" "$T/o" "$T/e" files "$T/listing"
_golden "probe/split" "$T/rep"
_axis_end "probe split: a \`== name\` file splits into the probes the replaced script wrote"
_axis_begin
(cd "$PR" && CYRIUS_REPO="$PR" PROBE_TIMEOUT=1 "$BIN/probe" run "$PD" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run" "$T/rep"
(cd "$PR" && CYRIUS_REPO="$PR" PROBE_TIMEOUT=1 OLD_CC="$T/old_cc" "$BIN/probe" run "$PD" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_old_cc" "$T/rep"
mkdir -p "$T/noprobes"
(cd "$T" && CYRIUS_REPO="$PR" "$BIN/probe" run noprobes > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_none" "$T/rep"
(cd "$T" && CYRIUS_REPO="$PR" "$BIN/probe" run nosuchdir > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "probe/run_nodir" "$T/rep"
(cd "$T" && CYRIUS_REPO="$PR" OLD_CC=no/such/cc "$BIN/probe" run "$PD" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
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
    (cd "$XR" && PATH="$FB:$PATH" CYRIUS_REPO="$XR" CYRIUS_SCRATCH="$T/xbs" "$BIN/xb" "$F/xb/$p" >> "$T/xb.out" 2> "$T/e") && r=0 || r=$?; echo "rc=$r" >> "$T/xb.out"
done
_golden "xb/four_programs" "$T/xb.out"
_axis_end "xb: four programs' four-target lines match the replaced script"

# ── envprobe ─────────────────────────────────────────────────────────────────────────────
# The values are the machine's; the keys — the line heads the script printed, in its order — are
# compared. A value printed verbatim may run over lines (an /etc/locale.conf of two settings,
# findmnt naming two /tmp mounts), and a continuation line's head is no key: only heads that ARE
# the golden's keys are kept, so a missing, renamed or reordered key is RED on any box and a
# two-line value is not. The filter itself is checked on the output with such a line planted.
_axis_begin
PATH="$FB:$PATH" "$BIN/envprobe" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
sed '1d' "$G/envprobe/keys" > "$T/envkeys"
nk=$(wc -l < "$T/envkeys" | tr -d ' ')
[ "$nk" -ge 25 ] || _fail "envprobe's golden names $nk keys (floor 25)"
_envkeys() { { echo "rc=$rc"; sed 's/[:=].*//' "$1" | grep -xF -f "$T/envkeys" || true; } > "$2"; }
_envkeys "$T/o" "$T/keys"
_golden "envprobe/keys" "$T/keys"
sed '/^localectl-conf:/a\
LC_TIME=en_GB.UTF-8' "$T/o" > "$T/o2"
_envkeys "$T/o2" "$T/keys2"
cmp -s "$T/keys" "$T/keys2" || _fail "envprobe's key filter read a value's continuation line as a key"
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
CYRIUS_SCRATCH="$T/abs" "$BIN/ab" HEAD~1 HEAD --runs 2 --repo "$AR" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_abmask "$T/o" > "$T/om"
_rep "$T/rep" "$rc" "$T/om" "$T/e"
_golden "ab/two_refs" "$T/rep"
(cd "$T" && CYRIUS_SCRATCH="$T/abs" "$BIN/ab" nosuchref HEAD --repo ab_repo > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "ab/not_a_commit" "$T/rep"
CYRIUS_SCRATCH="$T/abs" "$BIN/ab" HEAD HEAD --runs 0 --repo "$AR" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "ab/runs_zero" "$T/rep"
left=$(ls -A "$T/abs" 2>/dev/null | wc -l)
[ "$left" = 0 ] || _fail "ab left $left temp dir(s) in its scratch"
_axis_end "ab: the A/B table (times masked), a refusal, a signal death and the errors match the replaced script"

# ── the release steps (scripts/release/*.py until 6.7.17) ───────────────────────────────────
RF="$F/release"
C6="$T/c6"
mkdir -p "$C6"
# _tree <dir>: every file under <dir> (no .git), sorted, each named then shown
_tree() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do echo "== $f"; cat "$f"; done); }

# place: the units' and the plan's Placement and Decision lines (a wrapped parenthetical, text after
# `never 7.x.`, decision_ids, a special re-placement after an earlier Decision line), --dry, and an
# issue with no Placement line for the release
_axis_begin
PL="$T/place_repo"
for m in dry run; do
    rm -rf "$PL"
    mkdir -p "$PL/docs/development/issues"
    cp "$RF/place/issues/"*.md "$PL/docs/development/issues/"
    d=""
    [ "$m" = dry ] && d=--dry
    "$BIN/place" --repo "$PL" --c6 "$C6" --ver 9.8.7 --date 2026-10-22 --units "$RF/place/units.json" \
        --decisions "$RF/place/decisions.json" --plan "$RF/place/place.json" $d > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    _tree "$PL" > "$T/tree"
    _rep "$T/rep" "$rc" "$T/o" "$T/e" tree "$T/tree"
    _golden "place/$m" "$T/rep"
done
"$BIN/place" --repo "$PL" --c6 "$C6" --ver 9.8.7 --date 2026-10-22 --units "$RF/place/units_bad.json" \
    --decisions "$RF/place/decisions.json" --plan "$RF/place/none.json" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "place/no_line" "$T/rep"
# A missing input and a decision with no "id": place.py's FileNotFoundError and KeyError ended it
# with exit 1; the step's own refusal does the same, in its words (no Python traceback to match).
# Until 6.7.17's review fix both were a SIGSEGV: release/common.cyr built the "place: " prefix by
# handing a C string to a Str slot.
printf '{}' > "$T/units_empty.json"
printf '[{"issue": "a.md"}]' > "$T/dec_noid.json"
"$BIN/place" --repo "$PL" --c6 "$C6" --ver 9.8.7 --date 2026-10-22 --units "$T/no_units.json" \
    --decisions "$RF/place/decisions.json" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
if [ "$rc" != 1 ] || [ "$(cat "$T/e")" != "place: $T/no_units.json: cannot read (no such file?)" ]; then
    _fail "place with a units file that does not exist: rc $rc (place.py: 1), stderr: $(head -2 "$T/e" | tr '\n' ' ')"
fi
"$BIN/place" --repo "$PL" --c6 "$C6" --ver 9.8.7 --date 2026-10-22 --units "$T/units_empty.json" \
    --decisions "$T/dec_noid.json" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
if [ "$rc" != 1 ] || [ "$(cat "$T/e")" != "place: KeyError: 'id'" ]; then
    _fail "place with a decision that has no id: rc $rc (place.py: 1), stderr: $(head -2 "$T/e" | tr '\n' ' ')"
fi
_axis_end "place: Placement and Decision lines, a special re-placement, --dry and the refusal match place.py"

# briefs: every brief shape (a preamble, unit notes, an extra decision, a cross-lane note, a lane
# with no triage group of its own, an issue triaged in another lane, list / str / null fields)
_axis_begin
for m in dry run; do
    BO="$T/briefs_$m"
    d=""
    [ "$m" = dry ] && d=--dry
    "$BIN/briefs" --repo "$T" --c6 "$C6" --ver 9.8.7 --date 2026-10-22 --units "$RF/briefs/units.json" \
        --triage "$RF/briefs/triage.json" --decisions "$RF/briefs/decisions.json" \
        --notes "$RF/briefs/brief_notes.json" --out "$BO" $d > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    : > "$T/tree"
    [ -d "$BO" ] && _tree "$BO" > "$T/tree"
    _rep "$T/rep" "$rc" "$T/o" "$T/e" briefs "$T/tree"
    _golden "briefs/$m" "$T/rep"
done
_axis_end "briefs: every brief shape, --dry included, matches briefs.py"

# archive: titles (OPEN, PARTIAL, none), banners (two lanes for one file, NOT A CYRIUS BUG), the
# Status line (none, two), and the repointing (bare names in the index, ../ in archived/, issues/
# paths elsewhere, build/ skipped, a non-UTF-8 file skipped, CR LF), --dry, and a banner naming a
# file that is not open
_axis_begin
for m in dry run; do
    AV="$T/archive_$m"
    mkdir -p "$AV"
    cp -R "$RF/archive/tree/." "$AV/"
    git init -q "$AV"
    git -C "$AV" -c user.email=gate@local -c user.name=gate add -A
    git -C "$AV" -c user.email=gate@local -c user.name=gate -c commit.gpgsign=false commit -q -m t
    d=""
    [ "$m" = dry ] && d=--dry
    "$BIN/archive" --repo "$AV" --c6 "$C6" --ver 9.8.7 --docs "$RF/archive/docs" $d > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    git -C "$AV" status --porcelain > "$T/st"
    _tree "$AV" > "$T/tree"
    _rep "$T/rep" "$rc" "$T/o" "$T/e" status "$T/st" tree "$T/tree"
    _golden "archive/$m" "$T/rep"
done
"$BIN/archive" --repo "$T/archive_dry" --c6 "$C6" --ver 9.8.7 --docs "$RF/archive/docs_missing" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "archive/missing" "$T/rep"
_axis_end "archive: the banners, titles, Status lines, the git mv and every repointed link match archive.py"

# assemble: the head's placeholders, the lane and extra parts, the migration intro and parts,
# --dry, the real run, a second run (refused), a head placeholder with no value
_axis_begin
AS="$T/assemble_repo"
mkdir -p "$AS"
cp -R "$RF/assemble/repo/." "$AS/"
for m in dry run again; do
    d=""
    [ "$m" = dry ] && d=--dry
    "$BIN/assemble" --repo "$AS" --c6 "$C6" --docs "$RF/assemble/docs" --ver 9.8.7 --prev 9.8.6 \
        --date 2026-10-22 --lanes l1,l2 --mig-extra extra --gatehead abc1234 --driver '1 / 1' \
        --shell '2 / 2' --bench 99 $d > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    _tree "$AS" > "$T/tree"
    _rep "$T/rep" "$rc" "$T/o" "$T/e" tree "$T/tree"
    _golden "assemble/$m" "$T/rep"
done
AS2="$T/assemble_repo2"
mkdir -p "$AS2"
cp -R "$RF/assemble/repo/." "$AS2/"
"$BIN/assemble" --repo "$AS2" --c6 "$C6" --docs "$RF/assemble/docs" --ver 9.8.7 --prev 9.8.6 \
    --date 2026-10-22 --lanes l1 --gatehead abc1234 --driver x --shell y > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "assemble/no_bench" "$T/rep"
_axis_end "assemble: the CHANGELOG entry and the migration section, --dry and both refusals match assemble.py"

# roadmap_state: --derive over a scratch tree (dirs named like files, hidden files, a section
# table from a stand-in ELF), the template's every operation (sub with flags and groups, replace,
# cut, row, row keep_from, insert_after_row; format specs, placed[...] and --set values) dry and
# real, a placeholder with no value, a missing row, an issue still placed in the release
_axis_begin
RS="$T/rs_repo"
mkdir -p "$RS/tests/tcyr/crossos" "$RS/tests/tcyr/sub" "$RS/tests/tcyr/dir.tcyr" "$RS/tests/gates/a" \
    "$RS/tests/gates/b" "$RS/lib/sub.cyr" "$RS/build" "$RS/docs/development"
: > "$RS/tests/tcyr/a.tcyr"; : > "$RS/tests/tcyr/b.tcyr"; : > "$RS/tests/tcyr/sub/c.tcyr"
: > "$RS/tests/tcyr/crossos/d.tcyr"; : > "$RS/tests/tcyr/.e.tcyr"; : > "$RS/tests/tcyr/f.txt"
: > "$RS/tests/gates/a/x.sh"; : > "$RS/tests/gates/b/y.sh"; : > "$RS/tests/gates/z.sh"
: > "$RS/lib/a.cyr"; : > "$RS/lib/b.cyr"; : > "$RS/lib/.hidden.cyr"
cp "$RF/roadmap_state/cycc.elf" "$RS/build/cycc"
cp "$RF/roadmap_state/arm.bin" "$RS/build/cycc-native-aarch64"
cp "$RF/roadmap_state/api-surface.snapshot" "$RS/docs/api-surface.snapshot"
cp -R "$RF/roadmap_state/docs/." "$RS/docs/development/"
cp -R "$RS/docs/development/." "$T/rs_docs_orig/" 2>/dev/null || { mkdir -p "$T/rs_docs_orig"; cp -R "$RS/docs/development/." "$T/rs_docs_orig/"; }
"$BIN/roadmap_state" --repo "$RS" --ver 9.8.7 --derive > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "roadmap_state/derive" "$T/rep"
for m in dry run; do
    d=""
    [ "$m" = dry ] && d=--dry
    "$BIN/roadmap_state" --repo "$RS" --c6 "$C6" --ver 9.8.7 --template "$RF/roadmap_state/template.json" \
        --date 2026-10-22 --set gatehead=abc1234 --set driver='1 / 1' --set bench=99 --set archived=3 $d \
        > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    _tree "$RS/docs/development" > "$T/tree"
    _rep "$T/rep" "$rc" "$T/o" "$T/e" docs "$T/tree"
    _golden "roadmap_state/$m" "$T/rep"
done
for c in missing norow; do
    "$BIN/roadmap_state" --repo "$RS" --c6 "$C6" --ver 9.8.7 --template "$RF/roadmap_state/template_$c.json" \
        > "$T/o" 2> "$T/e" && rc=0 || rc=$?
    _rep "$T/rep" "$rc" "$T/o" "$T/e"
    _golden "roadmap_state/$c" "$T/rep"
done
"$BIN/roadmap_state" --repo "$RS" --c6 "$C6" --ver 9.9.0 --template "$RF/roadmap_state/template.json" \
    > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "roadmap_state/still_placed" "$T/rep"
_axis_end "roadmap_state: --derive, a template of every operation dry and real, and the refusals match roadmap-state.py"

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
        (cd "$FR" && CYRIUS_REPO="$FR" "$BIN/fixpoint" --$m "../st_${c}_$m" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
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
"$BIN/run_ci" "$RC" --list > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/list" "$T/rep"
"$BIN/run_ci" "$RC" --list --include-release > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/list_release" "$T/rep"
(cd "$T" && PATH="$STORE/9.9.9/bin:$PATH" HOME="$T/fh" CYRIUS_HOME="$T/fakehome" CI_TIMEOUT=3 CI_VERBOSE=1 \
    REPO_NAME=foldx RUNNER_TEMP="$T/rc_rt" "$BIN/run_ci" "$RC" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/run" "$T/rep"
(cd "$T" && PATH="$STORE/9.9.9/bin:$PATH" HOME="$T/fh" CYRIUS_HOME="$T/fakehome" CI_JOB=other \
    RUNNER_TEMP="$T/rc_rt" "$BIN/run_ci" "$RC" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci/run_one_job" "$T/rep"
_axis_end "run_ci: the step list and a run of every step shape match run-ci.py"
_axis_begin
SW="$T/sibw"
(cd "$T" && PATH="$FB:$PATH" CYRIUS_FOLDS_ROOT="$FOLDS" CYRIUS_STORE="$STORE" CI_TIMEOUT=3 \
    "$BIN/sibci" foldx v1 "$SW" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
{ echo "home/bin -> $(readlink "$SW/foldx/home/bin")"; echo "home/lib -> $(readlink "$SW/foldx/home/lib")"
  echo "home/current: $(cat "$SW/foldx/home/current")"; echo "fh/.cyrius -> $(readlink "$SW/foldx/fh/.cyrius")"
  ls "$SW/foldx/home/versions"; ls "$SW/foldx/home/deps" | wc -l; } > "$T/layout"
_rep "$T/rep" "$rc" "$T/o" "$T/e" ci.log "$SW/foldx/ci.log" copy/cyrius.cyml "$SW/foldx/copy/cyrius.cyml" layout "$T/layout"
_golden "sibci/run" "$T/rep"
for bad in "a/b" nopin badpin; do
    (cd "$T" && CYRIUS_FOLDS_ROOT="$FOLDS" CYRIUS_STORE="$STORE" "$BIN/sibci" "$bad" v1 "$SW" > "$T/o" 2> /dev/null) && rc=0 || rc=$?
    : > "$T/e"   # stderr dropped: git's and tar's own complaints; the verdict is stdout and the status
    _rep "$T/rep" "$rc" "$T/o" "$T/e"
    _golden_as "sibci/bad_$(echo "$bad" | tr / _)" "$T/rep" "sibci.sh: " "sibci: "
done
(cd "$T" && "$BIN/sibci" onlyone > "$T/o" 2> /dev/null) && rc=0 || rc=$?
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
"$BIN/run_ci" "$YC" --list > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "run_ci_yaml/list" "$T/rep"
(cd "$T" && RUNNER_TEMP="$T/yc_rt" "$BIN/run_ci" "$YC" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
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
"$BIN/cymlcheck" "$CM" content/cases.cyml content/sub/deep.cyml content/crlf.cyml content/valid.cyml > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "cymlcheck/named" "$T/rep"
git init -q "$CM"
git -C "$CM" -c user.email=gate@local -c user.name=gate add -A
git -C "$CM" -c user.email=gate@local -c user.name=gate -c commit.gpgsign=false commit -q -m cases
"$BIN/cymlcheck" "$CM" > "$T/o" 2> "$T/e" && rc=0 || rc=$?
_rep "$T/rep" "$rc" "$T/o" "$T/e"
_golden "cymlcheck/tracked" "$T/rep"
_axis_end "cymlcheck: 116 TOML cases, the recursion limit, CR LF and the tracked-tree walk match cymlcheck.py (tomllib)"

# ── the default checkout (6.7.17's review) ───────────────────────────────────────────────
# With no CYRIUS_REPO / --repo a helper works on the cyrius checkout around the current
# directory: the nearest directory holding src/main.cyr whose manifest's `[package] name` is
# exactly "cyrius" — cbt's _dep_is_cyrius_source_repo rule, never a filename probe. src/main.cyr
# beside a cyrius.cyml is every `cyrius init` project, and the probe took one for the cyrius
# checkout: regen_issue_index rewrote its issue index, fixpoint asked for its build/cycc. A resolver
# probe over helper_common.cyr prints hc_repo_root's and hc_repo_root_sh's answers (the Python-
# and the shell-replacing helpers' defaults); then every helper that resolves a default checkout
# runs from a consumer project and must refuse it and write nothing. The paths are physical
# (pwd -P), so getcwd and $PWD spell them alike. No golden: the scripts used their own location,
# so there is no old output to match.
_axis_begin
cat > "$T/rootprobe.cyr" <<'EOF'
include "programs/dev/helper_common.cyr"
fn _say(r): i64 {
    if (r == 0) { hc_outc("NONE\n"); return 0; }
    hc_out(r);
    hc_outc("\n");
    return 0;
}
fn main(): i64 {
    args_init();
    _say(hc_repo_root(0));
    _say(hc_repo_root_sh());
    return 0;
}
EOF
_build rootprobe "$T/rootprobe.cyr"
TP=$(cd "$T" && pwd -P)
# _ckproj <dir> <package name>: a `cyrius init`-shaped project with an issue index to regenerate
_ckproj() {
    mkdir -p "$1/src" "$1/docs/development/issues"
    : > "$1/src/main.cyr"
    printf '[package]\nname = "%s"\nversion = "0.1.0"\n' "$2" > "$1/cyrius.cyml"
    printf '# Issues\n\n## Open queue\n\nstale\n\n## Proposals\n' > "$1/docs/development/issues/README.md"
    printf '# An issue\n\n**Placement:** 9.9.9 — a slot\n' > "$1/docs/development/issues/2026-01-01-a.md"
}
# _where <dir>: the probe's two answers from <dir>, on one line
_where() { (cd "$1" && env -u CYRIUS_REPO "$BIN/rootprobe" 2>&1) | tr '\n' ' ' || true; }
ENC=$(_where "$TP")
CA="$TP/ck_app"
CK="$TP/ck_cyrius"
_ckproj "$CA" someapp
_ckproj "$CK" cyrius
_ckproj "$CK/sub/app" someapp
got=$(_where "$CA/docs/development")
[ "$got" = "$ENC" ] || _fail "from a project named someapp the default checkout is '$got' (the walk must pass it: '$ENC')"
got=$(_where "$CK/docs")
[ "$got" = "$CK $CK " ] || _fail "from inside a project named cyrius the default checkout is '$got' (want '$CK' twice)"
got=$(_where "$CK/sub/app/src")
[ "$got" = "$CK $CK " ] || _fail "from a someapp project inside a cyrius checkout the default is '$got' (want the enclosing '$CK' twice)"
# the cyrius-named project is found end to end: regen_issue_index from its docs/ rewrites its index
cp "$CK/docs/development/issues/README.md" "$T/ck_readme"
(cd "$CK/docs" && env -u CYRIUS_REPO "$BIN/regen_issue_index" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
[ "$rc" = 0 ] || _fail "regen_issue_index in a project named cyrius exited $rc: $(head -2 "$T/e")"
if cmp -s "$T/ck_readme" "$CK/docs/development/issues/README.md"; then
    _fail "regen_issue_index in a project named cyrius left its issue index as it was"
fi
# every helper with a default checkout, from the someapp project: refused by name, nothing written
if [ "$ENC" = "NONE NONE " ]; then
    _tree "$CA" > "$T/ck_before"
    for h in "regen_issue_index" "ab HEAD HEAD" "place --ver 9.9.9 --date 2026-10-22 --dry" \
        "fixpoint --fixpoint st" "xb x.cyr" "probe run ."; do
        set -- $h
        b=$1
        shift
        (cd "$CA" && env -u CYRIUS_REPO CYRIUS_SCRATCH="$T/cks" "$BIN/$b" "$@" > "$T/o" 2> "$T/e") && rc=0 || rc=$?
        if [ "$rc" = 0 ] || ! grep -q "no cyrius checkout here" "$T/e"; then
            _fail "$b from a project named someapp: rc $rc, not the no-checkout refusal: $(head -2 "$T/e" | tr '\n' ' ')"
        fi
    done
    _tree "$CA" > "$T/ck_after"
    cmp -s "$T/ck_before" "$T/ck_after" || _fail "a helper run from a project named someapp wrote into it"
else
    echo "  note: $NAME: the helper runs from a someapp project are NOT RUN — this gate's temp dir is inside the cyrius checkout $ENC, which each of them would act on (set TMPDIR outside it); the resolver rows above ran"
fi
_axis_end "the default checkout: a project named someapp is never taken for the cyrius checkout (six helpers refuse it, nothing written); one named cyrius is found from a subdirectory"

# ── no Python under scripts/ ─────────────────────────────────────────────────────────────
# The conversion's acceptance (the issue): scripts/ holds no Python. Every file is looked at — by
# name (*.py) and by its #! line (a python interpreter) — so a renamed or extension-less Python
# helper is seen too. The anti-vacuous floor: the scan read at least the shell scripts it knows.
_axis_begin
PYF=$(find scripts -type f -name '*.py' | LC_ALL=C sort)
[ -z "$PYF" ] || _fail "scripts/ holds Python: $(echo "$PYF" | tr '\n' ' ')"
nscan=0
for f in $(find scripts -type f | LC_ALL=C sort); do
    nscan=$((nscan + 1))
    l1=$(head -1 "$f" 2>/dev/null || true)
    case $l1 in '#!'*python*) _fail "$f is a Python script (its #! line)" ;; esac
done
[ "$nscan" -ge 30 ] || _fail "the scripts/ scan read only $nscan files (floor 30)"
# A program's message naming the script it replaced points its reader at a file that is gone:
# no string on a code line (comments, which say what each one replaced, are skipped) names one.
GONE='regen-issue-index\.py|ab\.py|keepboth\.py|probe-split\.py|probe\.sh|xb\.sh|envprobe\.sh|sibci\.sh'
GONE="$GONE|run-ci\\.py|cymlcheck\\.py|place\\.py|briefs\\.py|archive\\.py|assemble\\.py|roadmap-state\\.py"
GONE="$GONE|release_common\\.py"
ncyr=0
for f in $(find programs/dev programs/folds programs/release -type f -name '*.cyr' | LC_ALL=C sort); do
    ncyr=$((ncyr + 1))
    hits=$(grep -nE "^[[:space:]]*[^#[:space:]].*\"[^\"]*($GONE)" "$f" | cut -d: -f1 | tr '\n' ' ' || true)
    [ -z "$hits" ] || _fail "$f names a replaced script in a string (line(s) $hits)"
done
[ "$ncyr" -ge 15 ] || _fail "the programs/ scan read only $ncyr .cyr files (floor 15)"
_axis_end "scripts/ holds no Python ($nscan files read: no *.py, no python #! line); no string in $ncyr helper sources names a replaced script"

# ── stat fields through lib's layout (6.7.17's review) ───────────────────────────────────
# A stat buffer's fields sit at other offsets on other targets (st_mtime: 88 on Linux x86_64 and
# aarch64, 40 on macOS x86_64, 48 on macOS arm64), and lib/syscalls_*.cyr names each one STAT_*.
# hc_mtime_ns and xb's freshness walk read st_mtime at 88 / 96 and roadmap_state st_size at 48 —
# right on Linux only, byte-identical once spelled STAT_*. Every buffer a helper hands to sys_stat /
# sys_lstat / sys_fstat is read through STAT_*, never at a number; the one exception is hc_pwd's
# "same directory?" compare, whole words at 0 and 8 (dev and inode on every layout).
_axis_begin
nst=0
for f in $(find programs/dev programs/folds programs/release -type f -name '*.cyr' | LC_ALL=C sort); do
    for b in $(grep -oE 'sys_[lf]?stat\([^;&]*&[A-Za-z_][A-Za-z0-9_]*' "$f" | sed 's/.*&//' | LC_ALL=C sort -u || true); do
        nst=$((nst + 1))
        hits=$(grep -nE "load(8|16|32|64)\(&$b \+ [0-9]" "$f" | grep -vF 'load64(&a + 8) == load64(&b + 8)' | cut -d: -f1 | tr '\n' ' ' || true)
        [ -z "$hits" ] || _fail "$f reads stat buffer $b at a numeric offset (line(s) $hits): lib's STAT_* names each field"
    done
done
[ "$nst" -ge 5 ] || _fail "the stat-buffer census found only $nst buffers (floor 5)"
_axis_end "stat fields: the $nst stat buffers in the helpers are read through lib's STAT_* layout, never at a number"

# ── verdict ──────────────────────────────────────────────────────────────────────────────
[ "$AXES" -ge 20 ] || _fail "only $AXES axes ran (floor 20)"
if [ "$FAILS" -ne 0 ]; then
    echo "FAIL: $NAME: $FAILS case(s) differ from the replaced scripts' output"
    exit 1
fi
echo "PASS $NAME: $AXES axes — each helper byte-identical to the script it replaced on its fixture input (run_ci's YAML repair: to its oracle; the default checkout: to cbt's cyrius-checkout rule)"
