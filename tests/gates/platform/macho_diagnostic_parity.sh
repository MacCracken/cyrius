#!/bin/sh
# macho_diagnostic_parity.sh — v6.5.43
#
# macho_route_parity.sh compares the two Mach-O backends' ROUTE TABLES. This gate compares
# their DIAGNOSTICS, which had drifted just as far and was invisible to that gate.
#
# ⛔ WHAT THIS EXISTS FOR. Since v5.5.15 the arm64 backend warned "syscall not routed" on any
# number ESYSXLAT/__got does not handle. The x86 Mach-O backend had NO such warning AT ALL —
# `_TARGET_MACHO == 1` simply was not checked — so on Intel-Mac a missing route was silent at
# compile time and a SIGSYS at runtime. That is not hypothetical: `ioctl` sat unrouted on the
# x86 peer and was found at v6.5.36 only by reading the table, and v6.5.16's own notes list
# five ach corpus failures whose common cause was an unrouted number nobody was warned about.
# Adding the x86 arm at v6.5.43 immediately named two numbers in cycc's own macOS build.
#
# Two properties, because either alone passes for the wrong reason:
#   1. BOTH backends are checked in parse_expr — a warning that exists for one arch only is
#      exactly the state this gate was written to end.
#   2. The x86 answer comes from EMACHO_SYSXLAT's OWN rows (query mode), not a second
#      hardcoded list. v6.0.65 had to delete precisely such a list on the ARM side after it
#      drifted to 9 entries against ~40 real routes, so re-introducing one on the x86 side
#      would recreate a bug we have already paid for once.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PE="$ROOT/src/frontend/parse_expr.cyr"
XE="$ROOT/src/backend/x86/emit.cyr"
fail() { echo "FAIL macho_diagnostic_parity: $1" >&2; exit 1; }

# 1. both arches warn
grep -q '_macho_arm_routes(sc_num)' "$PE" || fail "arm64 unrouted-syscall diagnostic missing from parse_expr"
grep -q '_macho_x86_routes(sc_num)' "$PE" || fail "x86 Mach-O unrouted-syscall diagnostic missing from parse_expr — the pre-6.5.43 state, where a missing _msx row was silent at compile time and SIGSYS at runtime"

# The x86 query must be guarded by _TARGET_MACHO == 1 (not 2, and not unguarded — an
# unguarded warning would fire on Linux/PE builds for every ordinary syscall).
awk '/_macho_x86_routes\(sc_num\)/{found=1} /_TARGET_MACHO == 1/{g=NR} END{exit !found}' "$PE" \
  || fail "could not locate the x86 query"
CTX=$(grep -B12 '_macho_x86_routes(sc_num)' "$PE" | grep -c '_TARGET_MACHO == 1' || true)
[ "$CTX" -ge 1 ] || fail "x86 unrouted warning is not guarded by _TARGET_MACHO == 1"

# 2. single source of truth: _macho_x86_routes must REPLAY EMACHO_SYSXLAT, not list numbers.
grep -q 'fn _macho_x86_routes' "$XE" || fail "_macho_x86_routes missing from the x86 backend"
grep -A12 'fn _macho_x86_routes' "$XE" | grep -q 'EMACHO_SYSXLAT(' \
  || fail "_macho_x86_routes does not replay EMACHO_SYSXLAT — a second hardcoded route list is the v6.0.65 bug being reintroduced"

# The only literals allowed in the query fn are the parse_expr reroutes (228/35), which have
# no _msx row by design. Anything else means someone started a parallel list.
LITS=$(sed -n '/fn _macho_x86_routes/,/^}/p' "$XE" | grep -oE 'n == [0-9]+' | grep -oE '[0-9]+' | sort -n -u | tr '\n' ' ')
[ "$LITS" = "35 228 " ] || fail "unexpected literal route list in _macho_x86_routes: '$LITS' (expected exactly the two parse_expr reroutes '35 228 ')"

# 3. both diagnostics NAME the offending number. A warning that fires 470 times during cycc's
#    own build without saying which syscall reads as noise and gets scrolled past.
N=$(grep -c 'PRNUM(sc_num);' "$PE" || true)
[ "$N" -ge 2 ] || fail "expected both Mach-O unrouted diagnostics to print the syscall number via PRNUM (found $N)"

echo "PASS macho_diagnostic_parity: both Mach-O backends warn on unrouted syscalls, x86 answers from EMACHO_SYSXLAT's own rows, both name the number"
