#!/bin/sh
# tests/gates/codegen/struct_value_codegen.sh — 6.7.6 (Break 1, lane E)
#
# STRUCT VALUES AND STRUCT FIELDS AS OPERANDS — crashes and silent wrong values on valid code. The
# runtime half is tests/tcyr/crossos/struct_value_codegen.tcyr, which this gate builds and runs on
# x86_64 (default pipeline, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu) and cx (cxvm),
# compilers built from this tree (rows A); the release gate runs it on the four real hosts.
#
#   F  x86: `if (h.m)` / `while (h.m)` on an i8 / i16 / i32 field branched on the flags of the
#      statement before it (EFIELD_LOAD_W's narrow load never cleared `_flags_reflect_rax`)
#   I  a name intrinsic's result (`mulh64`, `fncallN`, `callptr`) kept its LAST argument's struct
#      type, so `fncall1(&f, n) + 1` with `n: Num` dispatched `Num_add` (100 where 8 is right)
#   P  a PARENTHESISED argument to an address-passed parameter (`rd3((a))`, `rd1((s))`,
#      `rd1((mk1(4)))`) pushed its value: SIGSEGV. Parentheses wrapping the whole argument are
#      transparent (`_sarg_paren`); its refusals (another struct, no frame at top level) are the
#      unparenthesised argument's, reported once
#
# MUTATION LEDGER (scratch copies of the tree, each rebuilt with the one change and the gate run
# from that copy as CYCC=<mutant>; 2026-10-08):
#   M-F x86 EFIELD_LOAD_W without `_flags_reflect_rax = 0`  -> RED F1 (exit 1) and A1-A4 (tcyr F1-F4
#       F6 F8); A5 A6 green (aarch64 / cx never set the tracker)
#   M-I1 `_lower_mulh64` without `_icall_untyped`            -> RED I2 (100) and A1-A6 (tcyr I1 I7)
#   M-I2 `_PINDIRECT_CALL_IN` without `_icall_untyped`       -> RED I1 (100) and A1-A6 (tcyr I2-I7)
#   M-P1 `_try_push_struct_addr_arg` without the `_sarg_paren` arm -> RED P1 P2 (139), P3 P5 (BUILT)
#       and A1-A6 (native SIGSEGV; cx tcyr P1 P2 read the value as an address)
#   M-P2 `_pwrap_k` without its consecutive-close test       -> RED A1-A6 (tcyr P16: `((a) + (b))`
#       read as two wraps; native SIGSEGV)
#   M-P3 `_pwrap_k` reading the token after the INNERMOST `)` (E-3 as first committed) -> RED P6
#       and A1-A6 (the values file does not build: "expected ')'" at tcyr P17's `+`)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_value_codegen
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
ulimit -c 0 2>/dev/null
fails=0
skips=0
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
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
# tcyr <what> <compiler> <runner> [ENV=V]: build the values file, run it, require "0 failed".
TC=tests/tcyr/crossos/struct_value_codegen.tcyr
tcyr() {
    n=$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')
    rc=0
    if [ -n "${4:-}" ]; then env "$4" "$2" < "$TC" > "$T/tc_$n" 2> "$T/tc_$n.err" || rc=$?
    else "$2" < "$TC" > "$T/tc_$n" 2> "$T/tc_$n.err" || rc=$?; fi
    if [ "$rc" -ne 0 ] || [ ! -s "$T/tc_$n" ]; then bad "$1: the values file did not build (rc $rc): $(grep '^error' "$T/tc_$n.err" | head -1)"; return; fi
    chmod +x "$T/tc_$n"
    got=0
    if [ -n "$3" ]; then timeout 120 $3 "$T/tc_$n" > "$T/tc_$n.out" 2>&1 || got=$?
    else timeout 60 "$T/tc_$n" > "$T/tc_$n.out" 2>&1 || got=$?; fi
    if [ "$got" -eq 0 ] && grep -q ' 0 failed' "$T/tc_$n.out"; then ok "$1: $(grep ' 0 failed' "$T/tc_$n.out")"
    else bad "$1: exit $got: $(grep -E 'FAIL|failed' "$T/tc_$n.out" | head -4 | tr '\n' '|')"; fi
}
E='\nsyscall(60, main());\n'

