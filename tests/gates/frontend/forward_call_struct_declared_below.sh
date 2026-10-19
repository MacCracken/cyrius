#!/bin/sh
# tests/gates/frontend/forward_call_struct_declared_below.sh — 6.7.15
#
# A CALL ABOVE A FN WHOSE SIGNATURE NAMES A STRUCT DECLARED BELOW THAT FN GETS THE SIGNATURE THE DEFINITION HAS. Pass 1
# records each fn's ABI facts as it meets the fn (`_prescan_fn_sig`, CO-01), and a struct declared below the fn was not
# registered yet, so the record named no struct; a call parsed before the definition read it. A 16 / 24 B by-value
# argument was pushed as its first word (139), `h(t)` into `x: *R2` was refused "cannot pass 't' ... pass &t for its
# address", a `: Pq` return took no hidden result pointer (139 / cx 0 or 254 / PE 5), an untyped `var t = mk(10);` was
# "no struct type in scope for 't'", and a struct named like a vector was the vector ("vector return type does not
# match the declared type"). Once every struct is registered, a signature naming one registered after it is read again
# (`_psig_reread`, src/frontend/parse_fn_def.cyr). Filed:
#   docs/development/issues/2026-10-17-forward-call-struct-parameter-of-struct-declared-below-fn.md
#   docs/development/issues/2026-10-17-forward-call-struct-return-of-struct-declared-below-fn.md
#
#   P  the parameter filing's repros, verbatim: P1 16 B by value (7), P1b its 24 B variant (7), P2 `g(&t) * 10 + h(t)`
#      into `x: *R2` (77)
#   R  the return filing's repros, verbatim: R1 24 B (10), R1b 16 B, R1c 8 B, R1u untyped (10 each), R1v named
#      `f32v4` (10: the program's struct, 6.7.14's D41 A)
#   C  controls: the callee defined ABOVE the caller with the struct still last (7; the return filing's 17), the struct
#      declared first (7)
#   T  tests/tcyr/crossos/forward_call_struct_declared_below.tcyr (8 / 16 / 24 B by value, `*S` read and written, a
#      method by `.` and by name, generic instances `One<B16>` / `Low<B24>`, a vector-named struct, parameter 62, every
#      return shape, the struct-above control): "N passed, 0 failed (N total)", N derived from the file
# every row on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine); the release gate's cross-OS leg
# runs T on ecb / ach / cass / pi. The argument type check a forward call now gets is struct_arg_type_refused.sh FB.
#
# MUTATION LEDGER (2026-10-18; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run FROM
# that copy with CYCC= it, so every leg's compiler carries the mutant):
#   `_psig_reread` returning at once (the 8b4d44602 behaviour) -> RED 45: every P / R row on every leg (139; cx 1 / 0 /
#       254; PE 5; P2 R1u R1v refused) and T on every leg (the file does not build: "pass &t"); C green
#   `_psig_one` without the impl context (`_impl_tnoff`)      -> RED 5: T on every leg (`H_take(h, t)`: 139; cx "guest
#       address out of range"; PE 5)
#   `_psig_one` without its last-definition test              -> green here: struct_arg_type_refused.sh FB3
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=forward_call_struct_declared_below
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

TC=tests/tcyr/crossos/forward_call_struct_declared_below.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
if [ "$N" -lt 21 ]; then echo "FAIL: $G: only $N rows in $TC (floor 21) — rows were lost"; exit 1; fi

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
LEGS="x86 x86:CYRIUS_IR=3 $OTHER"

# xr <id> <src> <want> <what>: the exit on every leg
xr() {
    for leg in $LEGS; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}

echo "P. the parameter filing's repros, verbatim"
cat > "$D/p1.cyr" <<'X'
include "lib/syscalls.cyr"
fn main() { var t: R2 = R2 { 5, 7 }; return g(t); }
fn g(x: R2): i64 { return x.b; }
struct R2 { a; b; }
var r = main();
syscall(SYS_EXIT, r);
X
xr P1 "$D/p1.cyr" 7 "16 B R2 by value, R2 below g"
sed 's/struct R2 { a; b; }/struct R2 { a; b; c; }/; s/R2 { 5, 7 }/R2 { 5, 7, 9 }/' "$D/p1.cyr" > "$D/p1b.cyr"
xr P1b "$D/p1b.cyr" 7 "the 24 B variant"
cat > "$D/p2.cyr" <<'X'
include "lib/syscalls.cyr"
fn main() { var t: R2 = R2 { 5, 7 }; return g(&t) * 10 + h(t); }
fn g(x: *R2): i64 { return x.b; }
fn h(x: *R2): i64 { return x.b; }
struct R2 { a; b; }
var r = main();
syscall(SYS_EXIT, r);
X
xr P2 "$D/p2.cyr" 77 "h(t) into x: *R2 passes &t"

echo "R. the return filing's repros, verbatim"
cat > "$D/r1.cyr" <<'X'
fn main(): i64 { var t: Pq = mk(10); return t.a; }
fn mk(n): Pq { var s: Pq; s.a = n; s.b = 2; s.c = 3; return s; }
struct Pq { a; b; c; }
syscall(60, main());
X
xr R1 "$D/r1.cyr" 10 "var t: Pq = mk(10), 24 B, Pq below mk"
sed 's/struct Pq { a; b; c; }/struct Pq { a; b; }/; s/ s.c = 3;//' "$D/r1.cyr" > "$D/r1b.cyr"
xr R1b "$D/r1b.cyr" 10 "the 16 B variant"
sed 's/struct Pq { a; b; c; }/struct Pq { a; }/; s/ s.b = 2; s.c = 3;//' "$D/r1.cyr" > "$D/r1c.cyr"
xr R1c "$D/r1c.cyr" 10 "the 8 B variant"
sed 's/var t: Pq = mk(10)/var t = mk(10)/' "$D/r1.cyr" > "$D/r1u.cyr"
xr R1u "$D/r1u.cyr" 10 "the untyped var t = mk(10)"
sed 's/Pq/f32v4/g' "$D/r1.cyr" > "$D/r1v.cyr"
xr R1v "$D/r1v.cyr" 10 "the struct named f32v4 (D41 A)"

echo "C. controls"
cat > "$D/c1.cyr" <<'X'
include "lib/syscalls.cyr"
fn g(x: R2): i64 { return x.b; }
fn main() { var t: R2 = R2 { 5, 7 }; return g(t); }
struct R2 { a; b; }
var r = main();
syscall(SYS_EXIT, r);
X
xr C1 "$D/c1.cyr" 7 "g defined above main, R2 still last"
cat > "$D/c2.cyr" <<'X'
fn mk(n): Pq { var s: Pq; s.a = n; s.b = 2; s.c = 3; return s; }
fn main(): i64 { var s = mk(7); var t: Pq = mk(10); return s.a + t.a; }
struct Pq { a; b; c; }
syscall(60, main());
X
xr C2 "$D/c2.cyr" 17 "mk defined above main, Pq still last"
cat > "$D/c3.cyr" <<'X'
include "lib/syscalls.cyr"
struct R2 { a; b; }
fn main() { var t: R2 = R2 { 5, 7 }; return g(t); }
fn g(x: R2): i64 { return x.b; }
var r = main();
syscall(SYS_EXIT, r);
X
xr C3 "$D/c3.cyr" 7 "R2 declared first"

echo "T. $TC ($N rows)"
for leg in $LEGS; do
    n=$(printf 'T_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: $TC did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a call above a fn whose signature names a struct declared below it reads the definition's signature: the filed repros (P, R), the controls (C) and $N rows (T) on x86_64 / IR / aarch64 / cx / PE"
