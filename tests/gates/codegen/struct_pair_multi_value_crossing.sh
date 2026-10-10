#!/bin/sh
# tests/gates/codegen/struct_pair_multi_value_crossing.sh — 6.7.7
#
# A 9-16 B STRUCT RETURN AND A MULTI-VALUE RETURN MEET IN BOTH DIRECTIONS — ON aarch64 TOO.
# (issues/2026-10-09-aarch64-struct-pair-and-multi-value-registers-disagree.md)
#
# cyrius hands back two machine words two ways: a 9-16 B struct (`fn mk(x): P`) in the struct PAIR's
# registers, a multi-value return (`return (a, b);`, `ret2`) in the multi-value ones. x86_64 / PE /
# Mach-O x86 use rax:rdx for both. aarch64 (ELF, Mach-O arm64, the native fork) puts the pair in x0:x1
# (AAPCS64) and the multi-value second slot in x2, and the frontend lets the two meet both ways — so
# on aarch64 the second word was read from the register its producer never wrote, with no diagnostic:
#   A  a `: P` fn's `return (x, x + 1);` / `ret2` / `return (x, y, z);` (x2) received by `var p: P = f();`
#      or `p = f();` (x1): 55 where 56 is right (pi, ecb, qemu)
#   B  a `: P` fn's `return p;` (x1) read by `var a, b = f();` (x2) — at fn scope, at top level in the
#      declaration zone (EMIT_GVAR_INITS' replay) and after the first statement: 50 (pi, qemu), 250 (ecb)
#   H  `f(); var b = rethi();` after such a call (x2): 0 where 6 is right
# Since 6.7.7 every 9-16 B struct return carries its high word in BOTH registers on aarch64:
# EFLLOAD_STRUCT_INT_PAIR writes x2 as well as x1, and `_mret_land` (the multi-value arms' landing,
# PARSE_RETURN's arity 2 and 3 and `ret2`) emits ESTRUCT_PAIR_HI_SYNC (`mov x1, x2`) in a struct fn —
# a no-op on x86 and cx, where nothing differs. Neither convention moved; AAPCS64's x0:x1 holds.
#
# LEGS (every compiler built from this tree by $CYCC):
#   X  the issue's table, verbatim shapes, as exit codes: x86_64 (the oracle — it was always right) and
#      the aarch64 cross compiler under qemu-aarch64
#   N  repro A and B through the NATIVE aarch64 fork (src/main_aarch64_native.cyr), itself run under
#      qemu — the third aarch64 fork; the Mach-O arm64 one is ecb's crossos leg
#   T  tests/tcyr/crossos/struct_pair_multi_value_crossing.tcyr (every producer shape x every consumer:
#      methods, an operator, generics, defer, a frame past the 256-byte ldur window, forwarding calls)
#      on x86_64 and under qemu; the release gate runs it on pi / ecb / ach / cass
#   R  the struct callee the tuple capture and `a, b = f();` REFUSE (the user's B4 decision: a struct
#      return is no multi-value call) stays refused on the aarch64 compiler
# cx has no 16 B struct pair yet (issues/2026-10-08-cx-16b-struct-return-refused.md): no cx leg.
#
# MUTATION LEDGER (scratch copies of the tree, each rebuilt with the one change, the gate run from
# that copy as CYCC=<mutant>; 2026-10-09):
#   M0 the merged 6.7.7 tree before the fix (l677-int @ 06bd8981)        -> RED X1-X7 X9 a64, N x1 x4, T2
#      (21 of 25 tcyr rows; X8 and the four tcyr controls green)
#   M1 aarch64 EFLLOAD_STRUCT_INT_PAIR without both `mov x2, x1`          -> RED X4-X7 a64, N x4, T2 (13)
#   M2 ... without the deep-frame arm's `mov x2, x1` only               -> RED T2 only (its two rows past
#      the 256-byte ldur window): no X row has that frame
#   M3 `_mret_land` without ESTRUCT_PAIR_HI_SYNC                          -> RED X1-X3 X9 a64, N x1, T2 (8)
#   M4 aarch64 ESTRUCT_PAIR_HI_SYNC emitting nothing                      -> RED X1-X3 X9 a64, N x1, T2 (8)
#   M5 `ret2` landing through EJMP0 / rp_vec again (not `_mret_land`)     -> RED X2 a64, T2 (1)
#   M6 the arity-3 arm landing through EJMP0 / rp_vec again              -> RED X9 a64, T2 (1)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_pair_multi_value_crossing
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
ulimit -c 0 2>/dev/null
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then QEMU=1; fi
A64="$T/cc_a64"
if [ "$QEMU" -eq 1 ]; then
    if ! "$CC" < src/main_aarch64.cyr > "$A64" 2> "$T/cc_a64.err" || [ ! -s "$A64" ]; then
        bad "src/main_aarch64.cyr did not build: $(grep '^error' "$T/cc_a64.err" | head -1 || true)"; QEMU=0
    else chmod +x "$A64"; fi
