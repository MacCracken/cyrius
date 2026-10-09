#!/bin/sh
# tests/gates/frontend/tuple_checked.sh — 6.7.7 (B4)
#
# TUPLES AS VALUES. The user's decision (2026-10-08): `(a, b)` builds a value laid out as an anonymous
# struct of 8-byte slots; `t.0` / `t.1` read and write it (`OP=` included); `(i64, f64)` is a type
# wherever a struct type goes; `var t: (i64, i64) = f();` captures every value of a multi-value call
# and `a, b = f();` re-assigns existing variables; `var x = f();` keeps its first-value meaning. A
# shape the decision leaves open is refused by name, never given a default meaning.
#
#   L  the lexer: `.` then a digit after an IDENT, `)` or `]` is a selector (IDENT DOT IDENT"0"), and
#      every other `.digit` lexes exactly as before — ranges, floats, `t. 0` with a space
#   S  shapes: S2 a struct with a tuple field (its layout, the neighbours intact); S3 a forward call
#      to a fn declared below with a tuple parameter and a second one (pass 1's parameter scan);
#      S5 `#derive` on a struct with a tuple field is refused by name
#   R  the shapes the decision leaves open, each refused by name (one error line, its fragment):
#      R1 an element outside i64 / f64 / bool; R2 arity and spelling; R3 a type position outside
#      a var / a struct field / a parameter; R4 a tuple in a generic fn / struct; R6 an `async fn`
#      tuple parameter; R11 a tuple (or a tuple field) used as a value; R12 a non-tuple source into
#      a tuple place (an argument of another struct or tuple type too); R13 methods; R17 a
#      multi-value call as a tuple argument (`g(f())`: bind it first); R21 `t.N` spellings that
#      name no element
#   P  positive: the type, `t.N`, copies, fields, parameters — exit codes, values distinguishable
#   X  `--syntax-only` (cyrius lint's pre-pass): a fn with a tuple parameter, and a call to a
#      sibling file's fn with a tuple argument, report nothing
#   A  tests/tcyr/crossos/tuple_values.tcyr with its full assertion count (derived from the source)
#      on x86 (default, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE
#      (wine, a private prefix). A leg whose tool is missing is a SKIP that names it (exit 77).
#
# MUTATION LEDGER (2026-10-09; each a one-edit scratch COPY of the tree, its compiler rebuilt from the
# mutated src, then this gate run with CYCC= the mutant):
#   M1  `_lex_dot` without the previous-token guard (every `.digit` a selector) -> L1 (a range's
#       `..10` lexes DOT IDENT"10": "undefined variable '10'"). L2's shapes never reach the guard
#       (`1.5` is one LEXNUM token; `1.0.5`'s refusal names the `.` either way). The same mutant
#       compiles 8 tree files differently from the base compiler (ranges in crossos tcyrs).
#   M1b the guard without `)` (11)                                               -> L3c
# THE EVIDENCE BEYOND THESE ROWS (T1, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in the tree
# (1051 files, default and CYRIUS_DCE=1) compiles byte-identical — stdout, stderr and exit code —
# with the T1 compiler and the base build/cycc (e44470b7); the aarch64, cx and PE
# (CYRIUS_TARGET_WIN=1) compilers likewise over tests/tcyr/crossos/. No program that compiled before
# lexes differently.
# T2 (2026-10-09; the same recipe; each mutant measured RED, the real tree 101/101):
#   M2  no `_sdef_tup_prescan` (PARSE_STRUCT_DEF)  -> 16 rows: S2, P2, P3, every struct-field R row
#       (R4b R11m R11n R11q R12j-R12l R13d) and A1-A4 / A7 — "internal error: a tuple field type was
#       not interned before its struct" (the field arm's lookup misses; it never REGSTRUCTs mid-definition)
#   M10b the pointer-mode backstop removed (`_tup_ptr_refuse` returns 0) -> R12e-R12i BUILD (a tuple
#       declared from a value took one word into a pointer-mode slot). (The plan's M10 is T5's
#       `_ret_tuple_var` mutation; this bite owns M10b, which T2 makes a refusal with rows.)
#   M11 `_tup_rchk` removed (PARSE_FACTOR)         -> R11a-l and R11o-r RED (BUILT, or a stray
#       `(i64, i64)_add` undefined-function / if-expression error); R11m / R11n stay green — the field
#       form is `_tup_fld_rchk`'s, at the load
#   M16 the element vocabulary check removed      -> R1a R1b R1d R1h R1i BUILD (every name an i64)
#   M17 the generic refusals removed (`_tup_gen_chk`, the prescan's) -> R4a R4b BUILD
#   M18 the `#derive` refusal removed (`PP_DTUP`) -> S5 BUILDS (every field after `t` silently loses
#       its derived code)
#   M13d `_tup_meth_chk` without its digit arm    -> R13e-R13i RED (`p.0()` calls `P_0`)
# THE EVIDENCE BEYOND THESE ROWS (T2, 2026-10-09): the same 1051 files compile byte-identical —
# stdout, stderr and exit code, default and CYRIUS_DCE=1 — with the T2 compiler and the T1 one, and
# the aarch64, cx and PE compilers likewise over all 537 pre-existing tests/tcyr files. No program
# that compiled before T2 compiles differently.
# T3 (2026-10-09; the same recipe; each mutant measured RED, the real tree 120/120):
#   M3  no pass-1 parameter arm (`_prescan_params_scan` without `_tup_pscan`) -> S3 and A1-A4 / A7
#       (a forward call counted one parameter with no struct-mask bit: the tuple was read as a value)
#   M14 no `g(f())` refusal (`_tup_arg_call` dropped) -> R17a-R17f BUILD; R17a's binary exits 139 (the
#       first value pushed as the tuple's address)
#   M14b no method / operator refusal (`_tup_arg_mrc` dropped) -> R17g, R17h BUILD; both binaries exit 139
#   Mbv pass 1 records no prologue copy (`_tup_bvcp` a no-op) -> A1-A4 / A7: tuple_values' "after an earlier
#       call to a copying callee declared below: kept" (the tail call diverted for nothing)
#   Masy the `async fn` tuple branch dropped -> R6a: the struct message, advising `t: *(i64, i64)`
# THE EVIDENCE BEYOND THESE ROWS (T3, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in src lib programs cbt
# tests benches fuzz bootstrap docs/development/issues but tuple_values.tcyr (1034 files) compiles byte-identical —
# stdout, stderr and exit code; default, CYRIUS_DCE=1 and --syntax-only — with the T3 compiler and the T2 one, and
# the aarch64, cx and PE compilers likewise over all 537 other tests/tcyr files.
# Defensive, no killing row (named): `_tok_start` set to the digit before LEXID — today every
# diagnostic at a selector points at the token AFTER it, so the IDENT's own offset is not observed;
# the guard's `]` (29) — no valid program today follows a subscript with `.field`, so `a[1].0` is
# "expected ';', got '.'" with or without it.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: tuple_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: tuple_checked: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# silent_values_checked.sh helper.
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
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
P='struct P { a; b; }\n'

