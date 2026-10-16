#!/bin/sh
# Gate: a vector-returning fn `return`s only what the vector return ABI can carry (6.6.6).
#
# THE DEFECT (measured at 6.6.5 and at this lane's parent, x86_64 Linux, NO diagnostic, exit 0):
#
#     fn bad(): f64v2 { return 5; }        -> compiled clean, the caller read 0
#     fn bad(): f64v2 { var s = 5; return s; }                    -> same
#     fn bad(): f64v2 { return; }                                 -> same
#     fn bad(x: f64v2, y: f64v2): f64v2 { return x + y; }         -> returned Y UNCHANGED
#     fn bad(): f64v2 { var v: f64v2 = mkv(41,7); return load64(&v); }  -> lo right, hi stale
#     fn sc(): i64 { return 5; }  fn bad(): f64v2 { return sc(); }      -> garbage
#     fn mk4(): f64v4 { ... }     fn bad(): f64v2 { return mk4(); }     -> 32 B into a 16 B return
#     fn bad(): f64v2 { return (41, 7); }                         -> caller read 0 (X10-X12)
#
# TWO MORE SHAPES THE 6.6.6 RULE REFUSES, whose pre-6.6.6 behaviour is NOT uniformly wrong and
# so is written down here rather than in the defect list (both measured at the lane parent):
#   X13  `return callptr(fp, 41, 7);`  -> high lane 7 on x86_64 and 7 under qemu-aarch64, 5
#        under wine-PE (all three built from the 701fb02f tree, which predates the refusal).
#        Right on two targets, wrong on the third. `callptr` is a BUILTIN token, not an IDENT
#        naming a declared fn, so there is no declared return type for the exact-type test or
#        for the PE arm's `GFRS(callee) == _cur_fn_ret_scalar` to key on — exactly the asymmetry
#        noted below. Refused.
#   X14  `return G;` for a correctly-typed vector GLOBAL -> read a STALE REGISTER, not G, on
#        x86_64. With `var G: f64v2 = mkv(41,7); var H: f64v2 = mkv(3,4);` ahead of it the
#        caller got 3 — H's low lane, the last thing left in XMM0 — not G's 41. (`load64(&G)`
#        reads 0 at the parent too: the top-level initializer of a vector global never stores,
#        a separate pre-existing defect reported by bite 21's review, not fixed here.) The two
#        `return IDENT;` branches resolve the name with FINDLOCAL, so a global never matched
#        and fell straight through to the scalar path. Refused.
#
# ROOT CAUSE. PARSE_RETURN's `_is_simd128` / `_is_simd256` branches handle exactly
# `return IDENT;` for a local of the matching class and fall through to the scalar PCMPE path
# for everything else, so rax held whatever the expression left there and rdx was never written.
# The v6.4.31 `_TARGET_PE` arm covers only `return <simd_call>(..)`. This is the same shape as
# bite 16c's 9-16 byte struct pair, one type class over.
#
# ⚠ THREE SITES, AND ONLY ONE OF THEM IS THE PARSE_RETURN REFUSAL. Two earlier arms of
# PARSE_RETURN handle a `return` themselves and `return 0` out of the function, so the refusal
# ~330 lines down never sees them:
#   * the TAIL-CALL path takes `return f(args);` and a `jmp` hands the callee's return
#     convention straight back to OUR caller — rows X6 and X7. Mutant m3.
#   * the MULTI-RETURN path takes `return (a, b);` and hands the values back in the ret2/ret3
#     INT convention (rax:rdx[:r3]), which is not the vector ABI on any target — rows X10-X12,
#     added by bite 21's review, which found the first refusal shipped with this hole open.
#     Mutant m4. The PAIR class is untouched (rax:rdx IS its ABI) and so is the scalar
#     multi-return: rows A7 (pair, host + win64) and A8/A9 (scalar, all four legs) are exactly
#     those, and they must stay GREEN under m4 as well as on the real tree.
#
# ⚠ THE CALL FORM IS TESTED ON THE EXACT DECLARED TYPE while `return IDENT;` accepts any local
# of the same CLASS. Deliberate: the IDENT branches byte-copy 16/32 bytes (right whatever the
# lane type), but the PE arm keys on `GFRS(callee) == _cur_fn_ret_scalar`, so a same-class call
# of a different declared type would miss that arm and land on the generic path on Windows.
#
# LEGS: host x86_64 (refusals + acceptances), the tree's own cx compiler under cxvm, aarch64
# under qemu-aarch64 and Win64 PE under wine when installed. qemu and wine are EMULATION, NOT
# hardware — the ecb/ach/cass/pi legs of the release gate are what verify the real thing.
# Refusal is a compile-time property, so every compiler is asked; only acceptances need a runner.
#
# EXPECTED VALUES. Refusals are checked on the MESSAGE, not just a non-zero exit, so a row
# cannot pass on an unrelated syntax error. Acceptances check BOTH lanes of the vector, by two
# separate programs, so a path that carries only the low half (exactly what the defect did)
# fails — and the values are re-derived per leg by the same program built by that leg's compiler.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree from `git archive HEAD` with the named
# hunk of src/frontend/parse_fn.cyr reverted, rebuilt with build/cycc, run as CYCC=<mutant>):
#   m1 all three sites reverted             -> RED, all 14 refusal rows (host)
#   m2 PARSE_RETURN refusal only reverted   -> RED, 11 rows: X1-X9 plus X13 and X14, which that
#                                              one refusal is the only site for; X10-X12 (the
#                                              tuple rows) stay green
#   m3 tail-call guard only reverted        -> RED, rows X6 and X7 only — the two CALL-form
#                                              rows, which the tail path takes before the
#                                              vector branch can see them
#   m4 multi-return guard only reverted     -> RED, rows X10, X11 and X12 only — the tuple
#                                              rows, which the multi-return arm takes before
#                                              the vector branch can see them. A7/A8/A9 stay
#                                              GREEN under m4, which is what proves the guard
#                                              is keyed on the vector classes and not on the
#                                              tuple syntax.
#   real tree                               -> GREEN (90 rows: 56 refusals, 34 acceptances —
#                                              14 refusal rows x 4 legs, 9 acceptance rows x 4
#                                              minus A7's two skipped legs, see a_legs —
#                                              across host + cx + qemu-aarch64 + wine-PE)
# Mutants were measured on a host-only copy of this file; the other legs share the frontend.
#
# ⛔ 6.7.11 (the call-arguments lane) — THE RECEIVE SIDE: a value-form vector LOCAL (`var v: T = <src>;`,
# `v = <src>;`). It got its 16 / 32 bytes only from `f(..)` by name: `callptr(&f, ..)`, `fncallN(&f,
# ..)` and `(f(..))` were stored as one word (wrong lanes on x86_64 / aarch64 / cx; on PE no hidden
# result pointer, so the callee wrote through its first argument), and so was every source that is no
# vector — a callee held in a variable (`callptr(fp, ..)`: 181 / 180 / 45 where 48 is right, a page
# fault at 0x29 on PE), `5`, `load64(..)`, `&w`. The receive now takes every source that IS the vector
# — a local of its type, a by-name call declared to return it, inside parentheses too, and
# `fncallN(&f, ..)` / `callptr(&f, ..)` with `f` declared to return it — and refuses every other one by
# name, at the declaration and the assignment (the user's decision, 2026-10-13: the 6.6.6 return
# rule's sources, at the receive). Rows V (accepted, each lane read back through a value-form
# parameter; f64v2 / f32v4 / i32v4 / f64v4, declaration and assignment, and the guide's out-pointer
# workaround) and Y (refused once, by name, no artifact — Y1 is the filed repro verbatim) on all four
# legs; tests/tcyr/crossos/simd_indirect_receive.tcyr is the same table for the release gate's hosts.
# MUTATION LEDGER (6.7.11 — a scratch copy of the tree, the one change, rebuilt, run as CYCC=<mutant>):
#   MV1 `_vrcv_decl` never declaring                       -> RED V1 V3 V5 V7 on all four legs (refused: the declaration
#                                                          fell to the scalar path)
#   MV2 `_vrcv_asg` always deferring (-1)                  -> RED Y5-Y8 Y11 (not refused) and V2 V4 V6 V8 (1; PE 5)
#                                                          on all four legs
#   MV3 `_var_rhs_post` without `_vrcv_decl_err`           -> RED Y1-Y4 Y9 Y10 (not refused) on all four legs
#   MV4 `_icall_sret` without its `_icall_vbeg` arm (PE)   -> RED win64 V1-V8 only (5: the callee wrote through its
#                                                          first argument) — the hidden pointer is PE's alone
#   MV5 `_vrcv_emit` without the register-pair store       -> RED V1-V8 on host / cx / aarch64 (1); win64 green (no pair)
# 6.7.12 (issues/archived/2026-10-14-6711-rows-not-run-on-hardware.md item 4): A7 runs on ecb / ach / cass / pi in
# tests/tcyr/crossos/struct_return_shape_controls.tcyr (6.7.13: its producer says `return p;`, as here).
#
# ⛔ 6.7.13 (the vectors lane, issues/2026-10-14-explicit-instance-vector-result-not-received.md) — AN
# EXPLICIT-INSTANCE GENERIC CALL `mkg<i64>(41, 7)` IS A BY-NAME CALL DECLARED TO RETURN ITS VECTOR. Every receive tested `IDENT (`: the
# assignment `v = mkg<i64>(41, 7);` was refused (".. got `mkg`"), the declaration `var v: f64v2 = mkg<i64>(..)` lost its
# annotation (PARSE_VAR's struct lookahead reset it: `_gen_decl_check` answered 0 for a vector), so the local was one
# word — `lanes(v)` refused "value-form SIMD arg must be a 16-byte vector" (PE: exit 5), `load64(&v + 8)` read garbage
# silently (x86_64 / IR=3 / aarch64 0, cx 154, PE 195; 161 is right) — and `return mkg<i64>(a, b)` from a `: f64v2` fn
# was refused. One recogniser (`_vcall_fi`: `_gcall_open` + `_gen_resolve_call`) now serves the receives, the
# declared-type check, the return rule, PE's own call (`_vcall_enter`) and D27's `*V` argument (`_svc_rs`); a vector
# annotation is never reset. Rows E (accepted; x86_64 / IR=3 / cx / aarch64 / PE) and Z (refused once, by name):
#   E1 the filed repro verbatim (161)   E2 the declaration with lanes(v)   E3 the declaration read through load64(&v)
#   (the silent one)   E4 `return mkg<i64>(a, b)`   E5 the inferred `mkg(41, 7)` (the control, always 161)   E6 the
#   unannotated `var v = mkg<i64>(..)` (inferred, as `var v = mkv(..)` is)   E7 `rd(mkg<i64>(42, 7))` into `*f64v2`
#   (42: D27's call result; row 7 of 2026-10-15-vector-value-into-other-pointer-or-byvalue-struct-and-unreceived-call-
#   sources.md)   E8 a real instance `mkg<i32>` and a struct type argument `mkp<Pt>`, declaration and assignment
#   E9 wrapped `(mkg<i64>(..))`, declaration and assignment
#   Z1 `var v: f64v4 = mkg<i64>(..)` (an f64v2 call) "vector return type does not match the declared type" (compiled
#   before: the annotation dropped)   Z2 `w = mkg<i64>(..)` into an f64v4 ".. the assigned variable"
#   Z3 `x = mkg<i64>(..)` into a scalar local, as `x = mkv(..)` is (compiled before: exit 0)   Z4 `var x: i64 =
#   mkg<i64>(..)` (compiled before)
#   Z5 `var v: f64v2 = idg<i64>(5)`, a scalar-returning generic: the vector local's own refusal (compiled before: the
#   annotation reset)   Z6 `return mkg<i64>(a, b)` from a `: f64v4` fn (the return rule's)
# MUTATION LEDGER (6.7.13 — a scratch copy of the tree, the one change, rebuilt, run as CYCC=<mutant>; measured):
#   ME1 `_vcall_fi` taking `IDENT (` only (`o != ti + 1` -> -1) -> RED 56: E1-E4 E6-E9 on all five legs (refused, or
#       the one-word local: E6 0 / cx 154 / PE 195, E7 139 / cx 0 / PE 5), Z1-Z4 on all four (another refusal, or
#       compiled); E5 (the inferred `IDENT (`) and Z5 Z6 green
#   ME2 `_gen_decl_check` without its vector guard          -> RED 4: Z5 on all four legs (compiled); the E rows green
#       (the receive takes them before the reset)
#   ME3 `_vrcv_decl` deferring an explicit instance (no `_vrcv_g` arm) -> RED 20: E2 E3 E6 E8 on all five legs (0;
#       cx 154 / 88, PE 195 / 244: the scalar init); E1 (`_try_vector_call_assign` takes the assignment) and E9 (a
#       wrap) green
#   ME4 `_vcall_enter` stepping two tokens (`IDENT (` only) -> RED 8: win64 E1-E4 E6-E9 ("undefined variable 'i64'":
#       the type argument parsed as the first argument) — PE's own call alone
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-$ROOT/build/cycc}
[ -x "$CC" ] || { echo "FAIL: compiler $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: mktemp"; exit 1; }
# A PRIVATE wine prefix under $W, never the user's ~/.wine: its one wineserver is shared by
# every concurrent check.sh on the box. The EXIT kill is scoped to THIS prefix and also removes
# its server socket dir (/tmp/.wine-<uid>/server-<dev>-<ino>). The bare `wineserver -k` this trap
# ran before 6.6.16 killed the DEFAULT prefix's server on any exit before the export below.
# CHANGELOG [6.6.16]
# 6.6.17: wine's own HOME and XDG_CACHE_HOME are under $W too — a fresh prefix writes
# $HOME/.cache (mesa shader caches) — and `wineserver -k` leaves the server dir behind, so
# _wine_down removes it. CHANGELOG [6.6.17]
WP="$W/wine"
WHM="$W/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT

