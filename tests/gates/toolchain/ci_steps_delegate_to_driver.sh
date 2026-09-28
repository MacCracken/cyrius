#!/bin/sh
# tests/gates/toolchain/ci_steps_delegate_to_driver.sh — 6.6.9 (bite 11)
#
# CI RUNS THE CHECK DRIVER'S GATES; IT DOES NOT CARRY ITS OWN COPIES OF THEM.
#
# THE DEFECT. v5.9.3, v5.9.17 and v5.9.22 moved the object-init, linker, shared-object and
# capacity shell regressions into the cyrius check driver (programs/checks/), and ci.yml kept a
# second, hand-written shell copy of each "so this job stays granular" — plus inline copies of
# the fmt walk and (until 6.6.7) the lint walk. CI never ran the driver at all. Nothing tied a
# copy to its source, so a change to a fixture's path, cwd, marker or count rule landed in ONE
# implementation: when 6.6.6 moved the dlopen fixture's working directory, the driver moved
# and ci.yml did not, and CI exited 11 while check.sh was green; CI's flat `for f in lib/*.cyr`
# fmt loop had meanwhile fallen behind the driver's recursive walker (it never saw lib/unicode/).
#
# THE FIX. The steps run the driver's rows by name (`CYRIUS_CHECK_NO_SKIP=1 ./build/cyrius_check
# <row>`): fmt and lint, and the four rows made selectable for exactly this (object-init,
# linker, shared-dlopen, capacity — `--list-selectable-only`). CYRIUS_CHECK_NO_SKIP=1 because a
# driver row whose tool is missing reports SKIP (6.6.9, check_driver_skip_is_not_pass.sh), and
# the inline copies FAILED on a missing tool — delegation without it would be a silent pass.
# The .tcyr loop stays a DELIBERATELY INDEPENDENT implementation (CO-02 was caught because the
# two differed) and shares only the corpus floor, which it reads from the driver.
#
# AXES
#   1  RATCHET 0: no workflow `run:` line (comments excluded) references tests/fixtures/
#   2  RATCHET 0: no workflow `run:` line invokes a delegated row's tool outside the driver —
#      every delegated row has a signature here (cyrfmt, cyrlint, cyrld, capacity, dlopen,
#      _cyrius_init/readelf), and a delegated row WITHOUT one fails the gate, so a new
#      selectable row cannot slip past this axis
#   3  the delegated set is exactly {fmt, lint} + the driver's selectable-only rows; each is run
#      by some CI step as `CYRIUS_CHECK_NO_SKIP=1 ./build/cyrius_check <row>`; every
#      `cyrius_check <row>` in ci.yml names a real suite, carries the no-skip mode, and follows
#      a build of build/cyrius_check IN THE SAME JOB
#   4  the .tcyr corpus floor is written down ONCE (tests/tcyr/CORPUS_FLOOR): every CI step
#      that walks the whole corpus reads it and compares against no literal count, and the
#      driver reads the same file (`--tcyr-floor` agrees with it)
#   5  every CI SELF-HOST step self-hosts the SAME per-target source fork that
#      scripts/cross-os-selfhost.sh self-hosts for that host (runner -> host below)
#
# MUTATIONS (each RED; measured when this gate was written):
#   N1 the old inline dlopen step restored (fixture + runner)           -> axes 1, 2, 3
#   N2 `CYRIUS_CHECK_NO_SKIP=1` dropped from the linker step            -> axis 3
#   N3 the cyrius_check build removed from the test job's Setup         -> axis 3
#   N4 a .tcyr loop's floor back to a literal `-ge 250`                 -> axis 4
#   N5 the capacity step deleted (a selectable row no CI step runs)     -> axis 3
#   N6 the Intel-mac SELF-HOST step self-hosts src/main.cyr (both gens) -> axis 5
#      (and the same fork swapped on the scripts/cross-os-selfhost.sh side -> axis 5)
#   N7 a step runs `cyrius_check nosuchrow`                             -> axis 3
#   N8 the driver's floor hard-coded to 250 while the file says 251     -> axis 4
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=ci_steps_delegate_to_driver
CIY="$ROOT/.github/workflows/ci.yml"
XOS="$ROOT/scripts/cross-os-selfhost.sh"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

