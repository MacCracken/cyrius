#!/bin/sh
# tests/gates/frontend/method_receiver_chain_lookaheads.sh — 6.7.16
#
# A METHOD ENDING A CHAIN ON ANY RECEIVER THE METHOD ARM TAKES IS A METHOD CALL TO EVERY PAIR / MULTI-VALUE LOOKAHEAD,
# as `x.m(..)` on a single name is. Every asker keyed a method call on the tokens `x . m (` with x one name
# (`_pair_callee_at`, `_tok_method_open`, `_mcall_open`; "a receiver that is not one name ... stays -1" since 6.6.16),
# so on a field chain `w.p.m2()` — and on every other receiver the method arm takes: a `*P` field `w.q.m2()`, three deep
# `h.w.p.m2()`, a `*W` parameter, `self.p.m2()`, a global, a closure's capture, a method's result `w.gp().m2()`, a call's
# `mkw().p.m2()` / `callptr(&gpw, &w).p.m2()`, a parenthesised head `(*pw).p.m2()` / `(w).p.m2()` / `(w.p).m2()` —
# `var c, d = w.p.m2();` was "multi-value destructure needs a call on the right-hand side" (the filed repro, rc 1),
# `var v = w.p.rs(3)?;` took the boxed `?` (SIGSEGV), `var v = w.p.rs(3);` kept a pair's tag in silence, `var t: (i64,
# i64) = w.p.m2();` was "not a tuple", `return w.p.rs(4);` beside `return Err(2);` drew a false dropped-tag warning, a
# forwarder `return w.p.rs(3);` defined below its caller was no pair there (`var v = fwd(w);` kept the tag), and a
# multi-value call stored as a struct named `P_m2` with no hint. `_mcall_open` now answers a chain's last method
# (`_mch_open`, the vector receive's recogniser since 6.7.15; from the unit's tokens in the token passes, `_mch_tok`),
# the shape readers take a chain on any head (`_pc_shape`, `_pw_head`: `_pair_unwrap`, `_pair_vwrap`,
# `_call_is_propagated`, `_tok_q_is_pair`'s `_tok_chain_back`), and each asker names the chain's method and spells its
# receiver as written (`_mc_recv_pr`).
# Filed: docs/development/issues/2026-10-20-multi-value-method-on-field-chain-receiver-refused-as-destructure-source.md
#
#   R0 the filed repro, verbatim: exit 34 (rc 1, "needs a call", before) on x86_64, CYRIUS_IR=3, aarch64 (qemu), cx
#      (cxvm) and PE (wine)
#   V  tests/tcyr/crossos/method_receiver_chain_lookaheads.tcyr on x86_64 (plain, IR=1, IR=3, DCE=1), aarch64, cx and
#      PE: "N passed, 0 failed (N total)", N derived from the file (floor 68) — destructures, re-assignments, tuple
#      captures, a 16 B struct, generic methods inferred / explicit / at f64, forwards, a for step, every receiver head,
#      a pair's `?` / statement `?` / wrapped `?` / destructure / forward (the forwarder below its caller), a `*T`
#      method as a dyn source, comparisons (`w.a.n < k >> (j)`), the declaration zone; MS a chain on a `callptr(..)`
#      result as a by-value struct argument (`_icall_dotted`: it pushed a word as the address, SIGSEGV); MR a struct
#      over 8 B returned from a chain's method (`_ret_expr_head`: refused before, "returned in two registers ... got `w`" /
#      "return must be a bare local identifier, or a call ...")
#   C  each refusal on a chain is the single name's, once, word for word but the receiver its hint spells (x86_64):
#      C1-C6 a pair bound to one name (`var v =`, `x =`, `store64`, a field, a struct literal, inside a value's
#      parentheses), C6b the first-call rule, C7 / C8 a multi-value call into a tuple / struct field, C9 / C10 into a
#      struct assignment / declaration, C11 a small-struct return, C12 / C12b a tuple capture's count / struct,
#      C12r / C12s a tuple re-assignment's count (bare, wrapped), C13 the destructure's count, C14 over 16 B, C15 /
#      C15b a one-value struct / method, C16 a re-assignment from a struct, C17 / C17b / C17c / C19 a 16 B / 8 B /
#      24 B struct and a tuple argument, C20 / C21 a `(i64, i64)` fn forwarding 3 values / 1 value — each on w.p (c),
#      h.w.p (d), w.q (f), (*pw).p (x), mkw().p (k), w.gp() (m), callptr(&gpw, &w).p (i), w.p.idv(w).p (g: an
#      inferred generic step `: V` mid-chain, unresolved before the lane's review: `_mch_bind`), w.p.idv<W>(w).p (e:
#      an explicit one) and (p) (y: a single name's parenthesised head); C1h / F1h / F2h on w.p.idv(p) (h); on the
#      callptr head C17 / C17c / C19 compiled through 6.7.16's first fix (`_icall_dotted`);
#      C22-C24 a struct return over 8 B of another struct / 2 values / 1 value (each chain said "returned in two
#      registers ... got `w`", the single name the text it shares now)
#   W  the dropped-tag warning reads the chain's method (x86_64, every receiver): W1 / W3 `return w.p.rs(4);` (and in
#      parentheses) beside `return Err(2);` draw none (one each before), W2 `return w.p.one();` one, WC1 / WC2 a
#      comparison `w.p.n < z >> (z)` / `w.p.id < z >> (z)` (id a field and a generic method) one
#   X  a lookahead instantiates nothing (x86_64): X1 the zone's `var gx, gy = GW.p.mm<f64>(2.5);` exits 12 plain and under
#      CYRIUS_COVERAGE=1 (the chain arm minted `P_mm$f64` in the zone's pass 1, `_gzf_elem`: SIGSEGV under the mode — met
#      in check.sh's coverage_mode_corpus at 4a790ef3c; the instance `_mco_inst`'s where the single name's is); X2 an
#      explicit generic step in the MIDDLE of a chain there — `GW.p.gq<f64>(2.5).m2()` destructured, captured, after a
#      single name `GP.gq<f64>(2.5).m2()`, on a parenthesised head, ending in `.mm<f64>(2.5)` — each exits its plain value
#      under the mode (each minted `P_gq$f64` in the zone's pass 1 and SIGSEGV'd: the review of 6.7.16's lane; `_mch_mres`
#      types every step from its template, a `: V` / `: G<..>` by a peek of its binding)
#   F  the token pass flags a forwarder below its caller (x86_64, every receiver): F1 `var v = fwd(w);` with `fwd`
#      returning `w.p.rs(3)` and F2 with `fwd`'s only pair route `w.p.rs(3)?` are refused "bind both" (each compiled before)
#
# MUTATION LEDGER (2026-10-21; each mutant a scratch copy of the tree with the one change, its 2-stage cycc, this gate
# run from the copy with CYCC= that cycc, so the aarch64 / cx / PE compilers are built from the mutant too; C17b came
# after the runs):
#   M0  the tree before (0e2e41805)                     -> RED 179: R0 x5, V x7 (the file did not build), C1-C17 on every
#                                                          chain ("needs a call", compiled, `P_m2` with no hint), W1 / W3
#                                                          x7 (the false warning), F1 / F2 x7 (compiled)
#   M1  `_mcall_open` without its chain arm             -> RED 172: as M0, but W2 x7 for W1 / W3 (an unread chain is
#                                                          unknown: no warning at all)
#   M2  the token passes read no chain (`_pc_mchain` 0)  -> RED 39: V x7 (`fc_qfa`'s `?` on a forwarder below it), C7 / C8
#                                                          on (*pw) / callptr, W1 / W3 x7, F1 / F2 x7
#   M3  no parenthesised head (`_pw_head` -1)           -> RED 19: V x7, C1-C6b / C11 / W1 / W3 / F1 / F2 on (*pw).p
#   M4  `_call_is_propagated` without its chain arm     -> RED 11: V x7 (`mkw(1).p.rs(6)?` refused "bind both"), F2 on
#                                                          (*pw) / call / method / callptr heads
#   M5  `_tok_chain_back` one step back only            -> RED 7: F2 x7
#   M6  `_fsc_src` without its `(..)` / callptr arm     -> RED 4: C7 / C8 on (*pw) and callptr (compiled; "not a tuple")
#   M7  `_dt_mfn` without its `_mcall_gen`              -> RED 7: V x7 (`var t: (f64, i64) = w.p.mm(h);` refused: the
#                                                          base's (i64, i64))
#   M8  no chain dyn source (`_dyn_smchain` -1)         -> RED 7: V x7 (`dw.d.me(1)`: "cannot form dyn")
#   M9  `_gvi_cap_tok` without its `(..)` arm           -> RED 7: V x7 (the zone's `(GW).p.mm(5)` capture: "not a tuple")
#   M10 `_pair_unwrap` without its callptr head         -> RED 8: V x7 (`(callptr(..).p.rs(10))?`: the boxed `?`,
#                                                          SIGSEGV), W3 on callptr
#   M11 `_mc_recv_pr` spelling the head's name only     -> RED 34: C8-C11 / C17 on every chain (`var a, b = w.m2(..);`)
#   M12 `_mch_head` in a token pass reading the parser's -> RED 22: V x7, W2 / F1 / F2 on the name heads (c d f x m)
#       scope (no `_mch_tok` arm)
#   M13 `_pair_callee_at` without its chain arm         -> RED 56: V x7, C1-C6b x7 (the pair refusals)
#   M14 `_dt_call_open` without its chain arm           -> RED 82: R0 x5, V x7, C7 / C8 / C11-C16 x7
#   M15 the tree before `_icall_dotted` (7cdce3aa1)     -> RED 10: V x7 (MS: SIGSEGV), C17 / C17c / C19 on callptr
#   M16 the tree before `_ret_expr_head`'s chain arm    -> RED 19: V x7 (MR: the file did not build), C22 / C23 on c d f
#       (df29930ab)                                        x k i ("returned in two registers ... got `w`")
#   M17 the tree before `_mch_nox` (4a790ef3c)           -> RED 1: X1 cov (SIGSEGV)
#   M18 the tree before `_mch_mres` read the template    -> RED 5: X2 x2a-x2e cov (SIGSEGV)
#       (ed17925c9)
#   M19 the tree before `_mch_bind` read an inferred step -> RED 35: V x7 (the file did not build: "needs a call"),
#       (ca9e73061)                                        C1-C17c on g, W2 on g (unread: no warning), F1 / F2 on g,
#                                                          C1h / F1h / F2h on h
#   M20 the tree before `_tup_asg`'s parenthesised head  -> RED 11: V x7 (the file did not build: "not a tuple"), C12r /
#       (cd9d77e02)                                        C12s on x and y
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=method_receiver_chain_lookaheads
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
ulimit -c 0 2>/dev/null

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TL=tests/tcyr/crossos/method_receiver_chain_lookaheads.tcyr
[ -f "$TL" ] || { echo "FAIL: $G: $TL is missing"; exit 1; }
# One row per `assert_eq(` call. The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TL")
FLOOR=91
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TL (floor $FLOOR) — rows were lost"; exit 1; fi

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

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build) and LAST (the last
# line of its output, CR stripped).
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

echo "R0. the filed repro, verbatim: var c, d = w.p.m2(); return c * 10 + d; is 34"
cat > "$D/r0.cyr" <<'X'
include "lib/syscalls.cyr"
struct P { k; }
struct W { p: P; }
impl P { fn m2(self): (i64, i64) { return (3, 4); } }
fn main(): i64 { var w: W; var c, d = w.p.m2(); return c * 10 + d; }
syscall(60, main());
X
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'r0_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/r0.cyr" "$D/$n"
    if [ "$RC" -eq -1 ]; then bad "R0 $leg: the filed repro did not build: $(grep -m1 'error' "$D/$n.err")"
    elif [ "$RC" -eq 34 ]; then ok "R0 $leg: the filed repro exits 34"
    else bad "R0 $leg: the filed repro exits $RC, want 34"; fi
done

echo "V. $TL ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf 'v_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TL" "$D/$n"
    if [ "$RC" -eq -1 ]; then bad "V $leg: the values file did not build: $(grep -m1 'error' "$D/$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "V $leg: $LAST"
    else bad "V $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/$n.out" | tr '\n' ' ')"; fi
