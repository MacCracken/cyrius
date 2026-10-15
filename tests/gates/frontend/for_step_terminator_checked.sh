#!/bin/sh
# tests/gates/frontend/for_step_terminator_checked.sh — 6.7.8 (C2-2b)
#
# EVERY CLASSIC-FOR STEP ENDS AT ITS `)`. The step of `for (init; cond; step)` is skipped (by paren
# depth) before the body and replayed after it (`_for_step_replay`, parse_ctrl.cyr). The field and
# `*p` arms (6.7.5) and the whole-aggregate helpers (6.6.20) end at the `)` and report anything else;
# the scalar arm (`_for_step_assign`) and the subscript arm (`_arr_sub_assign`) stopped after the
# value and never looked, so trailing junk up to the `)` was silently ignored (6.7.7 and before):
# `for (i = 0; i < 3; i += 1 2)` built and ran 3 iterations, and with `a`, `b` 24-byte structs the
# step `a = b 2` also defeated the whole-struct copy (it needs the `)` right after `b`) and stored
# ONE word — `a` became {4, 2, 3}, not {4, 5, 6}. Each arm now checks its `)` where its value ends,
# as the statement checks its `;`. (issues/2026-10-08-for-step-variable-subscript-close-paren-unchecked.md)
#
#   J  junk before the `)` refused once, "expected ')'": J1-J6 the issue's six repros verbatim
#      (local `i += 1 2`, a global, `i = i + 1 2`, `a[0] += 1 2`, `i += 1 ; junk`, the struct
#      `a = b 2`), J7-J16 the rest of the arms (`a[0] = n 2`, a variable index `a[j] += 1 2`, a
#      global `G = G + 1 2`, a global struct `G = B 2`, a struct call `a = mk(7) 2`, a wrapped
#      `a = (b) 2`, a struct field source `a = h.v 2`, an f64 `x += 0.25 2`, a top-level step,
#      a name as the junk)
#   F  the 6.7.5 arms beside them, unchanged: a field step and a `*p` step with junk, the 6.7.7
#      multi-value step `x, y = f2() 2` (its own refusal)
#   L  the lvalue refusal (a const, an enum constant) is the step's ONE error: no `)` check after it
#   U  6.7.9: a step whose destination is neither a local nor a global is the statement's ONE error,
#      "undefined variable 'x'" — it compiled and stored nothing, so the loop never advanced: U1 the
#      issue's repro verbatim (`j = i + 1`), `zz = 1`, `yy += 1`, a top-level step, a fn's name, a
#      captured name in a closure's step (the guide: a captured NAME is not an lvalue there)
#      (issues/2026-10-10-for-step-undeclared-name-compiles-silently.md)
#   X  `--syntax-only` (what `cyrius lint` runs): a step on a global / struct the file cannot see
#      stays silent (no invented "expected ')'", no "undefined variable", `+=` and `=`); junk is
#      still reported there
#   V  ANTI-VACUOUS: every step arm still runs its step — scalar local / global `=` and `OP=`, a
#      subscript at a constant / variable index (local and global), an f64, inner parentheses, call
#      values, a field, `*p`, a multi-value call, and the aggregate helpers that consume the `)`
#      themselves (a struct copy, a struct call, a wrapped source, a global struct, a tuple
#      literal), a top-level step, and a step on a global declared AFTER its fn (6.7.9: still
#      found, still stored) — on x86 (plain, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1),
#      aarch64 (qemu), cx (cxvm) and PE (wine); A: tests/tcyr/crossos/for_step_struct_assign.tcyr
#      (every aggregate helper's step, 6.6.20) builds and passes
#   P  fork parity: J1-J6 and U1 refused the same by the aarch64 and cx compilers built from this tree
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-10):
#   M2a `_for_step_replay` without its `)` check after `_arr_sub_assign`
#                                                        -> RED J4 J7 J8 P(J4) (each BUILDS)
#   M2b `_for_step_assign` without its `)` check at the scalar store's end
#                                                        -> RED J1-J3 J5 J6 J9-J16 X3 P(J1-J3 J5 J6)
#   M2c the check also after an aggregate helper that returned 1 (the `)` already consumed)
#                                                        -> RED V1-V7 on every leg ("expected ')',
#                                                           got '{'" — struct_copy, struct_call,
#                                                           struct_paren, struct_global, tuple_step
#                                                           each, measured one at a time) and A
#   the 6.7.7 parse_ctrl.cyr (the pre-fix compiler)      -> RED J1-J16 X3 P (29 rows)
# 2026-10-11 (6.7.9):
#   M3a `_for_step_assign` without the `else` after FINDVAR (the step stores nothing, silently)
#                                                        -> RED U1-U6 P(U1) (each BUILDS)
#   M3b the report without its `_syntax_only == 0` guard -> RED X1 X4 ("undefined variable")
#   the pre-fix compiler (crit bite 16's tree)           -> RED U1-U6 P(U1)
# (A check after the lvalue refusal is swallowed by the parse's panic flag — the L rows pin one
# error line, which holds either way: measured, no mutation of that site is observable.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=for_step_terminator_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# refused <name> <fragment> <what> <body> [compiler]: compile fails with exactly one error line holding the fragment
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    _c=${5:-$CC}
    rc=0; timeout 60 "$_c" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want the refusal \"$2\""
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want exactly 1: $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|')"
    elif grep '^error' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"; fi
}
# synonly <name> <what> <body>: --syntax-only exits 0 with no error line
synonly() {
    printf '%b' "$3" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ] || grep -q '^error' "$T/$1.err"; then bad "$2: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$2: silent"; fi
}
# synrefused <name> <fragment> <what> <body>: --syntax-only reports the fragment
synrefused() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ] && grep '^error' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: rc $rc, want \"$2\": $(grep '^error' "$T/$1.err" | head -1)"; fi
}

