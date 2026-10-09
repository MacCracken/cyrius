#!/bin/sh
# tests/gates/frontend/tuple_checked.sh — 6.7.7 (B4)
#
# TUPLES AS VALUES. The user's decision (2026-10-08): `(a, b)` builds a value laid out as an anonymous
# struct of 8-byte slots; `t.0` / `t.1` read and write it (`OP=` included); `(i64, f64)` is a type
# wherever a struct type goes; `var t: (i64, i64) = f();` captures every value of a multi-value call
# and `a, b = f();` re-assigns existing variables; `var x = f();` keeps its first-value meaning. A
# shape the decision leaves open is refused by name, never given a default meaning.
#
#   L  the lexer: `.` then a digit after an IDENT, `)` or `]` is a selector (IDENT DOT IDENT"0"), and
#      every other `.digit` lexes exactly as before — ranges, floats, `t. 0` with a space
#
# MUTATION LEDGER (2026-10-09; each a one-edit scratch COPY of the tree, its compiler rebuilt from the
# mutated src, then this gate run with CYCC= the mutant):
#   M1  `_lex_dot` without the previous-token guard (every `.digit` a selector) -> L1 (a range's
#       `..10` lexes DOT IDENT"10": "undefined variable '10'"). L2's shapes never reach the guard
#       (`1.5` is one LEXNUM token; `1.0.5`'s refusal names the `.` either way). The same mutant
#       compiles 8 tree files differently from the base compiler (ranges in crossos tcyrs).
#   M1b the guard without `)` (11)                                               -> L3c
# THE EVIDENCE BEYOND THESE ROWS (T1, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in the tree
# (1051 files, default and CYRIUS_DCE=1) compiles byte-identical — stdout, stderr and exit code —
# with the T1 compiler and the base build/cycc (e44470b7); the aarch64, cx and PE
# (CYRIUS_TARGET_WIN=1) compilers likewise over tests/tcyr/crossos/. No program that compiled before
# lexes differently.
# Defensive, no killing row (named): `_tok_start` set to the digit before LEXID — today every
# diagnostic at a selector points at the token AFTER it, so the IDENT's own offset is not observed;
# the guard's `]` (29) — no valid program today follows a subscript with `.field`, so `a[1].0` is
# "expected ';', got '.'" with or without it.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: tuple_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: tuple_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
P='struct P { a; b; }\n'

# ── L: the lexer ─────────────────────────────────────────────────────────────────────────────────
# L1: every range whose upper bound is a digit run — after a number, an IDENT, `)` and `]`. Its second
# `.` follows a DOT token, so the selector guard never fires on it.
exits l01 250 "L1: ranges \`0..10\`, \`a..5\`, \`a..hi\`, \`g(4)..6\`, \`arr[0]..5\` intact" 'fn g(x): i64 { return x; }\nfn f(c): i64 {\n    var s = 0;\n    var a = 2;\n    var hi = 6;\n    var arr: i64[2];\n    arr[0] = 3;\n    for i in 0..10 { s = s + 1; }\n    for i in a..5 { s = s + 10; }\n    for i in a..hi { s = s + 20; }\n    for i in g(4)..6 { s = s + 40; }\n    for i in arr[0]..5 { s = s + 25; }\n    return s;\n}\nsyscall(60, f(1));\n'
exits l02 3 "L2: \`1.5\` / \`0.25\` are still float literals (their binary64 bits)" 'var x = 1.5;\nvar y = 0.25;\nsyscall(60, (x == 0x3FF8000000000000) + (y == 0x3FD0000000000000) * 2);\n'
refused l02b "expected ';', got '.'" "L2b: \`1.0.5\` is still a float then a stray \`.\`" 'fn f(): i64 { var y = 1.0.5; return 0; }\nsyscall(60, f());\n'
refused l03 "unknown field '0' on struct 'P'" "L3: \`p.0\` on a named struct is a field selector" "${P}fn f(): i64 { var p: P; p.a = 1; return p.0; }\nsyscall(60, f());\n"
refused l03b "unknown field '0x1' on struct 'P'" "L3b: \`p.0x1\` is ONE selector (the whole alnum run), not a hex number" "${P}fn f(): i64 { var p: P; return p.0x1; }\nsyscall(60, f());\n"
refused l03c "unknown field '0' on struct 'P'" "L3c: after \`)\` too — \`mk().0\` (was \"expected ';', got '.'\")" "${P}fn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\nfn f(): i64 { return mk().0; }\nsyscall(60, f());\n"
refused l04 "unknown field '0' on struct 'P'" "L4: \`p.0.1\` is two selectors (the error names '0', not a float 0.1)" "${P}fn f(): i64 { var p: P; return p.0.1; }\nsyscall(60, f());\n"
# L4b: `--syntax-only` (what `cyrius lint` runs) reads `p.0.1` as a selector chain, exactly as `p.a.b`.
printf 'fn f(p): i64 { return p.0.1 + p.a.b; }\nsyscall(60, f(0));\n' > "$T/l04b.cyr"
rc=0; "$CC" --syntax-only < "$T/l04b.cyr" > /dev/null 2> "$T/l04b.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/l04b.err"; then ok "L4b: --syntax-only reads \`p.0.1\` as a chain, as \`p.a.b\`"
else bad "L4b: --syntax-only rc $rc: $(grep '^error' "$T/l04b.err" | head -1)"; fi
refused l05 "expected identifier, got number 0" "L5: \`p. 0\` (a space) is still a number, not a selector" "${P}fn f(): i64 { var p: P; return p. 0; }\nsyscall(60, f());\n"

if [ "$fails" -ne 0 ]; then echo "FAIL: tuple_checked — $fails row(s) red"; exit 1; fi
echo "PASS: tuple_checked — tuples: the lexer (L)"