done

# The receiver modes: s (the single name, the reference), then the chains.
HDR='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
enum SRes: stack { SOk(v); SErr(e); }
struct P { k; n; id; }
struct Q8 { a; }
struct Q16 { a; b; }
struct Q24 { a; b; c; }
struct H2 { a; b; }
struct R16 { x; y; }
struct W { p: P; q: *P; n; }
struct H { w: W; }
impl P {
    fn m2(self): (i64, i64) { return (3, 4); }
    fn m3(self): (i64, i64, i64) { return (3, 4, 1); }
    fn rs(self, x): i64 { if (x == 0) { return SErr(9); } return SOk(x); }
    fn one(self): i64 { return 5; }
    fn q8(self): Q8 { var q: Q8; q.a = 1; return q; }
    fn q16(self): Q16 { var q: Q16; q.a = 1; q.b = 2; return q; }
    fn q24(self): Q24 { var q: Q24; q.a = 1; q.b = 4; q.c = 5; return q; }
    fn r16(self): R16 { var r: R16; r.x = 1; r.y = 2; return r; }
}
impl W { fn gp(self): *P { var a = self; return a; } }
impl P { fn idv<V>(self, x: V): V { return x; } }
fn mkw(): W { var w: W; w.p.k = 1; w.q = 0; w.n = 0; return w; }
fn gpw(w: *W): *W { return w; }'
MODES="c d f x k m i g e y"
mode_rcv() {
    case "$1" in
        s) R='p.'; PW='p: P' ;;
        c) R='w.p.'; PW='w: W' ;;
        d) R='h.w.p.'; PW='h: H' ;;
        f) R='w.q.'; PW='w: W' ;;
        x) R='(*pw).p.'; PW='pw: *W' ;;
        k) R='mkw().p.'; PW='zz' ;;
        m) R='w.gp().'; PW='w: W' ;;
        i) R='callptr(&gpw, &w).p.'; PW='w: W' ;;
        g) R='w.p.idv(w).p.'; PW='w: W' ;;
        e) R='w.p.idv<W>(w).p.'; PW='w: W' ;;
        h) R='w.p.idv(p).'; PW='w: W' ;;
        y) R='(p).'; PW='p: P' ;;
    esac
}
# subst <from> <to>: stdin to stdout with every <from> replaced by <to> (literally).
subst() {
    awk -v f="$1" -v t="$2" '{ o = ""; s = $0; while ((i = index(s, f)) > 0) { o = o substr(s, 1, i - 1) t; s = substr(s, i + length(f)) } print o s }'
}
# mksrc <mode> <decls> <main body> <out>: the program with the receiver `@.` and the parameter `@W` of <mode>.
mksrc() {
    mode_rcv "$1"
    { printf '%s\n%s\n' "$HDR" "$2"
      printf 'fn main(): i64 { var p: P; p.k = 1; var w: W; w.p.k = 1; var h: H; var pw: *W = &w; %s return 0; }\nsyscall(60, main());\n' "$3"
    } | subst '@W' "$PW" | subst '@.' "$R" > "$4"
}
etext() { grep '^error' "$1" | sed 's/^error:<source>:[0-9]*:[0-9]*: //'; }
# crow <id> <decls> <body> <fragment> <what> [modes]: the single name is refused once, containing <fragment>; each chain
# mode is refused once with the same text, its receiver spelled where the single name's is.
crow() {
    mksrc s "$2" "$3" "$D/$1_s.cyr"
    src=0; "$CC" < "$D/$1_s.cyr" > "$D/$1_s" 2> "$D/$1_s.err" || src=$?
    ns=$(grep -c '^error' "$D/$1_s.err" || true)
    if [ "$src" -eq 0 ] || [ "$ns" -ne 1 ] || ! grep -qF -- "$4" "$D/$1_s.err"; then
        bad "$1 s: $5 on a single name: rc $src, $ns errors, want 1 holding '$4': $(etext "$D/$1_s.err" | tr '\n' ' ')"; return
    fi
    ts=$(etext "$D/$1_s.err")
    for m in ${6:-$MODES}; do
        mksrc "$m" "$2" "$3" "$D/$1_$m.cyr"
        rc=0; "$CC" < "$D/$1_$m.cyr" > "$D/$1_$m" 2> "$D/$1_$m.err" || rc=$?
        nm=$(grep -c '^error' "$D/$1_$m.err" || true)
        mode_rcv "$m"
        tm=$(etext "$D/$1_$m.err" | subst "$R" 'p.')
        if [ "$rc" -eq 0 ]; then bad "$1 $m: $5 on $R.. compiled (want it refused)"
        elif [ "$nm" -ne 1 ]; then bad "$1 $m: $5 on $R..: $nm errors, want 1: $(etext "$D/$1_$m.err" | tr '\n' ' ')"
        elif [ "$tm" != "$ts" ]; then bad "$1 $m: $5 on $R.. says '$(etext "$D/$1_$m.err")', the single name '$ts'"
        else ok "$1 $m: $5 on $R.. is refused once, as on a single name"; fi
    done
}
echo "C. each refusal on a chain is the single name's"
PB='a `: stack` enum returns two values — bind both'
crow C1 '' 'var v = @.rs(3);' "$PB" "var v = @.rs(3); (kept the tag in silence)"
crow C2 '' 'var x = 0; x = @.rs(3);' "$PB" "x = @.rs(3);"
crow C3 '' 'var x = 0; store64(&x, @.rs(3));' "$PB" "store64(&x, @.rs(3))"
crow C4 '' 'var hh: H2; hh.a = @.rs(3);' "$PB" "hh.a = @.rs(3);"
crow C5 '' 'var hh = H2 { @.rs(3), 2 };' "$PB" "H2 { @.rs(3), 2 }"
crow C6 '' 'var x = (@.rs(3) + 1);' "$PB" "var x = (@.rs(3) + 1);"
crow C6b '' 'var x = @.rs(3) + 1;' "$PB" "var x = @.rs(3) + 1;"
crow C7 'struct HT { t: (i64, i64); n; }' 'var hh: HT; hh.t = @.m2();' "is not stored into a tuple field" "hh.t = @.m2(); into a tuple field"
crow C8 'struct HS { s: Q16; n; }' 'var hh: HS; hh.s = @.m2();' "a multi-value call 'm2' is not stored into a struct 'Q16' field - bind it first: \`var a, b = p.m2(..);\`" "hh.s = @.m2(); into a struct field"
crow C9 '' 'var q: Q16; q = @.m2();' "a multi-value call 'm2' is not assigned to struct 'Q16'" "q = @.m2(); (named 'P_m2', no hint)"
crow C10 '' 'var q: Q16 = @.m2();' "a multi-value call 'm2' does not initialize struct 'Q16'" "var q: Q16 = @.m2(); (named 'P_m2', no hint)"
crow C11 'fn g(@W): Q8 { return @.m2(); }' '' "a multi-value call 'm2' is not returned as struct 'Q8'" "return @.m2(); from a : Q8 fn"
crow C12 '' 'var t: (i64, i64) = @.m3();' "cannot capture 'm3' into tuple (i64, i64) - it returns 3 values" "var t: (i64, i64) = @.m3(); (not a tuple)"
crow C12b '' 'var t: (i64, i64) = @.q16();' "cannot capture 'q16' into tuple (i64, i64) - it returns struct 'Q16'" "var t: (i64, i64) = @.q16(); (not a tuple)"
crow C12r '' 'var t: (i64, i64) = (1, 1); t = @.m3();' "cannot capture 'm3' into tuple (i64, i64) - it returns 3 values" "t = @.m3(); (a re-assignment: not a tuple on a parenthesised head)"
crow C12s '' 'var t: (i64, i64) = (1, 1); t = (@.m3());' "cannot capture 'm3' into tuple (i64, i64) - it returns 3 values" "t = (@.m3()); (wrapped)"
crow C13 '' 'var a, b, c = @.m2();' "multi-value destructure count does not match the fn's declared return arity" "var a, b, c = @.m2(); (needs a call)"
crow C14 '' 'var a, b = @.q24();' "cannot destructure 'q24' - it returns struct 'Q24', which is not in registers" "var a, b = @.q24(); (needs a call)"
crow C15 '' 'var a, b = @.q8();' "multi-value destructure binds 2 names, but 'P.q8' returns 1 value" "var a, b = @.q8(); (needs a call)"
crow C15b '' 'var a, b = @.one();' "multi-value destructure binds 2 names, but 'P.one' returns 1 value" "var a, b = @.one(); (needs a call)"
crow C16 '' 'var a = 0; var b = 0; a, b = @.q24();' "cannot re-assign from 'q24' - it returns struct 'Q24'" "a, b = @.q24(); (needs a call)"
crow C17 'fn tq(q: Q16): i64 { return q.a; }' 'tq(@.m2());' "a multi-value call 'm2' is not a struct 'Q16' argument" "tq(@.m2()) into a struct parameter (named 'P_m2', no hint)"
crow C17b 'fn t8(q: Q8): i64 { return q.a; }' 't8(@.m2());' "a multi-value call 'm2' is not a struct 'Q8' argument" "t8(@.m2()) into an 8-byte struct parameter"
crow C17c 'fn t24(q: Q24): i64 { return q.a; }' 't24(@.m2());' "a multi-value call 'm2' is not a struct 'Q24' argument" "t24(@.m2()) into a 24-byte struct parameter"
crow C19 'fn tk(t: (i64, i64)): i64 { return t.0; }' 'tk(@.m2());' "is not a tuple argument" "tk(@.m2()) into a tuple parameter"
crow C20 'fn g3(@W): (i64, i64) { return @.m3(); }' '' "'g3' returns 2 values - return (a, b)" "return @.m3(); from a (i64, i64) fn"
crow C21 'fn g4(@W): (i64, i64) { return @.one(); }' '' "'g4' returns 2 values - return (a, b)" "return @.one(); from a (i64, i64) fn"
SRF='struct-return fn: return must be a bare local identifier, or a call to a fn returning the same struct'
crow C22 'fn g5(@W): Q16 { return @.r16(); }' '' "$SRF" "return @.r16(); (another 16 B struct) from a : Q16 fn"
crow C23 'fn g6(@W): Q16 { return @.m2(); }' '' "$SRF" "return @.m2(); (2 values) from a : Q16 fn"
crow C24 'fn g7(@W): Q24 { return @.one(); }' '' "$SRF" "return @.one(); (one value) from a : Q24 fn"

