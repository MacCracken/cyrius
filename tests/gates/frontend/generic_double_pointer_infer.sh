#!/bin/sh
# tests/gates/frontend/generic_double_pointer_infer.sh — 6.7.14
#
# A `pp: **T` PARAMETER BINDS T TO THE STRUCT ITS `**S` ARGUMENT POINTS THROUGH TO (the user's decision D40 A,
# 2026-10-16). `**T` carried nothing (`_gs_param` reads one `*`), so `st(pps)` with `fn st<T>(pp: **T)` and
# `pps: **P3` ran the i64 base: `*pp + 1` stepped 8, not sizeof(P3), and `take(**pp)` into `*P3` passed the first
# field as the address (x86_64 / IR=3 / aarch64 139, cx a guest fault, PE 5) — where `st<P3>(pps)` steps 24 and
# `tg<P3>(pps)` gives 42. A T that no `x: T` / `p: *T` parameter and no generic struct carries is now carried by the
# first parameter declared exactly `**T` (`_gen_infer_ind`, `_pp_tparam`): the struct its whole argument's pin names
# (`_ic_pp_arg`) — a `**S` local, parameter, capture or global, a field chain, a `: **S` call, `&p` / `&G` of a `*S`.
# Free calls and generic methods alike. 6.7.13 (and every release before), every target.
# Filed: docs/development/issues/archived/2026-10-16-generic-double-pointer-parameter-pointee-unbound.md
#
#   R  the two filed repros, verbatim: 120 (56 before) and 42 (139 / cx fault / PE 5 before) — on x86_64,
#      x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine)
#   P  the same two generics with a `**P3` PARAMETER as the argument (`fn via(pps: **P3)`): 66 — every leg
#   M  a generic METHOD's `**T` (`s.gm(pps)`, `fn gm<T>(self, pp: **T)` in `impl P3`): 66 — every leg
#   E  the explicit spelling is unchanged: `st<P3>(pps) * 100 + tg<P3>(pps)` 2442 (the decision's reference) — every
#      leg
#   S  (6.7.15, the user's decision D11 (a), 2026-10-18) a SCALAR pointee binds too: `st(ppi)` with `ppi: **i32` steps
#      4 and `sz(ppi)` is 4, `gd(pph)` with `pph: **f64` is the f64 instance (its xmm result doubled: 5): 445 % 256 =
#      189 (was 112: the i64 base stepped 8 and returned the double's bits) — every leg (more sources:
#      tests/tcyr/crossos/generic_scalar_pointee_binding.tcyr's PP rows, generic_ptr_param_infer.sh PS)
#   W  (6.7.15, the user's decisions D22 A / D23 A, 2026-10-18) parentheses around the whole argument are transparent
#      and a typed pointer plus or minus n is still that pointer: W1 the filed repro verbatim, `tg((pps))` 42 (139,
#      cx 254, PE 5 before), W2 its table's `tg(pps + 0)` 42 (the same fault), W3 `tg((&ps))` 42 (the same fault),
#      W4 the single-star sibling through `p: *T` — `g((ps)) + g((&s)) + g(ps + 1) + g(1 + ps) + g((ps) - 1)`, each
#      step 24: 120 (72 before: the last three stepped 8); WK the controls — `g(ps + 1 & 3)` (a bitwise result),
#      `g(ps - ps)` (a distance), `g(&s + 0)` (a byte pointer, 6.7.11's D15) bind nothing (8 each), with the
#      explicit `tg<P3>((pps))` 42: 66 — every leg
#   D  (6.7.15, the user's decision D24 A, 2026-10-18) `ppp: ***T` and deeper bind T: D1 / D2 the filed repros
#      verbatim, `s3(ppps) * 10 + s3<P3>(ppps) / 24` 241 (81 before) and `t3(ppps)` 42 (139, cx 254, PE 5 before), D3
#      `t4(p4) + t3(&pps) - 42` with `p4: ****P3` and `&pps` of a `**P3` 42 (a fault before) — every leg
#   T  tests/tcyr/crossos/double_pointer_deref_step.tcyr (its GI / GK / GW / GD rows: every `**S` source, a method, a
#      `: T` result, two type parameters, a named argument, a forward call, a forwarder, and the controls — a direct or
#      a struct carrier wins, a `*S`, a `**Q2` that is no `**T`, `&ps + 0` bind nothing; 6.7.15 (D11 (a)): a `**i32`
#      binds i32; 6.7.15 (D22 A / D23 A): wrapped and computed arguments, a field / global / call + 0, a method, the
#      single-star `p: *T`, a generic forwarding the result into a method (the stub scan); (D24 A): `***T` / `****T`
#      from every source) on
#      x86_64 (default, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N
#      derived from the file; the release gate's cross-OS leg runs it on ecb / ach / cass / pi
#   B  (6.7.15, issues/2026-10-17-generic-double-pointer-to-generic-struct-parameter-refused.md) a generic's
#      `pp: **Box<T>` parameter, T its own type parameter, COMPILES — its pin is read under the binding its body has
#      (`_param_pin`: the base's T -> i64, an instance's own); it was refused "unknown type 'T' as a type argument" at
#      the definition (one error, every target). B1 the filed repro verbatim (7), B2 the explicit `nb<i64>(&p)` and
#      `**pp` as the struct value (a declaration copy, a by-value argument: 77), B3 the `<Pt>` instances, `**pp` read
#      through the instance's own pin (n at 16: 99), B4 a concrete `**Box<Pt>` parameter (11, unchanged) — every leg; more rows are
#      tests/tcyr/crossos/double_pointer_struct_value.tcyr's gb_* (small_struct_handle_line.sh R16)
#
# MUTATION LEDGER (2026-10-17; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run FROM
# that copy with CYCC= it, so every leg's compiler carries the mutant):
#   MD1 the fix reverted (`_gen_infer_tp` / `_mcall_infer`  -> RED R1 (56) and R2 (139, cx 254, PE 5), P and M (139,
#       ask `_gen_infer_sc` alone)                            cx 6, PE 5) on every leg; T: the file does not build
#                                                             (`v.c` of `var v = gi_gd(pps);` — T bound i64); E green
#   MD2 `_mcall_infer` unchanged (only the free call binds) -> RED M (139, cx 6, PE 5) on every leg; T (gi_meth 50
#                                                             for 66)
#   MD3 `_ic_pp_addr` answers i64 (no `&p` / `&G`)         -> RED T: x86_64 / IR / aarch64 139, PE 5 (the i64 base's
#                                                             `**pp` faults), cx 2 failed (gi_addr, gi_uses 8)
#   MD4 `_ic_pp_chain` answers 0 (no field chain)          -> RED T: 139 / PE 5, cx 1 failed (gi_fields)
#   MD5 `_ic_pp_name` without its capture rung             -> RED T: 139 / PE 5, cx 1 failed (gi_cap)
#   MD6 `_pp_is_tp` takes any `**X` (no T check)           -> RED T on every leg: 2 failed (gi_pair 2424 — B bound
#                                                             from `pa: **A`; gi_ctl2 — `gi_nt(ppq)` bound GiQ2)
# (2026-10-18, 6.7.15 — the S row and GK's `**i32`; CYCC= the mutant, so its x86_64 / IR / PE legs carry it:)
#   MS1 the fix reverted (the lane's previous compiler)    -> RED S (112) and T (gi_ctl 80808)
#   MS2 `_ic_pscalar` answers i64 (no scalar pointee)      -> RED S and T
#   MS3 `_ic_pscalar` binds without marking `_gi_sc`       -> RED S and T
#   MS4 `_ic_pp_sid` without its scalar arm                -> RED S and T
# (2026-10-18, 6.7.15 — the B rows; a scratch copy, its compiler, this gate run from it:)
#   MB1 `_param_pin` reading the pin unbound (`_ek_pin`)  -> RED B1-B4 on every leg (refused at the definition: B4's
#                                                             program holds the B2 / B3 generics too); the lane's
#                                                             previous compiler (x86 / IR / PE legs) the same
# (2026-10-18, 6.7.15 — the W / D rows and GW / GD; a scratch copy with the one change, its 2-stage cycc, CYCC= it:)
#   MW1 the fix reverted (the lane's previous compiler)    -> RED 40: W1-W3 / D2 / D3 (139, cx 254, PE 5), W4 (72),
#                                                             D1 (81) and T (the file does not build) on every leg;
#                                                             WK green
#   MW2 `_ic_pp_arg` without the `_pwrap_in` peel          -> RED W1, W3 (139 / cx 254 / PE 5) and T (x86_64 / IR /
#                                                             aarch64 139, PE 5, cx 3 failed: gi_wrap, gi_wmeth, gi_deep3)
#   MW3 `_ic_pp_arg` without its arithmetic arm            -> RED W2 and T (139 / PE 5, cx 4 failed: gi_arith,
#                                                             gi_arith2, gi_wmeth, gi_deep3)
#   MW4 `_ic_arg` without its arithmetic arm               -> RED W4 (72) and T (the file does not build: the stub row's
#                                                             r.pick, as the parser bound nothing)
#   MW5 `_ic_arith_end` taking any loosest operator        -> RED WK (82: `g(ps + 1 & 3)` bound P3)
#   MD7 `_pp_is_tp` taking exactly two stars               -> RED D1 (81), D2 / D3 (139, cx 254, PE 5) and T (the file
#                                                             does not build: `v.c` of `var v = gi_r3(ppps);`)
#   MD8 `_ic_pp_deep` without its hops                     -> RED D1-D3 and T (as MD7)
#   MD9 `_ic_pp_addr` without its `d > 2` arm              -> RED D3 and T (139 / PE 5, cx 3 failed: gi_deep, gi_deep2,
#                                                             gi_dctl — `&ps` into `***T` bound P3)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_double_pointer_infer
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

