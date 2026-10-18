#!/bin/sh
# Gate: a `.field` / `.m(..)` after PARENTHESES around a struct value reads it as unwrapped (6.7.14, the user's
# decision D24 (a), 2026-10-16; issues/archived/2026-10-16-field-of-parenthesised-expression-does-not-parse.md).
#
# THE DEFECT (measured on the 6.7.14 receives lane before the bite, x86_64 / aarch64 under qemu / cx under cxvm /
# PE under wine — refused alike, frontend): `return (s).a;` was `error:<source>:3:47: expected ';', got '.'` — the
# parenthesised factor returned at its `)` with no postfix step — and `(mk1()).a`, `(*p).a`, `(p).a`, `(s).m()`
# the same. A STATEMENT beginning `(` was "unexpected '('" whatever followed.
#
# THE RULE (D24 (a)): the wrap is transparent, as guide § Parentheses makes it for every struct source (6.7.6;
# 6.7.11's D35 / D44, 6.7.13's D16 / D17 / D19). The inside is taken as its unwrapped spelling takes it (`_paren_field`,
# src/frontend/parse_expr.cyr): a name through the field-load route, `*E` / a `*S` value through its pointer, a free
# call into a temp, a method / operator / known `&f` result or a struct-typed field from its record — then the wrap is
# closed and the chain goes on. A wrap around a value that is no struct (`(x + 1).a`) is refused by name; a STORE
# `(s).a = v;` / `(s).a += v;` is refused by name (`_stmt_paren_field`, one PARSE_STMT call); at top level a struct
# result is refused once (no frame), as unwrapped.
#
# ROWS — each on x86_64, aarch64 (qemu-aarch64), cx (cxvm) and PE (wine, a private prefix; a missing tool is a SKIP
# that names it): R0 the filed repro verbatim (33); V1-V12 the values; A1 the crossos values file
# (tests/tcyr/crossos/struct_receive_paren_call.tcyr, the release gate's real-hardware carrier); N1-N7 the refusals,
# each exactly one error line, no binary.
#
# MUTATION LEDGER (2026-10-17, a scratch copy of src/ with the one edit, this gate run as CYCC=<mutant>; the
# aarch64 / cx compilers build from the tree's src/, so a mutant is RED on its x86_64 and PE legs):
#   the tree before (the lane's D25 / D26 commit)          -> RED 21: every row (R0 V1-V12 A1 "expected ';', got '.'",
#                                                             V9 N2 N3 "unexpected '('", N1 N6 N7 other words, N4 N5 two)
#   PARSE_FACTOR without its `_paren_field` call            -> RED 19: R0 V1-V12 A1 N1 N4-N7
#   PARSE_STMT without its `_stmt_paren_field` call         -> RED 4: V9 N2 N3 ("unexpected '('"), A1 (its statement rows)
#   `_pfl_beg` ignoring the wrap's `(` (GTI - 1 always)     -> RED 2: V11 (`var x: P2 = (b).mk();` took no temp), A1
#   `_pf_lsc` answering 0 (no struct-result stamp)          -> RED 5: V7 V8 V10 (a method / operator / known callee
#                                                             refused "not a struct"), N5 (two errors), A1
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=paren_field_access
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

# compile <leg> <name>: $T/<name>.<leg> (+ .err); rc in $crc
compile() {
    crc=0
    case $1 in
        x86_64)  timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        aarch64) timeout 60 "$A64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        cx)      timeout 60 "$CXC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        pe)      CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
    esac
}
legs() {
    l="x86_64"
    [ "$QEMU" -eq 1 ] && l="$l aarch64"
    [ "$CX" -eq 1 ] && l="$l cx"
    echo "$l pe"
}
# refused <name> <fragment> <what> [<errors>]: the source is $T/<name>.cyr; <errors> (default 1)
# `^error` lines, the first holding <fragment>
refused() {
    rows=$((rows + 1))
    want=${4:-1}
    for leg in $(legs); do
        compile "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        w=$(grep -c '^warning' "$T/$1.$leg.err" || true)
        if [ "$crc" -eq 0 ]; then bad "$1 $3 ($leg): BUILT (rc 0)"
        elif ! grep '^error' "$T/$1.$leg.err" | head -1 | grep -qF "$2"; then bad "$1 $3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne "$want" ]; then bad "$1 $3 ($leg): $n error lines (want $want)"
        elif [ "$w" -ne 0 ]; then bad "$1 $3 ($leg): a warning beside the refusal: $(grep '^warning' "$T/$1.$leg.err" | head -1 || true)"
        elif [ -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): refused, but a binary was written"
        else ok "$1 $3 ($leg): refused ($n)"; fi
    done
}
# runs <name> <want> <what>: compiles clean and exits <want> on every leg
runs() {
    rows=$((rows + 1))
    for leg in $(legs); do
        [ "$leg" = pe ] && [ "$WINE" -eq 0 ] && continue
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        chmod +x "$T/$1.$leg"; got=0
        case $leg in
            x86_64)  timeout 30 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            aarch64) timeout 60 qemu-aarch64 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            cx)      timeout 60 "$T/cxvm" < "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            pe)      cp "$T/$1.$leg" "$T/$1.exe"
                     (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                         WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$1.exe" > /dev/null 2>&1) || got=$? ;;
        esac
        if [ "$got" = "$2" ]; then ok "$1 $3 ($leg): exit $got"; else bad "$1 $3 ($leg): exit $got, want $2"; fi
    done
}
REP=docs/development/issues/repros/2026-10-16-field-of-parenthesised-expression-does-not-parse.cyr
[ -f "$REP" ] || { echo "FAIL: $G: the issue's repro file is missing"; exit 1; }
cp "$REP" "$T/R0.cyr"
runs R0 33 "the filed repro verbatim: \`return (s).a;\` (expected ';' before)"

