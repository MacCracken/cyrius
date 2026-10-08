#!/bin/sh
# tests/gates/frontend/field_compound_checked.sh — 6.7.5 (B8)
#
# COMPOUND ASSIGNMENT ON EVERY LVALUE FORM (BACKLOG-13). `h.n += 4` was `expected '=', got '+'` on
# every field. The user's decisions (2026-10-08): every compound operator on every lvalue form; the
# lvalue's ADDRESS is computed ONCE, BEFORE the right-hand side, as `a[i] OP= v` already did (a
# plain `x.f = e` evaluates `e` first, and stays so). The runtime half is
# tests/tcyr/crossos/field_compound_values.tcyr, which this gate also builds and runs (A rows).
#
#   R  refused once, by name: a bool field (B2's rule), a struct-typed field, a field of a call's
#      result (`mk(3).n += 1`, `b.mk(4).n += 5` — and `= 5`, which was "expected ';', got '='"),
#      `E.A += 1`, an unknown field, an untyped base; and (R10-R16, the user's decision) OP= on a
#      STRUCT VALUE — an inline local of any size, an address-passed by-value parameter, an inline
#      global, a for step, a top-level statement: it integer-operated on the first word and never
#      called `T_add` (13 where `a = a + b` gives 33). H: a handle keeps its 6.6.17 pointer step.
#      (u128 and SIMD-vector OP= are filed, not refused here.)
#   W  the float rules of 6.6.11 on a field: an f64 field with an integer right operand warns
#      (kind 1), an f32 one with an f64 right operand (kind 5); an i8 field `+= 1` does not
#   X  `--syntax-only` (what `cyrius lint` runs): a struct the file cannot see, or a field it does
#      not know, takes `OP= e` silently, as it takes `= e` (no invented syntax error)
#   D  `*p OP= v` at word width (the address once), at top level; the rest are tcyr Q rows
#   F  a classic-for step takes a field / `*p` destination, `=` and `OP=` (the rest are tcyr T rows):
#      at top level; a struct field refused there too; a struct of another type refused by name (the
#      step's `)` reaches the struct-copy sources); junk before the `)` reported
#   C  `>>>=` (the eleventh operator, the arithmetic shift) in a const fn run in const contexts;
#      T: a mistyped `x >>> 2;` names the token (it said "got unknown")
#   A  ANTI-VACUOUS: the tcyr on x86_64 under the default pipeline, CYRIUS_IR=1, CYRIUS_IR=3 and
#      CYRIUS_DCE=1, and with compilers built from this tree on aarch64 (qemu) and cx (cxvm); plus
#      the address-once order row on its own (112 where a plain store gives 101)
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-08):
#   M1 `_fld_compound` without `_asg_cstep = ps`          -> RED A (tcyr S1 S2 S3: a `*T` field steps 1)
#   M2 no GFFK -> f64 / f32 mapping                       -> RED A (tcyr L1-L8) and W1 W2 (no warning)
#   M3 the field width never negated (unsigned load)      -> RED A (tcyr D6 D7)
#   M4 an 8-byte store into every field                   -> RED A (tcyr D5 D9: the neighbours)
#   M5 the address taken AFTER the right-hand side        -> RED A (tcyr O1) and O1 (101, not 112)
#   M6 the two --syntax-only arms without the OP= pair    -> RED X1 X2 ("expected '='")
#   M7 the slice OP= arm removed                          -> RED A (the tcyr does not build: F11)
#   R-a `_asg_temp_refused` not called by `_stmt_method_call` -> RED R4 R5 ("expected ';'")
#   R-b no struct-field refusal                           -> RED R2 (it BUILDS)
#   R-c no bool-field refusal                             -> RED R1 (it BUILDS)
#   M8 `_ce_cop` skipping 152 (the evaluator's own list)  -> RED C1 and A (tcyr A7 refused at the
#      definition: the values file does not build)
#   M8b no EASHRCL arm in `_asg_compound_op`              -> RED A (tcyr A1-A6 A9: the value unchanged)
#   M8c 152 dropped from the shared `_is_cop_tok`        -> RED C1 and A (the values file does not build)
#   M9 `_deref_store` loading nothing (rax = the address) -> RED D1 and A (tcyr Q1-Q7)
#   M10 `_fsc_src` told `;` in a for step (no terminator) -> RED F3 (it BUILDS: one word of `q`) and A
#      (tcyr T5: 52, the 6.6.20 one-word class; T6 T7)
#   M10b `_for_step_replay` without the field arm         -> RED F1-F4 and A (the values file does not build)
#   M10c `_for_step_replay` without the `*p` arm          -> RED A (the values file does not build: T8 T9)
#   M10d `_fsc_expr` not arming `_fla_stp` for a step     -> RED A (tcyr T6: one word of `z.k`, 76)
#   M11 `_asg_struct_refused` never refusing              -> RED R10-R16 (each BUILDS; R10 exits 13, measured)
#   M12 `_err_in_sync` without its `_tn_once` latch       -> RED R17 R18 (2 error lines, one per instance)
# (The IR_RAW_EMIT record at the address and the flags-tracker clear after the load are defensive:
# no row kills them — measured.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=field_compound_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
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
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
warns() {   # <name> <fragment> <what> <source>: builds, and warns with the fragment
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"
    elif grep '^warning' "$T/$1.err" | grep -qF "$2"; then ok "$3: warns"
    else bad "$3: no warning '$2'"; fi
}
quiet() {   # <name> <what> <source>: builds with no warning at all
    printf '%b' "$3" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$2: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"
    elif grep -q '^warning' "$T/$1.err"; then bad "$2: warned: $(grep '^warning' "$T/$1.err" | head -1)"
    else ok "$2: no warning"; fi
}
synonly() {   # <name> <what> <source>: --syntax-only exits 0 with no error line
    printf '%b' "$3" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ] || grep -q '^error' "$T/$1.err"; then bad "$2: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$2: silent"; fi
}
# tcyr <what> <compiler> <runner> [ENV=V]: build the values file, run it, require "0 failed".
TC=tests/tcyr/crossos/field_compound_values.tcyr
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
SH='struct H { n; m; }\nstruct B { k; }\nimpl B { fn mk(self, v): H { var h = H { v, 2 }; return h; } }\nfn mk(v): H { var h = H { v, 2 }; return h; }\n'
ST='struct I { a; b; }\nstruct O { x; i: I; }\n'

