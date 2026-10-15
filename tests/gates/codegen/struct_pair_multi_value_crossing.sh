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
#   C  (6.7.8) the X rows and the values file on cx (cxvm): cx's struct pair is r0:r4, the
#      multi-value registers themselves, so nothing differs there — the leg pins that it stays so
#      (it had no 16 B struct pair at all before 6.7.8: issues/archived/2026-10-08-cx-16b-struct-return-refused.md)
#   D  (6.7.11) a destructure binds a struct callee's REGISTER words only (the user's decision,
#      2026-10-13; issues/archived/2026-10-09-destructure-of-wide-struct-callee-reads-wrong-second-value.md):
#      over 16 B (a retptr: `var a, b = mk(5);` read a stale rdx, 50 where 56 is meant, on every
#      target) and three names from a 9-16 B struct's two words are refused by name, on the x86_64,
#      aarch64 and cx compilers, once each — at fn scope, in both top-level zones, as a method, from a
#      generic instance and from a `: Q` fn's `return (..)` arms; an 8 B struct is one value. X4-X6
#      (two names from 16 B) still run.
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
# (6.7.11, 2026-10-13, the same way)
#   M7 `_dt_struct_check` accepting a retptr struct (over 16 B)          -> RED D1-D4 D7 D9 (every leg)
#   M8 `_dt_struct_check` accepting three names from 9-16 B             -> RED D5 D6 D8 (every leg)
#   M9 `_dt_zone_check` clearing the latch before the right-hand side   -> RED D2 (two errors, every leg)
#   M10 `_dt_struct_check` accepting an 8 B struct                      -> RED D10 (every leg)
# (6.7.11, issues/archived/2026-10-08-struct-operator-results.md #4, the user's decision 2026-10-13) a tuple literal
# `return (x, y[, z]);` in a fn declared `: P` is refused by name in every class (`_refuse_struct_tuple_return`;
# struct_value_codegen.sh R8-R14), so the rows that produced the pair with it say `ret2(x, x + 1)` — the same
# multi-value arm and landing (`_mret_land`) — and X1 / X9 pin the refusal on the three compilers: X3 X8 D8
# and the values file's producers moved to `ret2`, the N leg reads X2. M6 is retired: the arity-3 arm no
# longer reaches a struct fn. Re-measured 2026-10-14:
#   M3 (again) `_mret_land` without ESTRUCT_PAIR_HI_SYNC                  -> RED X2 X3 a64, N x2, T2 (6 of 22)
#   M11 `_refuse_struct_tuple_return` answering 0                        -> RED X1 X9 (BUILT, every leg)
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
CX=0
CXC="$T/cc_cx"
if "$CC" < src/main_cx.cyr > "$CXC" 2> "$T/cc_cx.err" && [ -s "$CXC" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$CXC" "$T/cxvm"; CX=1
    printf '#!/bin/sh\nexec "%s" < "$1"\n' "$T/cxvm" > "$T/cxrun"; chmod +x "$T/cxrun"
else bad "src/main_cx.cyr or programs/cxvm.cyr did not build: $(grep '^error' "$T/cc_cx.err" "$T/cxvm.err" | head -1 || true)"; fi
# run <compiler> <runner|""> <name> <suffix> -> $got: the exit code, or "did not build ..."
run() {
    rc=0; timeout 60 "$1" < "$T/$3.cyr" > "$T/$3.$4" 2> "$T/$3.$4.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$3.$4" ]; then got="did not build (rc $rc): $(grep '^error' "$T/$3.$4.err" | head -1 || true)"; return; fi
    chmod +x "$T/$3.$4"; got=0
    if [ -n "$2" ]; then timeout 30 $2 "$T/$3.$4" > /dev/null 2>&1 || got=$?
    else timeout 30 "$T/$3.$4" > /dev/null 2>&1 || got=$?; fi
}
# exits <name> <want> <what> <source>: x86_64, aarch64 (qemu), then cx (cxvm)
exits() {
    printf '%b' "$4" > "$T/$1.cyr"
    run "$CC" "" "$1" x86
    if [ "$got" = "$2" ]; then ok "$3 (x86_64): exit $got"; else bad "$3 (x86_64): $got, want $2"; fi
    if [ "$QEMU" -eq 1 ]; then
        run "$A64" qemu-aarch64 "$1" a64
        if [ "$got" = "$2" ]; then ok "$3 (aarch64): exit $got"; else bad "$3 (aarch64): $got, want $2"; fi
    fi
    if [ "$CX" -eq 1 ]; then
        run "$CXC" "$T/cxrun" "$1" cyx
        if [ "$got" = "$2" ]; then ok "$3 (cx): exit $got"; else bad "$3 (cx): $got, want $2"; fi
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
# refused <name> <fragment> <what> <source>: the x86_64, aarch64 (qemu) and cx compilers each refuse it, once
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    for leg in x86_64 aarch64 cx; do
        c="$CC"
        if [ "$leg" = aarch64 ]; then [ "$QEMU" -eq 1 ] || continue; c="$A64"; fi
        if [ "$leg" = cx ]; then [ "$CX" -eq 1 ] || continue; c="$CXC"; fi
        rc=0; timeout 60 "$c" < "$T/$1.cyr" > "$T/$1.$leg.bin" 2> "$T/$1.$leg.err" || rc=$?
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        if [ "$rc" -eq 0 ]; then bad "$3 ($leg): BUILT (rc 0)"
        elif ! grep -qF "$2" "$T/$1.$leg.err"; then bad "$3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne 1 ]; then bad "$3 ($leg): $n error lines (want 1)"
        else ok "$3 ($leg): refused once"; fi
    done
}

