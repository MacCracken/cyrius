#!/bin/sh
# closure_capture_name_write_named.sh — 6.7.11 (issues/archived/2026-10-08-struct-operator-results.md #6)
#
# A WRITE TO A CAPTURED NAME IN A CLOSURE NAMES THE CAPTURE. A closure captures by value, and a captured
# NAME is not an lvalue in its body (guide § Compound assignment): `x += d`, `x = x + d`, a classic-`for`
# init or step and `a, x = f()` are refused. The refusal said `undefined variable 'x'` — though `x` is
# defined, captured and readable in the same body (`|d| { return x + d; }` builds). It now says what is
# refused: 'x' is captured by value; a captured name is not assignable in a closure — copy it into a local.
# One reporter (`_asg_cap_name`, parse.cyr) for the statement arm, the for step (both through
# `_asg_undef_report`) and the multi-value assignment (`_masg_resolve`). Diagnostics only.
#
#   W  a write to a captured name: the filed repro verbatim (`x += d`), `x = x + d`, a for init, a for
#      step (`=` and `+=`), `a, x = two()`, `x -= d`, a nested closure writing the fn's local — each
#      refused once, naming the capture, no binary. The fix-it's local is named from the capture
#      (`var x_l = x;`, 6.7.13); W9 / W9b: a capture named `y` (the fix-it read `var y = y;`)
#   U  a name declared nowhere, inside a closure (`y = d`, `y += d`, `a, y = two()`) and after one (a
#      block's local out of scope), still says `undefined variable 'y'`
#   C  a write to a captured struct's FIELD (`h.n += d`, the closure's own copy) and a read of a
#      captured name still build and run
#   G  6.7.14 (issues/archived/2026-10-16-closure-write-to-captured-name-lands-in-same-named-global.md) — the W shapes
#      with a GLOBAL of the captured name: each write arm looked the global up before asking for a capture,
#      so the write compiled and stored into the GLOBAL while the read beside it saw the capture (the
#      filed repro exited 52). Each is refused once, as without the global (`_asg_cap_first`, parse.cyr,
#      asked from `_asg_lvalue_at` and `_masg_resolve` before any global lookup). GC: a closure that sees
#      no enclosing `x` writes the global (legal), and a closure-local `var x` shadowing both writes its own.
#
# MUTATION LEDGER (2026-10-14, a scratch copy of the tree rebuilt with the one change, run as CYCC=<mutant>):
#   M1 `_asg_cap_name` answering 0 (= the tree before)        -> RED W1-W8 (undefined variable)
#   M2 `_masg_resolve` without its `_asg_cap_name` call       -> RED W6 only
#   M3 `_asg_undef_report` without its `_asg_cap_name` call   -> RED W1-W5 W7 W8; W6 green
# 6.7.13 (issues/archived/2026-10-14-captured-name-refusal-fixit-reads-var-y-equals-y.md):
#   M4 the fix-it's fixed `var y = ` (the tree before)        -> RED W1-W9 W9b (10)
# 6.7.14 (issues/archived/2026-10-16-closure-write-to-captured-name-lands-in-same-named-global.md):
#   M5 `_asg_cap_first` answering 0                         -> RED G0-G9 (10: built) + W6 (`undefined variable`)
#   M6 `_masg_resolve` asking after FINDVAR (6.7.11's order)  -> RED G6 only
#   M7 `_asg_lvalue_at` without its `_asg_cap_first` call     -> RED G0-G5 G7-G9; W1-W9 green (the no-global fallback)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=closure_capture_name_write_named
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
ulimit -c 0 2>/dev/null
fails=0
rows=0
ok()  { echo "  ok   $1"; rows=$((rows + 1)); }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); rows=$((rows + 1)); }
# refused <name> <fragment> <what> <source file>: refused, once, naming <fragment>, no binary
refused() {
    rc=0; timeout 60 "$CC" < "$4" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -qF -- "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    elif [ -s "$T/$1.bin" ]; then bad "$3: refused, but a binary was written"
    else ok "$3: refused once"; fi
}
# exits <name> <want> <what> <source file>
exits() {
    rc=0; timeout 60 "$CC" < "$4" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
src() { printf '%b' "$2" > "$T/$1.cyr"; echo "$T/$1.cyr"; }
I='include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\n'
TWO='fn two(): (i64, i64) { return (1, 2); }\n'
OPEN='fn main(): i64 {\n    var x = 5;\n    var f = '
CLOSE='\n    return callptr(f, 2);\n}\nsyscall(60, main());\n'
CAP="'x' is captured by value; a captured name is not assignable in a closure — copy it into a local (\`var x_l = x;\`)"
CAPY="'y' is captured by value; a captured name is not assignable in a closure — copy it into a local (\`var y_l = y;\`)"
UND="undefined variable 'y'"

echo "W - a write to a captured name names the capture:"
refused w1 "$CAP" "W1: |d| { x += d; .. } (the filed repro, verbatim: undefined variable 'x')" \
    docs/development/issues/repros/2026-10-08-struct-operator-results-6-captured-name-write-undefined.cyr
refused w2 "$CAP" "W2: x = x + d" "$(src w2 "${I}${OPEN}|d| { x = x + d; return x; };${CLOSE}")"
refused w3 "$CAP" "W3: a for init, for (x = 0; ..)" "$(src w3 "${I}${OPEN}|d| { var i = 0; for (x = 0; i < d; i = i + 1) { } return d; };${CLOSE}")"
refused w4 "$CAP" "W4: a for step, for (..; x = x + 1)" "$(src w4 "${I}${OPEN}|d| { for (var i = 0; i < d; x = x + 1) { i = i + 1; } return d; };${CLOSE}")"
refused w5 "$CAP" "W5: a compound for step, for (..; x += 1)" "$(src w5 "${I}${OPEN}|d| { for (var i = 0; i < d; x += 1) { i = i + 1; } return d; };${CLOSE}")"
refused w6 "$CAP" "W6: a, x = two()" "$(src w6 "${I}${TWO}${OPEN}|d| { var a = 0; a, x = two(); return a + d; };${CLOSE}")"
refused w7 "$CAP" "W7: x -= d" "$(src w7 "${I}${OPEN}|d| { x -= d; return x; };${CLOSE}")"
refused w8 "$CAP" "W8: a nested closure writing the fn's x" "$(src w8 "${I}${OPEN}|d| { var g = |e| { x = e; return e; }; return callptr(g, d); };${CLOSE}")"
# W9 (6.7.13): issues/archived/2026-10-14-captured-name-refusal-fixit-reads-var-y-equals-y.md verbatim — a capture
# named `y`. The fix-it named its local `y` always, so it read `var y = y;`: now `var y_l = y;`.
refused w9 "$CAPY" "W9: a capture named y (the filed repro, verbatim: the fix-it read \`var y = y;\`)" \
    docs/development/issues/repros/2026-10-14-captured-name-refusal-fixit-reads-var-y-equals-y.cyr
if grep -qF 'var y = y;' "$T/w9.err"; then bad "W9b: the fix-it still reads \`var y = y;\`"; else ok "W9b: the fix-it is not \`var y = y;\`"; fi

echo "U - a name declared nowhere is still undefined:"
refused u1 "$UND" "U1: y = d in a closure" "$(src u1 "${I}${OPEN}|d| { y = d; return x; };${CLOSE}")"
refused u2 "$UND" "U2: y += d in a closure" "$(src u2 "${I}${OPEN}|d| { y += d; return x; };${CLOSE}")"
refused u3 "$UND" "U3: a, y = two() in a closure" "$(src u3 "${I}${TWO}${OPEN}|d| { var a = 0; a, y = two(); return a + d; };${CLOSE}")"
refused u4 "undefined variable 'x'" "U4: a block's x written after the closure that captured it" "$(src u4 "${I}fn main(): i64 {\n    var f = 0;\n    if (1 == 1) { var x = 5; f = |d| { return x + d; }; }\n    x = 3;\n    return callptr(f, 2);\n}\nsyscall(60, main());\n")"

echo "C - a captured struct's field and a read still build:"
exits c1 7 "C1: h.n += d on a captured struct (the closure's copy)" "$(src c1 "${I}struct H { n; }\nfn main(): i64 {\n    var h = H { 5 };\n    var f = |d| { h.n += d; return h.n; };\n    return callptr(f, 2);\n}\nsyscall(60, main());\n")"
exits c2 7 "C2: |d| { return x + d; }" "$(src c2 "${I}${OPEN}|d| { return x + d; };${CLOSE}")"

echo "G - a same-named GLOBAL does not take the write (6.7.14):"
GX='var x = 100;\n'
GEND='\n    return callptr(f, 2);\n}\nfn g(): i64 { return x; }\nvar r = main();\nsyscall(60, r * 10 + (g() - 100));\n'
refused g0 "$CAPY" "G0: the filed repro, verbatim (y += d beside a global y: built, exit 52)" \
    docs/development/issues/repros/2026-10-16-closure-write-to-captured-name-lands-in-same-named-global.cyr
refused g1 "$CAP" "G1: x += d" "$(src g1 "${I}${GX}${OPEN}|d| { x += d; return x; };${GEND}")"
refused g2 "$CAP" "G2: x = x + d (built, exit 213)" "$(src g2 "${I}${GX}${OPEN}|d| { x = x + d; return x; };${GEND}")"
refused g3 "$CAP" "G3: a for init, for (x = 0; ..)" "$(src g3 "${I}${GX}${OPEN}|d| { var i = 0; for (x = 0; i < d; i = i + 1) { } return d; };${GEND}")"
refused g4 "$CAP" "G4: a for step, for (..; x = x + 1)" "$(src g4 "${I}${GX}${OPEN}|d| { for (var i = 0; i < d; x = x + 1) { i = i + 1; } return d; };${GEND}")"
refused g5 "$CAP" "G5: a compound for step, for (..; x += 1)" "$(src g5 "${I}${GX}${OPEN}|d| { for (var i = 0; i < d; x += 1) { i = i + 1; } return d; };${GEND}")"
refused g6 "$CAP" "G6: a, x = two()" "$(src g6 "${I}${GX}${TWO}${OPEN}|d| { var a = 0; a, x = two(); return a + d; };${GEND}")"
refused g7 "$CAP" "G7: x -= d" "$(src g7 "${I}${GX}${OPEN}|d| { x -= d; return x; };${GEND}")"
refused g8 "$CAP" "G8: a nested closure writing the fn's x" "$(src g8 "${I}${GX}${OPEN}|d| { var h = |e| { x = e; return e; }; return callptr(h, d); };${GEND}")"
refused g9 "$CAP" "G9: x = 9 (built, exit 215)" "$(src g9 "${I}${GX}${OPEN}|d| { x = 9; return x; };${GEND}")"
# GC1: no enclosing x — the closure's x IS the global: 102 + 5 returned, the global 100 -> 102: 107 + 2.
exits gc1 109 "GC1: a closure that sees no enclosing x writes the global x" "$(src gc1 "${I}${GX}fn main(): i64 {\n    var k = 5;\n    var f = |d| { x += d; return x + k; };\n    return callptr(f, 2);\n}\nfn g(): i64 { return x; }\nvar r = main();\nsyscall(60, r + (g() - 100));\n")"
# GC2: the closure's own x shadows the capture and the global: 1 + 2 returned, the global untouched: 30.
exits gc2 30 "GC2: a closure-local var x shadowing both writes its local" "$(src gc2 "${I}${GX}${OPEN}|d| { var x = 1; x += d; return x; };${GEND}")"

# Floor: 10 W + 4 U + 2 C + 10 G + 2 GC rows. A gate that ran fewer is broken, not green.
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$rows" -lt 28 ]; then echo "FAIL: $G — only $rows rows ran (floor 28)"; exit 1; fi
echo "PASS: $G ($rows rows) — a write to a captured name in a closure names the capture; an undefined name stays undefined"
exit 0