# wrow <id> <decls> <want> <what>: <want> dropped-tag warnings, no error, on the single name and every chain.
WTXT='returns a `: stack` pair on another path but a SINGLE value here'
wrow() {
    for m in s $MODES; do
        mksrc "$m" "$2" '' "$D/$1_$m.cyr"
        rc=0; "$CC" < "$D/$1_$m.cyr" > "$D/$1_$m" 2> "$D/$1_$m.err" || rc=$?
        nw=$(grep -c -F -- "$WTXT" "$D/$1_$m.err" || true)
        mode_rcv "$m"
        if [ "$rc" -ne 0 ]; then bad "$1 $m: $4 on $R.. did not compile: $(etext "$D/$1_$m.err" | tr '\n' ' ')"
        elif [ "$nw" -ne "$3" ]; then bad "$1 $m: $4 on $R..: $nw dropped-tag warnings, want $3"
        else ok "$1 $m: $4 on $R..: $3 dropped-tag warning(s)"; fi
    done
}
echo "W. the dropped-tag warning reads the chain's method"
wrow W1 'fn f(@W, z): i64 { if (z == 1) { return SErr(2); } return @.rs(4); }' 0 "return @.rs(4); beside return SErr(2); (warned before)"
wrow W2 'fn f(@W, z): i64 { if (z == 1) { return SErr(2); } return @.one(); }' 1 "return @.one(); beside return SErr(2);"
wrow W3 'fn f(@W, z): i64 { if (z == 1) { return SErr(2); } return (@.rs(4)); }' 0 "return (@.rs(4)); beside return SErr(2); (warned before)"
wrow WC1 'fn f(@W, z): i64 { if (z == 1) { return SErr(2); } return @.n < z >> (z); }' 1 "return @.n < z >> (z); (a comparison)"
wrow WC2 'impl P { fn id<V>(self, x: V): V { return x; } }
fn f(@W, z): i64 { if (z == 1) { return SErr(2); } return @.id < z >> (z); }' 1 "return @.id < z >> (z); (id a field and a generic method)"