# ── L: the lexer ─────────────────────────────────────────────────────────────────────────────────
# L1: every range whose upper bound is a digit run — after a number, an IDENT, `)` and `]`. Its second
# `.` follows a DOT token, so the selector guard never fires on it.
exits l01 250 "L1: ranges \`0..10\`, \`a..5\`, \`a..hi\`, \`g(4)..6\`, \`arr[0]..5\` intact" 'fn g(x): i64 { return x; }\nfn f(c): i64 {\n    var s = 0;\n    var a = 2;\n    var hi = 6;\n    var arr: i64[2];\n    arr[0] = 3;\n    for i in 0..10 { s = s + 1; }\n    for i in a..5 { s = s + 10; }\n    for i in a..hi { s = s + 20; }\n    for i in g(4)..6 { s = s + 40; }\n    for i in arr[0]..5 { s = s + 25; }\n    return s;\n}\nsyscall(60, f(1));\n'
exits l02 3 "L2: \`1.5\` / \`0.25\` are still float literals (their binary64 bits)" 'var x = 1.5;\nvar y = 0.25;\nsyscall(60, (x == 0x3FF8000000000000) + (y == 0x3FD0000000000000) * 2);\n'
refused l02b "expected ';', got '.'" "L2b: \`1.0.5\` is still a float then a stray \`.\`" 'fn f(): i64 { var y = 1.0.5; return 0; }\nsyscall(60, f());\n'
refused l03 "unknown field '0' on struct 'P'" "L3: \`p.0\` on a named struct is a field selector" "${P}fn f(): i64 { var p: P; p.a = 1; return p.0; }\nsyscall(60, f());\n"
refused l03b "unknown field '0x1' on struct 'P'" "L3b: \`p.0x1\` is ONE selector (the whole alnum run), not a hex number" "${P}fn f(): i64 { var p: P; return p.0x1; }\nsyscall(60, f());\n"
refused l03c "unknown field '0' on struct 'P'" "L3c: after \`)\` too — \`mk().0\` (was \"expected ';', got '.'\")" "${P}fn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\nfn f(): i64 { return mk().0; }\nsyscall(60, f());\n"
refused l04 "unknown field '0' on struct 'P'" "L4: \`p.0.1\` is two selectors (the error names '0', not a float 0.1)" "${P}fn f(): i64 { var p: P; return p.0.1; }\nsyscall(60, f());\n"
# L4b: `--syntax-only` (what `cyrius lint` runs) reads `p.0.1` as a selector chain, exactly as `p.a.b`.
printf 'fn f(p): i64 { return p.0.1 + p.a.b; }\nsyscall(60, f(0));\n' > "$T/l04b.cyr"
rc=0; "$CC" --syntax-only < "$T/l04b.cyr" > /dev/null 2> "$T/l04b.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/l04b.err"; then ok "L4b: --syntax-only reads \`p.0.1\` as a chain, as \`p.a.b\`"
else bad "L4b: --syntax-only rc $rc: $(grep '^error' "$T/l04b.err" | head -1)"; fi
refused l05 "expected identifier, got number 0" "L5: \`p. 0\` (a space) is still a number, not a selector" "${P}fn f(): i64 { var p: P; return p. 0; }\nsyscall(60, f());\n"