MSG="a vector-returning fn carries its result"
pass=0; fail=0; nrefuse=0; naccept=0

bad() { echo "  FAIL: $*"; fail=$((fail+1)); }
good() { echo "  ok: $*"; pass=$((pass+1)); }

MKV='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
'
MK4='fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, a + 1); return v; }
'

# ---- the row tables -------------------------------------------------------------------------
# One fn per table, `case` on the row id — the sources embed quotes and braces, so a here-doc
# list or an eval'd array would be the fragile spelling.
r_src() {  # $1 row id -> source on stdout
    case "$1" in
    X1) printf '%s' "$MKV"'fn bad(): f64v2 { return 5; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X2) printf '%s' "$MKV"'fn bad(): f64v2 { var s = 5; return s; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X3) printf '%s' "$MKV"'fn bad(): f64v2 { return; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X4) printf '%s' "$MKV"'fn bad(x: f64v2, y: f64v2): f64v2 { return x + y; }
fn main(): i64 { var a: f64v2 = mkv(10,11); var b: f64v2 = mkv(20,21); var c: f64v2 = bad(a,b); return load64(&c); }
var r = main(); syscall(60, r);
' ;;
    X5) printf '%s' "$MKV"'fn bad(): f64v2 { var v: f64v2 = mkv(41,7); return load64(&v); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X6) printf '%s' "$MKV"'fn sc(): i64 { return 5; }
