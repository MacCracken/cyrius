#!/bin/sh
# tests/gates/frontend/stray_brace_refused.sh — 6.7.9 (critical lane, bite 2)
#
# AN UNMATCHED `}` AT MODULE SCOPE IS REFUSED, IN PASS 1, ONCE. PARSE_PROG is also the block and
# fn-body parser, so `}` ends its loop; at module scope it stopped there and EVERYTHING after the
# brace was silently dropped — the build said OK, `main` was never compiled (its callees reported
# dead), the program exited 0. In a multi-file build the lost definitions surfaced as "undefined"
# errors in OTHER files, pointing everywhere but at the brace (agnos's report: 62 of them, a bisect).
# Pass 1's tail loop (`_prescan_tail_loop`, parse_fn.cyr) meets the same `}` at module depth — every
# declaration and statement before it was consumed with its braces balanced — and now reports
# "unmatched '}' at module scope" there (`_tl_stray_brace`) and stops the build before any body is
# parsed: one positioned error, no cascade. (issues/2026-10-11-stray-top-level-brace-silently-ends-the-unit.md;
# the user's decision 3(a), 2026-10-11)
#
#   R  the issue's two files VERBATIM (a.cyr: `main` after the brace; b.cyr: a var, a fn and `main`
#      after it): refused at :3:1, exactly one error line, no binary written
#   P  every placement: the brace first (nothing before it); in the declaration zone after a struct,
#      an enum, a const, a trait, an impl, a fn, a var; after a top-level statement (an assignment,
#      an if / else chain, a while, a switch, a `do .. while`, a closure declaration, a relaxed-
#      ordering fn after statements); two in a row (the first is the one named)
#   H  an extra `}` INSIDE a fn ends it early and the fn's own closing brace is the one left over:
#      refused there, once, with the hint — the old compiler reported "undefined variable" for the
#      fn's tail, now top-level code
#   I  the agnos shape, three files: inc_a.cyr has the brace and defines LATE / later() after it,
#      inc_b.cyr uses both, the entry calls them. I1 includes inc_b.cyr FIRST (agnos's: the old build
#      reported "undefined variable 'LATE'" in inc_b.cyr and "undefined function 'later'", nothing
#      at the brace); I2 after (dropped, the old build said OK). One error, naming inc_a.cyr:2, and
#      no "undefined" line
#   X  --syntax-only (cyrius lint's pre-pass) refuses it the same, once
#   F  fork parity: R (a.cyr) and I refused the same, and K compiled, by every fork compiler that
#      runs here, built from this tree — main_aarch64, main_cx, main_win, main_aarch64_native (built
#      by the cross compiler, run under qemu-aarch64) — and by the x86 compiler for the PE target
#      (CYRIUS_TARGET_WIN=1). The two Mach-O forks cannot run on Linux; they call the same
#      `_tl_pass1` (toplevel_scan_shared.sh)
#   K  ANTI-VACUOUS: every legitimate module-scope `}` still compiles — a struct / enum / trait /
#      impl / fn in the declaration zone, an if / elif / else chain, a while, a struct literal, two
#      closures (`|v| v * v`, `|v| { .. };`), a switch, a match, a for, a fn defined in a top-level
#      `if` block, a `do .. while`, a relaxed-ordering fn — and the program exits 42 (NOT 0: a
#      truncated program exits 0) on x86 (plain, CYRIUS_IR=3, CYRIUS_DCE=1); it compiles with no error on
#      every fork above
#
# MUTATION LEDGER (scratch trees, each a 2-stage mutant cycc, this gate run from that tree; 2026-10-11):
#   M1  the `t == 14` arm back to `go = 0` (no report — the 6.7.8 arm)
#                                -> RED R1 R2 P1-P15 H1 H1h I1 I2 X1 F (a.cyr and I1 on all five legs):
#                                   32 rows; K green
#   M2  the arm steps past the brace and continues (option (b) of the decision, without its warning)
#                                -> RED the same 32 rows (pass 2 still stops at the brace); K green
#   M3  `_tl_stray_brace` reports but does not exit (pass 2 runs)
#                                -> RED H1 I1 F(I1) on all five legs: 7 rows — the "undefined" cascade
#                                   is back beside the refusal; K green
#   M4  the hint line dropped    -> RED H1h
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=stray_brace_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
M="unmatched '}' at module scope"

