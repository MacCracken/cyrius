#!/bin/sh
# Gate: a type-argument list after an enum, Result, Option, Tagged or cstring is judged by what the name declares
# (6.7.16, the user's decision D88, 2026-10-20: "By declaration: refused where none are declared, read where
# declared").
#
# THE DEFECT (measured on 6.7.15 and the 6.7.16 lane before it, x86_64; the shared front end, every target): every type
# reader stepped the `<..>` after these names unread (`SKIP_GENERICS`), so `var e: Color<i64>`, `fn f(p: Result<Nope>)`,
# `s: cstring<i64>` and `t: Tagged<Zork>` compiled — a name in the list that is no type included — while a fn's own
# `: Option<i64>` return was a parse error with a cascade ("expected '{', got '<'", "undefined variable 'i64'"), and a
# trait member's `: Result<Nope>` against an impl's `: i64` compiled (the impl check counted the unread `Nope` as a side
# its reader refuses: issues/2026-10-20-enum-and-handle-type-arguments-unread.md). Now, by declaration:
#   * a name that declares no type parameters — an enum declared without `<..>` (above or below its use), Option and
#     Tagged (lib/tagged.cyr declares `enum Option: stack`), cstring, a program's own `enum Result` written without a
#     list — is refused once, at the name, with D7's words: "'Color' takes no type arguments" (`_ngt_tail`), the list
#     stepped, in every position D7 reaches; a position that refuses the bare name already (an enum return, a type
#     argument) keeps its one line;
#   * Result (lib/result.cyr's `enum Result<T, E>`; two when no enum declares it) and an enum declaring its own `<..>`
#     have the list READ (`_ngt_hread`): each argument as a type argument is read — "unknown type 'Nope' as a type
#     argument", D7's `Pt<i64>` inside it — nothing minted, a struct declared further down a name, and an argument past
#     the declared count is D5's "'Result' takes 2 type arguments, 3 given"; `fn g(): Result<i64, Pt>` compiles.
# Once per token (a generic's instances report once), silent under --syntax-only (as D6 / D7).
#
#   H1  the filed rn4.cyr verbatim — six lines, each at its name     H2  the filed `f(p: Result<Nope>, q: Option<Zork>)`
#   H3  the filed locals `Result<Nope>` / `Option<Pt<i64>>`         H4  `fn g(): Option<i64>` — one line, no cascade
#   H5  every position, Option / Tagged / cstring / an enum: a field, a pointer field, a union field, a zone global, a
#       trait member (its walk ends at its first refusal, as D7's), a parameter, `**X`, `*fn(X)`, a `*X` return, a
#       multi-value element, a generic body (three instances: once), `[X]`, `[*X]`, `slice<X>`, `Vec<X>`, `sizeof`
#   H6  the same positions, `Result<Nope>` (and `Result<T, Zork>` in the generic body)
#   H7  D5: `Result<i64, Pt, Pt>` as a parameter, a return and a local; in a generic body once
#   H8  enums declared below their use: `Late<i64>` refused, `LateG<Nope>` read, `LateG<i64>` compiles
#   H9  enums declaring their own `<..>`: `Gen<Nope>`, `Gen<i64, Pt>`, `Tri<..>` with four arguments
#   H10 a program's own `enum Result: stack` (no list) and `enum Option<T>: stack` — the declaration decides
#   H11 lib/result.cyr and lib/tagged.cyr included: `Option<i64>`, `Result<Nope>`, `Tagged<i64>`
#   H12 positions that refuse the bare name keep their one line: `fn a(): Color<i64>`, `Box<Option<i64>>`,
#       `Result<Result<Nope>>`, `Box<Color<i64>>`; and `Option<Pt<i64>>` is the name's line alone
#   H13 a trait member's walk goes on past a clean `Result<i64, Pt>` / `Gen<i64>` list (a refusal ends it, as D7's):
#       the next parameter's own "unknown type" line
#   HX  --syntax-only: H1-H4 and H6-H9 silent, rc 0
#   M0b CYRIUS_MONOMORPH=0 is read before pass 1 by every driver (a find repaired in passing): main_cx.cyr,
#       main_aarch64_native.cyr and main_aarch64_macho.cyr read it after, so pass 1 ran with the default flag and a
#       pointer field's `*Color<i64>` / `*Pt<i64>` was refused under the flag on cx and the native aarch64 compiler
#       (stepped on x86_64, PE, Mach-O x86 and the aarch64 cross compiler); run on the five legs and the native aarch64
#       compiler under qemu. Mutant: the drivers before (src/main_cx.cyr, src/main_aarch64_native.cyr at 636939df9) ->
#       RED M0b [cx] M0b [native]. The aarch64 Mach-O driver runs on macOS only: verified on ecb (the old driver refused
#       both fields under the flag, the new one compiles the program and it exits 4).
#   K1-K4 acceptance, run on x86_64, aarch64 (qemu-aarch64), cx (the tree's cxvm) and PE (wine, a private prefix): a
#       `: Result<i64, Pt>` return (exit 7); with lib/result.cyr, called above and below its definition (11); every read
#       position with a struct declared further down named in the list (3); an enum's own `Gen<i64>` (5)
# The runtime rows on every host are tests/tcyr/crossos/handle_type_args.tcyr. The impl / dyn hand-off (repro 2 and the
# residual: a method's `: Option<i64>` / `: Result<Pt<i64>>` return) is traits_checked.sh TRR7 / TRR8 / TRR10 and
# dyn_checked.sh F8r7 / F8r8 / F8p8.
#
# Refusal rows compare the whole error / warning list and check that no binary was written, on five legs: the x86_64
# compiler, its PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1) legs, and the aarch64 and cx compilers built from
# this tree. A cross compiler that does not build is RED; a missing qemu-aarch64 or wine is a SKIP line by name.
#
# MUTATION LEDGER (2026-10-21, f16 FG3; a scratch copy of the tree with the one change, its 2-stage cycc, this gate,
# traits_checked.sh and dyn_checked.sh run from the copy so every leg's compiler carries the mutant):
#   the lane before (src/ at 4ae0873f3)                -> RED H1-H12 K1-K4 (95 row-legs); traits_checked TRR1 TRR2 TRR5
#                                                         TRR7 TRR7b TRR8 TRR8b TRR10 TRR11b TRR12 TRR13 TRR13b;
#                                                         dyn_checked F8r7 F8r8 F8r8b F8p8 F8p13
#   `_ngt_tail` without its no-parameter arm            -> RED H1-H5 H8 H10-H12; TRR2 TRR5 TRR7 TRR7b; F8r8 F8p13
#   `_ngt_refuse` without `_ngt_hread`                  -> RED H2 H3 H6-H12 K1-K4; TRR1 TRR8 TRR8b TRR10 TRR11b TRR13
#                                                         TRR13b; F8r7 F8r8b F8p8
#   `_ngt_hread` without `_ta_late`                     -> RED K3 (a struct declared below, refused in pass 1's fields)
#   `_ngt_hread` answering a refused read as clean (2)  -> RED H6 (a member's walk went on past its refusal)
#   `_trs_ngt` marking a member bad on a clean read     -> RED H13 (the next parameter's own line swallowed)
#   `_ngt_skip` stepping a list only on 1 (refused)     -> RED H6 H7 H11 K1-K4; TRR8 TRR8b TRR11b TRR13b; F8r8b
#   `_ty_rd_reads` without the Result / generic enum arm -> RED TRR1 TRR8 TRR10 TRR10b; F8r7 F8r8b F8p8
#   `_ty_rd_shape` without `_ngt_hover`                 -> RED TRR13 TRR13b
#   `_tr_rt_bad` with 6.7.15's D4 arm as it was          -> RED TRR12
#   `_parse_one_type_arg` reading the list of a Result / Option / Tagged / cstring it refused as a type argument (the
#   `_c1 > -16` guard gone) -> GREEN: the panic latch and `_tn_once` already silence that read; the guard keeps the
#                              refused argument's list unread instead of leaning on them
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=handle_type_args
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