fn bad(): f64v2 { return sc(); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X7) printf '%s' "$MKV$MK4"'fn bad(): f64v2 { return mk4(77); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X8) printf '%s' 'fn bad(): f64v4 { return 5; }
fn main(): i64 { var v: f64v4 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X9) printf '%s' 'fn bad(): f64v2 { var v: f64v4; store64(&v, 41); return v; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X10) printf '%s' 'fn bad(): f64v2 { return (41, 7); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X11) printf '%s' 'fn bad(): i64v2 { return (41, 7); }
fn main(): i64 { var v: i64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X12) printf '%s' 'fn bad(): f64v4 { return (41, 7, 9); }
fn main(): i64 { var v: f64v4 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X13) printf '%s' "$MKV"'fn bad(): f64v2 { var fp = &mkv; return callptr(fp, 41, 7); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X14) printf '%s' "$MKV"'var G: f64v2 = mkv(41, 7);
fn bad(): f64v2 { return G; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    esac
}
REFUSE_ROWS="X1 X2 X3 X4 X5 X6 X7 X8 X9 X10 X11 X12 X13 X14"

a_src() {  # $1 row id -> source on stdout
    case "$1" in
    A1) printf '%s' "$MKV"'fn good(): f64v2 { var v: f64v2 = mkv(41, 7); return v; }
