#!/bin/sh
# tests/gates/codegen/simd_pointer_param.sh — 6.7.11
#
# A POINTER-TO-VECTOR PARAMETER (`p: *f64v2`) IS A POINTER: one integer word whose step is the
# vector's size, address-passed like `p: *S`. A vector local passed to it passes its ADDRESS, as a
# struct passed to a `*T` parameter does (6.6.20), and a vector of ANOTHER type is refused by name, as
# a struct of another type is (6.7.3) — the user's decision, 2026-10-13: (a). Both parameter scans
# consumed the `*` and classified the bare vector name, so the parameter was a VALUE-form vector (XMM /
# V registers; a by-pointer copy-in on Win64) and every caller routed it as one: `rd(&b)` was refused
# "value-form SIMD arg must be a local IDENT (inline-replay path)", and `rd(b)` compiled and the body
# dereferenced lane 0's bits (exit 139 on x86_64 and aarch64; cx "guest address out of range").
# Measured on 6.6.10 - 6.7.10. Filed: docs/development/issues/archived/2026-10-10-pointer-to-vector-parameter-is-value-form.md
#
#   R1 the filed repro (the valid call, refused) verbatim: exits 1 on x86_64, x86_64 CYRIUS_IR=3,
#      aarch64 (qemu), cx (cxvm) and PE (wine)
#   R2 the filed repro `rd(b)` verbatim: compiles and exits 0 on the same legs (139 before)
#   R3 the decision: `rd(b)` reads b (lane 0 = 42), `rd(&b)` too (exit 84), on the same legs
#   Y  a vector local of ANOTHER type into a `*V` parameter: exactly one error line, "cannot pass 'f' to a
#      parameter of a different vector type in a call to 'rd'" — f32v4 into `*f64v2`, f64v2 into `*f64v4`,
#      i32v4 into `*f32v4`, i64v2 into `*i32v4`, a forward call, a method, a generic, a tail position,
#      a parenthesised argument; Yw the first on PE (the Win64 arm takes the same route)
#   S  `p[1]` on a `*f64v2` parameter is refused with a `*f64v2` local's text (the element is a vector)
#   T  tests/tcyr/crossos/simd_pointer_param.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call) — `*f64v2` / `*f64v4` / `*f32v4` / `*i32v4` /
#      `*i64v2`, `p + 1` stepping 16 / 32, writes, mixed signatures (the XMM / V ordinals count only the
#      value-form vectors), a stack-passed one, a method, a generic, a tail position, a forward call,
#      `fncall1` / `callptr` with `&b` (an integer register now); the release gate's cross-OS leg runs
#      it on ecb / ach / cass / pi
#
#
# 6.7.12 (D27, the user, 2026-10-15: B — "pass the address for the *V shapes; another pointer kind refused by
# name"): a vector VALUE that is not a named local into a `*V` parameter passes an address — a call result
# through a frame temp (`_sarg_vec_call`), `*pv` as pv (`_dlo_vec`, the step word's vector) — and a vector
# local into a pointer of another kind is refused by name; `*f32v8` is a `*V` (`_ptr_vclass`). They passed
# lane 0's bits as the address (139 / 139 / a cx fault / PE 5; on PE `rp(b)` into `*Pt` alone passed `&b` by
# accident and ran — it is refused now too); x86_64 refused the `*V` shapes through 6.7.10 (an x86_64 regression
# in 6.7.11). Filed: docs/development/issues/2026-10-13-vector-value-into-pointer-
# parameter-passes-lane-bits.md
#   R4 the filed repro 1 verbatim (`rd(mkv(42, 7))` + `rd(*pb)`): exit 42 on x86_64 / IR=3 / aarch64 / cx / PE
#   R5 the filed repro 2 verbatim: `rp(b)` and `ri(b)` refused by name, once each (two lines, no binary), on
#      x86_64 and PE; R5e `r8(e)` (and `r8(&e)`) alone exits 42 on x86_64 / IR=3 / aarch64 / cx / PE
#   Y10-Y12 refused by name, once: `rd(mkv4(..))` (a call result of another vector type), `rd(*pq)` (a `*f32v4`
#      into `*f64v2`), `ri(b)` (a vector local into `*i64`); Y13 a top-level `rd(mkv(..))` (no frame for the
#      temp); Yw2 the Y10-Y12 refusals on PE
#   T  also carries the D27 rows (`sp_vrows`)
#
# MUTATION LEDGER (2026-10-15, 6.7.12; each change alone in the tree, this gate run with CYCC=<its 2-stage
# mutant>; measured):
#   M4  `_sarg_vec_call` answers 0 (no call-result arm)    -> RED 15: R4 (139 / 139 / 139 / cx 253 / PE 5),
#                                                             Y10 Y13 Yw2a (compiled), T on every leg
#   M5  `_dlo_vec` answers 0 (no vector park)              -> RED 14: R4 (as M4), Y11 Yw2b, T on every leg
#   M6  `_vec_kind_err` reports nothing                    -> RED 4: R5 x86 / PE (compiled), Y12 Yw2c
#   M7  `_ptr_vclass` without f32v8                        -> RED 14: R5 (a third line: `r8(e)` refused as a
#                                                             pointer of another kind), R5e on every leg, T
#
# MUTATION LEDGER (2026-10-13; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<its 2-stage mutant>; measured):
#   M0  the fix reverted (the slot-open scans and call)   -> RED 33: R1 (refused "value-form SIMD arg must
#                                                             be a local IDENT"; PE exit 5), R2 (139 / 139 /
#                                                             139 / cx 1 / PE 5), R3, Y1 Y4-Y8 Yw (compiled),
#                                                             Y2 Y3 Y9 (the old text, or a cascade), S1 ("it
#                                                             is not a typed array, a *T .."), T on every leg
#   M1  `_param_class` without class 9 (a `*V` classed as -> RED 32: as M0 but Yw (the value-form path wins;
#       its vector again, both scans)                        the Win64 arm still meets `_sarg_vec_ptr`)
#   M2  `_param_wants_struct_ptr` without the `*V` arm    -> RED 27: R2 R3 Y1-Y9 Yw and T on
#       (no address bit: `rd(b)` pushes lane 0)              every leg; R1 green (`&b` is a pointer)
#   M3  `_sarg_vec_ptr` without the type check            -> RED 10: Y1-Y9 Yw (they compile)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=simd_pointer_param
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

