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
#   T  tests/tcyr/crossos/double_pointer_deref_step.tcyr (its GI / GK rows: every `**S` source, a method, a `: T`
#      result, two type parameters, a named argument, a forward call, a forwarder, and the controls — a direct or a
#      struct carrier wins, a `*S`, a `**Q2` that is no `**T`, `(pps)` and `pps + 0` bind nothing; 6.7.15 (D11 (a)):
#      a `**i32` binds i32) on
#      x86_64 (default, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N
#      derived from the file; the release gate's cross-OS leg runs it on ecb / ach / cass / pi
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
FLOOR=40
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
NGI=$(grep -cE 'assert_eq\(.*"G[IK]: ' "$TC")
if [ "$NGI" -lt 14 ]; then echo "FAIL: $G: only $NGI GI / GK rows in $TC (floor 14) — rows were lost"; exit 1; fi

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

echo "T. $TC ($N rows, $NGI GI / GK)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`pp: **T\` parameter binds T from a \`**S\` argument (D40 A): the filed repros (R), a \`**P3\` parameter (P), a generic method (M), the explicit spelling (E), a \`**i32\` / \`**f64\` (S, D11 (a)) and $N rows (T) on x86_64 / IR / aarch64 / cx / PE"
