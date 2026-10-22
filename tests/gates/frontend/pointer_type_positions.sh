#!/bin/sh
# tests/gates/frontend/pointer_type_positions.sh — 6.7.17 (the user's D93, D94 and D105, 2026-10-22)
#
# A POINTER TYPE IS A POINTER TYPE IN EVERY POSITION THAT TAKES ONE. The lanes met two positions that read one `*`
# and then a name, where `var p: **i64` / `*fn( .. )` are types elsewhere:
#   P  (D93) a slice's pointer element — `var s: [**i64] = 0;` was "expected ']', got '*'", `[**fn(i64): i64]` added
#      "undefined variable 'i64'", `slice<**i64>` was "expected '=', got '*'". `_tn_slice_ptr_el`
#      (src/frontend/parse_types.cyr) now steps every `*` and reads the rest as `[*T]` reads T: the same 8-byte element,
#      the same refusals by name.
#   V  (D105) a slice element is any type valid elsewhere — `[*u128]` was "expected ']', got u128", `[Vec<i64>]` /
#      `[*Vec<i64>]` "expected ']', got '<'" (`slice<..>`: "expected '=', got '<'" + "undefined variable 'i64'"), while
#      `[u128]`, `[Box<i64>]` and a local `*u128` / `Vec<i64>` / `*Vec<i64>` compiled. `_tn_slice_w` reads a `Vec<T>`
#      element as `var v: Vec<T>` does (`_tn_slice_vec`, the 8-byte handle), `_tn_slice_ptr_el` a `*u128` and a
#      `*Vec<T>` (`_tn_slice_vptr`), D93's 8-byte pointer element; a closer closing more than the slice may is its error
#      (`_sl_el_over`).
#   Z  (D94) a sizeof operand — `sizeof(*i64)` was "expected identifier, got '*'" (`sizeof(*fn(i64): i64)` a cascade),
#      in an expression, a const context and `#assert` alike. `_sizeof_type` hands a `*` to `_sizeof_ptr`
#      (src/frontend/parse_types.cyr), and the const evaluator's `_ce_sizeof` (src/frontend/parse_fn.cyr) passes it on:
#      the `*`s and T stepped, T read as its own position reads it, the value 8.
# Measured on the 6.7.17 wave-1 integration (l6717-integ 45c7ff467), x86_64; the parse is every target's.
#
#   P   the repro verbatim (`[**i64]`) and `slice<**i64>`, `[***i64]`, `[**fn(i64): i64]`, `slice<**fn>`: no error, no
#       warning, exit 3 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine); PL each under --syntax-only (what
#       `cyrius lint` runs): rc 0, silent
#   PG  a refusal behind two `*` is the one-star element's one line: an unknown name (PG1, PG2), a fn-pointer type's
#       unknown name (PG3), a pointer to a slice (PG4), a generic struct's unknown argument (PG5); PG6 a control (a
#       declaration-zone global's slice: the zone's line, as before); PG7 PG8 (met landing D93) a pointer to a tuple is
#       R3's line, as `var p: *(i64, i64)`'s is — `[*(i64, i64)]` was "expected ']', got '('" through 6.7.16
#   Z   the repro verbatim (`syscall(60, sizeof(*i64));`: exit 8), `sizeof(*fn(i64): i64)`, `sizeof(**fn)`, a const,
#       an `#assert`: no error, no warning, the value on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine); ZL each under
#       --syntax-only: rc 0, silent
#   ZG  a refusal inside a sizeof operand behind a `*` is one line, sizeof's words: an unknown name (an expression, a
#       const, `#assert` — no "#assert failed" beside it), a fn-pointer type's unknown name, `*( .. )`, `*[T]`, no type
#       at all; ZG8 a control (a false `#assert` on the value 8 is "#assert failed", once)
#   ZM  (met landing D94) an `#assert`'s message is filed aside by the lexer (`_lex_is_dir_msg`, src/frontend/lex.cyr),
#       never the program's string pool — but its `sizeof ( .. )` atom stepped ONE name inside, so `sizeof(*T)`,
#       `sizeof(*fn( .. ))` and 6.6.17's `sizeof(Box<i64>)` missed the message (and the 12-token look-back missed a long
#       operand): each output carried the message's bytes. ZM1-ZM3 build on every leg with no marker in the output;
#       ZM4 a control
#   V   `[*u128]` and `[*Vec<i64>]` (the user's repros verbatim), `slice<*u128>`, `[Vec<i64>]`, `slice<Vec<Vec<i64>>>`,
#       `[**Vec<i64>]`: no error, no warning, exit 3 on x86_64 / aarch64 / cx / PE; VL each under --syntax-only
#   VG  a Vec element's refusals are a local's, one line (an unknown name, a tuple, a pointer, a second argument), and a
#       closer that closes more than the slice may is the slice's own error at it (`[Vec<i64>>]`, `slice<Vec<i64>>>`,
#       `slice<Vec<Vec<i64>>>>`'s trailing `>`)
#   T   each values file on x86_64 (default, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine):
#       "N passed, 0 failed (N total)", N derived from the file (one row per `assert_eq(`):
#       tests/tcyr/crossos/slice_pointer_element_stars.tcyr (P), tests/tcyr/crossos/sizeof_pointer_type.tcyr (Z),
#       tests/tcyr/crossos/slice_element_any_type.tcyr (V)
#
# MUTATION LEDGER (2026-10-22; a scratch copy of the tree, this gate run from that copy with CYCC=<its compiler>;
# measured):
#   MP0 the tree before D93 (l6717-integ 45c7ff467:     -> RED 36: P1-P5 on every leg (20) and P1L-P5L (5) ("expected
#       its src and build/cycc; `_tn_slice_ptr_el`        ']', got '*'" / "expected '=', got '*'"), PG1-PG5 (that line,
#       stepping one `*`)                                 PG2 PG3 PG5 also "undefined variable 'Nope'"), T on every leg
#                                                         (6: did not build) — PG6 (the zone's line) is a control
#   MZ0 the tree before D94 (2c0dade0e's src, its     -> RED 39: Z1-Z5 on every leg (20) and Z1L-Z5L (5) ("expected
#       2-stage compiler: sizeof reads a name only)       identifier, got '*'"), ZG1-ZG8 (8: that line, or "expected
#                                                         ')', got '*'" in a const context), T sizeof_pointer_type on
#                                                         every leg (6: did not build)
#   MZ1 `_ce_sizeof` not passing a `*` on               -> RED 20: Z4 Z5 on every leg and Z4L Z5L (a const, an array
#                                                         size, an #assert: "expected ')', got '*'"), ZG2 ZG3 ZG7 ZG8,
#                                                         T sizeof_pointer_type on every leg
#   MG0 the tree before the PG7 fix (720b4aee8)       -> RED 2: PG7 PG8 ("expected ']', got '('" / "expected '=', got '('")
#   MM0 the tree before the ZM fix (9314c587e)         -> RED 12: ZM1-ZM3 on every leg (the message in the output)
#   MM1 the look-back kept at 12 tokens                 -> RED 4: ZM2 on every leg (a 15-token operand)
#   MV0 the tree before D105 (l6717-integ de360e593)    -> RED 43: V1-V6 on every leg (24) and V1L-V6L (6) ("expected
#                                                         ']', got u128" / "got '<'"), VG1-VG7 (7), T
#                                                         slice_element_any_type on every leg (6: did not build)
#   MV1 `_sl_el_over` answering 0                       -> RED 3: VG5 VG6 VG7 (the over-closer compiled)
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
TCS="tests/tcyr/crossos/slice_pointer_element_stars.tcyr:10 tests/tcyr/crossos/sizeof_pointer_type.tcyr:17"
TCS="$TCS tests/tcyr/crossos/slice_element_any_type.tcyr:10"

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
refused PG7 "1:27: a tuple type cannot be a pointer target \`*( .. )\`" "PG7 [*( .. )]: R3's line, as \`var p: *(i64, i64)\`'s" "${F}var s: [*(i64, i64)] = 0;${E}"
refused PG8 "1:33: a tuple type cannot be a pointer target \`*( .. )\`" "PG8 slice<**( .. )>" "${F}var s: slice<**(i64, f64)> = 0;${E}"
refused PG6 "1:8: a slice cannot be declared in the declaration zone (6.7.8: slices are fn-locals) - declare it in a fn; a top-level slice after the first statement is used through slice_ptr / slice_len" \
    "PG6 control: a declaration-zone [**i64] is the zone's line, once" 'var G: [**i64] = 0;\nsyscall(60, 3);\n'

