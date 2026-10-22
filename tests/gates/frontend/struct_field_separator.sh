#!/bin/sh
# Gate: a struct's and a union's fields are separated by `;` (6.7.16, the user's decision D69, 2026-10-20: "Refuse it by
# name").
#
# THE DEFECT (measured on 6.7.15 and the 6.7.16 lane before it, x86_64; the shared front end, every target): the field
# loops of PARSE_STRUCT_DEF and PARSE_UNION_DEF stepped a `;` after a field when one was there and read the next field
# wherever the cursor stood, so `struct P { a b }` and `struct Q { x: i64 y: i64 }` compiled (the filed repro ran 46,
# as the separated form does), `union U { a: i64 b: i32 }` too, and one field per line with no `;`
# (issues/archived/2026-10-19-struct-and-union-fields-need-no-separator.md). Now a field that follows another with no `;` is ONE
# error at it, "expected ';' between struct fields" ("... union fields") — once per declaration (the declaration's `}`
# releases the latch, `_tl_decl1`, so the next declaration reports its own), under --syntax-only too, a line break
# being no separator, and a generic struct's instances (`_inst_name`) say nothing more. The last field may omit its `;`
# (`struct P { a; b }`), and the separated forms keep their offsets. A `,` keeps the loop's own "expected identifier,
# got ','". D12's enum members (enum_member_separator.sh) and 6.7.15's D1 (a) struct literal elements are the twins.
#
#   S1  the filed repro verbatim: two declarations, each its own error
#   S2  a union
#   S3  one field per line with no `;`
#   S4  a generic struct, used at two instances in one expression — once, the expression's own error kept
#   S5  three declarations: two refused, a valid one between them — each refused one its own error
#   S6  two missing separators in one struct and in one union — once each
#   S7  after every kind of field: a pointer, a Vec, a tuple, a narrow scalar, a struct, a generic instance
#   S8  --syntax-only: S1's and S3's lines
#   S9  control: a `,` between fields stays "expected identifier, got ','"
#   S10 a #derive(Serialize) struct: the one error, nothing from the derive
#   A1-A5 acceptance, run on x86_64, aarch64 (qemu-aarch64), cx (the tree's cxvm) and PE (wine, a private prefix): the
#       filed values separated and without a final `;`, mixed widths, a union, a generic struct, a K&R field-per-line
#
# Refusal rows compare the whole error / warning list and check that no binary was written, on five legs: the x86_64
# compiler, its PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1) legs, and the aarch64 and cx compilers built from
# this tree. A cross compiler that does not build is RED; a missing qemu-aarch64 or wine is a SKIP line by name.
#
# MUTATION LEDGER (2026-10-21, f16 FF6; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from the copy so every leg's compiler carries the mutant):
#   the lane before it (af28fa634)                     -> RED S1-S8 S10 on every leg, 50 (each compiled, rc 0; S4 its
#                                                      `(1 2)` alone)
#   `_fld_sep` without its error                       -> RED S1-S8 S10 on every leg, 50
#   `_tl_decl1` without its latch release              -> RED S1 S5 S6 S7 S8a on every leg, 25 (the next declaration's
#                                                      error lost)
#   `_fld_sep` erring on any token but `;` / `}`       -> RED S9 on every leg, 5 (the separator said for a `,`)
#   `_fld_sep` reporting in a generic's instance too   -> RED S4 on every leg, 5 (the repeat, printed as nothing,
#                                                      latched: the expression's "expected ')'" swallowed)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_field_separator
[ -x "$CC" ] || { echo "SKIP: $G: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: $G: mktemp -d failed"; exit 77; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit.
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
ulimit -c 0 2>/dev/null || true

pass=0; fail=0; skips=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

LEGS="x86 pe macho"
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; LEGS="$LEGS a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then chmod +x "$D/cc_cx" "$D/cxvm"; LEGS="$LEGS cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
QEMU=0; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then QEMU=1
else echo "  SKIP: the aarch64 run leg (qemu-aarch64 not installed; its refusal rows still run)"; skips=$((skips + 1)); fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: the PE run leg (wine not installed; its refusal rows still run)"; skips=$((skips + 1)); fi

# comp <leg> <src> <out> [cc-arg]: the rc in CRC
comp() {
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$D/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$D/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# execute <leg> <binary>: the exit in XRC, -1 = not run (NOTE says why)
execute() {
    XRC=-1; NOTE=""
    case "$1" in
        x86)   chmod +x "$2"; XRC=0; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64)   if [ "$QEMU" = 1 ]; then chmod +x "$2"; XRC=0; timeout 120 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$?
               else NOTE="qemu-aarch64 not installed"; fi ;;
        cx)    XRC=0; timeout 120 "$D/cxvm" < "$2" > /dev/null 2>&1 || XRC=$? ;;
        pe)    if [ "$WINE" = 1 ]; then
                   cp "$2" "$2.exe"; XRC=0
                   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                       WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "$2.exe" > /dev/null 2>&1) || XRC=$?
               else NOTE="wine not installed"; fi ;;
        macho) NOTE="no Mach-O loader on Linux" ;;
    esac
}
N=0
# row <id> <what> <source> <want error / warning lines> [cc-arg]: refused on every leg, the lines exactly, no binary
row() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"; comp "$leg" "$D/$1.cyr" "$o" "${5:-}"; N=$((N + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then bad "$1 [$leg]: $2: rc 0 (compiled)"
        elif ! cmp -s "$o.got" "$D/$1.want"; then bad "$1 [$leg]: $2: got $(wc -l < "$o.got") line(s): $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ] && [ -z "${5:-}" ]; then bad "$1 [$leg]: $2: refused, but a binary was written"
        else ok "$1 [$leg]: $2"; fi
    done
}
# runs <id> <what> <source> <exit>: compiles clean on every leg, runs <exit> wherever a runner is
runs() {
    printf '%s' "$3" > "$D/$1.cyr"
    for leg in $LEGS; do
        o="$D/$1_$leg"; comp "$leg" "$D/$1.cyr" "$o"; N=$((N + 1))
        if [ "$CRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            bad "$1 [$leg]: $2: rc $CRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"; continue
        fi
        execute "$leg" "$o"
        if [ "$XRC" = -1 ]; then ok "$1 [$leg]: $2 (compiled; not run: $NOTE)"
        elif [ "$XRC" = "$4" ]; then ok "$1 [$leg]: $2 (exit $XRC)"
        else bad "$1 [$leg]: $2: exit $XRC, want $4"; fi
    done
}
SF="expected ';' between struct fields"
UF="expected ';' between union fields"
ZZ="undefined variable 'zz' (missing include or enum?)"

echo "S — a missing ';' between two fields is one error at the second, on every leg ($LEGS):"
row S1 "filed: struct P { a b } and struct Q { x: i64 y: i64 } (it compiled, exit 46)" 'struct P { a b }
struct Q { x: i64 y: i64 }
fn f(): i64 { var p = P { 3, 4 }; var q = Q { 5, 6 }; return p.b * 10 + q.y; }
syscall(60, f());
' "error:<source>:1:14: $SF
error:<source>:2:19: $SF"
row S2 "a union, union U { a: i64 b: i32 }" 'union U { a: i64 b: i32 }
fn f(): i64 { var u: U; u.a = 5; return u.a + zz; }
syscall(60, f());
' "error:<source>:1:18: $UF
error:<source>:2:49: $ZZ"
row S3 "one field per line with no ';'" 'struct Q {
    x: i64
    y: i64
}
fn f(): i64 { var q = Q { 5, 6 }; return q.y + zz; }
syscall(60, f());
' "error:<source>:3:5: $SF
error:<source>:5:50: $ZZ"
row S4 "a generic struct at two instances in one expression: once, the expression's own error kept" 'struct B<T> { a: T b: i64 }
fn f(): i64 { return sizeof(B<i32>) + sizeof(B<i64>) + (1 2); }
syscall(60, f());
' "error:<source>:1:20: $SF
error:<source>:2:59: expected ')', got number 2"
row S5 "three declarations, a valid one between: each refused one its own error" 'struct P { a b }
struct R { x; y; }
struct Q { c: i8 d: i8 }
fn f(): i64 { var r = R { 1, 2 }; return r.y + zz; }
syscall(60, f());
' "error:<source>:1:14: $SF
error:<source>:3:18: $SF
error:<source>:4:50: $ZZ"
row S6 "two missing separators in one struct and in one union: once each" 'struct P { a b c }
union V { p q r }
fn f(): i64 { return zz; }
syscall(60, f());
' "error:<source>:1:14: $SF
error:<source>:2:13: $UF
error:<source>:3:24: $ZZ"
row S7 "after every kind of field: a pointer, a Vec, a tuple, a narrow scalar, a struct, a generic instance" 'struct Pt { x; y; }
struct Bx<T> { v: T; }
struct P1 { a: *i64 b }
struct P2 { a: Vec<i64> b }
struct P3 { a: (i64, i64) b }
struct P4 { a: i8 b }
struct P5 { a: Pt b }
struct P6 { a: Bx<i32> b }
union U1 { a: *i64 b }
union U2 { a: i16 b }
fn f(): i64 { return zz; }
syscall(60, f());
' "error:<source>:3:21: $SF
error:<source>:4:25: $SF
error:<source>:5:27: $SF
error:<source>:6:19: $SF
error:<source>:7:19: $SF
error:<source>:8:24: $SF
error:<source>:9:20: $UF
error:<source>:10:19: $UF
error:<source>:11:24: $ZZ"
row S8a "--syntax-only: S1's lines" 'struct P { a b }
struct Q { x: i64 y: i64 }
fn f(): i64 { var p = P { 3, 4 }; var q = Q { 5, 6 }; return p.b * 10 + q.y; }
syscall(60, f());
' "error:<source>:1:14: $SF
error:<source>:2:19: $SF" --syntax-only
row S8b "--syntax-only: S3's line" 'struct Q {
    x: i64
    y: i64
}
syscall(60, 0);
' "error:<source>:3:5: $SF" --syntax-only
row S9 "control: a ',' between fields stays the loop's own error" 'struct P { a, b }
fn f(): i64 { return zz; }
syscall(60, f());
' "error:<source>:1:13: expected identifier, got ','
error:<source>:2:24: $ZZ"
row S10 "a #derive(Serialize) struct: the one error, nothing from the derive" 'include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/bayan.cyr"
#derive(Serialize)
struct P { a: i64 b: i64 }
fn f(): i64 { return zz; }
syscall(60, f());
' "error:<source>:8:19: $SF
error:<source>:9:24: $ZZ"

