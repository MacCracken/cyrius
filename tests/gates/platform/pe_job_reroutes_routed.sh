#!/bin/sh
# 6.6.10 — the Job-object PE reroutes 0xF040-0xF044 are ROUTED by the parser, at their arity.
#
# lib/process_win.cyr, lib/async_win.cyr and cbt's `_win_run_timed` run every child in a
# KILL_ON_JOB_CLOSE Job object so a deadline ends its whole tree (bite 11). They reach
# CreateJobObjectW / AssignProcessToJobObject / TerminateJobObject / ResumeThread /
# SetInformationJobObject through literal syscall ids that `_PE_ROUTE_JOB`
# (src/frontend/parse_expr.cyr) sends to the ECREATEJOB_PE … ESETJOBINFO_PE emitters. Without
# the parse-side route each id is an unrouted literal: a warning, and -38 (-ENOSYS) at run time,
# so every PE spawn fails (measured: deadline_ends_grandchild.tcyr 13/19 under wine).
#
# THE AXES (compile-only; the behaviour is tests/tcyr/crossos/deadline_ends_grandchild.tcyr on
# real cass in the release gate's cross-OS leg).
#   axis 1  each id at its arity builds with CYRIUS_TARGET_WIN=1 and prints no "not routed"
#           warning for it.
#   axis 2  each id at a WRONG arity (one argument short) still warns — the route is
#           literal-and-arity, like every 0xF0xx id, not a blanket number match.
#   axis 3  the routed-number note names 0xF040-0xF044 (the note and the route table agree).
#   axis 4  the axis-1 build IMPORTS all five kernel32 functions (objdump -p's import table;
#           SKIPs without an objdump that reads PE).
#
# MUTATION (built and run 2026-09-29, lane S1 bite 17): the cycc WITHOUT the `_PE_ROUTE_JOB`
# hunk FAILS axes 1, 3 and 4 (five "syscall 6150x … is not routed" warnings, no job import);
# `_PE_ROUTE_JOB` accepting any arity FAILS axis 2. CHANGELOG [6.6.10]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_job_reroutes_routed: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# id  decimal  name  args-at-arity  args-one-short
ROWS="0xF040 61504 CreateJobObjectW 0,0 0
0xF041 61505 AssignProcessToJobObject 0,0 0
0xF042 61506 TerminateJobObject 0,0 0
0xF043 61507 ResumeThread 0 -
0xF044 61508 SetInformationJobObject 0,0,0,0 0,0,0"

build() {  # $1 = file stem, $2 = the syscall's argument list
    printf 'fn main(): i64 {\n    var j = syscall(%s);\n    return j & 0;\n}\nvar r = main();\nsyscall(60, r);\n' "$2" > "$D/$1.cyr"
    CYRIUS_TARGET_WIN=1 "$CC" < "$D/$1.cyr" > "$D/$1.exe" 2> "$D/$1.err"
}

echo "$ROWS" | while read -r id dec name good short; do
    build "g$dec" "$id, $good"
    rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$D/g$dec.exe" ]; then echo "BAD axis 1: $id ($name) build rc $rc"
    elif grep -q "syscall $dec with" "$D/g$dec.err"; then echo "BAD axis 1: $id ($name) at its arity is reported not routed"
    else echo "OK"; fi
    if [ "$short" != "-" ]; then
        build "s$dec" "$id, $short"
        if grep -q "syscall $dec with" "$D/s$dec.err"; then echo "OK"
        else echo "BAD axis 2: $id ($name) one argument short did not warn"; fi
    else
        # ResumeThread takes one argument; one short is the bare id.
        build "s$dec" "$id"
        if grep -q "syscall $dec with" "$D/s$dec.err"; then echo "OK"
        else echo "BAD axis 2: $id ($name) with no argument did not warn"; fi
    fi
done > "$D/rows.txt"
while read -r line; do
    case "$line" in OK) ok ;; *) bad "${line#BAD }" ;; esac
done < "$D/rows.txt"

# axis 3: any unrouted literal prints the routed-number note once; it must list the job range.
build note "0xF03C, 0, 0"
if grep -q '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/note.err"; then
    if grep '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/note.err" | grep -q '0xF040-0xF044 (kernel32: CreateJobObjectW/AssignProcessToJobObject/TerminateJobObject/ResumeThread/SetInformationJobObject)'; then ok
    else bad "axis 3: the routed-number note does not name 0xF040-0xF044"; fi
else bad "axis 3: the unrouted 0xF03C probe printed no routed-number note"; fi

# axis 4: the imports, read from the import directory.
if objdump -p "$D/g61504.exe" > "$D/imp.txt" 2>/dev/null && grep -q 'DLL Name' "$D/imp.txt"; then
    for dec in 61504 61505 61506 61507 61508; do objdump -p "$D/g$dec.exe"; done > "$D/imp.txt" 2>/dev/null
    for fn in CreateJobObjectW AssignProcessToJobObject TerminateJobObject ResumeThread SetInformationJobObject; do
        if grep -q " $fn\$" "$D/imp.txt"; then ok; else bad "axis 4: no build imports $fn"; fi
    done
else
    echo "  SKIP: axis 4 (no objdump that reads PE)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 10 ] || { echo "FAIL: pe_job_reroutes_routed: only $pass rows ran (floor 10)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_job_reroutes_routed"; exit 1; fi
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: pe_job_reroutes_routed — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: pe_job_reroutes_routed — 0xF040-0xF044 are routed at their arity, named in the note, imported"
