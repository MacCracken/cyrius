#!/bin/sh
# tests/gates/frontend/u128_deref_refused.sh — 6.7.15
#
# `*pu` THROUGH A TYPED `*u128` IS REFUSED BY NAME, AS `pu[0]` IS (the user's decision D20, 2026-10-18). The
# dereference read and wrote only the low 8 bytes, silently: `var x: u128 = *pa;` dropped the high word, `*pa == a`
# compared the low word, an if-expression branch `{ *pa }` was the low word, `*pa = b` left the old high word (the
# filed programs printed 0010 and 0-1, rc 0, no diagnostic), where `pa[0]` was refused by name. Every `*pu` whose
# operand is a typed `*u128` — a name, a `*u128` field, a call or method declared `: *u128`, `p + n`, a wrap, `**pp`
# of a `**u128` — is now "cannot dereference 'pu': a u128 element does not fit one register - use load64/store64 on
# its two halves", at the `*`, read or stored (`_deref_u128`, src/frontend/parse_expr.cyr). An untyped pointer
# (`var p = &b;`, silent_values_checked.sh U34) and a `**u128`'s `*pp` (a pointer) are unchanged.
# Filed: docs/development/issues/2026-10-17-u128-pointer-dereference-reads-and-writes-low-word.md
#
#   F  the filing's programs, verbatim: F1 its four `*pa` lines (a declaration, `==`, an if-expression branch, a
#      branch into a u128) — exactly four errors, one per line, at the `*`; F2 its store `*pa = b;` — one error
#   R  one shape per program, ONE error each, the operand named: R1 `var x: u128 = *pa;`, R2 `*pa == a`, R3 the
#      branch `{ *pa } else { *pb }` (once), R4 `*pa = b;`, R5 `*pa += 1;`, R6 a for step `*pa = 3`, R7 `*(pa + 1)`,
#      R8 `*(pa)`, R9 a `*u128` field `*h.pu`, R10 `*gpu() + 1`, R11 a method `*h.mp()`, R12 `**ppa` ('*ppa'), R13
#      `**ppa = 3;`, R14 a `p: *u128` parameter, R15 a closure's capture, R16 top level `var T = *GPA;`, R17 top level
#      `*GPA = 9;`, R18 two reads in one statement (once), R19 --syntax-only (what `cyrius lint` runs) refuses R1
#   C  controls that compile and run, unchanged: C1 `var q: *u128 = *ppa;` (a pointer, 5), C2 an untyped `var p = &a;
#      *p` (the low word, 5), C3 load64 / store64 on the halves (18), C4 `*&a` (5), C5 an untyped copy `var q = pa;
#      *q` (5)
# R / F on the x86_64, aarch64, cx and PE compilers (no binary); C compiled and run on x86_64, IR=1, IR=3, DCE,
# aarch64 (qemu), cx (cxvm) and PE (wine).
#
# MUTATION LEDGER (2026-10-18; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run FROM
# that copy with CYCC= it, so every leg's compiler carries the mutant):
#   `_deref_u128` answering 0 (the lane head's behaviour) -> RED 86: F1 F2 and R1-R18 on every compiler (built, rc 0),
#       F1's four and F2's one error positions, R19; C green
#   `_deref_store` without its `_deref_u128` -> RED 25: the stores F2 R4 R5 R6 R13 R17 on every compiler (built), F2's
#       error position; the reads and C green
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=u128_deref_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# The compilers: aarch64 and cx built from this tree's src (always — a refusal is checked without running);
# qemu, the tree's cxvm and wine run the controls.
A64=""; CXCC=""; QEMU=0; WINE=0
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"; A64="$D/cc_a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v qemu-aarch64 > /dev/null 2>&1; then QEMU=1
else echo "  SKIP: the aarch64 run legs (qemu-aarch64 not installed; the aarch64 refusals still run)"; skips=$((skips + 1)); fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: the PE run legs (wine not installed; the PE refusals still run)"; skips=$((skips + 1)); fi

# comp <leg> <src> <out>: compile; rc in CRC
comp() {
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        x86:*) env "${1#x86:}" timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$A64" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$CXCC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
RLEGS="x86"
[ -n "$A64" ] && RLEGS="$RLEGS a64"
[ -n "$CXCC" ] && RLEGS="$RLEGS cx"
RLEGS="$RLEGS pe"
XLEGS="x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1"
[ -n "$A64" ] && [ "$QEMU" = 1 ] && XLEGS="$XLEGS a64"
[ -n "$CXCC" ] && XLEGS="$XLEGS cx"
[ "$WINE" = 1 ] && XLEGS="$XLEGS pe"