# refused_f <name> <where> <what> <file> [compiler] [env]: the compile fails, exactly one error line,
# it holds "<where>: unmatched '}' at module scope", and nothing was written to stdout
refused_f() {
    _c=${5:-$CC}
    rc=0; env ${6:-} timeout 60 "$_c" < "$4" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want \"$2: $M\""
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want exactly 1: $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|')"
    elif ! grep '^error' "$T/$1.err" | grep -qF "$2: $M"; then bad "$3: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ -s "$T/$1.bin" ]; then bad "$3: refused, but a binary was written"
    else ok "$3"; fi
}
# refused <name> <where> <what> <body> [compiler]: refused_f on a printf body
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    refused_f "$1" "$2" "$3" "$T/$1.cyr" "${5:-$CC}"
}

# ── R: the issue's two files, verbatim ────────────────────────────────────────────────────────
cat > "$T/a.cyr" <<'EOF'
var counter = 0;
fn bump() { counter = counter + 1; return counter; }
}
fn main() { bump(); return counter; }
EOF
cat > "$T/b.cyr" <<'EOF'
var counter = 0;
fn bump() { counter = counter + 1; return counter; }
}
var later = 7;
fn usel() { return later; }
fn main() { bump(); return usel(); }
EOF
refused_f r01 "<source>:3:1" "R1: the issue's a.cyr (main after the brace)" "$T/a.cyr"
refused_f r02 "<source>:3:1" "R2: the issue's b.cyr (a var, a fn and main after it)" "$T/b.cyr"

# ── P: every placement ────────────────────────────────────────────────────────────────────────
TAIL='fn main() { return 3; }\nsyscall(60, main());\n'
refused p01 "<source>:1:1" "P1: the brace first, nothing before it" "}\n$TAIL"
refused p02 "<source>:2:1" "P2: after a struct" "struct S { a; b; }\n}\n$TAIL"
refused p03 "<source>:2:1" "P3: after an enum" "enum E { EA; EB; }\n}\n$TAIL"
refused p04 "<source>:2:1" "P4: after a const" "const K = 4;\n}\n$TAIL"
refused p05 "<source>:2:1" "P5: after a trait" "trait Tr { fn t(self): i64; }\n}\n$TAIL"
refused p06 "<source>:3:1" "P6: after an impl" "struct S { a; }\nimpl S { fn get(self): i64 { return self.a; } }\n}\n$TAIL"
refused p07 "<source>:2:1" "P7: after a fn" "fn f() { if (1) { return 1; } return 2; }\n}\n$TAIL"
refused p08 "<source>:2:1" "P8: after a declaration-zone var" "var g = 5;\n}\n$TAIL"
refused p09 "<source>:3:1" "P9: after a top-level assignment" "var x = 1;\nx = x + 1;\n}\nsyscall(60, x);\n"
refused p10 "<source>:3:1" "P10: after an if / elif / else chain" "var x = 1;\nif (x == 1) { x = 2; } elif (x == 2) { x = 3; } else { x = 4; }\n}\nsyscall(60, x);\n"
refused p11 "<source>:3:1" "P11: after a while" "var x = 1;\nwhile (x < 4) { x = x + 1; }\n}\nsyscall(60, x);\n"
refused p12 "<source>:6:1" "P12: after a switch" "var x = 1;\nswitch (x) {\n    case 1: { x = 5; }\n    default: { x = 6; }\n}\n}\nsyscall(60, x);\n"
refused p13 "<source>:3:1" "P13: after a do .. while" "var x = 1;\ndo { x = x + 1; } while (x < 4);\n}\nsyscall(60, x);\n"
refused p14 "<source>:3:1" "P14: after a closure declaration" "var x = 1;\nvar f = |v| { return v + 1; };\n}\nsyscall(60, x);\n"
refused p15 "<source>:4:1" "P15: two in a row, after a relaxed-ordering fn (the first is named)" "var x = 1;\nx = 2;\nfn late() { return 9; }\n}\n}\nsyscall(60, late());\n"

# ── H: an extra `}` inside a fn ───────────────────────────────────────────────────────────────
refused h01 "<source>:5:1" "H1: an extra '}' inside a fn — refused at the fn's own closing brace" \
    'fn f(x) {\n    if (x) { x = 1; } }\n    x = 2;\n    return x;\n}\nsyscall(60, f(0));\n'