TC=tests/tcyr/crossos/simd_pointer_param.tcyr
R1=docs/development/issues/repros/2026-10-10-pointer-to-vector-parameter-is-value-form.cyr
R2=docs/development/issues/repros/2026-10-10-pointer-to-vector-parameter-is-value-form-value.cyr
R4=docs/development/issues/repros/2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.cyr
R5=docs/development/issues/repros/2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits-other-kinds.cyr
for f in "$TC" "$R1" "$R2" "$R4" "$R5"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=51
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
# exit_rows <tag> <src> <want> <what>: on every leg
exit_rows() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/r_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: did not build: $(grep -h -m1 'error' "$D/r_$n.err" "$D/r_$n.exe.err" 2>/dev/null | head -1)"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: exit $3"
        else bad "$1 $leg: exit $RC, want $3 ($4)"; fi
    done
}

echo "R1. the filed repro, verbatim: \`rd(&b)\` into \`p: *f64v2\` compiles and reads b (exit 1)"
exit_rows R1 "$R1" 1 "1 = rd(&b) read lane 0"
echo "R2. the filed repro, verbatim: \`rd(b)\` compiles and runs (exit 0; 139 before)"
exit_rows R2 "$R2" 0 "rd(b) passes b's address"
echo "R3. the decision: \`rd(b)\` and \`rd(&b)\` both read b's lane 0 (exit 84)"
cat > "$D/r3.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    return rd(b) + rd(&b);
}
var rc = main();
syscall(60, rc);
EOF
exit_rows R3 "$D/r3.cyr" 84 "42 + 42"

