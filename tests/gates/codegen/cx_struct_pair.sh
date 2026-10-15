#!/bin/sh
# cx_struct_pair.sh — 6.7.8 (dyn lane, bite D1). cx returns a 9-16 B integer-class struct by value
# in a register pair — r0 (low word) : r4 (high word) — as x86 does in rax:rdx and aarch64 in x0:x1.
# (issues/archived/2026-10-08-cx-16b-struct-return-refused.md)
#
# THE DEFECT. cx's EFLLOAD_STRUCT_INT_PAIR / EFLSTORE_STRUCT_INT_PAIR were the v5.10.45 "Phase 1"
# ERR_MSG stubs, so every program that returned or received a 9-16 B struct by value failed to build
# for cx ("cx: int-class 16B struct pair-return ABI not supported") — a callee's `return p;`, a
# caller's `var q: P = f();`, a method result, an operator operand temp. Seventeen .tcyr files of
# the corpus (fourteen of them crossos) did not compile for cx at all, and six more fenced their
# pair rows off it with `#ifndef CYRIUS_TARGET_CX`.
# THE FIX. Both emitters are the f64v2 pair's shape with r4 in place of r1 — lo at the named slot,
# hi at its filler — and r4 because it is cx's rdx peer: the multi-value second slot (`return (a,
# b);`, `ret2`, the destructure, `rethi()`), so the struct pair and the multi-value return meet with
# no sync, as on x86 (ESTRUCT_PAIR_HI_SYNC stays a no-op on cx).
#
# ROWS — each a program run NATIVELY (x86_64, the oracle) and on cxvm; both must exit the value the
# row states. Every value is order-sensitive (x * 10 + y over a (4, 2) pair: a swapped pair reads 24).
#   P1   the issue's repro verbatim (42), and P1b the same order-sensitive
#   P2   an assignment `q = mk(4, 2);` into an existing P2        P3  `var r = mk(4, 2);` (inferred)
#   P4   a method's 16 B result `p.sw()`                         P5  a call result as an operator's
#        LEFT operand (`mk(9, 7) - s`)                           P5b ... as its RIGHT operand
#   P6   a destructure `var a, b = mk(4, 2);` of a `: P2` fn returning a P2 local (r4 read as the
#        multi-value slot)                                       P7  `mk(7, 42); var b = rethi();`
#   P8   a `: P2` fn's `return (x, 2);` — refused since 6.7.11 (a tuple is not the struct: the user's
#        decision, issues/archived/2026-10-08-struct-operator-results.md #4), on cx as natively, once
#                                                                P8b `ret2(x, 2);` received as `var p: P2 = mr(4);`
#   P9   a 13-argument callee returning a pair (arguments 11 and 12 ride r14 / r15, the emitters'
#        temps)                                                  P10 a pair call as the 13th argument
#   P11  a field of a call result `mk(4, 2).y`                   P12 a callee whose `defer` makes a
#        6-argument call (r3..r8, r4 included) after the pair is loaded
#   P13  a frame past 64 KiB (the slot offset needs the movhi half)
#   P14  `return mk(x, 2);` forwarded                            P15 a generic `idp<T>` returning T = P2
#   P16  a `#regalloc` callee                                    P17 a 12-byte struct (a pair whose
#        high word is 4 bytes)
#   R1   a top-level `var G: P2 = mk(4, 2);` is refused on cx exactly as natively (no frame), once
# Anti-vacuous: the native leg of every row is its control, and the row count is checked.
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and — unless CYCC_CX is set — the cx
# compiler from THIS tree's src/main_cx.cyr, and cxvm from programs/cxvm.cyr (CXVM overrides it). A
# cx-backend mutation is picked up by running the gate from a mutated COPY of the tree with the
# real build/cycc, or by passing the mutant as CYCC_CX.
#
# MUTATION LEDGER (6.7.8, each a scratch copy of the tree, its cycc_cx passed as CYCC_CX; measured,
# the real tree green 42/42):
#   MX1 the high word through r1 in both emitters (the f64v2 pair's register)
#       -> RED P6 P7 P8 P8b (4; the struct pair and the multi-value slot no longer meet — every
#          struct-to-struct row stays green, as it must); struct_pair_multi_value_crossing.sh run
#          from the copy: its cx leg RED X1-X7 X9 + T3 (9)
#   MX2 the callee's EFLLOAD_STRUCT_INT_PAIR loads lo / hi swapped
#       -> RED 17: every pair row but P1 (x + y is symmetric) and P8 / P8b (a multi-value
#          producer); cx_crossos_rows_run.sh RED 11 (R5, R6, R8 x 9)
#   MX3 EFLSTORE_STRUCT_INT_PAIR (the receive) back to its ERR_MSG stub
#       -> RED 18: every receiving row does not build on cx (P6 / P7 receive no struct);
#          cx_crossos_rows_run.sh RED 13 (R5, R6, every R8 file)
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "${CYCC:-$ROOT/build/cycc}")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
G=cx_struct_pair
[ -x "$CC" ] || { echo "SKIP: $G — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: $G — no timeout(1) (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0 2>/dev/null || true

if [ -n "$CYCC_CX" ]; then
    [ -x "$CYCC_CX" ] || { echo "FAIL: $G — CYCC_CX=$CYCC_CX is not executable"; exit 1; }
    CX=$CYCC_CX
else
    CX=$T/cycc_cx
    "$CC" < src/main_cx.cyr > "$CX" 2> "$T/eb"; chmod +x "$CX"
    [ -s "$CX" ] || { echo "FAIL: $G — cannot build the cx compiler from src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi
if [ -n "$CXVM" ]; then
    [ -x "$CXVM" ] || { echo "FAIL: $G — CXVM=$CXVM is not executable"; exit 1; }
    VM=$CXVM
else
    VM=$T/cxvm
    "$CC" < programs/cxvm.cyr > "$VM" 2> "$T/eb"; chmod +x "$VM"
    [ -s "$VM" ] || { echo "FAIL: $G — cannot build cxvm from programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# row NAME WANT WHAT SOURCE — native, then cxvm; each must exit WANT.
row() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.x" 2> "$T/$1.xe" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$1.x" ]; then bad "$3 (native): does not build: $(grep -m1 '^error' "$T/$1.xe")"
    else
        chmod +x "$T/$1.x"; got=0; timeout 30 "$T/$1.x" > /dev/null 2>&1 || got=$?
        if [ "$got" = "$2" ]; then ok "$3 (native): exit $got"; else bad "$3 (native): exit $got, want $2"; fi
    fi
    rc=0; "$CX" < "$T/$1.cyr" > "$T/$1.cyx" 2> "$T/$1.ce" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$1.cyx" ]; then bad "$3 (cx): does not build: $(grep -m1 '^error' "$T/$1.ce")"
    else
        got=0; timeout 30 "$VM" < "$T/$1.cyx" > "$T/$1.co" 2>&1 || got=$?
        if [ "$got" = "$2" ]; then ok "$3 (cx): exit $got"; else bad "$3 (cx): exit $got, want $2 $(grep -m1 '^cxvm:' "$T/$1.co")"; fi
    fi
}
# refused NAME FRAGMENT WHAT SOURCE — native and cx both refuse, once, with FRAGMENT, no artifact.
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    for leg in native cx; do
        if [ "$leg" = native ]; then c=$CC; else c=$CX; fi
        rc=0; "$c" < "$T/$1.cyr" > "$T/$1.$leg" 2> "$T/$1.$leg.e" || rc=$?
        n=$(grep -c '^error' "$T/$1.$leg.e")
        if [ "$rc" -eq 0 ]; then bad "$3 ($leg): BUILT (rc 0)"
        elif ! grep -qF "$2" "$T/$1.$leg.e"; then bad "$3 ($leg): refused, but not as expected: $(grep -m1 '^error' "$T/$1.$leg.e")"
        elif [ "$n" -ne 1 ]; then bad "$3 ($leg): $n error lines (want 1)"
        else ok "$3 ($leg): refused once"; fi
    done
}

