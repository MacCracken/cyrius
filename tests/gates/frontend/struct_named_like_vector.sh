#!/bin/sh
# tests/gates/frontend/struct_named_like_vector.sh — 6.7.14
#
# A PROGRAM'S OWN STRUCT NAMED LIKE A VECTOR TYPE IS THAT STRUCT EVERYWHERE, A PARAMETER TYPE INCLUDED (the user's
# decision D41 A, 2026-10-16). `struct f32v4 { a; b; c; }` was the struct as a local, a field, a return type and behind
# a `*`, but `_classify_param_type` read the vector names before any struct, so `fn g(v: f32v4)` took the SIMD vector:
# `v.a` was refused "SIMD vector has no named fields" (and `g(s)` "value-form SIMD arg type mismatch (callee expects
# f32v4)"), on every target — since 6.7.13 for `struct f32v8` too, which compiled through 6.7.12 (exit 5). A vector
# name is the vector now only while the program declares no struct or union of that name (`_cpt_vec`, `_cpt_vdecl`),
# read from the TOKENS so pass 1's signature prescan of a fn above the declaration and pass 2's definition agree.
# Filed: docs/development/issues/2026-10-16-struct-named-like-a-float-vector-is-a-vector-only-as-a-parameter.md
#
#   R  the filed repro, verbatim: exit 5 — on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine)
#   N  the same program with `struct f64v2` / `f64v4` / `f32v8` / `i32v4` in place of f32v4: 5 — every leg; and with
#      each of the other seven integer vector names (u32v4 i16v8 u16v8 i8v16 u8v16 i64v2 u64v2): 5 — x86_64
#   U  `union f32v4 { a; b: i32; }` as a by-value parameter: 9 — every leg
#   D  DECLARED BELOW (the two scans agree): D1 the struct last, the call after the fn's definition: 12; D2 an 8-byte
#      `struct f32v4 { a; }` declared last and called ABOVE the fn's definition (the pass-1 signature): 5, as a struct
#      `Pq` does (a struct over 8 B there is issues/2026-10-17-forward-call-struct-parameter-of-struct-declared-below-
#      fn.md, any name) — every leg
#   L  with lib/simd.cyr included, `struct f32v8` / `struct f64v2` as a parameter: 5 (the stdlib's functions of that
#      name see the struct, as the decision says) — x86_64
#   C  controls: a `struct f64v2` inside an `#ifdef` that is off leaves `v: f64v2` the vector (42); a program with
#      `struct i32v4` and `struct f64v4` keeps `i64v2` / `f64v2` parameters vectors (each name its own: 42 + 42) —
#      every leg; tests/tcyr/crossos/simd_param_then_scalar.tcyr (no such struct: the vector parameters) — every leg
#   T  tests/tcyr/crossos/struct_named_like_vector.tcyr (struct f32v4 / f64v2 / f64v4 / f32v8 / i32v4 and union
#      u8v16 by value at 8 / 16 / 24 / 32 B, a return, a `*` parameter, a field, a copy, a scalar after them, a vector
#      name no struct takes) on every leg: "N passed, 0 failed (N total)", N derived from the file; the release
#      gate's cross-OS leg runs it on ecb / ach / cass / pi
#
# MUTATION LEDGER (2026-10-17; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run FROM
# that copy with CYCC= it, so every leg's compiler carries the mutant):
#   MV1 the fix reverted (`_cpt_vec` answers the vector  -> RED R, N (every name), U, D1, L (refused "SIMD vector
#       class whatever the program declares)                has no named fields"), D2 ("value-form SIMD arg type
#                                                           mismatch"), T (the file does not build) — 55 rows; C green
#   MV2 the struct table instead of the tokens            -> RED D2: refused "value-form SIMD arg type mismatch (callee
#       (`_cpt_byname`, FINDSTRUCT: pass 1 misses a          expects f32v4)" on x86_64 / IR / aarch64 / cx (pass 1 read
#       struct declared below the fn)                        the parameter a vector, pass 2 the struct), PE exits 1
#   MV3 every integer vector name shares one bit          -> RED C2 (42, aarch64 106, for 84: `i64v2` taken as a struct
#       (`_cpt_vbit` 16 for each)                            parameter, silently) and T (vn_vec_ok 0) on every leg
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_named_like_vector
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

TC=tests/tcyr/crossos/struct_named_like_vector.tcyr
TC2=tests/tcyr/crossos/simd_param_then_scalar.tcyr
for f in "$TC" "$TC2"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
if [ "$N" -lt 5 ]; then echo "FAIL: $G: only $N rows in $TC (floor 5) — rows were lost"; exit 1; fi
N2=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC2")
if [ "$N2" -lt 10 ]; then echo "FAIL: $G: only $N2 rows in $TC2 (floor 10) — rows were lost"; exit 1; fi

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