# comp <leg> <src> <out> [cc-arg]: the rc in CRC; `CENV` (an assignment, default a no-op) is set for the compile
CENV=CYRIUS_GATE_NOOP=1
comp() {
    CRC=0
    case "$1" in
        x86)   env "$CENV" timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    env "$CENV" CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) env "$CENV" CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   env "$CENV" timeout 60 "$D/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    env "$CENV" timeout 60 "$D/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        native) env "$CENV" timeout 300 qemu-aarch64 "$D/cc_native" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# execute <leg> <binary>: the exit in XRC, -1 = not run (NOTE says why)
execute() {
    XRC=-1; NOTE=""
    case "$1" in
        x86)   chmod +x "$2"; XRC=0; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64|native) if [ "$QEMU" = 1 ]; then chmod +x "$2"; XRC=0; timeout 120 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$?
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
# row <id> <what> <source> <want error / warning lines>: refused on every leg, the lines exactly, no binary
row() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"; comp "$leg" "$D/$1.cyr" "$o"; N=$((N + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then bad "$1 [$leg]: $2: rc 0 (compiled)"
        elif ! cmp -s "$o.got" "$D/$1.want"; then bad "$1 [$leg]: $2: got $(wc -l < "$o.got") line(s): $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 [$leg]: $2: refused, but a binary was written"
        else ok "$1 [$leg]: $2"; fi
    done
}
# quiet <id> <what>: --syntax-only on a row's source, every leg: rc 0 with no error / warning line
quiet() {
    for leg in $LEGS; do
        o="$D/$1_q$leg"; comp "$leg" "$D/$1.cyr" "$o" --syntax-only; N=$((N + 1))
        if [ "$CRC" -ne 0 ] || grep -qE '^(error|warning)' "$o.err"; then bad "$1 [$leg]: $2: rc $CRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
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
NG="takes no type arguments"
UT="as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)"
E='error:<source>:'
PB='struct Pt { x; y; }
struct Box<T> { v: T; n; }
enum Color { Red, Green }
'

echo "H — a list after a name that declares none is refused at the name; Result's / a generic enum's is read ($LEGS):"
row H1 "the filed rn4.cyr verbatim (it ran 6)" 'enum Color { Red, Green }
struct H { p: *Color<i64>; k; }
fn g(c: Color<Nope>, s: cstring<i64>, t: Tagged<Zork>): i64 { return 6; }
fn h(): *Color<i8> { return 0; }
fn main(): i64 { var e: Color<i64> = 0; var hh: H; hh.k = 0; return g(0, 0, 0); }
' "${E}2:16: 'Color' $NG
${E}3:9: 'Color' $NG
${E}3:25: 'cstring' $NG
${E}3:42: 'Tagged' $NG
${E}4:10: 'Color' $NG
${E}5:25: 'Color' $NG"
row H2 "the filed f(p: Result<Nope>, q: Option<Zork>) (it ran 3)" 'fn f(p: Result<Nope>, q: Option<Zork>): i64 { return 3; }
fn main(): i64 { return f(0, 0); }
' "${E}1:20: unknown type 'Nope' $UT
${E}1:26: 'Option' $NG"
row H3 "the filed locals Result<Nope> / Option<Pt<i64>> (it ran 5) — the refused list's Pt<i64> not reported too" 'struct Pt { x; y; }
fn main(): i64 { var r: Result<Nope> = 0; var o: Option<Pt<i64>> = 0; return 5; }
' "${E}2:36: unknown type 'Nope' $UT
${E}2:50: 'Option' $NG"
row H4 "fn g(): Option<i64> — one line (it was \"expected '{', got '<'\" + \"undefined variable 'i64'\")" 'fn g(): Option<i64> { return 0; }
fn main(): i64 { return g(); }
' "${E}1:9: 'Option' $NG"
row H5 "every position: Option / Tagged / cstring / an enum (a generic body's three instances once)" "${PB}"'struct H { e: Option<i64>; p: *Option<i64>; k; }
union U { e: Tagged<i64>; k; }
var G: cstring<i64> = 0;
trait T { fn m(self, a: Option<i64>, b: *Option<i64>): Option<i64>; }
fn f(a: Option<i64>, b: **Option<i64>, c: *fn(Option<i64>): i64): *Option<i64> { return 0; }
fn mv(): (Option<i64>, i64) { return (0, 1); }
fn g<T>(x: T): i64 { var e: Color<T> = 0; return 0; }
fn main(): i64 { var a: [Option<i64>] = 0; var b: [*Option<i64>] = 0; var c: slice<Option<i64>> = 0; var v: Vec<Option<i64>> = 0; return sizeof(Option<i64>) + g(1) + g(2.0) + g<i32>(3); }
' "${E}4:15: 'Option' $NG
${E}4:32: 'Option' $NG
${E}5:14: 'Tagged' $NG
${E}6:8: 'cstring' $NG
${E}7:25: 'Option' $NG
${E}8:9: 'Option' $NG
${E}8:27: 'Option' $NG
${E}8:47: 'Option' $NG
${E}8:68: 'Option' $NG
${E}9:11: 'Option' $NG
${E}10:29: 'Color' $NG
${E}11:26: 'Option' $NG
${E}11:53: 'Option' $NG
${E}11:84: 'Option' $NG
${E}11:113: 'Option' $NG
${E}11:145: 'Option' $NG"
row H6 "every position: Result<Nope> (and Result<T, Zork> in the generic body, once)" "${PB}"'struct H { e: Result<Nope>; p: *Result<Nope>; k; }
union U { e: Result<Nope>; k; }
var G: Result<Nope> = 0;
trait T { fn m(self, a: Result<Nope>, b: *Result<Nope>): Result<Nope>; }
fn f(a: Result<Nope>, b: **Result<Nope>, c: *fn(Result<Nope>): i64): *Result<Nope> { return 0; }
fn mv(): (Result<Nope>, i64) { return (0, 1); }
fn g<T>(x: T): i64 { var e: Result<T, Zork> = 0; return 0; }
fn main(): i64 { var a: [Result<Nope>] = 0; var b: [*Result<Nope>] = 0; var c: slice<Result<Nope>> = 0; var v: Vec<Result<Nope>> = 0; return sizeof(Result<Nope>) + g(1) + g(2.0) + g<i32>(3); }
' "${E}4:26: unknown type 'Nope' $UT
${E}4:44: unknown type 'Nope' $UT
${E}5:25: unknown type 'Nope' $UT
${E}6:19: unknown type 'Nope' $UT
${E}7:36: unknown type 'Nope' $UT
${E}8:20: unknown type 'Nope' $UT
${E}8:39: unknown type 'Nope' $UT
${E}8:60: unknown type 'Nope' $UT
${E}8:82: unknown type 'Nope' $UT
${E}9:22: unknown type 'Nope' $UT
${E}10:43: unknown type 'Zork' $UT
${E}11:37: unknown type 'Nope' $UT
${E}11:65: unknown type 'Nope' $UT
${E}11:97: unknown type 'Nope' $UT
${E}11:127: unknown type 'Nope' $UT
${E}11:160: unknown type 'Nope' $UT"
row H7 "D5: Result<i64, Pt, Pt> as a parameter, a return, a local; in a generic body once" 'struct Pt { x; y; }
fn a(r: Result<i64, Pt, Pt>): Result<i64, Pt, Pt, i8> { var l: Result<Pt, i64, i64> = 0; return 0; }
fn g<T>(x: T): i64 { var e: Result<T, Pt, Pt> = 0; return 0; }
fn main(): i64 { return g(1) + g(2.0) + g<i32>(3); }
' "${E}2:25: 'Result' takes 2 type arguments, 3 given
${E}2:47: 'Result' takes 2 type arguments, 4 given
${E}2:80: 'Result' takes 2 type arguments, 3 given
${E}3:43: 'Result' takes 2 type arguments, 3 given"
row H8 "enums declared below their use: Late<i64> refused, LateG<Nope> read" 'fn f(a: Late<i64>, b: LateG<Nope>, c: LateG<i64>): i64 { var x: Late<i8> = 0; return 3; }
enum Late { LA, LB }
enum LateG<T> { GA, GB }
fn main(): i64 { return f(0, 0, 0); }
' "${E}1:9: 'Late' $NG
${E}1:33: unknown type 'Nope' $UT
${E}1:65: 'Late' $NG"
row H9 "enums declaring their own <..>: Gen<Nope>, Gen<i64, Pt>, Tri<..> given four" 'struct Pt { x; y; }
enum Gen<T> { GA, GB }
enum Tri<T, U, V> { TA, TB }
fn f(a: Gen<Nope>, b: Gen<i64, Pt>, c: Tri<i64, Pt, i8>, d: Tri<i64, i64, i64, Pt>): i64 { return 3; }
fn main(): i64 { return f(0, 0, 0, 0); }
' "${E}4:17: unknown type 'Nope' $UT
${E}4:32: 'Gen' takes 1 type argument, 2 given
${E}4:80: 'Tri' takes 3 type arguments, 4 given"
row H10 "a program's own enum Result (no list) and enum Option<T>: the declaration decides" 'enum Result: stack { Ok(v); Err(e); }
enum Option<T>: stack { None(); Some(v); }
fn h(o: Option<i64>, p: Option<Nope>, r: Result<i64, i64>): i64 { return 1; }
fn main(): i64 { return h(0, 0, 0); }
' "${E}3:36: unknown type 'Nope' $UT
${E}3:42: 'Result' $NG"
row H11 "lib/result.cyr and lib/tagged.cyr included" 'include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/result.cyr"
include "lib/tagged.cyr"
struct Pt { x; y; }
fn g(): Result<i64, Pt> { return Ok(7); }
fn h(o: Option<i64>): i64 { return 1; }
fn k(r: Result<Nope>, t: Tagged<i64>): i64 { return 1; }
fn main(): i64 { var a, b = g(); return b; }
syscall(60, main());
' "${E}7:9: 'Option' $NG
${E}8:20: unknown type 'Nope' $UT
${E}8:26: 'Tagged' $NG"
row H12 "a position refusing the bare name keeps its one line; Option<Pt<i64>> is the name's line alone" "${PB}"'fn a(): Color<i64> { return 0; }
fn b(): i64 { var bx: Box<Option<i64>>; var r: Result<Result<Nope>> = 0; var o: Option<Pt<i64>> = 0; var c: Box<Color<i64>>; return 0; }
fn main(): i64 { return 0; }
' "${E}4:9: type 'Color' cannot be a fn return type
${E}5:33: generic type-args must be a scalar (i8/i16/i32/i64) or a struct; Result/Option/Tagged/cstring/f64v2/f64v4 are unsupported
${E}5:61: generic type-args must be a scalar (i8/i16/i32/i64) or a struct; Result/Option/Tagged/cstring/f64v2/f64v4 are unsupported
${E}5:81: 'Option' $NG
${E}5:113: 'Color' is an enum, not a type argument — enum values are i64; write i64"
row H13 "a trait member's walk goes on past a clean Result / Gen list: the next parameter's own line" 'struct Pt { x; y; }
trait T { fn m(self, a: Result<i64, Pt>, b: Nope): i64; fn n(self, a: Gen<i64>, b: Zork): i64; }
enum Gen<T> { GA, GB }
fn main(): i64 { return 0; }
' "${E}2:45: unknown type 'Nope' for parameter 'b'
${E}2:84: unknown type 'Zork' for parameter 'b'"

echo "HX — --syntax-only is silent (as D6 / D7):"
for r in H1 H2 H3 H4 H6 H7 H8 H9; do quiet "$r" "--syntax-only on $r"; done

echo "K — acceptance ($LEGS; run on x86_64, qemu-aarch64, cxvm and wine):"
runs K1 "fn g(): Result<i64, Pt> compiles (a parse error before)" 'include "lib/syscalls.cyr"
struct Pt { x; y; }
fn g(): Result<i64, Pt> { return 7; }
fn main(): i64 { return g(); }
syscall(60, main());
' 7
runs K2 "with lib/result.cyr: Result<i64, Pt> called above and below its definition (0 + 7 + 1 + 3)" 'include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/result.cyr"
struct Pt { x; y; }
fn main(): i64 { var t, v = g(); var t2, v2 = h(); return v + v2 + t + t2; }
fn g(): Result<i64, Pt> { return Ok(7); }
fn h(): Result { return Err(3); }
syscall(60, main());
' 11
runs K3 "every read position, a struct declared further down named in the list" 'include "lib/syscalls.cyr"
struct H { r: Result<Later, i64>; p: *Result<Later>; v: Vec<Result<Later>>; k; }
union U { r: Result<Later, i64>; k; }
fn f(a: Result<Later>, b: *Result<i64, Later>): Result<Later, i64> { var x: Result<Later> = 0; return 0; }
trait T { fn m(self, a: Result<Later>): Result<Later>; }
var G: Result<Later> = 0;
struct Later { a; b; }
fn main(): i64 { var h: H; h.k = 3; return h.k; }
syscall(60, main());
' 3
runs K4 "an enum declaring its own <T>: Gen<i64> as a local, a parameter, a field" 'include "lib/syscalls.cyr"
enum Gen<T> { GA, GB }
struct H { g: Gen<i64>; k; }
fn f(a: Gen<i64>): i64 { var l: Gen<i8> = GB; return a + l; }
fn main(): i64 { var h: H; h.g = GB; h.k = 3; return f(h.g) + h.k; }
syscall(60, main());
' 5

echo "M0b — every driver reads CYRIUS_MONOMORPH before pass 1 ($LEGS, and the native aarch64 compiler under qemu):"
# main_cx.cyr, main_aarch64_native.cyr and main_aarch64_macho.cyr read it AFTER pass 1, so pass 1 ran with the default
# flag under CYRIUS_MONOMORPH=0: a pointer field's `*Color<i64>` / `*Pt<i64>` was refused there, stepped on every
# other driver (a find repaired in passing; the Mach-O driver runs only on macOS — verified on ecb, not here).
M0L="$LEGS"
if [ "$QEMU" = 1 ] && [ -x "$D/cc_a64" ]; then
    if "$D/cc_a64" < src/main_aarch64_native.cyr > "$D/cc_native" 2> /dev/null && [ -s "$D/cc_native" ]; then chmod +x "$D/cc_native"; M0L="$M0L native"
    else bad "native: src/main_aarch64_native.cyr did not build"; fi
else echo "  SKIP: the native aarch64 compiler leg (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
CENV=CYRIUS_MONOMORPH=0
printf '%s' 'include "lib/syscalls.cyr"
enum Color { Red, Green }
struct Pt { x; y; }
struct H { p: *Color<i64>; q: *Pt<i64>; k; }
fn main(): i64 { var h: H; h.k = 4; return h.k; }
syscall(60, main());
' > "$D/M0b.cyr"
for leg in $M0L; do
    o="$D/M0b_$leg"; comp "$leg" "$D/M0b.cyr" "$o"; N=$((N + 1))
    if [ "$CRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
        bad "M0b [$leg]: CYRIUS_MONOMORPH=0 steps a pointer field's *Color<i64> / *Pt<i64>: rc $CRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"; continue
    fi
    execute "$leg" "$o"
    if [ "$XRC" = -1 ]; then ok "M0b [$leg]: CYRIUS_MONOMORPH=0 steps a pointer field's *Color<i64> / *Pt<i64> (compiled; not run: $NOTE)"
    elif [ "$XRC" = 4 ]; then ok "M0b [$leg]: CYRIUS_MONOMORPH=0 steps a pointer field's *Color<i64> / *Pt<i64> (exit 4)"
    else bad "M0b [$leg]: exit $XRC, want 4"; fi
done
CENV=CYRIUS_GATE_NOOP=1

if [ "$N" -lt 125 ]; then bad "corpus floor: $N row-legs (want >= 125)"; fi
echo "$G: $pass ok, $fail FAIL, $skips SKIP ($N row-legs)"
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red"; exit 1; fi
echo "PASS: $G — a type-argument list after an enum, Option, Tagged or cstring is refused once at the name; after Result or an enum declaring its own <..> it is read (an unknown name, D7's shape and D5's extra argument refused, a struct declared below a name), silent under --syntax-only; Result<i64, Pt> compiles and runs in every position"