# ── J: junk before the step's `)` ─────────────────────────────────────────────────────────────
E='var r = main();\nsyscall(60, r);\n'
X2="expected ')', got number 2"
# J1-J6: the issue's six repros, verbatim.
J1='fn main() {\n    var s = 0;\n    var i = 0;\n    for (i = 0; i < 3; i += 1 2) { s = s + 1; }\n    return s;\n}\n'"$E"
J2='var G = 0;\nfn main() {\n    var s = 0;\n    for (G = 0; G < 3; G += 1 2) { s = s + 1; }\n    return s;\n}\n'"$E"
J3='fn main() {\n    var s = 0;\n    var i = 0;\n    for (i = 0; i < 3; i = i + 1 2) { s = s + 1; }\n    return s;\n}\n'"$E"
J4='fn main() {\n    var s = 0;\n    var a: i64[2];\n    for (a[0] = 0; a[0] < 3; a[0] += 1 2) { s = s + 1; }\n    return s;\n}\n'"$E"
J5='fn main() {\n    var s = 0;\n    var i = 0;\n    for (i = 0; i < 3; i += 1 ; junk) { s = s + 1; }\n    return s;\n}\n'"$E"
J6='struct P3 { x; y; z; }\nfn main() {\n    var a = P3 { 1, 2, 3 };\n    var b = P3 { 4, 5, 6 };\n    var n = 0;\n    for (n = 0; n < 1; a = b 2) { n = n + 1; }\n    return a.y;\n}\n'"$E"
refused j01 "$X2" "J1: i += 1 2 (built, 3 iterations)" "$J1"
refused j02 "$X2" "J2: a global, G += 1 2" "$J2"
refused j03 "$X2" "J3: i = i + 1 2" "$J3"
refused j04 "$X2" "J4: a[0] += 1 2 (the subscript arm)" "$J4"
refused j05 "expected ')', got ';'" "J5: i += 1 ; junk" "$J5"
refused j06 "$X2" "J6: a = b 2 on a 24-byte struct (built, stored one word: a.y stayed 2)" "$J6"
SP3='struct P3 { x; y; z; }\nfn mk(k): P3 { var r = P3 { k, k + 1, k + 2 }; return r; }\n'
LOOP='    var n = 0;\n    for (n = 0; n < 1; '
refused j07 "$X2" "J7: a[0] = n 2 (subscript, plain =)" 'fn main() {\n    var a: i64[2];\n    var n = 0;\n    for (n = 0; n < 3; a[0] = n 2) { n = n + 1; }\n    return n;\n}\n'"$E"
refused j08 "$X2" "J8: a[j] += 1 2 (a variable index)" 'fn main() {\n    var a: u8[4];\n    var j = 1;\n    var n = 0;\n    for (n = 0; n < 3; a[j] += 1 2) { n = n + 1; }\n    return a[1];\n}\n'"$E"
refused j09 "$X2" "J9: a global, G = G + 1 2" 'var G = 0;\nfn main() {\n    var s = 0;\n    for (G = 0; G < 3; G = G + 1 2) { s = s + 1; }\n    return s;\n}\n'"$E"
refused j10 "$X2" "J10: a global struct, G = B 2" "${SP3}var G = P3 { 1, 2, 3 };\nvar B = P3 { 4, 5, 6 };\nfn main() {\n${LOOP}G = B 2) { n = n + 1; }\n    return G.y;\n}\n$E"
refused j11 "$X2" "J11: a struct call, a = mk(7) 2 (built, one word)" "${SP3}fn main() {\n    var a = P3 { 1, 2, 3 };\n${LOOP}a = mk(7) 2) { n = n + 1; }\n    return a.y;\n}\n$E"
refused j12 "$X2" "J12: a wrapped source, a = (b) 2" "${SP3}fn main() {\n    var a = P3 { 1, 2, 3 };\n    var b = P3 { 4, 5, 6 };\n${LOOP}a = (b) 2) { n = n + 1; }\n    return a.y;\n}\n$E"
refused j13 "$X2" "J13: a struct field source, a = h.v 2" "${SP3}struct O { k; v: P3; }\nfn main() {\n    var a = P3 { 1, 2, 3 };\n    var h: O;\n    h.v = a;\n${LOOP}a = h.v 2) { n = n + 1; }\n    return a.y;\n}\n$E"
refused j14 "$X2" "J14: an f64, x += 0.25 2" 'fn main() {\n    var x: f64 = 0.0;\n    var n = 0;\n    for (x = 0.0; x < 1.0; x += 0.25 2) { n = n + 1; }\n    return n;\n}\n'"$E"
refused j15 "$X2" "J15: a top-level step, i += 1 2" 'var i = 0;\nvar s = 0;\nfor (i = 0; i < 3; i += 1 2) { s = s + 1; }\nsyscall(60, s);\n'
refused j16 "expected ')', got identifier 'zz'" "J16: a name as the junk, n += 1 zz" 'fn main() {\n    var n = 0;\n    for (n = 0; n < 3; n += 1 zz) { }\n    return n;\n}\n'"$E"

