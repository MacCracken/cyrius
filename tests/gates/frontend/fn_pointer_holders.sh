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
#   W  (met landing D8) a fn's address `&f` and a closure literal are pointers to the typed-pointer check, as a
#      variable's `&x` is (6.5.29): `var c: *fn(i64): i64 = &dbl;`, `cb = &inc;` into a `cb: *fn( .. )` parameter, a
#      zone / late / assigned global, a for step, `|x| x + 1`, `|| 4`, wrapped `((&f))` / `((|x| x))`, `&f` into a `*i64`,
#      `&P_m` — each warned "assigning non-pointer to typed pointer" through 6.7.16 (`_tp_fna_exempt`,
#      src/frontend/parse_decl.cyr); WC1-WC3 the controls that still warn (an untyped variable, `&f + 0`, `(|x| x) + 1`)
#   Y  (met landing D8) the statement resync (`_sync_kw`, src/common/util.cyr) stopped at a fn-pointer type's `fn` as at a
#      statement keyword, so junk `h(1 *fn(i64): i64;` added "a fn is defined inside fn 'f'" (and, once D8 made
#      `_skip_nested_body` take a `*fn` as no unit, "unexpected '('"): Y1 one error, Y2 the next statement's error kept,
#      Y3 the top-level control
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
# W, measured the same way on the D8 commit (343f710c7):
#   MW0 the D8 commit itself (no `_tp_fna_exempt`)      -> RED 5: W1-W5 (2-4 warnings each)
#   MW1 `_tp_exempt` not asking `_tp_fna_exempt`        -> RED 5: W1-W5
#   MW2 a wrapped closure not taken (`_tp_cl_whole` 0)  -> RED 1: W4 (`((|x| x))`)
#   MW3 `&f` taken without its terminator check         -> RED 1: WC2 (`&f + 0` silent)
#   MW4 a closure taken however it is wrapped           -> RED 1: WC3 (`(|x| x) + 1` silent)
# Y, on the D9 commit (313adedb4):
#   MY0 the D9 commit itself (`_sync_kw` stops at `fn`) -> RED 2: Y1 Y2 (+ "a fn is defined inside fn 'f'" and
#                                                         "unexpected '('")
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

echo "W. a fn's address and a closure literal are pointers: no \"assigning non-pointer to typed pointer\""
# quiet <name> <what> <want-exit> <body>: compiles (x86_64) with no error or warning and exits <want-exit>
quiet() {
    printf '%b' "$4" > "$D/$1.cyr"
    rc=0; timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    w=$(grep -cE '^(error|warning)' "$D/$1.err" || true)
    if [ "$rc" -ne 0 ]; then bad "$2: rc $rc: $(grep -m1 '^error' "$D/$1.err")"
    elif [ "$w" -ne 0 ]; then bad "$2: $w line(s): $(grep -E '^(error|warning)' "$D/$1.err" | head -2 | tr '\n' '|')"
    else
        chmod +x "$D/$1.bin"; got=0; timeout 10 "$D/$1.bin" > /dev/null 2>&1 || got=$?
        if [ "$got" -eq "$3" ]; then ok "$2: silent, exit $got"; else bad "$2: exit $got, want $3"; fi
    fi
}
# warns <name> <want-line> <what> <body>: compiles with exactly that one warning line (`L:C`, the text implied)
warns() {
    printf '%b' "$4" > "$D/$1.cyr"
    rc=0; timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    grep -E '^(error|warning)' "$D/$1.err" > "$D/$1.got" || true
    printf 'warning:<source>:%s: assigning non-pointer to typed pointer\n' "$2" > "$D/$1.want"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep -m1 '^error' "$D/$1.err")"
    elif cmp -s "$D/$1.got" "$D/$1.want"; then ok "$3: the one warning"
    else bad "$3: got $(tr '\n' '|' < "$D/$1.got") want warning at $2"; fi
}
FH='include "lib/fnptr.cyr"\ninclude "lib/alloc.cyr"\nfn dbl(x): i64 { return x * 2; }\nfn inc(x): i64 { return x + 1; }\n'
quiet W1 "W1 a local declared from &f, (&f) and ((&f))" 10 \
    "${FH}fn f(): i64 { var c: *fn(i64): i64 = &dbl; var d: *fn = (&inc); var e: *fn(i64): i64 = ((&dbl)); return fncall1(c, 1) + fncall1(d, 1) + fncall1(e, 3); }\nsyscall(60, f());\n"
