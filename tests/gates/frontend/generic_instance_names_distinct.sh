#!/bin/sh
# tests/gates/frontend/generic_instance_names_distinct.sh — 6.7.11
#
# NO TWO TYPE ARGUMENTS SHARE A GENERIC INSTANCE. An instance is named `Base$<fragment>` and
# FINDFN / FINDSTRUCT dedup by that name, so two type arguments with one fragment share one body:
# the second call runs the first's. `_append_conc_name` spelled i8 / i16 / i32 / i64 and fell
# through for f64 (conc -9), leaving a bare `i` — the name of a `struct i` too. So `gen<f64>` and
# `gen<i>` both minted `gen$i` (the filed repro exited 88, 96 is right; 176 swapped), and a generic
# struct's instances shared it the same way (`Box<f64>` / `Box<i>`). Spelling f64 `f64` alone would
# only move the collision to a `struct f64`, which a type argument binds before the scalar. The
# user's decision C (2026-10-13): f64 is `gen$f64`, and a struct named exactly like a scalar
# (i8 / i16 / i32 / i64 / f64) is marked with a byte no identifier holds, `gen$.f64` — every other
# instance keeps its name. 6.3.33 - 6.7.10, every target.
# Filed: docs/development/issues/archived/2026-10-12-generic-f64-instance-name-collides-with-struct-i.md
#
#   R1 the filed repro, verbatim: exit 96 (88 before), on x86_64, x86_64 CYRIUS_IR=3, aarch64
#      (qemu), cx (cxvm) and PE (wine); R2 its swapped form: 96 (176 before)
#   S  `sizeof(Box<f64>) * 10 + sizeof(Box<i>)` with `struct i { a; b; c; }`: 192 (176 before), every leg
#   F  `struct f64 { a; b; c; }`: the scalar `gs(1.5)` and the struct `gs<f64>(p)` / `gp<f64>(&p)`
#      run their own instances — 128 (F1), and 104 with the struct call first (F2), every leg
#   I  `struct i32` + `gen<i32>` binds the struct, as before: 32, every leg
#   N  x86_64, the names a coverage dump shows: `gen$f64` and `gen$i` (R1); `gs$f64`, `gs$.f64`,
#      `gp$.f64` (F1); `gen$.i32` (I)
#   T  tests/tcyr/crossos/generic_instance_names.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#
# MUTATION LEDGER (2026-10-14; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0  the fix reverted (the tree before it)       -> RED R1 (88), R2 (176) and S (176) on every leg; N R1
#                                                     (`2 gen$i`, no `gen$f64`), F1 (`gs$i`) and I; T: the
#                                                     file does not build on any leg (`bx.v.c`: Box<i> got
#                                                     Box<f64>'s layout); F / I exits green (no collision)
#   M1  f64 spelled, no `.` marker on a struct      -> RED F1 (112) on every leg; F2 on every leg (139 on
#                                                     x86 / IR / aarch64, cx exit 1, PE exit 5: the scalar
#                                                     call ran the struct's body); N F1 (`2 gs$f64`) and I;
#                                                     R / S / T green (no struct named like a scalar)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_instance_names_distinct
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
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/generic_instance_names.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=18
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

