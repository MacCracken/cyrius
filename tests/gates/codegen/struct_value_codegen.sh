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
#   Q  a PARENTHESISED struct source into a struct-typed field (`o.i = (z.k)`: 72 where 78 is
#      right; a for step too), a struct variable (`w = (j)`: one word) or a declaration
#      (`var q: K = (z.k)`: SIGSEGV), in a fn and at top level: transparent at every destination
#      (`_fsc_paren`, `_asg_paren`, `_scv_peel` + `_sc_pwrap` + `_fnc_agg`, `_sci_pname`,
#      `_gci_src`); a source of another struct is refused once, by name, as unwrapped
#   O  a struct result over 8 B as the RIGHT operand of an address-passed operator parameter
#      (`s - mk3(4)`, `p + p.dup()`, by-value or `*S`, bare or wrapped) pushed its first word:
#      SIGSEGV. The operand asks for the result's temp (`_op_big_arm` / `_op_big_take`); at top
#      level, where there is no frame, it is refused by name
#   S  a `: Str` field as a source (`bq(h.name)` with `fn bq(b: Q)`, `var q: Q = h.name;`) compiled
#      and read Q's fields out of the Str's header and past it. It is a Str handle (`_fls_note`):
#      into a struct of another type — an argument at either width, a declaration in a fn or at
#      top level, an assignment, a field, an operator operand, wrapped or not — refused by name;
#      into a Str, an untyped slot or a handle (6.6.16's rebind) unchanged
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
#   M-Q1 `_fsc_src` without the `_fsc_paren` arm             -> RED Q1, Q6 (BUILT), A1-A6 (tcyr Q1-Q7)
#   M-Q2 `_try_aggregate_copy_assign` without its wrap arm   -> RED Q2, Q5 (BUILT), A1-A6 (tcyr Q9 Q10
#       Q14 Q27)
#   M-Q3 `_try_struct_call_assign` without its wrap arm      -> RED Q7 (BUILT), A1-A6 (tcyr Q11; Q24
#       off cx)
#   M-Q4 `_pcmpe_struct_assign` without its wrap arm         -> RED A1-A5 (the values file does not
#       build: a 9-16 B method result in a wrap reached `_sc_whole` as "no frame" -4, and was
#       refused as at top level), A6 (tcyr Q8)
#   M-Q5 `_sc_whole` without `_sc_pwrap`                     -> RED Q8 (BUILT), A1-A6 (tcyr Q19 Q20;
#       native SIGSEGV after)
#   M-Q6 `_scv_arm` without `_scv_peel`                      -> RED Q2 (139), Q8 Q9 (BUILT), A1-A6
#       (tcyr Q17; native SIGSEGV after)
#   M-Q7 `_fnc_agg` never taking `_sc_fcw`                   -> RED Q8 (BUILT), A1-A5 (native SIGSEGV
#       at tcyr Q18); A6 green (cx binds the temp's address, measured)
#   M-Q8 `_fla_take` without `_fla_inparen`                  -> RED Q2 (139), Q9 (BUILT), A1-A6 (tcyr Q17)
#   M-Q9 `_try_struct_copy_init` refusing a wrapped name     -> RED Q4 (BUILT), A1-A6 (tcyr Q16 Q21)
#   M-Q10 `_gci_src` without the wrap                         -> RED Q3 (139), A1-A6 (tcyr Q27)
#   M-O1 `_op_rhs` without `_op_big_arm`                     -> RED O1-O3 (139), O4 O5 (BUILT), A1-A6
#       (native SIGSEGV; cx tcyr O1-O3 read the first word as an address)
#   M-O2 `_op_big_arm` not setting `_sc_fcw` (free calls)    -> RED O1 O3 (139), A1-A6 (tcyr O1 O2)
#   M-O3 `_op_big_arm` not setting `_sc_want` (9-16 B methods) -> RED O2 O3 (139), A1-A5 (native
#       SIGSEGV at tcyr O8); A6 green (cx has no 16-byte pair return)
#   M-O4 `_op_big_take` without the top-level pair-call refusal -> RED O5 (BUILT)
#   M-S1 `_fls_note` recording nothing                       -> RED S1-S8 (each BUILT)
#   M-S2 `_fls_asg_check` without the handle exemption        -> RED S9 (the rebind refused)
#   M-S3 `_push_struct_expr_arg` without its `_fls` check     -> RED S1 S8 (BUILT)
#   M-S4 `_sc_var_receive` without its `_fls` check           -> RED S2 (BUILT)
#   M-S5 `_fsc_expr` without its `_fls` check                 -> RED S4 (BUILT)
#   M-S6 `_op_arg_check` without its `_fls` arm               -> RED S5 (BUILT)
#   M-S7 `_sarg_byval_small` without its `_fls` arm           -> RED S6 (BUILT)
#   M-S8 `_sc_global_mismatch` without its `_fls` check       -> RED S7 (BUILT)
#   M-S9 `_pcmpe_struct_assign` without `_fls_asg_check`      -> RED S3 (BUILT)
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
KQ='struct K { a; b; c; }\nstruct Q { a; b; c; }\nstruct O { n; i: K; }\nstruct Z { m; k: K; }\nfn mkq(v): Q { var t: Q = Q { v, v, v }; return t; }\n'
exits q01 0 "Q1: o.i = (z.k); o.i = (j); and a for step (the filed repro: 72 where 78)" "${KQ}fn main(): i64 { var z = Z { 1, 20, 25, 30 }; var j = K { 21, 26, 31 }; var o = O { 0, 0, 0, 0 }; o.i = (z.k); var r = o.i.a + o.i.b + o.i.c; o.i = (j); r = r + o.i.a + o.i.b + o.i.c; var i = 0; o.i = j; for (i = 0; i < 1; o.i = (z.k)) { i = i + 1; } return r + o.i.a + o.i.b + o.i.c - 228; }$E"
exits q02 0 "Q2: var q: K = (z.k); (SIGSEGV) and w = (j); (one word)" "${KQ}fn main(): i64 { var z = Z { 1, 20, 25, 30 }; var j = K { 21, 26, 31 }; var q: K = (z.k); var w = K { 0, 0, 0 }; w = (j); return q.a + q.b + q.c + w.a + w.b + w.c - 153; }$E"
exits q03 6 "Q3: var G: K = (A); at top level (SIGSEGV)" "${KQ}var A = K { 1, 2, 3 };\nvar G: K = (A);\nsyscall(60, G.a + G.b + G.c);\n"
refused q04 "cannot copy 'q' into a variable of a different struct/vector type: 'v'" "Q4: var v: K = (q) with q: Q" "${KQ}fn main(): i64 { var q = Q { 1, 2, 3 }; var v: K = (q); return v.a; }$E"
refused q05 "cannot copy 'q' into a variable of a different struct/vector type: 'v'" "Q5: v = (q) with q: Q" "${KQ}fn main(): i64 { var q = Q { 1, 2, 3 }; var v = K { 0, 0, 0 }; v = (q); return v.a; }$E"
refused q06 "cannot copy 'q' into a struct field of a different struct type: 'i'" "Q6: o.i = (q) with q: Q" "${KQ}fn main(): i64 { var q = Q { 1, 2, 3 }; var o = O { 0, 0, 0, 0 }; o.i = (q); return o.n; }$E"
refused q07 "cannot copy 'mkq' into a variable of a different struct/vector type: 'v'" "Q7: v = (mkq(5))" "${KQ}fn main(): i64 { var v = K { 0, 0, 0 }; v = (mkq(5)); return v.a; }$E"
refused q08 "fn return struct-id differs from declared var type" "Q8: var v: K = (mkq(5))" "${KQ}fn main(): i64 { var v: K = (mkq(5)); return v.a; }$E"
refused q09 "cannot copy 'k' into a variable of a different struct/vector type: 'v'" "Q9: var v: K = (z.k) with z.k: Q" "struct K { a; b; c; }\nstruct Q { a; b; c; }\nstruct Z { m; k: Q; }\nfn main(): i64 { var z = Z { 1, 2, 3, 4 }; var v: K = (z.k); return v.a; }$E"
exits o01 5 "O1: s - mk3(4) into *P3 operands (the filed repro: SIGSEGV)" "${P3S}fn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nfn main() { var s: P3 = P3 { 9, 9, 9 }; return s - mk3(4); }$E"
PT2='struct Pt { x; y; }\nfn Pt_add(a: Pt, b: Pt) { return a.x + b.x + a.y + b.y; }\nimpl Pt { fn dup(self): Pt { var t: Pt = Pt { self.x, self.y }; return t; } }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\n'
exits o02 6 "O2: p + p.dup() (the filed repro: SIGSEGV)" "${PT2}fn main() { var p: Pt = Pt { 1, 2 }; return p + p.dup(); }$E"
exits o03 15 "O3: p + (p.dup()) + p + mk2(3) wrapped and a rax:rdx free call" "${PT2}fn main() { var p: Pt = Pt { 1, 2 }; var a = p + (p.dup()); return a + (p + mk2(3)); }$E"
TLO="the right operand of 'Pt_add' is passed by address"
refused o04 "$TLO" "O4: G + G.dup() at top level (no frame)" "${PT2}var G: Pt = Pt { 1, 2 };\nvar r = G + G.dup();\nsyscall(60, r);\n"
refused o05 "$TLO" "O5: G + mk2(3) at top level (no frame)" "${PT2}var G: Pt = Pt { 1, 2 };\nvar r = G + mk2(3);\nsyscall(60, r);\n"
refused o06 "cannot pass 'mkq' to a parameter of a different struct type in a call to 'P3_sub'" "O6: s - mkq(4) with mkq: Q3" "${P3S}struct Q3 { x; y; z; }\nfn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nfn mkq(v): Q3 { var t: Q3 = Q3 { v, v, v }; return t; }\nfn main() { var s: P3 = P3 { 9, 9, 9 }; return s - mkq(4); }$E"
HSQ='include "lib/str.cyr"\nstruct H { name: Str; k; }\nstruct Q { a; b; c; }\nstruct S1 { v; }\nstruct O { n; q: Q; }\n'
HMK='alloc_init(); var h: H; h.name = str_from("abc"); h.k = 7;'
SPC="to a parameter of a different struct type in a call to"
SCP="into a variable of a different struct/vector type"
refused s01 "cannot pass 'name' $SPC 'bq'" "S1: bq(h.name), fn bq(b: Q) (the filed repro: built)" "${HSQ}fn bq(b: Q): i64 { return b.c; }\nfn main(): i64 { $HMK return bq(h.name); }$E"
refused s02 "cannot copy 'name' $SCP: 'q'" "S2: var q: Q = h.name; (the filed repro: built)" "${HSQ}fn main(): i64 { $HMK var q: Q = h.name; return q.c; }$E"
refused s03 "cannot copy 'name' $SCP: 'q'" "S3: q = h.name; into an inline Q" "${HSQ}fn main(): i64 { $HMK var q = Q { 1, 2, 3 }; q = h.name; return q.c; }$E"
refused s04 "cannot copy 'name' into a struct field of a different struct type: 'q'" "S4: o.q = h.name;" "${HSQ}fn main(): i64 { $HMK var o = O { 0, 1, 2, 3 }; o.q = h.name; return o.n; }$E"
refused s05 "cannot pass 'name' $SPC 'Q_add'" "S5: q + h.name, fn Q_add(a: Q, b: Q)" "${HSQ}fn Q_add(a: Q, b: Q): i64 { return a.c + b.c; }\nfn main(): i64 { $HMK var q = Q { 1, 2, 3 }; return q + h.name; }$E"
refused s06 "cannot pass 'name' $SPC 'b1'" "S6: b1(h.name), an 8-byte by-value parameter" "${HSQ}fn b1(b: S1): i64 { return b.v; }\nfn main(): i64 { $HMK return b1(h.name); }$E"
refused s07 "cannot copy 'name' (a Str field) into a global of a different struct type" "S7: var GQ: Q = GH.name; at top level" "${HSQ}var GH: H = H { 0, 7 };\nvar GQ: Q = GH.name;\nsyscall(60, GQ.c);\n"
refused s08 "cannot pass 'name' $SPC 'bq'" "S8: bq((h.name)), fn bq(b: *Q)" "${HSQ}fn bq(b: *Q): i64 { return b.c; }\nfn main(): i64 { $HMK return bq((h.name)); }$E"
exits s09 0 "S9: a handle Q rebinds to h.name (6.6.16 C2), untouched" "${HSQ}fn main(): i64 { $HMK var q: Q = alloc(24); q = h.name; return 0; }$E"
exits s10 12 "S10: u = h.name; o.s = h.name; into Str destinations" "${HSQ}struct OS { n; s: Str; }\nfn main(): i64 { $HMK var u: Str = str_from(\"x\"); u = h.name; var o: OS; o.n = 0; o.s = h.name; var w: Str = (h.name); return str_len(u) * 4 + str_len(o.s) - str_len(w); }$E"
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