quiet W2 "W2 a zone global and a global after the first statement from &f, a top-level assignment" 5 \
    "${FH}var G: *fn(i64): i64 = &dbl;\nG = &inc;\nvar H: *fn(i64): i64 = (&dbl);\nsyscall(60, fncall1(G, 1) + fncall1(H, 1) + 1);\n"
quiet W3 "W3 assignments: a local, a cb: *fn( .. ) parameter (it warned since 6.7.11), a global in a fn, a for step" 9 \
    "${FH}var G: *fn(i64): i64 = 0;\nfn f(cb: *fn(i64): i64): i64 { var c: *fn(i64): i64 = 0; c = &dbl; cb = &inc; G = &dbl; for (var i = 0; i < 1; c = &inc) { i = i + 1; } return fncall1(c, 2) + fncall1(cb, 1) + fncall1(G, 2); }\nsyscall(60, f(0));\n"
quiet W4 "W4 a closure literal — bare, zero-parameter, wrapped — and a zone global's" 11 \
    "${FH}var Z: *fn = |x| x + 5;\nfn f(): i64 { var a: *fn(i64): i64 = |x| x + 1; var b: *fn = || 4; var c: *fn = ((|x| x)); return fncall1(a, 1) + fncall0(b) + fncall1(c, 0) + fncall1(Z, 0); }\nsyscall(60, f());\n"
quiet W5 "W5 any typed pointer takes it, as it takes a variable's &x: a *i64, an impl method's &P_m" 4 \
    "${FH}struct P { x; }\nimpl P { fn m(self): i64 { return self.x; } }\nfn f(): i64 { var q: *i64 = &dbl; var c: *fn(i64): i64 = &P_m; var p = P { 4 }; return fncall1(c, &p); }\nsyscall(60, f());\n"
warns WC1 "2:47" "WC1 control: an untyped variable holding &f still warns" \
    'fn inc(x): i64 { return x + 1; }\nfn main(): i64 { var q = &inc; var r: *i64 = q; return 0; }\nsyscall(60, main());\n'
warns WC2 "2:40" "WC2 control: &f + 0 (arithmetic, not the whole &f) still warns" \
    'fn inc(x): i64 { return x + 1; }\nfn main(): i64 { var s: *i64 = &inc + 0; return 0; }\nsyscall(60, main());\n'
warns WC3 "2:42" "WC3 control: (|x| x) + 1 still warns" \
    'fn inc(x): i64 { return x + 1; }\nfn main(): i64 { var v: *fn = (|x| x) + 1; return 0; }\nsyscall(60, main());\n'

echo "Y. a resync does not stop at a fn-pointer type's \`fn\`"
# errs <name> <what> <want-line>... <body is $D/<name>.cyr>: exactly these error lines (`L:C: text`), rc 1, no binary
errs() {
    nm=$1; what=$2; shift 2
    rc=0; timeout 60 "$CC" < "$D/$nm.cyr" > "$D/$nm.bin" 2> "$D/$nm.err" || rc=$?
    grep -E '^(error|warning)' "$D/$nm.err" > "$D/$nm.got" || true
    : > "$D/$nm.want"
    for w in "$@"; do printf 'error:<source>:%s\n' "$w" >> "$D/$nm.want"; done
    if [ "$rc" -eq 0 ]; then bad "$what: compiled (rc 0)"
    elif ! cmp -s "$D/$nm.got" "$D/$nm.want"; then bad "$what: got $(tr '\n' '|' < "$D/$nm.got") want $(tr '\n' '|' < "$D/$nm.want")"
    elif [ -s "$D/$nm.bin" ]; then bad "$what: refused, but a binary was written"
    else ok "$what: exactly $# line(s)"; fi
}
YH='fn h(x): i64 { return x; }\n'
printf "${YH}"'fn f(): i64 { h(1 *fn(i64): i64; return 3; }\nsyscall(60, f());\n' > "$D/y1.cyr"
errs y1 "Y1 junk *fn( .. ) in an expression: one error (it added \"a fn is defined inside fn 'f'\", 6.7.17's D8 also \"unexpected '('\")" \
    "2:20: unexpected fn"
printf "${YH}"'fn f(): i64 { h(1 *fn(i64): i64; var b = 2 2; return 3; }\nsyscall(60, f());\n' > "$D/y2.cyr"
errs y2 "Y2 ... the next statement's own error is still reported" "2:20: unexpected fn" "2:44: expected ';', got number 2"
printf "${YH}"'var a = 1;\na = h(1 *fn(i64): i64;\nsyscall(60, 3);\n' > "$D/y3.cyr"
errs y3 "Y3 control: at top level after the first statement, one error (as before)" "3:10: unexpected fn"

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
