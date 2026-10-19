#!/bin/sh
# tests/gates/frontend/struct_receive_inference_checked.sh — 6.7.11 (returns lane)
#
# A LOCAL'S STRUCT RECEIVE FROM A CALL: PARENTHESES AROUND THE WHOLE CALL ARE TRANSPARENT, AND AN
# ANNOTATION THAT NAMES NO STRUCT IS NEVER OVERRIDDEN BY THE CALLEE'S STRUCT.
# (issues/archived/2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md)
#
# THE DEFECT (measured on 6.7.11's returns-lane tip before the fix, x86_64 / aarch64 under qemu / cx
# under cxvm / PE under wine). PARSE_VAR gives a local initialised from a call returning a struct over
# 8 B the struct's storage and type (the 9-16 B rax:rdx receive, the > 16 B retptr), inferring it from
# the callee when the declaration has none. Both of its tests were too narrow:
#   (a) `var x = (mk());` — the test wanted `IDENT (` right after `=`, so the wrapped call inferred
#       nothing: x held the struct's FIRST word and `dq(x)` into a by-value `q: Q` passed it as the
#       struct's address. The repro: rc 139 / 139 / 1 / 5 (34 is right); `((mk()))`, 24 B and a
#       closure the same.
#   (b) `var x: i64 = mkp();` / `: u8` / `: f64` — "no annotation" was `pscale + lbool == 0`, which a
#       scalar annotation passes, so x became the struct: `x.b` compiled, a `u8` held 333. The repro:
#       3 on all four targets (0 is right). A `: bool` was refused as "not a bool".
# THE FIX. (a) The receive judges the call inside a whole wrap (`_rcv_peel`, `_pwrap_k` up to the `;`)
# and the typed path's `_scv_peel` takes it, as for `var x: Q = (mk());`. 6.7.13: of 8 B or less the peek types it
# (`_var_rhs_wsid`; `x.a` was "no struct type in scope for 'x'"): A3 the repro verbatim, A4 the 16 B method's
# (D42), tcyr w8* / w16_m / wf64 / wexpr, K7. The fix reverted (the 6.7.13 lane base as CYCC; the cross legs
# build from the tree): RED A3 (refused) and A2 K7 (do not build) on x86_64 and PE; D1 (V4d) green. (b) The user's decision
# (2026-10-13, A): an annotation that names no struct, receiving a struct over 8 B (not a `Str`), is
# refused by name at the call (`_rcv_scalar_ann`) —
#   cannot initialise 'x: i64' from 'mkp', which returns the struct 'P2' - declare 'x: P2' or bind a field
# — for every scalar annotation (i64, u8, f64, bool, and i32 / u128 / cstring / an enum alike); the
# variable then keeps its annotation (so the repro's `x.b` is a second, accurate error). A struct of
# 8 B or less and a `Str` handle are one word, which the scalar keeps; a dyn result keeps the 6.7.8
# refusals (`_dyn_var_ann`, V4d / V4n); a generic fn's BASE parse of `var x: T = mkp();` is not judged
# (`_rcv_tp_base`: each instance judges its own T).
#
# LEGS: every refused row on the x86_64, aarch64 (cross), cx and PE (CYRIUS_TARGET_WIN=1) compilers —
# refused, the expected `^error` count, no `^warning`, no binary; every run row on x86_64, aarch64
# (qemu-aarch64), cx (cxvm) and PE (wine, a private prefix). A missing tool is a SKIP that names it.
#
# MUTATION LEDGER (2026-10-14, each a scratch copy of the tree with the one change, its compiler built
# from it, this gate run from the copy as CYCC=<mutant>; every leg RED unless said):
#   N0 the tree before the fix (43066167)                -> RED A0 A1 A2 (rc 139 / 139 / 1 / 5; A2 does
#                                                           not build: its `x.a` rows) and B0 R1-R18
#                                                           (BUILT, or R4 R8 R18 the old "not a bool");
#                                                           K1-K6 D1-D3 green
#   N1 `_rcv_peel` returns 0                             -> RED A0 A1 A2 (139 / 139 / 1 / 5), R9 R10 R18
#                                                           (the wrapped scalar annotations BUILT)
#   N2 `_rcv_iscall` with term `;` for a wrap too        -> RED A0 A1 A2 R9 R10 R18 (as N1)
#   N3 the receive sizing without `_look_pk == 0`        -> RED A0 A1 A2 ("struct-valued assignment RHS
#                                                           must be a fn call")
#   N4 `_rcv_scalar_ann` returns 0                       -> RED B0 R1-R18 (BUILT, or the old "not a bool")
#   N5 PARSE_VAR keeping `lbool` after a refusal         -> RED R18 (2 errors: + "not a bool" at the `(`;
#                                                           unwrapped, the bool check shares the call's
#                                                           token and stays quiet)
#   N6 `_rcv_scalar_ann` without the dyn test            -> RED D3 (2 errors: y left an i64, so
#                                                           `y.show()` cascades; V4n's own report is first)
#   N7 `_rcv_peel` without the dyn test                  -> RED D1 (BUILT: the wrapped dyn inferred)
#   N8 `_rcv_scalar_ann` without `_rcv_tp_base`          -> RED K5 (the base of `gb<P2>` refused)
#   N9 `_rcv_scalar_ann` without the size / Str tests    -> RED K1 K2 (an 8 B struct, a `Str` refused)
#
# 6.7.12 (D28, the user, 2026-10-15: "refused as D24 refuses mk3(5)") — THE SAME AT A KNOWN FN-POINTER CALL.
# `var n: i64 = fncall1(&mk3, 5);` / `= callptr(&mk3, 5);` — the callee written `&f`, so the call carries the
# struct result (6.7.11, ARG-1) — compiled and read P3's first field (the filed repro: exit 55), where the
# direct call is refused. `_scv_icall_ann` (parse_decl.cyr, from `_scv_arm`) refuses it with D24's words,
# naming the callee at its name (issues/2026-10-14-scalar-annotation-from-known-fn-pointer-struct-call-reads-
# first-field.md). FP0 the filed repro verbatim (both declarations refused); FP1-FP8 `fncall0` / `callptr` at
# 16 B and 24 B into i64 / u8 / f64 / bool; FP9 / FP10 a wrapped initialiser (into `: bool`, the bool check not
# run again); FPK1 an 8 B struct is its word, FPK2 a callee in a variable is a word (D31: not refused), FPK3
# an untyped receive is the struct (D31). D28's "the wrapped callee too" rode issues/2026-10-14-parenthesised-fn-
# pointer-callee-loses-struct-result.md (6.7.13): FP11 its acceptance rows (`fncall1((&mk3), 5)` / `callptr((&mk3),
# 5)` into `: i64`, exit 139 before), FP12 FP13 a wrapped callee into `: bool` / inside a wrapped initialiser, FPK4
# an untyped receive of it, TL17 TL18 the same at top level. With the fix reverted (the 6.7.13 lane base as CYCC;
# the cross legs build from the tree): RED 13 — FP11 FP13 TL17 (BUILT), FP12 TL18 (the old "not a bool"), FPK4
# (139 / PE 5), FP11's second line, on x86_64 and PE.
#   N10 `_scv_icall_ann` returns 0 (2026-10-15)          -> RED 45: FP0 (BUILT; and its second line) FP1-FP10 on
#                                                           every leg (BUILT, or FP4 FP8 FP10 the bool check's
#                                                           "not a bool"); FPK1-FPK3 green
#   N11 `_scv_icall_ann` without its `_tn_once(st)` mark -> RED 12: FP8 FP10 on every leg (2 errors: + "not a
#                                                           bool" at the initialiser's first token)
#
# 6.7.13 — D24 AT TOP LEVEL (6.7.12's D28, "D24 at every path", binding). `var G: i64 = mk2(5);` (a 9-16 B struct) and
# `var H: i64 = fncall1(&mk2, 5);` at top level compiled and read the first field (the filed repro: exit 10 on every
# target) — in the declaration zone (`_gvi_expr`'s scalar arm, a plain PCMPE) and after a first statement (PARSE_VAR's
# receive runs only in a fn; D28's `_scv_icall_ann` was fn-only). `_scv_gcall_ann` / `_scv_icall_ann` (parse_decl.cyr,
# through `_scv_top_ann` from `_scv_arm` and `_gvi_expr`) refuse it with D24's words, once (a bool's check not run
# again); over 16 B keeps its one no-frame refusal (`_scv_top_big`), 8 B or less and a `Str` keep the word
# (issues/archived/2026-10-15-d24-scalar-annotation-refusal-misses-top-level.md). TL0 the repro verbatim; TL1-TL14 the zone /
# after a first statement x the direct, wrapped and `&f` forms, a redeclared global, `: u8` / `: f64` / `: cstring` /
# `: bool` (TL15 TL16 wrapped: once), a generic callee; TLK1 a struct annotation (no frame), TLK2 24 B (one error),
# TLK3 the 8 B / `Str` runs. (Each mutant: a scratch copy of the tree with the one change, this gate run from it.)
#   N12 the tree before it (ac17a963)                    -> RED 69: TL0-TL16 on every leg (BUILT; TL12 TL13 TL15 TL16
#                                                           the bool check's "not a bool"), TL0's second line;
#                                                           TLK1-TLK3 green
#   N13 `_scv_gcall_ann` returns 0                       -> RED 52: TL0 (one error, not 2) TL1 TL3 TL4 TL7-TL12 TL14
#                                                           TL15 TL16 x4 legs
#   N14 `_gvi_expr` without `_scv_top_ann`               -> RED 37: TL0 (+ its second line) TL1 TL2 TL7 TL9 TL11 TL12
#                                                           TL14 TL15 x4 (the zone; after a first statement green)
#   N15 `_scv_icall_ann` with its `GINFN != 1` return    -> RED 21: TL0 (+ its second line) TL2 TL5 TL6 TL13 x4
#   N16 `_scv_top_big` returns 0                         -> RED 4: TLK2 x4 (2 errors: + D24's at the call)
#   N17 `_scv_gcall_ann` without its `_tn_once(st)` mark -> RED 8: TL15 TL16 x4 (2 errors: + "not a bool" at the `(`)
#
# 6.7.13 — D13 (the user, 2026-10-15): D24 REACHES A METHOD OR OPERATOR RESULT. `var x: i64 = b.mk();` / `var y: u8 = a + c;`
# (any annotation that names no struct) with the method / operator fn returning a struct over 8 B kept the struct's first
# word, narrowed (the filed repro exited 77 on every target), and a `: bool` was "not a bool". `_scv_rec_ann`
# (parse_decl.cyr; PARSE_VAR after the initialiser's parse, and the declaration zone's `_gvi_scalar`) reads the
# struct-result record (`_sc_whole`) and refuses with D24's words through the shared `_rcv_ann_refuse`, naming the fn
# (issues/archived/2026-10-14-scalar-annotation-from-struct-method-or-operator-keeps-first-word.md). SA0 the repro verbatim;
# SA1-SA13 a 16 B / 24 B method and a 16 B / 24 B operator into i64 / u8 / f64 / bool; SA14 SA15 SA24 wrapped; SA16 a
# generic method; SA17 a closure; SA18 SA22 `: cstring` (SA22: the annotation stands, `x.b` the second error); SA19 a
# chain; SA20 a generic instance (T = i32); SA21 `x.b` the second error; SA23 an initialiser refused inside is not
# refused again; SAT1-SAT6 top level, the zone and after a first statement; controls SATK1 (24 B at top level: one
# no-frame refusal), SATK2 SAK1 SAK2 (8 B and `Str` keep the word), SAK3 (a struct annotation receives), SAK4 (untyped,
# a field), SAK5 (`var x: T` in `gb<Q>`), SAK6 (an 8 B method into `: bool` keeps the bool check). (Each mutant: a
# scratch copy of the tree with the one change, its compiler built from it, this gate run from the copy as CYCC.)
#   N18 the tree before it (7c29f2e1)                    -> RED 121: SA0 (+ its second line) SA1-SA22 SA24 SAT1-SAT6 x4
#                                                           legs (BUILT, or the bool check's "not a bool" / one error
#                                                           where two are wanted); SA23 and every control green
#   N19 `_scv_rec_ann` returns 0                         -> RED 121 (as N18)
#   N20 `_gvi_scalar` without `_scv_rec_ann`             -> RED 12: SAT1 SAT3 SAT5 x4 (the declaration zone)
#   N21 `_scv_rec_ann` without its `_tn_once(start)` mark-> RED 8: SA15 SAT5 x4 (2 errors: + "not a bool" at the `(`)
#   N22 `_sc_var_receive` without the `_scv_refd` test   -> RED 4: SA22 x4 (one error: x received the struct)
#   N23 `_scv_rec_ann` without the `_scv_err` test       -> RED 4: SA23 x4 (2 errors)
#   N24 `_rcv_ann_hit` without the size / `Str` tests    -> RED 20: K1 K2 FPK1 FPK4 TLK3 x4 (a method / operator of 8 B
#                                                           or less is never offered: its record is -3)
#
# 6.7.13 — D14 (the user, 2026-10-15): A BY-VALUE STRUCT OVER 8 B INTO A POINTER ANNOTATION, refused by name in a fn:
# "cannot initialise 'x: *P2' from 'mkp', which returns the struct 'P2' - declare 'x: P2' and take `&x`". It compiled
# under "assigning non-pointer to typed pointer" and stored the struct's first word as the pointer (the filed repros:
# 139 / 139 / 14 / 5 for `*P2`, 77 for `*i64`). PARSE_VAR's receive is gated on `pscale <= 0`; `_rcv_ptr_ann` takes the
# free call (wrapped, generic), `_scv_icall_ann` the known `&f` call and `_scv_rec_ann` a method / operator, each through
# `_rcv_ann_refuse` with the pointer remedy, the typed-pointer warning silenced on the refused line (`_ptr_refd_ti`)
# (issues/archived/2026-10-14-pointer-annotated-local-from-byvalue-struct-call.md). PT0 PT00 the two repros verbatim; PT1-PT9
# `*u8` / `*P3` / `*i64` at 16 and 24 B, wrapped, a generic callee, a closure, `*T` in a generic fn; PT10-PT13 `&f`
# (`fncall0`, `callptr`, the callee wrapped, the call wrapped; PT10's refusal at the callee's name, as D28's); PT14-PT18
# a method, an operator, wrapped, a generic method; controls PTK1 PTK2 (8 B keeps its word AND the warning), PTK3
# (`x = mkp();` into a `*P2` local copies through it), PTK4 (the remedy), PTK5 (a `Str` into `*Str`). Top level is
# taken by 6.7.14's D28 (PTT rows, below).
#   N25 the tree before it (6ab2a9c8)                    -> RED 80: PT0 PT00 PT1-PT18 x4 (BUILT with the warning)
#   N26 `_rcv_ptr_ann` returns 0                         -> RED 44: PT0 PT00 PT1-PT9 x4
#   N27 `_scv_icall_ann` without its pointer arm         -> RED 1: PT10's column (`_scv_rec_ann` still refuses the `&f`
#                                                           call from its struct-result record, at `fncall0`)
#   N28 `_scv_rec_ann` without its pointer arm           -> RED 20: PT14-PT18 x4
#   N29 `_rcv_ptr_ann` without `_ptr_refd_ti`            -> RED 44: PT0 PT00 PT1-PT9 x4 (a warning beside the refusal)
#   N30 `_rcv_ptr_ann` without the wrap peel             -> RED 8: PT5 PT6 x4
#   N31 `_scv_rec_ann` without `_ptr_refd_ti`            -> RED 20: PT14-PT18 x4 (a warning beside the refusal)
#
# 6.7.14 — A GENERIC `: *T` CALL INTO AN ANNOTATED LOCAL IS A HANDLE. `var h: S = gpg<S>();` (`fn gpg<T>(): *T`) dropped its
# `S`: PARSE_VAR's B-explicit reset (`pscale = 0`, re-derive the receive from the callee) ran for every generic callee
# the struct check (`_gen_decl_check`) did not keep, and that check answers 0 for a return that is no struct by value
# (`: *T` records GFRS -8). `h` was an untyped word, `h.v = 6` "no struct type in scope for 'h'" (the filed repro:
# 68 / refused / 8). `_gen_decl_reset` (parse_decl.cyr) resets only for a generic returning a struct BY VALUE, so the
# local keeps `S` and binds the handle, as the non-generic `fn gp(): *S` does (the 6.7.10 handle line)
# (issues/archived/2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md). GH0a-GH0c the filed loop's three
# programs; GH1 GH2 inferred; GH3-GH5 uses that name no field; GH6 GH7 24 / 8 B; GH8 an untyped-value return; GH9 a
# refused type argument reported once; GHK1-GHK4 a by-value generic receive and the 6.6.11 mismatch unchanged.
#   N32 `_gen_decl_reset` without its GFRS test (2026-10-16) -> RED 28: GH0b GH1 GH2 GH6 GH7 GH8 x4 legs (refused: no
#                                                           struct type in scope for 'h'), GH9 x4 (3 errors); GH3-GH5 green
#                                                           (the untyped word held the same address: they pin that the
#                                                           handle's uses stay right), GH0a GH0c GHK1-GHK4 green
# A generic returning its own `: T` kept the reset (`_gen_ret_tp`) through 6.7.14: at a scalar instance the struct-
# annotated local was refused at its field use. 6.7.15 — THE USER'S D13 (a), 2026-10-18: it is a handle, as the
# non-generic word-returning call is (issues/2026-10-17-generic-t-return-scalar-instance-into-struct-local-reported-at-use.md;
# tests/gates/frontend/generic_t_return_decl.sh carries the rows of that decision). GHT1-GHT4 now pin the handle: a field
# use compiles, and the word the handle holds is the call's (GHT1 `gid(&GQ)` reads GQ.z through it); GHT5 the
# struct-instance control.
#   N33 (6.7.15) `_gen_decl_reset` with 6.7.14's `_gen_ret_tp` reset -> RED 8: GHT1-GHT4 on x86_64 / PE (refused: "no
#                                                           struct type in scope for 'a'"; the aarch64 / cx legs build
#                                                           from the tree); GHT5 and the rest green
#
# 6.7.14 — D28 (the user, 2026-10-16): D14 AT TOP LEVEL, every `*T` and every path. `var X: *P2 = mkp();` (`= B.mk();`,
# `= A + C;`, `= callptr(&mkp);`, `*i64`, `*u8`) after the first statement compiled under the typed-pointer warning and
# stored the struct's first word as the pointer (the filed repro: 139 / 139 / 14 / 5); in the declaration zone the free
# and `&f` calls were refused with D24's scalar remedy (the replay gives a pointer annotation `gps` 0) and a method /
# operator result compiled under the warning (issues/archived/2026-10-16-top-level-pointer-annotation-from-byvalue-struct-call.md).
# `_scv_gcall_ann` takes a pointer annotation with D14's remedy, `_scv_icall_ann` and `_scv_rec_ann` lose their in-a-fn
# gates, the zone's `_gvi_scalar` passes the pointer (`_gvi_ptr_ann`), and PARSE_VAR's warning stays quiet on a line
# refused inside its initialiser (`_tp_warn_decl`: a top-level 24 B call, whose one refusal is the no-frame one).
# PTT0 PTT0z PTT0m the three filed repros verbatim; PTT1-PTT10 x {zone, after}: free, wrapped, `fncall1`, a wrapped
# `callptr((&mk2), ..)`, `**P2`, a generic, a method, a wrapped method, an operator, a generic method; PTT11-PTT13 24 B
# (one no-frame refusal, no warning); PTT14 after an earlier error (still no warning); PTTK1-PTTK3 8 B and `Str` keep
# their word and the warning.
#   N36 the tree before it (R3's tip, c5c4a165)          -> RED 110: every PTT row x4 legs but PTT11zone-PTT13zone and
#                                                           PTT14zone (the zone was quiet there); the PTT3 / PTT14 checks
#   N37 `_scv_gcall_ann` without its pointer arm         -> RED 49: PTT0 PTT0z PTT1 PTT2 PTT5 PTT6 PTT14 x {zone, after}
#   N38 `_scv_icall_ann` with its in-a-fn `*T` gate      -> RED 1: PTT3's column (`_scv_rec_ann` refuses the `&f` call
#                                                           from its record, at `fncall1`)
#   N39 `_scv_rec_ann` with its in-a-fn `*T` gate        -> RED 36: PTT0m PTT7-PTT10 x {zone, after}
#   N40 `_gvi_scalar` passing 0 (no `_gvi_ptr_ann`)      -> RED 49: PTT0z PTT0m PTT1zone-PTT10zone (D24's remedy, or built)
#   N41 `_tp_warn_decl` without its `_scv_err` test      -> RED 12: PTT11after-PTT13after (a warning beside the no-frame
#                                                           refusal)
#   N42 `_scv_gcall_ann` without `_ptr_refd_ti`          -> RED 4: PTT14after (after an earlier error `_scv_err` cannot tell)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_receive_inference_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
rows=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