echo "Z. a pointer type is a sizeof operand (D94): no error, no warning, 8"
builds z1 "Z1 the repro verbatim, sizeof(*i64)" 8 'syscall(60, sizeof(*i64));\n'
builds z2 "Z2 sizeof(*fn(i64): i64)" 8 'syscall(60, sizeof(*fn(i64): i64));\n'
builds z3 "Z3 sizeof(**fn) + sizeof(***Pt) in a fn" 16 'struct Pt { x; }\nfn f(): i64 { return sizeof(**fn) + sizeof(***Pt); }\nsyscall(60, f());\n'
builds z4 "Z4 a const and an array size" 9 'const C = sizeof(*i64);\nvar a: i64[sizeof(**u8)];\na[7] = 1;\nsyscall(60, C + a[7]);\n'
builds z5 "Z5 an #assert, at top level and in a fn" 3 '#assert sizeof(*i64) == 8, "m"\nfn f(): i64 { #assert sizeof(*fn(i64): i64) == 8, "n"\n return 3; }\nsyscall(60, f());\n'

echo "ZG. a refusal inside a sizeof operand behind a \`*\`: one line, sizeof's words"
refused ZG1 "1:21: $NT in sizeof" "ZG1 sizeof(*Nope)" 'syscall(60, sizeof(*Nope));\n'
refused ZG2 "1:19: $NT in sizeof" "ZG2 a const's sizeof(*Nope)" 'const C = sizeof(*Nope);\nsyscall(60, 3);\n'
refused ZG3 "1:17: $NT in #assert sizeof" "ZG3 #assert sizeof(*Nope) (no \"#assert failed\" beside it)" '#assert sizeof(*Nope) == 8, "m"\nsyscall(60, 3);\n'
refused ZG4 "1:24: $NT in sizeof" "ZG4 sizeof(*fn(Nope): i64)" 'syscall(60, sizeof(*fn(Nope): i64));\n'
refused ZG5 "1:21: a tuple type cannot be a pointer target \`*( .. )\`" "ZG5 sizeof(*(i64, i64))" 'syscall(60, sizeof(*(i64, i64)));\n'
refused ZG6 "1:21: a pointer to a slice is not a type (6.7.8: slices are fn-locals) - pass &s as a plain pointer and read slice_ptr / slice_len" \
    "ZG6 sizeof(*[u8])" 'syscall(60, sizeof(*[u8]));\n'