# ── S: shapes ──────────────────────────────────────────────────────────────────────────────────────
TH='struct H { a; p: (i64, i64); b; }\n'
exits s02 47 "S2: \`struct H { a; p: (i64, i64); b; }\` is 32 bytes, and \`b\` is intact after \`p.1\` is written" "${TH}fn f(): i64 {\n    var h: H;\n    h.a = 1;\n    h.b = 7;\n    h.p.0 = 3;\n    h.p.1 = 9;\n    if (sizeof(H) != 32) { return 99; }\n    return h.b * 10 - h.p.1 - h.a * 14;\n}\nsyscall(60, f());\n"
# S3: a forward call to a fn declared BELOW with a tuple parameter and then a second one. Pass 1's
# parameter scan stopped at the `(`: one parameter counted, no struct-mask bit — the call was refused
# ("expects 1 argument") or, with the arity right, pushed the tuple's first word as its address.
exits s03 64 "S3: \`later(t, 1000)\` before \`fn later(t: (i64, i64), k)\` (pass 1 scans the tuple parameter)" 'fn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    var r = later(t, 1000);\n    return r - 1000 + t.0;\n}\nfn later(t: (i64, i64), k): i64 {\n    t.0 = t.0 + 100;\n    return t.0 * 10 + t.1 + k;\n}\nsyscall(60, f() - 1000);\n'
refused s05 "#derive reads named field types; 't' is a tuple (in the declaration of D)" "S5: \`#derive\` on a struct with a tuple field (it silently dropped every later field's code)" '#derive(accessors)\nstruct D { a; t: (i64, i64); b; }\nfn f(): i64 { var d: D; d.a = 3; return d.a; }\nsyscall(60, f());\n'

# ── R1: the element vocabulary is i64 / f64 / bool ─────────────────────────────────────────────────
V='fn f(): i64 {\n    var t: '
W=';\n    return 0;\n}\nsyscall(60, f());\n'
refused r01a "a tuple element is i64, f64 or bool, not 'i32'" "R1a: \`(i32, i64)\` (narrow integers: 6.7.8's B7)" "${V}(i32, i64)${W}"
refused r01b "a tuple element is i64, f64 or bool, not 'u64'" "R1b: \`(u64, i64)\`" "${V}(u64, i64)${W}"
refused r01c "a tuple element is i64, f64 or bool, not a pointer" "R1c: \`(*i64, i64)\`" "${V}(*i64, i64)${W}"
refused r01d "a tuple element is i64, f64 or bool, not struct 'P'" "R1d: \`(P, i64)\`, a struct element" "${P}${V}(P, i64)${W}"
refused r01e "a tuple element is i64, f64 or bool, not a nested tuple" "R1e: \`((i64, i64), i64)\`" "${V}((i64, i64), i64)${W}"
refused r01f "a tuple element is i64, f64 or bool, not u128" "R1f: \`(u128, i64)\`" "${V}(u128, i64)${W}"
refused r01g "a tuple element is i64, f64 or bool, not a slice" "R1g: \`([u8], i64)\`" "${V}([u8], i64)${W}"
refused r01h "unknown type 'Nope' as a tuple element" "R1h: an unknown name" "${V}(Nope, i64)${W}"
refused r01i "a tuple element is i64, f64 or bool, not 'f32'" "R1i: \`(f32, i64)\`" "${V}(f32, i64)${W}"
refused r01j "a tuple element is i64, f64 or bool, not 'i32'" "R1j: a parameter \`t: (i32, i64)\`" 'fn g(t: (i32, i64)): i64 { return 1; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'

# ── R2: arity and spelling ─────────────────────────────────────────────────────────────────────────
refused r02a "a tuple type has 2 or more elements - \`()\` is empty" "R2a: \`()\`" "${V}()${W}"
refused r02b "a tuple type has 2 or more elements - write the one type without parentheses" "R2b: \`(i64)\`" "${V}(i64)${W}"
refused r02c "a trailing comma in a tuple type" "R2c: \`(i64, i64,)\`" "${V}(i64, i64,)${W}"
refused r02d "a trailing comma in a tuple type" "R2d: \`(i64,)\` (one error, not two)" "${V}(i64,)${W}"
refused r02e "an empty element in a tuple type" "R2e: \`(i64, , i64)\`" "${V}(i64, , i64)${W}"

