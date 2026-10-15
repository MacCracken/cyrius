#!/bin/sh
# tests/gates/frontend/generic_method_infer.sh — 6.7.11
#
# A GENERIC METHOD CALL `p.m(..)` REACHES THE INSTANCE ITS ARGUMENTS BIND, AS `P_m(p, ..)` DOES. The
# method arm (`_field_load_on`) asked `_mcall_gen` for an instance only when a type parameter bound
# f64 (6.7.9): a struct binding called the i64 base, the dead stub when the body uses the parameter as
# a struct — `p.pick(q)` returned 0 where `P_pick(p, q)` read q.b (the filed repro exited 7, 77 is
# right), a `Box<V>` carrier was refused as a different struct type, and `var b: Q = p.id(q);`
# faulted. `_mcall_gen` now infers as the free call does (`_mcall_infer`: a whole argument, a struct
# carrier through `_gen_infer_sc`, and a type parameter on `self` binds the receiver's struct — whose
# instance takes a <= 8 B receiver by value, `_selfbv_tp`) and calls the instance; a scalar binding of a
# stub, or of a base whose bound i64 fails, is refused naming the method's fn, as the free call is
# (the user's decision A, 2026-10-13: `p.pick(9)` and `p.pick(h)` returned 0). Only the emitting call
# reports; `_var_rhs_msid`'s lookahead resolves quietly. A generic that forwards a T-typed name into a
# stub generic method (`p.pick(t)`, `self.pick(w)`) is a stub too (`_gs_mfwd`), as the free spelling
# makes it — or its eagerly emitted i64 base met the new refusal at its own definition. 6.7.0 - 6.7.10,
# every target.
# Filed: docs/development/issues/2026-10-10-generic-method-call-runs-i64-base.md
#
#   R1 the filed repro, verbatim: exit 77 (7 before) on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu),
#      cx (cxvm) and PE (wine)
#   C  `mk().pick(q) * 10 + p.tp(q)` — a chain and an `impl Tr for P` generic member: 73 (0 before),
#      every leg
#   K  `p.k(9) + p.k(20)` into a generic method with an i64 base: 39 (unchanged), every leg
#   F  (the 6.7.11 review) a forwarder whose receiver is a field chain or a call result (`h.p.pick(t)`,
#      `mk().pick(t)`; a method call's and a generic's `: P` result in the tcyr's F17 / F18) is a
#      stub, as the free spelling `P_pick(h.p, t)` makes it: the stub scan typed a
#      single name only, so their i64 bases met the scalar-binding refusal at their own definitions.
#      F1 `oc(h, q) * 10 + ok(q)` 77 and F2 two uncalled forwarders 5, every leg; F3 `oc(h, 5)` /
#      `ok(6)` refused naming oc / ok (two errors) — x86_64
#   S  refusals, by name and once: `p.pick(9)` (S1) and `p.pick(h)` with `h: f64` (S2) refused naming
#      P_pick with the stub text, as the free spelling `P_pick(p, 9)` is (S3); `var w = p.pick(9);` (S4)
#      one error, at the call's `(` (the lookahead stays quiet); `p.bm(7)` with only `impl Show for
#      f64` (S5) refused by the bound with one note naming `impl Show for i64`, as `P_bm(p, 7)` is (S6);
#      a generic forwarding its T into a stub generic method is a stub too, so `o1(p, 5)` and `p.fwd(5)`
#      are refused naming o1 and P_fwd (S8: two errors, one each) and their struct calls compile (the
#      tcyr's F rows); `p.bm(r)` with no `impl Show for R` is refused by the bound, its note naming R
#      (S9; it ran the i64 base) — x86_64; S1 also through the aarch64 / cx / PE compilers (S7)
#   T  tests/tcyr/crossos/generic_method_struct_arg.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#
# MUTATION LEDGER (2026-10-14; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0  the fix reverted (the tree before it)       -> RED R1 (7) and C (0) on every leg; S1 / S2 / S4 /
#                                                     S5 / S7 / S8 / S9 (compiled); T: the file does not
#                                                     build on any leg; K and the free-spelling controls
#                                                     green
#   M1  a struct binding returns the base (6.7.9's  -> RED R1 (7) and C (0) on every leg; S9 (compiled);
#       `c0 > 0 || c1 > 0` early return)              T does not build; the other S rows green
#   M2  no refusal (a scalar stub binding returns   -> RED S1 / S2 / S4 / S5 / S7 (compiled); S8 (one
#       the base silently, as before)                 error: `p.fwd(5)` compiled; `o1(p, 5)` is the
#                                                     free call's refusal); R, C, K, S9, T green
#   M3  the lookahead reports too (`_var_rhs_msid`  -> RED S4 and S8 (the one error is at the
#       passes emit 1)                                lookahead's cursor, the receiver — 7:13, 11:13 —
#                                                     not the call's `(`)
#   M4  no carrier inference (`_mcall_infer` k 0    -> RED T: the file does not build on any leg
#       infers i64)                                   (`p.cm(bx)` refused as the stub)
#   M5  `self` binds nothing (k 1 infers i64)       -> RED T: the file does not build on any leg
#                                                     (`p.me()` refused as the stub)
#   M6  `_selfbv_tp` answers 0 (an 8 B receiver     -> RED T E1 on every leg (the instance read &p as
#       pushed by address)                            the value)
#   M7  the stub scan skips method calls (`_gs_use` -> RED S8 (the forwarders' own definitions refused,
#       mode 1 without `_gs_mfwd`)                    naming P_pick); T: the file does not build on any
#                                                     leg (`p.pick(t)` in o1's base)
#   M8  (review) `_gs_mcallee` types a single-name   -> RED F1 / F2 on every leg (the forwarders' own
#       receiver only (no `_gs_recv_sid` chain or     definitions refused, naming P_pick) and F3 (the
#       call arm)                                     errors name P_pick at the definitions, not oc /
#                                                     ok); T: the file does not build on any leg
#   M9  (review) `_gs_recv_call` without its method  -> RED T: the file does not build on any leg
#       arm (`h.gp().pick(t)`)                        (F17's of_m refused at its definition)
#   M10 (review) `_gs_ret_sid` answering 0 for a     -> RED T: the file does not build on any leg
#       generic callee (`mkfg(t).pick(t)`)            (F18's of_g refused at its definition)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_method_infer
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

