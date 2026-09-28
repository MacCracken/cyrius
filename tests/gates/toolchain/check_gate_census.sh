#!/bin/sh
# tests/gates/toolchain/check_gate_census.sh — 6.6.8 (bite 8)
#
# EVERY GATE UNDER tests/gates/ IS REGISTERED EXACTLY ONCE, AND EVERY REGISTERED GATE RUNS
# THROUGH THE ONE PATH THAT RECORDS ITS RESULT.
#
# THE DEFECT. 6.6.6 made scripts/check.sh run every shell gate through `_chk_gate` so that a red
# gate is recorded instead of aborting the `set -e` script — and the same release's later lanes
# added TEN gates as bare `sh "$ROOT/tests/gates/…"` lines. check.sh's registry reader
# (`_chk_shell_manifest`) matches only `^_chk_gate`, so for those ten:
#   * a failure ABORTED the run, every `_chk_gate` below it reported NOT RUN, and the FAILED list
#     omitted the culprit;
#   * no selector could reach them: `check.sh frontend` ran 33 of the 39 frontend gates, and
#     codegen / memory / toolchain each skipped some — and every one of those runs could print
#     ALL GREEN;
#   * the driver's registry reader took only `"tests/gates/…"` literals, so the driver row that
#     runs scripts/differential-smoke.sh was unreachable by any selector as well.
# And the tree's only documented orphan check (a grep recipe in programs/checks/main.cyr)
# counted ANY `tests/gates/…` literal as a registration — it read the bare lines as registered
# and reported 0 orphans. A check that shares the defect it checks for reads green.
#
# WHAT IS PINNED — read with `check.sh --registry`, the SAME readers the selectors and the NOT
# RUN bookkeeping use (one line per registration call, duplicates kept):
#   axis 1  every tests/gates/**/*.sh is registered, and registered EXACTLY ONCE
#   axis 2  every registration names a file that exists (tests/gates/… and scripts/…)
#   axis 3  every driver `_gate(` call carries a literal path the reader sees — counted
#           independently from the call sites, so a call with a computed path cannot hide
#   axis 4  scripts/check.sh runs no gate outside `_chk_gate`: a gate path literal appears only
#           on a registration line, and nothing `sh`/`bash`/`.`-runs a $ROOT script except the
#           staging call to scripts/install.sh
#   axis 5  every driver-registered path resolves as a selector (`--resolve gate:<name>`)
#   axis 6  ANTI-VACUOUS: the census is run against four mutants of the registry and must go
#           red on each — one `_chk_gate` turned back into a bare `sh` (axes 1 + 4), a gate
#           registered twice (axis 1), a registration of a missing file (axis 2), and a driver
#           `_gate(` whose path is a variable (axis 3).
#
# MUTATION PROOF (6.6.8, outside this gate): with the ten bare `sh` lines restored in
# scripts/check.sh this gate is RED on axes 1 and 4, naming each one (measured with one restored); with
# `_chk_driver_gate_manifest` back to its `"tests/gates/…"`-only grep it is RED on axis 3
# (160 `_gate(` calls, 159 seen — scripts/differential-smoke.sh) and on axis 5.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