P='struct P { a; b; }\n'
MT='fn mk(x): P { ret2(x, x + 1); }\n'
ML='fn mk(x): P { var p: P; p.a = x; p.b = x + 1; return p; }\n'
E='var r = main(); syscall(60, r);\n'
refused x1 "returns that struct — \`(a, b)\` is a tuple, another type" "X1: repro A's \`return (x, x + 1);\` in a \`: P\` fn is refused (6.7.11)" "${P}fn mk(x): P { return (x, x + 1); }\nfn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }\n$E"
exits x2 56 "X2: A with \`ret2(x, x + 1);\`" "${P}fn mk(x): P { ret2(x, x + 1); }\nfn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }\n$E"
exits x3 56 "X3: A with the assignment \`p = mk(5);\` into an existing P" "${P}${MT}fn main(): i64 { var p: P; p.a = 0; p.b = 0; p = mk(5); return p.a * 10 + p.b; }\n$E"
exits x4 56 "X4: repro B — \`var a, b = mk(5);\` from a \`: P\` fn returning a P local" "${P}${ML}fn main(): i64 { var a, b = mk(5); return a * 10 + b; }\n$E"
exits x5 56 "X5: B at top level, in the declaration zone" "${P}${ML}var a, b = mk(5);\nsyscall(60, a * 10 + b);\n"
exits x6 56 "X6: B at top level, after the first statement" "${P}${ML}var z = 0;\nz = 1;\nvar a, b = mk(5);\nsyscall(60, a * 10 + b);\n"
exits x7 6 "X7: \`mk(5); var b = rethi();\` after a P local" "${P}${ML}fn main(): i64 { mk(5); var b = rethi(); return b; }\n$E"
exits x8 6 "X8: \`mk(5); var b = rethi();\` after \`ret2(x, x + 1);\` (control)" "${P}${MT}fn main(): i64 { mk(5); var b = rethi(); return b; }\n$E"
refused x9 "returns that struct — \`(a, b, c)\` is a tuple, another type" "X9: A's \`return (x, x + 1, 9);\` is refused (6.7.11)" "${P}fn mk(x): P { return (x, x + 1, 9); }\nfn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }\n$E"