TC=tests/tcyr/crossos/double_pointer_deref_step.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=51
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
NGI=$(grep -cE 'assert_eq\(.*"G[IKWD]: ' "$TC")
if [ "$NGI" -lt 25 ]; then echo "FAIL: $G: only $NGI GI / GK / GW / GD rows in $TC (floor 25) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"

# xr <id> <src> <want> <what>: the exit on every leg
xr() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}

echo "R. the filed repros, verbatim (D40 A)"
cat > "$D/r1.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn st<T>(pp: **T): i64 { var a = *pp + 1; var b = *pp; return a - b; }               # a parameter
fn stl<T>(p: *T): i64 { var pp: **T = &p; var a = *pp + 1; var b = *pp; return a - b; }   # a local
fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; return st(pps) * 100 + stl(ps); }
syscall(60, main() % 256);
X
xr R1 "$D/r1.cyr" 120 "repro 1: st(pps) * 100 + stl(ps) (st steps 24)"
cat > "$D/r2.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return tg(pps); }
syscall(60, main());
X
xr R2 "$D/r2.cyr" 42 "repro 2: tg(pps) passes the struct to take"

# The repros' two generics, for the rows below.
cat > "$D/head.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn st<T>(pp: **T): i64 { var a = *pp + 1; var b = *pp; return a - b; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
impl P3 { fn gm<T>(self, pp: **T): i64 { var a = *pp + 1; var b = *pp; return a - b + take(**pp); } }
X
echo "P. a **P3 PARAMETER as the argument"
{ cat "$D/head.cyr"; printf '%s\n' 'fn via(pps: **P3): i64 { return st(pps) + tg(pps); }' \
    'fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; return via(&ps); }' 'syscall(60, main());'; } > "$D/p.cyr"