refused r01 "compound assignment to bool field 'ok' is refused - its result is not a bool" "R1: a bool field (B2)" "struct B1 { ok: bool; n; }\nfn main(): i64 { var b = B1 { true, 1 }; b.ok += 1; return 0; }$E"
refused r02 "compound assignment to struct field 'i' is refused - a struct value is not an integer or a float (write \`a = a + b\`)" "R2: a struct-typed field" "${ST}fn main(): i64 { var o = O { 1, 2, 3 }; o.i += 1; return 0; }$E"
refused r03 "cannot assign to a field of a call result: the result is a temporary" "R3: mk(3).n += 1" "${SH}fn main(): i64 { mk(3).n += 1; return 0; }$E"
refused r04 "cannot assign to a field of a call result: the result is a temporary" "R4: b.mk(4).n += 5" "${SH}fn main(): i64 { var b = B { 1 }; b.mk(4).n += 5; return 0; }$E"
refused r05 "cannot assign to a field of a call result: the result is a temporary" "R5: b.mk(4).n = 5 (was \"expected ';'\")" "${SH}fn main(): i64 { var b = B { 1 }; b.mk(4).n = 5; return 0; }$E"
refused r06 "cannot assign to enum constant 'A'" "R6: E.A += 1" "enum E { A; B; }\nfn main(): i64 { E.A += 1; return 0; }$E"
refused r07 "unknown field 'zz' on struct 'H'" "R7: an unknown field" "${SH}fn main(): i64 { var h = H { 1, 2 }; h.zz += 1; return 0; }$E"
refused r08 "no struct type in scope for 'e'; a '.field' assignment needs its struct declaration" "R8: an untyped base" "fn main(): i64 { var e = 0; e.size += 1; return 0; }$E"
PADD='struct P { x; y; }\nfn P_add(a: P, b: P): P { var r: P; r.x = a.x + b.x; r.y = a.y + b.y; return r; }\n'
SV="compound assignment to struct"
SVT="is refused - a struct value is not an integer or a float (write \`a = a + b\`)"
refused r10 "$SV 'a' $SVT" "R10: a struct local, a += b (13 where a = a + b gives 33)" "${PADD}fn main(): i64 { var a = P { 1, 2 }; var b = P { 10, 20 }; a += b; return a.x + a.y; }$E"
refused r11 "$SV 'G' $SVT" "R11: an inline struct global" "${PADD}var G = P { 1, 2 };\nfn main(): i64 { var b = P { 10, 20 }; G += b; return G.x; }$E"
refused r12 "$SV 'a' $SVT" "R12: an address-passed by-value parameter" "${PADD}fn f(a: P): i64 { a -= 1; return a.x; }\nfn main(): i64 { var b = P { 10, 20 }; return f(b); }$E"
refused r13 "$SV 'a' $SVT" "R13: an 8-byte struct local" "struct S8 { v; }\nfn main(): i64 { var a: S8; a.v = 1; a *= 4; return a.v; }$E"
refused r14 "$SV 'a' $SVT" "R14: a for step" "${PADD}fn main(): i64 { var a = P { 1, 2 }; for (var i = 0; i < 1; a += 1) { i = 1; } return a.x; }$E"
refused r15 "$SV 'G' $SVT" "R15: a top-level statement" "${PADD}var G = P { 1, 2 };\nG <<= 1;\nsyscall(60, G.x);\n"
refused r16 "$SV 'a' $SVT" "R16: an 8-byte by-value parameter" "struct S8 { v; }\nfn f(a: S8): i64 { a += 4; return a.v; }\nfn main(): i64 { var b: S8; b.v = 3; return f(b); }$E"
# 6.7.5 review: a generic base and its instances parse the same tokens, so a refusal inside a generic
# body was reported once per instantiation; `_err_in_sync` reports a token once (as B2's bool does).
refused r17 "$SV 'a' $SVT" "R17: a struct OP= in a generic fn instantiated twice is reported once" "struct I { a; b; }\n${PADD}fn g<T>(v: T): i64 { var a = P { 1, 2 }; a += 1; return a.x; }\nfn main(): i64 { var i = I { 1, 2 }; return g(1) + g(i); }$E"
refused r18 "compound assignment to struct field 'i' is refused" "R18: a struct-field OP= in a generic fn instantiated twice is reported once" "${ST}fn g<T>(v: T): i64 { var o = O { 0, 1, 2 }; o.i += 1; return o.x; }\nfn main(): i64 { var i = I { 1, 2 }; return g(1) + g(i); }$E"
exits h01 48 "H1: handles keep the pointer step: a \`*T\` param and global step sizeof(P), a pointer-mode local adds bytes" "${PADD}var GP: *P = 0;\nfn bits(v) { return v; }\nfn f(p: *P): i64 { p += 1; return p; }\nfn main(): i64 { var a: P[3]; var b0 = bits(&a); var q: P = b0; q += 16; GP = b0; GP += 1; return bits(f(b0)) - b0 + bits(GP) - b0 + bits(q) - b0; }$E"

