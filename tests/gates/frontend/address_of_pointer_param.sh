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
#   R3 6.7.16 — issues/2026-10-18-dereference-of-address-of-compound-assignment-steps-one-byte.md row 1, the
#      filed repro verbatim: `*(&pi) += 1` of a `pi: *i32` steps 4 bytes, as `q += 1` does (6.7.15's D21 A:
#      `*(&p)` is p) — exit 44 (14 before: one byte) on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm)
#      and PE (wine); the amp_cop_* rows in T carry its shapes
#   R4 6.7.16 (D21, the user's decision, 2026-10-19) — the same issue's row 3, the filed repro verbatim: `*(&GQ)`
#      of a packed `i32` global reads GQ alone, at its width, as GQ itself — exit 5 (59 before: 8 bytes, GQ and
#      the next global GR) on the same legs; the amp_narrow_* rows in T carry its shapes (stores, OP=, the
#      widths and signs, a for step, top level) and its controls (`*(&GQ + 0)`, a capture, an i64)
#   R6 6.7.16 — issues/2026-10-19-signed-narrow-global-declared-after-top-level-statement-reads-zero-extended.md,
#      the filed repro verbatim: a signed i16 / i32 / i8 global declared after the first top-level statement reads
#      sign-extended, as one in the declaration zone — prints `-2 -2 -2` (`65534 4294967294 254` before) on x86_64,
#      x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine); T's amp_narrow_after row and
#      tests/tcyr/crossos/narrow_global_init_width.tcyr's ps_ rows carry its shapes
#   R7 6.7.16 (D72, the user's decision, 2026-10-20) — issues/2026-10-19-narrow-parameter-holds-caller-word-unnarrowed.md,
#      the filed repro verbatim: a narrow parameter is narrowed in the fn, like a narrow local — prints
#      `255 -1 -32768 -32768` (`511 8589934591 32768 -32768` before) on x86_64, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1, aarch64 (qemu), cx (cxvm) and PE (wine); T2 carries its shapes
#   T  tests/tcyr/crossos/address_of_pointer_param.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#   T2 tests/tcyr/crossos/narrow_param_width.tcyr (D72's rows: every width and sign, stack-passed, a fn pointer,
#      `*(&y)`, `y = v` / `OP=`, a capture, #inline, a generic `x: T`, a method, a default, #regalloc; the controls) on
#      the same 7 legs, N2 derived from the file the same way (floor FLOOR2)
#
# MUTATION LEDGER (2026-10-11; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0  the fix reverted (the arm asks `_local_is_sptr_param` alone) -> RED R1 (exit 3) and R2 (53) on
#                                                    every leg; N the `*P` half on every leg; T 10 of 19
#                                                    rows on every leg (the `*P` ones; the controls and
#                                                    the inferred generic, whose T binds i64, green)
#   M1  `_addr_is_slot_content` answers 0 (the arm gone) -> RED N the by-value half on x86_64, aarch64
#                                                    and PE; R1, R2 and T green (no other `&q` reaches it)
#   M2  (2026-10-19) `_deref_store` without its `_amp_pw` line (the 6.7.16 fix reverted) -> RED 12: R3 (exit
#                                                    14) on all 5 legs; T on all 7 legs, the 11 amp_cop_*
#                                                    step rows (the `*u8` control green)
#   M3  (2026-10-19) `_amp_ew` answers 0 (D21's width reverted) -> RED 12: R4 (exit 59) on all 5 legs; T
#                                                    on all 7 legs, the 12 amp_narrow_* rows that read or
#                                                    write a narrow local or packed global (the parameter
#                                                    row and the controls green)
#   M4  (2026-10-19) `_deref_store` without its `_amp_ew` line (the read kept) -> RED 7: T on all 7 legs,
#                                                    the 7 store / OP= rows on packed globals (a local's
#                                                    8-byte slot hides a word store); R4 green (a read)
#   M5  (2026-10-21) PARSE_VAR's top-level arm without its SVSGN line (the 6.7.16 fix reverted) -> RED 12: R6
#                                                    (`65534 4294967294 254`) on all 5 legs; T the amp_narrow_after
#                                                    row on all 7 legs
#   M6  (2026-10-21) the parameter loop without its `_pnw_apply` line (the 6.7.16 D72 fix reverted) -> RED 14:
#                                                    R7 (`511 8589934591 32768 -32768`) and T2 (48 of 59 rows) on all 7
#                                                    legs
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
FLOOR=58
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
TC2=tests/tcyr/crossos/narrow_param_width.tcyr
[ -f "$TC2" ] || { echo "FAIL: $G: $TC2 is missing"; exit 1; }
N2=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC2")
FLOOR2=59
if [ "$N2" -lt "$FLOOR2" ]; then echo "FAIL: $G: only $N2 rows in $TC2 (floor $FLOOR2) — rows were lost"; exit 1; fi

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

