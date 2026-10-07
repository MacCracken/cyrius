#!/bin/sh
# Gate: the preprocessor's fixed-size tables refuse, BY NAME, what they cannot hold (6.6.20).
#
# Every row compiles a generated program with build/cycc (or $CYCC) and checks the exit code,
# the diagnostic and — where the program is accepted — what the binary returns.
#
# A. The #if / #ifdef / #ifndef / #ifplat per-level state stack at S+0x197F10 is 64 bytes, one
#    per nesting level. Until 6.6.20 none of its seven push sites (PP_PASS 4, PP_IFDEF_PASS 3)
#    checked the depth: each deeper level wrote its state byte upward through live compiler
#    state — silently, until ~24.8K levels hit the jump-target count, and at ~344K levels the
#    bytes landed in gvar_initval and were baked into the binary as global initialisers (a
#    clean compile that exited 49 where 0 is right). Fix: PP_PUSH_LEVEL refuses depth 65 with
#    a located error, in BOTH passes. Rows: 64 levels compile and run for every arm in the
#    main source (PP_PASS) and in an included file (PP_IFDEF_PASS); 65 levels are refused at
#    the 65th directive; 9000 levels are refused by the same message. CVE-TBD.
#
# MUTATION LEDGER (6.6.20, mutant = this tree with the named change, built by build/cycc and
# run as CYCC=<mutant>):
#   A1. PP_PUSH_LEVEL's `d >= 64` check deleted (the pre-6.6.20 behaviour)  -> RED: every A
#       refusal row (main + include + deep)
#   real tree                                                              -> GREEN
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
case "$CC" in /*) ;; *) CC="$(pwd)/$CC" ;; esac   # comp() runs from $WORK
[ -x "$CC" ] || { echo "FAIL: pp_table_caps: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: pp_table_caps: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# comp <src>: compile $WORK/<src> from $WORK (relative includes resolve there). Sets $rc; the
# binary is $WORK/out, stderr $WORK/err.
comp() {
    rc=0
    ( cd "$WORK" && "$CC" < "$1" > out 2> err ) || rc=$?
}
# run_ec: the exit code of $WORK/out, or CCFAIL when the compile emitted nothing.
run_ec() {
    [ -s "$WORK/out" ] || { printf 'CCFAIL'; return 0; }
    chmod +x "$WORK/out"
    _e=0; "$WORK/out" > /dev/null 2>&1 || _e=$?
    printf '%s' "$_e"
}
# accept <label> <src> <want-exit>: must compile clean and run to <want-exit>.
accept() {
    NROWS=$((NROWS + 1))
    comp "$2"
    if [ "$rc" != 0 ]; then bad "$1: compile rc $rc, want 0"; head -3 "$WORK/err"; return 0; fi
    _got=$(run_ec)
    [ "$_got" = "$3" ] || bad "$1: exit $_got, want $3"
}
# refuse <label> <src> <stderr-substring>: must fail (rc 1) and say <stderr-substring>.
refuse() {
    NROWS=$((NROWS + 1))
    comp "$2"
    [ "$rc" = 1 ] || { bad "$1: compile rc $rc, want 1"; return 0; }
    grep -qF -- "$3" "$WORK/err" || { bad "$1: diagnostic missing '$3'"; head -3 "$WORK/err"; }
}

# ── A. #if-family nesting stack ──────────────────────────────────────────────────────────
NEST_MSG='#if/#ifdef/#ifndef/#ifplat nesting exceeds 64 levels'
# nest <file> <levels> <directive>: <levels> nested <directive> lines, as many #endif, nothing
# inside — so the program below them is the same whichever way each arm evaluates.
nest() {
    awk -v n="$2" -v d="$3" 'BEGIN { for (i = 0; i < n; i++) print d; for (i = 0; i < n; i++) print "#endif" }' > "$WORK/$1"
}
for arm in '#ifdef PPCAP_NOPE' '#ifndef PPCAP_NOPE' '#if PPCAP_NOPE == 0' '#ifplat x86'; do
    nest m64.cyr 64 "$arm"
    printf 'var g = 7;\nsyscall(60, g);\n' >> "$WORK/m64.cyr"
    accept "main source, 64 x '$arm'" m64.cyr 7
    nest m65.cyr 65 "$arm"
    printf 'var g = 7;\nsyscall(60, g);\n' >> "$WORK/m65.cyr"
    refuse "main source, 65 x '$arm'" m65.cyr "$NEST_MSG"
    grep -qF "<source>:65:" "$WORK/err" || bad "main source, 65 x '$arm': error not located at the 65th directive"
done
# PP_IFDEF_PASS has no #ifplat arm.
for arm in '#ifdef PPCAP_NOPE' '#ifndef PPCAP_NOPE' '#if PPCAP_NOPE == 0'; do
    nest inc64.cyr 64 "$arm"
    printf 'include "inc64.cyr"\nvar g = 7;\nsyscall(60, g);\n' > "$WORK/i64.cyr"
    accept "included file, 64 x '$arm'" i64.cyr 7
    nest inc65.cyr 65 "$arm"
    printf 'include "inc65.cyr"\nvar g = 7;\nsyscall(60, g);\n' > "$WORK/i65.cyr"
    refuse "included file, 65 x '$arm'" i65.cyr "$NEST_MSG"
    grep -qF "inc65.cyr:65:" "$WORK/err" || bad "included file, 65 x '$arm': error not located at inc65.cyr:65"
done
# Far past the cap: the same refusal, not a downstream symptom of the overrun.
nest deep.cyr 9000 '#ifdef PPCAP_NOPE'
printf 'var g = 7;\nsyscall(60, g);\n' >> "$WORK/deep.cyr"
refuse "main source, 9000 levels" deep.cyr "$NEST_MSG"

if [ "$NFAIL" != 0 ]; then
    echo "FAIL: pp_table_caps: $NFAIL failure(s) across $NROWS rows"
    exit 1
fi
echo "PASS: pp_table_caps: $NROWS rows — #if-family nesting refused past 64 levels in both passes (6.6.20)"