# Two refusals in a row are both reported: each leaves the parse in sync.
printf '%b' "${ST}struct B1 { ok: bool; n; }\nfn main(): i64 { var o = O { 1, 2, 3 }; o.i += 1; var b = B1 { true, 1 }; b.ok |= 1; return 0; }$E" > "$T/r09.cyr"
build r09
if [ "$(grep -c '^error' "$T/r09.err")" -eq 2 ]; then ok "R9: a struct field then a bool field: both reported"
else bad "R9: want 2 error lines: $(grep '^error' "$T/r09.err" | tr '\n' '|')"; fi

warns w01 "f64 arithmetic with a non-f64 right operand" "W1: an f64 field *= an integer (kind 1)" "struct P { x: f64; y: f64; }\nfn main(): i64 { var p = P { 1.5, 2.0 }; p.x *= 4; return 0; }$E"
warns w02 "f32 arithmetic with a non-f32 right operand" "W2: an f32 field += an f64 (kind 5)" "struct Q { s: f32; t; }\nfn main(): i64 { var q = Q { f32_from(1.5), 1 }; q.s += 1.5; return 0; }$E"
quiet w03 "W3: an i8 field += 1, an f64 field += an f64" "struct W { c: i8; d; }\nstruct P { x: f64; }\nfn main(): i64 { var w = W { 1, 2 }; w.c += 1; var p = P { 1.5 }; p.x += 2.5; return w.c; }$E"