A64="$T/cc_a64"
QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$A64" 2> "$T/cc_a64.err" && [ -s "$A64" ]; then chmod +x "$A64"; QEMU=1
    else bad "src/main_aarch64.cyr did not build: $(grep '^error' "$T/cc_a64.err" | head -1 || true)"; fi
else echo "  SKIP the aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
CX=0
CXC="$T/cc_cx"
if "$CC" < src/main_cx.cyr > "$CXC" 2> "$T/cc_cx.err" && [ -s "$CXC" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$CXC" "$T/cxvm"; CX=1
else bad "src/main_cx.cyr or programs/cxvm.cyr did not build: $(grep '^error' "$T/cc_cx.err" "$T/cxvm.err" | head -1 || true)"; fi
WINE=0
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP the PE run leg — wine not installed (the PE refusals still run)"; skips=$((skips + 1)); fi

# compile <leg> <name>: $T/<name>.<leg> (+ .err); rc in $crc
compile() {
    crc=0
    case $1 in
        x86_64)  timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        aarch64) timeout 60 "$A64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        cx)      timeout 60 "$CXC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        pe)      CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
    esac
}
legs() {
    l="x86_64"
    [ "$QEMU" -eq 1 ] && l="$l aarch64"
    [ "$CX" -eq 1 ] && l="$l cx"
    echo "$l pe"
}
# refused <name> <fragment> <what> [<errors>]: the source is $T/<name>.cyr; <errors> (default 1)
# `^error` lines, the first holding <fragment>
refused() {
    rows=$((rows + 1))
    want=${4:-1}
    for leg in $(legs); do
        compile "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        w=$(grep -c '^warning' "$T/$1.$leg.err" || true)
        if [ "$crc" -eq 0 ]; then bad "$1 $3 ($leg): BUILT (rc 0)"
        elif ! grep '^error' "$T/$1.$leg.err" | head -1 | grep -qF "$2"; then bad "$1 $3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne "$want" ]; then bad "$1 $3 ($leg): $n error lines (want $want)"
        elif [ "$w" -ne 0 ]; then bad "$1 $3 ($leg): a warning beside the refusal: $(grep '^warning' "$T/$1.$leg.err" | head -1 || true)"
        elif [ -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): refused, but a binary was written"
        else ok "$1 $3 ($leg): refused ($n)"; fi
    done
}
# runs <name> <want> <what>: compiles clean and exits <want> on every leg
runs() {
    rows=$((rows + 1))
    for leg in $(legs); do
        [ "$leg" = pe ] && [ "$WINE" -eq 0 ] && continue
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        chmod +x "$T/$1.$leg"; got=0
        case $leg in
            x86_64)  timeout 30 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            aarch64) timeout 60 qemu-aarch64 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            cx)      timeout 60 "$T/cxvm" < "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            pe)      cp "$T/$1.$leg" "$T/$1.exe"
                     (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                         WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$1.exe" > /dev/null 2>&1) || got=$? ;;
        esac
        if [ "$got" = "$2" ]; then ok "$1 $3 ($leg): exit $got"; else bad "$1 $3 ($leg): exit $got, want $2"; fi
    done
}
# prints <name> <want> <what>: compiles clean, exits 0 and prints exactly <want> (its lines joined by `|`) on every leg
prints() {
    rows=$((rows + 1))
    for leg in $(legs); do
        [ "$leg" = pe ] && [ "$WINE" -eq 0 ] && continue
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        chmod +x "$T/$1.$leg"; got=0
        case $leg in
            x86_64)  timeout 30 "$T/$1.$leg" > "$T/$1.$leg.out" 2> /dev/null || got=$? ;;
            aarch64) timeout 60 qemu-aarch64 "$T/$1.$leg" > "$T/$1.$leg.out" 2> /dev/null || got=$? ;;
            cx)      timeout 60 "$T/cxvm" < "$T/$1.$leg" > "$T/$1.$leg.out" 2> /dev/null || got=$? ;;
            pe)      cp "$T/$1.$leg" "$T/$1.exe"
                     (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                         WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$1.exe" > "$T/$1.$leg.out" 2> /dev/null) || got=$? ;;
        esac
        o=$(tr -d '\r' < "$T/$1.$leg.out" | tr '\n' '|')
        if [ "$got" != 0 ]; then bad "$1 $3 ($leg): exit $got, want 0"
        elif [ "$o" = "$2" ]; then ok "$1 $3 ($leg): printed [$o]"
        else bad "$1 $3 ($leg): printed [$o], want [$2]"; fi
    done
}
# quiet <name> <what>: the last compile of <name> on every leg printed no `^warning`
quiet() {
    rows=$((rows + 1))
    for leg in $(legs); do
        [ -f "$T/$1.$leg.err" ] || compile "$leg" "$1"
        if grep -q '^warning' "$T/$1.$leg.err"; then bad "$1 $2 ($leg): $(grep '^warning' "$T/$1.$leg.err" | head -1)"
        else ok "$1 $2 ($leg): no warning"; fi
    done
}
REPA=docs/development/issues/repros/2026-10-10-struct-receive-inference-a-parenthesised-call.cyr
REPB=docs/development/issues/repros/2026-10-10-struct-receive-inference-b-scalar-annotation.cyr
[ -f "$REPA" ] && [ -f "$REPB" ] || { echo "FAIL: $G: the issue's repro files are missing"; exit 1; }

