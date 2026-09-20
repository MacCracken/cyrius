#!/bin/sh
# Gate: the duplicate-symbol warning still fires in a LARGE program (6.6.6 bite 19c).
#
# THE DEFECT (measured at 6.6.5):
#
#     var a = 5;                                  -> warning: duplicate symbol 'a' redefined
#     var a = 7;                                     with conflicting value (...)
#
#     <1100 globals>; var a = 5; var a = 7;       -> SILENT
#
# CHKDUPVAL opened with a blanket `if (pi >= 1024) { return 0; }` over the WHOLE function, so
# once a program had registered 1024 vars every later collision went unreported — and the
# programs that collide are exactly the large ones that co-link several modules. The value was
# correct; only the diagnostic vanished. The `SYS_*` note (four lines telling a consumer that
# overriding an arch-aware syscall number emits a DIFFERENT syscall on aarch64 and macOS,
# silently) vanished with it.
#
# THE REAL TABLE SIZES, which is what the cap should have been derived from:
#   - gvar_initval (`_vgsi_base`, the literal-init prior) is a GROWN table — it doubles with
#     the var count, and the hard ceiling is 1048576. It never had a 1024 cap.
#   - enum_const_val / the enum-presence flag stop at 1024 because the enum FOLD itself does
#     (PARSE_ENUM_DEF's `if (vcnt < 1024)`), and GVECP already returns 0 above it.
# So the blanket cap was the ENUM table's bound applied to BOTH halves. Removing it makes the
# literal half work at any index; the enum half is unchanged and still bounded by its own
# reader. (An enum constant registered past index 1024 is not FOLDED at all — a separate
# defect, not this one, and not addressed here.)
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual: every warning row also runs the
# program and checks the VALUE against a control that spells the winning definition once, so a
# row cannot pass on the diagnostic alone; and the warning COUNT is asserted exactly (not
# `>= 1`), so a cascade fails as loudly as a silence.
#
# The scale rows generate >1024 globals so the prior lands past the old cap. The floor is
# derived from the generated file, not assumed.
#
# MUTATION LEDGER (6.6.6 — the mutant is a scratch tree whose src/ carries the mutation, built
# by build/cycc and run as CYCC=<mutant>):
#   1. the blanket `if (pi >= 1024) { return 0; }` restored -> RED rows A D F
#   2. CHKDUPVAL made a no-op entirely                      -> RED rows A B D E F
#   3. real tree                                            -> GREEN (6 rows)
# Rows B/C/E are guards, not detectors: they were already correct at 6.6.5 (B and E because the
# prior sits at a LOW index, C because silence is what a same-value redeclaration means).
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: duplicate_symbol_warning_at_scale: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# The filler: enough globals that the NEXT declaration's prior sits past the old 1024 cap.
FILL="$WORK/fill.inc"
: > "$FILL"
i=0
while [ "$i" -lt 1100 ]; do printf 'var dsw_d%s = %s;\n' "$i" "$((i + 1))" >> "$FILL"; i=$((i + 1)); done
NFILL=$(grep -c '^var dsw_d' "$FILL")
[ "$NFILL" -gt 1024 ] || bad "the filler declares only $NFILL globals; it must exceed the old 1024 cap"

# compile <src> <out>: a failed compile or an empty binary is a failure, never a silent pass.
compile() {
    set +e; "$CC" < "$1" > "$2" 2> "$2.err"; _c=$?; set -e
    [ "$_c" = "0" ] || return 1
    [ -s "$2" ] || return 1
    chmod +x "$2"
    return 0
}
# _row <id> <scale:1|0> <want-warnings> <want-exit> <name> <body> <control-body> [prefix]
# <prefix> is emitted BEFORE the filler, so a row can put a declaration at a LOW var index
# with the filler between it and the redeclaration.
_row() {
    NROWS=$((NROWS + 1))
    _id=$1; _scale=$2; _wn=$3; _we=$4; _nm=$5; _b=$6; _c=$7; _pre=${8:-}
    : > "$WORK/t.cyr"; : > "$WORK/c.cyr"
    if [ -n "$_pre" ]; then printf '%b' "$_pre" >> "$WORK/t.cyr"; printf '%b' "$_pre" >> "$WORK/c.cyr"; fi
    if [ "$_scale" = "1" ]; then cat "$FILL" >> "$WORK/t.cyr"; cat "$FILL" >> "$WORK/c.cyr"; fi
    printf '%b' "$_b" >> "$WORK/t.cyr"
    printf '%b' "$_c" >> "$WORK/c.cyr"
    if compile "$WORK/t.cyr" "$WORK/t.bin"; then
        set +e; "$WORK/t.bin" > /dev/null 2>&1; _r=$?; set -e
    else
        _r=CCFAIL
    fi
    _n=$(grep -c "duplicate symbol '$_nm' redefined with conflicting value" "$WORK/t.bin.err" || true)
    [ "$_n" = "$_wn" ] || bad "row $_id: $_n warnings for '$_nm', want exactly $_wn"
    [ "$_r" = "$_we" ] || bad "row $_id: exit $_r, want $_we"
    # the value, computed a different way: a control that writes the winning definition once
    if compile "$WORK/c.cyr" "$WORK/c.bin"; then
        set +e; "$WORK/c.bin" > /dev/null 2>&1; _cr=$?; set -e
    else
        _cr=CCFAIL
    fi
    [ "$_cr" = "$_we" ] || bad "row $_id: CONTROL exit $_cr, want $_we (the gate's own premise is off)"
}

