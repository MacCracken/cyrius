#!/bin/sh
# tests/gates/frontend/fn_pointer_holders.sh — 6.7.17 (the user's D8, 2026-10-22)
#
# A `*fn( .. )` TYPE DECLARES A LOCAL, A GLOBAL, A STRUCT / UNION FIELD AND A SLICE ELEMENT AS THE ONE POINTER WORD A
# `cb: *fn( .. )` PARAMETER IS. The declaration readers took the token after the `*` as a type name and met the
# keyword: `var c: *fn(i64): i64 = 0;` was "expected identifier, got reserved keyword 'fn' (cannot be used as an
# identifier; rename the variable/field/fn)", then "undefined variable 'i64'" and "assigning non-pointer to typed
# pointer"; a declaration-zone global added "expected '=', got '('"; `struct H { cb: *fn(i64): i64; k; }` the keyword
# line. Measured on 6.7.16 (main 4a3c510f3), x86_64; the parse is every target's. The readers now read the type by the
# parameter's grammar (`_ptr_fnp_end`, src/frontend/parse_types.cyr), its names checked with the declaration's words,
# once, and step a pointer's 8 (`fncallN` / `callptr` call through the word as through a parameter). A `fn` behind a
# `*` is a fn-pointer type to the token scans too (`_skip_nested_body`, src/frontend/parse.cyr; `_tok_fn_kw`).
# Filed: docs/development/issues/2026-10-21-fn-pointer-type-outside-a-parameter.md
#
#   R  the filed repros verbatim — a local, a declaration-zone global, a field — and a global after the first
#      statement: no error and no warning, exit 3, on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine); RL each under
#      --syntax-only (what `cyrius lint` runs): rc 0, silent
#   G  a refusal inside the type is exactly one line, with the declaration's words, and no binary: an unknown name (a
#      local, a declaration-zone global, a global after the first statement, a field, a slice element, the type's own
#      return, a generic fn's local at two instances once), a token that is no type, a missing `)` (a local, a zone
#      global, a field: the line reads on from its `=` / `;`)
#   S  the token scans meet a local's `*fn`: a tuple local after one in a generic fn is still refused (R4: it
#      compiled); `p = mk3();` after one names `p: *i64` (D14 at an assignment: it was judged as an untyped `p`), and
#      `c = mk3();` into one names `c: *fn(i64): i64`; the walk for the enclosing fn met a `*fn( .. )` PARAMETER's
#      `fn` as well (6.7.7 - 6.7.16), so a tuple (R4) or a dyn (T11) in a generic fn with one compiled: S4, S5
#   T  tests/tcyr/crossos/fn_pointer_typed_holders.tcyr on x86_64 (default, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu),
#      cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived from the file (one row per `assert_eq(`)
#
# MUTATION LEDGER (2026-10-22; a scratch copy of the tree with the one change, this gate run from that copy with
# CYCC=<its 2-stage mutant>; measured):
#   M0  the fix reverted (HEAD e65604d5d's src)         -> RED 43: R1-R4 on every leg and RL (the keyword line), G1-G12
#                                                         (the keyword line, or "expected ']'" + "undefined variable"),
#                                                         S1-S3 (the keyword line), S4 S5 (compiled), T on every leg
#   M1  `_ptr_annot` without its `fn` arm               -> RED 33: r1 r2 r4 (pass 1 reads a zone global there too), G1-G4
#                                                         G7-G10 G12, S1-S3, T on every leg
#   M2  `_gvi_ann` without its `fn` arm                 -> RED 13: r2 and RL r2 ("expected '=', got '('"), G3 G10, T
#   M3  `_fld_ptr_annot` without its `fn` arm           -> RED 1: G5 ("for variable 'cb'": `_ptr_annot` reads it on)
#   M4  `_tn_slice_ptr_el` without its `fn` arm         -> RED 7: G6 ("expected ']', got fn"), T on every leg
#   M5  `_skip_nested_body` taking `*fn` as a nested fn -> RED 6: T on every leg (the `?` rows: 139 x86 / aarch64, a
#                                                         cxvm guest fault, exit 5 on PE)
#   M6  `_tok_fn_kw` answering 1 for every `fn`         -> RED 3: S1 S4 S5 (compiled)
#   M7  `_asa_back` meeting a `*fn` as its fn's header  -> RED 2: S2 S3 ("cannot assign 'p' .. or bind a field")
#   M8  a missing `)` not stepped to the `=` / `;`      -> RED 2: G9 (+ the warning), G10 (+ "expected '='")
#   M9  `_pty_what` keeping the parameter's words       -> RED 9: G1-G8 G12 ("for parameter 'c'")
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=fn_pointer_holders
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

