#!/bin/sh
# 6.6.6 — `open()`'s flag word must mean the same thing on Windows as it does on Linux.
#
# THE BUG. `EOPEN_PE` (src/backend/x86/emit.cyr) translated `syscall(2, path, flags, mode)`
# into CreateFileW by building dwCreationDisposition out of O_CREAT (0x40) and O_EXCL (0x80)
# ALONE, and by hardcoding dwDesiredAccess to GENERIC_READ|GENERIC_WRITE. Every other bit of
# the flag word was dropped: O_TRUNC did not truncate and O_APPEND did not append. Measured
# on HEAD before the fix (wine 11.17, and the same on real cass): a 17-byte file reopened
# `O_WRONLY|O_CREAT|O_TRUNC` and written "XYZ" stayed 17 bytes, "XYZ3456789abcdef\n", and
# `O_APPEND` did exactly the same thing instead of appending. That is SILENT DATA
# CORRUPTION for every Windows consumer that rewrites a file — the open SUCCEEDS, the write
# SUCCEEDS, and the old tail is still there — and it undercuts the atomic writers, whose
# whole job is rewrite-a-temp-then-rename.
#
# WHAT THE FIX IS. `_pe_open_flags` derives BOTH CreateFileW words from the flags:
#   access   O_RDONLY→GENERIC_READ, O_WRONLY→GENERIC_WRITE, O_RDWR→both;
#            O_APPEND replaces the write bit with FILE_APPEND_DATA (4).
#   disposition  O_CREAT|O_EXCL→CREATE_NEW, O_CREAT|O_TRUNC→CREATE_ALWAYS,
#                O_TRUNC→TRUNCATE_EXISTING, O_CREAT→OPEN_ALWAYS, else OPEN_EXISTING.
#   and then the two are RECONCILED: TRUNCATE_EXISTING forces GENERIC_WRITE into the access
#                word, because Win32 refuses that disposition without it.
#
# THE THREE AXES, AND WHICH ONE IS REAL.
#   axis 1  POSIX ORACLE (always runs). The rows are asserted against the LINUX kernel, by
#           running tests/tcyr/crossos/open_flag_translation.tcyr natively. This axis does
#           not test the PE backend at all — it establishes that the expected values are
#           POSIX's, not a table this gate and the emitter both made up. A check that shares
#           its expectations with the thing it checks reads GREEN; this one does not.
#   axis 2  EMITTER SHAPE (always runs, needs objdump). Disassembles a PE build and asserts
#           the defect's own instruction — `mov $0xc0000000,%edx`, the hardcoded
#           dwDesiredAccess — is GONE, and that the emit functions agree: `mov %r9d,%edx`
#           (from EOPEN_PE), `or $0x4,%r9d` (the O_APPEND map) and `or $0x40000000,%r9d` (the
#           GENERIC_WRITE that TRUNCATE_EXISTING requires) must occur the SAME number of
#           times, at least once. Three counts from two functions, so a half-revert of any
#           one is caught. This is a shape check; it cannot tell you the mapping is CORRECT,
#           only that the fix has not been reverted — but for the GENERIC_WRITE half it is
#           the ONLY local axis, because wine does not enforce that Win32 rule (see ⭐⭐).
#   axis 3  BEHAVIOUR (SKIPs without wine — and wine is NOT hardware). Runs the same .tcyr
#           as a PE binary and requires the identical pass count. The HARDWARE verification
#           is the release gate's cross-OS leg executing that .tcyr on real cass; this axis
#           is the local approximation that catches a regression before it gets there.
#
# ANTI-VACUOUS. The pass count is derived TWICE: grepped statically out of the .tcyr source
# (assert_eq/assert_neq call sites, comments stripped) and read from what the binary prints
# at run time. They must agree, and must be at least the ROW FLOOR below — so deleting rows
# from the .tcyr fails this gate instead of quietly shrinking it.
#
# ROW FLOOR: 30 assertions (measured 2026-09-19 at 6.6.6; 25 at the bite's first cut, +5 for the
# two TRUNCATE_EXISTING access rows added in the review round). Raise it when rows are added.
#
# MUTATION LEDGER — every mutant BUILT AND RUN, 2026-09-19 at 6.6.6, x86_64 Linux + wine 11.17.
# Each mutant is a scratch tree (git archive of lib+src, one edit, rebuilt with build/cycc)
# plus a copy of this gate, so $ROOT resolution picks the mutant up exactly as a regression.
#
# ⚠ ALL FOUR ROWS RE-MEASURED in the review round against the 30-row .tcyr (the counts moved:
# the two TRUNCATE_EXISTING rows are red under some of these mutants too).
#
#   mutant                                                   axis 1  axis 2       axis 3 (wine)
#   the 6.6.5 compiler (ca452ec6 build/cycc) — a full         PASS    FAIL (the    FAIL, exit 12
#     revert of this bite                                             hardcoded    (12 rows red)
#                                                                     edx is back)
#   revert ONLY `mov edx,r9d` to `mov edx,0xC0000000`         PASS    FAIL         FAIL, exit 7
#     (the dwDesiredAccess half)                                                   (append +
#                                                                                  access rows)
#   delete ONLY the O_TRUNC ladder (the `test ecx,0x200`      PASS    PASS <-- ⭐   FAIL, exit 5
#     block in _pe_open_flags)                                                     (the trunc
#                                                                                  rows)
#   drop the `cmp eax,5 / or r9d,GENERIC_WRITE` tail of       PASS    FAIL         PASS <-- ⭐⭐
#     _pe_open_flags (the bite's FIRST CUT, HEAD before                            wine accepts
#     the review round)                                                            it; REAL cass
#                                                                                  runs 25/30
#
# ⭐ READ THE THIRD ROW. Axis 2 PASSES a compiler whose O_TRUNC is still broken, because the
# signature it greps for lives in the access half and that mutation does not touch it. Axis 2
# alone is NOT a regression gate for this bite — axis 3, and behind it the cass leg, are. That
# is why the wine SKIP is spelled out rather than hidden: on a box without wine this gate still
# catches a whole-bite revert and does NOT catch a disposition-only one.
#
# ⭐⭐ READ THE FOURTH ROW, IT IS THE ONE THIS GATE LEARNED FROM. The bite's first cut chose the
# two CreateFileW words INDEPENDENTLY, and Win32 does not allow that: TRUNCATE_EXISTING is
# REFUSED (ERROR_INVALID_PARAMETER) unless dwDesiredAccess carries GENERIC_WRITE. wine does not
# enforce the rule, so axis 3 passed that mutant 30/30 while REAL cass ran 25/30 — the two
# TRUNCATE_EXISTING rows plus the tail-check returned fd = -1. Concrete instance of "wine is
# not hardware", measured 2026-09-19 on cass (Win 10.0.26200) both ways. Axis 2's
# `or $0x40000000,%r9d` count is the only LOCAL guard on that half.
#
# ⚠ The second row is also why the .tcyr keeps its "append ignores an explicit seek" row: that
# mutant's output names it directly ("the write landed at EOF despite the seek ... got 17"),
# which is the evidence that a seek-to-end implementation of O_APPEND would be caught here.
#
# Nothing is written inside the tree: the .tcyr creates CWD-relative files, so both runs
# happen inside a mktemp -d that is removed on exit.

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
SRC="$ROOT/tests/tcyr/crossos/open_flag_translation.tcyr"
FLOOR=30