# ── F: the 6.7.5 / 6.7.7 arms beside them ─────────────────────────────────────────────────────
refused f01 "$X2" "F1: a field step, c.n += 1 2 (6.7.5)" 'struct C { n; }\nfn main() {\n    var c = C { 0 };\n    for (c.n = 0; c.n < 3; c.n += 1 2) { }\n    return c.n;\n}\n'"$E"
refused f02 "$X2" "F2: a *p step, *p += 1 2 (6.7.5)" 'fn main() {\n    var v = 0;\n    var p = &v;\n    var n = 0;\n    for (n = 0; n < 3; *p += 1 2) { n = n + 1; }\n    return v;\n}\n'"$E"
refused f03 "multi-value destructure needs a call on the right-hand side" "F3: a multi-value step, x, y = f2() 2 (6.7.7)" 'fn f2(): i64 { return (3, 4); }\nfn main() {\n    var x = 0;\n    var y = 0;\n    var n = 0;\n    for (n = 0; n < 1; x, y = f2() 2) { n = n + 1; }\n    return x + y;\n}\n'"$E"

# ── L: the lvalue refusal is the step's one error ─────────────────────────────────────────────
refused l01 "cannot assign to const 'K'" "L1: a const, K += 2 3" 'const K = 1;\nfn main() {\n    var s = 0;\n    for (s = 0; s < 3; K += 2 3) { s = s + 1; }\n    return s;\n}\n'"$E"
refused l02 "cannot assign to enum constant 'A'" "L2: an enum constant, A = 1 2" 'enum E { A; B; }\nfn main() {\n    var s = 0;\n    for (s = 0; s < 3; A = 1 2) { s = s + 1; }\n    return s;\n}\n'"$E"

