#!/bin/sh
# 6.6.6 — the compiler must be able to read its own environment on Windows.
#
# THE BUG. `_read_env` (src/backend/common/runtime.cyr) had a Linux arm
# (/proc/self/environ) and a macOS arm (init-stack envp) and fell through to `return 0`
# on PE, so `cycc.exe` saw NONE of its own knobs. `CYRIUS_STATS=1 cycc.exe < p.cyr`
# printed nothing; `CYRIUS_DCE=1` eliminated nothing. Twenty names, all dead — derive
# the list, do not trust this one:
#   grep -ho '_read_env("[A-Z_]*")' $(transitive includes of src/main_win.cyr) | sort -u
# At 6.6.6 that is 20: STATS, DCE, DCE_VERBOSE, DEBUG_PHASES, DECODE_AUDIT, SYMS, WX,
# IR, MONOMORPH, ASYNC, STACK_ARRAYS, TYPE_CHECK, FILEID_DUMP, POISON, MACHO,
# MACHO_ARM, TARGET_WIN, TARGET_EFI, ALLOW_PARENT_INCLUDES, ALLOW_ABSOLUTE_INCLUDES.
#
# ⭐ WHY IT SURVIVED. The PE reroute it needed — 0xF015 GetEnvironmentVariableA — has
# existed since v6.0.85, and the comment above `_read_env` said the Windows lookup was
# "queued for v5.5.x tail" for five minors after it had actually shipped. The stdlib hit
# the IDENTICAL shape at v6.5.45 (`lib/io.cyr`'s note: "Windows has the reroute but
# NOTHING IN THE STDLIB CALLED IT"), that half was fixed, and the compiler's own copy —
# one call away in this repo — was not, because each was investigated as its own bug
# instead of as one class. A reroute existing is not a reroute being used.
#
# THE AXES.
#   axis 1  LINUX ORACLE (always). `CYRIUS_STATS=1 build/cycc` must print a meter block,
#           and an unset run must print none. The meter LABELS are captured here and
#           become the expected value for axis 3 — so nothing in this gate hardcodes a
#           list the emitter could drift from, and a compiler that always (or never)
#           printed would fail this axis before axis 3 could read anything into it.
#   axis 2  PE IMPORT TABLE (always, needs objdump). The PE compiler's kernel32 imports
#           must include GetEnvironmentVariableA. Measured: 0 entries at 6.6.5, 1 at
#           6.6.6. This reads the BINARY's import directory, not the source, so it
#           cannot be satisfied by a `_read_env` arm that is written but unreachable.
#   axis 3  KNOB ONE, under wine (SKIPs without it; wine is NOT hardware). CYRIUS_STATS
#           on cycc.exe must produce the same labels as the Linux oracle, and nothing
#           when unset. This knob is read in src/main_win.cyr.
#   axis 4  KNOB TWO, through a DIFFERENT code path. CYRIUS_DCE is read in
#           src/backend/x86/fixup.cyr and is observable in the DCE note: unset it invites
#           you ("set CYRIUS_DCE=1 to eliminate"), set it reports "NOPed". One knob could
#           be wired by accident at one call site; two, in two files, cannot.
#
# HARDWARE — MEASURED ON REAL cass (Win11), 2026-09-19, and this is the recipe to re-take it.
# wine is the local approximation; nothing here should be believed from wine alone.
#     scp cycc.exe + a probe to C:\cyrius-tests\<dir>, then:
#     ssh cass 'cmd /c "cd /d C:\cyrius-tests\<dir> && set CYRIUS_STATS=1&& cycc.exe < p.cyr > o.exe 2> e.txt"'
#   ⚠ `set CYRIUS_STATS=1&&` — NO SPACE before the `&&`. `set VAR=1 & prog` sets VAR to
#   "1 ", WITH the trailing space, and every knob in the compiler tests
#   `load8(v)==49 && load8(v+1)==0`, so the value silently fails to match and the run looks
#   exactly like the unfixed compiler. That cost a wrong "still broken on hardware" reading
#   on the first attempt at this very measurement.
#   Results: cycc.exe (6.6.6) printed the full 7-row meter block; the 6.6.5 binary on the
#   same host, same command, printed ZERO bytes of stderr. With CYRIUS_DCE=1 over a
#   20-dead-fn source: 6.6.6 "20 unreachable fns (1457 bytes NOPed)", 6.6.5 "1457 bytes —
#   set CYRIUS_DCE=1 to eliminate". The PE self-host fixpoint was re-taken on cass with
#   this change in (cycc.exe -> c2.exe -> c3.exe, fc /b clean, and c2.exe byte-identical to
#   the Linux cross-built cycc.exe).
#
# MUTATION LEDGER — both mutants BUILT AND RUN, 2026-09-19 at 6.6.6 (wine 11.17).
#   mutant                                                  axis 1  axis 2  axis 3  axis 4
#   the 6.6.5 compiler (ca452ec6 build/cycc) cross-building  PASS    FAIL    FAIL    FAIL
#     the PE compiler — i.e. a full revert of bite 18b               (0 imports)
#   delete ONLY the `#ifdef CYRIUS_TARGET_WIN` arm from      PASS    FAIL    FAIL    FAIL
#     _read_env in src/backend/common/runtime.cyr
# Both mutants leave axis 1 green, which is the point of axis 1: it proves the knob
# mechanism itself is intact, so axes 2-4 are measuring the Windows path and nothing else.
#
# Nothing is written inside the tree; everything lands in a mktemp -d removed on exit.

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
LABEL_FLOOR=6