xr P "$D/p.cyr" 66 "via(pps: **P3): st(pps) + tg(pps)"
echo "M. a generic method's **T"
{ cat "$D/head.cyr"; printf '%s\n' \
    'fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return s.gm(pps); }' \
    'syscall(60, main());'; } > "$D/m.cyr"
xr M "$D/m.cyr" 66 "s.gm(pps) with fn gm<T>(self, pp: **T)"
echo "E. the explicit spelling (unchanged)"
{ cat "$D/head.cyr"; printf '%s\n' \
    'fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return st<P3>(pps) * 100 + tg<P3>(pps); }' \
    'syscall(60, main() % 256);'; } > "$D/e.cyr"
xr E "$D/e.cyr" 138 "st<P3>(pps) * 100 + tg<P3>(pps) (2442 % 256)"
echo "S. a **i32 / **f64 binds its scalar (6.7.15, D11 (a))"
cat > "$D/s.cyr" <<'X'
include "lib/syscalls.cyr"
fn st<T>(pp: **T): i64 { var a = *pp + 1; var b = *pp; return a - b; }
fn sz<T>(pp: **T): i64 { return sizeof(T); }
fn gd<T>(pp: **T): T { return **pp; }
fn ms(): i64 {
    var a: i32[4]; var pa: *i32 = &a; var ppi: **i32 = &pa;
    var h: f64 = 2.5; var ph: *f64 = &h; var pph: **f64 = &ph;
    var v = gd(pph) * 2.0;
    return st(ppi) * 100 + sz(ppi) * 10 + f64_to(v);
}
syscall(60, ms() % 256);
X
xr S "$D/s.cyr" 189 "st(ppi) 4, sz(ppi) 4, gd(pph) * 2.0 at f64 5 (445 % 256)"

