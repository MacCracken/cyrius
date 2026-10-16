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
# and the typed path's `_scv_peel` takes it, as for `var x: Q = (mk());`. (b) The user's decision
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
# (issues/2026-10-15-d24-scalar-annotation-refusal-misses-top-level.md). TL0 the repro verbatim; TL1-TL14 the zone /
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
# The filed repro, verbatim (issues/2026-10-15-d24-scalar-annotation-refusal-misses-top-level.md): exit 10 before.
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

# --- (a): wrapped calls, run ---
row A1 'fn f(): i64 { var x = ((mkp())); var y = (mk3()); var z = ((mk3())); return dq(x) + dq3(y) + dq3(z) - 68; }'
runs A1 34 "\`((mkp()))\`, \`(mk3())\`, \`((mk3()))\` into by-value parameters"
cp tests/tcyr/crossos/struct_receive_paren_call.tcyr "$T/A2.cyr"
runs A2 0 "tests/tcyr/crossos/struct_receive_paren_call.tcyr (fn scope, a closure, a generic; 16 B and 24 B)"

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

[ "$rows" -ge 71 ] || bad "only $rows rows ran (floor 71)"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails check(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run (named above); the rest passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G ($rows rows) — \`var x = (mk());\` receives the struct (16 B, 24 B, a closure, a generic) and an annotation naming no struct (i64, u8, f64, bool, ...) is refused by name on x86_64 / aarch64 / cx / PE; the 8 B, \`Str\`, struct-annotated, field-bind, generic-base and dyn controls hold; a known fn-pointer call is refused as the direct call is (D28); and at top level, in the declaration zone and after a first statement (6.7.13)"
