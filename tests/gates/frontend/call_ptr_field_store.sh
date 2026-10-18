#!/bin/sh
# Gate: a field of a `: *T` call's result is an lvalue — `gp().n = 5;` stores through the returned pointer (6.7.13,
# the user's decision D8 (a), 2026-10-15; issues/archived/2026-10-08-field-store-through-pointer-returning-call-refused.md).
#
# THE DEFECT (measured on the 6.7.13 structs lane before the fix, 0d09e732, every target): with `fn gp(): *H`,
#     gp().n = 5;   gp().m += 5;   gp().h.n = 5;   gpg<H>().n = 5;   o.gp().n = 5;
# were refused "cannot assign to a field of a call result: the result is a temporary", while the READ `gp().n` (6.6.17)
# and a method's `o.gp().n` (6.7.11 D43) go through the pointer, and `var p: *H = gp(); p.n = 5;` writes the pointee.
# The reason is true only for a struct returned BY VALUE (its retptr / rax:rdx temporary).
#
# THE RULE (the user's decision D8 (a)): `=` and `OP=` (the address computed once, 6.7.5 B8) on a chain of fields of a
# `: *T` result — a free call, an explicit generic, a method, a `*T` field hop, a method's `*T` at the chain's end —
# store through the pointer, as the field store does through a `*T` local (`_cpf_try` hands the parked pointer to
# PARSE_FIELD_STORE's body, `_fst_on`). A by-value result keeps the refusal; an untyped `var p = gp();` is unchanged.
#
# ROWS: R0 the filed repro verbatim; R1 tests/tcyr/crossos/call_ptr_field_store.tcyr (its row count derived, floor
# 34) on x86_64 (plain, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu — EMULATION,
# not hardware), cx (cxvm) and PE (wine, a private prefix); X1-X6 refused (the message first, ONE `^error`, no
# warning, no binary) on the x86_64, aarch64, cx and PE compilers; T0-T5 (6.7.14) a top-level by-value call's
# field assignment refused once, by the no-frame refusal; F0-F6 (6.7.14) the same as a classic-for step (F0 the filed
# repro, runs; F1-F4 refused once; F5 F6 no assignment, "expected '='"); K1-K3 controls that compile and run on every leg;
# U1-U15 (6.7.15) a `.field` of an UNDEFINED fn's result named "undefined function 'undefd'" once (U1 / U2 the filed
# repros, their positions; U11 a later statement's error still reported; U12 --allow-undef still refuses it; U13-U15
# controls: a plain `undefd();` and an intrinsic keep their own paths); S1-S9 (6.7.15) --syntax-only, a field assignment
# on a call whose callee this file does not define parses silently (S1 the filed repro; S5-S7 a grammar error in its
# tail still reported; S8 / S9 controls: a by-value callee this file defines keeps "the result is a temporary");
# T6-T15 (6.7.15) a top-level METHOD returning a struct by value, its `*T` field subscripted, one error (T6 the filed
# repro; T13 its in-fn control, exit 5; T14 a genuine non-`*T` subscript in a fn keeps its refusal; T15 the next
# statement still checked).
#
# MUTATION LEDGER (2026-10-15; each mutant a scratch copy of the tree (src, lib, programs, this gate and its tcyr)
# with the one change, its cycc built from the mutated src, this gate run from the copy with CYCC= that cycc):
#   p0 the tree before the fix (0d09e732)          -> RED 26: R0 x7, R1 x7 (each refused "the result is a temporary"),
#                                                     K1-K3 x4
#   p1 `_cpf_try` returns 0 at once                -> RED 26: as p0
#   p2 `_mchain_ptr` without its `_cpf_try`        -> RED 7: R1 x7 (`o.gp().n = 5;` refused as a temporary; and
#                                                     struct_value_codegen.sh MP3)
#   p3 `_call_ptr_field` without its `_cpf_try`    -> RED 26: as p0
#   p5 `_cpf_asg_at` without its `op =` arm        -> RED 7: R1 x7 (`gpc().m += 5;` refused as a temporary)
#   p7 `_stmt_method_call` without its done return -> RED 7: R1 x7 ("expected ';'": the store had ended it)
#   p8 `_stmt_call_field` without its done return  -> RED 26: R0, R1, K1-K3 ("expected ';', got return")
#   real tree                                       -> GREEN
#   (6.7.14, 2026-10-17, the same procedure) `_stmt_call_field` without its `_tsc_n` skip -> RED 12: T0-T2 x4
#                                                     (2 error lines: the no-frame refusal, then "the result is a temporary")
#   the statement forms of the T0-T2 commit (54da1380: the skip on `=` / `OP=` only, no method arm) -> RED 12: T3-T5 x4
#   `_for_step_replay` without its `_step_call_field` arm -> RED 27: R1 x7 ("expected '=', got '('"), F0-F4 x4
#   `_cpf_try` ending every store at `;` (no `_cpf_step` term) -> RED 11: R1 x7, F0 x4 ("expected ';', got ')'")
#   `_cpf_try` disarming `_cpf_step` on any store              -> RED 7: R1 x7 (st_nested: the store inside the step's
#                                                     call disarmed the step, "expected ';', got ')'")
# (`_cpf_try`'s `beg != _cpf_st` is a guard no current path reaches: a closure's statements arm their own, and since
# 6.7.14 a for step arms its own too, `_step_call_field`.)
#
# 6.7.14 (the receives lane, unit R2; issues/archived/2026-10-16-callptr-statement-field-store-does-not-parse.md) — THE SAME STORE
# THROUGH A KNOWN `&f` CALLEE SPELLED `callptr`. A statement starting with an IDENT `fncallN` reaches the call statement's
# field arms (`_stmt_call_field` -> `_call_field` -> `_icall_stmt_chain`), so `fncall1(&gp, 5).b = 40;` stored through
# (6.7.13's D16 (a) with D8 (a)); `callptr` is token 137, and PARSE_STMT's 136-137 band sent its statement to PCMPE,
# which read `.b` as a value and left the `=` over: "expected ';', got '='" (`+= 40` "unexpected '='"; a by-value callee
# the same, where the fncall1 form is refused by name). PARSE_STMT now makes one call for token 137,
# `_stmt_callptr_field` (parse_expr.cyr): a call followed by `.name` takes `_stmt_call_field`, whose `_call_field`
# routes 137 to `_icall_stmt_chain` (no fncallN arity read: `callptr` is variadic). CP1 the filed repro verbatim (40);
# CP2 `+= 40`; CP3 / CP3c a by-value result refused by name once; CP4 `callptr(&mk3, 5).tot();` (control: worked
# before); CP5 the callee wrapped; CP6 two arguments; CP7 in a closure; CP8 at top level; CP9 a callee in a variable
# refused by name (D31); CP10 a read statement (control) — every row on x86_64 / aarch64 / cx / PE.
# tests/tcyr/crossos/fncall_struct_result.tcyr FC15 / FC16 carry the 40 / 40 rows to the real hosts. (2026-10-17, the
# same procedure)
#   c0 PARSE_STMT without its `_stmt_callptr_field` call (= the tree before) -> RED 32: CP1 CP2 CP5-CP8 x4 legs (did not
#                                                     build: expected ';' / unexpected '='), CP3 CP3c x4 (refused, but as
#                                                     expected ';' / unexpected '='); CP4 CP9 CP10 and the rows above green
#   c1 `_call_field` without its token-137 arm     -> RED 32, as c0 (`_call_dotted` wants an IDENT: not that shape, the
#                                                     cursor restored, the statement back on PCMPE)
#   c2 `_icall_stmt_chain` reading the fncallN digit for 137 -> RED 44: CP1-CP10 x4 (the arity check: "fncallN
#                                                     argument count does not match the N in its name")
# (6.7.15, the structs lane, unit S6; issues/2026-10-17-undefined-callee-field-assignment-names-no-undefined-fn.md; the
# same procedure, 2026-10-18)
#   u1 `_call_field` returning 0 for an unresolved callee (= the tree before) -> RED 47: U1-U11 x4 ("expected ';', got
#                                                     '.'" / "expected '=', got '('", then the end-of-compile refusal),
#                                                     U12 x3 (refused as before, but not naming the fn)
#   u2 `_call_undef` without its `_tsc_n` move    -> RED 32: the statement / step rows (U1 U2 U4 U6 U8-U11 x4: "the
#                                                     result is a temporary" or "expected ';'" after the named error)
#   u3 `_call_undef` without its intrinsic guard  -> RED 4: U14 x4 ("undefined function 'mulh64'")
# (6.7.15, unit S6; issues/2026-10-17-syntax-only-sibling-ptr-call-field-store-false-temporary.md; the same procedure)
#   s1 neither `_cf_unres` arm (= the tree before) -> RED 21: S1-S7 x3 (the false "the result is a temporary"; S5-S7
#                                                     its error in place of the tail's own)
#   s2 `_fn_nodef` answering 1 only for an unregistered callee -> RED 6: S1 S3 x3 (the callee registered by the line's
#                                                     earlier call)
#   s3 `_step_cf_tail` without its arm             -> RED 9: S1 S2 S6 x3
# (6.7.15, unit S6; issues/2026-10-17-toplevel-by-value-method-result-field-subscript-two-errors.md; the same procedure)
#   t1 `_method_chain`'s top-level arm stepping only its `.name` / `(..)` steps (= the tree before) -> RED 32: T6-T12,
#                                                     T15 x4 (the second, false "cannot subscript field 'p': it is not
#                                                     a *T field")
#
# Exit 1 = a row failed (or the compiler is missing); every leg that cannot run says so by name (a SKIP).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=call_ptr_field_store
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
rows=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

