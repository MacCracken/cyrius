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
# Filed: docs/development/issues/archived/2026-10-10-generic-method-call-runs-i64-base.md
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
#   E  (6.7.14, the user's D7 (a), 2026-10-16) EXPLICIT TYPE ARGUMENTS ON A METHOD CALL, as on its free spelling:
#      `p.id<f64>(h)` was refused "unknown field 'id' on struct 'P'" + "undefined variable 'f64'" (the `<` read as
#      less-than). `.m<..>(` where m is no field and a generic method of the receiver's struct (`_mtargs_at`)
#      reads the list as `_explicit_generic_call` does and enters the method arm on that instance
#      (`_meth_targs`); `var a = p.id<f64>(h);` is an f64 (`_mchain_targs`), and the chain, a statement, a
#      struct return and the stub scan (`p.pick<T>(t)` in a generic) take the shape. E0 the filed repro
#      verbatim (exit 0); E1 the chain `w.v.id<f64>(h)` and a statement; E2 struct type arguments of 8 / 16 /
#      24 B (receive, annotation, assignment, argument, chain, return); E3 a bounded member `p.bm<f64>(h)`; E4 a
#      field still wins: `p.n < k`, and `q.id < k` where `id` is a field AND a generic method — every leg;
#      refusals, once each (x86_64): E5 `p.pick<i64>(9)` naming P_pick with the stub text, E6 `p.bm<i64>(3)` by
#      the bound with one note naming `impl Show for i64`, E7 `p.id<Zork>(h)` "unknown type 'Zork' as a type
#      argument". Filed: docs/development/issues/archived/2026-10-11-method-call-explicit-type-arguments-misdiagnosed.md
#   P  (6.7.15) THE STUB SCAN'S TOKEN BINDING FOLLOWS THE PARSER'S POINTER RULE (6.7.14's D8 (a), and 6.7.15's D12 (a)
#      spellings): `var r = gd(&GP0); return r.pick(t);` in a generic was refused naming the stub method P_pick (the
#      scan answered 0 for `&GP0`, so `r` was untyped there and the forward of T into P_pick unseen). P0 the filed
#      repro verbatim (docs/development/issues/2026-10-16-generic-token-scans-miss-d8-pointer-binding.md) 44, P0c its
#      control (o removed, o2 alone: the explicit spelling) 4, unchanged — every leg; P1 the `var pp: *P` local form 4 and, through `p: *T`, P2 a `*P` global,
#      P3 `GW.p` / `w.p` / `wp.p` field chains, P4 a `: *P` call, P5 `(&GP0)` / `(pp)`, P6 `&l` of a struct local;
#      through `x: T` P7 `gid(*pp)` and `gid((l))` — each 4 (each refused naming P_pick before) — x86_64; PX an
#      `x: T` given a `pp: *P` PARAMETER binds no struct in the scan either: `o(5, &GP0)` meets the parser's own
#      "no struct type in scope for 'r'" at `r.pick`, not a stub refusal naming o (the scan made o a stub) — x86_64
#   L  (6.7.15) THE EXPLICIT SPELLING IN THE METHOD-CALL LOOKAHEADS: every lookahead that keys a method call on the
#      tokens `x . m (` (`_tok_method_open`, its `(` at ti + 3) missed `x.m<..>(` — `var a, b = p.mm<i64>(3);` was
#      "multi-value destructure needs a call on the right-hand side", `var v = p.rs<i64>(3)?;` took the boxed `?`
#      (SIGSEGV), `var v = p.rs<i64>(3);` kept a pair's tag in silence, a vector receive or a dyn refused the call, a
#      multi-value call stored as a struct compiled. `_mcall_open` answers either spelling's `(`, the `<` one only
#      where the receiver's struct has no field m and a generic method m (`_mtargs_at`), at all 17 sites; the callee
#      is resolved at the explicit instance (`_mcall_xquiet`). L0 the filed repro verbatim (10) and LV
#      tests/tcyr/crossos/generic_method_explicit_lookaheads.tcyr (28 rows: destructures, a re-assignment, a `*P`
#      receiver, parentheses, a tuple capture, a forward, inside a generic, a for step, a 16 B struct; a pair's `?`,
#      statement `?`, wrapped `?`, forward, destructure; a vector method into an annotated / unannotated local, an
#      assignment, an argument, a return, parentheses; a `*T` result as a dyn source in four positions; a top-level
#      zone; MC the comparisons) — every leg; LR1-LR19 (x86_64) each refusal on the explicit spelling, once, in the
#      inferred spelling's words (a pair bound one-wide in six positions, a multi-value call into a tuple / struct
#      field, a struct assignment / declaration / small-struct return, a tuple capture's count, a destructure's count /
#      over-16 B / one-value struct, a vector into an i64 declaration / assignment, an async fn, a tuple argument);
#      LC `p.n < k >> (j)` / `q.id < k >> (j)` (id a field AND a generic method) compare on every leg, and a
#      pair-returning fn's comparison return keeps its dropped-tag warning. Filed: docs/development/issues/
#      2026-10-16-explicit-method-type-args-in-method-call-lookaheads.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, CYCC= it — the aarch64 / cx legs build from the tree):
#      ML1 the lane's previous compiler (3ad93752) -> RED 24: L0 LV (x86 / IR / PE), LR1-LR18; ML2 `_mcall_open`
#      without its `<` arm -> RED 24, as ML1; ML3 `_mcall_open` by shape (no `_mtargs_at`) -> GREEN: the parser's
#      field still wins and a field's comparison resolves no method (as 6.7.14's ME2; the corpus differential guards
#      it); ML4 `_vrcv_src` kind 3 at ti + 3 -> RED 3: LV (x86 / IR / PE: the wrapped vector receive refused); ML5
#      `_pair_callee_at` at the template (no `_mcall_xquiet`) -> GREEN: the template's flags and return agree with the
#      instance's on these shapes (the free spelling's `_pair_gen_inst` twin, kept for the instance the call reaches);
#      ML6 `_pair_mopen` without its `<` arm -> RED 4: LV (x86 / IR SIGSEGV, PE: the wrapped `?`), LR6
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
# 6.7.14 (D7 (a); 2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it with
# CYCC= it — the aarch64 / cx legs build their compilers from the tree's own src, so a mutant shows on x86_64 / IR /
# PE):
#   ME1 `_field_load_on` without the `_meth_targs`  -> RED E0-E3 (did not build: "unknown field 'id'"), E5-E7 (two
#       call (the field miss reports)                 errors each), T (the file does not build)
#   ME2 `_mtargs_at` without its field test         -> GREEN: `_field_load_on` looks a field up before
#                                                     `_meth_targs` on every path, so the field still wins
#                                                     (E4); the test keeps a chain's comparison
#                                                     (`w.q.id < k && f > (0)`) on the inline field walk — the
#                                                     corpus differential is its guard, no row
#   ME3 `_var_rhs_mchain` without `_mchain_targs`   -> RED E0 / E1 (exit 1: `a` an untyped word), T (X1 / X3)
#   ME4 `_rlf_more` / `_fld_meth_inline` without    -> RED E1 (did not build: "unknown field 'id'" on the
#       `_mtargs_at` (no chain)                       chain's leaf), T (the file does not build)
#   ME5 the stub scan's method arm without the      -> RED T (the file does not build: X13's `ox` refused at
#       `<T>` forward (`_gs_mfwd` reads args only)    its definition, naming P_pick)
#   ME6 `_ret_expr_head` without `x.m<..>(`         -> RED E2 (did not build: "a fn returning the 9-16 byte
#                                                     struct `Pt` ..."), T (X8)
#   ME7 `_stmt_dot_chain_call` without `.m<..>(`    -> RED E1 (the statements: "unknown field 'id'"), T (X13)
# 6.7.15 (the P rows; 2026-10-18, CYCC= the mutant, so its x86_64 / IR / PE legs carry it):
#   MT1 the fix reverted (the lane's previous compiler) -> RED P0 (refused naming P_pick), P1-P7 (each refused), PX
#                                                         (the stub refusal naming o); P0c green
#   MT2 `_tok_ta_arg` told `x: T` always (no shape)    -> RED P0, P1-P6 (refused); P7 / PX green
#   MT3 `_tok_ta_name` binds a `*S` through `x: T`     -> RED PX (the stub refusal naming o)
#   MT4 `_tok_ta_decl` without a `var p: *S` local      -> RED P1, P3c, P5b, P7a
#   MT5 `_tok_ta_arg` without `_pwrap_in`              -> RED P5a, P5b, P7b
#   MT6 `_tok_ta_arg` without its chain arm            -> RED P3a, P3b, P3c
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
FLOOR=63
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

