#!/bin/sh
# tests/gates/codegen/struct_named_like_stdlib_handle.sh — 6.7.14
#
# A PROGRAM'S OWN `struct Result` / `struct Option` / `struct Tagged` IS A PLAIN STRUCT.
# (issues/2026-10-15-user-struct-named-result-option-tagged-is-a-handle-by-name.md)
#
# The parameter classifier `_classify_param_type` (src/frontend/parse_fn.cyr) answered the stdlib's
# handle classes 3 / 4 / 5 for the NAMES `Result` / `Option` / `Tagged`, whatever the program declared:
# a 16 B `struct Result { a; b; }` was a one-word value parameter (`_param_wants_struct_ptr` 0), the
# caller pushed its first field, and the callee read `x.b` through it — x86_64 139, aarch64 139, cx 252,
# PE 5 where 7 is right; a method with an untyped `self` was "no struct type in scope for 'self'". Since
# 6.7.14 the three names are handles only while no struct takes the name (`_cpt_byname`, FINDSTRUCT 0 —
# lib/result.cyr's `enum Result<T, E>: stack` and lib/tagged.cyr's `enum Option: stack` never enter the
# struct table), as the return classifier has always read them. `Str` stays a handle by name.
#
# LEGS (every compiler built from this tree by $CYCC): x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
# CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine, a private prefix).
#   R  the filed repro VERBATIM, and its `Option` / `Tagged` spellings: exit 7
#   C1 a program declaring its own Result / Option / Tagged (16 B and 24 B by-value parameters, a 4 B one,
#      a `: Result` return) builds BYTE-IDENTICAL to the same program with the three structs renamed
#      (same-length names): the names decide nothing. Compile only, on every compiler.
#   C2 a program using the stdlib's Result / Option (lib/result.cyr, lib/tagged.cyr: `Ok` / `Err` / `Some`
#      / `None` returns, `t: Result` / `o: Option` / `x: Tagged` parameters) builds BYTE-IDENTICAL to its
#      spelling with those parameters untyped — the stdlib's handle reading is unchanged — and runs to 36.
#      (The 6.7.14 differential: the 635-file .tcyr corpus, 103 of them including lib/result.cyr or
#      lib/tagged.cyr, compiled byte-identical before and after the fix.)
#   T  tests/tcyr/crossos/struct_named_like_stdlib_handle.tcyr (16 B: parameters, methods typed and
#      untyped, globals, top level) and its _8b twin: "N passed, 0 failed (N total)", N derived from each
#      file with a floor; the release gate's cross-OS leg runs both on ecb / ach / cass / pi
#
# MUTATION LEDGER (2026-10-17, the gate run as CYCC=<the lane's compiler before the fix>, 6.7.14 structs
# S1 @ ede6b7e18):
#   M0 the fix reverted -> RED 37: R all 15 (x86_64 / IR=3 139, aarch64 139, cx 252, PE 5); C1 all 8
#      (the builds differ; they run to 139 / 139 / 220 / 5); T 14 — both files fail to build on every leg
#      ("no struct type in scope for 'self'": the untyped-self methods). C2 green (the stdlib side is what
#      must not move).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_named_like_stdlib_handle
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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