A64="$T/cc_a64"
QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$A64" 2> "$T/cc_a64.err" && [ -s "$A64" ]; then chmod +x "$A64"; QEMU=1
    else bad "src/main_aarch64.cyr did not build: $(grep '^error' "$T/cc_a64.err" | head -1 || true)"; fi
else echo "  SKIP the aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
CX=0
CXC="$T/cc_cx"
if "$CC" < src/main_cx.cyr > "$CXC" 2> "$T/cc_cx.err" && [ -s "$CXC" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$CXC" "$T/cxvm"; CX=1
else bad "src/main_cx.cyr or programs/cxvm.cyr did not build: $(grep '^error' "$T/cc_cx.err" "$T/cxvm.err" | head -1 || true)"; fi
WINE=0
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP the PE run leg — wine not installed (the PE refusals still run)"; skips=$((skips + 1)); fi

# compile <leg> <name>: $T/<name>.<leg> (+ .err); rc in $crc. x86_64:VAR=1 is the host compiler under VAR.
compile() {
    crc=0
    case $1 in
        x86_64)   timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        x86_64:*) env "${1#x86_64:}" timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        aarch64)  timeout 60 "$A64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        cx)       timeout 60 "$CXC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        pe)       CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
    esac
}
legs() {
    l="x86_64"
    [ "$QEMU" -eq 1 ] && l="$l aarch64"
    [ "$CX" -eq 1 ] && l="$l cx"
    echo "$l pe"
}
# execute <leg> <name>: runs $T/<name>.<leg>; exit in $got, the last output line in $last
execute() {
    got=0
    chmod +x "$T/$2.$1"
    case $1 in
        x86_64*) timeout 60 "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        aarch64) timeout 120 qemu-aarch64 "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        cx)      timeout 120 "$T/cxvm" < "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        pe)      cp "$T/$2.$1" "$T/$2.exe"
                 (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                     WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2.exe" > "$T/$2.$1.out" 2> /dev/null) || got=$? ;;
    esac
    last=$(tail -1 "$T/$2.$1.out" | tr -d '\r')
}
# refused <name> <fragment> <what>: the source is $T/<name>.cyr; ONE `^error` line, holding <fragment>
refused() {
    rows=$((rows + 1))
    for leg in $(legs); do
        compile "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        w=$(grep -c '^warning' "$T/$1.$leg.err" || true)
        if [ "$crc" -eq 0 ]; then bad "$1 $3 ($leg): BUILT (rc 0)"
        elif ! grep '^error' "$T/$1.$leg.err" | head -1 | grep -qF "$2"; then bad "$1 $3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne 1 ]; then bad "$1 $3 ($leg): $n error lines (want 1)"
        elif [ "$w" -ne 0 ]; then bad "$1 $3 ($leg): a warning beside the refusal: $(grep '^warning' "$T/$1.$leg.err" | head -1 || true)"
        elif [ -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): refused, but a binary was written"
        else ok "$1 $3 ($leg): refused"; fi
    done
}
# runs <name> <want> <what> [<legs>]: compiles clean and exits <want> on every leg
runs() {
    rows=$((rows + 1))
    for leg in ${4:-$(legs)}; do
        [ "$leg" = pe ] && [ "$WINE" -eq 0 ] && continue
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        execute "$leg" "$1"
        if [ "$got" = "$2" ]; then ok "$1 $3 ($leg): exit $got"; else bad "$1 $3 ($leg): exit $got, want $2"; fi
    done
}
XLEGS="x86_64 x86_64:CYRIUS_IR=1 x86_64:CYRIUS_IR=3 x86_64:CYRIUS_DCE=1"
OLEGS=""
[ "$QEMU" -eq 1 ] && OLEGS="$OLEGS aarch64"
[ "$CX" -eq 1 ] && OLEGS="$OLEGS cx"
[ "$WINE" -eq 1 ] && OLEGS="$OLEGS pe"