echo "E. explicit type arguments on a method call (6.7.14, D7 (a)): bound as the free spelling binds them"
cat > "$D/e0.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { a; }
impl P {
    fn id<V>(self, x: V): V { return x; }
}
fn main(): i64 {
    var p: P = P { 1 };
    var h: f64 = 1.5;
    var a = p.id<f64>(h);
    if (a * 2.0 != 3.0) { return 1; }
    return 0;
}
syscall(60, main());
XEOF
xr E0 "$D/e0.cyr" 0 "the filed repro, var a = p.id<f64>(h); a * 2.0"
cat > "$D/e1.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { a; n; }
struct W { v: P; k; }
struct Nd { next: *P; z; }
impl P { fn id<V>(self, x: V): V { return x; } }
fn main(): i64 {
    var p: P = P { 1, 2 };
    var h: f64 = 1.5;
    var w: W;
    w.v = p;
    w.k = 3;
    var nd: Nd;
    nd.next = &p;
    nd.z = 0;
    var pp: *P = &p;
    var a = w.v.id<f64>(h);
    var b = nd.next.id<f64>(h);
    var c = pp.id<f64>(h);
    w.v.id<f64>(h);
    p.id<f64>(h);
    if (a * 2.0 != 3.0) { return 1; }
    if (b + c != 3.0) { return 2; }
    if (w.v.id<f64>(h) * 2.0 != 3.0) { return 3; }
    return 21;
}
syscall(60, main());
XEOF
xr E1 "$D/e1.cyr" 21 "w.v.id<f64>(h), nd.next.id<f64>(h) through a *P field, pp.id<f64>(h), and as statements"
cat > "$D/e2.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P8 { a: i32; b: i32; }
struct Pt { x; y; }
struct P3 { a; b; c; }
struct P { k; }
impl P { fn id<V>(self, x: V): V { return x; } }
fn t8(v: P8): i64 { return v.b; }
fn t16(v: Pt): i64 { return v.y; }
fn t24(v: P3): i64 { return v.c; }
fn r8(p: P, v: P8): P8 { return p.id<P8>(v); }
fn r16(p: P, v: Pt): Pt { return p.id<Pt>(v); }
fn r24(p: P, v: P3): P3 { return p.id<P3>(v); }
fn main(): i64 {
    var p: P = P { 1 };
    var v8: P8 = P8 { 1, 2 };
    var v16: Pt = Pt { 1, 3 };
    var v24: P3 = P3 { 1, 2, 4 };
    var a = p.id<P8>(v8);
    var b: Pt = p.id<Pt>(v16);
    var c: P3 = P3 { 0, 0, 0 };
    c = p.id<P3>(v24);
    var s = a.b + b.y + c.c;
    s = s + t8(p.id<P8>(v8)) + t16(p.id<Pt>(v16)) + t24(p.id<P3>(v24));
    s = s + p.id<Pt>(v16).y + r8(p, v8).b + r16(p, v16).y + r24(p, v24).c;
    return s;
}
syscall(60, main());
XEOF
xr E2 "$D/e2.cyr" 30 "8 / 16 / 24 B type arguments: receive, annotation, assignment, argument, chain, return (9 + 9 + 12)"
cat > "$D/e3.cyr" <<'XEOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
struct P { a; }
impl P { fn bm<V: Show>(self, x: V): i64 { return self.a + x.show(); } }
fn main(): i64 {
    var p: P = P { 1 };
    var h: f64 = 1.5;
    return p.bm<f64>(h);
}
syscall(60, main());
XEOF
xr E3 "$D/e3.cyr" 6 "a bounded generic method, p.bm<f64>(h) (impl Show for f64 only)"
cat > "$D/e4.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { a; n; }
struct Q { id; }
struct WQ { q: Q; n; }
impl P { fn id<V>(self, x: V): V { return x; } }
impl Q { fn id<V>(self, x: V): V { return x; } }
fn main(): i64 {
    var p: P = P { 1, 2 };
    var q: Q = Q { 2 };
    var k = 3;
    var f = 1;
    var r = 0;
    if (p.n < k) { r = r + 10; }
    if (q.id < k) { r = r + 20; }
    if (q.id < f) { r = r + 100; }
    var w: WQ;
    w.q = q;
    w.n = 0;
    if (q.id < k && f > (0)) { r = r + 100; }
    if (w.q.id < k && f > (0)) { r = r + 100; }
    return r;
}
syscall(60, main());
XEOF
xr E4 "$D/e4.cyr" 230 "p.n < k, q.id < k, q.id < k && f > (0) and w.q.id < k && f > (0) (the \`.m<..>(\` token shape) where id is a field AND a generic method: the field wins"
ME='include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
struct P { v; }
impl P {
    fn pick<V>(self, w: V): i64 { return w.b; }
    fn bm<V: Show>(self, v: V): i64 { return v.show(); }
    fn id<V>(self, x: V): V { return x; }
}'
# erow <id> <expr> <fragment> <what>: refused with exactly one error, containing <fragment>
erow() {
    printf '%s\nfn main(): i64 {\n    var p = P { 5 };\n    var h: f64 = 1.5;\n    return %s;\n}\nsyscall(60, main());\n' "$ME" "$2" > "$D/$1.cyr"
    erc=0; "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || erc=$?
    ne=$(grep -c '^error' "$D/$1.err" || true)
    if [ "$erc" -eq 0 ]; then bad "$1: $4 compiled (want it refused)"
    elif [ "$ne" -ne 1 ]; then bad "$1: $4: $ne errors, want 1: $(grep '^error' "$D/$1.err" | tr '\n' ' ')"
    elif grep -qF "$3" "$D/$1.err"; then ok "$1: $4 is refused once: $3"
    else bad "$1: $4: not refused as '$3': $(grep '^error' "$D/$1.err")"; fi
}
erow E5 'p.pick<i64>(9)' "generic 'P_pick' $STUB" "p.pick<i64>(9), a stub's scalar binding"
erow E6 'p.bm<i64>(3)' "generic 'P_bm': its type argument does not implement trait 'Show'" "p.bm<i64>(3), only impl Show for f64"
if [ "$(grep -c 'needs `impl Show for i64`' "$D/E6.err")" -eq 1 ]; then ok "E6: one note naming impl Show for i64"
else bad "E6: not one note naming impl Show for i64: $(tr '\n' ' ' < "$D/E6.err")"; fi
erow E7 'p.id<Zork>(h)' "unknown type 'Zork' as a type argument" "p.id<Zork>(h)"