# The filed repro, verbatim, and its swapped form.
cat > "$D/r1.cyr" <<'EOF'
struct i { a; b; }
fn gen<T>(x: *T): i64 { return sizeof(T); }
var a = gen<f64>(0);
var b = gen<i>(0);
var r = a * 10 + b;
syscall(60, r);
EOF
cat > "$D/r2.cyr" <<'EOF'
struct i { a; b; }
fn gen<T>(x: *T): i64 { return sizeof(T); }
var b = gen<i>(0);
var a = gen<f64>(0);
var r = a * 10 + b;
syscall(60, r);
EOF
cat > "$D/s.cyr" <<'EOF'
struct i { a; b; c; }
struct Box<T> { v: T; n; }
var r = sizeof(Box<f64>) * 10 + sizeof(Box<i>);
syscall(60, r);
EOF
cat > "$D/f1.cyr" <<'EOF'
struct f64 { a; b; c; }
fn gs<T>(x: T): i64 { return sizeof(T); }
fn gp<T>(x: *T): i64 { return sizeof(T); }
fn main(): i64 {
    var p = f64 { 1, 2, 3 };
    var a = gs(1.5);
    var b = gs<f64>(p);
    var c = gp<f64>(&p);
    return a * 10 + b + c;
}
syscall(60, main());
EOF
cat > "$D/f2.cyr" <<'EOF'
struct f64 { a; b; c; }
fn gs<T>(x: T): i64 { return sizeof(T); }
fn main(): i64 {
    var p = f64 { 1, 2, 3 };
    var b = gs<f64>(p);
    var a = gs(1.5);
    return a * 10 + b;
}
syscall(60, main());
EOF
cat > "$D/i.cyr" <<'EOF'
struct i32 { a; b; c; d; }
fn gen<T>(x: *T): i64 { return sizeof(T); }
var b = gen<i32>(0);
syscall(60, b);
EOF

# xrow <id> <src> <want> <what>: the exit on every leg
xrow() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: exit $3"
        else bad "$1 $leg: exit $RC, want $3 ($4)"; fi
    done
}
echo "R. the filed repro, verbatim, and swapped: gen<f64> and gen<i> (struct i, 16 B) are 8 and 16"
xrow R1 "$D/r1.cyr" 96 "88: gen<i> ran the f64 instance, both were gen\$i"
xrow R2 "$D/r2.cyr" 96 "176: gen<f64> ran the struct's instance"
echo "S. a generic struct: Box<f64> (16 B) and Box<i> (32 B) are two instances"
xrow S "$D/s.cyr" 192 "176: Box<i> took Box<f64>'s layout"
echo "F. struct f64: a scalar f64 (gs(1.5)) and the struct (gs<f64>(p), gp<f64>(&p)) are two instances"
xrow F1 "$D/f1.cyr" 128 "112: gs<f64>(p) ran the scalar instance"
xrow F2 "$D/f2.cyr" 104 "the scalar call ran the struct's instance"
echo "I. struct i32: gen<i32> binds the program's struct, as before"
xrow I "$D/i.cyr" 32 "gen<i32> did not bind struct i32"

echo "N. x86_64: the instance names a coverage dump shows"
# nrow <id> <src> <want-file>: the dump, exactly
nrow() {
    rm -f "$D/$1.cov"
    if ! CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D/$1.cov" "$CC" < "$2" > "$D/n_$1" 2> "$D/n_$1.err"; then
        bad "N $1: did not build: $(grep -m1 'error' "$D/n_$1.err")"; return 0
    fi
    chmod +x "$D/n_$1"; timeout 60 "$D/n_$1" > /dev/null 2>&1 || true
    if [ -f "$D/$1.cov" ] && cmp -s "$D/$1.cov" "$3"; then ok "N $1: $(sed 1d "$3" | sed 's/^[0-9]* <source>:[0-9]* //' | tr '\n' ' ')"
    else bad "N $1: the dump is '$(tr '\n' '|' < "$D/$1.cov" 2> /dev/null)', want '$(tr '\n' '|' < "$3")'"; fi
}
HDR='# cyrius-coverage 1'
printf '%s\n1 <source>:2 gen$f64\n1 <source>:2 gen$i\n' "$HDR" > "$D/r1.want"
printf '%s\n1 <source>:4 main\n1 <source>:2 gs$f64\n1 <source>:2 gs$.f64\n1 <source>:3 gp$.f64\n' "$HDR" > "$D/f1.want"
printf '%s\n1 <source>:2 gen$.i32\n' "$HDR" > "$D/i.want"
nrow R1 "$D/r1.cyr" "$D/r1.want"
nrow F1 "$D/f1.cyr" "$D/f1.want"
nrow I "$D/i.cyr" "$D/i.want"

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
echo "PASS: $G — a scalar type argument never shares a generic instance with a struct: f64 is \$f64 and a struct named like a scalar \$.<name> — the filed repro and its swap (R), Box (S), struct f64 (F), struct i32 (I) on x86_64 / IR / aarch64 / cx / PE, the names (N) on x86_64, and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