P='struct P2 { x; y; }\nfn mk(a, b): P2 { var p: P2; p.x = a; p.y = b; return p; }\n'
# A one-argument producer: its high word (x * 10 + 2) is in no argument register, so a consumer
# reading r4 / rdx / x2 sees the pair's word or nothing (a two-argument `mk(a, b)` leaves b in r4).
P1='struct P2 { x; y; }\nfn mk1(x): P2 { var p: P2; p.x = x; p.y = x * 10 + 2; return p; }\n'
E='var r = main();\nsyscall(60, r);\n'

row p1 42 "P1: the issue's repro verbatim" 'struct P2 { x; y; }\nfn p2(a, b): P2 { var r: P2 = P2 { a, b }; return r; }\nfn main(): i64 {\n    var q: P2 = p2(20, 22);\n    return q.x + q.y;\n}\nvar r = main();\nsyscall(60, r);\n'
row p1b 42 "P1b: \`var q: P2 = mk(4, 2);\`, order-sensitive" "${P}fn main(): i64 { var q: P2 = mk(4, 2); return q.x * 10 + q.y; }\n$E"
row p2 42 "P2: \`q = mk(4, 2);\` into an existing P2" "${P}fn main(): i64 { var q: P2 = mk(0, 0); q = mk(4, 2); return q.x * 10 + q.y; }\n$E"
row p3 42 "P3: \`var r = mk(4, 2);\` (inferred)" "${P}fn main(): i64 { var r = mk(4, 2); return r.x * 10 + r.y; }\n$E"
row p4 42 "P4: a method's 16 B result \`p.sw()\`" "${P}impl P2 { fn sw(self): P2 { var t: P2; t.x = self.y; t.y = self.x; return t; } }\nfn main(): i64 { var p: P2 = P2 { 2, 4 }; var q: P2 = p.sw(); return q.x * 10 + q.y; }\n$E"
row p5 42 "P5: a call result as an operator's left operand \`mk(9, 7) - s\`" "${P}fn P2_sub(a: P2, b: P2): i64 { return (a.x - b.x) * 10 + (a.y - b.y); }\nfn main(): i64 { var s: P2 = mk(5, 5); return mk(9, 7) - s; }\n$E"
row p5b 42 "P5b: ... as its right operand \`s - mk(1, 3)\`" "${P}fn P2_sub(a: P2, b: P2): i64 { return (a.x - b.x) * 10 + (a.y - b.y); }\nfn main(): i64 { var s: P2 = mk(5, 5); return s - mk(1, 3); }\n$E"
row p6 42 "P6: \`var a, b = mk1(4);\` (the high word read as the multi-value slot)" "${P1}fn main(): i64 { var a, b = mk1(4); if (a != 4) { return 1; } return b; }\n$E"
row p7 42 "P7: \`mk1(4); var b = rethi();\`" "${P1}fn main(): i64 { mk1(4); var b = rethi(); return b; }\n$E"
refused p8 "returns that struct — \`(a, b)\` is a tuple, another type" "P8: a \`: P2\` fn's \`return (x, 2);\` is refused (6.7.11)" "struct P2 { x; y; }\nfn mt(x): P2 { return (x, 2); }\nfn main(): i64 { var p: P2 = mt(4); return p.x * 10 + p.y; }\n$E"
row p8b 42 "P8b: a \`: P2\` fn's \`ret2(x, 2);\` received as the struct" "struct P2 { x; y; }\nfn mr(x): P2 { ret2(x, 2); }\nfn main(): i64 { var p: P2 = mr(4); return p.x * 10 + p.y; }\n$E"
row p9 42 "P9: a 13-argument callee returning a pair (args 11 / 12 in r14 / r15)" "struct P2 { x; y; }\nfn m13(a, b, c, d, e, f, g, h, i, j, k, l, m): P2 { var p: P2; p.x = a + b + c + d + e + f + g + h + i + j + k; p.y = l * 100 + m; return p; }\nfn main(): i64 { var q: P2 = m13(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13); if (q.x != 66) { return 1; } if (q.y != 1213) { return 2; } return 42; }\n$E"
row p10 42 "P10: a pair call as the 13th argument (a by-value P2)" "${P}fn t13(a, b, c, d, e, f, g, h, i, j, k, l, p: P2): i64 { if (a + b + c + d + e + f + g + h + i + j + k + l != 78) { return 1; } return p.x * 10 + p.y; }\nfn main(): i64 { return t13(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, mk(4, 2)); }\n$E"
row p11 42 "P11: a field of a call result \`mk(4, 2).x\`" "${P}fn main(): i64 { return mk(4, 2).x * 10 + mk(4, 2).y; }\n$E"
row p12 42 "P12: a pair loaded, then a defer's 6-argument call before the return" "${P}var cnt = 0;\nfn clob(a, b, c, d, e, f): i64 { cnt = cnt + 1; return a + b + c + d + e + f; }\nfn md(x): P2 { defer { clob(1, 2, 3, 4, 5, 6); } var p: P2; p.x = x; p.y = 2; return p; }\nfn main(): i64 { var q: P2 = md(4); return q.x * 10 + q.y + (cnt - 1) * 100; }\n$E"
row p13 42 "P13: a frame past 64 KiB" "struct P2 { x; y; }\nfn deep(x): P2 { var big: i64[9000]; big[0] = 1; big[8999] = 5; var p: P2; p.x = x; p.y = big[8999] - 3; return p; }\nfn main(): i64 { var big2: i64[9000]; big2[8990] = 7; var q: P2 = deep(4); return q.x * 10 + q.y + big2[8990] - 7; }\n$E"
row p14 42 "P14: \`return mk(x, 2);\` forwarded" "${P}fn fw(x): P2 { return mk(x, 2); }\nfn main(): i64 { var q: P2 = fw(4); return q.x * 10 + q.y; }\n$E"
row p15 42 "P15: a generic \`idp<T>\` returning T = P2" "${P}fn idp<T>(v: T): T { return v; }\nfn main(): i64 { var p: P2 = P2 { 4, 2 }; var q: P2 = idp(p); return q.x * 10 + q.y; }\n$E"
row p16 42 "P16: a \`#regalloc\` callee" "struct P2 { x; y; }\n#regalloc\nfn rg(a, b): P2 { var s = a + b; var p: P2; p.x = s - b; p.y = b; return p; }\nfn main(): i64 { var q: P2 = rg(4, 2); return q.x * 10 + q.y; }\n$E"
row p17 42 "P17: a 12-byte struct \`{ a: i64; b: i32; }\`" "struct P12 { a: i64; b: i32; }\nfn m12(a, b): P12 { var p: P12; p.a = a; p.b = b; return p; }\nfn main(): i64 { var q: P12 = m12(4, 2); return q.a * 10 + q.b; }\n$E"
refused r1 "returns a struct by value, and a struct result needs storage in a fn's frame" "R1: a top-level \`var G: P2 = mk(4, 2);\`" "${P}var G: P2 = mk(4, 2);\nsyscall(60, G.x);\n"

WANT=42
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: $G — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: $G — $pass/$WANT rows: cx returns and receives a 9-16 B struct in r0:r4, natively and on cxvm alike (receives, a method, operator operands, the multi-value crossings, 13 arguments, defer, a deep frame, generics, #regalloc, a 12-byte struct; the top-level refusal unchanged)"
exit 0