# --- R0: the filed repro, verbatim (exit 5: the store reached buf) ---
cat > "$T/R0.cyr" <<'EOF2'
struct H { n; m; }
var buf[16];
fn gp(): *H { return &buf; }
fn main() {
    gp().n = 5;
    return load64(&buf);
}
var r = main();
syscall(60, r);
EOF2
runs R0 5 "the filed repro: gp().n = 5; through \`fn gp(): *H\`" "$XLEGS $OLEGS"

# --- R1: the crossos values file on every leg ---
TC=tests/tcyr/crossos/call_ptr_field_store.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=34
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
cp "$TC" "$T/R1.cyr"
# Every leg runs every row, CYRIUS_IR=3 included: its f64 row (`gp().f = 2.5;`) faulted there until the float literal's
# movabs was recorded IR-opaque (CHANGELOG [6.7.14]).
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    f=R1; n=$N
    compile "$leg" $f
    if [ "$crc" -ne 0 ] || [ ! -s "$T/$f.$leg" ]; then bad "R1 $TC ($leg): did not build: $(grep '^error' "$T/$f.$leg.err" | head -1 || true)"; continue; fi
    execute "$leg" $f
    if [ "$got" -eq 0 ] && [ "$last" = "$n passed, 0 failed ($n total)" ]; then ok "R1 ($leg): $last"
    else bad "R1 ($leg): exit $got, '$last' (want $n passed): $(grep FAIL "$T/$f.$leg.out" | head -2 | tr '\n' ' ')"; fi