synonly x01 "X1: a struct the file cannot see (e.size += 1)" "fn k(): i64 { e.size += 1; ee.size *= 2; return 0; }\n"
synonly x02 "X2: a field the struct does not declare (h.zz += 1)" "struct H { n; m; }\nfn f(h: H): i64 { h.zz += 1; h.yy <<= 2; return 0; }\n"

exits c01 3 "C1: >>>= in a const fn: a const, an array size, #assert" 'const fn h(x): i64 { var y = x; y >>>= 1; return y; }\nconst K = h(0 - 6);\nvar arr: i64[h(16)];\n#assert K == 0 - 3\nfn main(): i64 { arr[7] = 0 - K; return arr[7]; }\nsyscall(60, main());\n'
refused t01 "expected '=', got '>>>'" "T1: a mistyped \`x >>> 2;\` names the token" "fn main(): i64 { var x = 1; x >>> 2; return x; }$E"

exits d01 9 "D1: \`*p += 2;\` at top level" 'var v = 5;\nvar p = &v;\nv = 7;\n*p += 2;\nsyscall(60, v);\n'

exits f01 55 "F1: a field step at top level" 'struct H { n; m; }\nvar G = H { 0, 0 };\nvar c = 0;\nc = 0;\nfor (G.n = 0; G.n < 5; G.n += 1) { c = c + 1; }\nsyscall(60, c * 10 + G.n);\n'
refused f02 "compound assignment to struct field 'i' is refused" "F2: a struct-typed field step" "${ST}fn main(): i64 { var o = O { 0, 1, 2 }; for (o.x = 0; o.x < 1; o.i += 1) { o.x = 1; } return 0; }$E"
refused f03 "cannot copy 'q' into a struct field of a different struct type: 'i'" "F3: a step copying a struct of another type" "${ST}struct J { a; b; }\nfn main(): i64 { var o = O { 0, 1, 2 }; var q = J { 5, 6 }; for (o.x = 0; o.x < 1; o.i = q) { o.x = 1; } return o.i.b; }$E"
refused f04 "expected ')', got number" "F4: junk before a field step's ')'" "${SH}fn main(): i64 { var h = H { 0, 0 }; for (h.n = 0; h.n < 3; h.n += 1 2) { } return h.n; }$E"

exits o01 112 "O1: OP= takes the address before the right-hand side (GP.n += repoint())" 'struct H { n; m; }\nvar A = H { 10, 0 };\nvar B = H { 20, 0 };\nvar GP: *H = &A;\nfn repoint(): i64 { GP = &B; return 1; }\nfn main(): i64 { GP.n += repoint(); return A.n * 10 + B.n / 10; }\nsyscall(60, main());\n'
exits o02 101 "O2: a plain store evaluates the right-hand side first (unchanged)" 'struct H { n; m; }\nvar A = H { 10, 0 };\nvar B = H { 20, 0 };\nvar GP: *H = &A;\nfn repoint(): i64 { GP = &B; return 1; }\nfn main(): i64 { GP.n = GP.n + repoint(); return A.n * 10 + B.n / 10; }\nsyscall(60, main());\n'

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
echo "PASS: $G — compound assignment on every lvalue form: refusals (R), float warnings (W), --syntax-only (X), values on x86_64 / IR / DCE / aarch64 / cx (A)"