refused ZG7 "1:17: expected identifier, got '+'" "ZG7 #assert sizeof(*+): no type after the \`*\`" '#assert sizeof(*+) == 8, "m"\nsyscall(60, 3);\n'
refused ZG8 "1:28: #assert failed: m" "ZG8 control: a false #assert on sizeof(*i64) is its one line" '#assert sizeof(*i64) == 4, "m"\nsyscall(60, 3);\n'

echo "ZM. an #assert's message stays out of the binary when its operand is sizeof(*T) or sizeof(T<..>)"
# nomsg <name> <what> <assert-operands>: an #assert at top level and in a fn, each with a 40-byte marker message, builds
# on every leg and no output carries the marker (the lexer files a directive's message aside); the program's own
# string literal (a second marker) is in each output — the control that the search can see a string
MK=ZMSGZMSGZMSGZMSGZMSGZMSGZMSGZMSGZMSGZMSG
nomsg() {
    printf 'struct Box<T> { v: T; w: T; }\n#assert %s, "%s";\nfn f(): i64 {\n#assert %s, "%s"\nvar s = "KEEPKEEPKEEP";\nreturn load8(s) - 72; }\nsyscall(60, f());\n' \
        "$3" "$MK" "$3" "$MK" > "$D/$1.cyr"
    for leg in x86 $OTHER; do
        o="$D/m_$1_$leg"; [ "$leg" = pe ] && o="$o.exe"
        if ! build_leg "$leg" "$D/$1.cyr" "$o" || [ ! -s "$o" ]; then bad "$2 $leg: did not build: $(grep -h -m1 '^error' "$o.err" 2>/dev/null)"; continue; fi
        n=$(LC_ALL=C grep -a -c "$MK" "$o" || true)
        k=$(LC_ALL=C grep -a -c KEEPKEEPKEEP "$o" || true)
        if [ "$n" -ne 0 ]; then bad "$2 $leg: the message is in the output ($n line(s))"
        elif [ "$k" -eq 0 ]; then bad "$2 $leg: control: the program's own string is not in the output either"
        else ok "$2 $leg: the message is not in the output, the program's string is"; fi
    done
}
nomsg zm1 "ZM1 sizeof(*i64)" 'sizeof(*i64) == 8'
nomsg zm2 "ZM2 sizeof(*fn(i64, i64): i64) == sizeof(**fn(i64): i64)" 'sizeof(*fn(i64, i64): i64) == sizeof(**fn(i64): i64)'
nomsg zm3 "ZM3 sizeof(Box<i64>) (6.6.17's form)" 'sizeof(Box<i64>) == 16'
nomsg zm4 "ZM4 control: sizeof(i64)" 'sizeof(i64) == 8'