echo "A — the separated forms compile and keep their offsets, run on every leg with a runner:"
runs A1 "the filed values, separated, the last field without its ';'" 'struct P { a; b }
struct Q { x: i64; y: i64 }
fn f(): i64 { var p = P { 3, 4 }; var q = Q { 5, 6 }; return p.b * 10 + q.y; }
syscall(60, f());
' 46
runs A2 "mixed widths: sizeof 13, each field at its offset" 'struct M { a: i8; b: i32; c: i64 }
fn f(): i64 { var m = M { 1, 2, 3 }; var p = &m; return sizeof(M) * 4 + load8(p) + load32(p + 1) * 2 + load64(p + 5) * 3; }
syscall(60, f());
' 66
runs A3 "a union, the last member without its ';'" 'union U { a: i64; b: i32 }
fn f(): i64 { var u: U; u.a = 0; u.b = 7; return sizeof(U) * 10 + u.a; }
syscall(60, f());
' 87
runs A4 "a generic struct at two instances" 'struct B<T> { a: T; b: i64 }
fn f(): i64 { var x: B<i32>; x.b = 3; return sizeof(B<i32>) + sizeof(B<i64>) + x.b; }
syscall(60, f());
' 31
runs A5 "one field per line with its ';', a K&R brace, the last field bare" 'struct R
{
    x: i8;
    y: i64;
    z: i16
}
fn f(): i64 { var r = R { 2, 30, 5 }; return sizeof(R) * 2 + r.x + r.y + r.z; }
syscall(60, f());
' 59

# The floor: 11 refusal rows and 5 acceptance rows on five legs. A leg that did not build is RED above.
FLOOR=80
[ "$N" -ge "$FLOOR" ] || bad "the rows ran $N row-legs (floor $FLOOR) — rows or legs were lost"
echo "$G: $pass passed, $fail failed, $skips skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