# --- the issue's repros, verbatim ---
cp "$REPA" "$T/A0.cyr"
runs A0 34 "repro (a) verbatim: \`var x = (mk());\` into a by-value parameter"
cp "$REPB" "$T/B0.cyr"
refused B0 "cannot initialise 'x: i64' from 'mkp', which returns the struct 'P2' - declare 'x: P2' or bind a field" \
    "repro (b) verbatim: \`x: i64\` and \`y: u8\` refused, x keeps its i64 (\`x.b\` the third error)" 3
if grep -qF "cannot initialise 'y: u8' from 'mkp', which returns the struct 'P2' - declare 'y: P2' or bind a field" "$T/B0.x86_64.err"; then
    ok "B0 the second declaration is refused by name too"
else bad "B0 the second declaration (\`y: u8\`) was not refused by name"; fi

H='include "lib/syscalls.cyr"
struct P2 { a; b; }
struct P3 { a; b; c; }
struct P1 { a; }
enum E { EA, EB }
struct Bx<T> { a: T; b: T; }
fn mkp(): P2 { var p: P2; p.a = 30; p.b = 4; return p; }
fn mk3(): P3 { var p: P3; p.a = 30; p.b = 4; p.c = 7; return p; }
fn mk1(): P1 { var p: P1; p.a = 33; return p; }
fn mkg<T>(v: T): Bx<T> { var b: Bx<T>; b.a = v; b.b = v + 1; return b; }
fn dq(q: P2): i64 { return q.a + q.b; }
fn dq3(q: P3): i64 { return q.a + q.b + q.c - 7; }'
row() { printf '%s\n%s\nsyscall(60, f());\n' "$H" "$2" > "$T/$1.cyr"; }
M16="from 'mkp', which returns the struct 'P2' - declare 'x: P2' or bind a field"
M24="from 'mk3', which returns the struct 'P3' - declare 'x: P3' or bind a field"

# --- (b): every scalar annotation, 9-16 B and > 16 B ---
row R1 'fn f(): i64 { var x: i64 = mkp(); return x; }'
refused R1 "cannot initialise 'x: i64' $M16" "16 B into \`: i64\`"
row R2 'fn f(): i64 { var x: u8 = mkp(); return x; }'
refused R2 "cannot initialise 'x: u8' $M16" "16 B into \`: u8\` (it held 333)"
row R3 'fn f(): i64 { var x: f64 = mkp(); return 0; }'
refused R3 "cannot initialise 'x: f64' $M16" "16 B into \`: f64\`"
row R4 'fn f(): i64 { var x: bool = mkp(); if (x) { return 1; } return 0; }'
refused R4 "cannot initialise 'x: bool' $M16" "16 B into \`: bool\` (was \"not a bool\")"
row R5 'fn f(): i64 { var x: i64 = mk3(); return x; }'
refused R5 "cannot initialise 'x: i64' $M24" "24 B into \`: i64\`"
row R6 'fn f(): i64 { var x: u8 = mk3(); return x; }'
refused R6 "cannot initialise 'x: u8' $M24" "24 B into \`: u8\`"
row R7 'fn f(): i64 { var x: f64 = mk3(); return 0; }'
refused R7 "cannot initialise 'x: f64' $M24" "24 B into \`: f64\`"
row R8 'fn f(): i64 { var x: bool = mk3(); if (x) { return 1; } return 0; }'
refused R8 "cannot initialise 'x: bool' $M24" "24 B into \`: bool\`"
row R9 'fn f(): i64 { var x: i64 = (mkp()); return x; }'
refused R9 "cannot initialise 'x: i64' $M16" "a wrapped call, \`(mkp())\`"
row R10 'fn f(): i64 { var x: u8 = ((mk3())); return x; }'
refused R10 "cannot initialise 'x: u8' $M24" "a wrapped call, \`((mk3()))\`"
row R11 'fn f(): i64 { var g = |k| { var x: u8 = mkp(); return x + k; }; return fncall1(g, 0); }'
refused R11 "cannot initialise 'x: u8' $M16" "in a closure"
row R12 'fn f(): i64 { var x: i64 = mkg<i64>(3); return x; }'
refused R12 "cannot initialise 'x: i64' from 'mkg', which returns the struct 'Bx' - declare 'x: Bx' or bind a field" "a generic callee"
row R13 'fn gb<T>(v: T): i64 { var x: T = mkp(); return 0; }
fn f(): i64 { return gb<i32>(3); }'
refused R13 "cannot initialise 'x: T' $M16" "a generic instance whose T is i32"
row R14 'fn f(): i64 { var x: i32 = mkp(); return x; }'
refused R14 "cannot initialise 'x: i32' $M16" "\`: i32\`"
row R15 'fn f(): i64 { var x: u128 = mkp(); return 0; }'
refused R15 "cannot initialise 'x: u128' $M16" "\`: u128\`"
row R16 'fn f(): i64 { var x: cstring = mkp(); return 0; }'
refused R16 "cannot initialise 'x: cstring' $M16" "\`: cstring\`"
row R17 'fn f(): i64 { var x: E = mk3(); return 0; }'
refused R17 "cannot initialise 'x: E' $M24" "an enum annotation"
row R18 'fn f(): i64 { var x: bool = (mkp()); if (x) { return 1; } return 0; }'
refused R18 "cannot initialise 'x: bool' $M16" "a wrapped call into \`: bool\` (the bool check not run again)"

# --- D28 (6.7.12): a known fn-pointer call (`fncallN(&f, ..)` / `callptr(&f, ..)`) ---
REPF=docs/development/issues/repros/2026-10-14-scalar-annotation-from-known-fn-pointer-struct-call-reads-first-field.cyr
[ -f "$REPF" ] || { echo "FAIL: $G: $REPF is missing"; exit 1; }
cp "$REPF" "$T/FP0.cyr"
refused FP0 "cannot initialise 'n: i64' from 'mk3', which returns the struct 'P3' - declare 'n: P3' or bind a field" \
    "the D28 repro verbatim: \`fncall1(&mk3, 5)\` and \`callptr(&mk3, 5)\` into \`: i64\` (exit 55 before)" 2
if grep -qF "cannot initialise 'm: i64' from 'mk3', which returns the struct 'P3' - declare 'm: P3' or bind a field" "$T/FP0.x86_64.err"; then
    ok "FP0 the callptr declaration is refused by name too"
else bad "FP0 the second declaration (\`m: i64 = callptr(&mk3, 5)\`) was not refused by name"; fi
rowf() { printf 'include "lib/fnptr.cyr"\n%s\n%s\nsyscall(60, f());\n' "$H" "$2" > "$T/$1.cyr"; }
rowf FP1 'fn f(): i64 { var x: i64 = fncall0(&mkp); return x; }'
refused FP1 "cannot initialise 'x: i64' $M16" "fncall0(&mkp) (16 B) into \`: i64\`"
rowf FP2 'fn f(): i64 { var x: u8 = callptr(&mkp); return x; }'
refused FP2 "cannot initialise 'x: u8' $M16" "callptr(&mkp) (16 B) into \`: u8\`"
rowf FP3 'fn f(): i64 { var x: f64 = fncall0(&mkp); return 0; }'
refused FP3 "cannot initialise 'x: f64' $M16" "fncall0(&mkp) (16 B) into \`: f64\`"
rowf FP4 'fn f(): i64 { var x: bool = callptr(&mkp); if (x) { return 1; } return 0; }'
refused FP4 "cannot initialise 'x: bool' $M16" "callptr(&mkp) (16 B) into \`: bool\`"
rowf FP5 'fn f(): i64 { var x: i64 = callptr(&mk3); return x; }'
refused FP5 "cannot initialise 'x: i64' $M24" "callptr(&mk3) (24 B) into \`: i64\`"
rowf FP6 'fn f(): i64 { var x: u8 = fncall0(&mk3); return x; }'
refused FP6 "cannot initialise 'x: u8' $M24" "fncall0(&mk3) (24 B) into \`: u8\`"
rowf FP7 'fn f(): i64 { var x: f64 = callptr(&mk3); return 0; }'
refused FP7 "cannot initialise 'x: f64' $M24" "callptr(&mk3) (24 B) into \`: f64\`"
rowf FP8 'fn f(): i64 { var x: bool = fncall0(&mk3); if (x) { return 1; } return 0; }'
refused FP8 "cannot initialise 'x: bool' $M24" "fncall0(&mk3) (24 B) into \`: bool\`"
rowf FP9 'fn f(): i64 { var x: i64 = ((fncall0(&mk3))); return x; }'
refused FP9 "cannot initialise 'x: i64' $M24" "a wrapped initialiser, \`((fncall0(&mk3)))\`"
rowf FP10 'fn f(): i64 { var x: bool = (callptr(&mkp)); if (x) { return 1; } return 0; }'
refused FP10 "cannot initialise 'x: bool' $M16" "a wrapped initialiser into \`: bool\` (the bool check not run again)"
rowf FPK1 'fn f(): i64 { var x: i64 = fncall0(&mk1); return x + 1; }'
runs FPK1 34 "control: an 8 B struct through \`fncall0(&mk1)\` into \`: i64\` is its one word"
rowf FPK2 'fn f(): i64 { var fp = &mkp; var x: i64 = callptr(fp); return x + 4; }'
runs FPK2 34 "control: a callee held in a variable is a word (D31), not refused"
rowf FPK3 'fn f(): i64 { var x = callptr(&mk3); var y = fncall0(&mkp); return dq3(x) + dq(y) - 34; }'
runs FPK3 34 "control: an untyped receive of a known callee is the struct (D31)"
# 6.7.13 — the callee in parentheses, `(&mk3)`, is the known callee (issues/2026-10-14-parenthesised-fn-pointer-
# callee-loses-struct-result.md): D28's acceptance rows, refused with D24's words naming mk3 (they compiled and exited
# 139 on x86_64 / aarch64, 1 on cx, 5 on PE).
cat > "$T/FP11.cyr" <<'EOF'
include "lib/fnptr.cyr"
struct P3 { a; b; c; }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
fn main(): i64 { var n: i64 = fncall1((&mk3), 5); var m: i64 = callptr((&mk3), 5); return n + m; }
syscall(60, main());
EOF
refused FP11 "cannot initialise 'n: i64' from 'mk3', which returns the struct 'P3' - declare 'n: P3' or bind a field" \
    "D28's wrapped callee: \`fncall1((&mk3), 5)\` and \`callptr((&mk3), 5)\` into \`: i64\` (exit 139 before)" 2
if grep -qF "cannot initialise 'm: i64' from 'mk3', which returns the struct 'P3' - declare 'm: P3' or bind a field" "$T/FP11.x86_64.err"; then
    ok "FP11 the callptr declaration is refused by name too"
