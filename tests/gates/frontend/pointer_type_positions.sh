#!/bin/sh
# tests/gates/frontend/pointer_type_positions.sh — 6.7.17 (the user's D93, 2026-10-22)
#
# A POINTER TYPE IS A POINTER TYPE IN EVERY POSITION THAT TAKES ONE. The lanes met two positions that read one `*`
# and then a name, where `var p: **i64` / `*fn( .. )` are types elsewhere:
#   P  (D93) a slice's pointer element — `var s: [**i64] = 0;` was "expected ']', got '*'", `[**fn(i64): i64]` added
#      "undefined variable 'i64'", `slice<**i64>` was "expected '=', got '*'". `_tn_slice_ptr_el`
#      (src/frontend/parse_types.cyr) now steps every `*` and reads the rest as `[*T]` reads T: the same 8-byte element,
#      the same refusals by name.
# Measured on the 6.7.17 wave-1 integration (l6717-integ 45c7ff467), x86_64; the parse is every target's.
#
#   P   the repro verbatim (`[**i64]`) and `slice<**i64>`, `[***i64]`, `[**fn(i64): i64]`, `slice<**fn>`: no error, no
#       warning, exit 3 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine); PL each under --syntax-only (what
#       `cyrius lint` runs): rc 0, silent
#   PG  a refusal behind two `*` is the one-star element's one line: an unknown name (PG1, PG2), a fn-pointer type's
#       unknown name (PG3), a pointer to a slice (PG4), a generic struct's unknown argument (PG5); PG6 a control (a
#       declaration-zone global's slice: the zone's line, as before)
#   T   each values file on x86_64 (default, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine):
#       "N passed, 0 failed (N total)", N derived from the file (one row per `assert_eq(`):
#       tests/tcyr/crossos/slice_pointer_element_stars.tcyr (P)
#
# MUTATION LEDGER (2026-10-22; a scratch copy of the tree, this gate run from that copy with CYCC=<its compiler>;
# measured):
#   MP0 the tree before D93 (l6717-integ 45c7ff467:     -> RED 36: P1-P5 on every leg (20) and P1L-P5L (5) ("expected
#       its src and build/cycc; `_tn_slice_ptr_el`        ']', got '*'" / "expected '=', got '*'"), PG1-PG5 (that line,
#       stepping one `*`)                                 PG2 PG3 PG5 also "undefined variable 'Nope'"), T on every leg
#                                                         (6: did not build) — PG6 (the zone's line) is a control
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=pointer_type_positions
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