# A scratch root carrying only what check.sh's registry readers read (scripts/check.sh and
# programs/checks/*.cyr), plus a stub check binary newer than every source so check.sh never
# rebuilds anything. Nothing here can write the tree or stage a CYRIUS_HOME.
_mkroot() {  # $1 = dir
    mkdir -p "$1/scripts" "$1/build" "$1/programs/checks" "$1/lib" "$1/tmp"
    cp "$ROOT/scripts/check.sh" "$1/scripts/check.sh"
    cp "$ROOT"/programs/checks/*.cyr "$1/programs/checks/"
    cp "$ROOT/VERSION" "$1/"
    : > "$1/lib/placeholder.cyr"
    printf '#!/bin/sh\nexit 0\n' > "$1/build/cycc"
    printf '#!/bin/sh\nexit 0\n' > "$1/build/cyrius_check"
    chmod +x "$1/build/cycc" "$1/build/cyrius_check"
    touch -d '2038-01-01' "$1/build/cyrius_check"
}
_chk() {  # $1 = scratch root; runs its check.sh with the remaining args
    _r=$1; shift
    ( cd "$_r" && env -u CYRIUS_HOME TMPDIR="$_r/tmp" sh scripts/check.sh "$@" )
}

# The census over one scratch root. Prints each finding, returns the number found. Files on
# disk always come from the REAL tree; only the registry (check.sh + the driver sources) varies.
_census() {  # $1 = scratch root, $2 = tag for scratch files
    _R=$1; _t=$2; _n=0
    if ! _chk "$_R" --registry > "$D/$_t.reg" 2>"$D/$_t.err"; then
        echo "    check.sh --registry exited non-zero:"; sed 's/^/      /' "$D/$_t.err"
        return 1
    fi
    find tests/gates -name '*.sh' | LC_ALL=C sort > "$D/$_t.disk"
    grep '^tests/gates/' "$D/$_t.reg" | LC_ALL=C sort > "$D/$_t.regg"
    # axis 1: registered exactly once
    LC_ALL=C comm -23 "$D/$_t.disk" "$D/$_t.regg" | LC_ALL=C sort -u > "$D/$_t.orph"
    while read -r g; do
        [ -n "$g" ] || continue
        echo "    axis 1: NOT REGISTERED (no selector reaches it, a failure is never recorded): $g"
        _n=$((_n + 1))
    done < "$D/$_t.orph"
    LC_ALL=C sort "$D/$_t.reg" | uniq -d > "$D/$_t.dup"
    while read -r g; do
        [ -n "$g" ] || continue
        echo "    axis 1: REGISTERED MORE THAN ONCE (it runs twice): $g"
        _n=$((_n + 1))
    done < "$D/$_t.dup"
    # axis 2: every registration names a real file
    while read -r g; do
        [ -n "$g" ] || continue
        [ -f "$ROOT/$g" ] || { echo "    axis 2: registered but there is NO SUCH FILE: $g"; _n=$((_n + 1)); }
    done < "$D/$_t.reg"
    # axis 3: every driver `_gate(` call is one the reader saw. Call sites counted from the
    # source, independently of the reader's own regex.
    _calls=$(grep -hE '(^|[^A-Za-z0-9_])_gate\(' "$_R"/programs/checks/*.cyr \
        | grep -vE '^[[:space:]]*#' | grep -cvE '^[[:space:]]*fn[[:space:]]+_gate\(' || true)
    _shreg=$(grep -cE '^_chk_gate "\$ROOT/' "$_R/scripts/check.sh" || true)
    _total=$(grep -c . "$D/$_t.reg" || true)
    _drv=$((_total - _shreg))
    if [ "$_calls" != "$_drv" ]; then
        echo "    axis 3: the driver makes $_calls _gate( call(s) but the registry reader sees $_drv — a call whose path is not a literal the reader can see"
        _n=$((_n + 1))
    fi
    # axis 4: no gate runs outside _chk_gate in check.sh
    grep -nE 'tests/gates/[a-z-]+/[A-Za-z0-9_]+\.sh' "$_R/scripts/check.sh" \
        | grep -vE '^[0-9]+:[[:space:]]*#' \
        | grep -vE '^[0-9]+:_chk_gate "\$ROOT/tests/gates/[a-z-]+/[A-Za-z0-9_]+\.sh"([[:space:]].*)?$' > "$D/$_t.bare" || true
    grep -nE '(^|[[:space:];&|(])(sh|bash|\.|exec)[[:space:]]+"?\$\{?ROOT\}?/' "$_R/scripts/check.sh" \
        | grep -vE '^[0-9]+:[[:space:]]*#' \
        | grep -v 'scripts/install\.sh" --refresh-only' >> "$D/$_t.bare" || true
    LC_ALL=C sort -u "$D/$_t.bare" > "$D/$_t.bare2"
    while read -r l; do
        [ -n "$l" ] || continue
        echo "    axis 4: check.sh runs a gate OUTSIDE _chk_gate (a failure aborts the run and no selector sees it): line $l"
        _n=$((_n + 1))
    done < "$D/$_t.bare2"
    return "$_n"
}

R="$D/real"
_mkroot "$R"

echo "axis 1-4: the census over the tree's own registry"
NREG=$(_chk "$R" --registry 2>/dev/null | grep -c . || true)
NDISK=$(find tests/gates -name '*.sh' | grep -c . || true)
# Floors: an empty reader or an empty find would make every axis vacuously green.
[ "$NDISK" -ge 200 ] || _fail "only $NDISK gate file(s) under tests/gates — the find is blind"
[ "$NREG" -ge 200 ] || _fail "check.sh --registry printed only $NREG registration(s) — the reader is blind"
_census "$R" real
RC=$?
[ "$RC" = "0" ] || _fail "the census found $RC problem(s) in the registry (listed above)"
echo "  $NDISK gate file(s), $NREG registration(s)"

echo "axis 5: every driver-registered gate resolves as a selector"
grep -hE '(^|[^A-Za-z0-9_])_gate\(' programs/checks/*.cyr | grep -vE '^[[:space:]]*#' \
    | grep -oE '"(tests/gates|scripts)/[A-Za-z0-9_./-]+\.sh"\);' \
    | sed 's|.*/||; s|\.sh");$||' | LC_ALL=C sort -u > "$D/dnames"
ND=$(grep -c . "$D/dnames" || true)
[ "$ND" -ge 100 ] || _fail "only $ND driver gate name(s) — the driver scan is blind"
sed 's/^/gate:/' "$D/dnames" > "$D/dq"
RC5=0
# shellcheck disable=SC2046  # the selectors are shell words by construction
_chk "$R" --resolve $(cat "$D/dq") > "$D/dres" 2>/dev/null || RC5=$?
[ "$RC5" = "0" ] || { _fail "$(grep -c '^UNRESOLVED' "$D/dres" || true) driver-registered gate(s) do not resolve as a selector"; grep '^UNRESOLVED' "$D/dres" | head -5 | sed 's/^/      /'; }
grep -qx 'gate differential-smoke' "$D/dres" || _fail "the driver's scripts/differential-smoke.sh row is not reachable as gate:differential-smoke"

echo "axis 6: the census goes RED on each mutant (anti-vacuous)"
# 6a: one registered gate turned back into a bare `sh` line — the 6.6.6 shape.
M="$D/m1"; _mkroot "$M"
_victim=$(grep -m1 -E '^_chk_gate "\$ROOT/tests/gates/' "$M/scripts/check.sh")
[ -n "$_victim" ] || _fail "no _chk_gate registration to mutate"
_vpath=$(printf '%s\n' "$_victim" | sed 's|^_chk_gate "\$ROOT/||; s|".*||')
awk -v v="$_victim" '$0 == v && !done { sub(/^_chk_gate /, "sh "); done = 1 } { print }' \
    "$M/scripts/check.sh" > "$M/scripts/check.sh.new" && mv "$M/scripts/check.sh.new" "$M/scripts/check.sh"
_census "$M" m1 > "$D/m1.out"; RCM=$?
[ "$RCM" -ge 2 ] || _fail "a bare \`sh\` gate line was not caught on both axes 1 and 4 (census found $RCM)"
grep -q "axis 1: NOT REGISTERED.*$_vpath" "$D/m1.out" || _fail "mutant 6a: axis 1 did not name $_vpath"
grep -q "axis 4: .*$_vpath" "$D/m1.out" || _fail "mutant 6a: axis 4 did not name the bare line"
# 6b: a gate registered twice.
M="$D/m2"; _mkroot "$M"
printf '_chk_gate "$ROOT/%s"\n' "$_vpath" >> "$M/scripts/check.sh"
_census "$M" m2 > "$D/m2.out"; RCM=$?
grep -q "axis 1: REGISTERED MORE THAN ONCE.*$_vpath" "$D/m2.out" || _fail "mutant 6b: a double registration was not caught (census found $RCM)"
# 6c: a registration of a file that does not exist.
M="$D/m3"; _mkroot "$M"
printf '_chk_gate "$ROOT/tests/gates/toolchain/zz_no_such_gate_census.sh"\n' >> "$M/scripts/check.sh"
_census "$M" m3 > "$D/m3.out"; RCM=$?
grep -q "axis 2: .*zz_no_such_gate_census.sh" "$D/m3.out" || _fail "mutant 6c: a registration with no file was not caught (census found $RCM)"
# 6d: a driver _gate( call whose path the reader cannot see.
M="$D/m4"; _mkroot "$M"
printf 'fn _zz_census_probe(p): i64 {\n    _gate("census probe", p);\n    return 0;\n}\n' >> "$M/programs/checks/main.cyr"
_census "$M" m4 > "$D/m4.out"; RCM=$?
grep -q "axis 3: " "$D/m4.out" || _fail "mutant 6d: a _gate( call with a non-literal path was not caught (census found $RCM)"

if [ "$FAILS" -ne 0 ]; then
    echo "check_gate_census: $FAILS FAILURE(S)"
    exit 1
fi
echo "check_gate_census: every gate registered once, every registration runs through _chk_gate or the driver, 4 mutants caught"
exit 0