[ -f "$CIY" ] || { echo "FAIL: $NAME — $CIY missing"; exit 1; }
[ -x "$CC" ] || { echo "FAIL: $NAME — no compiler at $CC"; exit 1; }
( cd "$ROOT" && cat programs/checks/main.cyr | "$CC" > "$D/drv" 2>"$D/drv.err" ) \
    || { cat "$D/drv.err"; echo "FAIL: $NAME — the check driver does not compile"; exit 1; }
chmod +x "$D/drv"

# ── the workflow, one record per CODE line of a `run:` block ─────────────────────────────
# job <TAB> runs-on <TAB> step name <TAB> line. Comment lines (`#`, cmd's `REM`) are dropped:
# a comment that DESCRIBES the old copy is history, not a copy.
wf_lines() {
    awk '
    function emit(l,  t) {
        t = l; sub(/^[ \t]+/, "", t)
        if (t == "" || t ~ /^#/ || t ~ /^(REM|rem)([ \t]|$)/) return
        printf "%s\t%s\t%s\t%s\n", job, ro[job], step, t
    }
    {
        if (inrun) {
            if ($0 ~ /^[ \t]*$/) next
            match($0, /^ */)
            if (RLENGTH > 8) { emit($0); next }
            inrun = 0
        }
    }
    /^  [A-Za-z0-9_-]+:[ \t]*$/ { job = $1; sub(/:$/, "", job); step = ""; next }
    /^    runs-on:/ { r = $0; sub(/^    runs-on:[ \t]*/, "", r); ro[job] = r; next }
    /^      - / {
        step = ""
        if ($0 ~ /^      - name:/) { step = $0; sub(/^      - name:[ \t]*/, "", step) }
        if ($0 ~ /^      - run:/) { l = $0; sub(/^      - run:[ \t]*/, "", l); if (l ~ /^[|>]/) inrun = 1; else emit(l) }
        next
    }
    /^        name:/ { step = $0; sub(/^        name:[ \t]*/, "", step); next }
    /^        run:/ {
        l = $0; sub(/^        run:[ \t]*/, "", l)
        if (l ~ /^[|>]/) inrun = 1; else emit(l)
        next
    }' "$1"
}
wf_lines "$CIY" > "$D/ci.tsv"
for w in "$ROOT"/.github/workflows/*.yml; do wf_lines "$w" | sed "s|^|$(basename "$w")\t|"; done > "$D/all.tsv"
NL=$(grep -c . "$D/ci.tsv" || true)
[ "$NL" -ge 300 ] || _fail "the workflow reader found $NL run: code line(s) in ci.yml (floor 300) — it read nothing"
NJ=$(cut -f1 "$D/ci.tsv" | sort -u | grep -c . || true)
[ "$NJ" -ge 10 ] || _fail "the workflow reader found $NJ job(s) with run: blocks (floor 10)"

# The delegated rows. fmt and lint are FULL-RUN suites CI also runs on their own; every other
# delegated row is one the driver marks selectable-only (it exists for CI). Each row has a
# SIGNATURE: what an inline re-implementation of it would have to invoke.
FULL_RUN_DELEGATED="fmt lint"
sig_of() {
    case "$1" in
        fmt)           echo 'build/cyrfmt' ;;
        lint)          echo 'build/cyrlint' ;;
        linker)        echo 'build/cyrld' ;;
        capacity)      echo '(^|[^A-Za-z0-9_-])capacity([^A-Za-z0-9_-]|$)' ;;
        shared-dlopen) echo 'dlopen' ;;
        object-init)   echo '_cyrius_init|readelf' ;;
        *)             echo '' ;;
    esac
}
"$D/drv" --list-suites > "$D/suites" 2>&1 || _fail "cyrius_check --list-suites exited non-zero"
"$D/drv" --list-selectable-only > "$D/selonly" 2>&1 || _fail "cyrius_check --list-selectable-only exited non-zero"
NSO=$(grep -c . "$D/selonly" || true)
[ "$NSO" -ge 4 ] || _fail "the driver lists $NSO selectable-only row(s); expected >= 4 (object-init, linker, shared-dlopen, capacity)"
DELEGATED="$FULL_RUN_DELEGATED $(tr '\n' ' ' < "$D/selonly")"

# A code line with the build of a tool, a chmod of it, redirections, a source path and the
# driver's own invocation removed — what is left is what the line RUNS.
normalise() {
    sed -E 's/CYRIUS_CHECK_NO_SKIP=1 \.\/build\/cyrius_check [A-Za-z0-9_-]+//g;
            s/chmod \+x [^ ;&|]+//g; s/[0-9]?> *[^ ;&|]+//g; s/programs\/[A-Za-z0-9_\/.-]+\.cyr//g'
}

echo "axis 1: no workflow run: line references tests/fixtures/ (ratchet 0)"
grep -F 'tests/fixtures/' "$D/all.tsv" > "$D/a1" || true
N1=$(grep -c . "$D/a1" || true)
[ "$N1" = 0 ] || { _fail "axis 1: $N1 run: line(s) reference tests/fixtures/ — a driver gate's fixture used outside the driver:"; cut -f1,5 "$D/a1" | sed 's/^/      /' | head -8; }

echo "axis 2: no run: line re-implements a delegated driver row (ratchet 0)"
for row in $DELEGATED; do
    sig=$(sig_of "$row")
    if [ -z "$sig" ]; then
        _fail "axis 2: delegated row '$row' has no re-implementation signature in this gate — add one to sig_of"
        continue
    fi
    cut -f5 "$D/all.tsv" | normalise | grep -nE "$sig" > "$D/a2.$row" || true
    n=$(grep -c . "$D/a2.$row" || true)
    [ "$n" = 0 ] || { _fail "axis 2: $n run: line(s) do what the driver's '$row' row does, outside the driver:"; sed 's/^/      /' "$D/a2.$row" | head -5; }
done

echo "axis 3: CI runs exactly the delegated rows, through the driver, in no-skip mode"
for row in $FULL_RUN_DELEGATED; do
    grep -qx -- "$row" "$D/suites" || _fail "axis 3: '$row' is not a driver suite"
    grep -qx -- "$row" "$D/selonly" && _fail "axis 3: '$row' is expected to be a FULL-RUN suite, but the driver marks it selectable-only"
done
cut -f4 "$D/ci.tsv" > "$D/ci.code"
for row in $DELEGATED; do
    grep -qE "(^|[;&|] *)CYRIUS_CHECK_NO_SKIP=1 \./build/cyrius_check $row( |;|&|\$)" "$D/ci.code" \
        || _fail "axis 3: no CI step runs the driver row '$row' as 'CYRIUS_CHECK_NO_SKIP=1 ./build/cyrius_check $row'"
done
# Every driver invocation in ci.yml: a real row (or a read-only flag), the no-skip mode, and a
# build of the binary earlier IN THE SAME JOB (jobs do not share a workspace).
awk -F'\t' '$4 ~ /cyrius_check/ { print NR "\t" $1 "\t" $4 }' "$D/ci.tsv" > "$D/inv"
NINV=$(grep -c . "$D/inv" || true)
[ "$NINV" -ge 6 ] || _fail "axis 3: found $NINV line(s) naming cyrius_check in ci.yml (floor 6: the two builds + >= 4 rows) — the scan read nothing"
while IFS="$(printf '\t')" read -r nr job line; do
    case "$line" in
        *'programs/checks/main.cyr'*'> ./build/cyrius_check'*) continue ;;
        'chmod +x ./build/cyrius_check') continue ;;
    esac
    sel=$(printf '%s\n' "$line" | sed -nE 's/.*cyrius_check ([A-Za-z0-9_-]+).*/\1/p')
    flag=$(printf '%s\n' "$line" | sed -nE 's/.*cyrius_check (--[A-Za-z0-9-]+).*/\1/p')
    if [ -n "$flag" ]; then
        case "$flag" in --tcyr-floor|--list-suites|--list-selectable-only) ;; *) _fail "axis 3: job '$job' runs cyrius_check with an unknown flag '$flag'" ;; esac
    elif [ -z "$sel" ]; then
        _fail "axis 3: job '$job' runs cyrius_check with NO row — that is the whole ~15-minute suite: $line"
    else
        grep -qx -- "$sel" "$D/suites" || _fail "axis 3: job '$job' runs cyrius_check '$sel', which is not a driver suite"
        printf '%s\n' "$line" | grep -qE "CYRIUS_CHECK_NO_SKIP=1 \./build/cyrius_check $sel" \
            || _fail "axis 3: job '$job' runs the driver row '$sel' without CYRIUS_CHECK_NO_SKIP=1 (a missing tool would SKIP and pass)"
    fi
    awk -F'\t' -v n="$nr" -v j="$job" 'NR < n && $1 == j && $4 ~ /programs\/checks\/main\.cyr.*> \.\/build\/cyrius_check/ { f = 1 } END { exit f ? 0 : 1 }' "$D/ci.tsv" \
        || _fail "axis 3: job '$job' runs ./build/cyrius_check before building it in that job"