# ── U: a destination declared nowhere is the statement's "undefined variable" (6.7.9) ────────
U1=$(cat docs/development/issues/repros/2026-10-10-for-step-undeclared-name-compiles-silently.cyr)
refused u01 "undefined variable 'j'" "U1: the issue's repro, j = i + 1 (built, looped to its guard)" "$U1"
refused u02 "undefined variable 'zz'" "U2: zz = 1" 'fn main() {\n    var n = 0;\n    for (n = 0; n < 3; zz = 1) { n = n + 1; }\n    return n;\n}\n'"$E"
refused u03 "undefined variable 'yy'" "U3: a compound step, yy += 1" 'fn main() {\n    var n = 0;\n    var c = 0;\n    for (n = 0; n < 3; yy += 1) { c = c + 1; if (c > 9) { return 99; } }\n    return c;\n}\n'"$E"
refused u04 "undefined variable 'j'" "U4: a top-level step, j = i + 1" 'var i = 0;\nvar s = 0;\nfor (i = 0; i < 3; j = i + 1) { s = s + 1; i = i + 1; }\nsyscall(60, s);\n'
refused u05 "undefined variable 'g'" "U5: a fn's name, g = 1 (as the statement)" 'fn g(): i64 { return 1; }\nfn main() {\n    var i = 0;\n    for (i = 0; i < 3; g = 1) { i = i + 1; }\n    return i;\n}\n'"$E"
refused u06 "'t' is captured by value; a captured name is not assignable in a closure" "U6: a captured name in a closure's step, t += 1 (as the statement; 6.7.11: the capture named)" 'include "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\nfn main() {\n    alloc_init();\n    var t = 0;\n    var f = |n| { var k = 0; for (k = 0; k < n; t += 1) { k = k + 1; } return k * 10 + t; };\n    return fncall1(f, 4);\n}\n'"$E"

# ── X: --syntax-only ──────────────────────────────────────────────────────────────────────────
synonly x01 "X1: a step on a global the file cannot see (G_SIB += 1)" 'fn k(n): i64 {\n    var i = 0;\n    for (i = 0; i < n; G_SIB += 1) { i = i + 1; }\n    return i;\n}\n'
synonly x02 "X2: a step whose value is a field of a struct the file cannot see (i = e.size)" 'fn k(e): i64 {\n    var i = 0;\n    for (i = 0; i < 3; i = e.size) { i = i + 1; }\n    return i;\n}\n'
synrefused x03 "$X2" "X3: junk is still reported under --syntax-only" 'fn k(n): i64 {\n    var i = 0;\n    for (i = 0; i < n; i += 1 2) { }\n    return i;\n}\n'
synonly x04 "X4: a plain step on a global the file cannot see (G_SIB = i + 1)" 'fn k(n): i64 {\n    var i = 0;\n    for (i = 0; i < n; G_SIB = i + 1) { i = i + 1; }\n    return i;\n}\n'

