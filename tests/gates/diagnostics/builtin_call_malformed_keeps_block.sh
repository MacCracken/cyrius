#!/bin/sh
# tests/gates/diagnostics/builtin_call_malformed_keeps_block.sh — 6.7.17
#
# A BUILTIN'S OR AN IDENTIFIER INTRINSIC'S MALFORMED ARGUMENT LIST IS ONE ERROR: THE BLOCK AROUND IT STILL CLOSES.
#
# THE DEFECT (measured 6.7.17 at the fea lane's base, 0d291492b; x86_64, aarch64, cx and PE alike — the shared
# frontend). Each builtin's lowering in PARSE_FACTOR (src/frontend/parse_expr.cyr) checked its `(` and `,` with
# `if (PEEKT(S) != t) { ERR_EXPECT(S, t); } STI(S, GTI(S) + 1);`, stepping the token found whatever it was (6.7.14 had
# made most `)` checks `_expect_step`). A malformed call at the end of a block took the statement's `;` and the block's
# `}`: `var y = load8;` (or `f64_sqrt;`, `syscall;`, `callptr;`, `rethi;`, `store8(p;`, `ret2(p;`, `iv_add(p, p;`, ..)
# as a fn's last statement made the NEXT fn "defined inside fn 'main'" and the file end "expected '}', got end of file",
# and that fn's own error was never reported. Which shapes cascaded depended on how many tokens each arm stepped.
#
# THE FIX. Every `(`, `,` and `)` check in those arms is `_expect_step` (a miss reported, a recovery point — `;`, `}`, a
# statement keyword, EOF — never stepped); the iv width literal steps only a non-recovery token; `sizeof` reads no
# type when its `(` is missing.
#
# THE SAME STEP IN THE ASSIGNMENT ARM (met with these rows). A bare name as a statement — `p;`, `zq;` — is the
# assignment arm's "expected '='"; the arm then stepped the `;`, its value read the block's `}`, and the next fn was
# "defined inside fn 'main'" (`zq;` added "undefined variable" at the next line). Now `_asg_eq_step` (src/frontend/
# parse.cyr): a missing `=` is one error and the statement ends in sync — nothing read as a value, the rest stepped to
# its `;` with its brackets balanced (`_stmt_rest_skip`) — so the next statement is parsed with its own errors (`p 5;`
# lost the next statement's error to the resync).
#
#   X   the matrix: every builtin TOKNAME_BUILTIN names (less its keywords) and f64_sqrt / callptr / sizeof / mulh64, in
#       four shapes — `var y = NAME;`, `var y = NAME(A;`, `var y = NAME(A, A;` and the statement `NAME;` — as a fn's
#       last statement, then `fn g(): i64 { return zz; }`: exactly two error lines, the second g's "undefined variable
#       'zz'", nothing "defined inside" and no "end of file"
#   V   verbatim: the measured repros' exact lines
#   N   a bare name as a statement (`p;`, `zq;`, `p 5;`, `p { 5 };`, `p` before the `}` or the next line's `return`): its
#       one error, then the next statement's own (`zq2`) and g's
# Every row on the x86_64, aarch64, cx and PE-cross compilers built from this tree: rc 1, no binary.
#
# MUTATION LEDGER (2026-10-22, fea FA2; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from that copy with CYCC= it):
#   the lane before it (6620050a1's src)                    -> RED 668 of 1224 X row-legs + V load8 store8 mulh64
#   the `,` checks back to the stepping form                -> RED 516 X row-legs + V store8 ret2
#   the one-line f64 arms' `(` back to the stepping form    -> RED 72 X row-legs (18 builtins x 4 legs)
#   `sizeof` reading a type with its `(` missing            -> RED X sizeof.a + V sizeof on every leg (8)
#   the assignment arm's `=` back to the stepping form      -> RED N n_local n_undef n_next n_for n_junk on every leg (20)
#   `_asg_eq_step` without its `_refuse_in_sync`            -> RED N n_next n_for n_junk n_brk on every leg (16: zq2
#                                                              lost to the resync; the for header misread)
#   `_stmt_rest_skip` with no bracket balance               -> RED N n_brk on every leg (4)
#
# Exit 77 = could not run (no compiler); never 0 for that.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: builtin_call_malformed_keeps_block — $CC not built"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: builtin_call_malformed_keeps_block: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 77; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || { echo "FAIL: builtin_call_malformed_keeps_block — cannot cd to $ROOT"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then :
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
LEGS="x86"
if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"; LEGS="$LEGS a64"
else echo "  FAIL: aarch64 — src/main_aarch64.cyr did not build"; fails=$((fails + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ]; then chmod +x "$T/cc_cx"; LEGS="$LEGS cx"
else echo "  FAIL: cx — src/main_cx.cyr did not build"; fails=$((fails + 1)); fi
if "$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null && [ -s "$T/cc_win" ]; then chmod +x "$T/cc_win"; LEGS="$LEGS win"
else echo "  FAIL: win — src/main_win.cyr (the PE cross compiler) did not build"; fails=$((fails + 1)); fi
# comp <leg> <src> <out>: the rc in CRC, the error lines (|-joined) in CERR
comp() {
    CRC=0
    case "$1" in
        x86) timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64) timeout 60 "$T/cc_a64" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)  timeout 60 "$T/cc_cx" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        win) timeout 60 "$T/cc_win" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
    CERR=$(grep -E '^(error|warning)' "$3.err" | tr '\n' '|')
}
ZE="error:<source>:6:24: undefined variable 'zz' (missing include or enum?)|"
NAMES=$( (sed -n '/^fn TOKNAME_BUILTIN/,/^}/p' src/common/util.cyr | sed -n 's/.*return "\([a-z0-9_]*\)".*/\1/p'; \
    echo f64_sqrt; echo callptr; echo sizeof; echo mulh64) | grep -vxE 'union|u128|defer|secret|async|await')