exits f01 0 "F1: if (h.m) on a zero i8 field after x = x + 1 (the filed repro: 1 on x86)" "struct H { n; m: i8; k: i32; }\nfn main(): i64 { var h = H { 1, 0, 3 }; var x = 5; x = x + 1; if (h.m) { return 1; } return 0; }$E"
NUM='struct Num { a; b; }\nfn Num_add(x: Num, y) { return 100; }\nfn id1(x) { return 7; }\n'
exits i01 8 "I1: fncall1(&id1, n) + 1 (the filed repro: 100)" "include \"lib/fnptr.cyr\"\n${NUM}fn main() { var n: Num = Num { 1, 2 }; return fncall1(&id1, n) + 1; }$E"
exits i02 1 "I2: mulh64(3, n) + 1 (the filed repro: 100)" "${NUM}fn main() { var n: Num = Num { 1, 2 }; return mulh64(3, n) + 1; }$E"
P3S='struct P3 { x; y; z; }\nfn rd3(p: *P3) { return p.z; }\nfn mk3(v): P3 { var t: P3 = P3 { v, v, v }; return t; }\n'
S1S='struct S1 { v; }\nfn rd1(p: *S1) { return p.v; }\nfn mk1(v): S1 { var t: S1; t.v = v; return t; }\n'
exits p01 3 "P1: rd3((a)) (the filed repro: SIGSEGV)" "${P3S}fn main() { var a: P3 = P3 { 1, 2, 3 }; return rd3((a)); }$E"
exits p02 45 "P2: rd1((s)) + rd1((mk1(4))) * 10 (the filed repros: SIGSEGV)" "${S1S}fn main() { var s: S1; s.v = 5; return rd1((s)) + rd1((mk1(4))) * 10; }$E"
refused p03 "cannot pass 'a' to a parameter of a different struct type in a call to 'rd3'" "P3: rd3((a)) with a: Q3" "${P3S}struct Q3 { x; y; z; }\nfn main() { var a: Q3 = Q3 { 1, 2, 3 }; return rd3((a)); }$E"
refused p04 "'mk3' returns a struct by value, and a struct result needs storage in a fn's frame" "P4: rd3((mk3(4))) at top level" "${P3S}var r = rd3((mk3(4)));\nsyscall(60, r);\n"
refused p05 "'mk1' returns a struct by value, and a struct result needs storage in a fn's frame" "P5: rd1((mk1(4))) at top level" "${S1S}var r = rd1((mk1(4)));\nsyscall(60, r);\n"
exits p06 21 "P6: sz(((a)) + (b)): a double wrap that is only the left operand" "${P3S}fn P3_add(a: *P3, b: *P3): P3 { var t: P3 = P3 { a.x + b.x, a.y + b.y, a.z + b.z }; return t; }\nfn sz(p: P3) { return p.x + p.y + p.z; }\nfn main() { var a: P3 = P3 { 1, 2, 3 }; var b: P3 = P3 { 4, 5, 6 }; return sz(((a)) + (b)) + rd3(((b))) - 6; }$E"

tcyr "A1: the values file (x86_64)" "$CC" ""
tcyr "A2: ... under CYRIUS_IR=1" "$CC" "" CYRIUS_IR=1
tcyr "A3: ... under CYRIUS_IR=3" "$CC" "" CYRIUS_IR=3
tcyr "A4: ... under CYRIUS_DCE=1" "$CC" "" CYRIUS_DCE=1
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        tcyr "A5: aarch64 (qemu)" "$T/cc_a64" qemu-aarch64
    else bad "A5: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    printf '#!/bin/sh\nexec "%s" < "$1"\n' "$T/cxvm" > "$T/cxrun"; chmod +x "$T/cxrun"
    tcyr "A6: cx (cxvm)" "$T/cc_cx" "$T/cxrun"
else bad "A6: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — struct values and narrow fields as operands: values on x86_64 / IR / DCE / aarch64 / cx (A)"