# ── V: every step arm still runs its step (exit 0; else the failing check's number) ──────────
cat > "$T/steps.cyr" <<'EOF'
struct C { n; }
struct P3 { x; y; z; }
var G = 0;
var GA: i64[3];
var GP = P3 { 1, 2, 3 };
var GQ = P3 { 4, 5, 6 };
fn inc(v): i64 { return v + 1; }
fn f2(): i64 { return (3, 4); }
fn mk(k): P3 { var r = P3 { k, k + 1, k + 2 }; return r; }
fn local_op(): i64 { var s = 0; var i = 0; for (i = 0; i < 3; i += 1) { s = s + 1; } return s * 10 + i; }
fn local_plain(): i64 { var s = 0; var i = 0; for (i = 0; i < 3; i = i + 1) { s = s + 1; } return s * 10 + i; }
fn global_op(): i64 { var s = 0; for (G = 0; G < 4; G += 2) { s = s + 1; } return s * 10 + G; }
fn global_plain(): i64 { var s = 0; for (G = 0; G < 4; G = G + 1) { s = s + 1; } return s * 10 + G; }
fn sub_const(): i64 { var a: i64[2]; var s = 0; for (a[0] = 0; a[0] < 3; a[0] += 1) { s = s + 1; } return s * 10 + a[0]; }
fn sub_var(): i64 { var a: u8[4]; var j = 2; var s = 0; for (a[j] = 0; a[j] < 6; a[j] = a[j] + 2) { s = s + 1; } return s * 10 + a[j]; }
fn global_sub(): i64 { var s = 0; for (GA[1] = 0; GA[1] < 3; GA[1] += 1) { s = s + 1; } return s * 10 + GA[1]; }
fn f64_step(): i64 { var x: f64 = 0.0; var n = 0; for (x = 0.0; x < 1.0; x += 0.25) { n = n + 1; } return n; }
fn nested_paren(): i64 { var s = 0; var i = 0; for (i = 0; i < 6; i = (i + 3) * 1) { s = s + 1; } return s * 10 + i; }
fn call_value(): i64 { var s = 0; var i = 0; for (i = 0; i < 3; i = inc(i)) { s = s + 1; } return s * 10 + i; }
fn call_op(): i64 { var s = 0; var i = 0; for (i = 0; i < 4; i += inc(1)) { s = s + 1; } return s * 10 + i; }
fn field(): i64 { var c = C { 0 }; var s = 0; for (c.n = 0; c.n < 3; c.n += 1) { s = s + 1; } return s * 10 + c.n; }
fn deref(): i64 { var v = 0; var p = &v; var s = 0; for (v = 0; v < 3; *p += 1) { s = s + 1; } return s * 10 + v; }
fn multi(): i64 { var x = 0; var y = 0; var s = 0; for (s = 0; s < 1; x, y = f2()) { s = s + 1; } return x * 10 + y; }
fn struct_copy(): i64 { var a = P3 { 1, 2, 3 }; var b = P3 { 4, 5, 6 }; var n = 0; for (n = 0; n < 1; a = b) { n = n + 1; } return a.x * 100 + a.y * 10 + a.z; }
fn struct_call(): i64 { var a = P3 { 1, 2, 3 }; var n = 0; for (n = 0; n < 1; a = mk(7)) { n = n + 1; } return a.x * 100 + a.y * 10 + a.z; }
fn struct_paren(): i64 { var a = P3 { 1, 2, 3 }; var b = P3 { 4, 5, 6 }; var n = 0; for (n = 0; n < 1; a = (b)) { n = n + 1; } return a.x * 100 + a.y * 10 + a.z; }
fn struct_global(): i64 { var n = 0; for (n = 0; n < 1; GP = GQ) { n = n + 1; } return GP.x * 100 + GP.y * 10 + GP.z; }
fn tuple_step(): i64 { var t = (1, 2); var n = 0; for (n = 0; n < 1; t = (5, 6)) { n = n + 1; } return t.0 * 10 + t.1; }
fn later_global(): i64 { var s = 0; var i = 0; for (i = 0; i < 3; GLATE = i + 1) { s = s + 1; if (s > 9) { return 0; } i = GLATE; } return s * 10 + GLATE; }
var GLATE = 0;
var TI = 0;
var TS = 0;
for (TI = 0; TI < 3; TI += 1) { TS = TS + 1; }
fn main(): i64 {
    if (local_op() != 33) { return 1; }
    if (local_plain() != 33) { return 2; }
    if (global_op() != 24) { return 3; }
    if (global_plain() != 44) { return 4; }
    if (sub_const() != 33) { return 5; }
    if (sub_var() != 36) { return 6; }
    if (global_sub() != 33) { return 7; }
    if (f64_step() != 4) { return 8; }
    if (nested_paren() != 26) { return 9; }
    if (call_value() != 33) { return 10; }
    if (call_op() != 24) { return 11; }
    if (field() != 33) { return 12; }
    if (deref() != 33) { return 13; }
    if (multi() != 34) { return 14; }
    if (struct_copy() != 456) { return 15; }
    if (struct_call() != 789) { return 16; }
    if (struct_paren() != 456) { return 17; }
    if (struct_global() != 456) { return 18; }
    if (tuple_step() != 56) { return 19; }
    if (TS * 10 + TI != 33) { return 20; }
    if (later_global() != 44) { return 21; }
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
v_ok() {   # <label> <exit>
    if [ "$2" -eq 0 ]; then ok "$1: every step arm ran its step"; else bad "$1: exit $2 (the failing check's number)"; fi
}
for mode in plain IR1 IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="V1: x86" ;;
        IR1) env_="CYRIUS_IR=1"; lbl="V2: x86, CYRIUS_IR=1" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="V3: x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="V4: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$T/steps.cyr" > "$T/steps_$mode" 2> "$T/steps_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/steps_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/steps_$mode"; got=0; timeout 30 "$T/steps_$mode" > /dev/null 2>&1 || got=$?
    v_ok "$lbl" "$got"