[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f "$ROOT/src/main_win.cyr" ] || { echo "  FAIL: src/main_win.cyr is missing"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
cd "$ROOT" || exit 1
ulimit -c 0

# A one-line program and a stdlib-heavy one: the first keeps the meter block small, the
# second gives the DCE pass something real to eliminate.
printf 'fn main(): i64 { return 7; }\nvar e = main();\n' > "$D/tiny.cyr"
printf 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/io.cyr"\nfn main(): i64 { return 7; }\nvar e = main();\n' > "$D/heavy.cyr"

labels() {   # the meter row names printed on stderr, one per line
    grep -oE '^  [a-z_]+:' "$1" | tr -d ' :' | sort
}

# --- axis 1: the Linux oracle, and the anti-vacuous pair ---
CYRIUS_STATS=1 "$CC" < "$D/tiny.cyr" > /dev/null 2> "$D/lin_set.err"
"$CC" < "$D/tiny.cyr" > /dev/null 2> "$D/lin_unset.err"
labels "$D/lin_set.err" > "$D/want_labels"
n_want=$(wc -l < "$D/want_labels")
n_unset=$(labels "$D/lin_unset.err" | wc -l)
if [ "$n_want" -lt "$LABEL_FLOOR" ]; then
    echo "  FAIL axis 1: CYRIUS_STATS=1 on Linux printed $n_want meter rows, floor is $LABEL_FLOOR"
    fail=1
elif [ "$n_unset" != "0" ]; then
    echo "  FAIL axis 1 (anti-vacuous): the UNSET Linux run also printed $n_unset meter rows — the knob is not what makes the block appear"
    fail=1
else
    echo "  ok axis 1: the Linux oracle prints $n_want meter rows with CYRIUS_STATS=1 and none without"
fi

# --- axis 2: the PE compiler's own import table ---
CYRIUS_TARGET_WIN=1 "$CC" < src/main_win.cyr > "$D/cycc.exe" 2> "$D/pebuild.err" || true
if [ ! -s "$D/cycc.exe" ]; then
    echo "  FAIL axis 2: the PE build of src/main_win.cyr produced no binary"
    grep -m3 "^error" "$D/pebuild.err" | sed 's/^/      /'
    fail=1
elif ! command -v objdump > /dev/null 2>&1; then
    echo "  SKIP axis 2: objdump not available (a strings scan is NOT a substitute — cycc carries the name as a literal in its own reroute-warning text whether or not it imports it)"
else
    nimp=$(objdump -x "$D/cycc.exe" 2>/dev/null | sed -n '/DLL Name/,$p' | grep -c 'GetEnvironmentVariableA')
    ncf=$(objdump -x "$D/cycc.exe" 2>/dev/null | sed -n '/DLL Name/,$p' | grep -c 'CreateFileW')
    if [ "$ncf" -lt 1 ]; then
        echo "  FAIL axis 2 (anti-vacuous): the import directory could not be read at all (CreateFileW is missing too)"
        fail=1
    elif [ "$nimp" -lt 1 ]; then
        echo "  FAIL axis 2: the PE compiler does not import GetEnvironmentVariableA — _read_env cannot see anything on Windows"
        fail=1
    else
        echo "  ok axis 2: the PE compiler imports GetEnvironmentVariableA from kernel32"
    fi
fi

# --- axes 3 and 4: behaviour, under wine ---
if [ ! -s "$D/cycc.exe" ]; then
    :
elif ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP axes 3-4: wine absent — the PE BEHAVIOUR of the knobs is covered only by the cass leg"
else
    export WINEPREFIX="$D/wp" WINEDEBUG=-all
    export WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'

    CYRIUS_STATS=1 wine "$D/cycc.exe" < "$D/tiny.cyr" > /dev/null 2> "$D/pe_set.err"
    wine "$D/cycc.exe" < "$D/tiny.cyr" > /dev/null 2> "$D/pe_unset.err"
    labels "$D/pe_set.err" > "$D/got_labels"
    n_pe_unset=$(labels "$D/pe_unset.err" | wc -l)
    if ! cmp -s "$D/want_labels" "$D/got_labels"; then
        echo "  FAIL axis 3: CYRIUS_STATS is invisible to cycc.exe — PE printed $(wc -l < "$D/got_labels") meter rows, the Linux oracle printed $n_want"
        fail=1
    elif [ "$n_pe_unset" != "0" ]; then
        echo "  FAIL axis 3 (anti-vacuous): cycc.exe printed the meter block with CYRIUS_STATS UNSET"
        fail=1
    else
        echo "  ok axis 3: cycc.exe honours CYRIUS_STATS — the same $n_want meter rows as Linux, and none when unset"
    fi

    CYRIUS_DCE=1 wine "$D/cycc.exe" < "$D/heavy.cyr" > /dev/null 2> "$D/pe_dce.err"
    wine "$D/cycc.exe" < "$D/heavy.cyr" > /dev/null 2> "$D/pe_nodce.err"
    noped=$(grep -c 'bytes NOPed' "$D/pe_dce.err")
    invited=$(grep -c 'set CYRIUS_DCE=1 to eliminate' "$D/pe_nodce.err")
    still=$(grep -c 'set CYRIUS_DCE=1 to eliminate' "$D/pe_dce.err")
    if [ "$invited" -lt 1 ]; then
        echo "  FAIL axis 4 (anti-vacuous): the unset PE run printed no DCE note at all, so the set run proves nothing"
        fail=1
    elif [ "$noped" -lt 1 ] || [ "$still" != "0" ]; then
        echo "  FAIL axis 4: CYRIUS_DCE is invisible to cycc.exe — the note still invites you to set it ($still) and reports no elimination ($noped)"
        fail=1
    else
        echo "  ok axis 4: cycc.exe honours CYRIUS_DCE too — a second knob, read in a different source file"
    fi
    rm -rf "$D/wp"
fi

if [ "$fail" = "0" ]; then
    echo "PASS: the PE compiler reads its own environment (import table + two knobs in two files)"
    exit 0
fi
echo "FAIL: the PE compiler cannot read its environment"
exit 1