else bad "FP11 the second declaration (\`m: i64 = callptr((&mk3), 5)\`) was not refused by name"; fi
rowf FP12 'fn f(): i64 { var x: bool = fncall0(((&mk3))); if (x) { return 1; } return 0; }'
refused FP12 "cannot initialise 'x: bool' $M24" "\`fncall0(((&mk3)))\` into \`: bool\` (the bool check not run again)"
rowf FP13 'fn f(): i64 { var x: u8 = (callptr((&mkp))); return x; }'
refused FP13 "cannot initialise 'x: u8' $M16" "a wrapped initialiser and callee, \`(callptr((&mkp)))\`"
rowf FPK4 'fn f(): i64 { var x = callptr((&mk3)); var y = fncall0(((&mkp))); var z: i64 = fncall0((&mk1)); return dq3(x) + dq(y) + z - 67; }'
runs FPK4 34 "control: an untyped receive of a wrapped known callee is the struct; 8 B into \`: i64\` its word"

# --- D24 at top level (6.7.13; 6.7.12's D28, "D24 at every path"): the declaration zone and after a first statement ---
# The filed repro, verbatim (issues/archived/2026-10-15-d24-scalar-annotation-refusal-misses-top-level.md): exit 10 before.
cat > "$T/TL0.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct P2 { a; b; }
fn mk2(x): P2 { var r = P2 { x, x + 1 }; return r; }
var G: i64 = mk2(5);
var H: i64 = fncall1(&mk2, 5);
syscall(60, G + H);
EOF
refused TL0 "cannot initialise 'G: i64' from 'mk2', which returns the struct 'P2' - declare 'G: P2' or bind a field" \
    "the filed repro verbatim: \`mk2(5)\` and \`fncall1(&mk2, 5)\` into top-level \`: i64\` (exit 10 before)" 2
if grep -qF "cannot initialise 'H: i64' from 'mk2', which returns the struct 'P2' - declare 'H: P2' or bind a field" "$T/TL0.x86_64.err"; then
    ok "TL0 the fncall1 declaration is refused by name too"
else bad "TL0 the second declaration (\`H: i64 = fncall1(&mk2, 5)\`) was not refused by name"; fi
TH='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
struct P1 { a; }
struct P2 { a; b; }
struct P3 { a; b; c; }
fn mk1(x): P1 { var r = P1 { x }; return r; }
fn mk2(x): P2 { var r = P2 { x, x + 1 }; return r; }
fn mk3(x): P3 { var r = P3 { x, x + 1, x + 2 }; return r; }
fn mkg<T>(x: T): P2 { var r = P2 { x, x + 1 }; return r; }
fn mks(): Str { return str_from("abcde"); }'
TS='var Z = 0;
Z = 1;'
# rowt <name> <zone|after> <declarations>: the declarations in the declaration zone, or after a first statement
rowt() {
    if [ "$2" = zone ]; then printf '%s\n%s\nsyscall(60, 0);\n' "$TH" "$3" > "$T/$1.cyr"
    else printf '%s\n%s\n%s\nsyscall(60, 0);\n' "$TH" "$TS" "$3" > "$T/$1.cyr"; fi
}
MT="from 'mk2', which returns the struct 'P2' - declare 'G: P2' or bind a field"
rowt TL1 zone 'var G: i64 = (mk2(5));'
refused TL1 "cannot initialise 'G: i64' $MT" "the declaration zone: \`(mk2(5))\`"
rowt TL2 zone 'var G: i64 = callptr(&mk2, 5);'
refused TL2 "cannot initialise 'G: i64' $MT" "the declaration zone: \`callptr(&mk2, 5)\`"
rowt TL3 after 'var G: i64 = mk2(5);'
refused TL3 "cannot initialise 'G: i64' $MT" "after a first statement: \`mk2(5)\`"
rowt TL4 after 'var G: i64 = (mk2(5));'
refused TL4 "cannot initialise 'G: i64' $MT" "after a first statement: \`(mk2(5))\`"
rowt TL5 after 'var G: i64 = fncall1(&mk2, 5);'
refused TL5 "cannot initialise 'G: i64' $MT" "after a first statement: \`fncall1(&mk2, 5)\`"
rowt TL6 after 'var G: i64 = callptr(&mk2, 5);'
refused TL6 "cannot initialise 'G: i64' $MT" "after a first statement: \`callptr(&mk2, 5)\`"
rowt TL7 zone 'var G: i64 = 0;
var G: i64 = mk2(5);'
refused TL7 "cannot initialise 'G: i64' $MT" "a redeclared global in the declaration zone (exit 5 before)"
rowt TL8 after 'var G: i64 = 0;
var G: i64 = mk2(5);'
refused TL8 "cannot initialise 'G: i64' $MT" "a redeclared global after a first statement"
rowt TL9 zone 'var G: u8 = mk2(5);'
refused TL9 "cannot initialise 'G: u8' $MT" "the declaration zone: \`: u8\`"
rowt TL10 after 'var G: f64 = mk2(5);'
refused TL10 "cannot initialise 'G: f64' $MT" "after a first statement: \`: f64\`"
rowt TL11 zone 'var G: cstring = mk2(5);'
refused TL11 "cannot initialise 'G: cstring' $MT" "the declaration zone: \`: cstring\`"
rowt TL12 zone 'var G: bool = mk2(5);'
refused TL12 "cannot initialise 'G: bool' $MT" "the declaration zone: \`: bool\` (D24's words, the bool check not run again)"
rowt TL13 after 'var G: bool = (fncall1(&mk2, 5));'
refused TL13 "cannot initialise 'G: bool' $MT" "after a first statement: a wrapped call into \`: bool\` (once)"
rowt TL14 zone 'var G: i64 = mkg<i64>(5);'
refused TL14 "cannot initialise 'G: i64' from 'mkg', which returns the struct 'P2' - declare 'G: P2' or bind a field" "the declaration zone: a generic callee"
rowt TL15 zone 'var G: bool = (mk2(5));'
refused TL15 "cannot initialise 'G: bool' $MT" "the declaration zone: a wrapped direct call into \`: bool\` (once)"
rowt TL16 after 'var G: bool = ((mk2(5)));'
refused TL16 "cannot initialise 'G: bool' $MT" "after a first statement: a wrapped direct call into \`: bool\` (once)"
rowt TLK1 zone 'var G: P2 = mk2(5);'
refused TLK1 "returns a struct by value, and a struct result needs storage in a fn's frame" "control: \`var G: P2 = mk2(5);\` keeps its no-frame refusal"
rowt TLK2 after 'var G: i64 = mk3(5);'
refused TLK2 "returns a struct by value, and a struct result needs storage in a fn's frame" "control: over 16 B keeps its one no-frame refusal"
printf '%s\nvar A: i64 = mk1(5);\nvar B: i64 = fncall1(&mk1, 6);\n%s\nalloc_init();\nvar C: i64 = mk1(9);\nvar D: i64 = mks();\nvar E: i64 = callptr(&mk1, 9);\nsyscall(60, A + B + C + str_len(D) + E);\n' "$TH" "$TS" > "$T/TLK3.cyr"
runs TLK3 34 "control: an 8 B struct (direct, \`fncall1\`, \`callptr\`) and a \`Str\` into top-level \`: i64\`, the zone and after"
rowt TL17 zone 'var G: i64 = callptr((&mk2), 5);'
refused TL17 "cannot initialise 'G: i64' $MT" "the declaration zone: the callee in parentheses, \`callptr((&mk2), 5)\` (6.7.13; exit 5 before)"
rowt TL18 after 'var G: bool = fncall1(((&mk2)), 5);'
refused TL18 "cannot initialise 'G: bool' $MT" "after a first statement: \`fncall1(((&mk2)), 5)\` into \`: bool\` (once)"

# --- D13 (6.7.13; the user, 2026-10-15): D24 reaches a METHOD or OPERATOR result, in a fn and at top level ---
# (issues/archived/2026-10-14-scalar-annotation-from-struct-method-or-operator-keeps-first-word.md) The filed repro, verbatim:
# exit 77 on x86_64 / aarch64 / cx / PE before (x = 333, y = 77); now both declarations are refused by name.
cat > "$T/SA0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn Q_add(l: *Q, r: *Q): Q { var q: Q; q.a = l.a + r.a; q.b = l.b + r.b; return q; }
fn main(): i64 {
    var b = Q { 1, 2 };
    var x: i64 = b.mk();          # 333 — the first word
    var a = Q { 300, 2 };
    var c = Q { 33, 2 };
    var y: u8 = a + c;            # 333 narrowed to 77
    return x % 256 + y - 77;      # 77 on every target
}
syscall(60, main());
EOF
refused SA0 "cannot initialise 'x: i64' from 'Q.mk', which returns the struct 'Q' - declare 'x: Q' or bind a field" \
    "D13's repro verbatim: \`var x: i64 = b.mk();\` and \`var y: u8 = a + c;\` (exit 77 before)" 2
if grep -qF "cannot initialise 'y: u8' from 'Q_add', which returns the struct 'Q' - declare 'y: Q' or bind a field" "$T/SA0.x86_64.err"; then
    ok "SA0 the operator declaration is refused by name too"