echo "P. the stub scan's token binding follows the parser's pointer rule (6.7.15)"
# The filed repro, verbatim (the issue's text), and its control (o2 alone).
cat > "$D/p0.cyr" <<'X'
include "lib/syscalls.cyr"
struct P { n; }
struct Q { a; b; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
var GP0 = P { 1 };
fn gd<T>(x: *T): T { var t: T = *x; return t; }
fn o<T>(t: T): i64 { var r = gd(&GP0); return r.pick(t); }
fn o2<T>(t: T): i64 { var r = gd<P>(&GP0); return r.pick(t); }
fn m(): i64 { var q = Q { 3, 4 }; return o(q) * 10 + o2(q); }
syscall(60, m());
X
xr P0 "$D/p0.cyr" 44 "the filed repro, o(q) * 10 + o2(q)"
sed -e 's/return o(q) \* 10 + o2(q);/return o2(q);/' -e '/^fn o<T>/d' "$D/p0.cyr" > "$D/p0c.cyr"
xr P0c "$D/p0c.cyr" 4 "its control, o removed: o2(q) alone"
PH='include "lib/syscalls.cyr"
struct P { n; }
struct Q { a; b; }
struct W { p: *P; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
var GP0 = P { 1 };
var GPP: *P = &GP0;
var GW = W { &GP0 };
fn mkp(): *P { return &GP0; }
fn gd<T>(x: *T): T { var t: T = *x; return t; }
fn gid<T>(x: T): T { return x; }'
# prow <id> <body of the generic o<T>(t: T)> <what>: `o(q)` on a Q { 3, 4 } exits 4 (x86_64)
prow() {
    printf '%s\nfn o<T>(t: T): i64 { %s }\nfn m(): i64 { var q = Q { 3, 4 }; return o(q); }\nsyscall(60, m());\n' "$PH" "$2" > "$D/$1.cyr"
    run_leg x86 "$D/$1.cyr" "$D/$1"
    if [ "$RC" -eq -1 ]; then bad "$1: $3 did not build: $(grep -m1 'error' "$D/$1.err")"
    elif [ "$RC" -eq 4 ]; then ok "$1: $3 exits 4"
    else bad "$1: $3 exits $RC, want 4"; fi
}
prow P1 'var pp: *P = &GP0; var r = gd(pp); return r.pick(t);' "a \`var pp: *P\` local, gd(pp)"
prow P2 'var r = gd(GPP); return r.pick(t);' "a \`*P\` global, gd(GPP)"
prow P3a 'var r = gd(GW.p); return r.pick(t);' "gd(GW.p), a global's \`*P\` field"
prow P3b 'var w = W { &GP0 }; var r = gd(w.p); return r.pick(t);' "gd(w.p), a local's \`*P\` field"
prow P3c 'var wp: *W = &GW; var r = gd(wp.p); return r.pick(t);' "gd(wp.p) through a \`*W\`"
prow P4 'var r = gd(mkp()); return r.pick(t);' "gd(mkp()), a \`: *P\` call"
prow P5a 'var r = gd((&GP0)); return r.pick(t);' "gd((&GP0)), wrapped"
prow P5b 'var pp: *P = &GP0; var r = gd((pp)); return r.pick(t);' "gd((pp)), wrapped"
prow P6 'var l = P { 2 }; var r = gd(&l); return r.pick(t);' "gd(&l) of a struct local"
prow P7a 'var pp: *P = &GP0; var r = gid(*pp); return r.pick(t);' "gid(*pp) through \`x: T\`"
prow P7b 'var l = P { 2 }; var r = gid((l)); return r.pick(t);' "gid((l)) through \`x: T\`"
printf '%s\nfn o<T>(t: T, pp: *P): i64 { var r = gid(pp); return r.pick(t); }\nfn m(): i64 { return o(5, &GP0); }\nsyscall(60, m());\n' "$PH" > "$D/px.cyr"
erc=0; "$CC" < "$D/px.cyr" > "$D/px" 2> "$D/px.err" || erc=$?
ne=$(grep -c '^error' "$D/px.err" || true)
if [ "$erc" -ne 0 ] && [ "$ne" -eq 1 ] && grep -qF "no struct type in scope for 'r'" "$D/px.err"; then ok "PX: gid(pp) with a \`pp: *P\` parameter binds no struct: the parser's own error at r.pick, once"
else bad "PX: o(5, &GP0): rc $erc, $ne errors (want the parser's one 'no struct type in scope for 'r''): $(grep '^error' "$D/px.err" | tr '\n' ' ')"; fi

echo "L. the explicit spelling x.m<..>(..) in the method-call lookaheads (6.7.15)"
# The filed repro, verbatim (the issue's text).
cat > "$D/l0.cyr" <<'X'
include "lib/syscalls.cyr"
struct P { k; }
impl P {
    fn id<V>(self, x: V): V { return x; }
    fn mm<V>(self, x: V): (V, i64) { return (x, 7); }
}
fn main(): i64 { var p: P = P { 1 }; var a, b = p.mm<i64>(3); return a + b; }
syscall(60, main());
X
xr L0 "$D/l0.cyr" 10 "the filed repro, var a, b = p.mm<i64>(3); return a + b;"
TL=tests/tcyr/crossos/generic_method_explicit_lookaheads.tcyr
[ -f "$TL" ] || { echo "FAIL: $G: $TL is missing"; exit 1; }
NL=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TL")
if [ "$NL" -lt 28 ]; then echo "FAIL: $G: only $NL rows in $TL (floor 28) — rows were lost"; exit 1; fi
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'lv_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TL" "$D/$n"
    if [ "$RC" -eq -1 ]; then bad "LV $leg: the values file did not build: $(grep -m1 'error' "$D/$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NL passed, 0 failed ($NL total)" ]; then ok "LV $leg: $LAST"
    else bad "LV $leg: exit $RC, '$LAST' (want '$NL passed, 0 failed ($NL total)') $(grep -m3 'FAIL' "$D/$n.out" | tr '\n' ' ')"; fi
done
# lrow <id> <decls> <main body> <fragment> <what>: the explicit spelling (`.m<i64>(`) is refused once, containing
# <fragment>, and its error text (past the position) is the inferred spelling's (`.m(`) — x86_64.
LH='include "lib/syscalls.cyr"
enum SRes: stack { SOk(v); SErr(e); }
struct P { k; }
struct Q8 { a; }
struct Q16 { a; b; }
struct Q24 { a; b; c; }
struct H2 { a; b; }
struct Sv { k; }
impl P {
    fn mm<V>(self, x: V): (V, i64) { return (x, 7); }
    fn m3<V>(self, x: V): (V, i64, i64) { return (x, 7, 1); }
    fn rs<V>(self, x: V): i64 { if (x == 0) { return SErr(9); } return SOk(x); }
    fn q8<V>(self, x: V): Q8 { var q: Q8; q.a = x; return q; }
    fn q24<V>(self, x: V): Q24 { var q: Q24; q.a = x; q.b = 4; q.c = 5; return q; }
}
impl Sv { fn vv<V>(self, a: V, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; } }'
lrow() {
    printf '%s\n%s\nfn main(): i64 { var p: P = P { 1 }; var s: Sv = Sv { 1 }; %s return 0; }\nsyscall(60, main());\n' "$LH" "$2" "$3" > "$D/$1_x.cyr"
    sed 's/\.\(mm\|m3\|rs\|q8\|q24\|vv\)<i64>(/.\1(/g' "$D/$1_x.cyr" > "$D/$1_i.cyr"
    for v in x i; do lrc=0; env $LENV "$CC" < "$D/$1_$v.cyr" > "$D/$1_$v" 2> "$D/$1_$v.err" || lrc=$?; eval "lrc_$v=$lrc"; done
    nx=$(grep -c '^error' "$D/$1_x.err" || true)
    tx=$(grep '^error' "$D/$1_x.err" | sed 's/^error:<source>:[0-9]*:[0-9]*: //')
    ti=$(grep '^error' "$D/$1_i.err" | sed 's/^error:<source>:[0-9]*:[0-9]*: //')
    if [ "$lrc_x" -eq 0 ]; then bad "$1: $5 compiled (want it refused)"
    elif [ "$nx" -ne 1 ]; then bad "$1: $5: $nx errors, want 1: $(grep '^error' "$D/$1_x.err" | tr '\n' ' ')"
    elif ! grep -qF -- "$4" "$D/$1_x.err"; then bad "$1: $5: not refused as '$4': $(grep '^error' "$D/$1_x.err")"
    elif [ "$tx" != "$ti" ]; then bad "$1: $5: the explicit spelling says '$tx', the inferred '$ti'"
    else ok "$1: $5 is refused once, as the inferred spelling is: $4"; fi
}
LENV=
PB='a `: stack` enum returns two values — bind both'
lrow LR1 '' 'var v = p.rs<i64>(3);' "$PB" "var v = p.rs<i64>(3); (kept the tag in silence)"
lrow LR2 '' 'var x = 0; x = p.rs<i64>(3);' "$PB" "x = p.rs<i64>(3);"
lrow LR3 '' 'var x = 0; store64(&x, p.rs<i64>(3));' "$PB" "store64(&x, p.rs<i64>(3))"
lrow LR4 '' 'var h: H2; h.a = p.rs<i64>(3);' "$PB" "h.a = p.rs<i64>(3);"
lrow LR5 '' 'var h = H2 { p.rs<i64>(3), 2 };' "$PB" "H2 { p.rs<i64>(3), 2 }"
lrow LR6 '' 'var x = (p.rs<i64>(3) + 1);' "$PB" "var x = (p.rs<i64>(3) + 1);"
lrow LR7 'struct HT { t: (i64, i64); n; }' 'var h: HT; h.t = p.mm<i64>(3);' "a multi-value call 'P.mm' is not stored into a tuple field" "h.t = p.mm<i64>(3); into a tuple field"
lrow LR8 'struct HS { s: Q16; n; }' 'var h: HS; h.s = p.mm<i64>(3);' "a multi-value call 'mm' is not stored into a struct 'Q16' field - bind it first: \`var a, b = p.mm(..);\`" "h.s = p.mm<i64>(3); into a struct field (compiled)"
lrow LR9 '' 'var q: Q16; q = p.mm<i64>(3);' "a multi-value call 'mm' is not assigned to struct 'Q16' - bind it first: \`var a, b = p.mm(..);\`" "q = p.mm<i64>(3); (named 'P_mm', no hint)"
lrow LR10 '' 'var q: Q16 = p.mm<i64>(3);' "a multi-value call 'mm' does not initialize struct 'Q16' - bind it first: \`var a, b = p.mm(..);\`" "var q: Q16 = p.mm<i64>(3); (named 'P_mm', no hint)"
lrow LR11 'fn g(p: P): Q8 { return p.mm<i64>(3); }' '' "a multi-value call 'mm' is not returned as struct 'Q8' - bind it first: \`var a, b = p.mm(..);\`" "return p.mm<i64>(3); from a : Q8 fn (compiled)"
lrow LR12 '' 'var t: (i64, i64) = p.m3<i64>(3);' "cannot capture 'm3' into tuple (i64, i64) - it returns 3 values" "var t: (i64, i64) = p.m3<i64>(3); (not a tuple)"
lrow LR13 '' 'var a, b, c = p.mm<i64>(3);' "multi-value destructure count does not match the fn's declared return arity" "var a, b, c = p.mm<i64>(3); (needs a call)"
lrow LR14 '' 'var a, b = p.q24<i64>(3);' "cannot destructure 'q24' - it returns struct 'Q24', which is not in registers" "var a, b = p.q24<i64>(3); (needs a call)"
lrow LR15 '' 'var a, b = p.q8<i64>(3);' "multi-value destructure binds 2 names, but 'P.q8' returns 1 value" "var a, b = p.q8<i64>(3); (needs a call)"
lrow LR16 '' 'var x: i64 = s.vv<i64>(4, 2);' "vector return type does not match the declared type" "var x: i64 = s.vv<i64>(4, 2); (compiled)"
lrow LR17 '' 'var x = 0; x = s.vv<i64>(4, 2);' "vector return type does not match the assigned variable" "x = s.vv<i64>(4, 2); (compiled)"
LENV=CYRIUS_ASYNC=1
lrow LR18 'async fn af(p: P): i64 { return p.mm<i64>(3); }' '' "\`async fn af\` returns 2 values, and a Future carries one i64" "async fn af returning p.mm<i64>(3) (compiled: the second value lost)"
LENV=
lrow LR19 'fn tk(t: (i64, i64)): i64 { return t.0; }' 'tk(p.mm<i64>(3));' "a multi-value call 'P_mm' is not a tuple argument" "tk(p.mm<i64>(3)) (unchanged)"
# LC: a field compared with the `.m<..>(` token shape is a comparison, and a pair-returning fn's comparison return keeps
# its dropped-tag warning (the shape alone is no method call).
cat > "$D/lc.cyr" <<'X'
include "lib/syscalls.cyr"
enum SRes: stack { SOk(v); SErr(e); }
struct P { n; k; }
struct Q { id; }
impl Q { fn id<V>(self, x: V): V { return x; } }
fn w(p: P, k, j): i64 { if (k == 0) { return SErr(1); } return SOk(p.n < k >> (j)); }
fn w2(p: P, k, j): i64 { if (k == 0) { return SErr(1); } return p.n < k >> (j); }
fn w3(p: P, k, j): i64 { if (k == 0) { return SErr(1); } return (p.n < k >> (j)); }
fn main(): i64 {
    var p: P; p.n = 1; p.k = 2;
    var q: Q; q.id = 3;
    var k = 5; var j = 0;
    var a = p.n < k >> (j);
    var b = q.id < k >> (j);
    var c = 0;
    c = p.n < k >> (j);
    var t, v = w(p, k, j);
    var d = (p.n < k >> (j));
    if (p.n < k >> (j)) { c = c + 10; }
    return a + b * 2 + c + v * 100 + d * 1000;
}
syscall(60, main());
X
xr LC "$D/lc.cyr" 90 "p.n < k >> (j) / q.id < k >> (j) compare (id a field AND a generic method)"
lcw=$(grep -c 'returns a `: stack` pair on another path but a SINGLE value here' "$D/x_LC_x86.err" || true)
if [ "$lcw" -eq 2 ]; then ok "LC: return p.n < k >> (j); and its wrapped form keep the dropped-tag warning (2)"
else bad "LC: $lcw dropped-tag warnings, want 2 (w2, w3): $(grep '^warning' "$D/x_LC_x86.err" | tr '\n' ' ')"; fi

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
echo "PASS: $G — a generic method call reaches the instance its arguments bind: the filed repro (R1), a chain and a trait member (C), a scalar into an i64 base (K) on x86_64 / IR / aarch64 / cx / PE, the refusals by name (S) on x86_64 and through every cross compiler, a forwarder through a field chain or a call receiver (F), explicit type arguments on the method spelling (E, 6.7.14), the stub scan's pointer binding (P, 6.7.15), the explicit spelling in every method-call lookahead (L, 6.7.15), and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