# frow <id> <fwd body> <what> [modes]: `var v = fwd(w);` above `fwd` is refused "bind both" on the single name and every
# chain.
frow() {
    for m in s ${4:-$MODES}; do
        mode_rcv "$m"
        { printf '%s\n' "$HDR"
          printf 'fn main(): i64 { var w: W; w.p.k = 1; var v = fwd(w); return v; }\n'
          printf 'fn fwd(w: W): i64 { var p: P = w.p; var h: H; var pw: *W = &w; %s }\n' "$2"
          printf 'syscall(60, main());\n'
        } | subst '@.' "$R" > "$D/$1_$m.cyr"
        rc=0; "$CC" < "$D/$1_$m.cyr" > "$D/$1_$m" 2> "$D/$1_$m.err" || rc=$?
        ne=$(grep -c '^error' "$D/$1_$m.err" || true)
        if [ "$rc" -eq 0 ]; then bad "$1 $m: $3 on $R.. compiled (want 'bind both')"
        elif [ "$ne" -ne 1 ] || ! grep -qF -- "$PB" "$D/$1_$m.err"; then bad "$1 $m: $3 on $R..: $ne errors: $(etext "$D/$1_$m.err" | tr '\n' ' ')"
        else ok "$1 $m: $3 on $R.. is refused 'bind both' above its definition"; fi
    done
}
echo "F. a forwarder below its caller is a pair there"
frow F1 'return @.rs(3);' "var v = fwd(w); with fwd returning @.rs(3)"
frow F2 'var v = @.rs(3)?; return v + 0;' "var v = fwd(w); with fwd's only pair route @.rs(3)?"
# h: the review's spelling of an inferred step, `w.p.idv(p).rs(3)` (p a local `P`: only where one is in scope)
crow C1h '' 'var v = @.rs(3);' "$PB" "var v = @.rs(3); (kept the tag in silence)" h
frow F1h 'return @.rs(3);' "var v = fwd(w); with fwd returning @.rs(3)" h
frow F2h 'var v = @.rs(3)?; return v + 0;' "var v = fwd(w); with fwd's only pair route @.rs(3)?" h