else bad "SA0 the second declaration (\`y: u8 = a + c\`) was not refused by name"; fi
MH='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
struct Q { a; b; }
struct Q3 { a; b; c; }
struct Q1 { a; }
impl Q {
    fn mk(self): Q { var q: Q; q.a = 30; q.b = 4; return q; }
    fn mk3(self): Q3 { var q: Q3; q.a = 30; q.b = 4; q.c = 7; return q; }
    fn mk1(self): Q1 { var q: Q1; q.a = 33; return q; }
    fn ms(self): Str { return str_from("abc"); }
    fn mkg<T>(self, v: T): Q { var q: Q; q.a = v; q.b = 4; return q; }
}
fn Q_add(l: *Q, r: *Q): Q { var q: Q; q.a = l.a + r.a; q.b = l.b + r.b; return q; }
fn Q3_add(l: *Q3, r: *Q3): Q3 { var q: Q3; q.a = l.a + r.a; q.b = l.b + r.b; q.c = 7; return q; }
fn Q1_add(l: *Q1, r: *Q1): Q1 { var q: Q1; q.a = l.a + r.a; return q; }
fn dqm(q: Q): i64 { return q.a + q.b; }'
rowm() { printf '%s\n%s\nsyscall(60, f());\n' "$MH" "$2" > "$T/$1.cyr"; }
MB='var b = Q { 1, 2 };'
MO='var a = Q { 10, 1 }; var c = Q { 20, 3 };'
MO3='var a = Q3 { 10, 1, 0 }; var c = Q3 { 20, 3, 0 };'
MQ="from 'Q.mk', which returns the struct 'Q' - declare 'x: Q' or bind a field"
MQ3="from 'Q.mk3', which returns the struct 'Q3' - declare 'x: Q3' or bind a field"
MQA="from 'Q_add', which returns the struct 'Q' - declare 'x: Q' or bind a field"
MQ3A="from 'Q3_add', which returns the struct 'Q3' - declare 'x: Q3' or bind a field"
rowm SA1 "fn f(): i64 { $MB var x: i64 = b.mk(); return x; }"
refused SA1 "cannot initialise 'x: i64' $MQ" "a 16 B method into \`: i64\` (exit 30 before: the first word)"
rowm SA2 "fn f(): i64 { $MB var x: u8 = b.mk(); return x; }"
refused SA2 "cannot initialise 'x: u8' $MQ" "a 16 B method into \`: u8\`"
rowm SA3 "fn f(): i64 { $MB var x: f64 = b.mk(); return 0; }"
refused SA3 "cannot initialise 'x: f64' $MQ" "a 16 B method into \`: f64\` (built before)"
rowm SA4 "fn f(): i64 { $MB var x: bool = b.mk(); if (x) { return 1; } return 0; }"
refused SA4 "cannot initialise 'x: bool' $MQ" "a 16 B method into \`: bool\` (D24's words, not \"not a bool\")"
rowm SA5 "fn f(): i64 { $MB var x: i64 = b.mk3(); return x; }"
refused SA5 "cannot initialise 'x: i64' $MQ3" "a 24 B method into \`: i64\`"
rowm SA6 "fn f(): i64 { $MB var x: u8 = b.mk3(); return x; }"
refused SA6 "cannot initialise 'x: u8' $MQ3" "a 24 B method into \`: u8\`"
rowm SA7 "fn f(): i64 { $MB var x: f64 = b.mk3(); return 0; }"
refused SA7 "cannot initialise 'x: f64' $MQ3" "a 24 B method into \`: f64\`"
rowm SA8 "fn f(): i64 { $MB var x: bool = b.mk3(); if (x) { return 1; } return 0; }"
refused SA8 "cannot initialise 'x: bool' $MQ3" "a 24 B method into \`: bool\`"
rowm SA9 "fn f(): i64 { $MO var x: i64 = a + c; return x; }"
refused SA9 "cannot initialise 'x: i64' $MQA" "a 16 B operator into \`: i64\`"
rowm SA10 "fn f(): i64 { $MO var x: u8 = a + c; return x; }"
refused SA10 "cannot initialise 'x: u8' $MQA" "a 16 B operator into \`: u8\`"
rowm SA11 "fn f(): i64 { $MO var x: f64 = a + c; return 0; }"
refused SA11 "cannot initialise 'x: f64' $MQA" "a 16 B operator into \`: f64\`"
rowm SA12 "fn f(): i64 { $MO var x: bool = a + c; if (x) { return 1; } return 0; }"
refused SA12 "cannot initialise 'x: bool' $MQA" "a 16 B operator into \`: bool\`"
rowm SA13 "fn f(): i64 { $MO3 var x: i64 = a + c; return x; }"
refused SA13 "cannot initialise 'x: i64' $MQ3A" "a 24 B operator into \`: i64\`"
rowm SA14 "fn f(): i64 { $MB var x: i64 = (b.mk()); return x; }"
refused SA14 "cannot initialise 'x: i64' $MQ" "a wrapped method, \`(b.mk())\`"
rowm SA15 "fn f(): i64 { $MO var x: bool = ((a + c)); if (x) { return 1; } return 0; }"
refused SA15 "cannot initialise 'x: bool' $MQA" "a wrapped operator into \`: bool\` (the bool check not run again)"
rowm SA16 "fn f(): i64 { $MB var x: i64 = b.mkg(33); return x; }"
refused SA16 "cannot initialise 'x: i64' from 'Q.mkg', which returns the struct 'Q' - declare 'x: Q' or bind a field" "a generic method, \`b.mkg(33)\`"
rowm SA17 "fn f(): i64 { $MB var g = |k| { var x: u8 = b.mk(); return x + k; }; return fncall1(g, 0); }"
refused SA17 "cannot initialise 'x: u8' $MQ" "a method in a closure"
rowm SA18 "fn f(): i64 { $MB var x: cstring = b.mk(); return 0; }"
refused SA18 "cannot initialise 'x: cstring' $MQ" "\`: cstring\` (the struct was received behind it before)"
rowm SA19 "fn f(): i64 { $MB var x: i64 = b.mk().mk(); return x; }"
refused SA19 "cannot initialise 'x: i64' $MQ" "a method chain ending in a 16 B result"
rowm SA20 "fn gb<T>(b: Q): i64 { var x: T = b.mk(); return 0; }
fn f(): i64 { $MB return gb<i32>(b); }"
refused SA20 "cannot initialise 'x: T' $MQ" "a generic instance whose T is i32"
rowm SA21 "fn f(): i64 { $MB var x: i64 = b.mk(); return x.b; }"
refused SA21 "cannot initialise 'x: i64' $MQ" "x keeps its \`i64\`: \`x.b\` the second, accurate error" 2
rowm SA24 "fn f(): i64 { $MO var x: i64 = (a + c); return x; }"
refused SA24 "cannot initialise 'x: i64' $MQA" "a wrapped 16 B operator into \`: i64\` (struct_operator_result_binding.tcyr pinned its first word through 6.7.12)"
rowm SA22 "fn f(): i64 { $MB var x: cstring = b.mk(); return x.b; }"
refused SA22 "cannot initialise 'x: cstring' $MQ" "\`: cstring\` keeps its annotation: \`x.b\` the second error (it read 4 before)" 2
rowm SA23 "fn f(): i64 { $MB var x: i64 = b.mkg(zz); return x; }"
refused SA23 "undefined variable 'zz'" "a line refused inside its initialiser is not refused again for its result"
# top level: the declaration zone (`_gvi_expr`) and after a first statement (PARSE_VAR)
MZ='var B = Q { 1, 2 };
var A = Q { 10, 1 };
var C = Q { 20, 3 };'
rowz() {
    if [ "$2" = zone ]; then printf '%s\n%s\n%s\nsyscall(60, 0);\n' "$MH" "$MZ" "$3" > "$T/$1.cyr"
    else printf '%s\n%s\nvar Z = 0;\nZ = 1;\n%s\nsyscall(60, 0);\n' "$MH" "$MZ" "$3" > "$T/$1.cyr"; fi
}
MGQ="from 'Q.mk', which returns the struct 'Q' - declare 'G: Q' or bind a field"
MGA="from 'Q_add', which returns the struct 'Q' - declare 'G: Q' or bind a field"
rowz SAT1 zone 'var G: i64 = B.mk();'
refused SAT1 "cannot initialise 'G: i64' $MGQ" "top level, the declaration zone: \`var G: i64 = B.mk();\` (exit 30 before)"
rowz SAT2 after 'var G: i64 = B.mk();'
refused SAT2 "cannot initialise 'G: i64' $MGQ" "top level, after a first statement: a method"
rowz SAT3 zone 'var G: u8 = A + C;'
refused SAT3 "cannot initialise 'G: u8' $MGA" "top level, the declaration zone: an operator into \`: u8\`"
rowz SAT4 after 'var G: f64 = (A + C);'
refused SAT4 "cannot initialise 'G: f64' $MGA" "top level, after a first statement: a wrapped operator into \`: f64\`"
rowz SAT5 zone 'var G: bool = (B.mk());'
refused SAT5 "cannot initialise 'G: bool' $MGQ" "top level, the declaration zone: a wrapped method into \`: bool\` (once)"
rowz SAT6 after 'var G: cstring = B.mkg(7);'
refused SAT6 "cannot initialise 'G: cstring' from 'Q.mkg', which returns the struct 'Q' - declare 'G: Q' or bind a field" "top level, after a first statement: a generic method into \`: cstring\`"
rowz SATK1 after 'var G: i64 = B.mk3();'
refused SATK1 "returns a struct by value, and a struct result needs storage in a fn's frame" "control: a 24 B method at top level keeps its one no-frame refusal"
printf '%s\n%s\nvar P = Q1 { 33 };\nvar G1: i64 = B.mk1();\nvar G2 = B.mk();\nvar Z = 0;\nZ = 1;\nalloc_init();\nvar G3: i64 = B.ms();\nvar G4: i64 = P + P;\nsyscall(60, G1 + str_len(G3) - 36 + G4 - 66 + 34 + G2 - 30);\n' "$MH" "$MZ" > "$T/SATK2.cyr"
runs SATK2 34 "control: at top level an 8 B method / operator and a \`Str\` method into \`: i64\`, an untyped method, keep the word"
# controls in a fn
rowm SAK1 "fn f(): i64 { $MB var x: i64 = b.mk1(); var a1 = Q1 { 30 }; var y: u8 = a1 + a1; return x + y - 59; }"
runs SAK1 34 "control: an 8 B method and operator result into \`: i64\` / \`: u8\` keep their one word"
rowm SAK2 "fn f(): i64 { alloc_init(); $MB var s: i64 = b.ms(); return str_len(s) + 31; }"
runs SAK2 34 "control: a \`Str\`-returning method into \`: i64\` keeps the handle"
rowm SAK3 "fn f(): i64 { $MB $MO var x: Q = b.mk(); var y: Q = (a + c); var z: Q3 = b.mk3(); return dqm(x) + dqm(y) + z.c - 41; }"
runs SAK3 34 "control: a struct annotation still receives the method / operator result"
rowm SAK4 "fn f(): i64 { $MB $MO var x = b.mk(); var y = (a + c); var n: i64 = b.mk().b; return dqm(x) + dqm(y) + n - 38; }"
runs SAK4 34 "control: an untyped receive is the struct; a field of the result binds the field"
rowm SAK5 "fn gb<T>(b: Q): i64 { var x: T = b.mk(); return dqm(x); }
fn f(): i64 { $MB return gb<Q>(b); }"
runs SAK5 34 "control: \`var x: T = b.mk();\` in \`gb<Q>\` is the struct (the base parse is not judged)"
rowm SAK6 "fn f(): i64 { $MB var x: bool = b.mk1(); return 0; }"
refused SAK6 "cannot initialize bool 'x' with a value that is not a bool" "control: an 8 B method into \`: bool\` keeps the bool check"

# --- D14 (6.7.13; the user, 2026-10-15): a by-value struct over 8 B into a POINTER annotation, refused by name ---
# (issues/archived/2026-10-14-pointer-annotated-local-from-byvalue-struct-call.md) The two filed repros, verbatim: they compiled
# under "assigning non-pointer to typed pointer" and exited 139 on x86_64 / aarch64, 14 on cx, 5 on PE (`*P2`), and 77
# on all four (`*i64`, the struct's first word held as an address); now each is refused once, with no warning.
cat > "$T/PT0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
fn main(): i64 {
    var x: *P2 = mkp();
    return x.b;
}
var rc = main();
syscall(60, rc);
EOF
refused PT0 "cannot initialise 'x: *P2' from 'mkp', which returns the struct 'P2' - declare 'x: P2' and take \`&x\`" \
    "D14's repro 1 verbatim: \`var x: *P2 = mkp();\` (warning only, SIGSEGV at x.b before)"
cat > "$T/PT00.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
fn main(): i64 {
    var x: *i64 = mkp();
    return x;
}
var rc = main();
syscall(60, rc);
EOF
refused PT00 "cannot initialise 'x: *i64' from 'mkp', which returns the struct 'P2' - declare 'x: P2' and take \`&x\`" \
    "D14's repro 2 verbatim: \`var x: *i64 = mkp();\` (it held 333 as an address)"
PM16="from 'mkp', which returns the struct 'P2' - declare 'x: P2' and take \`&x\`"
PM24="from 'mk3', which returns the struct 'P3' - declare 'x: P3' and take \`&x\`"
row PT1 'fn f(): i64 { var x: *u8 = mkp(); return 0; }'
refused PT1 "cannot initialise 'x: *u8' $PM16" "16 B into \`*u8\`"
row PT2 'fn f(): i64 { var x: *P3 = mk3(); return x.c; }'
refused PT2 "cannot initialise 'x: *P3' $PM24" "24 B into \`*P3\` (SIGSEGV before)"
row PT3 'fn f(): i64 { var x: *i64 = mk3(); return 0; }'
refused PT3 "cannot initialise 'x: *i64' $PM24" "24 B into \`*i64\`"
row PT4 'fn f(): i64 { var x: *u8 = mk3(); return 0; }'
refused PT4 "cannot initialise 'x: *u8' $PM24" "24 B into \`*u8\`"
row PT5 'fn f(): i64 { var x: *P2 = (mkp()); return x.b; }'
refused PT5 "cannot initialise 'x: *P2' $PM16" "a wrapped call, \`(mkp())\`"
row PT6 'fn f(): i64 { var x: *i64 = ((mk3())); return 0; }'
refused PT6 "cannot initialise 'x: *i64' $PM24" "a wrapped call, \`((mk3()))\`"
row PT7 'fn f(): i64 { var x: *i64 = mkg<i64>(3); return 0; }'
refused PT7 "cannot initialise 'x: *i64' from 'mkg', which returns the struct 'Bx' - declare 'x: Bx' and take \`&x\`" "a generic callee, \`mkg<i64>(3)\`"
row PT8 'fn f(): i64 { var g = |k| { var x: *P2 = mkp(); return k; }; return fncall1(g, 0); }'
refused PT8 "cannot initialise 'x: *P2' $PM16" "in a closure"
row PT9 'fn gp<T>(v: T): i64 { var x: *T = mkp(); return 0; }
fn f(): i64 { return gp<i32>(3); }'
refused PT9 "cannot initialise 'x: *T' $PM16" "in a generic fn (\`*T\`, every instance)"
rowf PT10 'fn f(): i64 { var x: *P2 = fncall0(&mkp); return x.b; }'
refused PT10 "cannot initialise 'x: *P2' $PM16" "\`fncall0(&mkp)\`"
if grep -q '^error:<source>:[0-9]*:37: cannot initialise' "$T/PT10.x86_64.err"; then
    ok "PT10 the refusal sits at the callee's name (\`mkp\`, column 37), as D28's does"