MSG="': a u128 element does not fit one register - use load64/store64 on its two halves"
# nref <id> <src> <count> <name> <what>: refused with exactly <count> error lines, each "cannot dereference '<name>..."
# — no warning, no binary — by every compiler
nref() {
    for leg in $RLEGS; do
        o="$D/r_$1_$leg"
        comp "$leg" "$2" "$o"
        n=$(grep -c '^error' "$o.err" || true)
        m=$(grep '^error' "$o.err" | grep -cF "cannot dereference '$4$MSG" || true)
        w=$(grep -c '^warning' "$o.err" || true)
        if [ "$CRC" -eq 0 ]; then bad "$1 $leg: $5: BUILT (rc 0) — want the refusal"
        elif [ "$n" -ne "$3" ]; then bad "$1 $leg: $5: $n error lines, want $3: $(grep '^error' "$o.err" | head -2 | tr '\n' '|')"
        elif [ "$m" -ne "$3" ]; then bad "$1 $leg: $5: not the refusal: $(grep '^error' "$o.err" | head -1)"
        elif [ "$w" -ne 0 ]; then bad "$1 $leg: $5: a warning beside it: $(grep -m1 '^warning' "$o.err")"
        elif [ -s "$o" ]; then bad "$1 $leg: $5: refused, but a binary was written"
        else ok "$1 $leg: $5: refused ($3)"; fi
    done
}
# xr <id> <src> <want> <what>: compiles with no diagnostic but notes, exits <want> on every run leg
xr() {
    for leg in $XLEGS; do
        o="$D/x_$1_$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')"
        comp "$leg" "$2" "$o"
        if [ "$CRC" -ne 0 ] || [ ! -s "$o" ]; then bad "$1 $leg: $4 did not build: $(grep -m1 '^error' "$o.err")"; continue; fi
        if grep -q '^error\|^warning' "$o.err"; then bad "$1 $leg: $4 built with a diagnostic: $(grep -m1 '^error\|^warning' "$o.err")"; continue; fi
        RC=0
        case "$leg" in
            x86|x86:*) chmod +x "$o"; timeout 60 "$o" > "$o.out" 2>&1 || RC=$? ;;
            a64) chmod +x "$o"; timeout 120 qemu-aarch64 "$o" > "$o.out" 2>&1 || RC=$? ;;
            cx)  timeout 120 "$D/cxvm" < "$o" > "$o.out" 2>&1 || RC=$? ;;
            pe)  cp "$o" "$o.exe"
                 (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "$o.exe" > "$o.out" 2> /dev/null) || RC=$? ;;
        esac
        if [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"; else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}

echo "F. the filing's programs, verbatim"
cat > "$D/f1.cyr" <<'X'
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    var a: u128 = 0;
    a = a - 1;
    var b: u128 = 5;
    var pa: *u128 = &a;
    var pb: *u128 = &b;
    var x: u128 = *pa;
    fmt_int(x == a);
    fmt_int(*pa == a);
    var c = 1;
    var y = if (c == 1) { *pa } else { *pb };
    fmt_int(y == 0 - 1);
    var z: u128 = if (c == 1) { *pa } else { *pb };
    fmt_int(z == a);
    return 0;
}
syscall(60, main());
X
nref F1 "$D/f1.cyr" 4 pa "the four *pa lines (printed 0010)"
for ln in 9:19 11:13 13:27 15:33; do
    if grep -q "^error:<source>:$ln: cannot dereference 'pa'" "$D/r_F1_x86.err"; then ok "F1 x86: the error at $ln (the \`*\`)"
    else bad "F1 x86: no error at $ln: $(grep '^error' "$D/r_F1_x86.err" | cut -d' ' -f1 | tr '\n' ' ')"; fi
done
cat > "$D/f2.cyr" <<'X'
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    var a: u128 = 0;
    a = a - 1;
    var b: u128 = 5;
    var pa: *u128 = &a;
    *pa = b;
    fmt_int(a == b);
    fmt_int(load64(&a + 8));
    return 0;
}
syscall(60, main());
X
nref F2 "$D/f2.cyr" 1 pa "the store *pa = b; (printed 0-1)"
if grep -q "^error:<source>:8:5: " "$D/r_F2_x86.err"; then ok "F2 x86: the error at 8:5 (the \`*\`)"
else bad "F2 x86: not at 8:5: $(grep -m1 '^error' "$D/r_F2_x86.err")"; fi