# refused <name> <what> <body> [pe|x86 [frag]]: compile fails with exactly one error line holding the
# refusal (`FRAG`, the vector-type one, unless a fragment is given), and no binary
FRAG="to a parameter of a different vector type in a call to"
refused() {
    printf '%b' "$3" > "$D/$1.cyr"
    rc=0
    fr=${5:-$FRAG}
    if [ "${4:-}" = pe ]; then CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    else timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; fi
    n=$(grep -c '^error' "$D/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$2: compiled (rc 0) — want \".. $fr ..\""
    elif [ "$n" -ne 1 ]; then bad "$2: $n error lines, want exactly 1: $(grep '^error' "$D/$1.err" | head -3 | tr '\n' '|')"
    elif ! grep '^error' "$D/$1.err" | grep -qF -- "$fr"; then bad "$2: wrong refusal: $(grep '^error' "$D/$1.err" | head -1)"
    elif [ -s "$D/$1.bin" ]; then bad "$2: refused, but a binary was written"
    else ok "$2"; fi
}
H='include "lib/syscalls.cyr"\ninclude "lib/simd.cyr"\n'
E='var rc = main();\nsyscall(60, rc);\n'
echo "Y. a vector of another type into a \`*V\` parameter: refused by name, once"
refused Y1 "Y1 f32v4 into *f64v2" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f) + 1; }\n${E}"
refused Y2 "Y2 f64v2 into *f64v4" "${H}fn rd(p: *f64v4): i64 { return load64(p); }\nfn main(): i64 { var f: f64v2 = f64v2_make(1, 2); return rd(f) + 1; }\n${E}"
refused Y3 "Y3 i32v4 into *f32v4" "${H}fn rd(p: *f32v4): i64 { return load32(p); }\nfn main(): i64 { var f: i32v4 = i32v4_make(1, 2, 3, 4); return rd(f) + 1; }\n${E}"
refused Y4 "Y4 i64v2 into *i32v4 (the same size)" "${H}fn rd(p: *i32v4): i64 { return load32(p); }\nfn main(): i64 { var f: i64v2; return rd(f) + 1; }\n${E}"
refused Y5 "Y5 a forward call" "${H}fn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f) + 1; }\nfn rd(p: *f64v2): i64 { return load64(p); }\n${E}"
refused Y6 "Y6 a method" "${H}struct S { k; }\nimpl S {\n    fn m(self, p: *f64v2): i64 { return load64(p); }\n}\nfn main(): i64 { var s: S; var f: f32v4 = f32v4_make(1, 2, 3, 4); return s.m(f); }\n${E}"
refused Y7 "Y7 a generic" "${H}fn rd<T>(p: *f64v2, x: T): i64 { return load64(p) + x; }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f, 1) + 1; }\n${E}"
refused Y8 "Y8 a tail position" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f); }\n${E}"
refused Y9 "Y9 a parenthesised argument" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd((f)) + 1; }\n${E}"
if [ "$WINE" = 1 ]; then
    refused Yw "Yw f32v4 into *f64v2 on PE" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f); }\n${E}" pe
fi

echo "R4. the filed repro 1, verbatim: \`rd(mkv(42, 7))\` + \`rd(*pb)\` into \`p: *f64v2\` (exit 42; 139 / cx fault / PE 5 before)"
exit_rows R4 "$R4" 42 "a temp's address and pb"
echo "R5. the filed repro 2, verbatim: \`rp(b)\` (\`*Pt\`) and \`ri(b)\` (\`*i64\`) refused by name; \`r8(e)\` (\`*f32v8\`) alone exits 42"
KFRAG="to a parameter that is not a pointer to its vector type in a call to"
for leg in x86 pe; do
    [ "$leg" = pe ] && [ "$WINE" != 1 ] && continue
    rc=0
    if [ "$leg" = pe ]; then CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$R5" > "$D/r5.bin" 2> "$D/r5.err" || rc=$?
    else timeout 60 "$CC" < "$R5" > "$D/r5.bin" 2> "$D/r5.err" || rc=$?; fi
    np=$(grep '^error' "$D/r5.err" | grep -cF "cannot pass 'b' $KFRAG 'rp'" || true)
    ni=$(grep '^error' "$D/r5.err" | grep -cF "cannot pass 'b' $KFRAG 'ri'" || true)
    n=$(grep -c '^error' "$D/r5.err" || true)
    if [ "$rc" -eq 0 ]; then bad "R5 $leg: compiled - want rp(b) and ri(b) refused"
    elif [ "$n" -ne 2 ] || [ "$np" -ne 1 ] || [ "$ni" -ne 1 ]; then bad "R5 $leg: $n error lines (rp $np, ri $ni), want one each: $(grep '^error' "$D/r5.err" | head -3 | tr '\n' '|')"
    elif [ -s "$D/r5.bin" ]; then bad "R5 $leg: refused, but a binary was written"
    else ok "R5 $leg: rp(b) and ri(b) refused by name, once each"; fi