else bad "PT10 the refusal is not at the callee's name: $(grep '^error' "$T/PT10.x86_64.err" | head -1)"; fi
rowf PT11 'fn f(): i64 { var x: *i64 = fncall0((&mkp)); return 0; }'
refused PT11 "cannot initialise 'x: *i64' $PM16" "\`fncall0((&mkp))\`, the callee in parentheses"
rowf PT12 'fn f(): i64 { var x: *P3 = callptr(&mk3); return x.c; }'
refused PT12 "cannot initialise 'x: *P3' $PM24" "\`callptr(&mk3)\` (24 B)"
rowf PT13 'fn f(): i64 { var x: *u8 = (fncall0(&mkp)); return 0; }'
refused PT13 "cannot initialise 'x: *u8' $PM16" "a wrapped \`(fncall0(&mkp))\`"
PMQ="from 'Q.mk', which returns the struct 'Q' - declare 'x: Q' and take \`&x\`"
PMA="from 'Q_add', which returns the struct 'Q' - declare 'x: Q' and take \`&x\`"
rowm PT14 "fn f(): i64 { $MB var x: *Q = b.mk(); return x.b; }"
refused PT14 "cannot initialise 'x: *Q' $PMQ" "a 16 B method into \`*Q\` (SIGSEGV before)"
rowm PT15 "fn f(): i64 { $MB var x: *i64 = b.mk3(); return 0; }"
refused PT15 "cannot initialise 'x: *i64' from 'Q.mk3', which returns the struct 'Q3' - declare 'x: Q3' and take \`&x\`" "a 24 B method into \`*i64\`"
rowm PT16 "fn f(): i64 { $MO var x: *Q = a + c; return x.b; }"
refused PT16 "cannot initialise 'x: *Q' $PMA" "a 16 B operator into \`*Q\`"
rowm PT17 "fn f(): i64 { $MO var x: *u8 = ((a + c)); return 0; }"
refused PT17 "cannot initialise 'x: *u8' $PMA" "a wrapped operator into \`*u8\`"
rowm PT18 "fn f(): i64 { $MB var x: *Q = b.mkg(5); return 0; }"
refused PT18 "cannot initialise 'x: *Q' from 'Q.mkg', which returns the struct 'Q' - declare 'x: Q' and take \`&x\`" "a generic method into \`*Q\`"
# controls: 8 B or less keeps its word and the typed-pointer warning (D14); an assignment through a *P2 local is unchanged
# warned <name> <want exit> <what>: builds on every leg WITH the typed-pointer warning, and exits <want>
warned() {
    rows=$((rows + 1))
    for leg in $(legs); do
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        if grep -qF "assigning non-pointer to typed pointer" "$T/$1.$leg.err"; then ok "$1 $3 ($leg): the warning kept"
        else bad "$1 $3 ($leg): no typed-pointer warning"; fi
    done
    runs "$1" "$2" "$3"
    rows=$((rows - 1))
}
row PTK1 'fn f(): i64 { var x: *P1 = mk1(); return x; }'
warned PTK1 33 "control: an 8 B struct into \`*P1\` is its one word, with the typed-pointer warning"
rowm PTK2 "fn f(): i64 { $MB var x: *Q1 = b.mk1(); return x; }"
warned PTK2 33 "control: an 8 B method into \`*Q1\` is its one word, with the warning"
row PTK3 'fn f(): i64 { var p: P2; var x: *P2 = &p; x = mkp(); return x.b + 30; }'
runs PTK3 34 "control: \`x = mkp();\` into a \`*P2\` local copies through it (the issue's \"right (3)\")"
row PTK4 'fn f(): i64 { var x: P2 = mkp(); var y: *P2 = &x; var z: P3 = mk3(); var w: *P3 = &z; return y.a + y.b + w.c - 7; }'
runs PTK4 34 "control: the remedy — \`var x: P2 = mkp();\` and take \`&x\`"
cat > "$T/PTK5.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
fn mks(): Str { return str_from("abc"); }
fn f(): i64 { alloc_init(); var s: *Str = mks(); return str_len(s) + 31; }
syscall(60, f());
EOF
runs PTK5 34 "control: a \`Str\` result into \`*Str\` keeps its handle (a \`Str\` is one word)"

# --- D28 (6.7.14; the user, 2026-10-16: D14 at top level, every `*T` and every path) ---
# (issues/archived/2026-10-16-top-level-pointer-annotation-from-byvalue-struct-call.md) The three filed repros, verbatim: after the
# first statement `var X: *P2 = mkp();` compiled under the typed-pointer warning and exited 139 / 139 / 14 / 5; in the
# declaration zone the free call was refused with D24's scalar remedy ("or bind a field") and the method compiled
# (warned) and faulted. Now each is refused once in D14's words, with no warning.
REPT=docs/development/issues/repros/2026-10-16-top-level-pointer-annotation-from-byvalue-struct-call
[ -f "$REPT.cyr" ] && [ -f "$REPT-zone.cyr" ] && [ -f "$REPT-zone-method.cyr" ] || { echo "FAIL: $G: $REPT*.cyr missing"; exit 1; }
cp "$REPT.cyr" "$T/PTT0.cyr"
refused PTT0 "cannot initialise 'X: *P2' from 'mkp', which returns the struct 'P2' - declare 'X: P2' and take \`&X\`" \
    "D28's repro 1 verbatim: after the first statement (warning + 139 before)"
cp "$REPT-zone.cyr" "$T/PTT0z.cyr"
refused PTT0z "cannot initialise 'X: *P2' from 'mkp', which returns the struct 'P2' - declare 'X: P2' and take \`&X\`" \
    "D28's repro 2 verbatim: the declaration zone (D24's \"or bind a field\" before)"
cp "$REPT-zone-method.cyr" "$T/PTT0m.cyr"
refused PTT0m "cannot initialise 'X: *Q' from 'Q.mk', which returns the struct 'Q' - declare 'X: Q' and take \`&X\`" \
    "D28's repro 3 verbatim: a method in the declaration zone (warning + 139 before)"
PGT="from 'mk2', which returns the struct 'P2' - declare 'G: P2' and take \`&G\`"
PGQ="from 'Q.mk', which returns the struct 'Q' - declare 'G: Q' and take \`&G\`"
PGA="from 'Q_add', which returns the struct 'Q' - declare 'G: Q' and take \`&G\`"
for zw in zone after; do
    rowt "PTT1$zw" $zw 'var G: *P2 = mk2(5);'
    refused "PTT1$zw" "cannot initialise 'G: *P2' $PGT" "top level ($zw): a 16 B free call into \`*P2\`"
    rowt "PTT2$zw" $zw 'var G: *i64 = (mk2(5));'
    refused "PTT2$zw" "cannot initialise 'G: *i64' $PGT" "top level ($zw): wrapped, into \`*i64\`"
    rowt "PTT3$zw" $zw 'var G: *u8 = fncall1(&mk2, 5);'
    refused "PTT3$zw" "cannot initialise 'G: *u8' $PGT" "top level ($zw): \`fncall1(&mk2, 5)\` into \`*u8\`"
    rowt "PTT4$zw" $zw 'var G: *P2 = (callptr((&mk2), 5));'
    refused "PTT4$zw" "cannot initialise 'G: *P2' $PGT" "top level ($zw): a wrapped \`callptr((&mk2), 5)\`"
    rowt "PTT5$zw" $zw 'var G: **P2 = mk2(5);'
    refused "PTT5$zw" "cannot initialise 'G: **P2' $PGT" "top level ($zw): \`**P2\`"
    rowt "PTT6$zw" $zw 'var G: *i64 = mkg<i64>(5);'
    refused "PTT6$zw" "cannot initialise 'G: *i64' from 'mkg', which returns the struct 'P2' - declare 'G: P2' and take \`&G\`" "top level ($zw): a generic callee"
    rowz "PTT7$zw" $zw 'var G: *Q = B.mk();'
    refused "PTT7$zw" "cannot initialise 'G: *Q' $PGQ" "top level ($zw): a 16 B method into \`*Q\`"
    rowz "PTT8$zw" $zw 'var G: *i64 = (B.mk());'
    refused "PTT8$zw" "cannot initialise 'G: *i64' $PGQ" "top level ($zw): a wrapped method into \`*i64\`"
    rowz "PTT9$zw" $zw 'var G: *u8 = A + C;'
    refused "PTT9$zw" "cannot initialise 'G: *u8' $PGA" "top level ($zw): an operator into \`*u8\`"
    rowz "PTT10$zw" $zw 'var G: *Q = B.mkg(7);'
    refused "PTT10$zw" "cannot initialise 'G: *Q' from 'Q.mkg', which returns the struct 'Q' - declare 'G: Q' and take \`&G\`" "top level ($zw): a generic method"
    rowt "PTT11$zw" $zw 'var G: *P3 = mk3(5);'
    refused "PTT11$zw" "returns a struct by value, and a struct result needs storage in a fn's frame" "top level ($zw): 24 B keeps its one no-frame refusal (no D14, no warning)"
    rowz "PTT12$zw" $zw 'var G: *i64 = B.mk3();'
    refused "PTT12$zw" "returns a struct by value, and a struct result needs storage in a fn's frame" "top level ($zw): a 24 B method, the one no-frame refusal"
    rowt "PTT13$zw" $zw 'var G: *P3 = callptr(&mk3, 5);'
    refused "PTT13$zw" "returns a struct by value, and a struct result needs storage in a fn's frame" "top level ($zw): a 24 B \`callptr(&mk3, 5)\`, the one no-frame refusal"
    rowt "PTT14$zw" $zw 'var E = nope;
var G: *P2 = mk2(5);'
    refused "PTT14$zw" "undefined variable 'nope'" "top level ($zw): after an earlier error the refusal still says no warning" 2
    rowt "PTTK1$zw" $zw 'var G: *P1 = mk1(5);'
    warned "PTTK1$zw" 0 "control, top level ($zw): an 8 B struct into \`*P1\` keeps its word and the warning"
    rowz "PTTK2$zw" $zw 'var G: *Q1 = B.mk1();'
    warned "PTTK2$zw" 0 "control, top level ($zw): an 8 B method into \`*Q1\` keeps its word and the warning"
done
if grep -q '^error:<source>:[0-9]*:23: cannot initialise' "$T/PTT3after.x86_64.err" && grep -q '^error:<source>:[0-9]*:23: cannot initialise' "$T/PTT3zone.x86_64.err"; then
    ok "PTT3 the top-level refusal sits at the callee's name (\`mk2\`, column 23), as in a fn (PT10)"
else bad "PTT3 the top-level refusal is not at the callee's name: $(grep '^error' "$T/PTT3after.x86_64.err" "$T/PTT3zone.x86_64.err" | head -2)"; fi
if grep -qF "cannot initialise 'G: *P2' $PGT" "$T/PTT14after.x86_64.err" && grep -qF "cannot initialise 'G: *P2' $PGT" "$T/PTT14zone.x86_64.err"; then
    ok "PTT14 the D14 refusal is the second error, after the earlier one"
else bad "PTT14 the D14 refusal is missing after the earlier error"; fi
printf '%s\nalloc_init();\nvar S: *Str = mks();\nvar T: *Str = (fncall0(&mks));\nsyscall(60, str_len(S) + str_len(T) + 24);\n' "$TH" > "$T/PTTK3.cyr"
warned PTTK3 34 "control: after the first statement a \`Str\` into \`*Str\` keeps its handle and the warning, as in a fn"