echo "V. a slice element is any type valid elsewhere (D105): no error, no warning, exit 3"
builds v1 "V1 the repro verbatim, [*u128]" 3 "${F}var s: [*u128] = 0;${E}"
builds v2 "V2 the repro verbatim, [*Vec<i64>]" 3 "${F}var s: [*Vec<i64>] = 0;${E}"
builds v3 "V3 slice<*u128>" 3 "${F}var s: slice<*u128> = 0;${E}"
builds v4 "V4 [Vec<i64>]" 3 "${F}var s: [Vec<i64>] = 0;${E}"
builds v5 "V5 slice<Vec<Vec<i64>>> (its >>> closes the slice)" 3 "${F}var s: slice<Vec<Vec<i64>>> = 0;${E}"
builds v6 "V6 [**Vec<i64>]" 3 "${F}var s: [**Vec<i64>] = 0;${E}"

echo "VG. a Vec element's refusals are a local's, one line; a closer closing more than the slice may is the slice's error"
refused VG1 "1:30: $NT as the Vec element of 's'" "VG1 [Vec<Nope>]" "${F}var s: [Vec<Nope>] = 0;${E}"
refused VG2 "1:31: a tuple type cannot be a Vec element" "VG2 [*Vec<(i64, i64)>]" "${F}var s: [*Vec<(i64, i64)>] = 0;${E}"
refused VG3 "1:30: expected a Vec element type for 's', got '*'" "VG3 [Vec<*i64>] (as a local's Vec<*i64>)" "${F}var s: [Vec<*i64>] = 0;${E}"
refused VG4 "1:35: expected '>' after the Vec element type for 's', got ','" "VG4 [**Vec<i64, i64>]" "${F}var s: [**Vec<i64, i64>] = 0;${E}"
refused VG5 "1:33: expected ']', got '>>'" "VG5 [Vec<i64>>]: the >> closes more than the element" "${F}var s: [Vec<i64>>] = 0;${E}"
refused VG6 "1:38: expected '=', got '>>>'" "VG6 slice<Vec<i64>>>: the >>> closes more than the slice" "${F}var s: slice<Vec<i64>>> = 0;${E}"
refused VG7 "1:45: expected '=', got '>'" "VG7 slice<Vec<Vec<i64>>>>: a > after the closer that closed the slice" "${F}var s: slice<Vec<Vec<i64>>>> = 0;${E}"

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
echo "PASS: $G — a pointer type behind any number of \`*\` is a slice's pointer element (P, PG; the user's D93) a sizeof operand, 8 (Z, ZG; the user's D94), a slice element is any type valid elsewhere (V, VG; the user's D105), and the values files (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