done

H='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct H { n; m; }
struct E { a; }
var buf[16];
fn gp(): *H { return &buf; }
fn gi(): *i64 { return &buf; }
fn mk(): H { var h: H; h.n = 1; return h; }
fn mk8(): E { var e: E; e.a = 1; return e; }
struct O { k; }
fn O_mk(self): H { var h: H; h.n = 1; return h; }'
row() { printf '%s\n%s\nsyscall(60, go());\n' "$H" "$2" > "$T/$1.cyr"; }
MT="cannot assign to a field of a call result: the result is a temporary"

# --- X: a by-value result keeps the refusal; an untyped binding and a `*i64` result are unchanged ---
row X1 'fn go(): i64 { mk().n = 5; return 0; }'
refused X1 "$MT" "\`mk().n = 5;\`, a 16 B struct returned by value"
row X2 'fn go(): i64 { mk().n += 5; return 0; }'
refused X2 "$MT" "\`mk().n += 5;\`"
row X3 'fn go(): i64 { var o: O = O { 1 }; o.mk().n = 5; return 0; }'
refused X3 "$MT" "\`o.mk().n = 5;\`, a method returning by value"
row X4 'fn go(): i64 { mk8().a = 5; return 0; }'
refused X4 "$MT" "\`mk8().a = 5;\`, an 8 B struct returned by value"
row X5 'fn go(): i64 { var p = gp(); p.n = 5; return 0; }'
refused X5 "no struct type in scope for 'p'" "an untyped \`var p = gp();\` is unchanged (D8 (a))"
row X6 'fn go(): i64 { gi().n = 5; return 0; }'
refused X6 "cannot take a field of the result of 'gi': it does not return a struct" "a \`: *i64\` result is no struct"

# --- T (6.7.14, issues/archived/2026-10-15-toplevel-by-value-call-field-store-two-errors.md): at top level a by-value call's
# field assignment is ONE error, the no-frame refusal — it was that plus "the result is a temporary". In a fn the
# temporary stays the one error (X1 X2). T0 is the filed repro verbatim.
NS="returns a struct by value, and a struct result needs storage in a fn's frame"
cat > "$T/T0.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct H { n; m; }
fn mk(): H { var h: H; h.n = 1; return h; }
mk().n = 5;
syscall(60, 0);
EOF2
refused T0 "'mk' $NS" "the filed repro: top-level \`mk().n = 5;\`, one error"
row T1 'fn go(): i64 { return 0; }
mk().n += 1;'
refused T1 "'mk' $NS" "top-level \`mk().n += 1;\`, one error"
row T2 'fn go(): i64 { return 0; }
mk8().a = 5;'
refused T2 "'mk8' $NS" "top-level \`mk8().a = 5;\`, an 8 B result, one error"
# T3-T5: the same statement's other spellings (found beside the filing): a subscript of the result's `*T` field (the
# second error was a false "cannot subscript field 'p': it is not a *T field") and a method returning by value.
row T3 'struct HP { n; p: *i64; }
fn mkp(): HP { var h: HP; h.n = 1; h.p = &buf; return h; }
fn go(): i64 { return 0; }
mkp().p[0] = 5;'
refused T3 "'mkp' $NS" "top-level \`mkp().p[0] = 5;\`, one error"
row T4 'fn go(): i64 { return 0; }
var o: O = O { 1 };
o.mk().n = 5;'
refused T4 "'O_mk' $NS" "top-level \`o.mk().n = 5;\`, a method, one error"
row T5 'fn go(): i64 { return 0; }
var o: O = O { 1 };
o.mk().n += 1;'
refused T5 "'O_mk' $NS" "top-level \`o.mk().n += 1;\`, one error"