# A — the filed repro: a conflicting redeclaration with >1024 priors. SILENT at 6.6.5.
_row A 1 1 7 dsw_a 'var dsw_a = 5;\nvar dsw_a = 7;\nsyscall(60, dsw_a);\n' \
                   'var dsw_a = 7;\nsyscall(60, dsw_a);\n'
# B — the same shape SMALL: the warning was never broken here. Regression guard.
_row B 0 1 7 dsw_a 'var dsw_a = 5;\nvar dsw_a = 7;\nsyscall(60, dsw_a);\n' \
                   'var dsw_a = 7;\nsyscall(60, dsw_a);\n'
# C — a SAME-VALUE redeclaration at scale is silent on purpose (two files, or an #ifdef arm,
#     legitimately declaring one constant). Exactly zero warnings.
_row C 1 0 5 dsw_a 'var dsw_a = 5;\nvar dsw_a = 5;\nsyscall(60, dsw_a);\n' \
                   'var dsw_a = 5;\nsyscall(60, dsw_a);\n'
# E — an ENUM-const prior at a LOW index, with >1024 vars between it and the `var` that
#     shadows it. The prior's index is what the cap looked at, so this was already correct;
#     it guards the enum half of the probe.
_row E 1 1 7 dsw_KK 'var dsw_b = dsw_KK;\nvar dsw_KK = 7;\nsyscall(60, dsw_b);\n' \
                    'var dsw_KK = 7;\nvar dsw_b = dsw_KK;\nsyscall(60, dsw_b);\n' \
                    'enum DswE { dsw_KK = 5; }\n'
# F — a three-link chain at scale: the 2nd and 3rd links each report, and the last wins.
_row F 1 2 4 dsw_a 'var dsw_a = 1;\nvar dsw_a = 2;\nvar dsw_a = 4;\nsyscall(60, dsw_a);\n' \
                   'var dsw_a = 4;\nsyscall(60, dsw_a);\n'

# D — the `SYS_*` note at scale. A consumer's own `var SYS_FOO = <x86 number>` agrees on x86
#     and WINS everywhere else, so the emitted svc issues a different, valid syscall. The note
#     is four lines and it went silent with the warning; checking the WARNING alone would pass
#     a fix that restored only the first line.
NROWS=$((NROWS + 1))
cat "$FILL" > "$WORK/s.cyr"
printf 'var SYS_DSWZZ = 5;\nvar SYS_DSWZZ = 7;\nsyscall(60, SYS_DSWZZ);\n' >> "$WORK/s.cyr"
if compile "$WORK/s.cyr" "$WORK/s.bin"; then
    set +e; "$WORK/s.bin" > /dev/null 2>&1; sr=$?; set -e
else
    sr=CCFAIL
fi
[ "$sr" = "7" ] || bad "row D: exit $sr, want 7"
sn=$(grep -c "duplicate symbol 'SYS_DSWZZ' redefined with conflicting value" "$WORK/s.bin.err" || true)
[ "$sn" = "1" ] || bad "row D: $sn warnings, want exactly 1"
snote=$(grep -c "ARCH-AWARE" "$WORK/s.bin.err" || true)
[ "$snote" = "1" ] || bad "row D: $snote 'ARCH-AWARE' note lines, want exactly 1"
sdrop=$(grep -c "Drop the local definition and include lib/syscalls.cyr instead" "$WORK/s.bin.err" || true)
[ "$sdrop" = "1" ] || bad "row D: the note's closing advice line is missing"

# Anti-vacuity: the floor is DERIVED from this file's own row calls.
WANT=$(( $(grep -cE '^_row [A-Z] ' "$0") + 1 ))
[ "$NROWS" -eq "$WANT" ] || bad "only $NROWS rows ran; this file spells $WANT"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: duplicate_symbol_warning_at_scale: $NFAIL of $NROWS rows"
    exit 1
fi
echo "PASS: the duplicate-symbol warning and its SYS_* note survive $NFILL preceding globals ($NROWS rows)"
exit 0