echo "X — every builtin's malformed call as a fn's last statement is one error; the next fn is its own ($LEGS):"
nx=0; xbad=0
for nm in $NAMES; do
    a=p
    [ "$nm" = sizeof ] && a=i64
    for sh in a b c d; do
        case $sh in
            a) e="var y = $nm;" ;;
            b) e="var y = $nm($a;" ;;
            c) e="var y = $nm($a, $a;" ;;
            d) e="$nm;" ;;
        esac
        printf 'var gb: i64 = 7;\nfn main(): i64 {\n    var p = &gb;\n    %s\n}\nfn g(): i64 { return zz; }\nsyscall(60, main());\n' "$e" > "$T/x.cyr"
        for leg in $LEGS; do
            nx=$((nx + 1))
            comp "$leg" "$T/x.cyr" "$T/x.$leg"
            n=$(printf '%s' "$CERR" | tr '|' '\n' | grep -c .)
            last=$(printf '%s' "$CERR" | tr '|' '\n' | tail -1)
            if [ "$CRC" != 1 ] || [ "$n" != 2 ] || [ "$last|" != "$ZE" ] || [ -s "$T/x.$leg" ]; then
                echo "  FAIL: X $nm.$sh $leg ($e) — rc $CRC, got $CERR"; fails=$((fails + 1)); xbad=$((xbad + 1))
            fi
        done
    done
done
echo "  X: $nx row-legs, $xbad wrong"
echo "V — the measured repros, verbatim, on every leg ($LEGS):"
nv=0
# vrow <name> <statement> <want error lines>
vrow() {
    printf 'var gb: i64 = 7;\nfn main(): i64 {\n    var p = &gb;\n    %s\n}\nfn g(): i64 { return zz; }\nsyscall(60, main());\n' "$2" > "$T/$1.cyr"
    for leg in $LEGS; do
        nv=$((nv + 1))
        comp "$leg" "$T/$1.cyr" "$T/$1.$leg"
        check "V $1 $leg: exits 1" 1 "$CRC"
        check "V $1 $leg: error lines" "$3" "$CERR"
    done
}
vrow v_load8   'var y = load8;'      "error:<source>:4:18: expected '(', got ';'|$ZE"
vrow v_syscall 'syscall;'            "error:<source>:4:12: expected '(', got ';'|$ZE"
vrow v_sizeof  'var y = sizeof;'     "error:<source>:4:19: expected '(', got ';'|$ZE"
vrow v_store8  'var y = store8(p;'   "error:<source>:4:21: expected ',', got ';'|$ZE"
vrow v_ret2    'var y = ret2;'       "error:<source>:4:17: expected '(', got ';'|$ZE"
vrow v_ivadd   'var y = iv_add(p, p;' "error:<source>:4:24: expected ',', got ';'|$ZE"
vrow v_callptr 'callptr;'            "error:<source>:4:12: expected '(', got ';'|$ZE"
vrow v_mulh64  'var y = mulh64(p;'   "error:<source>:4:21: expected ',', got ';'|$ZE"
echo "N — a bare name as a statement is its one error; the next statement is its own, the block still closes ($LEGS):"
# The assignment arm stepped the token after a missing `=`: `p;` took the `;`, the value then read the `}` and the next
# fn was "defined inside fn 'main'" (`zq;` added "undefined variable" at the next line's first token). A missing `=` at
# a recovery point now ends the statement in sync: one error, the next statement (`zq2`) and fn (g) report their own.
vrow n_local  'p;'      "error:<source>:4:6: expected '=', got ';'|$ZE"
vrow n_undef  'zq;'     "error:<source>:4:7: expected '=', got ';'|$ZE"
vrow n_brace  'p'       "error:<source>:5:1: expected '=', got '}'|$ZE"
vrow n_next   'p; zq2 = 1;' "error:<source>:4:6: expected '=', got ';'|error:<source>:4:15: undefined variable 'zq2'|$ZE"
vrow n_kw     'p
    return zq2;' "error:<source>:5:5: expected '=', got return|error:<source>:5:15: undefined variable 'zq2' (missing include or enum?)|error:<source>:7:24: undefined variable 'zz' (missing include or enum?)|"
vrow n_for    'for (p; p < 3; p = p + 1) { }' "error:<source>:4:11: expected '=', got ';'|$ZE"
vrow n_junk   'p 5; zq2 = 1;' "error:<source>:4:7: expected '=', got number 5|error:<source>:4:17: undefined variable 'zq2'|$ZE"
vrow n_brk    'p { 5 }; zq2 = 1;' "error:<source>:4:7: expected '=', got '{'|error:<source>:4:21: undefined variable 'zq2'|$ZE"
# The floor: 77 names x 4 shapes on four legs; 8 V + 8 N rows on four legs.
X_FLOOR=1232
V_FLOOR=64
[ "$nx" -ge "$X_FLOOR" ] || { echo "  FAIL: X ran $nx row-legs (floor $X_FLOOR) — names or legs were lost"; fails=$((fails + 1)); }
[ "$nv" -ge "$V_FLOOR" ] || { echo "  FAIL: V ran $nv row-legs (floor $V_FLOOR)"; fails=$((fails + 1)); }
if [ "$fails" = 0 ]; then
    echo "PASS: builtin_call_malformed_keeps_block — $nx + $nv row-legs on $LEGS: a malformed builtin call is one error, the block still closes"
    exit 0
fi
echo "FAIL: builtin_call_malformed_keeps_block — $fails assertion(s) failed"
exit 1