# --- F (6.7.14, issues/archived/2026-10-15-for-step-call-led-field-assignment-refused-with-false-undefined.md): a classic-for
# step is the statement's assignment — through a `: *T` result it stores (F0, the filed repro verbatim; the values
# file's st_ rows), a by-value result is the statement's refusal, ONCE (it was "expected '=', got '('" — through
# 6.7.13 also a false "undefined variable 'gp'"); a step with no `=` keeps "expected '='".
cat > "$T/F0.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct H { n; m; }
var buf[16];
fn gp(): *H { return &buf; }
fn mk(): H { var h: H; h.n = 1; return h; }
fn go(): i64 { var i = 0; for (i = 0; i < 3; gp().n += 1) { i = i + 1; } return load64(&buf); }
syscall(60, go());
EOF2
runs F0 3 "the filed repro: for step gp().n += 1 stores 3"
row F1 'fn go(): i64 { var i = 0; for (i = 0; i < 3; mk().n += 1) { i = i + 1; } return i; }'
refused F1 "$MT" "for step \`mk().n += 1\`, a by-value result, one error"
row F2 'fn go(): i64 { var o: O = O { 1 }; var i = 0; for (i = 0; i < 3; o.mk().n = 1) { i = i + 1; } return i; }'
refused F2 "$MT" "for step \`o.mk().n = 1\`, a method returning by value, one error"
row F3 'fn go(): i64 { return 0; }
var I = 0;
for (I = 0; I < 3; mk().n += 1) { I = I + 1; }'
refused F3 "'mk' $NS" "top-level for step \`mk().n += 1\`: the no-frame refusal, one error"
row F4 'fn go(): i64 { return 0; }
var o: O = O { 1 };
var I = 0;
for (I = 0; I < 3; o.mk().n = 1) { I = I + 1; }'
refused F4 "'O_mk' $NS" "top-level for step \`o.mk().n = 1\`: the no-frame refusal, one error"
row F5 'fn f(): i64 { return 0; }
fn go(): i64 { var i = 0; for (i = 0; i < 3; f()) { i = i + 1; } return i; }'
refused F5 "expected '=', got '('" "for step \`f()\`, a call, keeps its refusal"
row F6 'fn go(): i64 { var i = 0; for (i = 0; i < 3; gp().n) { i = i + 1; } return i; }'
refused F6 "expected '=', got '('" "for step \`gp().n\`, no assignment, keeps its refusal"

# --- T6-T13 (6.7.15, issues/2026-10-17-toplevel-by-value-method-result-field-subscript-two-errors.md): a top-level
# METHOD returning a struct by value, its `*T` field subscripted — one error, the no-frame refusal. The chain's walk
# stopped before the `[`, and the subscript was then judged against a field never typed: a second, false "cannot
# subscript field 'p': it is not a *T field". T6 is the filed repro verbatim; T13 the filed in-fn control (exit 5).
cat > "$T/T6.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct H { n; p: *i64; }
struct O { a; }
var buf[16];
impl O { fn mk(self: *O): H { var h: H; h.n = 1; h.p = &buf; return h; } }
var o: O = O { 0 };
o.mk().p[0] = 5;
syscall(60, 0);
EOF2
refused T6 "7:7: 'O_mk' $NS" "the filed repro: top-level \`o.mk().p[0] = 5;\`, one error"
TH='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct H { n; p: *i64; }
struct H3 { n; p: *i64; q; }
struct O { a; }
var buf[16];
impl O { fn mk(self: *O): H { var h: H; h.n = 1; h.p = &buf; return h; }
         fn mk3(self: *O): H3 { var h: H3; h.n = 1; h.p = &buf; h.q = 0; return h; } }
var o: O = O { 0 };'
trow() { printf '%s\n%s\nsyscall(60, 0);\n' "$TH" "$2" > "$T/$1.cyr"; }
trow T7 'o.mk().p[0] += 5;'
refused T7 "'O_mk' $NS" "top-level \`o.mk().p[0] += 5;\`"
trow T8 'o.mk().p[0];'
refused T8 "'O_mk' $NS" "top-level \`o.mk().p[0];\`, no assignment"
trow T9 'var x = o.mk().p[0];'
refused T9 "'O_mk' $NS" "top-level \`var x = o.mk().p[0];\`, a value"
trow T10 'o.mk3().p[0] = 5;'
refused T10 "'O_mk3' $NS" "a 24 B result (refused by its own call)"
trow T11 'var x = fncall1(&O_mk, &o).p[0];'
refused T11 "'O_mk' $NS" "through \`fncall1(&O_mk, &o)\`"
trow T12 'o.mk().p[0][1] = 5;'
refused T12 "'O_mk' $NS" "a second \`[..]\` stepped over with the chain"
cat > "$T/T13.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct H { n; p: *i64; }
struct O { a; }
var buf[16];
impl O { fn mk(self: *O): H { var h: H; h.n = 1; h.p = &buf; return h; } }
fn go(): i64 { var o: O = O { 0 }; o.mk().p[0] = 5; return load64(&buf); }
syscall(60, go());
EOF2
runs T13 5 "the filed control: in a fn \`o.mk().p[0] = 5;\` stores through the field"
# T14: a genuine non-`*T` subscript in a fn keeps its refusal; T15: at top level the next statement is still checked
trow T14 'fn go(): i64 { var q: O = O { 0 }; q.mk().n[0] = 5; return 0; }'
refused T14 "cannot subscript field 'n': it is not a *T field" "control: in a fn, \`q.mk().n[0]\` (n no *T field) keeps its refusal"
trow T15 'var x = o.mk().p[0] + 1;
var y = zz;'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" T15
    e=$(grep '^error' "$T/T15.$leg.err" | tr '\n' '|')
    n=$(grep -c '^error' "$T/T15.$leg.err" || true)
    case $e in
        *"'O_mk' $NS"*"undefined variable 'zz'"*)
            if [ "$n" -eq 2 ]; then ok "T15 the next statement still checked ($leg)"; else bad "T15 ($leg): $n errors (want 2)"; fi ;;
        *) bad "T15 the next statement still checked ($leg): $e" ;;
    esac
done