fn main(): i64 { var v: f64v2 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A2) printf '%s' "$MKV"'fn good(): f64v2 { var v: f64v2 = mkv(41, 7); return v; }
fn main(): i64 { var v: f64v2 = good(); return load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    A3) printf '%s' "$MKV"'fn good(): f64v2 { return mkv(41, 7); }
fn main(): i64 { var v: f64v2 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A4) printf '%s' "$MKV"'fn good(): f64v2 { return mkv(41, 7); }
fn main(): i64 { var v: f64v2 = good(); return load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    A5) printf '%s' "$MK4"'fn good(): f64v4 { var v: f64v4 = mk4(41); return v; }
fn main(): i64 { var v: f64v4 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A6) printf '%s' 'fn sc(): i64 { return 33; }
fn main(): i64 { return sc(); }
var r = main(); syscall(60, r);
' ;;
    # A7-A9: the tuple return is refused for the VECTOR classes ONLY. These three are the
    # shapes X10-X12 sit next to and must not take with them — the rax:rdx pair struct, whose
    # ABI the ret2 convention IS, and the scalar arity-2/arity-3 multi-return. Each packs its
    # values into distinct decimal digits so a row cannot pass with the operands swapped or
    # with one register left unwritten. 6.7.11: a fn returning a named struct refuses the tuple
    # literal itself (the user's decision, issues/archived/2026-10-08-struct-operator-results.md #4), so
    # A7's pair struct said `ret2(41, 7)`, the same multi-value arm; A8 / A9 keep the tuple spelling. 6.7.13:
    # `ret2` in a fn declared to return a named struct is refused too (D22 A, the user's decision, 2026-10-15), so
    # A7 returns its struct as the struct: `return p;`, the 9-16 B pair's own path.
    A7) printf '%s' 'struct P2 { a; b; }
fn good(): P2 { var p: P2 = P2 { 41, 7 }; return p; }
fn main(): i64 { var p: P2 = good(); return p.a + p.b; }
var r = main(); syscall(60, r);
' ;;
    A8) printf '%s' 'fn two(): i64 { return (5, 6); }
fn main(): i64 { var a, b = two(); return a * 10 + b; }
var r = main(); syscall(60, r);
' ;;
    A9) printf '%s' 'fn three(): i64 { return (1, 2, 3); }
fn main(): i64 { var a, b, c = three(); return a * 100 + b * 10 + c; }
var r = main(); syscall(60, r);
' ;;
    esac
}
ACCEPT_ROWS="A1 A2 A3 A4 A5 A6 A7 A8 A9"

# ---- 6.7.11: the receive (rows V accepted, Y refused) ----------------------------------------
MSGV="a value-form vector local is"
VH='include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn mki(a, b, c, d): i32v4 { var v: i32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn mkd(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn l2(x: f64v2): i64 { return load64(&x) * 100 + load64(&x + 8); }
fn lf(x: f32v4): i64 { return load32(&x) * 1000000 + load32(&x + 4) * 10000 + load32(&x + 8) * 100 + load32(&x + 12); }
fn li(x: i32v4): i64 { return load32(&x) * 1000000 + load32(&x + 4) * 10000 + load32(&x + 8) * 100 + load32(&x + 12); }
fn ld(x: f64v4): i64 { return load64(&x) * 1000000 + load64(&x + 8) * 10000 + load64(&x + 16) * 100 + load64(&x + 24); }
'
VE='var r = main(); syscall(60, r);
'
v_src() {  # $1 row id -> source on stdout; each returns 42 when every lane is right, else the shape that is not
    case "$1" in
    V1) printf '%s' "$VH"'fn main(): i64 { var a: f64v2 = callptr(&mk2, 41, 7); var b: f64v2 = fncall2(&mk2, 12, 34); var c: f64v2 = (mk2(56, 78));
  if (l2(a) != 4107) { return 1; } if (l2(b) != 1234) { return 2; } if (l2(c) != 5678) { return 3; } return 42; }