done < "$D/inv"
# The other direction: every CI-delegated row outside the full-run pair is selectable-only.
sed -nE 's/.*CYRIUS_CHECK_NO_SKIP=1 \.\/build\/cyrius_check ([A-Za-z0-9_-]+).*/\1/p' "$D/ci.code" | sort -u > "$D/ran"
for row in $(cat "$D/ran"); do
    case " $FULL_RUN_DELEGATED " in *" $row "*) continue ;; esac
    grep -qx -- "$row" "$D/suites" || continue   # not a suite at all: reported above
    grep -qx -- "$row" "$D/selonly" || _fail "axis 3: CI runs the row '$row' on its own, but the driver's full run ALSO runs it — make it selectable-only or add it to FULL_RUN_DELEGATED"
done

echo "axis 4: the .tcyr corpus floor has one definition"
FLF="$ROOT/tests/tcyr/CORPUS_FLOOR"
FL=$(sed -n 1p "$FLF" 2>/dev/null || true)
case "$FL" in ''|*[!0-9]*) _fail "axis 4: tests/tcyr/CORPUS_FLOOR line 1 is '$FL', not a number" ;; *) [ "$FL" -gt 0 ] || _fail "axis 4: the corpus floor is $FL" ;; esac
DFL=$("$D/drv" --tcyr-floor 2>/dev/null || true)
[ "$DFL" = "$FL" ] || _fail "axis 4: the driver reads the corpus floor as '$DFL', the file says '$FL'"
mkdir -p "$D/nofloor"
( cd "$D/nofloor" && "$D/drv" --tcyr-floor ) > "$D/nofloor.out" 2>/dev/null \
    && _fail "axis 4: with no tests/tcyr/CORPUS_FLOOR, cyrius_check --tcyr-floor exited 0 (printed '$(cat "$D/nofloor.out")') — a missing floor must not read as a number"