echo "X. a lookahead instantiates nothing: the zone's GW.p.mm<f64>(2.5) under CYRIUS_COVERAGE=1"
cat > "$D/x1.cyr" <<'X'
include "lib/syscalls.cyr"
struct P { k; }
struct W { p: P; n; }
impl P { fn mm<V>(self, x: V): (V, i64) { return (x, 7); } }
var GP: P = P { 1 };
var GW: W = W { GP, 0 };
var gx, gy = GW.p.mm<f64>(2.5);
syscall(60, gy + f64_to(gx * 2.0));
X
for mode in plain cov; do
    xc=0
    if [ "$mode" = cov ]; then CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D/x1.cov" "$CC" < "$D/x1.cyr" > "$D/x1_$mode" 2> "$D/x1_$mode.err" || xc=$?
    else "$CC" < "$D/x1.cyr" > "$D/x1_$mode" 2> "$D/x1_$mode.err" || xc=$?; fi
    if [ "$xc" -ne 0 ]; then bad "X1 $mode: did not build: $(grep -m1 error "$D/x1_$mode.err")"; continue; fi
    chmod +x "$D/x1_$mode"; xr=0; CYRIUS_COVERAGE_FILE="$D/x1.cov" timeout 60 "$D/x1_$mode" > /dev/null 2>&1 || xr=$?
    if [ "$xr" -eq 12 ]; then ok "X1 $mode: var gx, gy = GW.p.mm<f64>(2.5); exits 12"
    else bad "X1 $mode: var gx, gy = GW.p.mm<f64>(2.5); exits $xr, want 12"; fi