'"$VE" ;;
    V2) printf '%s' "$VH"'fn main(): i64 { var a: f64v2 = mk2(0, 0); a = callptr(&mk2, 41, 7); if (l2(a) != 4107) { return 1; }
  a = fncall2(&mk2, 12, 34); if (l2(a) != 1234) { return 2; } a = (mk2(56, 78)); if (l2(a) != 5678) { return 3; } return 42; }
'"$VE" ;;
    V3) printf '%s' "$VH"'fn main(): i64 { var a: f32v4 = callptr(&mkf, 1, 2, 3, 4); var b: f32v4 = fncall4(&mkf, 5, 6, 7, 8); var c: f32v4 = (mkf(9, 10, 11, 12));
  if (lf(a) != 1020304) { return 1; } if (lf(b) != 5060708) { return 2; } if (lf(c) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V4) printf '%s' "$VH"'fn main(): i64 { var a: f32v4 = mkf(0, 0, 0, 0); a = callptr(&mkf, 1, 2, 3, 4); if (lf(a) != 1020304) { return 1; }
  a = fncall4(&mkf, 5, 6, 7, 8); if (lf(a) != 5060708) { return 2; } a = (mkf(9, 10, 11, 12)); if (lf(a) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V5) printf '%s' "$VH"'fn main(): i64 { var a: i32v4 = callptr(&mki, 1, 2, 3, 4); var b: i32v4 = fncall4(&mki, 5, 6, 7, 8); var c: i32v4 = (mki(9, 10, 11, 12));
  if (li(a) != 1020304) { return 1; } if (li(b) != 5060708) { return 2; } if (li(c) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V6) printf '%s' "$VH"'fn main(): i64 { var a: i32v4 = mki(0, 0, 0, 0); a = callptr(&mki, 1, 2, 3, 4); if (li(a) != 1020304) { return 1; }
  a = fncall4(&mki, 5, 6, 7, 8); if (li(a) != 5060708) { return 2; } a = (mki(9, 10, 11, 12)); if (li(a) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V7) printf '%s' "$VH"'fn main(): i64 { var a: f64v4 = callptr(&mkd, 1, 2, 3, 4); var b: f64v4 = fncall4(&mkd, 5, 6, 7, 8); var c: f64v4 = (mkd(9, 10, 11, 12));
  if (ld(a) != 1020304) { return 1; } if (ld(b) != 5060708) { return 2; } if (ld(c) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V8) printf '%s' "$VH"'fn main(): i64 { var a: f64v4 = mkd(0, 0, 0, 0); a = callptr(&mkd, 1, 2, 3, 4); if (ld(a) != 1020304) { return 1; }
  a = fncall4(&mkd, 5, 6, 7, 8); if (ld(a) != 5060708) { return 2; } a = (mkd(9, 10, 11, 12)); if (ld(a) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V9) printf '%s' "$VH"'fn mko(out, a, b): i64 { store64(out, a); store64(out + 8, b); return 0; }
fn main(): i64 { var fp = &mko; var v: f64v2 = mk2(0, 0); var ig = callptr(fp, &v, 41, 7); var u: f64v2 = mk2(41, 7);
  if (l2(v) != 4107) { return 1; } if (l2(u) != 4107) { return 2; } return 42; }
'"$VE" ;;
    esac
}
V_ROWS="V1 V2 V3 V4 V5 V6 V7 V8 V9"
y_src() {  # $1 row id -> source on stdout
    case "$1" in
    Y1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 {
    var fp = &mkv;
    var v: f64v2 = callptr(fp, 41, 7);
    return load64(&v) + load64(&v + 8);
}
syscall(60, run());
' ;;
    Y2) printf '%s' "$VH"'fn main(): i64 { var v: f64v2 = 5; return l2(v); }
'"$VE" ;;
    Y3) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = load64(&w); return l2(v); }
'"$VE" ;;
    Y4) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = &w; return l2(v); }
'"$VE" ;;
    Y5) printf '%s' "$VH"'fn main(): i64 { var fp = &mk2; var v: f64v2 = mk2(0, 0); v = callptr(fp, 41, 7); return l2(v); }
'"$VE" ;;
    Y6) printf '%s' "$VH"'fn main(): i64 { var v: f64v2 = mk2(0, 0); v = 5; return l2(v); }
'"$VE" ;;
    Y7) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = mk2(0, 0); v = load64(&w); return l2(v); }
'"$VE" ;;
    Y8) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = mk2(0, 0); v = &w; return l2(v); }
'"$VE" ;;
    Y9) printf '%s' "$VH"'fn main(): i64 { var fp = &mkd; var v: f64v4 = callptr(fp, 1, 2, 3, 4); return ld(v); }
'"$VE" ;;
    Y10) printf '%s' "$VH"'fn main(): i64 { var fp = &mkf; var v: f32v4 = fncall4(fp, 1, 2, 3, 4); return lf(v); }