TC=tests/tcyr/crossos/generic_method_struct_arg.tcyr
R1=docs/development/issues/repros/2026-10-10-generic-method-call-runs-i64-base.cyr
for f in "$TC" "$R1"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=49
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

echo "R1. the filed repro, verbatim: p.pick(q) * 10 + P_pick(p, q) is 77 (7 = the method ran the stub)"
xr R1 "$R1" 77 "the filed repro"

echo "C. a chain and an impl Tr for P generic member"
cat > "$D/chain.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { v; }
struct Q { a; b; c; }
trait Tr { fn tk(self): i64; fn tp<V>(self, w: V): i64; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
impl Tr for P { fn tk(self): i64 { return 1; } fn tp<V>(self, w: V): i64 { return w.c; } }
fn mk(): P { var p = P { 5 }; return p; }
fn main(): i64 {
    var p = P { 5 };
    var q = Q { 1, 7, 3 };
    var a: i64 = mk().pick(q);
    var b: i64 = p.tp(q);
    return a * 10 + b;
}
var rc = main();
syscall(60, rc);
XEOF
xr C "$D/chain.cyr" 73 "mk().pick(q) * 10 + p.tp(q)"

echo "K. a scalar into a generic method with an i64 base is unchanged"
cat > "$D/k.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { v; }
impl P { fn k<V>(self, v: V): i64 { return v + self.v; } }
fn main(): i64 {
    var p = P { 5 };
    var a: i64 = p.k(9);
    var b = p.k(20);
    return a + b;
}
var rc = main();
syscall(60, rc);
XEOF
xr K "$D/k.cyr" 39 "p.k(9) + p.k(20)"

STUB="has no i64 (or other scalar) instance: it uses its type parameter as a struct"
echo "F. a forwarder whose receiver is a field chain or a call result is a stub, as P_pick(h.p, t) makes it"
cat > "$D/f1.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { v; }
struct Q { a; b; c; }
struct H { p: P; n; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
fn mk(): P { var p = P { 5 }; return p; }
fn oc<T>(h: H, t: T): i64 { return h.p.pick(t); }
fn ok<T>(t: T): i64 { return mk().pick(t); }
fn main(): i64 {
    var h: H;
    h.p.v = 5;
    h.n = 1;
    var q = Q { 1, 7, 3 };
    return oc(h, q) * 10 + ok(q);
}
var rc = main();
syscall(60, rc);
XEOF
xr F1 "$D/f1.cyr" 77 "oc(h, q) * 10 + ok(q) (h.p.pick(t) / mk().pick(t) were refused at their definitions)"
cat > "$D/f2.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { v; }
struct Q { a; b; c; }
struct H { p: P; n; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
fn mk(): P { var p = P { 5 }; return p; }
fn outer<T>(h: H, t: T): i64 { return h.p.pick(t); }
fn outk<T>(t: T): i64 { return mk().pick(t); }
fn main(): i64 { return 5; }
syscall(60, main());
XEOF
xr F2 "$D/f2.cyr" 5 "two forwarders never called"
sed 's/    var q = Q { 1, 7, 3 };/    var a = oc(h, 5);/; s/    return oc(h, q) \* 10 + ok(q);/    var b = ok(6);\n    return a + b;/' "$D/f1.cyr" > "$D/f3.cyr"
f3rc=0; "$CC" < "$D/f3.cyr" > "$D/f3" 2> "$D/f3.err" || f3rc=$?
ne=$(grep -c '^error' "$D/f3.err" || true)
if [ "$f3rc" -eq 0 ]; then bad "F3: oc(h, 5) and ok(6) compiled (want them refused)"
elif [ "$ne" -ne 2 ]; then bad "F3: $ne errors, want 2: $(grep '^error' "$D/f3.err" | tr '\n' ' ')"
elif grep -q "^error:<source>:13:16: generic 'oc' $STUB" "$D/f3.err" \
     && grep -q "^error:<source>:14:16: generic 'ok' $STUB" "$D/f3.err"; then ok "F3: oc(h, 5) and ok(6) are refused, naming oc and ok (the forwarders are stubs)"
else bad "F3: not the stub refusals naming oc and ok: $(grep '^error' "$D/f3.err" | tr '\n' ' ')"; fi

echo "S. a scalar binding of a stub is refused naming the method's fn, once, as the free call is"
cat > "$D/s1.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { v; }
struct Q { a; b; c; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
fn main(): i64 {
    var p = P { 5 };
    var a: i64 = p.pick(9);
    return a + 1;
}
var rc = main();
syscall(60, rc);
XEOF
sed 's/    var a: i64 = p.pick(9);/    var h: f64 = 1.5;\n    var a: i64 = p.pick(h);/' "$D/s1.cyr" > "$D/s2.cyr"
sed 's/p\.pick(9)/P_pick(p, 9)/' "$D/s1.cyr" > "$D/s3.cyr"
sed 's/    var a: i64 = p.pick(9);/    var a = p.pick(9);/' "$D/s1.cyr" > "$D/s4.cyr"
# srow <id> <compiler> <src> <line:col> <what>: refused with exactly one error, at <line:col>, naming
# 'P_pick' with the stub text
srow() {
    src=0; "$2" < "$3" > "$D/sr_$1" 2> "$D/sr_$1.err" || src=$?
    ne=$(grep -c '^error' "$D/sr_$1.err" || true)
    if [ "$src" -eq 0 ]; then bad "$1: $5 compiled (want it refused)"
    elif [ "$ne" -ne 1 ]; then bad "$1: $5: $ne errors, want 1: $(grep '^error' "$D/sr_$1.err" | tr '\n' ' ')"
    elif grep -q "^error:<source>:$4: generic 'P_pick' $STUB" "$D/sr_$1.err"; then ok "$1: $5 is refused once, at $4, naming P_pick"
    else bad "$1: $5: not the stub refusal naming P_pick at $4: $(grep '^error' "$D/sr_$1.err")"; fi
}
srow S1 "$CC" "$D/s1.cyr" 7:24 "p.pick(9)"
srow S2 "$CC" "$D/s2.cyr" 8:24 "p.pick(h), h: f64"
srow S3 "$CC" "$D/s3.cyr" 7:25 "the free spelling P_pick(p, 9) (control)"
srow S4 "$CC" "$D/s4.cyr" 7:19 "var a = p.pick(9); (the lookahead and the call)"
cat > "$D/s5.cyr" <<'XEOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
struct P { v; }
impl P { fn bm<V: Show>(self, v: V): i64 { return v.show(); } }
fn main(): i64 {
    var p = P { 5 };
    return p.bm(7);
}
var rc = main();
syscall(60, rc);
XEOF
sed 's/return p.bm(7);/return P_bm(p, 7);/' "$D/s5.cyr" > "$D/s6.cyr"
# brow <id> <src> <what>: refused by the bound at line 8, one error and one note, naming impl Show for i64
brow() {
    brc=0; "$CC" < "$2" > "$D/br_$1" 2> "$D/br_$1.err" || brc=$?
    ne=$(grep -c '^error' "$D/br_$1.err" || true)
    nn=$(grep -c 'note: the bound' "$D/br_$1.err" || true)
    if [ "$brc" -eq 0 ]; then bad "$1: $3 compiled (want it refused)"
    elif [ "$ne" -ne 1 ] || [ "$nn" -ne 1 ]; then bad "$1: $3: $ne errors and $nn notes, want 1 and 1: $(tr '\n' ' ' < "$D/br_$1.err")"
    elif grep -q "^error:<source>:8:.*generic 'P_bm': its type argument does not implement trait 'Show'" "$D/br_$1.err" \
         && grep -q 'needs `impl Show for i64`' "$D/br_$1.err"; then ok "$1: $3 is refused by the bound, its note naming impl Show for i64"
    else bad "$1: $3: not the bound refusal naming i64: $(tr '\n' ' ' < "$D/br_$1.err")"; fi
}
brow S5 "$D/s5.cyr" "p.bm(7), only impl Show for f64"
brow S6 "$D/s6.cyr" "the free spelling P_bm(p, 7) (control)"
cat > "$D/s8.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { v; }
impl P {
    fn pick<V>(self, w: V): i64 { return w.b; }
    fn fwd<V>(self, w: V): i64 { return self.pick(w) + 1; }
}
fn o1<T>(p: P, t: T): i64 { return p.pick(t); }
fn main(): i64 {
    var p = P { 5 };
    var a = o1(p, 5);
    var b = p.fwd(5);
    return a + b;
}
var rc = main();
syscall(60, rc);
XEOF
s8rc=0; "$CC" < "$D/s8.cyr" > "$D/s8" 2> "$D/s8.err" || s8rc=$?
ne=$(grep -c '^error' "$D/s8.err" || true)
if [ "$s8rc" -eq 0 ]; then bad "S8: the scalar calls of two forwarders compiled (want them refused)"
elif [ "$ne" -ne 2 ]; then bad "S8: $ne errors, want 2: $(grep '^error' "$D/s8.err" | tr '\n' ' ')"
elif grep -q "^error:<source>:10:16: generic 'o1' $STUB" "$D/s8.err" \
     && grep -q "^error:<source>:11:18: generic 'P_fwd' $STUB" "$D/s8.err"; then ok "S8: o1(p, 5) and p.fwd(5) are refused, naming o1 and P_fwd (the forwarders are stubs)"
else bad "S8: not the stub refusals naming o1 and P_fwd: $(grep '^error' "$D/s8.err" | tr '\n' ' ')"; fi
cat > "$D/s9.cyr" <<'XEOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
struct P { v; }
struct R { x; }
impl P { fn bm<V: Show>(self, v: V): i64 { return v.show(); } }
fn main(): i64 {
    var p = P { 5 };
    var r = R { 1 };
    return p.bm(r);
}
var rc = main();
syscall(60, rc);
XEOF
s9rc=0; "$CC" < "$D/s9.cyr" > "$D/s9" 2> "$D/s9.err" || s9rc=$?
ne=$(grep -c '^error' "$D/s9.err" || true)
nn=$(grep -c 'note: the bound' "$D/s9.err" || true)
if [ "$s9rc" -eq 0 ]; then bad "S9: p.bm(r) with no impl Show for R compiled (want it refused)"
elif [ "$ne" -ne 1 ] || [ "$nn" -ne 1 ]; then bad "S9: $ne errors and $nn notes, want 1 and 1: $(tr '\n' ' ' < "$D/s9.err")"
elif grep -q "^error:<source>:10:.*generic 'P_bm': its type argument does not implement trait 'Show'" "$D/s9.err" \
     && grep -q 'needs `impl Show for R`' "$D/s9.err"; then ok "S9: p.bm(r) is refused by the bound, its note naming impl Show for R"
else bad "S9: not the bound refusal naming R: $(tr '\n' ' ' < "$D/s9.err")"; fi
for leg in $OTHER; do
    case "$leg" in
        a64) srow "S7_a64" "$A64" "$D/s1.cyr" 7:24 "p.pick(9) through the aarch64 compiler" ;;
        cx)  srow "S7_cx" "$CXCC" "$D/s1.cyr" 7:24 "p.pick(9) through the cx compiler" ;;
        pe)  printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$CC" > "$D/cc_pe"; chmod +x "$D/cc_pe"
             srow "S7_pe" "$D/cc_pe" "$D/s1.cyr" 7:24 "p.pick(9) through the PE compiler" ;;
    esac
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
echo "PASS: $G — a generic method call reaches the instance its arguments bind: the filed repro (R1), a chain and a trait member (C), a scalar into an i64 base (K) on x86_64 / IR / aarch64 / cx / PE, the refusals by name (S) on x86_64 and through every cross compiler, a forwarder through a field chain or a call receiver (F), and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