# xr <id> <src> <want> <what> [legs]: the exit on every leg (or the legs named)
xr() {
    _legs=${5:-"x86 x86:CYRIUS_IR=3 $OTHER"}
    for leg in $_legs; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}

echo "R. the filed repro, verbatim (D41 A)"
cat > "$D/r.cyr" <<'X'
struct f32v4 { a; b; c; }
fn g(v: f32v4): i64 { return v.a; }
fn main(): i64 { var s: f32v4; s.a = 5; return g(s); }
syscall(60, main());
X
xr R "$D/r.cyr" 5 "struct f32v4 as g's parameter"

echo "N. the repro with every other vector name"
for nm in f64v2 f64v4 f32v8 i32v4; do
    sed "s/f32v4/$nm/g" "$D/r.cyr" > "$D/n_$nm.cyr"
    xr "N $nm" "$D/n_$nm.cyr" 5 "struct $nm as g's parameter"
done
for nm in u32v4 i16v8 u16v8 i8v16 u8v16 i64v2 u64v2; do
    sed "s/f32v4/$nm/g" "$D/r.cyr" > "$D/n_$nm.cyr"
    xr "N $nm" "$D/n_$nm.cyr" 5 "struct $nm as g's parameter" x86
done

echo "U. a union named like a vector"
cat > "$D/u.cyr" <<'X'
union f32v4 { a; b: i32; }
fn g(v: f32v4): i64 { return v.a; }
fn main(): i64 { var s: f32v4; s.a = 9; return g(s); }
syscall(60, main());
X
xr U "$D/u.cyr" 9 "union f32v4 as g's parameter"

echo "D. declared below the fn (pass 1's signature and pass 2's definition agree)"
cat > "$D/d1.cyr" <<'X'
fn g(v: f32v4): i64 { return v.a + v.c; }
fn main(): i64 { var s: f32v4; s.a = 5; s.c = 7; return g(s); }
struct f32v4 { a; b; c; }
syscall(60, main());
X
xr D1 "$D/d1.cyr" 12 "struct f32v4 declared last, called after g's definition"
cat > "$D/d2.cyr" <<'X'
fn main(): i64 { var s: f32v4; s.a = 5; return g(s); }
fn g(v: f32v4): i64 { return v.a; }
struct f32v4 { a; }
syscall(60, main());
X
xr D2 "$D/d2.cyr" 5 "an 8-byte struct f32v4 declared last, called above g's definition"

echo "L. with lib/simd.cyr included (x86_64)"
for nm in f32v8 f64v2; do
    { printf 'include "lib/syscalls.cyr"\ninclude "lib/simd.cyr"\n'; sed "s/f32v4/$nm/g" "$D/r.cyr"; } > "$D/l_$nm.cyr"
    xr "L $nm" "$D/l_$nm.cyr" 5 "struct $nm beside lib/simd.cyr" x86
done

echo "C. controls: the vector stays the vector"
cat > "$D/c1.cyr" <<'X'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
#ifdef CYRIUS_NO_SUCH_FLAG
struct f64v2 { a; b; c; }
#endif
fn hi(v: f64v2): i64 { return load64(&v + 8); }
fn main(): i64 { var b: f64v2 = f64v2_make(3, 42); return hi(b); }
syscall(60, main());
X
xr C1 "$D/c1.cyr" 42 "a struct f64v2 in an #ifdef that is off: v: f64v2 is the vector"
cat > "$D/c2.cyr" <<'X'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct i32v4 { a; b; }
struct f64v4 { a; b; c; d; }
fn hi(v: i64v2): i64 { return load64(&v + 8); }
fn hf(v: f64v2): i64 { return load64(&v + 8); }
fn main(): i64 { var b: i64v2 = i64v2_make(3, 42); var c: f64v2 = f64v2_make(3, 42); return hi(b) + hf(c); }
syscall(60, main());
X
xr C2 "$D/c2.cyr" 84 "struct i32v4 / f64v4 declared: i64v2 / f64v2 parameters stay vectors"

# tf <id> <file> <rows> <what>: a values file on every leg
tf() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/t_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/t_$n.err")"
        elif [ "$RC" -eq 0 ] && [ "$LAST" = "$3 passed, 0 failed ($3 total)" ]; then ok "$1 $leg: $LAST"
        else bad "$1 $leg: exit $RC, '$LAST' (want '$3 passed, 0 failed ($3 total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
    done
}
tf C3 "$TC2" "$N2" "$TC2 (no struct named like a vector)"
echo "T. $TC ($N rows)"
tf T "$TC" "$N" "$TC"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a struct named like a vector type is the program's struct as a parameter too (D41 A): the filed repro (R), the other vector names (N), a union (U), declared below (D), beside lib/simd.cyr (L), the vector controls (C) and $N rows (T) on x86_64 / IR / aarch64 / cx / PE"
