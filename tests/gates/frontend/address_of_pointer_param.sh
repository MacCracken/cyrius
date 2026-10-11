#!/bin/sh
# tests/gates/frontend/address_of_pointer_param.sh — 6.7.9
#
# `&q` OF A `q: *P` PARAMETER IS THE SLOT THAT HOLDS THE POINTER, as `&` of every other pointer is.
# 6.6.6 made `&q` of an address-passed BY-VALUE struct parameter (P over 8 B, its slot then holding
# the caller's struct's address) the slot's CONTENT. Its test, `_local_is_sptr_param`, answers 1 for a
# `q: *P` parameter too (the same struct type, the same non-inline layout), and the `&IDENT` arm never
# asked `_is_ptr_param`, as that predicate's other readers do. So for P over 8 B `&q` was the pointee:
# `load64(&q)` read q's first field and `store64(&q, o)` wrote into the caller's struct, while `&q` of
# a `*P` local, a `*Q` of 8 B or less and a `*i64` parameter was the slot (and 6.6.5 gave the slot for
# all of them). Since 6.6.16 a by-value parameter is copied into its own inline local, so the arm fired
# only for `*P` parameters — and for a `#naked` fn's by-value one, which keeps it. Now the arm asks
# `_addr_is_slot_content` (parse_fn.cyr). The user's decision 2(a). 6.6.6 - 6.7.8 measured, x86_64 /
# aarch64 / cx / PE. Filed: docs/development/issues/2026-10-10-address-of-pointer-param-over-8b-is-pointee.md
#
#   R1 the filed repro, verbatim, exits 0 (3 before) on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu),
#      cx (cxvm) and PE (wine)
#   R2 the filing's size probe (pa*27 + pb*9 + pc*3 + la; 1 = `load64(&q)` read the pointee, 2 = the
#      pointer) exits 80, every `&q` the slot (53 before: the `*P` parameter over 8 B alone read the
#      pointee), on the same legs
#   N  a `#naked` fn, compile only (it has no frame, so it is never run): its BY-VALUE `q: P` keeps the
#      6.6.6 arm — `var a = &q;` builds byte-identical to `var a = q;` of an i64 parameter (the slot's
#      content) — and its `q: *P` takes the slot — byte-identical to `var a = &q;` of an i64 parameter
#      (before: identical to the content load). x86_64, aarch64 and PE; on cx `#naked` is inert (the
#      by-value parameter is copied in, so only the `*P` half applies there)
#   T  tests/tcyr/crossos/address_of_pointer_param.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#
# MUTATION LEDGER (2026-10-11; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0  the fix reverted (the arm asks `_local_is_sptr_param` alone) -> RED R1 (exit 3) and R2 (53) on
#                                                    every leg; N the `*P` half on every leg; T 10 of 19
#                                                    rows on every leg (the `*P` ones; the controls and
#                                                    the inferred generic, whose T binds i64, green)
#   M1  `_addr_is_slot_content` answers 0 (the arm gone) -> RED N the by-value half on x86_64, aarch64
#                                                    and PE; R1, R2 and T green (no other `&q` reaches it)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=address_of_pointer_param
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

TC=tests/tcyr/crossos/address_of_pointer_param.tcyr
R1=docs/development/issues/repros/2026-10-10-address-of-pointer-param-over-8b-is-pointee.cyr
for f in "$TC" "$R1"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=19
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi

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

# build_leg <leg> <src> <out>: compile only; 0 = built.
build_leg() {
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3" 2> "$3.err" ;;
    esac
}
# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    if [ "$1" = pe ]; then build_leg pe "$2" "$3.exe" || return 0
    else build_leg "$1" "$2" "$3" || return 0; fi
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

echo "R1. the filed repro, verbatim: one meaning for \`&q\` (exit 0; 3 = the *P parameter's &q was the pointee)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'R1_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$R1" "$D/r_$n"
    if [ "$RC" -eq -1 ]; then bad "R1 $leg: did not build: $(grep -m1 'error' "$D/r_$n.err")"
    elif [ "$RC" -eq 0 ]; then ok "R1 $leg: exit 0"
    else bad "R1 $leg: exit $RC, want 0"; fi
done

echo "R2. the filing's size probe: \`&q\` of a *P (16 B), *Q (8 B), *i64 parameter and a *P local is the slot (exit 80; 53 before)"
cat > "$D/size.cyr" <<'EOF'
struct P { x; y; }
struct Q { x; }
fn pa(q: *P): i64 { var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn pb(q: *Q): i64 { var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn pc(q: *i64): i64 { var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn la(p0: P): i64 { var q: *P = &p0; var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn main(): i64 {
    var p = P { 4, 2 };
    var s = Q { 4 };
    var n = 4;
    return pa(&p) * 27 + pb(&s) * 9 + pc(&n) * 3 + la(p);
}
var rc = main();
syscall(60, rc);
EOF
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'R2_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/size.cyr" "$D/s_$n"
    if [ "$RC" -eq -1 ]; then bad "R2 $leg: did not build: $(grep -m1 'error' "$D/s_$n.err")"
    elif [ "$RC" -eq 80 ]; then ok "R2 $leg: exit 80"
    else bad "R2 $leg: exit $RC, want 80"; fi
done

echo "N. a #naked fn (compile only): by-value \`&q\` stays the slot's content, a *P parameter's \`&q\` is the slot"
# nk_src <param type> <initialiser> <out>: one #naked fn, kept by `&nk`, its asm a bare return.
nk_src() {
    cat > "$3" <<EOF
struct P { x; y; }
#naked
fn nk(q: $1): i64 {
    var a = $2;
    #ifdef CYRIUS_ARCH_X86
    asm { 0xC3; }
    #endif
    #ifdef CYRIUS_ARCH_AARCH64
    asm { 0xC0; 0x03; 0x5F; 0xD6; }
    #endif
}
var z = &nk;
syscall(60, 0);
EOF
}
nk_src P '&q' "$D/nk_bv.cyr"
nk_src '*P' '&q' "$D/nk_ptr.cyr"
nk_src i64 '&q' "$D/nk_addr.cyr"
nk_src i64 q "$D/nk_load.cyr"
for leg in x86 $OTHER; do
    nb=0
    for v in bv ptr addr load; do
        build_leg "$leg" "$D/nk_$v.cyr" "$D/nk_${v}_$leg" || { bad "N $leg: nk_$v did not build: $(grep -m1 'error' "$D/nk_${v}_$leg.err")"; nb=1; }
    done
    [ "$nb" = 0 ] || continue
    if [ "$leg" != cx ]; then
        if cmp -s "$D/nk_bv_$leg" "$D/nk_load_$leg"; then ok "N $leg: by-value q: P — \`&q\` is the slot's content (= \`q\` of an i64)"
        else bad "N $leg: by-value q: P — \`&q\` no longer builds as the slot's content (the 6.6.6 arm is gone)"; fi
    fi
    if cmp -s "$D/nk_ptr_$leg" "$D/nk_addr_$leg"; then ok "N $leg: q: *P — \`&q\` is the slot (= \`&q\` of an i64)"
    else bad "N $leg: q: *P — \`&q\` does not build as the slot's address"; fi
done

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — \`&q\` of a \`q: *P\` parameter is its slot: the filed repro (R1) and size probe (R2) on x86_64 / IR / aarch64 / cx / PE, the #naked halves (N), and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