echo "R. one shape per program"
H='include "lib/syscalls.cyr"
struct Hu { pu: *u128; n; }
var GA: u128 = 7;
var GPA: *u128 = &GA;
fn gpu(): *u128 { return GPA; }
impl Hu { fn mp(self): *u128 { return self.pu; } }
fn take(x): i64 { return x; }'
L='var a: u128 = 5; var b: u128 = 6; var pa: *u128 = &a; var pb: *u128 = &b; var ppa: **u128 = &pa; var c = 1;'
mk() { printf '%s\n%s\n' "$H" "$2" > "$D/$1.cyr"; }
fnr() { mk "$1" "fn main(): i64 { $L $2 }
syscall(60, main());"; }
fnr r1 'var x: u128 = *pa; return 0;'
nref R1 "$D/r1.cyr" 1 pa "var x: u128 = *pa;"
fnr r2 'return *pa == a;'
nref R2 "$D/r2.cyr" 1 pa "*pa == a"
fnr r3 'var y = if (c == 1) { *pa } else { *pb }; return y;'
nref R3 "$D/r3.cyr" 1 pa "an if-expression branch { *pa } else { *pb } (once)"
fnr r4 '*pa = b; return 0;'
nref R4 "$D/r4.cyr" 1 pa "the store *pa = b;"
fnr r5 '*pa += 1; return 0;'
nref R5 "$D/r5.cyr" 1 pa "*pa += 1;"
fnr r6 'var i = 0; for (i = 0; i < 2; *pa = 3) { i = i + 1; } return 0;'
nref R6 "$D/r6.cyr" 1 pa "a for step *pa = 3"
fnr r7 'var x = *(pa + 1); return 0;'
nref R7 "$D/r7.cyr" 1 pa "*(pa + 1)"
fnr r8 'return *(pa);'
nref R8 "$D/r8.cyr" 1 pa "*(pa)"
fnr r9 'var h: Hu = Hu { &a, 1 }; return take(*h.pu);'
nref R9 "$D/r9.cyr" 1 pu "a *u128 field: take(*h.pu)"
fnr r10 'return *gpu() + 1;'
nref R10 "$D/r10.cyr" 1 gpu "a call declared : *u128: *gpu() + 1"
fnr r11 'var h: Hu = Hu { &a, 1 }; return *h.mp();'
nref R11 "$D/r11.cyr" 1 mp "a method declared : *u128: *h.mp()"
fnr r12 'return **ppa;'
nref R12 "$D/r12.cyr" 1 '*ppa' "**ppa of a **u128"
fnr r13 '**ppa = 3; return 0;'
nref R13 "$D/r13.cyr" 1 '*ppa' "**ppa = 3;"
mk r14 'fn f(pu: *u128): i64 { return *pu; }
fn main(): i64 { var a: u128 = 5; return f(&a); }
syscall(60, main());'
nref R14 "$D/r14.cyr" 1 pu "a p: *u128 parameter"
fnr r15 'var f = || { return *pa; }; return fncall0(f);'
nref R15 "$D/r15.cyr" 1 pa "a closure's capture"
mk r16 'var T = *GPA;
syscall(60, 0);'
nref R16 "$D/r16.cyr" 1 GPA "top level: var T = *GPA;"
mk r17 '*GPA = 9;
syscall(60, 0);'
nref R17 "$D/r17.cyr" 1 GPA "top level: *GPA = 9;"
fnr r18 'return *pa + *pb;'
nref R18 "$D/r18.cyr" 1 pa "*pa + *pb (once)"
rc=0; "$CC" --syntax-only < "$D/r1.cyr" > /dev/null 2> "$D/so.err" || rc=$?
if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$D/so.err")" -eq 1 ] && grep -qF "cannot dereference 'pa$MSG" "$D/so.err"; then
    ok "R19: --syntax-only refuses R1, one error"
else bad "R19: --syntax-only rc $rc: $(grep '^error' "$D/so.err" | head -2 | tr '\n' '|')"; fi

echo "C. controls, unchanged"
fnr c1 'var q: *u128 = *ppa; return load64(q);'
xr C1 "$D/c1.cyr" 5 "var q: *u128 = *ppa; (a pointer)"
mk c2 'fn main(): i64 { var a: u128 = 5; var p = &a; return *p; }
syscall(60, main());'
xr C2 "$D/c2.cyr" 5 "an untyped var p = &a; *p (the low word)"
fnr c3 'store64(pa, 9); return load64(pa) + load64(pa + 0);'
xr C3 "$D/c3.cyr" 18 "load64 / store64 on the halves"
fnr c4 'return *&a;'
xr C4 "$D/c4.cyr" 5 "*&a"
fnr c5 'var q = pa; return *q;'
xr C5 "$D/c5.cyr" 5 "an untyped copy var q = pa; *q"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — *pu through a typed *u128 is refused by name at the \`*\`, read or stored (F, R1-R19, the x86_64 / aarch64 / cx / PE compilers); an untyped pointer, a **u128's *pp and the halves are unchanged (C, every run leg)"