Q='struct Q { a; b; c; }\n'
QL='fn mk(x): Q { var q: Q; q.a = x; q.b = x + 1; q.c = x + 2; return q; }\n'
NR="it returns struct 'Q', which is not in registers - bind it to one name: \`var x = mk(..);\`"
N3="into 3 names - it returns struct 'P', whose 2 words are its return registers - bind 2 names"
refused d1 "cannot destructure 'mk' - $NR" "D1: the issue's repro — \`var a, b = mk(5);\` from a 24 B \`: Q\` fn" "${Q}${QL}fn main(): i64 { var a, b = mk(5); return a * 10 + b; }\n$E"
refused d2 "cannot destructure 'mk' - $NR" "D2: 24 B at top level, in the declaration zone" "${Q}${QL}var a, b = mk(5);\nsyscall(60, a * 10 + b);\n"
refused d3 "cannot destructure 'mk' - $NR" "D3: 24 B at top level, after the first statement" "${Q}${QL}var z = 0;\nz = 1;\nvar a, b = mk(5);\nsyscall(60, a * 10 + b);\n"
refused d4 "cannot destructure 'mk' - $NR" "D4: 24 B from a method" "${Q}impl Q { fn mk(self, x): Q { var q: Q; q.a = x; q.b = x + 1; q.c = x + 2; return q; } }\nfn main(): i64 { var z: Q; z.a = 0; var a, b = z.mk(5); return a * 10 + b; }\n$E"
refused d5 "cannot destructure 'mk' $N3" "D5: \`var a, b, c = mk(5);\` from a 16 B \`: P\` fn" "${P}${ML}fn main(): i64 { var a, b, c = mk(5); return a * 10 + b; }\n$E"
refused d6 "cannot destructure 'mk' $N3" "D6: three names from 16 B at top level, in the declaration zone" "${P}${ML}var a, b, c = mk(5);\nsyscall(60, a * 10 + b);\n"
refused d7 "cannot destructure 'mk' - $NR" "D7: 24 B with the if / else body pass 1 cannot prove" "${Q}fn mk(x): Q { var q: Q; q.a = x; q.b = x + 1; q.c = x + 2; if (x > 3) { return q; } else { return q; } }\nfn main(): i64 { var a, b = mk(5); return a * 10 + b; }\n$E"
refused d8 "cannot destructure 'mk' $N3" "D8: three names from a 16 B \`: P\` fn saying \`ret2(x, x + 1);\`" "${P}${MT}fn main(): i64 { var a, b, c = mk(5); return a * 10 + b + c; }\n$E"
refused d9 "cannot destructure 'mk' - $NR" "D9: 24 B from a generic instance" "${Q}fn mk<T>(x: T): Q { var q: Q; q.a = x; q.b = x + 1; q.c = x + 2; return q; }\nfn main(): i64 { var a, b = mk<i64>(5); return a * 10 + b; }\n$E"
refused d10 "but 'mk' returns 1 value - bind it to one name" "D10: an 8 B struct is one value, whatever its body" "struct P1 { a; }\nfn mk(x): P1 { var q: P1; q.a = x; if (x > 3) { return q; } else { return q; } }\nfn main(): i64 { var a, b = mk(5); return a * 10 + b; }\n$E"

if [ "$QEMU" -eq 1 ]; then
    NAT="$T/cc_nat"
    if "$A64" < src/main_aarch64_native.cyr > "$NAT" 2> "$T/cc_nat.err" && [ -s "$NAT" ]; then
        chmod +x "$NAT"
        printf '#!/bin/sh\nexec qemu-aarch64 "%s"\n' "$NAT" > "$T/natcc"; chmod +x "$T/natcc"
        for row in x2 x4; do
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
if [ "$CX" -eq 1 ]; then tcyr "T3: the values file (cx, cxvm)" "$CXC" "$T/cxrun"; fi

refused_a64 r1 "cannot capture 'mk' into tuple (i64, i64) - it returns struct 'P', not a tuple" "R1: \`var t: (i64, i64) = mk(5);\` from a \`: P\` fn" "${P}${ML}fn main(): i64 { var t: (i64, i64) = mk(5); return t.0 * 10 + t.1; }\n$E"
refused_a64 r2 "cannot re-assign from 'mk' - it returns struct 'P', not multiple values" "R2: \`a, b = mk(5);\` from a \`: P\` fn" "${P}${ML}fn main(): i64 { var a = 0; var b = 0; a, b = mk(5); return a * 10 + b; }\n$E"

if [ "$QEMU" -eq 0 ]; then echo "  SKIP: the aarch64 legs (qemu-aarch64 not installed; the crossos tcyr covers pi / ecb)"; skips=$((skips + 1)); fi
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — the aarch64 legs could not run; the x86_64 rows passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a 9-16 B struct return and a multi-value return agree in both directions on x86_64, aarch64 (cross + native fork) and cx, rethi() included; a destructure past a struct's register words is refused"
