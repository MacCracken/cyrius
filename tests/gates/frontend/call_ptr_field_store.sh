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
# repro, runs; F1-F4 refused once; F5 F6 no assignment, "expected '='"); K1-K3 controls that compile and run on every leg.
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

# --- T (6.7.14, issues/2026-10-15-toplevel-by-value-call-field-store-two-errors.md): at top level a by-value call's
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

# --- F (6.7.14, issues/2026-10-15-for-step-call-led-field-assignment-refused-with-false-undefined.md): a classic-for
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

# --- K: controls ---
row K1 'fn go(): i64 { gpb().n = 5; return load64(&buf); }
fn gpb(): *H { return &buf; }'
runs K1 5 "a callee defined below the statement (pass 1's record)"
row K2 'fn setn<T>(v: T): i64 { gp().n = v; return 0; }
fn go(): i64 { setn<i64>(4); setn<i32>(6); return load64(&buf); }'
runs K2 6 "the store in a generic body, two instances"
row K3 'fn go(): i64 { gp().n = fncall0(|| { gp().m = 2; return 3; }); return load64(&buf) * 10 + load64(&buf + 8); }'
runs K3 32 "a closure in the value storing through its own call"

FLOOR_ROWS=24
[ "$rows" -ge "$FLOOR_ROWS" ] || bad "only $rows rows ran (floor $FLOOR_ROWS) — rows were lost"
echo "  $rows rows, $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails)"; exit 1; fi
echo "PASS: $G — a field of a : *T call's result is stored through the pointer; a by-value result stays refused"