'"$VE" ;;
    Y11) printf '%s' "$VH"'fn main(): i64 { var v: i32v4 = mki(1, 2, 3, 4); var i = 0; for (i = 0; i < 1; v = 5) { i = i + 1; } return li(v); }
'"$VE" ;;
    esac
}
Y_ROWS="Y1 Y2 Y3 Y4 Y5 Y6 Y7 Y8 Y9 Y10 Y11"
# ---- 6.7.13: the explicit instance (rows E accepted, Z refused) --------------------------------
EH='include "lib/fnptr.cyr"
struct Pt { x; y; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkp<T>(p: T, a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn idg<T>(a: T): T { return a; }
fn rd(p: *f64v2): i64 { return load64(p); }
'
e_src() {  # $1 row id -> source on stdout
    case "$1" in
    E1) printf '%s' 'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 { var v: f64v2; v = mkg<i64>(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E2) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = mkg<i64>(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E3) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = mkg<i64>(41, 7); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run());
' ;;
    E4) printf '%s' "$EH"'fn mk2(a, b): f64v2 { return mkg<i64>(a, b); }
fn run(): i64 { var v: f64v2 = mk2(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E5) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = mkg(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E6) printf '%s' "$EH"'fn run(): i64 { var v = mkg<i64>(41, 7); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run());
' ;;
    E7) printf '%s' "$EH"'fn run(): i64 { return rd(mkg<i64>(42, 7)); }
syscall(60, run());
' ;;
    E8) printf '%s' "$EH"'fn run(): i64 { var p: Pt; var v: f64v2 = mkg<i32>(41, 7); var w: f64v2; w = mkp<Pt>(p, 1, 2);
  var q: f64v2 = mkp<Pt>(p, 3, 4); v = mkg<i32>(lanes(v) - 120, 7); return lanes(v) + lanes(w) + lanes(q) - 46; }
syscall(60, run());
' ;;
    E9) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = (mkg<i64>(41, 7)); var w: f64v2; w = (mkg<i64>(1, 2));
  return lanes(v) + lanes(w) - 12; }
syscall(60, run());
' ;;
    esac
}
E_ROWS="E1 E2 E3 E4 E5 E6 E7 E8 E9"
e_want() { case "$1" in E7) echo 42;; *) echo 161;; esac; }
z_src() {  # $1 row id -> source on stdout
    case "$1" in
    Z1) printf '%s' "$EH"'fn run(): i64 { var v: f64v4 = mkg<i64>(41, 7); return 1; }
syscall(60, run());
' ;;
    Z2) printf '%s' "$EH"'fn run(): i64 { var w: f64v4; w = mkg<i64>(1, 2); return 1; }
syscall(60, run());
' ;;
    Z3) printf '%s' "$EH"'fn run(): i64 { var x = 0; x = mkg<i64>(1, 2); return x; }
syscall(60, run());
' ;;
    Z4) printf '%s' "$EH"'fn run(): i64 { var x: i64 = mkg<i64>(1, 2); return x; }
syscall(60, run());
' ;;
    Z5) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = idg<i64>(5); return 1; }
syscall(60, run());
' ;;
    Z6) printf '%s' "$EH"'fn r4(a, b): f64v4 { return mkg<i64>(a, b); }
syscall(60, 1);
' ;;
    esac
}
Z_ROWS="Z1 Z2 Z3 Z4 Z5 Z6"
z_msg() {
    case "$1" in
    Z1|Z4) echo "vector return type does not match the declared type";;
    Z2|Z3) echo "vector return type does not match the assigned variable";;
    Z5) echo "$MSGV";;
    Z6) echo "$MSG";;
    esac
}
# Which legs an acceptance row RUNS on: every row on all four. A7's int-class 16-byte pair return
# is a per-target ABI the tuple guard has nothing to do with, and it was kept off two legs until
# each target carried it:
#   cx      — refused the pair outright ("cx: int-class 16B struct pair-return ABI not supported")
#             until 6.7.8 (r0:r4, the multi-value pair's registers).
#   aarch64 — silently lost the second register (41 for 48): the struct pair (x0:x1) and the
#             multi-value slot (x2) disagreed until 6.7.7 (ESTRUCT_PAIR_HI_SYNC); 48 since.
#             Mutation (6.7.8, a scratch copy): aarch64 ESTRUCT_PAIR_HI_SYNC emitting nothing ->
#             RED aarch64 A7 = 41, every other row green. 6.7.13: A7's producer is `return p;` (its
#             `ret2` refused) and the sync is gone with its last producer.
# A8 and A9 (the SCALAR arity-2/arity-3 multi-return) run on all four legs and are green on all
# four, so the "tuple syntax still works" property is not host-only.
a_legs() { echo "host cx aarch64 win64"; }
# Every expectation is derived a different way from the program that produces it: the vector
# rows read a lane the source stored a literal into, A7 sums two distinct fields (41+7=48, and
# 7+41 is the same — so A7 is paired with X10, which has the same operands and must be REFUSED),
# A8/A9 pack each return slot into its own decimal digit so a swap or an unwritten register
# cannot land on the expected number.
a_want() {
    case "$1" in
    A1) echo 41;; A2) echo 7;; A3) echo 41;; A4) echo 7;; A5) echo 41;; A6) echo 33;;
    A7) echo 48;; A8) echo 56;; A9) echo 123;;
    esac
}