fi
# run <compiler> <runner|""> <name> <suffix> -> $got: the exit code, or "did not build ..."
run() {
    rc=0; timeout 60 "$1" < "$T/$3.cyr" > "$T/$3.$4" 2> "$T/$3.$4.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$3.$4" ]; then got="did not build (rc $rc): $(grep '^error' "$T/$3.$4.err" | head -1 || true)"; return; fi
    chmod +x "$T/$3.$4"; got=0
    if [ -n "$2" ]; then timeout 30 $2 "$T/$3.$4" > /dev/null 2>&1 || got=$?
    else timeout 30 "$T/$3.$4" > /dev/null 2>&1 || got=$?; fi
}
# exits <name> <want> <what> <source>: x86_64 then aarch64 (qemu)
exits() {
    printf '%b' "$4" > "$T/$1.cyr"
    run "$CC" "" "$1" x86
    if [ "$got" = "$2" ]; then ok "$3 (x86_64): exit $got"; else bad "$3 (x86_64): $got, want $2"; fi
    if [ "$QEMU" -eq 1 ]; then
        run "$A64" qemu-aarch64 "$1" a64
        if [ "$got" = "$2" ]; then ok "$3 (aarch64): exit $got"; else bad "$3 (aarch64): $got, want $2"; fi
    fi
}
# refused_a64 <name> <fragment> <what> <source>: the aarch64 compiler refuses it, once
refused_a64() {
    [ "$QEMU" -eq 1 ] || return 0
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$A64" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3 (aarch64): BUILT (rc 0)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3 (aarch64): refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1 || true)"
    elif [ "$n" -ne 1 ]; then bad "$3 (aarch64): $n error lines (want 1)"
    else ok "$3 (aarch64): refused once"; fi
}

P='struct P { a; b; }\n'
MT='fn mk(x): P { return (x, x + 1); }\n'
ML='fn mk(x): P { var p: P; p.a = x; p.b = x + 1; return p; }\n'
E='var r = main(); syscall(60, r);\n'
exits x1 56 "X1: repro A — \`return (x, x + 1);\` in a \`: P\` fn, \`var p: P = mk(5);\`" "${P}${MT}fn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }\n$E"
exits x2 56 "X2: A with \`ret2(x, x + 1);\`" "${P}fn mk(x): P { ret2(x, x + 1); }\nfn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }\n$E"
exits x3 56 "X3: A with the assignment \`p = mk(5);\` into an existing P" "${P}${MT}fn main(): i64 { var p: P; p.a = 0; p.b = 0; p = mk(5); return p.a * 10 + p.b; }\n$E"
exits x4 56 "X4: repro B — \`var a, b = mk(5);\` from a \`: P\` fn returning a P local" "${P}${ML}fn main(): i64 { var a, b = mk(5); return a * 10 + b; }\n$E"
exits x5 56 "X5: B at top level, in the declaration zone" "${P}${ML}var a, b = mk(5);\nsyscall(60, a * 10 + b);\n"
exits x6 56 "X6: B at top level, after the first statement" "${P}${ML}var z = 0;\nz = 1;\nvar a, b = mk(5);\nsyscall(60, a * 10 + b);\n"
exits x7 6 "X7: \`mk(5); var b = rethi();\` after a P local" "${P}${ML}fn main(): i64 { mk(5); var b = rethi(); return b; }\n$E"
exits x8 6 "X8: \`mk(5); var b = rethi();\` after \`return (x, x + 1);\` (control)" "${P}${MT}fn main(): i64 { mk(5); var b = rethi(); return b; }\n$E"
exits x9 56 "X9: A with \`return (x, x + 1, 9);\`" "${P}fn mk(x): P { return (x, x + 1, 9); }\nfn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }\n$E"