done
A64=""
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        A64="$T/cc_a64"
        if "$A64" < "$T/steps.cyr" > "$T/steps.a64" 2> "$T/steps.a64.err" && [ -s "$T/steps.a64" ]; then
            chmod +x "$T/steps.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 ./steps.a64 > /dev/null 2>&1) || got=$?
            v_ok "V5: aarch64 (qemu)" "$got"
        else bad "V5: aarch64: did not compile: $(grep '^error' "$T/steps.a64.err" | head -1)"; fi
    else bad "V5: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP V5: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
CX=""
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    CX="$T/cc_cx"
    if "$CX" < "$T/steps.cyr" > "$T/steps.cyx" 2> "$T/steps.cyx.err" && [ -s "$T/steps.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/steps.cyx" > /dev/null 2>&1 || got=$?
        v_ok "V6: cx (cxvm)" "$got"
    else bad "V6: cx: did not compile: $(grep '^error' "$T/steps.cyx.err" | head -1)"; fi
else bad "V6: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$T/steps.cyr" > "$T/steps.exe" 2> "$T/steps.exe.err" && [ -s "$T/steps.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./steps.exe > /dev/null 2>&1) || got=$?
        v_ok "V7: PE (wine)" "$got"
    else bad "V7: PE: did not compile: $(grep '^error' "$T/steps.exe.err" | head -1)"; fi
else echo "  SKIP V7: PE leg — wine not installed"; skips=$((skips + 1)); fi

# A: the 6.6.20 aggregate-step file (every helper that consumes the `)` itself) builds and passes
TC=tests/tcyr/crossos/for_step_struct_assign.tcyr
rc=0; "$CC" < "$TC" > "$T/agg" 2> "$T/agg.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$T/agg" ]; then bad "A: $TC did not build (rc $rc): $(grep '^error' "$T/agg.err" | head -1)"
else
    chmod +x "$T/agg"; got=0; timeout 60 "$T/agg" > "$T/agg.out" 2>&1 || got=$?
    if [ "$got" -eq 0 ] && grep -q ' 0 failed' "$T/agg.out"; then ok "A: $TC: $(grep ' 0 failed' "$T/agg.out")"
    else bad "A: $TC: exit $got: $(grep -E 'FAIL|failed' "$T/agg.out" | head -3 | tr '\n' '|')"; fi
fi

# ── P: fork parity — the issue's six refused the same by the aarch64 and cx compilers ────────
for leg in a64 cx; do
    case $leg in a64) pc=$A64 ;; cx) pc=$CX ;; esac
    [ -n "$pc" ] || { echo "  SKIP P ($leg): no $leg compiler (see V5 / V6)"; skips=$((skips + 1)); continue; }
    refused "p${leg}1" "$X2" "P1 ($leg): J1" "$J1" "$pc"
    refused "p${leg}2" "$X2" "P2 ($leg): J2" "$J2" "$pc"
    refused "p${leg}3" "$X2" "P3 ($leg): J3" "$J3" "$pc"
    refused "p${leg}4" "$X2" "P4 ($leg): J4" "$J4" "$pc"
    refused "p${leg}5" "expected ')', got ';'" "P5 ($leg): J5" "$J5" "$pc"
    refused "p${leg}6" "$X2" "P6 ($leg): J6" "$J6" "$pc"
    refused "p${leg}7" "undefined variable 'j'" "P7 ($leg): U1" "$U1" "$pc"
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — every classic-for step ends at its \`)\`: junk refused once on every arm (J, F, L, X), a destination declared nowhere refused as the statement (U), every arm still runs its step on x86 / IR / DCE / aarch64 / cx / PE (V, A), fork parity (P)"