echo "B. a generic's pp: **Box<T> parameter compiles (6.7.15)"
cat > "$D/b1.cyr" <<'X'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn nb<T>(pp: **Box<T>): i64 { var b: *Box<T> = *pp; return b.n; }
fn main(): i64 { var x: Box<i64>; x.n = 7; var p: *Box<i64> = &x; return nb(&p); }
syscall(60, main());
X
xr B1 "$D/b1.cyr" 7 "the filed repro: nb(&p)"
cat > "$D/bh.cyr" <<'X'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn nb<T>(pp: **Box<T>): i64 { var b: *Box<T> = *pp; return b.n; }
fn nv<T>(pp: **Box<T>): i64 { var b: Box<T> = **pp; return b.n; }
fn tk(b: Box<i64>): i64 { return b.n; }
fn nt<T>(pp: **Box<T>): i64 { return tk(**pp); }
fn nc(pp: **Box<Pt>): i64 { var b: *Box<Pt> = *pp; return b.n + b.v.y; }
X
{ cat "$D/bh.cyr"; printf '%s\n' \
    'fn main(): i64 { var x: Box<i64>; x.n = 7; var p: *Box<i64> = &x; return nb<i64>(&p) + nv(&p) * 10 + nt(&p) - 7; }' \
    'syscall(60, main());'; } > "$D/b2.cyr"
xr B2 "$D/b2.cyr" 77 "nb<i64>(&p) + nv(&p) * 10 + nt(&p) - 7"
{ cat "$D/bh.cyr"; printf '%s\n' \
    'fn main(): i64 { var y: Box<Pt>; y.v.y = 2; y.n = 9; var q: *Box<Pt> = &y; return nb<Pt>(&q) * 10 + nv<Pt>(&q); }' \
    'syscall(60, main());'; } > "$D/b3.cyr"
xr B3 "$D/b3.cyr" 99 "nb<Pt>(&q) * 10 + nv<Pt>(&q): the instance's pin (**pp a Box<Pt>)"
{ cat "$D/bh.cyr"; printf '%s\n' \
    'fn main(): i64 { var y: Box<Pt>; y.v.y = 2; y.n = 9; var q: *Box<Pt> = &y; return nc(&q); }' \
    'syscall(60, main());'; } > "$D/b4.cyr"