grep -qE 'var floor = _tcyr_corpus_floor\(\);' "$ROOT/programs/checks/selfhost.cyr" \
    || _fail "axis 4: the driver's tcyr gate no longer takes its floor from _tcyr_corpus_floor()"
# Every step (any job) that walks the WHOLE corpus: reads the file, compares against no literal.
awk -F'\t' '$4 ~ /find tests\/tcyr / { print $1 "\t" $3 }' "$D/ci.tsv" | sort -u > "$D/tcyr_steps"
NTS=$(grep -c . "$D/tcyr_steps" || true)
[ "$NTS" -ge 3 ] || _fail "axis 4: found $NTS ci.yml step(s) walking tests/tcyr (floor 3: ubuntu, AGNOS, native arm64) — the reader is blind"
while IFS="$(printf '\t')" read -r job st; do
    awk -F'\t' -v j="$job" -v s="$st" '$1 == j && $3 == s { print $4 }' "$D/ci.tsv" > "$D/tstep"
    grep -qF 'tests/tcyr/CORPUS_FLOOR' "$D/tstep" || _fail "axis 4: job '$job' step '$st' walks the corpus without reading tests/tcyr/CORPUS_FLOOR"
    grep -nE -- '-(ge|gt|lt|le) [0-9]{2,}' "$D/tstep" > "$D/tlit" || true
    [ ! -s "$D/tlit" ] || { _fail "axis 4: job '$job' step '$st' compares against a LITERAL count:"; sed 's/^/      /' "$D/tlit"; }