if [ "$QEMU" -eq 1 ]; then
    NAT="$T/cc_nat"
    if "$A64" < src/main_aarch64_native.cyr > "$NAT" 2> "$T/cc_nat.err" && [ -s "$NAT" ]; then
        chmod +x "$NAT"
        printf '#!/bin/sh\nexec qemu-aarch64 "%s"\n' "$NAT" > "$T/natcc"; chmod +x "$T/natcc"
        for row in x1 x4; do
            run "$T/natcc" qemu-aarch64 "$row" nat
            if [ "$got" = 56 ]; then ok "N: $row through the native aarch64 fork: exit 56"; else bad "N: $row through the native aarch64 fork: $got, want 56"; fi
        done
    else bad "N: src/main_aarch64_native.cyr did not build: $(grep '^error' "$T/cc_nat.err" | head -1 || true)"; fi
fi

TC=tests/tcyr/crossos/struct_pair_multi_value_crossing.tcyr
tcyr() {   # <what> <compiler> <runner>
    n=$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')
    rc=0; "$2" < "$TC" > "$T/tc_$n" 2> "$T/tc_$n.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/tc_$n" ]; then bad "$1: the values file did not build (rc $rc): $(grep '^error' "$T/tc_$n.err" | head -1 || true)"; return; fi
    chmod +x "$T/tc_$n"; got=0
    if [ -n "$3" ]; then timeout 120 $3 "$T/tc_$n" > "$T/tc_$n.out" 2>&1 || got=$?
    else timeout 60 "$T/tc_$n" > "$T/tc_$n.out" 2>&1 || got=$?; fi
    if [ "$got" -eq 0 ] && grep -q ' 0 failed' "$T/tc_$n.out"; then ok "$1: $(grep ' 0 failed' "$T/tc_$n.out")"
    else bad "$1: exit $got: $(grep -E 'FAIL|failed' "$T/tc_$n.out" | head -4 | tr '\n' '|' || true)"; fi
}
tcyr "T1: the values file (x86_64)" "$CC" ""
if [ "$QEMU" -eq 1 ]; then tcyr "T2: the values file (aarch64, qemu)" "$A64" qemu-aarch64; fi

refused_a64 r1 "cannot capture 'mk' into tuple (i64, i64) - it returns struct 'P', not a tuple" "R1: \`var t: (i64, i64) = mk(5);\` from a \`: P\` fn" "${P}${ML}fn main(): i64 { var t: (i64, i64) = mk(5); return t.0 * 10 + t.1; }\n$E"
refused_a64 r2 "cannot re-assign from 'mk' - it returns struct 'P', not multiple values" "R2: \`a, b = mk(5);\` from a \`: P\` fn" "${P}${ML}fn main(): i64 { var a = 0; var b = 0; a, b = mk(5); return a * 10 + b; }\n$E"

if [ "$QEMU" -eq 0 ]; then echo "  SKIP: the aarch64 legs (qemu-aarch64 not installed; the crossos tcyr covers pi / ecb)"; skips=$((skips + 1)); fi
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — the aarch64 legs could not run; the x86_64 rows passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a 9-16 B struct return and a multi-value return agree in both directions on x86_64 and aarch64 (cross + native fork), rethi() included"