# --- (a): wrapped calls, run ---
row A1 'fn f(): i64 { var x = ((mkp())); var y = (mk3()); var z = ((mk3())); return dq(x) + dq3(y) + dq3(z) - 68; }'
runs A1 34 "\`((mkp()))\`, \`(mk3())\`, \`((mk3()))\` into by-value parameters"
cp tests/tcyr/crossos/struct_receive_paren_call.tcyr "$T/A2.cyr"
runs A2 0 "tests/tcyr/crossos/struct_receive_paren_call.tcyr (fn scope, a closure, a generic; 16 B and 24 B; 6.7.13: 8 B)"
# 6.7.13 (issues/archived/2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md): the issue's two repros,
# verbatim — the 8 B free call (`x.a` refused before: "no struct type in scope for 'x'") and the 16 B method
# (139 / 139 / 1 / 5 through 6.7.10; D42 fixed it in 6.7.11, pinned here).
cat > "$T/A3.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P1 { a; }
fn mk1(): P1 { var p: P1; p.a = 33; return p; }
fn main(): i64 { var x = (mk1()); return x.a; }
syscall(60, main());
EOF
runs A3 33 "the 8 B repro verbatim: \`var x = (mk1()); return x.a;\` (refused before)"
cat > "$T/A4.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 3; q.b = 4; return q; } }
fn dq(q: Q): i64 { return q.a * 10 + q.b; }
fn main(): i64 { var b = Q { 1, 2 }; var x = (b.mk()); return dq(x); }
syscall(60, main());
EOF
runs A4 34 "the 16 B method repro verbatim: \`var x = (b.mk()); return dq(x);\` (D42)"

# --- controls ---
row K1 'fn f(): i64 { var x: i64 = mk1(); return x + 1; }'
runs K1 34 "control: an 8 B struct into \`: i64\` is its one word"
cat > "$T/K2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
fn mks(): Str { return str_from("abc"); }
fn f(): i64 { alloc_init(); var n: i64 = mks(); return str_len(n) + 31; }
syscall(60, f());
EOF
runs K2 34 "control: a \`Str\` into \`: i64\` is its handle"
row K3 'fn f(): i64 { var x: P2 = mkp(); var y: P2 = (mkp()); var z: P3 = ((mk3())); return dq(x) + dq(y) + dq3(z) - 68; }'
runs K3 34 "control: a struct annotation, plain and wrapped"
row K4 'fn f(): i64 { var x: i64 = mkp().a; var y: u8 = mk3().b; return x + y; }'
runs K4 34 "control: the hint — bind a field"
row K5 'fn gb<T>(v: T): i64 { var x: T = mkp(); return dq(x); }
fn f(): i64 { return gb<P2>(mkp()); }'
runs K5 34 "control: \`var x: T = mkp();\` in \`gb<P2>\` (the base parse is not judged)"
row K6 'fn f(): i64 { var x = mkp(); var y = mk3(); return x.a + x.b + y.c - 7; }'
runs K6 34 "control: unannotated, unwrapped"
row K7 'fn f(): i64 { var x = (31 + 3); var y = ((mk1())); return x + y.a - 33; }'
runs K7 34 "control: \`var x = (31 + 3);\` stays an untyped word beside a wrapped 8 B call (6.7.13)"

# --- a dyn result keeps the 6.7.8 refusals ---
DH='include "lib/alloc.cyr"
trait Show { fn show(self): i64; }
fn pass(o: dyn Show): dyn Show { return o; }'
RV='used as a value - call one of its methods, or copy it whole into a dyn'
printf '%s\nfn f(o: dyn Show): i64 { var x = (pass(o)); return 0; }\nsyscall(60, 0);\n' "$DH" > "$T/D1.cyr"
refused D1 "a dyn Show result $RV" "a dyn: \`var x = (pass(o));\` keeps V4d"
printf '%s\nfn f(o: dyn Show): i64 { var y: i64 = pass(o); return 0; }\nsyscall(60, 0);\n' "$DH" > "$T/D2.cyr"
refused D2 "a dyn Show result $RV" "a dyn: \`var y: i64 = pass(o);\` keeps V4n"
printf '%s\nfn f(o: dyn Show): i64 { var y: i64 = pass(o); return y.show(); }\nsyscall(60, 0);\n' "$DH" > "$T/D3.cyr"
refused D3 "a dyn Show result $RV" "a dyn: after V4n, y is still the dyn (\`y.show()\` no second error)"

# --- 6.7.14: a GENERIC call declared `: *T` into an annotated local is a handle (the 6.7.10 handle line) ---
# issues/archived/2026-10-14-generic-pointer-call-into-annotated-local-drops-struct-type.md: the B-explicit reset dropped the
# annotation of every generic receive the struct check did not keep — a `: *T` (GFRS -8) or scalar return included —
# so `var h: S = gpg<S>();` declared an untyped word and `h.v = 6` was refused "no struct type in scope for 'h'".
# `_gen_decl_reset` resets only for a generic returning a struct BY VALUE.
GHS='struct S { v; w; }
var GS = S { 5, 8 };'
gh() { printf '%s\n%s\nsyscall(60, f());\n' "$GHS" "$2" > "$T/$1.cyr"; }
# the filed repro's loop, its three programs verbatim
gh GH0a 'fn gp(): *S { return &GS; }
fn f(): i64 { var h: S = gp(); h.v = 6; return GS.v * 10 + h.w; }'
runs GH0a 68 "the filed repro, row 1: the non-generic \`fn gp(): *S\` (a handle)"
gh GH0b 'fn gpg<T>(): *T { return &GS; }
fn f(): i64 { var h: S = gpg<S>(); h.v = 6; return GS.v * 10 + h.w; }'
runs GH0b 68 "the filed repro, row 2: \`var h: S = gpg<S>();\` is a handle (refused before: no struct type in scope for 'h')"
gh GH0c 'fn gpg<T>(): *T { return &GS; }
fn f(): i64 { var h: *S = gpg<S>(); return h.w; }'
runs GH0c 8 "the filed repro, row 3: control \`var h: *S = gpg<S>();\`"
gh GH1 'fn gpg<T>(x: T): *T { return &GS; }
fn f(): i64 { var s = S { 1, 2 }; var h: S = gpg(s); h.v = 6; return GS.v * 10 + h.w; }'
runs GH1 68 "inferred \`var h: S = gpg(s);\` (\`x: T\`, a struct argument)"
gh GH2 'fn gpg<T>(p: *T): *T { return &GS; }
fn f(): i64 { var s = S { 1, 2 }; var h: S = gpg(&s); h.v = 6; return GS.v * 10 + h.w; }'
runs GH2 68 "inferred \`var h: S = gpg(&s);\` (\`p: *T\`)"
gh GH3 'fn gpg<T>(): *T { return &GS; }
fn f(): i64 { var h: S = gpg<S>(); var c: S = h; c.v = 7; return GS.v * 10 + c.w; }'
runs GH3 78 "\`var c: S = h;\` binds a second handle to the struct h points at"
gh GH4 'fn gpg<T>(): *T { return &GS; }
fn take(s: S): i64 { return s.v * 10 + s.w; }
fn f(): i64 { var h: S = gpg<S>(); return take(h); }'
runs GH4 58 "\`take(h)\` into a by-value \`s: S\` passes the struct h points at"
gh GH5 'fn gpg<T>(): *T { return &GS; }
fn takep(p: *S): i64 { p.v = 9; return p.w; }
fn f(): i64 { var h: S = gpg<S>(); return takep(h) * 10 + GS.v; }'
runs GH5 89 "\`takep(h)\` into a \`p: *S\` passes the pointer"
printf 'struct S3 { v; w; u; }\nvar GS = S3 { 5, 8, 1 };\nfn gpg<T>(): *T { return &GS; }\nfn f(): i64 { var h: S3 = gpg<S3>(); h.u = 6; return GS.u * 10 + h.w; }\nsyscall(60, f());\n' > "$T/GH6.cyr"
runs GH6 68 "24 B: \`var h: S3 = gpg<S3>();\`"
printf 'struct S1 { v; }\nvar GS = S1 { 5 };\nfn gpg<T>(): *T { return &GS; }\nfn f(): i64 { var h: S1 = gpg<S1>(); h.v = 6; return GS.v * 10 + h.v; }\nsyscall(60, f());\n' > "$T/GH7.cyr"
runs GH7 66 "8 B: \`var h: S1 = gpg<S1>();\`"
gh GH8 'fn gi<T>(): i64 { return &GS; }
fn f(): i64 { var h: S = gi<S>(); h.v = 6; return GS.v * 10 + h.w; }'
runs GH8 68 "a generic returning an untyped value is a handle, as the non-generic \`fn gi(): i64\` is"
gh GH9 'fn gpg<T>(): *T { return &GS; }
fn f(): i64 { var h: S = gpg<Zork>(); h.v = 6; return GS.v * 10 + h.w; }'
refused GH9 "unknown type 'Zork' as a type argument" "\`gpg<Zork>()\` is refused once (h keeps S: no 'no struct type in scope' after it)"
# controls: a generic returning a struct BY VALUE keeps today's receive (the reset re-derives it from the callee)
printf 'struct Box<T> { v: T; n; }\nstruct Pt { x; y; }\nfn mk<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 3; return b; }\nfn f(): i64 { var p = Pt { 4, 5 }; var r: Box<Pt> = mk<Pt>(p); var q: Box<Pt> = mk(p); return r.v.x * 10 + q.v.y + r.n * 100; }\nsyscall(60, f() - 300);\n' > "$T/GHK1.cyr"
runs GHK1 45 "control: \`var r: Box<Pt> = mk<Pt>(p);\` / \`= mk(p);\` (24 B by value) receive"
printf 'struct S { v; w; }\nfn mks<T>(x: T): S { var s = S { x, 7 }; return s; }\nfn f(): i64 { var r: S = mks<i64>(4); var q: S = mks(3); return r.v * 10 + q.w + q.v; }\nsyscall(60, f());\n' > "$T/GHK2.cyr"
runs GHK2 50 "control: a generic returning a 16 B struct by value"
printf 'struct S3 { v; w; u; }\nfn mks<T>(x: T): S3 { var s = S3 { x, 7, 1 }; return s; }\nfn f(): i64 { var r: S3 = mks<i64>(4); var q: S3 = mks(3); return r.v * 10 + q.w + q.v + r.u; }\nsyscall(60, f());\n' > "$T/GHK3.cyr"
runs GHK3 51 "control: a generic returning a 24 B struct by value"
printf 'struct Box<T> { v: T; n; }\nstruct Pt { x; y; }\nfn mk<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 3; return b; }\nfn f(): i64 { var p = Pt { 4, 5 }; var r: Box<Pt> = mk(p.x); return r.n; }\nsyscall(60, f());\n' > "$T/GHK4.cyr"
refused GHK4 "fn return struct-id differs from declared var type" "control: the 6.6.11 mismatch \`var r: Box<Pt> = mk(p.x);\` (Box<i64>) is still refused"
# a generic returning its own `: T` whose T binds no struct is a handle in a struct-annotated local (6.7.15's D13 (a)):
# the field use compiles (it was refused "no struct type in scope for 'a'" through 6.7.14), the handle holds the word
GHT='struct P3 { x; y; z; }
struct W { n; v: P3; }
fn gid<T>(x: T): T { return x; }'
ght() { printf '%s\n%s\nsyscall(60, f());\n' "$GHT" "$2" > "$T/$1.cyr"; }
ght GHT1 'var GQ = P3 { 0, 0, 0 };
fn f(): i64 { GQ.z = 9; var a: P3 = gid(&GQ); return a.z; }'
runs GHT1 9 "\`var a: P3 = gid(&GQ);\` (\`: T\` at i64): a handle, a.z reads GQ.z (6.7.15's D13 (a); refused before)"
ght GHT2 'fn f(): i64 { var a: P3 = gid<i32>(5); var k: i64 = a; if (k == 0) { return a.z; } return k; }'
runs GHT2 5 "\`var a: P3 = gid<i32>(5);\` (an explicit scalar instance): a handle holding 5, its field use compiles"
ght GHT3 'fn f(): i64 { var h: f64 = 1.5; var a: P3 = gid(h); var k: i64 = a; if (k == 0) { return a.z; } return k >> 56; }'
runs GHT3 63 "\`var a: P3 = gid(h);\` (\`h: f64\`): a handle holding its bits, its field use compiles"
ght GHT4 'fn f(): i64 { var w: W; w.v.x = 7; var a: P3 = gid(w.v); var k: i64 = a; if (k == 0) { return a.z; } return k; }'
runs GHT4 7 "\`var a: P3 = gid(w.v);\` (i64 by the whole-argument rule): a handle holding w.v's word, its field use compiles"
ght GHT5 'fn f(): i64 { var p = P3 { 1, 2, 3 }; var a: P3 = gid(p); return a.z; }'
runs GHT5 3 "control: \`var a: P3 = gid(p);\` (\`p: P3\`) receives the struct"