if grep -q "^  hint: if it was meant to close a fn or block, a '}' above it closed that one too soon" "$T/h01.err"; then
    ok "H1h: the hint names the earlier '}'"
else bad "H1h: no hint line: $(tr '\n' '|' < "$T/h01.err" | head -c 300)"; fi

# ── I: the agnos shape — the brace in one file, its lost definitions used in another ─────────
# inc1 (agnos's): inc_b.cyr, included BEFORE the file with the brace, uses what inc_a.cyr defines
# after it — the old build reported "undefined variable 'LATE'" in inc_b.cyr and "undefined
# function 'later'", nothing at the brace. inc2: the user included after it — dropped with the
# rest, the old build said OK.
for d in inc1 inc2; do
    mkdir -p "$T/$d"
    printf 'fn helper() { return 7; }\n}\nvar LATE = 30;\nfn later() { return LATE + 5; }\n' > "$T/$d/inc_a.cyr"
    printf 'fn use_late() { return later() + LATE + helper(); }\n' > "$T/$d/inc_b.cyr"
done
printf 'include "inc_b.cyr"\ninclude "inc_a.cyr"\nfn main() { return use_late() + LATE; }\nsyscall(60, main());\n' > "$T/inc1/main.cyr"
printf 'include "inc_a.cyr"\ninclude "inc_b.cyr"\nfn main() { return use_late() + LATE; }\nsyscall(60, main());\n' > "$T/inc2/main.cyr"
# include_i <name> <what> <dir> [compiler] [env]: the three-file build, run from its directory —
# one error, naming inc_a.cyr:2, and no "undefined" line (error or warning) anywhere
include_i() {
    _c=${4:-$CC}
    rc=0; (cd "$T/$3" && env ${5:-} timeout 60 "$_c" < main.cyr > "$T/$1.bin" 2> "$T/$1.err") || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$2: compiled (rc 0)"
    elif [ "$n" -ne 1 ]; then bad "$2: $n error lines, want exactly 1: $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|')"
    elif ! grep '^error' "$T/$1.err" | grep -qF "inc_a.cyr:2:1: $M"; then bad "$2: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"
    elif grep -q 'undefined' "$T/$1.err"; then bad "$2: an 'undefined' line besides the refusal: $(grep 'undefined' "$T/$1.err" | head -1)"
    else ok "$2"; fi
}
include_i i01 "I1: the user included BEFORE the brace's file (agnos) — one error at inc_a.cyr:2, no 'undefined' in inc_b.cyr" inc1
include_i i02 "I2: the user included after it — one error at inc_a.cyr:2" inc2

# ── X: --syntax-only ──────────────────────────────────────────────────────────────────────────
rc=0; timeout 60 "$CC" --syntax-only < "$T/a.cyr" > /dev/null 2> "$T/x01.err" || rc=$?
n=$(grep -c '^error' "$T/x01.err" || true)
if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ] && grep -qF "<source>:3:1: $M" "$T/x01.err"; then ok "X1: --syntax-only refuses a.cyr, once"
else bad "X1: --syntax-only rc $rc, $n error lines: $(grep '^error' "$T/x01.err" | head -1)"; fi