echo "R3. 6.7.16: the filed repro verbatim — \`*(&pi) += 1\` of a *i32 steps 4 bytes, as \`q += 1\` (exit 44; 14 = one byte)"
cat > "$D/cop.cyr" <<'EOF'
fn run(): i64 {
  var buf: i64[4];
  var pi: *i32 = &buf;
  var q: *i32 = &buf;
  *(&pi) += 1;
  q += 1;
  var a = pi; var b = q; var o = &buf;
  return (a - o) * 10 + (b - o);
}
syscall(60, run());
EOF
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'R3_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/cop.cyr" "$D/c_$n"
    if [ "$RC" -eq -1 ]; then bad "R3 $leg: did not build: $(grep -m1 'error' "$D/c_$n.err")"
    elif [ "$RC" -eq 44 ]; then ok "R3 $leg: exit 44"
    else bad "R3 $leg: exit $RC, want 44"; fi
done

echo "R4. 6.7.16 (D21): the filed row-3 repro verbatim — \`*(&GQ)\` of a packed i32 global reads GQ alone (exit 5; 59 = GQ and GR)"
cat > "$D/narrow.cyr" <<'EOF'
var GQ: i32 = 5;
var GR: i32 = 9;
fn run(): i64 { var x = *(&GQ); if (x == 5) { return 5; } if (x == 5 + (9 << 32)) { return 59; } return 1; }
syscall(60, run());
EOF
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'R4_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/narrow.cyr" "$D/w_$n"
    if [ "$RC" -eq -1 ]; then bad "R4 $leg: did not build: $(grep -m1 'error' "$D/w_$n.err")"
    elif [ "$RC" -eq 5 ]; then ok "R4 $leg: exit 5"
    else bad "R4 $leg: exit $RC, want 5"; fi
done

echo "R6. 6.7.16: the filed repro verbatim — a signed narrow global declared after a top-level statement reads sign-extended (\`-2 -2 -2\`; \`65534 4294967294 254\` before)"
cat > "$D/sglob.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
var Z = 0;
Z = 1;
var GS: i16 = 0 - 2;
var GI: i32 = 0;
var GB: i8 = 0;
fn main(): i64 {
    GI = 0 - 2;
    GB = 0 - 2;
    pr(GS); pr(GI); pr(GB);
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'R6_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/sglob.cyr" "$D/g_$n"
    if [ "$RC" -eq -1 ]; then bad "R6 $leg: did not build: $(grep -m1 'error' "$D/g_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "-2 -2 -2 " ]; then ok "R6 $leg: '$LAST'"
    else bad "R6 $leg: exit $RC, '$LAST' (want '-2 -2 -2 ')"; fi
done

echo "R7. 6.7.16 (D72): the filed repro verbatim — a narrow parameter is narrowed in the fn (\`255 -1 -32768 -32768\`; \`511 8589934591 32768 -32768\` before)"
cat > "$D/nparam.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
fn wid(y: u8): i64 { return y; }
fn w32(y: i32): i64 { return y; }
fn inc(y: i16): i64 { y += 1; return y; }
fn inc_l(a: i16): i64 { var y: i16 = a; y += 1; return y; }
fn main(): i64 {
    pr(wid(0x1FF));          # a u8 holds 0..255
    pr(w32(0x1FFFFFFFF));    # an i32 holds -2^31..2^31-1
    pr(inc(0x7FFF));         # i16 32767 + 1
    pr(inc_l(0x7FFF));       # the same through an i16 local
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf 'R7_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/nparam.cyr" "$D/p_$n"
    if [ "$RC" -eq -1 ]; then bad "R7 $leg: did not build: $(grep -m1 'error' "$D/p_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "255 -1 -32768 -32768 " ]; then ok "R7 $leg: '$LAST'"
    else bad "R7 $leg: exit $RC, '$LAST' (want '255 -1 -32768 -32768 ')"; fi
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

echo "T2. $TC2 ($N2 rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC2" "$D/t2_$n"
    if [ "$RC" -eq -1 ]; then bad "T2 $leg: the values file did not build: $(grep -m1 'error' "$D/t2_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N2 passed, 0 failed ($N2 total)" ]; then ok "T2 $leg: $LAST"
    else bad "T2 $leg: exit $RC, '$LAST' (want '$N2 passed, 0 failed ($N2 total)') $(grep -m3 'FAIL' "$D/t2_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — \`&q\` of a \`q: *P\` parameter is its slot: the filed repro (R1) and size probe (R2) on x86_64 / IR / aarch64 / cx / PE, the #naked halves (N), \`*(&pi) += 1\` steps the element (R3), \`*(&GQ)\` of a narrow global reads its width (R4), a signed narrow global after a statement reads signed (R6), a narrow parameter is narrowed (R7), and $N + $N2 rows (T / T2) on x86_64 / IR / DCE / aarch64 / cx / PE"