# ---- legs ------------------------------------------------------------------------------------
refuse_all() {  # $1 leg label  $2 compiler
    for row in $REFUSE_ROWS; do
        r_src "$row" > "$W/r.cyr"
        rc=0
        cat "$W/r.cyr" | "$2" > "$W/r.out" 2>"$W/r.err" || rc=$?
        nrefuse=$((nrefuse+1))
        if ! grep -q "$MSG" "$W/r.err" 2>/dev/null; then
            bad "$1 $row: not refused (rc=$rc, first line: $(head -1 "$W/r.err" 2>/dev/null))"
        elif [ -s "$W/r.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused"
        fi
    done
}

accept_all() {  # $1 leg label  $2 compiler  $3 runner fn name
    for row in $ACCEPT_ROWS; do
        case " $(a_legs "$row") " in *" $1 "*) ;; *) echo "  skip: $1 $row (see a_legs)"; continue;; esac
        a_src "$row" > "$W/a.cyr"
        cat "$W/a.cyr" | "$2" > "$W/a.out" 2>/dev/null || true
        naccept=$((naccept+1))
        if ! [ -s "$W/a.out" ]; then bad "$1 $row: produced no artifact"; continue; fi
        chmod +x "$W/a.out"
        got=0
        ( ulimit -c 0; "$3" "$W/a.out" ) >/dev/null 2>&1 || got=$?
        want=$(a_want "$row")
        if [ "$got" = "$want" ]; then good "$1 $row = $got"; else bad "$1 $row = $got, want $want"; fi
    done
}

# 6.7.11: the receive rows — each Y refused ONCE (one `error` line), by name, with no artifact.
refuse_v_all() {  # $1 leg label  $2 compiler
    for row in $Y_ROWS; do
        y_src "$row" > "$W/y.cyr"
        rc=0
        cat "$W/y.cyr" | "$2" > "$W/y.out" 2>"$W/y.err" || rc=$?
        nrefuse=$((nrefuse+1))
        ne=$(grep -c '^error' "$W/y.err" 2>/dev/null || true)
        if ! grep -q "$MSGV" "$W/y.err" 2>/dev/null; then
            bad "$1 $row: not refused (rc=$rc, first line: $(head -1 "$W/y.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/y.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}