# ── R3: type positions the decision leaves open ────────────────────────────────────────────────────
refused r03a "a tuple type cannot be a pointer target" "R3a: \`*(i64, i64)\`" 'fn f(): i64 {\n    var p: *(i64, i64) = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03b "a tuple type cannot be a slice element" "R3b: \`[(i64, i64)]\`" 'fn f(): i64 {\n    var s: [(i64, i64)] = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03c "a tuple type cannot be a slice element" "R3c: \`slice<(i64, i64)>\`" 'fn f(): i64 {\n    var s: slice<(i64, i64)> = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03d "a tuple type cannot be an array element" "R3d: \`(i64, i64)[4]\`, a local" "${V}(i64, i64)[4]${W}"
refused r03e "a tuple type cannot be an array element" "R3e: \`(i64, i64)[4]\`, a declaration-zone global" 'var G: (i64, i64)[4];\nsyscall(60, 3);\n'
refused r03f "a tuple type cannot be a sizeof operand" "R3f: \`sizeof((i64, i64))\`" 'fn f(): i64 { return sizeof((i64, i64)); }\nsyscall(60, f());\n'
refused r03g "a tuple type cannot be a sizeof operand" "R3g: \`#assert sizeof((i64, i64))\` (no \"#assert failed\" after it)" 'fn f(): i64 {\n    #assert sizeof((i64, i64)) == 16, "x"\n    return 3;\n}\nsyscall(60, f());\n'
refused r03h "a tuple type cannot be a type argument" "R3h: \`B<(i64, i64)>\` (it said \"unknown type 'struct'\")" 'struct B<T> { v: T; }\nfn f(): i64 { var b: B<(i64, i64)>; return 3; }\nsyscall(60, f());\n'
refused r03i "a tuple type cannot be a type argument" "R3i: \`id<(i64, i64)>(3)\` (it said \"undefined variable 'id'\")" 'fn id<T>(x: T): T { return x; }\nfn f(): i64 { return id<(i64, i64)>(3); }\nsyscall(60, f());\n'
refused r03j "union field 't' cannot be a tuple" "R3j: a union field" 'union U { a; t: (i64, i64); }\nfn f(): i64 { var u: U; u.a = 3; return u.a; }\nsyscall(60, f());\n'
refused r03k "a tuple has no methods - \`impl\` on a tuple type is refused" "R3k: \`impl (i64, i64) {\`" 'impl (i64, i64) {\n    fn m(self): i64 { return 1; }\n}\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03l "a tuple has no methods - \`impl\` on a tuple type is refused" "R3l: \`impl Tr for (i64, i64) {\`" 'trait Tr { fn m(self): i64; }\nimpl Tr for (i64, i64) {\n    fn m(self): i64 { return 1; }\n}\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03m "a tuple type cannot be a multi-value return element" "R3m: \`fn g(): ((i64, i64), i64)\`" 'fn g(): ((i64, i64), i64) { return (1, 2); }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03n "a tuple in a const fn" "R3n: a tuple local in a const fn's evaluation" 'const fn cf(x: i64): i64 {\n    var t: (i64, i64);\n    return x;\n}\nconst C = cf(3);\nsyscall(60, C);\n'
refused r03o "a tuple type cannot be a Vec element" "R3o: a \`Vec<(i64, i64)>\` struct field (it said \"expected identifier\")" 'struct W { v: Vec<(i64, i64)>; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03p "a tuple type cannot be a pointer target" "R3p: a parameter \`t: *(i64, i64)\`" 'fn g(t: *(i64, i64)): i64 { return 1; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'

# ── R4: generics ───────────────────────────────────────────────────────────────────────────────────
refused r04a "a tuple type in a generic fn is refused" "R4a: a tuple local in a generic fn" 'fn g<T>(x: T): T {\n    var t: (i64, i64);\n    t.0 = x;\n    return t.0;\n}\nfn f(): i64 { return g(3); }\nsyscall(60, f());\n'
refused r04b "a tuple field in a generic struct is refused" "R4b: a tuple field in a generic struct" 'struct B<T> { v: T; t: (i64, i64); }\nfn f(): i64 { var b: B<i64>; b.v = 3; return b.v; }\nsyscall(60, f());\n'
refused r04c "a tuple type in a generic fn is refused" "R4c: a tuple parameter in a generic fn's signature" 'fn g<T>(x: T, t: (i64, i64)): T { return x; }\nfn f(): i64 { return g(3, 0); }\nsyscall(60, f());\n'

# ── R6: async ──────────────────────────────────────────────────────────────────────────────────────
# An `async fn` runs its body at force time, so a by-value struct parameter is refused (the inherited
# rule, `_refuse_async_struct_param`). Its usual advice is a pointer, which a tuple cannot be: the
# tuple form names the type and says to pass the elements.
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc"; chmod +x "$T/acc"
CC_SV=$CC; CC="$T/acc"
refused r06a "async fn parameter 't' is a tuple (i64, i64), which an \`async fn\` does not capture yet - pass its elements as separate parameters" "R6a: an \`async fn\` with a tuple parameter (CYRIUS_ASYNC=1)" 'include "lib/alloc.cyr"\nasync fn af(t: (i64, i64)): i64 { return t.0; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
CC=$CC_SV

# ── R11: a whole tuple is not a value ──────────────────────────────────────────────────────────────
TT='fn g(x): i64 { return x; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n'
TE='\n    return 0;\n}\nsyscall(60, f());\n'
U="tuple 't' used as a value"
refused r11a "$U" "R11a: \`t == 5\`" "${TT}    if (t == 5) { return 1; }${TE}"
refused r11b "$U" "R11b: \`t + 1\`" "${TT}    return t + 1;${TE}"
refused r11c "$U" "R11c: \`!t\`" "${TT}    if (!t) { return 1; }${TE}"
refused r11d "$U" "R11d: \`if (t)\`" "${TT}    if (t) { return 1; }${TE}"
refused r11e "$U" "R11e: \`while (t)\`" "${TT}    while (t) { return 1; }${TE}"
refused r11f "$U" "R11f: \`match t\`" "${TT}    match t { 1 => { return 1; } _ => { return 0; } }${TE}"
refused r11g "$U" "R11g: \`switch (t)\`" "${TT}    switch (t) { case 1: return 1; default: return 0; }${TE}"
refused r11h "$U" "R11h: \`for x in t\`" "include \"lib/alloc.cyr\"\ninclude \"lib/vec.cyr\"\n${TT}    var s = 0;\n    for x in t { s = s + x; }${TE}"
refused r11i "$U" "R11i: an untyped-parameter argument \`g(t)\`" "${TT}    return g(t);${TE}"
refused r11j "$U" "R11j: \`load64(t)\`" "${TT}    return load64(t);${TE}"
refused r11k "$U" "R11k: an un-annotated \`var x = t;\`" "${TT}    var x = t;\n    return x;${TE}"
refused r11l "$U" "R11l: \`callptr(fp, t)\`" "${TT}    var fp = &g;\n    return callptr(fp, t);${TE}"
refused r11m "tuple field 'p' used as a value" "R11m: a tuple FIELD, \`h.p == 5\`" "${TH}fn f(): i64 {\n    var h: H;\n    h.p.0 = 1;\n    if (h.p == 5) { return 1; }\n    return 0;\n}\nsyscall(60, f());\n"
refused r11n "tuple field 'p' used as a value" "R11n: a tuple field as an untyped argument" "${TH}fn g(x): i64 { return x; }\nfn f(): i64 {\n    var h: H;\n    return g(h.p);\n}\nsyscall(60, f());\n"
refused r11o "$U" "R11o: an if-expression branch" "${TT}    var y = if (t.0 == 1) { t } else { 0 };\n    return y;${TE}"
refused r11p "$U" "R11p: \`-t\`" "${TT}    return -t;${TE}"
refused r11q "tuple 'G' used as a value" "R11q: a global, \`G + 1\`" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nfn f(): i64 { return G + 1; }\nsyscall(60, f());\n"
refused r11r "$U" "R11r: a closure's capture, \`|| t + 1\`" "include \"lib/alloc.cyr\"\n${TT}    alloc_init();\n    var c = || t + 1;\n    return fncall0(c);${TE}"

# ── R12: a value that is no tuple into a tuple place (non-literal shapes) ──────────────────────────
A12="cannot assign a value that is not a tuple to tuple"
I12="cannot initialize tuple"
refused r12a "$A12 't'" "R12a: \`t = 5\`" "${TT}    t = 5;${TE}"
refused r12b "$A12 't'" "R12b: \`t = x\`, a scalar" "${TT}    var x = 3;\n    t = x;${TE}"
refused r12c "$A12 't'" "R12c: \`t = g(3)\`, a scalar call" "${TT}    t = g(3);${TE}"
refused r12d "$A12 't'" "R12d: \`t = (g(3))\`" "${TT}    t = (g(3));${TE}"
refused r12e "$I12 'u' with a value that is not a tuple" "R12e: \`var u: (i64, i64) = 5;\`" "${TT}    var u: (i64, i64) = 5;${TE}"
refused r12f "$I12 'u' with a value that is not a tuple" "R12f: \`= x + 1\`" "${TT}    var x = 2;\n    var u: (i64, i64) = x + 1;${TE}"
refused r12g "$I12 'u' with a value that is not a tuple" "R12g: an address (it would be pointer-mode)" "${TT}    var u: (i64, i64) = g(4096);${TE}"
refused r12h "$I12 'G' with a value that is not a tuple" "R12h: a declaration-zone global \`var G: (i64, i64) = 5;\`" 'var G: (i64, i64) = 5;\nsyscall(60, 0);\n'
refused r12i "$I12 'G' with a value that is not a tuple" "R12i: a global after the first statement" 'syscall(1, 1, "", 0);\nvar G: (i64, i64) = 5;\nsyscall(60, 0);\n'
refused r12j "cannot store a value that is not a tuple into tuple field 'p'" "R12j: \`h.p = 5\`" "${TH}fn f(): i64 {\n    var h: H;\n    h.p = 5;\n    return 0;\n}\nsyscall(60, f());\n"
refused r12k "$A12 'G'" "R12k: a global, \`G = 5\` at top level" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nG = 5;\nsyscall(60, 0);\n"
refused r12l "$A12 'G'" "R12l: a classic-for step \`G = 5\`" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nfn f(): i64 {\n    for (var i = 0; i < 2; G = 5) { i = i + 1; }\n    return 0;\n}\nsyscall(60, f());\n"
refused r12m "cannot copy 'p' into a variable of a different struct/vector type: 't'" "R12m: a struct into a tuple (by sid)" "${P}${TT}    var p: P;\n    t = p;${TE}"
refused r12n "cannot copy 'u' into a variable of a different struct/vector type: 't'" "R12n: another tuple type" "${TT}    var u: (i64, f64);\n    t = u;${TE}"
refused r12o "cannot copy 'u' into a variable of a different struct/vector type: 'v'" "R12o: another tuple type, a declaration" "${TT}    var u: (i64, f64);\n    var v: (i64, i64) = u;${TE}"
refused r12p "uninitialized variable not allowed" "R12p: \`var G: (i64, i64);\` in the declaration zone keeps its one \"uninitialized\" refusal" 'var G: (i64, i64);\nsyscall(60, 0);\n'
# R12q-s: an argument is type-checked by sid against a tuple parameter (`_sarg_type_err`), both ways.
TK='fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\n'
refused r12q "cannot pass 'p' to a parameter of a different struct type in a call to 'take'" "R12q: a struct as a tuple argument" "${P}${TK}fn f(): i64 {\n    var p: P;\n    p.a = 1;\n    return take(p);\n}\nsyscall(60, f());\n"
refused r12r "cannot pass 'u' to a parameter of a different struct type in a call to 'take'" "R12r: another tuple type as the argument" "${TK}fn f(): i64 {\n    var u: (i64, f64);\n    u.0 = 1;\n    return take(u);\n}\nsyscall(60, f());\n"
refused r12s "cannot pass 't' to a parameter of a different struct type in a call to 'tp'" "R12s: a tuple as a struct argument" "${P}fn tp(p: P): i64 { return p.a; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    return tp(t);\n}\nsyscall(60, f());\n"

# ── R13: a tuple has no methods ────────────────────────────────────────────────────────────────────
M13="a tuple has no methods"
refused r13a "$M13 - 'm' is not a method of a tuple" "R13a: \`t.m()\`" "${TT}    return t.m();${TE}"
refused r13b "$M13 - 'm' is not a method of a tuple" "R13b: \`t.m();\` as a statement" "${TT}    t.m();${TE}"
refused r13c "$M13 - '0' is not a method of a tuple" "R13c: \`t.0(1)\`" "${TT}    return t.0(1);${TE}"
refused r13d "$M13 - 'm' is not a method of a tuple" "R13d: \`h.p.m()\`, a tuple field" "${TH}fn f(): i64 {\n    var h: H;\n    return h.p.m();\n}\nsyscall(60, f());\n"

# R13e-i: `x.0(..)` on ANY receiver. Since T1 lexed `p.0` as a selector, `p.0()` on a struct resolved as the
# method `P_0` and CALLED a user `fn P_0(self)` (exit 7) — it was "expected identifier, got number 0".
PM='struct P { a; b; }\nfn P_0(self): i64 { return 7; }\n'
D13="a method name cannot start with a digit - '0' is an element selector"
refused r13e "$D13" "R13e: \`p.0()\` on a named struct (a user \`fn P_0(self)\` is not called)" "${PM}fn f(): i64 {\n    var p: P;\n    return p.0();\n}\nsyscall(60, f());\n"
refused r13f "$D13" "R13f: \`p.0();\` as a statement" "${PM}fn f(): i64 {\n    var p: P;\n    p.0();\n    return 3;\n}\nsyscall(60, f());\n"
refused r13g "$D13" "R13g: \`mk().0()\`, on a call's result" "${PM}fn mk(): P {\n    var p: P;\n    return p;\n}\nfn f(): i64 { return mk().0(); }\nsyscall(60, f());\n"
refused r13h "$D13" "R13h: \`q.p.0()\`, on a nested struct field" "${PM}struct Q { p: P; }\nfn f(): i64 {\n    var q: Q;\n    return q.p.0();\n}\nsyscall(60, f());\n"
refused r13i "$D13" "R13i: \`p.0().a\` — the chain after it is consumed (one error)" "${PM}fn f(): i64 {\n    var p: P;\n    var x = p.0().a;\n    return x;\n}\nsyscall(60, f());\n"

# ── R17: a multi-value call is not a tuple argument ───────────────────────────────────────────────
# The parameter takes a tuple's ADDRESS; the call leaves its values in the return registers, so the
# value push handed the callee the first value as an address (x86: SIGSEGV). Bind it first.
MK='fn mk(a): (i64, i64) { return (a, a + 1); }\n'
R17="is not a tuple argument - bind it first: \`var t: (i64, i64) = "
refused r17a "a multi-value call 'mk' $R17" "R17a: \`take(mk(3))\` in a fn" "${MK}${TK}fn f(): i64 { return take(mk(3)) + 1; }\nsyscall(60, f());\n"
refused r17b "a multi-value call 'mk' $R17" "R17b: at top level" "${MK}${TK}syscall(60, take(mk(3)));\n"
refused r17c "a multi-value call 'mk' $R17" "R17c: a tail call, \`mk\` declared below" "${TK}fn f(): i64 { return take(mk(3)); }\n${MK}syscall(60, f());\n"
refused r17d "a multi-value call 'mk' $R17" "R17d: the second argument, in a loop's tail call" "fn take2(k, t: (i64, i64)): i64 { return t.0 * 10 + t.1 + k; }\n${MK}fn f(): i64 {\n    var i = 0;\n    while (i < 3) {\n        if (i == 2) { return take2(1, mk(3)); }\n        i = i + 1;\n    }\n    return 0;\n}\nsyscall(60, f());\n"
refused r17e "a multi-value call 'mk' $R17" "R17e: an explicit generic \`mk<i64>(3)\`" "fn mk<T>(a: T): (i64, i64) { return (a, a + 1); }\n${TK}fn f(): i64 { return take(mk<i64>(3)); }\nsyscall(60, f());\n"
refused r17f "a multi-value call 'mk' $R17" "R17f: \`take((mk(3)))\`, parenthesised" "${MK}${TK}fn f(): i64 { return take((mk(3))); }\nsyscall(60, f());\n"
refused r17g "a multi-value call 'B_mk' $R17" "R17g: a method \`take(b.mk(3))\`" "struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a + self.v); } }\n${TK}fn f(): i64 {\n    var b: B;\n    b.v = 1;\n    return take(b.mk(3));\n}\nsyscall(60, f());\n"
refused r17h "a multi-value call 'P_add' $R17" "R17h: an operator \`take(p + q)\`" "${P}fn P_add(a: P, b: P): (i64, i64) { return (a.a + b.a, a.b + b.b); }\n${TK}fn f(): i64 {\n    var p = P { 1, 2 };\n    var q = P { 3, 4 };\n    return take(p + q);\n}\nsyscall(60, f());\n"

# ── R21: `t.N` spellings that name no element ──────────────────────────────────────────────────────
refused r21a "unknown field '2' on struct '(i64, i64)'" "R21a: \`t.2\` past the arity (a read)" "${TT}    return t.2;${TE}"
refused r21b "unknown field '2' on struct '(i64, i64)'" "R21b: \`t.2 = 1\` (a write)" "${TT}    t.2 = 1;${TE}"
refused r21c "unknown field '01' on struct '(i64, i64)'" "R21c: \`t.01\`" "${TT}    return t.01;${TE}"
refused r21d "unknown field '0x1' on struct '(i64, i64)'" "R21d: \`t.0x1\`" "${TT}    return t.0x1;${TE}"
refused r21e "unknown field '1_0' on struct '(i64, i64)'" "R21e: \`t.1_0\`" "${TT}    return t.1_0;${TE}"

# ── P: positive ────────────────────────────────────────────────────────────────────────────────────
exits p01 59 "P1: \`var t: (i64, i64);\` then \`t.0 = 5; t.1 = 9;\`" 'fn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n'
exits p02 96 "P2: copies are by value (a declaration, an assignment, a field)" "${TH}fn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    var u: (i64, i64) = t;\n    u.0 = 6;\n    var w: (i64, i64);\n    w = u;\n    u.1 = 1;\n    var h: H;\n    h.p = w;\n    w.0 = 0;\n    return h.p.0 * 10 + h.p.1 + t.0 * 0 + (u.1 - 1) * 50 + (t.0 - 5) * 7 + 27;\n}\nsyscall(60, f());\n"
exits p03 23 "P3: a declaration-zone global copied from a struct literal's tuple field" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nsyscall(60, G.0 * 10 + G.1);\n"
exits p04 61 "P4: f64 and bool elements keep their kind" 'fn f(): i64 {\n    var t: (i64, f64, bool);\n    t.0 = 6;\n    t.1 = 0.5;\n    t.2 = true;\n    t.1 *= 2.0;\n    var k = 0;\n    if (t.2) { k = 1; }\n    if (t.1 == 1.0) { k = k + t.0 * 10; }\n    return k;\n}\nsyscall(60, f());\n'
exits p05 64 "P5: a tuple parameter is the callee's copy (its write never reaches the caller)" 'fn take(t: (i64, i64), k): i64 {\n    t.0 = t.0 + 100;\n    return t.0 * 10 + t.1 + k;\n}\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    var r = take(t, 1000);\n    return r - 1000 + t.0;\n}\nsyscall(60, f() - 1000);\n'
# P6: `#inline` on a fn with a tuple parameter falls back to a call (the struct rule, `_inl_param_why`)
printf '#inline\nfn ti(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 4;\n    t.1 = 2;\n    return ti(t) + ti((t));\n}\nsyscall(60, f());\n' > "$T/p06.cyr"
build p06
if [ "$rc" -ne 0 ]; then bad "P6: rc $rc: $(grep '^error' "$T/p06.err" | head -1)"
elif ! grep -q "#inline ignored: struct/aggregate parameter" "$T/p06.err"; then bad "P6: no '#inline ignored' warning: $(head -1 "$T/p06.err")"
else chmod +x "$T/p06.bin"; got=0; timeout 10 "$T/p06.bin" || got=$?
    if [ "$got" -eq 84 ]; then ok "P6: \`#inline\` with a tuple parameter: a call (warned), exit 84"; else bad "P6: exit $got, want 84"; fi
fi

# ── X: --syntax-only (cyrius lint's pre-pass) ──────────────────────────────────────────────────────
# A fn with a tuple parameter, its call, and calls to a sibling file's fns (unknown here) with a tuple
# argument and a sibling's call as a tuple argument: nothing tuple-related is reported.
printf 'fn take(t: (i64, i64), k): i64 { return t.0 * 10 + t.1 + k; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n    return take(t, 3) + sib_take(t, 4) + take(sib_mk(), 5);\n}\nsyscall(60, f());\n' > "$T/x03.cyr"
"$CC" --syntax-only < "$T/x03.cyr" > /dev/null 2> "$T/x03.err" || true
if grep -q "tuple\|^error:<source>" "$T/x03.err"; then bad "X3: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x03.err")"
else ok "X3: --syntax-only: a tuple parameter, a sibling's fn given a tuple, a sibling's call as a tuple argument — silent"; fi

# ── A: tests/tcyr/crossos/tuple_values.tcyr on every pipeline and target ───────────────────────────
TV="$ROOT/tests/tcyr/crossos/tuple_values.tcyr"
want=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TV")
[ "$want" -ge 65 ] || bad "A0: only $want assertions derived from $TV (floor 65)"
tcyr_ok() {   # <label> <output file> <exit> <want>
    if [ "$3" -eq 0 ] && grep -q "^$4 passed, 0 failed" "$2"; then ok "$1: $4 passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
for mode in plain IR1 IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="A1 x86" ;;
        IR1) env_="CYRIUS_IR=1"; lbl="A2 x86, CYRIUS_IR=1" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="A3 x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="A4 x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$TV" > "$T/tv.$mode" 2> "$T/tv.$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/tv.$mode.err" | head -1)"; continue; fi
    chmod +x "$T/tv.$mode"; got=0; timeout 60 "$T/tv.$mode" > "$T/tv.$mode.out" 2>&1 || got=$?
    tcyr_ok "$lbl" "$T/tv.$mode.out" "$got" "$want"
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        if "$T/cc_a64" < "$TV" > "$T/tv.a" 2> "$T/tv.aerr"; then
            chmod +x "$T/tv.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./tv.a > "$T/tv.aout" 2>&1) || got=$?
            tcyr_ok "A5 aarch64 (qemu)" "$T/tv.aout" "$got" "$want"
        else bad "A5 aarch64: the tcyr did not compile: $(grep '^error' "$T/tv.aerr" | head -1)"; fi
    else bad "A5: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A5 aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$TV" > "$T/tv.cyx" 2> "$T/tv.cxerr" && [ -s "$T/tv.cyx" ]; then
        got=0; timeout 120 "$T/cxvm" < "$T/tv.cyx" > "$T/tv.cxout" 2>&1 || got=$?
        tcyr_ok "A6 cx (cxvm)" "$T/tv.cxout" "$got" "$want"
    else bad "A6 cx: the tcyr did not compile: $(grep '^error' "$T/tv.cxerr" | head -1)"; fi
else bad "A6: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$TV" > "$T/tv.exe" 2> "$T/tv.werr" && [ -s "$T/tv.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./tv.exe > "$T/tv.wout" 2>/dev/null) || got=$?
        tcyr_ok "A7 PE (wine)" "$T/tv.wout" "$got" "$want"
    else bad "A7 PE: the tcyr did not compile: $(grep '^error' "$T/tv.werr" | head -1)"; fi
else echo "  SKIP A7 PE — wine not installed"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: tuple_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: tuple_checked — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: tuple_checked — tuples: the lexer (L); the type in a var, a struct field and a parameter, \`t.N\`, copies (S, P); every open shape refused by name (R1-R4, R6, R11-R13, R17, R21); --syntax-only silent (X); tuple_values.tcyr on x86 / IR / DCE / aarch64 / cx / PE (A)"