# The values files and their floors: one row per `assert_eq(` call (none defines it). A floor keeps a gutted file from
# passing.
TCS="tests/tcyr/crossos/slice_pointer_element_stars.tcyr:10"

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
# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build), LAST (the last
# line of its output, CR stripped) and ERRF (the compile's stderr file).
run_leg() {
    RC=-1; LAST=''; ERRF="$3.err"
    if [ "$1" = pe ]; then ERRF="$3.exe.err"; build_leg pe "$2" "$3.exe" || return 0
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

# builds <name> <what> <want-exit> <body>: no error and no warning on every leg, exit <want-exit>; then --syntax-only
# rc 0 and silent
builds() {
    printf '%b' "$4" > "$D/$1.cyr"
    for leg in x86 $OTHER; do
        run_leg "$leg" "$D/$1.cyr" "$D/b_$1_$leg"
        w=$(grep -cE '^(error|warning)' "$ERRF" 2>/dev/null || true)
        if [ "$RC" -eq -1 ]; then bad "$2 $leg: did not build: $(grep -h -m1 '^error' "$ERRF" 2>/dev/null)"
        elif [ "$w" -ne 0 ]; then bad "$2 $leg: $w diagnostic line(s): $(grep -E '^(error|warning)' "$ERRF" | head -2 | tr '\n' '|')"
        elif [ "$RC" -eq "$3" ]; then ok "$2 $leg: exit $3, nothing said"
        else bad "$2 $leg: exit $RC, want $3"; fi
    done
    rc=0; timeout 60 "$CC" --syntax-only < "$D/$1.cyr" > /dev/null 2> "$D/$1.lint" || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$D/$1.lint" ]; then ok "${2%% *}L: --syntax-only rc 0, silent"
    else bad "${2%% *}L: --syntax-only rc $rc: $(head -2 "$D/$1.lint" | tr '\n' '|')"; fi
}
# refused <name> <want-line> <what> <body>: the compile fails with exactly that one error line (`L:C: text`, the
# `error:<source>:` prefix implied), no warning, and no binary
refused() {
    printf '%b' "$4" > "$D/$1.cyr"
    rc=0; timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    grep -E '^(error|warning)' "$D/$1.err" > "$D/$1.got" || true
    printf 'error:<source>:%s\n' "$2" > "$D/$1.want"
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want \"$2\""
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! cmp -s "$D/$1.got" "$D/$1.want"; then bad "$3: got $(tr '\n' '|' < "$D/$1.got") want $2"
    elif [ -s "$D/$1.bin" ]; then bad "$3: refused, but a binary was written"
    else ok "$3"; fi
}

F='fn main(): i64 { '
E=' return 3; }\nsyscall(60, main());\n'
NT="unknown type 'Nope'"

echo "P. a slice's pointer element behind any number of \`*\` (D93): no error, no warning, exit 3"
builds p1 "P1 the repro verbatim, [**i64]" 3 "${F}var s: [**i64] = 0;${E}"
builds p2 "P2 slice<**i64>" 3 "${F}var s: slice<**i64> = 0;${E}"
builds p3 "P3 [***i64]" 3 "${F}var s: [***i64] = 0;${E}"
builds p4 "P4 [**fn(i64): i64]" 3 "${F}var s: [**fn(i64): i64] = 0;${E}"
builds p5 "P5 slice<**fn> (bare)" 3 "${F}var s: slice<**fn> = 0;${E}"

echo "PG. a refusal behind two \`*\` is the one-star element's one line"
refused PG1 "1:28: $NT as the target of pointer 's'" "PG1 [**Nope]" "${F}var s: [**Nope] = 0;${E}"
refused PG2 "1:33: $NT as the target of pointer 's'" "PG2 slice<**Nope>" "${F}var s: slice<**Nope> = 0;${E}"
refused PG3 "1:31: $NT for variable 's'" "PG3 [**fn(Nope): i64]" "${F}var s: [**fn(Nope): i64] = 0;${E}"
refused PG4 "1:28: a pointer to a slice is not a type (6.7.8: slices are fn-locals) - pass &s as a plain pointer and read slice_ptr / slice_len" \
    "PG4 [**[u8]]" "${F}var s: [**[u8]] = 0;${E}"
refused PG5 "2:32: $NT as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)" \
    "PG5 [**Box<Nope>]" "struct Box<T> { v: T; }\n${F}var s: [**Box<Nope>] = 0;${E}"
refused PG6 "1:8: a slice cannot be declared in the declaration zone (6.7.8: slices are fn-locals) - declare it in a fn; a top-level slice after the first statement is used through slice_ptr / slice_len" \
    "PG6 control: a declaration-zone [**i64] is the zone's line, once" 'var G: [**i64] = 0;\nsyscall(60, 3);\n'

for tc in $TCS; do
    TC=${tc%%:*}; FLOOR=${tc##*:}
    [ -f "$TC" ] || { bad "T: $TC is missing"; continue; }
    N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
    if [ "$N" -lt "$FLOOR" ]; then bad "T: only $N rows in $TC (floor $FLOOR) — rows were lost"; continue; fi
    echo "T. $TC ($N rows)"
    for leg in x86 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
        n=$(printf '%s_%s' "$(basename "$TC" .tcyr)" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$TC" "$D/t_$n"
        if [ "$RC" -eq -1 ]; then bad "T $leg: $TC did not build: $(grep -h -m1 '^error' "$ERRF" 2>/dev/null)"
        elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
        else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
    done
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a pointer type behind any number of \`*\` is a slice's pointer element (P, PG; the user's D93) and the values files (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