# 6.7.14 — A WRAPPED `Str` CALL IS A Str (issues/archived/2026-10-16-paren-wrapped-str-call-untyped-receive-is-a-word.md). `var s =
# (mks());` with `fn mks(): Str` bound an untyped word, where `var t = mks();` is a Str (v5.10.4): `println(s)` took the
# cstring overload and printed the header's bytes (the filed repro: `P`, a backquote line, then `abcde`), and `s.len()`
# was "no struct type in scope for 's'". `_var_rhs_wsid` types the wrapped Str as the unwrapped peek does. WS0 the filed
# repro verbatim; WS1 its `s.len()` form; WS2 `((mks()))`; tcyr ws* through A2.
#   N34 `_var_rhs_wsid` without its Str test (2026-10-17) -> RED 16: WS0 (printed garbage) WS1 WS2 A2 x4 legs (refused:
#                                                           no struct type in scope for 's'); the rest green
REPS=docs/development/issues/repros/2026-10-16-paren-wrapped-str-call-untyped-receive-is-a-word.cyr
[ -f "$REPS" ] || { echo "FAIL: $G: $REPS is missing"; exit 1; }
cp "$REPS" "$T/WS0.cyr"
prints WS0 "abcde|abcde|" "the filed repro verbatim: \`var s = (mks()); println(s);\` prints abcde, as \`var t = mks();\` does"
sed 's/return 0; }$/return s.len() * 10 + t.len(); }/' "$REPS" > "$T/WS1.cyr"
runs WS1 55 "the filed repro's \`return s.len() * 10 + t.len();\` form (refused before: no struct type in scope for 's')"
sed 's/var s = (mks());/var s = ((mks()));/' "$T/WS1.cyr" > "$T/WS2.cyr"
runs WS2 55 "\`var s = ((mks()));\`, two wraps"

# 6.7.14 — A WRAPPED `: f64` CALL BEFORE AN OPERATOR (issues/archived/2026-10-16-paren-wrapped-f64-call-leading-operator-untyped.md).
# `var a = (f()) * 2.0;` bound an untyped word holding the product's bits, where `var a = f() * 2.0;` and (6.7.13) `var a =
# (f());` bind an f64: the filed repro's `a + 1.5` added integers under "integer arithmetic with an f64 right operand",
# exit 0 on all four. `_var_rhs_wsid` gives the wrapped leading call's -9 whatever follows the wrap, and `_var_rhs_post`
# keeps it only while the whole initialiser is an f64 (a comparison, `&&`, D12's `& | ^ % << >>` stay integers: tcyr
# wf64_*, through A2). WF0 the filed repro verbatim: exit 6, and (a second row) no warning.
#   N35 `_var_rhs_wsid` with the `;` test before the f64 return (2026-10-17) -> RED 12: WF0 x2 (exit 0; the warning)
#                                                           A2 (wf64_op wf64_2) x4 legs; the rest green
REPF64=docs/development/issues/repros/2026-10-16-paren-wrapped-f64-call-leading-operator-untyped.cyr
[ -f "$REPF64" ] || { echo "FAIL: $G: $REPF64 is missing"; exit 1; }
cp "$REPF64" "$T/WF0.cyr"
runs WF0 6 "the filed repro verbatim: \`var a = (f()) * 2.0;\` is an f64 (exit 0 before)"
quiet WF0 "the filed repro: no \"integer arithmetic with an f64 right operand\""

# 6.7.14 — D29 (a) / D30 (a) (the user, 2026-10-16): AN UNTYPED TOP-LEVEL `var x = mk1(30);` BINDS THE STRUCT
# (issues/archived/2026-10-16-top-level-untyped-struct-call-receive-infers-nothing.md). The initialiser one whole free call, wrapped
# or not, in the declaration zone or after the first statement: of 8 B or less x is the struct (`x.a` was "no struct type
# in scope for 'x'"); of 9-16 B it is refused as `var x: P2 = mk2(30);` is ("needs storage in a fn's frame"; it held the
# first word silently: the filed repro exited 33); over 16 B the call's own refusal is the one error (the "no struct
# type in scope" after it is gone). `_gu_late` (PARSE_VAR's global arm), `_gu_sweep` (the zone, the end of pass 1) and the
# zone replay's `_gu_refuse`. TU0 TU0b the filed repros verbatim; TU1-TU7 x {zone, after a first statement}: 8 B plain /
# wrapped / twice wrapped, 16 B plain / wrapped (`G.b` used), 24 B plain / wrapped (`G.c` used); TU8 `G + G` dispatches
# `P1_add`, TU9 `G + 1` with no `P1_add` is refused; TU10 a refusal inside the initialiser is the one error; TU11 the
# callee declared below; TU12 a fn body reads `G.a` and passes G by value; TU13 `var Y: P1 = G;`; TUK1 a `Str` stays the
# handle it was; TUK2 a 16 B method keeps the word (SATK2).
#   N43 the tree before it (63aa1cb8)                    -> RED 102: TU0 TU0b TU1-TU8 TU11-TU13 x {zone, after} x4 legs
#                                                           (refused / built / two errors), TU9 x2 (x86_64), A2 x4 (the
#                                                           tcyr's TU* / TA* rows); TU10 TUK1 green
#   N44 `_gu_sweep` returns 0 (the zone)                 -> RED 53: TU0 TU1zone-TU8zone TU11zone-TU13zone x4, TU9zone, A2
#                                                           x4 (TU0b green: its replay refusal stands, nothing reads `x.a`)
#   N45 `_gu_late` keeping `pscale` (after a statement)  -> RED 49: TU1after-TU8after TU11after-TU13after x4, TU9after, A2 x4
#   N46 `_gvi_scalar` without `_gu_refuse`               -> RED 12: TU0b TU4zone TU5zone x4 (built)
#   N47 `_gu_refuse` without its `_scv_err` test         -> RED 8: TU10zone TU10after x4 (two errors)
REPU=docs/development/issues/repros/2026-10-16-top-level-untyped-struct-call-receive-infers-nothing
[ -f "$REPU.cyr" ] && [ -f "$REPU-16b.cyr" ] || { echo "FAIL: $G: $REPU*.cyr missing"; exit 1; }
cp "$REPU.cyr" "$T/TU0.cyr"
runs TU0 33 "D29's repro verbatim: \`var x = mk1(30); syscall(60, x.a);\` in the zone (refused before: no struct type in scope)"
cp "$REPU-16b.cyr" "$T/TU0b.cyr"
refused TU0b "'mk2' returns a struct by value, and a struct result needs storage in a fn's frame" \
    "D30's repro verbatim: \`var x = mk2(30);\` (16 B) refused once (33, the first word, silently before)"
MNF="returns a struct by value, and a struct result needs storage in a fn's frame"
# rowu <name> <zone|after> <declarations> <exit expression>: after = behind a first statement (`Z = 1;`, `$TS`)
rowu() {
    if [ "$2" = zone ]; then printf '%s\n%s\nsyscall(60, %s);\n' "$TH" "$3" "$4" > "$T/$1.cyr"
    else printf '%s\n%s\n%s\nsyscall(60, %s);\n' "$TH" "$TS" "$3" "$4" > "$T/$1.cyr"; fi
}
for zw in zone after; do
    rowu "TU1$zw" $zw 'var G = mk1(33);' 'G.a'
    runs "TU1$zw" 33 "top level ($zw): \`var G = mk1(33);\` is the 8 B struct (\`G.a\`)"
    rowu "TU2$zw" $zw 'var G = (mk1(33));' 'G.a'
    runs "TU2$zw" 33 "top level ($zw): \`var G = (mk1(33));\`"
    rowu "TU3$zw" $zw 'var G = ((mk1(30)));
var H = mk1(3);' 'G.a + H.a'
    runs "TU3$zw" 33 "top level ($zw): \`((mk1(30)))\` beside a plain one"
    rowu "TU4$zw" $zw 'var G = mk2(5);' 'G.a'
    refused "TU4$zw" "'mk2' $MNF" "top level ($zw): \`var G = mk2(5);\` (16 B) refused once, \`G.a\` no second error"
    rowu "TU5$zw" $zw 'var G = (mk2(5));' 'G.b'
    refused "TU5$zw" "'mk2' $MNF" "top level ($zw): \`var G = (mk2(5));\` refused once"
    rowu "TU6$zw" $zw 'var G = mk3(5);' 'G.c'
    refused "TU6$zw" "'mk3' $MNF" "top level ($zw): 24 B, the call's one refusal (no 'no struct type in scope' after it)"
    rowu "TU7$zw" $zw 'var G = ((mk3(5)));' 'G.a'
    refused "TU7$zw" "'mk3' $MNF" "top level ($zw): 24 B wrapped, one error"
    rowu "TU8$zw" $zw 'fn P1_add(l: P1, r: P1): P1 { var q: P1; q.a = l.a + r.a; return q; }
var G = mk1(17);
var K: P1 = G + G;' 'K.a - 1'
    runs "TU8$zw" 33 "top level ($zw): \`G + G\` dispatches \`P1_add\`"
    rowu "TU9$zw" $zw 'var G = mk1(17);
var K = G + 1;' '0'
    rows=$((rows + 1))
    compile x86_64 "TU9$zw"
    if [ "$crc" -ne 0 ] && grep -q "undefined function 'P1_add'" "$T/TU9$zw.x86_64.err" && [ ! -s "$T/TU9$zw.x86_64" ]; then
        ok "TU9$zw top level ($zw): \`G + 1\` with no \`P1_add\` is refused (it added to the word before)"
    else bad "TU9$zw top level ($zw): \`G + 1\` was not refused for want of \`P1_add\` (rc $crc)"; fi
    rowu "TU10$zw" $zw 'var G = mk2(nope);' '0'
    refused "TU10$zw" "undefined variable 'nope'" "top level ($zw): a refusal inside the initialiser is the one error"
    rowu "TU12$zw" $zw 'var G = mk1(30);
fn f(): i64 { return G.a + d1(G); }
fn d1(p: P1): i64 { return p.a; }' 'f() - 27'
    runs "TU12$zw" 33 "top level ($zw): a fn body reads \`G.a\` and passes G by value"
    rowu "TU13$zw" $zw 'var G = mk1(33);
var Y: P1 = G;' 'Y.a'
    runs "TU13$zw" 33 "top level ($zw): \`var Y: P1 = G;\` copies it"
done
printf 'include "lib/syscalls.cyr"\nstruct P1 { a; }\nvar G = mkb(30);\nfn mkb(a): P1 { var r: P1 = P1 { a + 3 }; return r; }\nsyscall(60, G.a);\n' > "$T/TU11zone.cyr"
runs TU11zone 33 "the declaration zone: the callee declared below the global"
printf 'include "lib/syscalls.cyr"\nstruct P1 { a; }\nvar Z = 0;\nZ = 1;\nvar G = mkb(30);\nsyscall(60, G.a);\nfn mkb(a): P1 { var r: P1 = P1 { a + 3 }; return r; }\n' > "$T/TU11after.cyr"
runs TU11after 33 "after a statement: the callee declared below the global"
rowu TUK1 after 'alloc_init();
var S = mks();
var R = (mks());' 'str_len(S) + str_len(R) + 24'
runs TUK1 34 "control: an untyped \`Str\` call at top level stays the handle (\`str_len(S)\`, wrapped too)"

[ "$rows" -ge 229 ] || bad "only $rows rows ran (floor 229)"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails check(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run (named above); the rest passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G ($rows rows) — \`var x = (mk());\` receives the struct (16 B, 24 B, a closure, a generic) and an annotation naming no struct (i64, u8, f64, bool, ...) is refused by name on x86_64 / aarch64 / cx / PE; the 8 B, \`Str\`, struct-annotated, field-bind, generic-base and dyn controls hold; a known fn-pointer call is refused as the direct call is (D28); and at top level, in the declaration zone and after a first statement (6.7.13); a method or operator result is refused as the free call is (D13); a struct over 8 B into a pointer annotation is refused by name in a fn (D14) and at top level (D28, 6.7.14); a generic \`: *T\` call into \`var h: S\` binds a handle, a \`: T\` one at a scalar instance stays refused (6.7.14); a wrapped \`Str\` call is a Str and a wrapped \`: f64\` call before an operator an f64 (6.7.14); an untyped top-level whole call binds its 8 B struct, a 9-16 B one is refused (D29 / D30, 6.7.14)"