done

# X2: a generic step in the MIDDLE of a chain, in the zone (the lookahead minted an explicit step's instance there:
# `_mch_mres`) — each exits its plain value under the mode too.
XH='include "lib/syscalls.cyr"
struct P { k; }
struct W { p: P; n; }
impl P { fn gq<V>(self, x: V): *P { return self; } fn m2(self): (i64, i64) { return (3, 4); } fn mm<V>(self, x: V): (V, i64) { return (x, 7); } }
var GP: P = P { 1 };
var GW: W = W { GP, 0 };'
x2row() {
    printf '%s\n%s\n%s\n' "$XH" "$2" "$3" > "$D/$1.cyr"
    for mode in plain cov; do
        xc=0
        if [ "$mode" = cov ]; then CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D/$1.cov" "$CC" < "$D/$1.cyr" > "$D/$1_$mode" 2> "$D/$1_$mode.err" || xc=$?
        else "$CC" < "$D/$1.cyr" > "$D/$1_$mode" 2> "$D/$1_$mode.err" || xc=$?; fi
        if [ "$xc" -ne 0 ]; then bad "X2 $1 $mode: $2 did not build: $(grep -m1 error "$D/$1_$mode.err")"; continue; fi
        chmod +x "$D/$1_$mode"; xr=0; CYRIUS_COVERAGE_FILE="$D/$1.cov" timeout 60 "$D/$1_$mode" > /dev/null 2>&1 || xr=$?
        if [ "$xr" -eq "$4" ]; then ok "X2 $1 $mode: $2 exits $4"
        else bad "X2 $1 $mode: $2 exits $xr, want $4"; fi
    done
}
x2row x2a 'var ga, gb = GW.p.gq<f64>(2.5).m2();' 'syscall(60, ga * 10 + gb);' 34
x2row x2b 'var ga, gb = GP.gq<f64>(2.5).m2();' 'syscall(60, ga * 10 + gb);' 34
x2row x2c 'var gt: (i64, i64) = GW.p.gq<f64>(2.5).m2();' 'syscall(60, gt.0 * 10 + gt.1);' 34
x2row x2d 'var ga, gb = (GW).p.gq<f64>(2.5).m2();' 'syscall(60, ga * 10 + gb);' 34
x2row x2e 'var ga, gb = GW.p.gq<f64>(2.5).mm<f64>(2.5);' 'syscall(60, gb + f64_to(ga * 2.0));' 12

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a method ending a chain on any receiver is a method call to every pair / multi-value lookahead: the filed repro (R0) and $N rows (V) on x86_64 / IR / DCE / aarch64 / cx / PE, each refusal word for word (C), the dropped-tag warning (W) and a forwarder below its caller (F) on every receiver head"