# --- K: controls ---
row K1 'fn go(): i64 { gpb().n = 5; return load64(&buf); }
fn gpb(): *H { return &buf; }'
runs K1 5 "a callee defined below the statement (pass 1's record)"
row K2 'fn setn<T>(v: T): i64 { gp().n = v; return 0; }
fn go(): i64 { setn<i64>(4); setn<i32>(6); return load64(&buf); }'
runs K2 6 "the store in a generic body, two instances"
row K3 'fn go(): i64 { gp().n = fncall0(|| { gp().m = 2; return 3; }); return load64(&buf) * 10 + load64(&buf + 8); }'
runs K3 32 "a closure in the value storing through its own call"

# --- CP (6.7.14): `callptr(&f, ..).field = v;` in statement position, as the fncallN spelling ---
REPCP=docs/development/issues/repros/2026-10-16-callptr-statement-field-store-does-not-parse.cyr
[ -f "$REPCP" ] || { echo "FAIL: $G: $REPCP is missing"; exit 1; }
cp "$REPCP" "$T/CP1.cyr"
runs CP1 40 "the filed repro verbatim: \`callptr(&gp, 5).b = 40;\` (expected ';', got '=' before)"
CPH='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P3 { a; b; c; }
var G: P3 = P3 { 0, 0, 0 };
fn gp(a): *P3 { G.a = a; return &G; }
fn gp2(a, b): *P3 { G.a = a + b; return &G; }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
impl P3 { fn tot(self): i64 { G.c = self.a + self.b + self.c; return G.c; } }'
cprow() { printf '%s\n%s\n' "$CPH" "$2" > "$T/$1.cyr"; }
cprow CP2 'fn main(): i64 { callptr(&gp, 5).b += 40; return G.b; }
syscall(60, main());'
runs CP2 40 "\`callptr(&gp, 5).b += 40;\` (unexpected '=' before)"
cprow CP3 'fn main(): i64 { callptr(&mk3, 5).b = 1; return 0; }
syscall(60, main());'
refused CP3 "$MT" "\`callptr(&mk3, 5).b = 1;\`, a by-value result, refused by name as the fncall1 form is (expected ';' before)"
cprow CP3c 'fn main(): i64 { callptr(&mk3, 5).b += 1; return 0; }
syscall(60, main());'
refused CP3c "$MT" "\`callptr(&mk3, 5).b += 1;\` (unexpected '=' before)"
cprow CP4 'fn main(): i64 { callptr(&mk3, 5).tot(); return G.c; }
syscall(60, main());'
runs CP4 18 "control: \`callptr(&mk3, 5).tot();\`, a method statement"
cprow CP5 'fn main(): i64 { callptr((&gp), 5).b = 40; return G.b + G.a; }
syscall(60, main());'
runs CP5 45 "\`callptr((&gp), 5).b = 40;\`, the callee wrapped"
cprow CP6 'fn main(): i64 { callptr(&gp2, 2, 3).c = 9; return G.c * 10 + G.a; }
syscall(60, main());'
runs CP6 95 "\`callptr(&gp2, 2, 3).c = 9;\`, two arguments"
cprow CP7 'fn main(): i64 { var f = |k| { callptr(&gp, k).b = 40; return G.b + G.a; }; return fncall1(f, 2); }
syscall(60, main());'
runs CP7 42 "in a closure"
cprow CP8 'callptr(&gp, 5).b = 40;
syscall(60, G.b + G.a);'
runs CP8 45 "at top level"
cprow CP9 'fn main(): i64 { var fp = &gp; callptr(fp, 5).b = 1; return G.b; }
syscall(60, main());'
refused CP9 "cannot take a field of the result of 'callptr': its callee is a value" "a callee in a variable, refused by name (D31)"
cprow CP10 'fn main(): i64 { callptr(&gp, 5).b; return G.a; }
syscall(60, main());'
runs CP10 5 "control: \`callptr(&gp, 5).b;\`, a read statement"