# ── K: the legitimate module-scope braces still compile, and nothing after them is dropped ────
cat > "$T/kept.cyr" <<'EOF'
include "lib/fnptr.cyr"
struct P { x; y; }
struct Q { a; }
enum E { EA; EB; }
const K = 3;
trait Sh { fn sh(self): i64; }
impl Sh for P { fn sh(self): i64 { return self.x * 10 + self.y; } }
impl P { fn sum(self): i64 { return self.x + self.y; } }
fn f(x) { if (x) { return 1; } return 2; }
var t = 0;
if (t == 0) { t = 1; } elif (t == 2) { t = 3; } else { t = 4; }
while (t < 5) { t = t + 1; }
var q = P { 2, 3 };
var sq = |v| v * v;
var add = |v| { return v + K; };
switch (t) {
    case 5: { t = 6; }
    default: { t = 7; }
}
var m = 0;
match (t) {
    6 => { m = 1; }
    _ => { m = 2; }
}
for (var i = 0; i < 2; i = i + 1) { t = t + 1; }
if (t > 0) { fn inner(v) { return v * 2; } }
do { t = t + 1; } while (t < 9);
fn late() { return 40; }
var w = Q { 5 };
var s = 0;
if (t != 9) { s = s + 1; }
if (m != 1) { s = s + 2; }
if (q.sum() != 5) { s = s + 4; }
if (q.sh() != 23) { s = s + 8; }
if (fncall1(sq, 3) + fncall1(add, 1) != 13) { s = s + 16; }
if (inner(late()) + w.a + EB + f(1) != 87) { s = s + 32; }
syscall(60, 42 + s);
EOF
for mode in plain IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="K1: x86" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="K2: x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="K3: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ timeout 60 "$CC" < "$T/kept.cyr" > "$T/kept_$mode" 2> "$T/kept_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ] || grep -q '^error' "$T/kept_$mode.err"; then bad "$lbl: rc $rc: $(grep '^error' "$T/kept_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/kept_$mode"; got=0; timeout 30 "$T/kept_$mode" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq 42 ]; then ok "$lbl: every legitimate module-scope '}' compiles; exit 42"
    else bad "$lbl: exit $got, want 42 (0 = the tail was dropped; 43+ = the failing checks' bits)"; fi
done

# ── F: fork parity — the refusal lives in the shared pass 1 ──────────────────────────────────
# fork_rows <fork> <compiler>: a.cyr and the three-file build refused, the kept file compiles
fork_rows() {
    refused_f "f_$1" "<source>:3:1" "F ($1): a.cyr" "$T/a.cyr" "$2"
    include_i "fi_$1" "F ($1): the agnos three-file build (I1)" inc1 "$2"
    rc=0; timeout 60 "$2" < "$T/kept.cyr" > "$T/fk_$1" 2> "$T/fk_$1.err" || rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/fk_$1.err" && [ -s "$T/fk_$1" ]; then ok "F ($1): the kept file compiles"
    else bad "F ($1): the kept file: rc $rc: $(grep '^error' "$T/fk_$1.err" | head -1)"; fi
}
for fk in main_aarch64 main_cx main_win; do
    if timeout 120 "$CC" < "src/$fk.cyr" > "$T/cc_$fk" 2> "$T/cc_$fk.err" && [ -s "$T/cc_$fk" ]; then
        chmod +x "$T/cc_$fk"
        fork_rows "$fk" "$T/cc_$fk"
    else bad "F ($fk): src/$fk.cyr did not build: $(grep '^error' "$T/cc_$fk.err" | head -1)"; fi
done
# The aarch64-HOSTED compiler, built by the cross compiler above and run under qemu-user.
if ! command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "  SKIP F (main_aarch64_native): qemu-aarch64 not installed"; skips=$((skips + 1))
elif [ ! -s "$T/cc_main_aarch64" ]; then bad "F (main_aarch64_native): no aarch64 cross compiler (see F main_aarch64)"
elif timeout 120 "$T/cc_main_aarch64" < src/main_aarch64_native.cyr > "$T/cc_nat" 2> "$T/cc_nat.err" && [ -s "$T/cc_nat" ]; then
    chmod +x "$T/cc_nat"
    printf '#!/bin/sh\nexec qemu-aarch64 "%s" "$@"\n' "$T/cc_nat" > "$T/cc_nat.sh"
    chmod +x "$T/cc_nat.sh"
    fork_rows main_aarch64_native "$T/cc_nat.sh"
else bad "F (main_aarch64_native): src/main_aarch64_native.cyr did not build: $(grep '^error' "$T/cc_nat.err" | head -1)"; fi
# The PE target through the x86 compiler. (The two Mach-O forks cannot run on Linux — they call the
# same `_tl_pass1`, which toplevel_scan_shared.sh pins for every fork.)
refused_f f_pe "<source>:3:1" "F (PE target, CYRIUS_TARGET_WIN=1): a.cyr" "$T/a.cyr" "$CC" "CYRIUS_TARGET_WIN=1"
include_i fi_pe "F (PE target, CYRIUS_TARGET_WIN=1): the agnos three-file build (I1)" inc1 "$CC" "CYRIUS_TARGET_WIN=1"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — an unmatched module-scope '}' is refused in pass 1, once, positioned (R, P, H, I, X), on every fork that runs here (F); every legitimate module-scope '}' still compiles and nothing after it is dropped (K)"