[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f "$SRC" ] || { echo "  FAIL: $SRC is missing — the cross-OS companion for this bite is gone"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0

# Expected value, derivation A: count the assertion call sites in the source, comments
# stripped. Every row in that file executes exactly once (no loops, no conditionals), which
# is what makes a static count a legitimate oracle for the runtime one.
want=$(grep -v '^[[:space:]]*#' "$SRC" | grep -cE 'assert_(eq|neq)\(')
if [ "$want" -lt "$FLOOR" ]; then
    echo "  FAIL floor: the .tcyr carries only $want assertions, floor is $FLOOR — rows were deleted"
    fail=1
else
    echo "  ok floor: $want assertions in the .tcyr (floor $FLOOR)"
fi

# Expected value, derivation B: what the binary reports at run time.
ran_count() {   # $1 = output file -> the "N passed" number, or -1
    sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' "$1" | while read -r p f; do
        if [ "$f" = "0" ]; then echo "$p"; else echo "-1"; fi
    done
}

# --- axis 1: the POSIX oracle — the same rows against the Linux kernel ---
cd "$ROOT" || exit 1
"$CC" < "$SRC" > "$D/oft_elf" 2> "$D/elf.err" || true
if [ ! -s "$D/oft_elf" ]; then
    echo "  FAIL axis 1: the ELF build of the .tcyr produced no binary"
    grep -m3 "^error" "$D/elf.err" | sed 's/^/      /'
    fail=1
else
    chmod +x "$D/oft_elf"
    ( cd "$D" && ulimit -c 0; ./oft_elf > "$D/elf.out" 2>&1 ); rc=$?
    got=$(ran_count "$D/elf.out")
    if [ "$rc" != "0" ] || [ "$got" != "$want" ]; then
        echo "  FAIL axis 1 (POSIX oracle): native run exited $rc, reported '$got' of $want rows"
        grep -hm5 "FAIL:" "$D/elf.out" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 1: $got of $want rows hold against the Linux kernel (these are POSIX's expectations, not ours)"
    fi
fi

# --- axis 2: the emitter shape — the defect's instruction is gone, the two halves agree ---
CYRIUS_TARGET_WIN=1 "$CC" < "$SRC" > "$D/oft.exe" 2> "$D/pe.err" || true
if [ ! -s "$D/oft.exe" ]; then
    echo "  FAIL axis 2: the PE build of the .tcyr produced no binary"
    grep -m3 "^error" "$D/pe.err" | sed 's/^/      /'
    fail=1
elif ! command -v objdump > /dev/null 2>&1; then
    echo "  SKIP axis 2: objdump not available (a raw byte scan is not a substitute — see pe_no_raw_syscall_bytes)"
else
    objdump -d "$D/oft.exe" > "$D/dis" 2>/dev/null
    hard=$(grep -cE 'mov[[:space:]]+\$0xc0000000,%edx' "$D/dis")
    a_edx=$(grep -cE 'mov[[:space:]]+%r9d,%edx' "$D/dis")
    a_app=$(grep -cE 'or[[:space:]]+\$0x4,%r9d' "$D/dis")
    # The access word and the disposition word are NOT independent: Win32 refuses
    # TRUNCATE_EXISTING unless GENERIC_WRITE is in dwDesiredAccess (ERROR_INVALID_PARAMETER,
    # measured on cass — and wine does NOT enforce it, so axis 3 is blind to this half).
    # That makes this grep the only local guard on it.
    a_gw=$(grep -cE 'or[[:space:]]+\$0x40000000,%r9d' "$D/dis")
    if [ "$hard" != "0" ]; then
        echo "  FAIL axis 2: $hard site(s) still load dwDesiredAccess from the hardcoded 0xC0000000 — the flag word is being ignored"
        fail=1
    elif [ "$a_edx" -lt 1 ]; then
        echo "  FAIL axis 2 (anti-vacuous): the PE build contains NO open reroute at all, so this axis proves nothing"
        fail=1
    elif [ "$a_edx" != "$a_app" ]; then
        echo "  FAIL axis 2: EOPEN_PE emits $a_edx access loads but _pe_open_flags emits $a_app append maps — half of the fix was reverted"
        fail=1
    elif [ "$a_edx" != "$a_gw" ]; then
        echo "  FAIL axis 2: $a_edx open reroute(s) but $a_gw force GENERIC_WRITE for TRUNCATE_EXISTING — Win32 refuses that disposition without it (err 87 on real Windows; wine accepts it, so axis 3 will NOT catch this)"
        fail=1
    else
        echo "  ok axis 2: $a_edx open reroute(s), dwDesiredAccess taken from the decoded flags (incl. the TRUNCATE_EXISTING write bit), no hardcoded 0xC0000000"
    fi
fi

# --- axis 3: behaviour, under wine. NOT hardware — the cass leg of the release gate is. ---
if [ ! -s "$D/oft.exe" ]; then
    :
elif ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP axis 3: wine absent — the PE BEHAVIOUR of these rows is covered only by the cass leg (see the ledger: axis 2 alone misses a disposition-only regression)"
else
    mkdir -p "$D/w" && cp "$D/oft.exe" "$D/w/oft.exe"
    ( cd "$D/w" && ulimit -c 0; WINEPREFIX="$D/wp" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
        wine oft.exe > "$D/pe.out" 2> "$D/pe.err" ); rc=$?
    got=$(ran_count "$D/pe.out")
    if [ "$rc" != "0" ] || [ "$got" != "$want" ]; then
        echo "  FAIL axis 3 (wine): PE run exited $rc, reported '$got' of $want rows"
        grep -hm6 "FAIL:" "$D/pe.err" "$D/pe.out" | sed 's/^/      /'
        fail=1
    else
        echo "  ok axis 3: $got of $want rows hold on PE under wine — identical to the POSIX oracle (hardware: the cass cross-OS leg)"
    fi
    rm -rf "$D/wp"
fi

if [ "$fail" = "0" ]; then
    echo "PASS: open() flags translate to CreateFileW faithfully on PE ($want rows, POSIX oracle + emitter shape + wine)"
    exit 0
fi
echo "FAIL: PE open() flag translation"
exit 1