# --- U (6.7.15, issues/2026-10-17-undefined-callee-field-assignment-names-no-undefined-fn.md): a `.field` of an
# UNDEFINED fn's result is "undefined function 'undefd'" at the name, ONE error — no warning, no end-of-compile
# refusal (the call is never registered), no binary. It was "expected ';', got '.'" (the step "expected '=', got '('")
# then the end-of-compile refusal. U1 / U2 are the filed repros verbatim, with their positions.
UF="undefined function 'undefd'"
cat > "$T/U1.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { undefd().n += 1; return 0; }
syscall(60, go());
EOF2
refused U1 "<source>:3:16: $UF" "the filed repro: \`undefd().n += 1;\`, the fn named at its name"
cat > "$T/U2.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { var i = 0; for (i = 0; i < 3; undefd().n += 1) { i = i + 1; } return i; }
syscall(60, go());
EOF2
refused U2 "<source>:3:46: $UF" "the filed repro: the for step \`undefd().n += 1\`"
row U3 'fn go(): i64 { var x = undefd().n; return x; }'
refused U3 "$UF" "a factor, \`var x = undefd().n;\`"
row U4 'fn go(): i64 { undefd().n = 5; return 0; }'
refused U4 "$UF" "\`undefd().n = 5;\`"
row U5 'fn go(): i64 { undefd(1, 2).m(3); return 0; }'
refused U5 "$UF" "a method on the result, \`undefd(1, 2).m(3);\`"
row U6 'fn go(): i64 { undefd().p[0] = 5; return 0; }'
refused U6 "$UF" "a subscript of its field, \`undefd().p[0] = 5;\`"
row U7 'fn go(): i64 { var x = 1 + undefd().p[0] * 2; return x; }'
refused U7 "$UF" "inside an expression, \`1 + undefd().p[0] * 2\`"
row U8 'fn go(): i64 { return 0; }
undefd().n = 5;'
refused U8 "$UF" "at top level"
row U9 'fn g<T>(v: T): i64 { undefd().n = v; return 0; }
fn go(): i64 { g<i64>(1); g<i32>(2); return 0; }'
refused U9 "$UF" "in a generic used at two types, once"
row U10 'fn go(): i64 { var f = || { undefd().n += 1; return 0; }; return fncall0(f); }'
refused U10 "$UF" "in a closure"
# U11: the latch is left as it was — the next statement's own error is still reported (two errors in all)
row U11 'fn go(): i64 { undefd().n += 1; return zz; }'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" U11
    e=$(grep '^error' "$T/U11.$leg.err" | tr '\n' '|')
    case $e in
        *"$UF"*"undefined variable 'zz'"*) n=$(grep -c '^error' "$T/U11.$leg.err" || true)
            if [ "$n" -eq 2 ] && [ "$crc" -ne 0 ]; then ok "U11 a later error still reported ($leg)"; else bad "U11 ($leg): $n errors, rc $crc"; fi ;;
        *) bad "U11 a later error still reported ($leg): $e" ;;
    esac
done
# U12: --allow-undef does not compile it — it is an error, not the downgradable undefined-function refusal (cx has no
# --allow-undef: its undefined fns are always an error)
rows=$((rows + 1))
for leg in $(legs); do
    crc=0
    case $leg in
        x86_64)  timeout 60 "$CC" --allow-undef < "$T/U1.cyr" > "$T/U12.$leg" 2> "$T/U12.$leg.err" || crc=$? ;;
        aarch64) timeout 60 "$A64" --allow-undef < "$T/U1.cyr" > "$T/U12.$leg" 2> "$T/U12.$leg.err" || crc=$? ;;
        pe)      CYRIUS_TARGET_WIN=1 timeout 60 "$CC" --allow-undef < "$T/U1.cyr" > "$T/U12.$leg" 2> "$T/U12.$leg.err" || crc=$? ;;
        *) continue ;;
    esac
    if [ "$crc" -ne 0 ] && [ ! -s "$T/U12.$leg" ] && grep -q "^error.*$UF" "$T/U12.$leg.err"; then ok "U12 --allow-undef still refuses U1 ($leg)"
    else bad "U12 --allow-undef ($leg): rc $crc, $(grep '^error' "$T/U12.$leg.err" | head -1 || true)"; fi
done
# U13 (control): a plain call statement to an undefined fn keeps its warning and the end-of-compile refusal, no
# error at the call
row U13 'fn go(): i64 { undefd(); return 0; }'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" U13
    if [ "$crc" -ne 0 ] && grep -q "^warning: $UF" "$T/U13.$leg.err" && ! grep -q '^error:<source>' "$T/U13.$leg.err"; then
        ok "U13 control: \`undefd();\` keeps the warning and the end-of-compile refusal ($leg)"
    else bad "U13 control ($leg): rc $crc, $(grep '^error' "$T/U13.$leg.err" | head -1 || true)"; fi
done
# U14 / U15 (controls): an intrinsic lowered by name is no undefined fn — `mulh64(2, 3).n = 5;` (a statement, which
# reaches the call statement's field arm) and `var x = mulh64(2, 3).n;` keep "expected ';', got '.'"
row U14 'fn go(): i64 { mulh64(2, 3).n = 5; return 0; }'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" U14
    if [ "$crc" -ne 0 ] && grep '^error' "$T/U14.$leg.err" | head -1 | grep -qF "expected ';', got '.'" \
       && ! grep -q "^error.*undefined function 'mulh64'" "$T/U14.$leg.err"; then ok "U14 control: \`mulh64(2, 3).n = 5;\` is no undefined fn ($leg)"
    else bad "U14 control ($leg): rc $crc, $(grep '^error' "$T/U14.$leg.err" | head -1 || true)"; fi
done
row U15 'fn go(): i64 { var x = mulh64(2, 3).n; return x; }'
refused U15 "expected ';', got '.'" "control: \`var x = mulh64(2, 3).n;\`, an intrinsic, is no undefined fn"