done
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/simd.cyr"' \
  'fn r8(p: *f32v8): i64 { return load32(p); }' \
  'fn main(): i64 {' \
  '    var e: f32v8 = f32v8_make(42, 2, 3, 4, 5, 6, 7, 8);' \
  '    return r8(e) + r8(&e) - 42;' \
  '}' 'var rc = main();' 'syscall(60, rc);' > "$D/r5e.cyr"
exit_rows R5e "$D/r5e.cyr" 42 "r8(e) passes &e"
echo "Y10-Y13. refused by name, once"
refused Y10 "Y10 a call result of another vector type (f64v4 into *f64v2)" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn mkv4(a): f64v4 { var v: f64v4; return v; }\nfn main(): i64 { return rd(mkv4(1)) + 1; }\n${E}"
refused Y11 "Y11 a dereference of another vector type (*f32v4 into *f64v2)" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); var pq: *f32v4 = &f; return rd(*pq) + 1; }\n${E}"
refused Y12 "Y12 a vector local into *i64" "${H}fn ri(p: *i64): i64 { return *p; }\nfn main(): i64 { var b: f64v2 = f64v2_make(42, 7); return ri(b) + 1; }\n${E}" x86 "$KFRAG"
refused Y13 "Y13 a top-level rd(mkv(..)) (no frame for the temp)" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn mkv(a, b): f64v2 { return f64v2_make(a, b); }\nvar r1 = rd(mkv(42, 7));\nsyscall(60, r1);\n" x86 "returns a vector by value, and a vector result needs storage in a fn's frame"
if [ "$WINE" = 1 ]; then
    refused Yw2a "Yw2 Y10 on PE" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn mkv4(a): f64v4 { var v: f64v4; return v; }\nfn main(): i64 { return rd(mkv4(1)) + 1; }\n${E}" pe
    refused Yw2b "Yw2 Y11 on PE" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); var pq: *f32v4 = &f; return rd(*pq) + 1; }\n${E}" pe
    refused Yw2c "Yw2 Y12 on PE" "${H}fn ri(p: *i64): i64 { return *p; }\nfn main(): i64 { var b: f64v2 = f64v2_make(42, 7); return ri(b) + 1; }\n${E}" pe "$KFRAG"
fi

echo "S. \`p[1]\` on a \`*f64v2\` parameter is refused as on a \`*f64v2\` local (a vector element: load at p + i)"
printf '%b' "${H}fn rd(p: *f64v2): i64 { var x = p[1]; return 0; }\nfn main(): i64 { return 0; }\n${E}" > "$D/s1.cyr"
printf '%b' "${H}fn rl(): i64 { var b: f64v2; var p: *f64v2 = &b; var x = p[1]; return 0; }\nfn main(): i64 { return 0; }\n${E}" > "$D/s2.cyr"
rc1=0; "$CC" < "$D/s1.cyr" > /dev/null 2> "$D/s1.err" || rc1=$?
rc2=0; "$CC" < "$D/s2.cyr" > /dev/null 2> "$D/s2.err" || rc2=$?
m1=$(grep '^error' "$D/s1.err" | sed 's/^error:<source>:[0-9]*:[0-9]*: //')
m2=$(grep '^error' "$D/s2.err" | sed 's/^error:<source>:[0-9]*:[0-9]*: //')
if [ "$rc1" -eq 0 ] || [ -z "$m1" ]; then bad "S1 the parameter's p[1]: rc $rc1, no refusal"
elif [ "$m1" != "$m2" ]; then bad "S1 the parameter's p[1] is refused otherwise than the local's: '$m1' vs '$m2'"
else ok "S1 the parameter's p[1] is the local's refusal: $(printf '%s' "$m1" | cut -c1-70)"; fi

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -h -m1 'error' "$D/t_$n.err" "$D/t_$n.exe.err" 2>/dev/null | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`*V\` parameter is a pointer: the filed repros (R1 R2 R4 R5) and the decisions (R3, D27) on x86_64 / IR / aarch64 / cx / PE, the refusals each once (Y), the subscript (S), and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