H='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P1 { a; }
struct P2 { a; b; }
struct P3 { a; b; c; }
struct HQ { n; q: P2; }
impl P1 { fn m(self): i64 { return self.a + 1; } }
impl P2 { fn mk(self): P2 { var r = P2 { self.a * 2, self.b * 2 }; return r; } }
fn mk1(): P1 { var r = P1 { 33 }; return r; }
fn mk0(): i64 { return 5; }
fn mk3(v): P3 { var r = P3 { v, v * 2, v * 3 }; return r; }
fn P2_add(x: P2, y: P2): P2 { var r = P2 { x.a + y.a, x.b + y.b }; return r; }
var GS = P2 { 5, 6 };
fn gp(): *P2 { return &GS; }
'
src() { printf '%s%s\n' "$H" "$2" > "$T/$1.cyr"; }
src V1 'fn main(): i64 { return (mk1()).a; }
syscall(60, main());'
runs V1 33 "(mk1()).a, an 8 B call"
src V2 'fn main(): i64 { var s = P1 { 33 }; return ((s)).a; }
syscall(60, main());'
runs V2 33 "((s)).a"
src V3 'fn main(): i64 { var s = P1 { 33 }; var p: *P1 = &s; return (*p).a; }
syscall(60, main());'
runs V3 33 "(*p).a"
src V4 'fn main(): i64 { var s = P1 { 33 }; var p: *P1 = &s; return (p).a; }
syscall(60, main());'
runs V4 33 "(p).a, p a *P1"
src V5 'fn main(): i64 { var s = P1 { 32 }; return (s).m(); }
syscall(60, main());'
runs V5 33 "(s).m()"
src V6 'fn main(): i64 { return (mk3(5)).b + (mk3(1)).c; }
syscall(60, main());'
runs V6 13 "(mk3(5)).b, 24 B (a temp)"
src V7 'fn main(): i64 { var b = P2 { 3, 4 }; return (b.mk()).b * 10 + (b.mk()).a; }
syscall(60, main());'
runs V7 86 "(b.mk()).b, a 16 B method result"
src V8 'fn main(): i64 { var x = P2 { 3, 4 }; var y = P2 { 10, 20 }; return (x + y).b; }
syscall(60, main());'
runs V8 24 "(x + y).b, an operator result"
src V9 'fn main(): i64 { var s = P1 { 32 }; (s).m(); (mk1()).a; return (s).a + 1; }
syscall(60, main());'
runs V9 33 "(s).m(); (mk1()).a; as statements (unexpected '(' before)"
src V10 'fn main(): i64 { var h: HQ; h.n = 1; h.q.a = 7; h.q.b = 8; return (h.q).b * 10 + (gp()).a + (fncall1(&mk3, 2)).c; }
syscall(60, main());'
runs V10 91 "(h.q).b, a struct-typed field; (gp()).a, a : *P2 call; (fncall1(&mk3, 2)).c, a known callee"
src V11 'fn main(): i64 { var b = P2 { 3, 4 }; var x: P2 = (b).mk(); return x.a * 10 + x.b; }
syscall(60, main());'
runs V11 68 "var x: P2 = (b).mk(); a struct destination takes the method's temp"
src V12 'var S1 = P1 { 33 };
var X = (S1).a;
syscall(60, X);'
runs V12 33 "top level: var X = (S1).a;"
cp tests/tcyr/crossos/struct_receive_paren_call.tcyr "$T/A1.cyr"
runs A1 0 "tests/tcyr/crossos/struct_receive_paren_call.tcyr (the D24 group and every earlier one)"

src N1 'fn main(): i64 { var x = 5; return (x + 1).a; }
syscall(60, main());'
refused N1 "a field is read only from a struct value - the value in these parentheses is not a struct" "(x + 1).a, no struct"
src N2 'fn main(): i64 { var s = P1 { 33 }; (s).a = 1; return s.a; }
syscall(60, main());'
refused N2 "cannot assign to a field after parentheses" "(s).a = 1; a store"
src N3 'fn main(): i64 { var s = P1 { 33 }; (s).a += 1; return s.a; }
syscall(60, main());'
refused N3 "cannot assign to a field after parentheses" "(s).a += 1; a compound store"
src N4 'var X = (mk3(5)).b;
syscall(60, X);'
refused N4 "'mk3' returns a struct by value, and a struct result needs storage in a fn's frame" "top level: (mk3(5)).b, no frame"
src N5 'var B = P2 { 3, 4 };
var X = (B.mk()).b;
syscall(60, X);'
refused N5 "'P2.mk' returns a struct by value, and a struct result needs storage in a fn's frame" "top level: (B.mk()).b, no frame"
src N6 'fn main(): i64 { var x = 5; return (x).a; }
syscall(60, main());'
refused N6 "no struct type in scope for 'x'" "(x).a, x no struct, as x.a"
src N7 'fn main(): i64 { return (mk0()).a; }
syscall(60, main());'
refused N7 "cannot take a field of the result of 'mk0': it does not return a struct" "(mk0()).a, as mk0().a"

FLOOR=21
[ "$rows" -ge "$FLOOR" ] || bad "only $rows rows ran (floor $FLOOR)"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails failed ($rows rows, $skips legs skipped)"; exit 1; fi
echo "PASS: $G — $rows rows: a .field / .m() after parentheses around a struct value reads it as unwrapped (D24 (a)), a non-struct / a store / a top-level struct result refused once by name ($skips legs skipped)"
