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
# 17) on x86_64 (plain, CYRIUS_IR=1, CYRIUS_IR=3 without its IR3-PRE row, CYRIUS_DCE=1), aarch64 (qemu — EMULATION,
# not hardware), cx (cxvm) and PE (wine, a private prefix); X1-X6 refused (the message first, ONE `^error`, no
# warning, no binary) on the x86_64, aarch64, cx and PE compilers; K1-K3 controls that compile and run on every leg.
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
# (`_cpf_try`'s `beg != _cpf_st` is a guard no current path reaches: a closure's statements arm their own, and a for
# step's call chain is refused before any `*T` arm runs.)
#
# 6.7.14 (the receives lane, unit R2; issues/2026-10-16-callptr-statement-field-store-does-not-parse.md) — THE SAME STORE
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
FLOOR=17
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
cp "$TC" "$T/R1.cyr"
# Under CYRIUS_IR=3 the row marked IR3-PRE is left out: an f64 field store through a `*T` faults there before this fix
# too (`var q: *H = &buf; q.f = 2.5;`: SIGSEGV with the 6.7.13 lane's base compiler) — a pre-existing IR=3 defect, filed.
grep -v 'IR3-PRE' "$TC" > "$T/R1i.cyr"
NI=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$T/R1i.cyr")
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    f=R1; n=$N
    [ "$leg" = "x86_64:CYRIUS_IR=3" ] && { f=R1i; n=$NI; }
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

FLOOR_ROWS=22
[ "$rows" -ge "$FLOOR_ROWS" ] || bad "only $rows rows ran (floor $FLOOR_ROWS) — rows were lost"
echo "  $rows rows, $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails)"; exit 1; fi
echo "PASS: $G — a field of a : *T call's result is stored through the pointer; a by-value result stays refused; \`callptr(&f, ..).b = v;\` as the fncallN statement (6.7.14)"