TC=tests/tcyr/crossos/fn_pointer_typed_holders.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=32
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

echo "R. the filed repros verbatim (and a global after the first statement): no error, no warning, exit 3"
printf 'fn main(): i64 { var c: *fn(i64): i64 = 0; return 3; }\nsyscall(60, main());\n' > "$D/r1.cyr"
printf 'var G: *fn(i64): i64 = 0;\nsyscall(60, 3);\n' > "$D/r2.cyr"
printf 'struct H { cb: *fn(i64): i64; k; }\nsyscall(60, 3);\n' > "$D/r3.cyr"
printf 'var a = 3;\na = a + 0;\nvar G: *fn(i64): i64 = 0;\nsyscall(60, a);\n' > "$D/r4.cyr"
for r in r1 r2 r3 r4; do
    for leg in x86 $OTHER; do
        n=$(printf '%s_%s' "$r" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$D/$r.cyr" "$D/b_$n"
        w=$(grep -cE '^(error|warning)' "$ERRF" 2>/dev/null || true)
        if [ "$RC" -eq -1 ]; then bad "$r $leg: did not build: $(grep -h -m1 '^error' "$ERRF" 2>/dev/null)"
        elif [ "$w" -ne 0 ]; then bad "$r $leg: $w diagnostic line(s): $(grep -E '^(error|warning)' "$ERRF" | head -2 | tr '\n' '|')"
        elif [ "$RC" -eq 3 ]; then ok "$r $leg: exit 3, nothing said"
        else bad "$r $leg: exit $RC, want 3"; fi
    done
    rc=0; timeout 60 "$CC" --syntax-only < "$D/$r.cyr" > /dev/null 2> "$D/$r.lint" || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$D/$r.lint" ]; then ok "RL $r: --syntax-only rc 0, silent"
    else bad "RL $r: --syntax-only rc $rc: $(head -2 "$D/$r.lint" | tr '\n' '|')"; fi
done

echo "G. a refusal inside the type: one line, the declaration's words, no cascade"
F='fn main(): i64 { '
E=' return 3; }\nsyscall(60, main());\n'
NT="unknown type 'Nope'"
refused G1 "1:29: $NT for variable 'c'" "G1 a local's unknown parameter type" "${F}var c: *fn(Nope): i64 = 0;${E}"
refused G2 "1:35: $NT for variable 'c'" "G2 a local's unknown return type" "${F}var c: *fn(i64): Nope = 0;${E}"
refused G3 "1:12: $NT for variable 'G'" "G3 a declaration-zone global's" 'var G: *fn(Nope): i64 = 0;\nsyscall(60, 3);\n'
refused G4 "2:12: $NT for variable 'G'" "G4 a global after the first statement" 'syscall(60, 3);\nvar G: *fn(Nope): i64 = 0;\n'
refused G5 "1:20: $NT for struct field 'cb'" "G5 a field's" 'struct H { cb: *fn(Nope): i64; k; }\nsyscall(60, 3);\n'
refused G6 "1:30: $NT for variable 's'" "G6 a slice element's" "${F}var s: [*fn(Nope): i64] = 0;${E}"
refused G7 "1:29: expected a type for variable 'c', got '+'" "G7 a token that is no type" "${F}var c: *fn(+): i64 = 0;${E}"
refused G8 "1:35: expected a type for variable 'c', got '='" "G8 no return type after its ':'" "${F}var c: *fn(i64): = 0;${E}"
refused G9 "1:33: expected ')', got identifier 'i64'" "G9 a local's missing ')' (no warning, no cascade)" "${F}var c: *fn(i64 i64): i64 = 0;${E}"
refused G10 "1:16: expected ')', got identifier 'i64'" "G10 a declaration-zone global's (no \"expected '='\")" 'var G: *fn(i64 i64): i64 = 0;\nsyscall(60, 3);\n'
refused G11 "1:24: expected ')', got identifier 'i64'" "G11 a field's" 'struct H { cb: *fn(i64 i64): i64; k; }\nsyscall(60, 3);\n'
refused G12 "1:34: $NT for variable 'c'" "G12 a generic fn's local at two instances: once" 'fn g<T>(x: T): T { var c: *fn(T, Nope): T = 0; return x; }\nstruct P { a; }\nfn main(): i64 { var p = P { 1 }; var q = g(p); return g(3); }\nsyscall(60, main());\n'

echo "S. the token scans read a local's *fn as a type, not a nested fn"
refused S1 "1:45: a tuple type in a generic fn is refused - a type parameter and a tuple do not combine yet" \
    "S1 a tuple local after a *fn local in a generic fn (it compiled)" \
    'fn g<T>(x: T): i64 { var c: *fn = 0; var t: (i64, i64) = (1, 2); return 0; }\nsyscall(60, g(1));\n'
P3='struct P3 { a; b; c; }\nfn mk3(): P3 { var t = P3 { 1, 2, 3 }; return t; }\n'
refused S2 "3:52: cannot assign 'p: *i64' from 'mk3', which returns the struct 'P3' - declare 'p: P3' and take \`&p\`" \
    "S2 p = mk3() after a *fn local names p's *i64 (it was judged untyped)" \
    "${P3}fn f(): i64 { var p: *i64 = 0; var c: *fn = 0; p = mk3(); return 0; }\nsyscall(60, f());\n"
refused S3 "3:45: cannot assign 'c: *fn(i64): i64' from 'mk3', which returns the struct 'P3' - declare 'c: P3' and take \`&c\`" \
    "S3 c = mk3() into a *fn( .. ) local names its type" \
    "${P3}fn f(): i64 { var c: *fn(i64): i64 = 0; c = mk3(); return 0; }\nsyscall(60, f());\n"
# The same walk met a `*fn( .. )` PARAMETER's `fn` before 6.7.17, so these compiled (R4 since 6.7.7, T11 since 6.7.8):
refused S4 "1:48: a tuple type in a generic fn is refused - a type parameter and a tuple do not combine yet" \
    "S4 a tuple local in a generic fn with a *fn( .. ) parameter (it compiled)" \
    'fn g<T>(cb: *fn(i64): i64, x: T): i64 { var t: (i64, i64) = (1, 2); return 0; }\nsyscall(60, g(0, 1));\n'
refused S5 "4:55: a dyn type in a generic fn is refused - a type parameter and a dyn do not combine yet" \
    "S5 a dyn local in a generic fn with a bare *fn parameter (it compiled)" \
    'struct P { a; }\ntrait Tr { fn m(self): i64; }\nimpl Tr for P { fn m(self): i64 { return self.a; } }\nfn g<T>(cb: *fn, x: T): i64 { var p = P { 1 }; var o: dyn Tr = &p; return 0; }\nsyscall(60, g(0, 1));\n'

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -h -m1 '^error' "$ERRF" 2>/dev/null)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a *fn( .. ) declares a local, a global, a field and a slice element as one pointer word (the user's D8): the filed repros (R, RL), a refusal inside the type once (G), the token scans (S) and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"