TC1=tests/tcyr/crossos/struct_named_like_stdlib_handle.tcyr
TC2=tests/tcyr/crossos/struct_named_like_stdlib_handle_8b.tcyr
for f in "$TC1" "$TC2"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
rows() { awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$1"; }
N1=$(rows "$TC1"); N2=$(rows "$TC2")
if [ "$N1" -lt 19 ]; then echo "FAIL: $G: only $N1 rows in $TC1 (floor 19) — rows were lost"; exit 1; fi
if [ "$N2" -lt 10 ]; then echo "FAIL: $G: only $N2 rows in $TC2 (floor 10) — rows were lost"; exit 1; fi

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
# errof <out>: the first error line of the build of <out> (a PE build writes <out>.exe.err).
errof() { cat "$1.err" "$1.exe.err" 2> /dev/null | grep -m1 'error' || true; }
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"

echo "R. the filed repro, verbatim, and its Option / Tagged spellings: exit 7 (139 / 252 / 5 before)"
cat > "$D/r_Result.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Result { a; b; }
fn g(x: Result): i64 { return x.b; }
fn main() { var t: Result = Result { 5, 7 }; return g(t); }
var r = main();
syscall(SYS_EXIT, r);
EOF
sed 's/Result/Option/g' "$D/r_Result.cyr" > "$D/r_Option.cyr"
sed 's/Result/Tagged/g' "$D/r_Result.cyr" > "$D/r_Tagged.cyr"
for nm in Result Option Tagged; do
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf 'R_%s_%s' "$nm" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$D/r_$nm.cyr" "$D/$n"
        if [ "$RC" -eq -1 ]; then bad "R $nm $leg: did not build: $(errof "$D/$n")"
        elif [ "$RC" -eq 7 ]; then ok "R $nm $leg: exit 7"
        else bad "R $nm $leg: exit $RC, want 7"; fi
    done
done

echo "C1. own Result / Option / Tagged build byte-identical to the same structs renamed"
cat > "$D/c1_own.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Result { a; b; }
struct Option { a; b; c; }
struct Tagged { v: i32; w: i32; }
fn g(x: Result): i64 { return x.b; }
fn go(x: Option): i64 { return x.c; }
fn gt(x: Tagged): i64 { return x.w; }
fn mk(): Result { var r: Result; r.a = 1; r.b = 2; return r; }
fn main(): i64 {
    var t: Result = Result { 5, 7 };
    var o: Option = Option { 1, 2, 3 };
    var q: Tagged = Tagged { 4, 6 };
    var m = mk();
    var u: Result;
    u = t;
    return g(u) + go(o) * 10 + gt(q) + m.b;
}
syscall(SYS_EXIT, main());
EOF
sed -e 's/Result/Rexult/g; s/Option/Optiox/g; s/Tagged/Taggex/g' "$D/c1_own.cyr" > "$D/c1_ren.cyr"
for leg in x86 $OTHER; do
    build_leg "$leg" "$D/c1_own.cyr" "$D/c1_own_$leg" || { bad "C1 $leg: the own-named program did not build: $(grep -m1 'error' "$D/c1_own_$leg.err")"; continue; }
    build_leg "$leg" "$D/c1_ren.cyr" "$D/c1_ren_$leg" || { bad "C1 $leg: the renamed program did not build: $(grep -m1 'error' "$D/c1_ren_$leg.err")"; continue; }
    if cmp -s "$D/c1_own_$leg" "$D/c1_ren_$leg"; then ok "C1 $leg: byte-identical"
    else bad "C1 $leg: the own-named program builds differently from the renamed one (a name chose the ABI)"; fi
done
for leg in x86 $OTHER; do
    run_leg "$leg" "$D/c1_own.cyr" "$D/c1_run_$leg"
    if [ "$RC" -eq 45 ]; then ok "C1 $leg: runs to 45"; else bad "C1 $leg: exit $RC, want 45"; fi
done

echo "C2. the stdlib's Result / Option: typed parameters build byte-identical to untyped, and run to 36"
cat > "$D/c2_typed.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/result.cyr"
include "lib/tagged.cyr"
fn mk(n): Result { if (n > 0) { return Ok(n); } return Err(5); }
fn tagof(t: Result): i64 { if (t == Ok) { return 1; } return 2; }
fn opt(n): Option { if (n > 0) { return Some(n); } return None; }
fn osome(o: Option): i64 { if (o == None) { return 0; } return 3; }
fn tg(x: Tagged): i64 { return x + 1; }
fn main(): i64 {
    var t, v = mk(4);
    var a = tagof(t);
    var u, w = mk(0);
    var b = tagof(u);
    var o, ov = opt(2);
    var c = osome(o);
    return a + b * 10 + v + w + c + ov + tg(0);
}
syscall(SYS_EXIT, main());
EOF
sed -e 's/(t: Result)/(t)/; s/(o: Option)/(o)/; s/(x: Tagged)/(x)/' "$D/c2_typed.cyr" > "$D/c2_untyped.cyr"
if cmp -s "$D/c2_typed.cyr" "$D/c2_untyped.cyr"; then bad "C2: the untyped spelling did not change the source (sed)"; fi
for leg in x86 $OTHER; do
    build_leg "$leg" "$D/c2_typed.cyr" "$D/c2_t_$leg" || { bad "C2 $leg: the typed program did not build: $(grep -m1 'error' "$D/c2_t_$leg.err")"; continue; }
    build_leg "$leg" "$D/c2_untyped.cyr" "$D/c2_u_$leg" || { bad "C2 $leg: the untyped program did not build: $(grep -m1 'error' "$D/c2_u_$leg.err")"; continue; }
    if cmp -s "$D/c2_t_$leg" "$D/c2_u_$leg"; then ok "C2 $leg: byte-identical"
    else bad "C2 $leg: the stdlib Result / Option / Tagged parameters no longer build as the untyped ones"; fi
done
for leg in x86 $OTHER; do
    run_leg "$leg" "$D/c2_typed.cyr" "$D/c2_run_$leg"
    if [ "$RC" -eq 36 ]; then ok "C2 $leg: runs to 36"; else bad "C2 $leg: exit $RC, want 36"; fi
done

for pair in "$TC1:$N1" "$TC2:$N2"; do
    TC=${pair%%:*}; N=${pair##*:}
    echo "T. $TC ($N rows)"
    for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
        n=$(printf '%s_%s' "$(basename "$TC" .tcyr)" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$TC" "$D/t_$n"
        if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(errof "$D/t_$n")"
        elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
        else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
    done
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a program's own struct Result / Option / Tagged is a plain struct (R, C1) and the stdlib's stay handles byte-identical (C2), $N1 + $N2 rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