# --- S (6.7.15, issues/2026-10-17-syntax-only-sibling-ptr-call-field-store-false-temporary.md): --syntax-only (lint's
# pre-pass), a field assignment on a call whose callee this file does not define — a sibling module's — parses its
# tail silently: it was "cannot assign to a field of a call result: the result is a temporary", true only of a callee
# KNOWN to return a struct by value. S1 is the filed repro verbatim (the statement registers gp, so the step's callee
# is a call-registered fn with no definition). On the x86_64, aarch64 and PE compilers; the cx compiler refuses every
# call to an undefined fn even under --syntax-only (its backend's own refusal, staged), so it has no S leg.
# synonly <name> <want-rc> <fragment|-> <what>: `--syntax-only`; rc <want-rc>; `-` = no `^error` line and the
# "warning: undefined function 'gp'"; else ONE `^error` line holding <fragment>.
synonly() {
    rows=$((rows + 1))
    for leg in x86_64 aarch64 pe; do
        [ "$leg" = aarch64 ] && [ "$QEMU" -eq 0 ] && continue
        crc=0
        case $leg in
            x86_64)  timeout 60 "$CC" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.$leg.err" || crc=$? ;;
            aarch64) timeout 60 "$A64" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.$leg.err" || crc=$? ;;
            pe)      CYRIUS_TARGET_WIN=1 timeout 60 "$CC" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.$leg.err" || crc=$? ;;
        esac
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        if [ "$crc" -ne "$2" ]; then bad "$1 $4 ($leg): rc $crc (want $2): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$3" = - ]; then
            if [ "$n" -ne 0 ]; then bad "$1 $4 ($leg): $(grep '^error' "$T/$1.$leg.err" | head -1)"
            elif ! grep -q "^warning: undefined function 'gp'" "$T/$1.$leg.err"; then bad "$1 $4 ($leg): no undefined-function warning"
            else ok "$1 $4 ($leg): accepted"; fi
        elif [ "$n" -ne 1 ]; then bad "$1 $4 ($leg): $n error lines (want 1)"
        elif ! grep '^error' "$T/$1.$leg.err" | grep -qF "$3"; then bad "$1 $4 ($leg): $(grep '^error' "$T/$1.$leg.err" | head -1)"
        else ok "$1 $4 ($leg): one error"; fi
    done
}
cat > "$T/S1.cyr" <<'EOF2'
struct H { n; m; }
fn go(): i64 { gp().n = 5; var i = 0; for (i = 0; i < 3; gp().n += 1) { i = i + 1; } return 0; }
EOF2
synonly S1 0 - "the filed repro: \`gp().n = 5;\` and the for step \`gp().n += 1\`, gp a sibling's"
SH='struct H { n; m; p: *i64; }
fn mk(): H { var h: H; h.n = 1; return h; }'
srow() { printf '%s\n%s\n' "$SH" "$2" > "$T/$1.cyr"; }
srow S2 'fn go(): i64 { var i = 0; for (i = 0; i < 3; gp().n = i) { i = i + 1; } return 0; }'
synonly S2 0 - "the step alone (gp unregistered)"
srow S3 'fn go(): i64 { gp().p[0] = 5; gp().m(); gp().n += gp().m; gp().n <<= 1; return 0; }'
synonly S3 0 - "a subscript, a method, \`+=\` reading the sibling's call, \`<<=\`"
srow S4 'fn g<T>(v: T): i64 { gp().n = v; return 0; }
fn go(): i64 { g<i64>(1); g<i32>(2); return 0; }'
synonly S4 0 - "in a generic body, two instances"
srow S5 'fn go(): i64 { gp().n = 5 +; return 0; }'
synonly S5 1 "3:28: unexpected ';'" "a grammar error in the value is still reported (it was the temporary)"
srow S6 'fn go(): i64 { var i = 0; for (i = 0; i < 3; gp().n += ) { i = i + 1; } return 0; }'
synonly S6 1 "unexpected ')'" "a step with no value is still reported"
srow S7 'fn go(): i64 { gp().n = 5 return 0; }'
synonly S7 1 "expected ';', got return" "a missing \`;\` is still reported"
srow S8 'fn go(): i64 { mk().n = 5; return 0; }'
synonly S8 1 "$MT" "control: a by-value callee this file defines keeps the refusal"
srow S9 'fn go(): i64 { var i = 0; for (i = 0; i < 3; mk().n += 1) { i = i + 1; } return 0; }'
synonly S9 1 "$MT" "control: ... as a for step too"

FLOOR_ROWS=69   # 6.7.14: the base 11 + the structs lane's for-step / top-level rows (13) + the receives lane's CP rows (11);
                # 6.7.15: + U1-U15, S1-S9, T6-T15
[ "$rows" -ge "$FLOOR_ROWS" ] || bad "only $rows rows ran (floor $FLOOR_ROWS) — rows were lost"
echo "  $rows rows, $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails)"; exit 1; fi
echo "PASS: $G — a field of a : *T call's result is stored through the pointer; a by-value result stays refused; \`callptr(&f, ..).b = v;\` as the fncallN statement (6.7.14)"
