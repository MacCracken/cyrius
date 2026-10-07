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
# B. The function-like macro table (S+0x192000.., 16 macros). The 17th function-like #define
#    was silently DISCARDED (stored only inside `if (msi < 16)`, no else): a same-name fn was
#    called instead (exit 99 where 10 is right), or the use failed as a misleading "undefined
#    function". A redefinition took its own slot and was never used (first match wins and
#    expansion runs after every definition is in), and a function-like #define in an INCLUDED
#    file became a plain flag — never a macro. Fix: PP_MACRO_SLOT refuses the 17th and a
#    redefinition by name; PP_DEFINE_INCLUDED refuses the included form by name. Rows: 16
#    macros expand; the 17th is refused by name with and without a same-name fn; a
#    redefinition is refused; an included function-like #define is refused, located in the
#    included file; one inside a false #ifdef in an included file is NOT refused, and an
#    included object-like #define still works.
#
# MUTATION LEDGER (6.6.20, mutant = this tree with the named change, built by build/cycc and
# run as CYCC=<mutant>):
#   A1. PP_PUSH_LEVEL's `d >= 64` check deleted (the pre-6.6.20 behaviour)  -> RED: every A
#       refusal row (main + include + deep)
#   B1. PP_MACRO_SLOT's `_pp_macro_count >= 16` refusal deleted            -> RED: B 17th rows
#   B2. PP_MACRO_SLOT's redefinition refusal deleted                       -> RED: B redefinition
#   B3. PP_IFDEF_PASS calls PP_DEFINE again, not PP_DEFINE_INCLUDED         -> RED: B included row
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

# ── B. function-like macro table ─────────────────────────────────────────────────────────
# fill <n>: n distinct function-like macros M1..Mn.
fill() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "#define M%d(x) (x + %d)\n", i, i }'; }
{ fill 15; echo '#define SIXTEENTH(x) (x * 2)'; echo 'var r = SIXTEENTH(5);'; echo 'syscall(60, r);'; } > "$WORK/mac16.cyr"
accept "16 function-like macros, the 16th expands" mac16.cyr 10
{ fill 16; echo '#define SEVENTEENTH(x) (x * 2)'; echo 'fn SEVENTEENTH(x) { return 99; }'; echo 'var r = SEVENTEENTH(5);'; echo 'syscall(60, r);'; } > "$WORK/mac17.cyr"
refuse "17th function-like macro beside a same-name fn" mac17.cyr "<source>:17:1: too many function-like #define macros (max 16): 'SEVENTEENTH'"
{ fill 16; echo '#define SEVENTEENTH(x) (x * 2)'; echo 'var r = SEVENTEENTH(5);'; echo 'syscall(60, r);'; } > "$WORK/mac17u.cyr"
refuse "17th function-like macro, no fn" mac17u.cyr "too many function-like #define macros (max 16): 'SEVENTEENTH'"
printf '#define A(x) (x + 1)\n#define A(x) (x + 2)\nvar r = A(5);\nsyscall(60, r);\n' > "$WORK/redef.cyr"
refuse "function-like macro redefined" redef.cyr "<source>:2:1: function-like macro 'A' is already defined"
printf '#define INC_DBL(x) (x * 2)\n' > "$WORK/incdbl.cyr"
printf 'include "incdbl.cyr"\nfn INC_DBL(x) { return 77; }\nvar r = INC_DBL(5);\nsyscall(60, r);\n' > "$WORK/incfn.cyr"
refuse "function-like macro in an included file" incfn.cyr "incdbl.cyr:1:1: function-like macro 'INC_DBL' is defined in an included file"
printf '#ifdef PPCAP_NOPE\n#define INC_SKIP(x) (x * 2)\n#endif\n#define INC_FLAG 3\n#if INC_FLAG == 3\nvar g = 5;\n#endif\n' > "$WORK/incskip.cyr"
printf 'include "incskip.cyr"\nsyscall(60, g);\n' > "$WORK/incskipm.cyr"
accept "included file: skipped function-like #define, live object-like #define" incskipm.cyr 5

if [ "$NFAIL" != 0 ]; then
    echo "FAIL: pp_table_caps: $NFAIL failure(s) across $NROWS rows"
    exit 1
fi
echo "PASS: pp_table_caps: $NROWS rows — #if-family nesting refused past 64 levels in both passes; function-like macro table refuses the 17th, a redefinition and an included definition by name (6.6.20)"