accept_v_all() {  # $1 leg label  $2 compiler  $3 runner fn name
    for row in $V_ROWS; do
        v_src "$row" > "$W/v.cyr"
        rc=0
        cat "$W/v.cyr" | "$2" > "$W/v.out" 2>"$W/v.err" || rc=$?
        naccept=$((naccept+1))
        if ! [ -s "$W/v.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/v.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/v.out"
        got=0
        ( ulimit -c 0; "$3" "$W/v.out" ) >/dev/null 2>&1 || got=$?
        if [ "$got" = 42 ]; then good "$1 $row = 42"; else bad "$1 $row = $got, want 42"; fi
    done
}

# 6.7.13: the explicit-instance rows — each E built by the leg's compiler (`$3` an env assignment or -) and run;
# each Z refused once, by its own words, with no artifact.
accept_e_all() {  # $1 leg label  $2 compiler  $3 runner fn name  [$4 VAR=value for the compiler]
    for row in $E_ROWS; do
        e_src "$row" > "$W/e.cyr"
        rc=0
        if [ -n "${4:-}" ]; then env "$4" "$2" < "$W/e.cyr" > "$W/e.out" 2>"$W/e.err" || rc=$?
        else "$2" < "$W/e.cyr" > "$W/e.out" 2>"$W/e.err" || rc=$?; fi
        naccept=$((naccept+1))
        if ! [ -s "$W/e.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/e.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/e.out"
        got=0
        ( ulimit -c 0; "$3" "$W/e.out" ) >/dev/null 2>&1 || got=$?
        want=$(e_want "$row")
        if [ "$got" = "$want" ]; then good "$1 $row = $got"; else bad "$1 $row = $got, want $want"; fi
    done
}
refuse_z_all() {  # $1 leg label  $2 compiler
    for row in $Z_ROWS; do
        z_src "$row" > "$W/z.cyr"
        rc=0
        "$2" < "$W/z.cyr" > "$W/z.out" 2>"$W/z.err" || rc=$?
        nrefuse=$((nrefuse+1))
        zm=$(z_msg "$row")
        ne=$(grep -c '^error' "$W/z.err" 2>/dev/null || true)
        if ! grep -qF "$zm" "$W/z.err" 2>/dev/null; then
            bad "$1 $row: not refused as '$zm' (rc=$rc, first line: $(head -1 "$W/z.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/z.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}

hostr() { timeout 60 "$1"; }
echo "host x86_64:"
refuse_all host "$CC"
accept_all host "$CC" hostr
refuse_v_all host "$CC"
accept_v_all host "$CC" hostr
accept_e_all host "$CC" hostr
accept_e_all host-ir3 "$CC" hostr CYRIUS_IR=3
refuse_z_all host "$CC"

echo "cx (cxvm):"
if cat src/main_cx.cyr | "$CC" > "$W/cycc_cx" 2>/dev/null && [ -s "$W/cycc_cx" ] \
   && cat programs/cxvm.cyr | "$CC" > "$W/cxvm" 2>/dev/null && [ -s "$W/cxvm" ]; then
    chmod +x "$W/cycc_cx" "$W/cxvm"
    cxr() { timeout 60 "$W/cxvm" < "$1"; }
    refuse_all cx "$W/cycc_cx"
    accept_all cx "$W/cycc_cx" cxr
    refuse_v_all cx "$W/cycc_cx"
    accept_v_all cx "$W/cycc_cx" cxr
    accept_e_all cx "$W/cycc_cx" cxr
    refuse_z_all cx "$W/cycc_cx"
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi

if command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "aarch64 (qemu-aarch64 — EMULATION, not hardware):"
    if cat src/main_aarch64.cyr | "$CC" > "$W/cycc_a64" 2>/dev/null && [ -s "$W/cycc_a64" ]; then
        chmod +x "$W/cycc_a64"
        a64r() { timeout 120 qemu-aarch64 "$1"; }
        refuse_all aarch64 "$W/cycc_a64"
        accept_all aarch64 "$W/cycc_a64" a64r
        refuse_v_all aarch64 "$W/cycc_a64"
        accept_v_all aarch64 "$W/cycc_a64" a64r
        accept_e_all aarch64 "$W/cycc_a64" a64r
        refuse_z_all aarch64 "$W/cycc_a64"
    else
        bad "aarch64 leg: could not build src/main_aarch64.cyr"
    fi
else
    echo "  SKIP: qemu-aarch64 not installed (the pi hardware leg still covers it)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

if command -v wine > /dev/null 2>&1; then
    echo "win64 (wine — EMULATION, not hardware; the PE arm is the one this refusal sits in front of):"
    export WINEPREFIX="$W/wine" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    if cat src/main_win.cyr | "$CC" > "$W/cycc_win" 2>/dev/null && [ -s "$W/cycc_win" ]; then
        chmod +x "$W/cycc_win"
        wr_() { cp "$1" "$1.exe"; timeout 180 wine "$1.exe"; }
        refuse_all win64 "$W/cycc_win"
        accept_all win64 "$W/cycc_win" wr_
        refuse_v_all win64 "$W/cycc_win"
        accept_v_all win64 "$W/cycc_win" wr_
        accept_e_all win64 "$W/cycc_win" wr_
        refuse_z_all win64 "$W/cycc_win"
    else
        bad "win64 leg: could not build src/main_win.cyr"
    fi
    wineserver -k > /dev/null 2>&1 || true
else
    echo "  SKIP: wine not installed (the cass hardware leg still covers it)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

# Anti-vacuous. The floor is DERIVED from the row tables (every row on host + cx, the two legs
# that are always present) so adding a row cannot leave a stale hard-coded number behind.
nr_rows=$(set -- $REFUSE_ROWS $Y_ROWS $Z_ROWS; echo $#)
[ "$nrefuse" -ge $((nr_rows * 2)) ] || bad "only $nrefuse refusal rows ran (floor $((nr_rows * 2)) = $nr_rows rows x host + cx)"
# The acceptance floor sums a_legs over the two always-present legs rather than multiplying, so
# a row excluded from a leg is subtracted here automatically and an over-broad exclusion lowers
# the floor visibly instead of silently passing.
na_floor=0
for row in $ACCEPT_ROWS; do
    for leg in host cx; do
        case " $(a_legs "$row") " in *" $leg "*) na_floor=$((na_floor + 1));; esac
    done
done
na_floor=$((na_floor + $(set -- $V_ROWS; echo $#) * 2))   # 6.7.11: every V row on host + cx
na_floor=$((na_floor + $(set -- $E_ROWS; echo $#) * 3))   # 6.7.13: every E row on host + host IR=3 + cx
[ "$naccept" -ge "$na_floor" ] || bad "only $naccept acceptance rows ran (floor $na_floor = a_legs summed over host + cx, + the V rows)"
# And every row id in both tables must actually produce a source — a typo'd id would otherwise
# compile an EMPTY program, which cycc accepts (exit 0, runnable binary) and would score a row.
for row in $REFUSE_ROWS $ACCEPT_ROWS $V_ROWS $Y_ROWS $E_ROWS $Z_ROWS; do
    if [ "$(r_src "$row"; a_src "$row"; v_src "$row"; y_src "$row"; e_src "$row"; z_src "$row")" = "" ]; then bad "row $row has no source in any table"; fi
done
# And the message this gate greps for must still be the one the compiler emits.
n=$(grep -c "$MSG" src/frontend/parse_fn.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_fn.cyr no longer spells '$MSG' — reworded?"
n=$(grep -c "$MSGV" src/frontend/parse_decl.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_decl.cyr no longer spells '$MSGV' — reworded?"

echo "simd_return_shapes: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "$fail" -eq 0 ] && [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: simd_return_shapes — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
[ "$fail" -eq 0 ]