done < "$D/tcyr_steps"

echo "axis 5: each CI SELF-HOST step self-hosts the fork cross-os-selfhost.sh uses for its host"
# The runner each self-hosting CI job uses, mapped to the verification host that runs the same
# platform (CLAUDE.md: ecb macOS-arm64, ach Intel-Mac, cass Windows, pi aarch64).
host_of() {
    case "$1" in
        macos-14|macos-15|macos-latest) echo ecb ;;
        *self-hosted*macOS*X64*)        echo ach ;;
        windows-*)                      echo cass ;;
        ubuntu-*-arm)                   echo pi ;;
        *)                              echo '' ;;
    esac
}
awk -F'\t' '$3 ~ /^SELF-HOST/ { print $1 "\t" $2 }' "$D/ci.tsv" | sort -u > "$D/sh_jobs"
NSH=$(grep -c . "$D/sh_jobs" || true)
[ "$NSH" -ge 4 ] || _fail "axis 5: found $NSH CI SELF-HOST job(s) (floor 4: ecb, ach, cass, pi)"
while IFS="$(printf '\t')" read -r job ro; do
    h=$(host_of "$ro")
    [ -n "$h" ] || { _fail "axis 5: job '$job' self-hosts on runner '$ro', which maps to no verification host — extend host_of"; continue; }
    forks=$(awk -F'\t' -v j="$job" '$1 == j && $3 ~ /^SELF-HOST/ { print $4 }' "$D/ci.tsv" \
        | grep -oE 'src[/\\]main[A-Za-z0-9_]*\.cyr' | tr '\\' '/' | sort -u)
    nf=$(printf '%s\n' "$forks" | grep -c . || true)
    [ "$nf" = 1 ] || { _fail "axis 5: job '$job' SELF-HOST step names $nf fork(s) ($forks) — expected exactly one"; continue; }
    # The host's arm of the per-host `case "$HOST" in` (2-space indented), self-host lines only
    # (the ones that produce the second generation: r2, n2, c3.exe).
    xforks=$(awk -v h="$h" '
        $0 ~ "^  " h "\\)[ \t]*$" { on = 1; next }
        on && /^  [a-z|-]+\)[ \t]*$/ { on = 0 }
        on && /^esac/ { on = 0 }
        on' "$XOS" | grep -E '> *(r2|n2)|c3\.exe' | grep -oE 'src[/\\]main[A-Za-z0-9_]*\.cyr' | tr '\\' '/' | sort -u)
    [ -n "$xforks" ] || { _fail "axis 5: scripts/cross-os-selfhost.sh has no self-host line in its '$h' arm — the reader is blind or the arm moved"; continue; }
    printf '%s\n' "$xforks" | grep -qx -- "$forks" \
        || _fail "axis 5: CI job '$job' ($h) self-hosts $forks, but scripts/cross-os-selfhost.sh self-hosts $(echo $xforks) on $h"
done < "$D/sh_jobs"

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed"
    exit 1
fi
echo "PASS: $NAME ($(echo $DELEGATED | wc -w) driver rows delegated in no-skip mode, 0 inline copies, one .tcyr floor ($FL), $NSH self-host forks agree with cross-os-selfhost.sh)"
exit 0
