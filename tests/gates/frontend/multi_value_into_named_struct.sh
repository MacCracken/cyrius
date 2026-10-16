#!/bin/sh
# tests/gates/frontend/multi_value_into_named_struct.sh — 6.7.11 (returns lane)
#
# A MULTI-VALUE CALL WHERE A NAMED STRUCT IS EXPECTED IS REFUSED BY NAME (the user's decision,
# 2026-10-13: R17's wording, at every struct size).
# (issues/archived/2026-10-09-multi-value-call-into-named-struct-slot.md,
#  issues/archived/2026-10-09-struct-var-from-multi-value-call-crashes.md)
#
# THE DEFECT (measured on 6.7.11's returns-lane tip before the fix, x86_64 / aarch64 under qemu / cx
# under cxvm / PE under wine): a call returning several values (`fn mk(a): (i64, i64)`, or an
# undeclared `return (a, b);` pass 1 counted) leaves them in the return registers. A named struct is a
# VALUE — taken by address over 8 B, as one word at or under it — and every named-struct destination
# keyed on the callee's struct, which a multi-value callee has none of. So its FIRST value became the
# struct, silently:
#   take(mk(3))              into `fn take(t: P)`               rc 139 / 139 / guest error 1 / 5
#   take(b.mk(3))            a method                            rc 139 / 139 / 1 / 5
#   var p: P = mk(3);        (and the struct-var issue's g2)     rc 139 / 139 / 1 / 5
#   h.p = mk(3);             into `struct H { p: P; }`           30 / 30 / 30 / 30 (34 meant)
#   var p: P; p = mk(3);                                         30 (a warning, then the wrong value)
#   an 8 B P1, every position                                    3 (a P1 built from the first value)
# R17 (6.7.7) refuses the same call into a TUPLE parameter or field ("bind it first"); the guide refuses
# the reverse direction (`var t: (i64, i64) = mk();` from a struct callee: "a struct return is not
# multiple values"). A named struct is now refused the same way, naming the call and the position:
#   a multi-value call 'mk' is not a struct 'P' argument - bind it first: `var a, b = mk(..);`
#   a multi-value call 'mk' does not initialize struct 'P' - bind it first: ...
#   a multi-value call 'mk' is not stored into a struct 'P' field - bind it first: ...
#   a multi-value call 'mk' is not assigned to struct 'P' - bind it first: ...
# The predicate keys on the callee's DECLARED return (`_mv_callee`): a `: P` fn returns a P and stays
# accepted (C2; its `return (x, y)` / `ret2` producers are refused at the producer since 6.7.11 / 6.7.13 —
# the SR axis below). A `*P` (parameter, variable) and a `Str`
# handle take a word — the call's first value, as `var x = mk(3);` does — and are not refused (C3, C6).
#
# LEGS: every refused row on the x86_64, aarch64 (cross), cx and PE (CYRIUS_TARGET_WIN=1) compilers —
# refused, the ONE `^error` line, no `^warning`, no binary; every control row run on x86_64, aarch64
# (qemu-aarch64), cx (cxvm) and PE (wine, a private prefix). A missing tool is a SKIP that names it.
#
# MUTATION LEDGER (2026-10-14, each a scratch copy of the tree with the one change, its compiler built
# from it, this gate run from the copy as CYCC=<mutant>; every leg RED unless said):
#   N0 the tree before the fix (76eaea61)                -> RED every refusal row but R17 (33 rows, every
#                                                           leg: rc 0); R17 and C1-C6 green
#   N1 `_mv_arg_call` returns 0                          -> RED S1 U1 TA W1 NA GC GS T3 FW
#   N2 `_mv_arg_mrc` returns 0                           -> RED S2 U2
#   N3 `_mv_small_arg` returns 0                         -> RED A8 M8
#   N4 `_mv_decl_src` returns 0                          -> RED S3 V1 H8 MD GZ GL W2 GD
#   N5 `_gen_decl_check` without the multi-value keep    -> RED GD
#   N6 `_mv_fsc_call` returns 0                          -> RED S4 F8 MF GF W3
#   N7 `_mv_asg_src` returns 0                           -> RED S5 S8 MA GA GT W4 FS
#   N8 `_mv_callee` without the counted undeclared fn    -> RED U1 U2 FW
#   N9 `_sc_post_small` recording a declared callee only -> RED U2
#   N10 `_mv_arg_call` without the `_pm_copies` test     -> RED C3 (a `*P` parameter refused)
#   N11 `_mv_dst_sid` without the `*P` (GLPTRP) test     -> RED C3 (a `*P` variable refused)
#   N12 `_mv_asg_src` not typing the refused source      -> RED S5 S8 MA W4 (the warning after the error)
# 6.7.12 (issues/archived/2026-10-14-6711-rows-not-run-on-hardware.md item 4): C2 runs on ecb / ach / cass / pi in
# tests/tcyr/crossos/struct_return_shape_controls.tcyr.
#
# 6.7.13 — AXIS SR: `ret2(a, b)` IN A FN DECLARED TO RETURN A NAMED STRUCT IS REFUSED IN EVERY CLASS (D22 A, the
# user's decision, 2026-10-15; issues/2026-10-14-ret2-in-struct-returning-fn-takes-multi-value-path.md), as the
# tuple literal `return (a, b);` is since 6.7.11 (D39): over 16 B the result pointer was never written (the
# repro read 0 on x86_64 / aarch64 / cx / PE), at 8 B or less the second value was dropped (1), at 9-16 B the
# words came back by ABI coincidence (the C2 control's old producer). Once (a generic's instances), in sync (the
# next statement's own error), at the ret2 — `return ret2(..)` too, where the 9-16 B return's "got `this
# expression`" yields to it; over 16 B the retptr arm's own refusal speaks first (once). A dyn keeps its V7 text;
# an #inline fn's ret2 replayed in a struct fn and a closure's own ret2 there still run — and an #inline fn's
# `return ret2(..);` replayed in a 9-16 B struct fn, refused "got `this expression`" through 6.7.12, now runs
# (SC1r). C2's producer says `return p;` now.
#   N13 `_ret2_in_struct` answering 0 at once           -> RED SR1 SR2 SR3 SR3m SR3g SR3d SR5 SR5b SR6 (BUILT / one line), every leg
#   N14 ... without its GIDEP test                      -> RED SC1 (the replayed #inline ret2 refused), every leg
#   N15 ... without its `_tn_once`                      -> RED SR3g (two lines), every leg
#   N16 `_ret_struct_pair` reporting a ret2 return too  -> RED SR5b (two lines), SC1r (refused "got `this
#                                                           expression`", as through 6.7.12), every leg
#
# 6.7.13 — AXIS RT: `return mk(..);` OF A MULTI-VALUE CALL IN A FN RETURNING A STRUCT OF 8 B OR LESS is refused by
# name, the fifth destination (D25 A, the user's decision, 2026-10-15;
# issues/2026-10-14-small-struct-fn-returns-multi-value-call.md): the call's FIRST value was returned as the struct's
# word (the repro exited 3 on x86_64 / aarch64 / cx / PE) — `a multi-value call 'mk' is not returned as struct 'P1' -
# bind it first: ...`, at the call, parentheses transparent; the 9-16 B and over-16 B classes keep their own texts; a
# `: P1` callee and a one-value callee still run.
#   N17 `_ret_mv_fwd` without its small-struct arm       -> RED RT1 RT2 RT3 RT4 RT7 RT8 (BUILT), every leg
#
# 6.7.13 — AXIS DP: `*p = mk(..);` THROUGH A `p: *S` copies what `G = mk(..);` copies (D4), so a multi-value call is
# refused into it as into `G` (D26 A, the user's decision, 2026-10-15;
# issues/2026-10-14-multi-value-call-stored-through-struct-pointer-decision.md): it stored the FIRST value as the
# struct's word (the repro exited 50 on x86_64 / aarch64 / cx / PE: GT2 = {5, 0}) — `is not assigned to struct 'P2'`,
# at every size, a method, wrapped, a classic-for step and top level; a `*i64` still takes the first value.
#   N18 `_mv_dst_sid` answering 0 under the override again -> RED DP1-DP9 DPu (BUILT), every leg
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=multi_value_into_named_struct
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
# refused <name> <fragment> <what>: the source is $T/<name>.cyr (written by `src`)
refused() {
    rows=$((rows + 1))
    for leg in $(legs); do
        compile "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        w=$(grep -c '^warning' "$T/$1.$leg.err" || true)
        if [ "$crc" -eq 0 ]; then bad "$1 $3 ($leg): BUILT (rc 0)"
        elif ! grep -qF "$2" "$T/$1.$leg.err"; then bad "$1 $3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne 1 ]; then bad "$1 $3 ($leg): $n error lines (want 1)"
        elif [ "$w" -ne 0 ]; then bad "$1 $3 ($leg): a warning beside the refusal: $(grep '^warning' "$T/$1.$leg.err" | head -1 || true)"
        elif [ -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): refused, but a binary was written"
        else ok "$1 $3 ($leg): refused once"; fi
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
src() { cat > "$T/$1.cyr"; }

ARG="is not a struct 'P' argument - bind it first: \`var a, b = mk(..);\`"
DCL="does not initialize struct 'P' - bind it first: \`var a, b = mk(..);\`"
FLD="is not stored into a struct 'P' field - bind it first: \`var a, b = mk(..);\`"
ASG="is not assigned to struct 'P' - bind it first: \`var a, b = mk(..);\`"

# --- the issue's four repro files, verbatim (docs/development/issues/repros/2026-10-09-multi-value-call-into-named-struct-*.cyr)
src S1 <<'EOF'
# A multi-value call passed to a by-value parameter of a NAMED struct over 8 B.
# Expected: a compile error naming the call (as a tuple parameter's R17 does), or 34.
# Actual (6.6.0 - 6.7.7): compiles clean, SIGSEGV (rc 139) on x86_64 and aarch64.
struct P { a; b; }
fn mk(a): (i64, i64) { return (a, a + 1); }
fn take(t: P): i64 { return t.a * 10 + t.b; }
fn f(): i64 { return take(mk(3)); }
syscall(60, f());
EOF
refused S1 "a multi-value call 'mk' $ARG" "repro 1, the argument"
src S2 <<'EOF'
# The method form: `b.mk(3)` returns two values; `take` takes a named 16 B struct by value.
# Expected: a compile error naming the call, or 34. Actual (6.7.0 - 6.7.7): compiles clean, rc 139.
struct P { a; b; }
struct B { z; }
impl B { fn mk(self, a): (i64, i64) { return (a, a + 1); } }
fn take(t: P): i64 { return t.a * 10 + t.b; }
fn f(): i64 { var b = B { 0 }; return take(b.mk(3)); }
syscall(60, f());
EOF
refused S2 "a multi-value call 'mk' is not a struct 'P' argument - bind it first: \`var a, b = b.mk(..);\`" "repro 2, the method argument"
src S3 <<'EOF'
# A struct-typed declaration initialised from a multi-value call.
# Expected: a compile error naming the call, or 3. Actual (6.6.0 - 6.7.7): compiles clean, rc 139.
struct P { a; b; }
fn mk(a): (i64, i64) { return (a, a + 1); }
fn f(): i64 { var p: P = mk(3); return p.a; }
syscall(60, f());
EOF
refused S3 "a multi-value call 'mk' $DCL" "repro 3, the declaration"
src S4 <<'EOF'
# A struct-typed FIELD stored from a multi-value call.
# Expected: a compile error naming the call (as a tuple field's R17 does), or 34.
# Actual (6.6.0 - 6.7.7): compiles clean, exits 30 (b is 0) on x86_64 and aarch64.
struct P { a; b; }
fn mk(a): (i64, i64) { return (a, a + 1); }
struct H { p: P; }
fn f(): i64 { var h: H; h.p = mk(3); return h.p.a * 10 + h.p.b; }
syscall(60, f());
EOF
refused S4 "a multi-value call 'mk' $FLD" "repro 4, the field store"
# --- the struct-var issue's repro, verbatim (issues/archived/2026-10-09-struct-var-from-multi-value-call-crashes.md)
src V1 <<'EOF'
struct P { a; b; }
fn g2(x): (i64, i64) { return (x, x + 1); }
fn main(): i64 { var p: P = g2(5); return p.a * 10 + p.b; }
var r = main(); syscall(60, r);
EOF
refused V1 "a multi-value call 'g2' does not initialize struct 'P' - bind it first: \`var a, b = g2(..);\`" "the struct-var issue's repro"

H='struct P { a; b; }
struct P1 { a; }
struct B { z; }
struct H { p: P; }
struct H1 { p: P1; }
impl B { fn mk(self, a): (i64, i64) { return (a, a + 1); } }
impl B { fn mku(self, a) { return (a, a + 1); } }
fn mk(a): (i64, i64) { return (a, a + 1); }
fn mku(a) { return (a, a + 1); }
fn take(t: P): i64 { return t.a * 10 + t.b; }
fn take1(t: P1): i64 { return t.a; }'
row() { printf '%s\n%s\n' "$H" "$2" > "$T/$1.cyr"; }

row S5 'fn f(): i64 { var p: P; p = mk(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused S5 "a multi-value call 'mk' $ASG" "the assignment (it warned, then stored one word)"
row U1 'fn f(): i64 { return take(mku(3)); }
syscall(60, f());'
refused U1 "a multi-value call 'mku' is not a struct 'P' argument - bind it first: \`var a, b = mku(..);\`" "an undeclared callee (pass 1 counted 2 values)"
row U2 'fn f(): i64 { var b = B { 0 }; return take(b.mku(3)); }
syscall(60, f());'
refused U2 "a multi-value call 'mku' is not a struct 'P' argument" "an undeclared method"
row FW 'fn f(): i64 { return take(late(3)); }
fn late(a) { return (a, a + 1); }
syscall(60, f());'
refused FW "a multi-value call 'late' is not a struct 'P' argument" "an undeclared callee defined after the call"
row H8 'fn f(): i64 { var p: P1 = mk(3); return p.a; }
syscall(60, f());'
refused H8 "a multi-value call 'mk' does not initialize struct 'P1'" "8 B: the declaration (the handle line's form)"
row A8 'fn f(): i64 { return take1(mk(3)); }
syscall(60, f());'
refused A8 "a multi-value call 'mk' is not a struct 'P1' argument" "8 B: the argument"
row M8 'fn f(): i64 { var b = B { 0 }; return take1(b.mk(3)); }
syscall(60, f());'
refused M8 "a multi-value call 'mk' is not a struct 'P1' argument" "8 B: the method argument"
row F8 'fn f(): i64 { var h: H1; h.p = mk(3); return h.p.a; }
syscall(60, f());'
refused F8 "a multi-value call 'mk' is not stored into a struct 'P1' field" "8 B: the field"
row S8 'fn f(): i64 { var p: P1; p = mk(3); return p.a; }
syscall(60, f());'
refused S8 "a multi-value call 'mk' is not assigned to struct 'P1'" "8 B: the assignment"
row MD 'fn f(): i64 { var b = B { 0 }; var p: P = b.mk(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused MD "a multi-value call 'mk' does not initialize struct 'P' - bind it first: \`var a, b = b.mk(..);\`" "a method into the declaration"
row MF 'fn f(): i64 { var b = B { 0 }; var h: H; h.p = b.mk(3); return h.p.a * 10 + h.p.b; }
syscall(60, f());'
refused MF "a multi-value call 'mk' is not stored into a struct 'P' field - bind it first: \`var a, b = b.mk(..);\`" "a method into the field"
row MA 'fn f(): i64 { var b = B { 0 }; var p: P; p = b.mk(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused MA "a multi-value call 'mk' is not assigned to struct 'P'" "a method into the assignment"
row GZ 'var p: P = mk(3);
syscall(60, p.a * 10 + p.b);'
refused GZ "a multi-value call 'mk' $DCL" "a global in the declaration zone"
row GL 'var z = 0;
z = 1;
var p: P = mk(3);
syscall(60, p.a * 10 + p.b);'
refused GL "a multi-value call 'mk' $DCL" "a global after the first statement"
row GA 'var p = P { 0, 0 };
fn f(): i64 { p = mk(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused GA "a multi-value call 'mk' $ASG" "a global assigned in a fn"
row GT 'var p = P { 0, 0 };
p = mk(3);
syscall(60, p.a * 10 + p.b);'
refused GT "a multi-value call 'mk' $ASG" "a global assigned at top level"
row GF 'var h = H { 0, 0 };
fn f(): i64 { h.p = mk(3); return h.p.a * 10 + h.p.b; }
syscall(60, f());'
refused GF "a multi-value call 'mk' $FLD" "a global's field"
row TA 'syscall(60, take(mk(3)));'
refused TA "a multi-value call 'mk' $ARG" "an argument at top level"
row W1 'fn f(): i64 { return take((mk(3))); }
syscall(60, f());'
refused W1 "a multi-value call 'mk' $ARG" "the argument, parenthesised"
row W2 'fn f(): i64 { var p: P = (mk(3)); return p.a * 10 + p.b; }
syscall(60, f());'
refused W2 "a multi-value call 'mk' $DCL" "the declaration, parenthesised"
row W3 'fn f(): i64 { var h: H; h.p = (mk(3)); return h.p.a * 10 + h.p.b; }
syscall(60, f());'
refused W3 "a multi-value call 'mk' $FLD" "the field, parenthesised"
row W4 'fn f(): i64 { var p: P; p = (mk(3)); return p.a * 10 + p.b; }
syscall(60, f());'
refused W4 "a multi-value call 'mk' $ASG" "the assignment, parenthesised"
row NA 'fn f(): i64 { return take(t: mk(3)); }
syscall(60, f());'
refused NA "a multi-value call 'mk' $ARG" "a named argument"
row GC 'fn mkg<T>(a: T): (T, T) { return (a, a + 1); }
fn f(): i64 { return take(mkg<i64>(3)); }
syscall(60, f());'
refused GC "a multi-value call 'mkg' is not a struct 'P' argument" "a generic callee as the argument"
row GD 'fn mkg<T>(a: T): (T, T) { return (a, a + 1); }
fn f(): i64 { var p: P = mkg<i64>(3); return 7; }
syscall(60, f());'
refused GD "a multi-value call 'mkg' does not initialize struct 'P'" "a generic callee into the declaration (it built, p an untyped word)"
row GS 'struct Box<T> { a: T; b: T; }
fn takeb(t: Box<i64>): i64 { return t.a * 10 + t.b; }
fn f(): i64 { return takeb(mk(3)); }
syscall(60, f());'
refused GS "a multi-value call 'mk' is not a struct 'Box" "a generic struct parameter"
row FS 'fn f(): i64 { var p: P = P { 0, 0 }; for (var i = 0; i < 1; p = mk(3)) { i = i + 1; } return p.a * 10 + p.b; }
syscall(60, f());'
refused FS "a multi-value call 'mk' $ASG" "a classic-for step"
row T3 'struct Q { a; b; c; }
fn takeq(t: Q): i64 { return t.a * 10 + t.b; }
fn mk3(a): (i64, i64, i64) { return (a, a + 1, a + 2); }
fn f(): i64 { return takeq(mk3(3)); }
syscall(60, f());'
refused T3 "a multi-value call 'mk3' is not a struct 'Q' argument - bind it first: \`var a, b, c = mk3(..);\`" "three values into a 24 B struct"
# R17 keeps its own text for a tuple parameter
row R17 'fn takt(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return takt(mk(3)); }
syscall(60, f());'
refused R17 "a multi-value call 'mk' is not a tuple argument" "control: a tuple parameter is R17's"

# --- controls: compiled and run
row C1 'fn mkp(a): P { var p = P { a, a + 1 }; return p; }
fn f(): i64 { return take(mkp(3)); }
syscall(60, f());'
runs C1 34 "control: a callee declared \`: P\` (the issue's)"
row C2 'fn mp(x): P { var p: P = P { x, x + 1 }; return p; }
fn f(): i64 { var p: P = mp(3); var h: H; h.p = mp(3); var q: P = P { 0, 0 }; q = mp(3);
    return take(mp(3)) + p.a * 10 + p.b + h.p.a * 10 + h.p.b + q.a * 10 + q.b - 102; }
syscall(60, f());'
runs C2 34 "control: a \`: P\` fn's \`return p;\` into an argument, a declaration, a field, an assignment (its \`return (x, y);\` refused since 6.7.11, its \`ret2(x, y)\` since 6.7.13: axis SR)"
row C3 'fn rd(q: *P): i64 { return q.a * 10 + q.b; }
fn mkq(p): (i64, i64) { return (p, 1); }
fn f(): i64 { var s = P { 3, 4 }; var q: *P = mkq(&s); var r: *P = &s; r = mkq(&s); return rd(mkq(&s)) + q.a + r.b - 7; }
syscall(60, f());'
runs C3 34 "control: a \`*P\` parameter, declaration and assignment take the first value as a pointer"
row C4 'fn f(): i64 { var a, b = mk(3); var p = P { a, b }; return take(p); }
syscall(60, f());'
runs C4 34 "control: the hint — bind the values, then build the struct"
row C5 'fn f(): i64 { var x = mk(3); x = mk(x + 1); return x; }
syscall(60, f());'
runs C5 4 "control: a scalar still takes the first value"
cat > "$T/C6.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
fn mk(a): (i64, i64) { return (a, a + 1); }
fn tk(s: Str): i64 { return 7; }
fn f(): i64 { return tk(mk(3)); }
syscall(60, f());
EOF
runs C6 7 "control: a \`Str\` handle parameter takes a word"

# --- axis SR (6.7.13, D22 A): `ret2(a, b)` in a fn declared to return a named struct, every class ---
R2S="returns that struct — \`ret2\` writes two values"
# the issue's two repros, verbatim (issues/2026-10-14-ret2-in-struct-returning-fn-takes-multi-value-path.md)
printf 'struct P3 { x; y; z; }\nfn f(a, b): P3 { ret2(a, b); }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x * 100 + q.y * 10 + q.z; }\nsyscall(60, main());\n' > "$T/SR1.cyr"
refused SR1 "2:18: a fn returning the struct \`P3\` $R2S" "repro 1 verbatim: over 16 B (it read 0, the result pointer never written)"
printf 'struct S8 { v; }\nfn f(a, b): S8 { ret2(a, b); }\nfn main(): i64 { var q: S8 = f(1, 2); return q.v; }\nsyscall(60, main());\n' > "$T/SR2.cyr"
refused SR2 "2:18: a fn returning the struct \`S8\` $R2S" "repro 2 verbatim: 8 B (it read 1, the second value dropped)"
row SR3 'fn mp(x): P { ret2(x, x + 1); }
fn f(): i64 { var p: P = mp(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused SR3 "a fn returning the struct \`P\` $R2S" "9-16 B: the form that worked by the registers' coincidence"
row SR3m 'impl B { fn mkp(self, x): P { ret2(x, x + 1); } }
fn f(): i64 { var b = B { 0 }; var p: P = b.mkp(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused SR3m "a fn returning the struct \`P\` $R2S" "a method"
row SR3g 'fn mg<T>(x: T): P { ret2(x, x + 1); }
fn f(): i64 { var p: P = mg<i64>(3); var q: P = mg<i32>(3); return p.a * 10 + q.b; }
syscall(60, f());'
refused SR3g "a fn returning the struct \`P\` $R2S" "a generic with two instances: once"
row SR3d 'var runs = 0;
fn md(x): P1 { defer { runs = runs + 1; } ret2(x, x + 1); }
fn f(): i64 { var p: P1 = md(3); return p.a + runs; }
syscall(60, f());'
refused SR3d "a fn returning the struct \`P1\` $R2S" "8 B through a defer"
printf 'trait Show { fn show(self): i64; }\nfn mk(a, b): dyn Show { ret2(a, b); }\nsyscall(60, 0);\n' > "$T/SR4.cyr"
refused SR4 "a fn returning dyn Show returns a whole dyn - \`return (a, b)\` / \`ret2\` would write its words" "a dyn keeps its V7 text"
for leg in $(legs); do
    if grep -qF "$R2S" "$T/SR4.$leg.err"; then bad "SR4 the struct text beside the dyn's ($leg)"; else ok "SR4 no struct text ($leg)"; fi
done
row SR5 'fn m1(x): P1 { return ret2(x, x + 1); }
fn f(): i64 { var p: P1 = m1(3); return p.a; }
syscall(60, f());'
refused SR5 "a fn returning the struct \`P1\` $R2S" "\`return ret2(..);\` at 8 B (it compiled: 3)"
row SR5b 'fn mp(x): P { return ret2(x, x + 1); }
fn f(): i64 { var p: P = mp(3); return p.a * 10 + p.b; }
syscall(60, f());'
refused SR5b "a fn returning the struct \`P\` $R2S" "\`return ret2(..);\` at 9-16 B: once, not beside \"got \`this expression\`\""
printf 'struct P3 { x; y; z; }\nfn f(a, b): P3 { return ret2(a, b); }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x; }\nsyscall(60, main());\n' > "$T/SR5c.cyr"
refused SR5c "struct-return fn: return must be a bare local identifier" "\`return ret2(..);\` over 16 B: the retptr arm's refusal, once"
# in sync: the next statement's own error is reported (two lines)
row SR6 'fn m1(x): P1 { ret2(x, x + 1); syscall(60, nosuch); }
fn f(): i64 { var p: P1 = m1(3); return p.a; }
syscall(60, f());'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" SR6
    n=$(grep -c '^error' "$T/SR6.$leg.err" || true)
    if [ "$crc" -ne 0 ] && [ "$n" -eq 2 ] && grep -qF "$R2S" "$T/SR6.$leg.err" && grep -qF "undefined variable 'nosuch'" "$T/SR6.$leg.err"; then ok "SR6 in sync: the ret2 refusal and the next statement's own error ($leg)"
    else bad "SR6 in sync ($leg): rc $crc, $n error lines: $(grep '^error' "$T/SR6.$leg.err" | tr '\n' '|')"; fi
done
# --- axis RT (6.7.13, D25 A): `return mk(..);` of a multi-value call in a fn returning a struct of 8 B or less ---
RTT="is not returned as struct 'P1' - bind it first:"
# the issue's repro, verbatim
printf 'struct P1 { a; }\nfn mk(a): (i64, i64) { return (a, a + 1); }\nfn g(): P1 { return mk(3); }\nfn f(): i64 { var p: P1 = g(); return p.a; }\nsyscall(60, f());\n' > "$T/RT1.cyr"
refused RT1 "3:21: a multi-value call 'mk' $RTT \`var a, b = mk(..);\`" "the repro verbatim (it exited 3)"
row RT2 'fn g(): P1 { return mku(3); }
fn f(): i64 { var p: P1 = g(); return p.a + 10; }
syscall(60, f());'
refused RT2 "a multi-value call 'mku' $RTT \`var a, b = mku(..);\`" "an undeclared callee pass 1 counted (it exited 13)"
row RT3 'fn g(): P1 { var b = B { 0 }; return b.mk(3); }
fn f(): i64 { var p: P1 = g(); return p.a; }
syscall(60, f());'
refused RT3 "a multi-value call 'mk' $RTT \`var a, b = b.mk(..);\`" "a method callee"
row RT4 'fn g(): P1 { return ((mk(3))); }
fn f(): i64 { var p: P1 = g(); return p.a; }
syscall(60, f());'
refused RT4 "a multi-value call 'mk' $RTT" "wrapped, depth 2"
row RT7 'fn mk3(a): (i64, i64, i64) { return (a, 1, 2); }
fn g(): P1 { return mk3(3); }
fn f(): i64 { var p: P1 = g(); return p.a; }
syscall(60, f());'
refused RT7 "a multi-value call 'mk3' $RTT \`var a, b, c = mk3(..);\`" "three values: the hint binds three"
row RT8 'fn mkg<T>(a: T): (T, T) { return (a, a + 1); }
impl P1 { fn m(self): P1 { return mkg<i64>(self.a); } }
fn f(): i64 { var q = P1 { 3 }; var p: P1 = q.m(); return p.a; }
syscall(60, f());'
refused RT8 "a multi-value call 'mkg' $RTT" "a generic callee, in a method"
row RT9 'fn g(): P { return mk(3); }
fn f(): i64 { var p: P = g(); return p.a; }
syscall(60, f());'
refused RT9 "a fn returning the 9-16 byte struct \`P\` is returned in two registers" "9-16 B: its own text, unchanged"
row RT10 'struct Q { a; b; c; }
fn g(): Q { return mk(3); }
fn f(): i64 { var p: Q = g(); return p.a; }
syscall(60, f());'
refused RT10 "struct-return fn: return must be a bare local identifier, or a call to a fn returning the same struct" "over 16 B: its own text, unchanged"
row RT5 'fn mk1(a): P1 { var p = P1 { a }; return p; }
fn g(): P1 { return mk1(7); }
fn f(): i64 { var p: P1 = g(); return p.a; }
syscall(60, f());'
runs RT5 7 "control: a \`: P1\` callee forwarded"
row RT6 'fn one(a) { return a + 4; }
fn g(): P1 { return one(3); }
fn f(): i64 { var p: P1 = g(); return p.a; }
syscall(60, f());'
runs RT6 7 "control: a one-value callee (an untyped word stays the struct's word)"
# --- axis DP (6.7.13, D26 A): `*p = mk(..);` through a `p: *S` ---
# the issue's repro, verbatim
printf 'struct P2 { x; y; }\nvar GT2 = P2 { 0, 0 };\nfn mv(): (i64, i64) { return (5, 6); }\nfn main(): i64 { var p: *P2 = &GT2; *p = mv(); return GT2.x * 10 + GT2.y; }\nsyscall(60, main());\n' > "$T/DP1.cyr"
refused DP1 "4:42: a multi-value call 'mv' is not assigned to struct 'P2' - bind it first: \`var a, b = mv(..);\`" "the repro verbatim (it exited 50)"
row DP2 'struct S3 { a: i8; b: i8; c: i8; }
fn f(): i64 { var s: S3; var p: *S3 = &s; *p = mk(3); return s.a; }
syscall(60, f());'
refused DP2 "a multi-value call 'mk' is not assigned to struct 'S3'" "3 B"
row DP3 'fn f(): i64 { var q = P1 { 0 }; var p: *P1 = &q; *p = mk(3); return q.a; }
syscall(60, f());'
refused DP3 "a multi-value call 'mk' is not assigned to struct 'P1'" "8 B"
row DP4 'fn f(): i64 { var q = P { 0, 0 }; var p: *P = &q; *p = mk(3); return q.a * 10 + q.b; }
syscall(60, f());'
refused DP4 "a multi-value call 'mk' $ASG" "16 B"
row DP5 'struct Q { a; b; c; }
fn mk3(a): (i64, i64, i64) { return (a, 1, 2); }
fn f(): i64 { var q = Q { 0, 0, 0 }; var p: *Q = &q; *p = mk3(3); return q.a; }
syscall(60, f());'
refused DP5 "a multi-value call 'mk3' is not assigned to struct 'Q' - bind it first: \`var a, b, c = mk3(..);\`" "24 B, three values"
row DP6 'fn f(): i64 { var b = B { 0 }; var q = P1 { 0 }; var p: *P1 = &q; *p = b.mk(3); return q.a; }
syscall(60, f());'
refused DP6 "a multi-value call 'mk' is not assigned to struct 'P1' - bind it first: \`var a, b = b.mk(..);\`" "a method callee"
row DP7 'fn f(): i64 { var q = P { 0, 0 }; var p: *P = &q; *p = (mk(3)); return q.a; }
syscall(60, f());'
refused DP7 "a multi-value call 'mk' $ASG" "wrapped: \`*p = (mk(3));\`"
row DP8 'fn f(): i64 { var q = P { 0, 0 }; var p: *P = &q; for (var i = 0; i < 1; *p = mk(3)) { i = i + 1; } return q.a; }
syscall(60, f());'
refused DP8 "a multi-value call 'mk' $ASG" "a classic-for step"
row DP9 'var q = P { 0, 0 };
var p: *P = &q;
*p = mk(3);
syscall(60, q.a);'
refused DP9 "a multi-value call 'mk' $ASG" "at top level"
row DPu 'fn f(): i64 { var q = P { 0, 0 }; var p: *P = &q; *p = mku(3); return q.a; }
syscall(60, f());'
refused DPu "a multi-value call 'mku' is not assigned to struct 'P' - bind it first: \`var a, b = mku(..);\`" "an undeclared callee pass 1 counted"
row DP10 'fn f(): i64 { var x = 0; var r: *i64 = &x; *r = mk(3); return x; }
syscall(60, f());'
runs DP10 3 "control: \`*r = mk(3);\` through a \`*i64\` takes the first value"
row SC1 '#inline
fn two(a, b) { ret2(a, b); }
fn mp(x): P { var a, b = two(x, x + 1); var p: P = P { a, b }; return p; }
fn f(): i64 { var p: P = mp(3); return p.a * 10 + p.b; }
syscall(60, f());'
runs SC1 34 "control: an #inline fn's ret2 replayed in a struct fn"
# SC1r — the `return ret2(..);` spelling of SC1's callee: the replay is judged by the CALLER's class, so through
# 6.7.12 the 9-16 B return's "got `this expression`" refused it (base b13d3598: 2:28); since `_ret_struct_pair`
# yields to a ret2 value (6.7.13) it compiles and runs. The review probe, verbatim; on ecb / ach / cass / pi as
# tests/tcyr/crossos/struct_return_shape_controls.tcyr's SC1r.
src SC1r <<'EOF'
struct Pt { x; y; }
#inline fn two(a) { return ret2(a, a + 1); }
fn mk(): Pt { var a, b = two(3); var p = Pt { a, b }; return p; }
fn m(): i64 { var p = mk(); return p.x * 10 + p.y; }
syscall(60, m());
EOF
runs SC1r 34 "control: an #inline fn's \`return ret2(..);\` replayed in a 9-16 B struct fn (refused through 6.7.12)"
row SC2 'include "lib/fnptr.cyr"
fn mp(x): P { var cl = |y| { ret2(y, y + 1); }; var a, b = fncall1(cl, x); var p: P = P { a, b }; return p; }
fn f(): i64 { var p: P = mp(3); return p.a * 10 + p.b; }
syscall(60, f());'
runs SC2 34 "control: a closure's own ret2 inside a struct fn"

[ "$rows" -ge 75 ] || bad "only $rows rows ran (floor 75)"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails check(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run (named above); the rest passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G ($rows rows) — a multi-value call into a named struct (argument, method argument, declaration, field, assignment; every size, both top-level zones, wrapped, named, generic, a for step) is refused by name on x86_64 / aarch64 / cx / PE; the crossing, \`*P\`, \`Str\` and scalar controls run on all four; 6.7.13: \`ret2\` in a struct fn (every class), \`return mk(..)\` from an 8 B struct fn and \`*p = mk(..)\` through a \`*S\` refused"