xr B4 "$D/b4.cyr" 11 "nc(&q) through a concrete **Box<Pt>"

echo "W. a wrapped or computed pointer argument binds as the pointer (6.7.15, D22 A / D23 A)"
# W1 the filed repro, verbatim (issues/2026-10-17-generic-double-pointer-argument-in-parentheses-binds-nothing.md).
cat > "$D/w1.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return tg((pps)); }
syscall(60, main());
X
xr W1 "$D/w1.cyr" 42 "the filed repro: tg((pps))"
sed -e 's/return tg((pps));/return tg(pps + 0);/' "$D/w1.cyr" > "$D/w2.cyr"
xr W2 "$D/w2.cyr" 42 "its table's tg(pps + 0)"
sed -e 's/return tg((pps));/return tg((\&ps));/' "$D/w1.cyr" > "$D/w3.cyr"
xr W3 "$D/w3.cyr" 42 "tg((&ps))"
cat > "$D/w4.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn g<T>(p: *T): i64 { var a = p + 1; var b = p; return a - b; }
fn main(): i64 { var s: P3; var ps: *P3 = &s; return g((ps)) + g((&s)) + g(ps + 1) + g(1 + ps) + g((ps) - 1); }
syscall(60, main());
X
xr W4 "$D/w4.cyr" 120 "through p: *T, g((ps)) + g((&s)) + g(ps + 1) + g(1 + ps) + g((ps) - 1) (24 each)"
cat > "$D/wk.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
fn g<T>(p: *T): i64 { var a = p + 1; var b = p; return a - b; }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return g(ps + 1 & 3) + g(ps - ps) + g(&s + 0) + tg<P3>((pps)); }
syscall(60, main());
X
xr WK "$D/wk.cyr" 66 "controls: g(ps + 1 & 3), g(ps - ps), g(&s + 0) bind nothing (8 each), tg<P3>((pps)) 42"

echo "D. a ***T (and deeper) binds T (6.7.15, D24 A)"
# D1 / D2 the filed repros, verbatim (issues/2026-10-17-generic-triple-pointer-parameter-carries-nothing.md).
cat > "$D/d1.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn s3<T>(ppp: ***T): i64 { var a = **ppp + 1; var b = **ppp; return a - b; }
fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; var ppps: ***P3 = &pps; return s3(ppps) * 10 + s3<P3>(ppps) / 24; }
syscall(60, main());
X
xr D1 "$D/d1.cyr" 241 "repro 1: s3(ppps) * 10 + s3<P3>(ppps) / 24 (s3 steps 24)"
cat > "$D/d2.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn t3<T>(ppp: ***T): i64 { return take(***ppp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; var ppps: ***P3 = &pps; return t3(ppps); }
syscall(60, main());
X
xr D2 "$D/d2.cyr" 42 "repro 2: t3(ppps) passes the struct to take"
cat > "$D/d3.cyr" <<'X'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn t3<T>(ppp: ***T): i64 { return take(***ppp); }
fn t4<T>(p4: ****T): i64 { return take(****p4); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; var ppps: ***P3 = &pps; var p4: ****P3 = &ppps; return t4(p4) + t3(&pps) - 42; }
syscall(60, main());
X
xr D3 "$D/d3.cyr" 42 "t4(p4) of a ****P3 and t3(&pps) of a **P3"

echo "T. $TC ($N rows, $NGI GI / GK / GW / GD)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`pp: **T\` parameter binds T from a \`**S\` argument (D40 A): the filed repros (R), a \`**P3\` parameter (P), a generic method (M), the explicit spelling (E), a \`**i32\` / \`**f64\` (S, D11 (a)), a \`pp: **Box<T>\` parameter (B, 6.7.15), a wrapped or computed argument (W, D22 A / D23 A), a \`***T\` and deeper (D, D24 A) and $N rows (T) on x86_64 / IR / aarch64 / cx / PE"
