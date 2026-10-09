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
#   T4 — the literal `(a, b)`, accepted in five positions (a `var` initializer in a fn and in either
#      global zone, an assignment to a tuple variable, a tuple field store, a tuple argument, and
#      `return`'s multi-value arm) and refused by name everywhere else:
#      C  compatibility — `(|a, b| ..)` and `(pk<A, B>(..))` stay one value as an initializer and a
#         `return` (PARSE_RETURN's paren-depth comma scan took the two returns for multi-value ones)
#      S1 a wrapped `((a, b))` in every accepting position; S4 a zone literal global's neighbour
#         intact (8n bytes registered in pass 1); K1 `kernel;` parity with a struct literal global
#         (constant elements baked, a call element named late)
#      R2 a literal's shape (trailing comma, empty element, arity, > 256); R4d an un-annotated literal
#         in a generic fn; R5 a tuple in a const context; R7 an un-annotated float element ("declare
#         the tuple's type", the user's decision 2026-10-09); R8 a struct / tuple / u128 / vector /
#         slice element (a `Str` handle and a `*T` are i64s, R8i), an integer into an f64 element
#         warned (R8j); R9 a literal in any other position; R10 a literal assignment / field store /
#         argument at top level (no frame for its temp)
#      PW every `_pwrap_k` caller that can see a literal gives a named outcome, never "expected ')'"
#      AS a literal local in a suspending `async fn`, read and re-assigned across awaits; SEC1
#         `secret var t = ( .. );` wiped whole at the epilogue
#   T5 — the bridge: a tuple CAPTURES a multi-value call by its type (`var t: T = f();`, `t = f();`, `G = f();`,
#      both global zones), `return t;` from a fn declared with its values, and `a, b = f();` re-assigning
#      existing variables (the positive shapes are tuple_values.tcyr's capture / returns / reassign, the A rows):
#      R14 `return t;` from a fn that does not declare those values (S6: an undeclared fn's, refused once), an
#         arity / class mismatch, a closure, an `async fn`, `return h.p;`
#      R15 `f().0` on a multi-value call: the refusal says how to read the values
#      R16 a capture refused: a struct / vector callee, an arity or element-class disagreement, > 3 elements, a
#         `: f64` callee into a non-f64 element, an unchecked callee into a bool element; a one-value callee, a
#         wrapped call, `f()?`, `callptr` and a call that is not the whole value are R12 ("not a tuple")
#      R17i-l a multi-value call stored into a tuple FIELD: bind it first
#      R18 `a, b = f()` targets that are no plain variable, > 3, a duplicate, a const / enum constant, a struct /
#         tuple / vector / array / u128 / slice / f32 target, a bool target from a non-bool value, an undefined
#         or captured name; R19 a right-hand side that is not one whole call (the destructure's texts);
#         R20 `(a, b) = f();` / `var (q, r) = f();` unchanged
#      AS2 a capture, a re-capture and `a, q = f()` in a SUSPENDING `async fn` across awaits (CG1: the stores are
#         addressed — the coroutine's heap frame orders an aggregate from its low slot)
#   X  `--syntax-only` (cyrius lint's pre-pass): a fn with a tuple parameter, and a call to a
#      sibling file's fn with a tuple argument, report nothing; X4 literals, a sibling's fn given one;
#      X5 sibling targets and callees in captures and `a, b = f()`, `return t;`
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
# T4 (2026-10-09; the same recipe, run FROM the scratch copy so its cross legs build from the mutated
# src too; each mutant measured RED, the real tree 187/187):
#   M4  no zone fold (`_gci_inline` without `_tup_gci`) -> S1, S4, K1, R10a and A1-A7 (pass 1 registered
#       an 8-byte pointer-mode slot: "cannot initialize tuple 'G' with a value that is not a tuple")
#   M5  no literal arm before the unwraps (`_tup_asg` in `_try_aggregate_copy_assign`, `_tup_sarg_lit` in
#       `_sarg_paren`) -> S1, R2j, R2k, R9c, R9k, R10a, R10b, PW1 / PW3 ("expected ')'" or the value
#       refusal), AS1, X4 and A1-A7
#   M6  the literal argument without `_sarg_escapes` -> A1-A7: the tailcalls rows (the `jmp` kept: same
#       depth, and the temp read from the freed frame, 52 where 60 is right)
#   M7a the local literal's span recorded LAST (after its stores) -> AS1 (the coroutine frame splits it)
#   M7b the local / temp element stores through EFLSTORE -> AS1 and A3 (CYRIUS_IR=3: the swap reads 0)
#   M12 a non-tuple annotation's literal taken as `(i64 x n)` -> R9d-R9g, PW4 (BUILT, or a cascade). The
#       plan's M12 shape (`var t: T = 5;` built) is T2's M10b, the pointer-mode refusal, already measured.
#   M20 `_tup_lit_stray` removed -> R8g, R9a, R9b, R9d-R9i, R9l-R9n, R9p-R9r, PW4, PW5, PW7-PW9, X4
#       ("expected ')', got ','", or a second error after the named one)
#   M21 `_tup_commas` without the closure / generic steps (`_tok_item_end` alone) -> C1-C4
# THE EVIDENCE BEYOND THESE ROWS (T4, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in src lib programs cbt
# tests benches fuzz bootstrap docs/development/issues but tuple_values.tcyr (1034 files) compiles byte-identical —
# stdout, stderr and exit code; default, CYRIUS_DCE=1 and --syntax-only — with the T4 compiler and the T3 one, and
# the aarch64, cx and PE compilers likewise over all 537 other tests/tcyr files.
# T5 (2026-10-09; the same recipe, run FROM the scratch copy; each mutant measured RED, the real tree 269/269 —
# the crossos file at 168 assertions):
#   M8a the drain stores in push order (slot k takes the value pushed k-th from the top) -> AS2 and A1-A7 (`(5, 9)`
#       captured as 95, arity 3 as 321)
#   M8b arity 3 without `EMOVRA_R3` (the third value is rdx's again) -> AS2 and A1-A7 (122 where 123 is right, in a
#       capture, a zone capture and `a, b, c = f()`)
#   M8c (CG1) a local capture's slots stored through EFLSTORE, not addressed -> AS2 (the coroutine frame's word order;
#       the stack frame's and IR=3's happen to agree)
#   M9  no `_ret_tuple_var` -> R14a-c, R14f-j, R14l, R14m, R14o, R14p (the value refusal instead) and A1-A7 (the
#       file does not build); R14d gives two errors
#   M10 `return t;` loads slot 1 into rax and slot 0 into rdx -> A1-A7 (`return t;` 95 where 59 is right)
#   M10b the pointer-mode backstop removed (`_tup_ptr_refuse` returns 0) -> R12e-i and R16k-o BUILD (the capture
#       declines those right-hand sides to it)
#   M13 no `_tup_asg` call arm -> R16p, R16w, AS2 and A1-A7 (`t = f();` is "not a tuple"; a `: stack` pair "bind both")
#   M15 `_masg_stmt` without `_dt_arity_check` -> R19f, R19g BUILD
#   M19 the capture's class check removed (`_tup_cap_class` -> 1) -> R16a-k, R16p, R16r-t, R16v, R16w, R12c, R12g BUILD
#   M22 PARSE_FIELD_STORE's first-target `,` refusal removed -> R18a, R18d ("expected '=', got ','")
#   M23 `_masg_stmt` reads its targets back from `_masg_ix` AFTER the call -> A1-A7 (a multi-value assignment in a
#       closure among the arguments re-used the table: the outer stores went to the closure's slots, 26 where 813)
#   (`_ret_tuple_var` runs for every `return`: its wrap scan is one linear pass. A `_pwrap_k` peel there was
#   quadratic in the depth — tests/gates/diagnostics/recursion_depth_bounded.sh's `nested parens @ 65536`
#   timed out, 99 s — and that row is the guard.)
# THE EVIDENCE BEYOND THESE ROWS (T5, 2026-10-09): the same 1034 files compile byte-identical — stdout, stderr and exit
# code; default, CYRIUS_DCE=1 and --syntax-only — with the T5 compiler and the T4 one, and the aarch64, cx and PE
# compilers likewise over all 537 other tests/tcyr files.
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
refused r04d "a tuple type in a generic fn is refused" "R4d: an un-annotated literal in a generic fn (it mints its type there; once over the instances)" 'fn g<T>(x: T): T {\n    var t = (x, 1);\n    return t.0;\n}\nfn f(): i64 { return g(3) + g(4); }\nsyscall(60, f());\n'

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

# ── T4: the literal `(a, b)` ───────────────────────────────────────────────────────────────────────
# C — compatibility (the planners' q1 / q5 / q7 / q8). PARSE_RETURN's own paren-depth comma scan took
# `return (|a, b| a + b);` and `return (pk<i64, i64>(1, 2));` for multi-value returns ("expected ','");
# the literal's ONE detector (`_tup_commas`) steps a leading closure's bars and a generic call's type
# arguments, so both return their value and the two parenthesised initialisers stay one value.
CL='include "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\n'
GP='fn pk<A, B>(x: A, y: B): i64 { return 40 + x; }\n'
exits c01 7 "C1: \`var f = (|a, b| a + b);\` is still a parenthesised closure" "${CL}fn m(): i64 { var f = (|a, b| a + b); return fncall2(f, 3, 4); }\nalloc_init();\nsyscall(60, m());\n"
exits c02 7 "C2: \`return (|a, b| a + b);\` returns the closure (it was \"expected ','\")" "${CL}fn mk() { return (|a, b| a + b); }\nfn m(): i64 { var f = mk(); return fncall2(f, 3, 4); }\nalloc_init();\nsyscall(60, m());\n"
exits c03 41 "C3: \`return (pk<i64, i64>(1, 2));\` returns the call (it was \"expected ','\")" "${GP}fn m(): i64 { return (pk<i64, i64>(1, 2)); }\nsyscall(60, m());\n"
exits c04 41 "C4: \`var r = (pk<i64, i64>(1, 2));\` is still one value" "${GP}fn m(): i64 { var r = (pk<i64, i64>(1, 2)); return r; }\nsyscall(60, m());\n"

# S1 — a WRAPPED literal `((a, b))` in every accepting position (the 6.7.6 transparency rule; `_pwrap_k`
# counts the literal's own `(` as a wrap, so an unwrap that stepped inside parsed `1` then "expected ')'").
exits s01 42 "S1: \`((a, b))\` as a local (typed, inferred), an assignment, a field store, an argument, a global in either zone" 'struct H { a; p: (i64, i64); }\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nvar G: (i64, i64) = ((1, 2));\nfn f(): i64 {\n    var t: (i64, i64) = ((3, 4));\n    var u = ((5, 6));\n    t = ((t.1, t.0));\n    var h: H;\n    h.p = ((7, 8));\n    return take(((9, 1))) - 91 + take(t) - 43 + take(u) - 56 + take(h.p) - 78 + take(G) - 12;\n}\nsyscall(1, 1, "", 0);\nvar G2 = ((2, 3));\nsyscall(60, f() + G2.0 * 10 + G2.1 + 19);\n'
# S4 — a declaration-zone tuple literal global is registered 8n bytes inline (pass 1's `_tup_gci`): an
# element write leaves the next global intact (one 8-byte slot would put `G.1` on it).
exits s04 77 "S4: zone \`var G: (i64, i64) = (1, 2); var H = 7;\` (and an un-annotated one): H intact after \`G.1 = 9\`" 'var G: (i64, i64) = (1, 2);\nvar H = 7;\nvar U = (3, 4);\nvar V = 70;\nG.1 = 9;\nU.1 = 9;\nsyscall(60, H + V + (G.1 - 9) + (U.1 - 9) + (G.0 - 1) + (U.0 - 3));\n'

# K1 — `kernel;` parity with a struct literal global: in an x86 kernel build the deferred replay runs
# AFTER the top-level program, so a zone literal of constants is BAKED into the image exactly as
# `var G = P { 3, 4 };` is (`_spc_try`, closing at the tuple's `)`; float elements and `-1.5` too), and
# one with a call element stays late and is named — as the struct literal with a call is.
cat > "$T/k01.cyr" <<'EOF'
kernel;
struct KP { a; b; }
var KS = KP { 3, 4 };
var KT: (i64, i64) = (3, 4);
var KU = (5, 6);
var KF: (i64, f64) = (7, 2.5);
var KN: (i64, f64) = (8, -1.5);
fn kf(): i64 { return 9; }
var KW = (kf(), 1);
var KX = KP { kf(), 1 };
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(KS.a * 10 + KS.b, 34, 1);
ck(KT.0 * 10 + KT.1, 34, 2);
ck(KU.0 * 10 + KU.1, 56, 3);
ck(load64(&KF + 8), 0x4004000000000000, 4);
ck(KF.0, 7, 5);
ck(load64(&KN + 8), 0xBFF8000000000000, 6);
ck(KW.0 + KW.1, 0, 7);
ck(KX.a + KX.b, 0, 8);
syscall(60, 100);
EOF
rc=0; CYRIUS_ELF64_KERNEL=1 "$CC" < "$T/k01.cyr" > "$T/k01.bin" 2> "$T/k01.err" || rc=$?
KW_='in a kernel build the initializer of'
if [ "$rc" -ne 0 ]; then bad "K1: the ELF64 kernel build failed: $(grep -m1 '^error' "$T/k01.err")"
else chmod +x "$T/k01.bin"; got=0; timeout 10 "$T/k01.bin" > /dev/null 2>&1 || got=$?
    nw=$(grep -c "$KW_" "$T/k01.err" || true)
    if [ "$got" -ne 100 ]; then bad "K1: the kernel program read a wrong value at check $got (2-6 a baked tuple, 7 the late one)"
    elif [ "$nw" -ne 2 ] || ! grep -q "$KW_ 'KW'" "$T/k01.err" || ! grep -q "$KW_ 'KX'" "$T/k01.err"; then bad "K1: $nw late-initializer warnings, want exactly KW and KX: $(grep "$KW_" "$T/k01.err" | head -3 | tr '\n' '|')"
    else ok "K1: kernel build — constant zone tuples baked (the struct literal's parity), the call element named late"; fi
fi

# R2 — a literal's own shape.
TL='fn take(t: (i64, i64)): i64 { return t.0; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n'
refused r02f "a trailing comma in a tuple literal" "R2f: \`(1, 2,)\`" "${TL}    var q = (1, 2,);${TE}"
refused r02g "a trailing comma in a tuple literal" "R2g: \`(1,)\` (one error)" "${TL}    var q = (1,);${TE}"
refused r02h "an empty element in a tuple literal" "R2h: \`(1, , 2)\`" "${TL}    var q = (1, , 2);${TE}"
refused r02i "tuple (i64, i64) has 2 elements - this literal has 3" "R2i: an annotated literal of another arity (the name is still declared: no cascade)" "${TL}    var q: (i64, i64) = (1, 2, 3);\n    q.0 = 4;\n    return q.0;${TE}"
refused r02j "tuple (i64, i64) has 2 elements - this literal has 3" "R2j: assigned" "${TL}    t = (1, 2, 3);${TE}"
refused r02k "tuple (i64, i64) has 2 elements - this literal has 3" "R2k: an argument \`take((1, 2, 3))\`" "${TL}    return take((1, 2, 3));${TE}"
big='(0'; i=1; while [ $i -lt 257 ]; do big="$big, $i"; i=$((i + 1)); done; big="$big)"
refused r02l "a tuple literal has at most 256 elements" "R2l: 257 elements" "${TL}    var q = ${big};${TE}"

# R5 — a tuple is not a constant: refused by the const evaluator (`_ce_factor`), by name.
refused r05a "a tuple in a const context" "R5a: \`const C = (1, 2);\` (it was \"expected ')', got ','\")" 'const C = (1, 2);\nsyscall(60, 0);\n'
refused r05b "a tuple in a const context" "R5b: a tuple literal in a const fn's evaluation" 'const fn cf(x: i64): i64 {\n    var t = (x, 1);\n    return t.0;\n}\nconst C = cf(3);\nsyscall(60, C);\n'
refused r05c "a tuple in a const context" "R5c: \`#assert (1, 2) == 3\`" 'fn f(): i64 {\n    #assert (1, 2) == 3, "x"\n    return 0;\n}\nsyscall(60, f());\n'
refused r05d "a tuple in a const context" "R5d: \`return (x, 1)\` in a const fn's evaluation" 'const fn cf(x: i64): i64 {\n    return (x, 1);\n}\nconst C = cf(3);\nsyscall(60, C);\n'

# R7 — an UN-annotated literal's elements are i64 (ADR-002: an untyped float is an integer); a float
# element is refused: declare the tuple's type (the user's decision, 2026-10-09).
D7="declare the tuple's type"
refused r07a "$D7" "R7a: \`var p = (1, 2.5);\`" "${TL}    var p = (1, 2.5);${TE}"
refused r07b "$D7" "R7b: an f64-typed element \`(1, y)\`" "${TL}    var y: f64 = 1.5;\n    var p = (1, y);${TE}"
refused r07c "$D7" "R7c: a declaration-zone global \`var G = (1, 2.5);\`" 'var G = (1, 2.5);\nsyscall(60, 0);\n'
refused r07d "$D7" "R7d: a global after the first statement" 'syscall(1, 1, "", 0);\nvar G = (2.5, 1);\nsyscall(60, 0);\n'
exits r07e 25 "R7e: annotated, \`var p: (i64, f64) = (1, 2.5);\` is an f64 element" 'fn f(): i64 {\n    var p: (i64, f64) = (1, 2.5);\n    if (p.1 == 2.5) { return 25; }\n    return 1;\n}\nsyscall(60, f());\n'

# R8 — an element is an i64 / f64 / bool VALUE: a struct (by its static type; a heap handle and a
# `*T` are pointers, i64s), a tuple, a u128, a vector and a slice are refused by name.
E8="a tuple element is i64, f64 or bool, not"
refused r08a "$E8 struct 'P'" "R8a: a struct local \`(p, 1)\`" "${P}${TL}    var p: P;\n    var q = (p, 1);${TE}"
refused r08b "tuple 't' used as a value" "R8b: a tuple \`(t, 1)\` (its factor's refusal, once)" "${TL}    var q = (t, 1);${TE}"
refused r08c "$E8 u128" "R8c: a u128" "${TL}    var w: u128 = 5;\n    var q = (w, 1);${TE}"
refused r08d "$E8 a vector" "R8d: an f64v2" "${TL}    var v: f64v2;\n    var q = (v, 1);${TE}"
refused r08e "$E8 a slice" "R8e: a slice" "${TL}    var s: [u8] = 0;\n    var q = (s, 1);${TE}"
refused r08f "$E8 struct 'P'" "R8f: a struct-valued call \`(mk(), 1)\`" "${P}fn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\n${TL}    var q = (mk(), 1);${TE}"
refused r08g "a tuple \`( .. )\` is a value only" "R8g: a nested literal \`((1, 2), 3)\`" "${TL}    var q = ((1, 2), 3);${TE}"
refused r08h "cannot store a value that is not a bool into bool field '1'" "R8h: a non-bool into a bool element" "${TL}    var q: (i64, bool) = (1, 5);${TE}"
exits r08i 7 "R8i: a \`Str\` handle and a \`*T\` are pointers — i64 elements" "include \"lib/str.cyr\"\n${P}fn f(): i64 {\n    alloc_init();\n    var p: P;\n    p.a = 4;\n    var pp: *P = &p;\n    var s = str_from(\"abc\");\n    var q = (s, pp);\n    return str_len(q.0) + load64(q.1);\n}\nsyscall(60, f());\n"
printf 'fn f(): i64 {\n    var q: (f64, i64) = (1, 5);\n    return q.1;\n}\nsyscall(60, f());\n' > "$T/r08j.cyr"
build r08j
if [ "$rc" -ne 0 ]; then bad "R8j: rc $rc: $(grep '^error' "$T/r08j.err" | head -1)"
elif ! grep -q "an integer stored into an f64/f32 slot keeps its integer bits" "$T/r08j.err"; then bad "R8j: no keep-its-bits warning: $(head -1 "$T/r08j.err")"
else chmod +x "$T/r08j.bin"; got=0; timeout 10 "$T/r08j.bin" || got=$?
    if [ "$got" -eq 5 ]; then ok "R8j: an integer into an f64 element keeps its bits, warned (the struct literal's rule), exit 5"; else bad "R8j: exit $got, want 5"; fi
fi

# R9 — a literal anywhere outside the five accepting positions: refused by name, once, the parse in step.
S9="a tuple \`( .. )\` is a value only as a \`var\` initializer, assigned to a tuple variable or field, as a tuple argument, or after \`return\` - here one value is expected"
TG="${P}struct HP { a; q: P; }\nfn g(x): i64 { return x; }\nfn tp(p: P): i64 { return p.a; }\n${TL}"
refused r09a "$S9" "R9a: an operand \`(1, 2) + 3\`" "${TG}    var x = (1, 2) + 3;${TE}"
refused r09b "$S9" "R9b: an untyped parameter's argument \`g((1, 2))\`" "${TG}    return g((1, 2));${TE}"
refused r09c "a tuple literal is passed only to a tuple parameter - this parameter of 'tp' is not a tuple" "R9c: a struct parameter's argument" "${TG}    return tp((1, 2));${TE}"
refused r09d "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "R9d: \`var k: i64 = (1, 2);\` (k still declared)" "${TG}    var k: i64 = (1, 2);\n    return k;${TE}"
refused r09e "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "R9e: a struct annotation" "${TG}    var k: P = (1, 2);\n    return k.a;${TE}"
refused r09f "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "R9f: a bool annotation" "${TG}    var k: bool = (1, 2);${TE}"
refused r09g "a tuple literal cannot initialize 's' - its declared type is not a tuple" "R9g: a slice annotation" "${TG}    var s: [u8] = (1, 2);${TE}"
refused r09h "$S9" "R9h: \`(1, 2).0\`" "${TG}    var x = (1, 2).0;${TE}"
refused r09i "$S9" "R9i: an if-expression branch" "${TG}    var x = if (t.0 == 1) { (1, 2) } else { 0 };${TE}"
refused r09j "unexpected '('" "R9j: an expression statement \`(1, 2);\` keeps its error" "${TG}    (1, 2);${TE}"
refused r09k "cannot assign a tuple literal to 'p' - it is not a tuple" "R9k: into a struct variable" "${TG}    var p: P;\n    p = (1, 2);${TE}"
refused r09l "$S9" "R9l: into a scalar variable \`x = (1, 2);\`" "${TG}    var x = 0;\n    x = (1, 2);${TE}"
refused r09m "$S9" "R9m: \`callptr(fp, (1, 2))\`" "${TG}    var fp = &g;\n    return callptr(fp, (1, 2));${TE}"
refused r09n "$S9" "R9n: \`return ((1, 2));\` (a multi-value return keeps its exact spelling)" "fn mk(): (i64, i64) { return ((1, 2)); }\nfn f(): i64 {\n    var a, b = mk();\n    return a;\n}\nsyscall(60, f());\n"
refused r09o "cannot store a tuple literal into field 'q' - it is not a tuple" "R9o: into a struct field of another type" "${TG}    var h: HP;\n    h.q = (1, 2);${TE}"
refused r09p "$S9" "R9p: into a scalar field" "${TG}    var h: HP;\n    h.a = (1, 2);${TE}"
refused r09q "$S9" "R9q: a struct-literal element \`P { (1, 2), 3 }\`" "${TG}    var h = P { (1, 2), 3 };${TE}"
refused r09r "$S9" "R9r: a \`match\` scrutinee" "${TG}    match (1, 2) { 1 => { return 1; } _ => { return 0; } }${TE}"

# R10 — at top level an assignment, field store or argument has no frame for the literal's temp.
refused r10a "a tuple literal assigned at top level has no frame to be built in - assign 'G' inside a fn" "R10a: \`G = (3, 4);\` at top level" 'var G: (i64, i64) = (1, 2);\nG = (3, 4);\nsyscall(60, G.0);\n'
refused r10b "a tuple literal argument at top level has no frame to be built in - call 'take' inside a fn" "R10b: \`take((1, 2))\` at top level" 'fn take(t: (i64, i64)): i64 { return t.0; }\nsyscall(60, take((1, 2)));\n'
refused r10c "a tuple literal stored at top level has no frame to be built in - store it into 'p' inside a fn" "R10c: \`GH.p = (5, 6);\` at top level" "${TH}var GH = H { 1, 2, 3, 4 };\nGH.p = (5, 6);\nsyscall(60, GH.a);\n"

# PW — every `_pwrap_k` caller that can see a literal gives a NAMED outcome, never "expected ')'":
# `_asg_paren`, `_fsc_paren`, `_sarg_paren` (accept: S1; refuse: R9k R9o R9c wrapped below),
# `_gci_src` / `_gci_take` (the zone fold claims first: S1), `_sci_pname` / `_scv_peel` (`_tup_var`
# claims first), `_ret_peel` (both struct-return classes) and `_ret_expr_head`, `_op_big_arm` /
# `_op_rhs_pair_call` (an operator's right operand: the factor's refusal).
B3='struct B3 { a; b; c; }\n'
refused pw1 "cannot assign a tuple literal to 'p' - it is not a tuple" "PW1: \`p = ((1, 2));\`, a struct variable (_asg_paren)" "${TG}    var p: P;\n    p = ((1, 2));${TE}"
refused pw2 "cannot store a tuple literal into field 'q' - it is not a tuple" "PW2: \`h.q = ((1, 2));\` (_fsc_paren)" "${TG}    var h: HP;\n    h.q = ((1, 2));${TE}"
refused pw3 "a tuple literal is passed only to a tuple parameter - this parameter of 'tp' is not a tuple" "PW3: \`tp(((1, 2)))\` (_sarg_paren)" "${TG}    return tp(((1, 2)));${TE}"
refused pw4 "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "PW4: \`var k: P = ((1, 2));\` (_scv_peel / _sci_pname)" "${TG}    var k: P = ((1, 2));\n    return k.a;${TE}"
refused pw5 "$S9" "PW5: \`return ((1, 2));\` from a 16-byte \`: P\` fn (_ret_peel, the pair class)" "${P}fn mk(): P { return ((1, 2)); }\nfn f(): i64 {\n    var p: P = mk();\n    return p.a;\n}\nsyscall(60, f());\n"
refused pw6 "struct-return fn: return must be a bare local identifier" "PW6: \`return ((1, 2));\` from a 24-byte \`: B3\` fn (_ret_peel, the retptr class: its own refusal)" "${B3}fn mk(): B3 { return ((1, 2)); }\nfn f(): i64 {\n    var p: B3 = mk();\n    return p.a;\n}\nsyscall(60, f());\n"
refused pw7 "$S9" "PW7: \`return ((1, 2)) + 1;\` (_ret_expr_head)" 'fn mk(): i64 { return ((1, 2)) + 1; }\nsyscall(60, mk());\n'
refused pw8 "$S9" "PW8: \`p + (1, 2)\`, a by-value struct operand (_op_big_arm)" "${P}fn P_add(a: P, b: P): P {\n    var r: P;\n    r.a = a.a + b.a;\n    r.b = a.b + b.b;\n    return r;\n}\nfn f(): i64 {\n    var p = P { 1, 2 };\n    var q = p + (1, 2);\n    return q.a;\n}\nsyscall(60, f());\n"
refused pw9 "$S9" "PW9: \`p + ((1, 2))\` into a tuple operand (_op_rhs_pair_call)" "${P}fn P_add(a: P, b: (i64, i64)): P {\n    var r: P;\n    r.a = a.a + b.0;\n    r.b = a.b + b.1;\n    return r;\n}\nfn f(): i64 {\n    var p = P { 1, 2 };\n    var q = p + ((1, 2));\n    return q.a;\n}\nsyscall(60, f());\n"

# SEC — `secret var t = (..);` is wiped at the epilogue, all 8n bytes (the struct rule: the slot delta
# PARSE_VAR's literal reserved). The frame-reuse scan of tests/tcyr/lang/secret.tcyr; the plain control
# proves the scan sees a survivor. (Measured on aarch64 / cx / PE too, 2026-10-09.)
exits sec1 0 "SEC1: \`secret var t = (S, S, S, S);\` and \`secret var w: (i64, i64) = (..);\` leave nothing on the stack" 'var SEC = 0x5EC5EC5EC5EC5EC5;\nfn write_secret(): i64 {\n    secret var t = (SEC, SEC, SEC, SEC);\n    var u: (i64, i64) = (t.0 + 1, t.3 + 1);\n    secret var w: (i64, i64) = (u.1 - 1, SEC);\n    return 0;\n}\nfn write_plain(): i64 {\n    var t = (SEC, SEC, SEC, SEC);\n    var w: (i64, i64) = (t.1, SEC);\n    return 0;\n}\nfn scan_for_secret(): i64 {\n    var window: i64[64];\n    var found = 0;\n    var i = 0;\n    while (i < 64) {\n        if (load64(&window + i * 8) == SEC) { found = found + 1; }\n        i = i + 1;\n    }\n    return found;\n}\nfn f(): i64 {\n    write_secret();\n    var a = scan_for_secret();\n    write_plain();\n    var b = scan_for_secret();\n    if (a != 0) { return 10 + a; }\n    if (b == 0) { return 99; }\n    return 0;\n}\nsyscall(60, f());\n'

# AS — a literal local in a SUSPENDING `async fn` (CYRIUS_ASYNC=1), read and re-assigned across awaits:
# the block's span is recorded before its first store and every store is addressed, so the coroutine's
# heap frame (whose slots ascend, `_ECORO_AGG_OFF`) holds it whole.
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc4"; chmod +x "$T/acc4"
CC_SV=$CC; CC="$T/acc4"
exits as1 0 "AS1: \`var t = (5, 6, 7);\` in a suspending async fn, \`t = (t.2, t.0, b);\` between awaits" 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nstruct P2 { x; y; }\nfn nopark(): i64 { return 0; }\nasync fn steps(C): i64 {\n    var a = 3;\n    var t = (5, 6, 7);\n    var p = P2 { 1, 2 };\n    var b = 4;\n    var s1 = await nopark();\n    t = (t.2, t.0, b);\n    var s2 = await nopark();\n    return t.0 * 1000 + t.1 * 100 + t.2 * 10 + a + p.y * 10000;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(0);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    if (r3 != 27543) { syscall(60, 1); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# ── T5: the bridge — a tuple CAPTURES a multi-value call by its type, `return t;`, `a, b = f();` ────
# The positive shapes (every callee class, `t = f()`, a for step, both global zones, `return t;` from a
# local / parameter / global / defer fn / loop / #inline replay, `a, b = f()` everywhere, the re-poll
# loop) are tests/tcyr/crossos/tuple_values.tcyr's `capture` / `returns` / `reassign` (the A rows).
MK='fn mk(a): (i64, i64) { return (a, a + 1); }\n'
MF='fn mkf(a): (i64, f64) { return (a, 1.5); }\n'
F5='fn f(): i64 {\n'
F5V='fn f(): i64 {\n    var a = 0;\n    var b = 0;\n'
E5='\n    return 0;\n}\nsyscall(60, f());\n'
CAP="cannot capture '"
# R14 — `return t;` from a fn that does not declare those values: refused by name (it was the value refusal).
RT="cannot return tuple 't' (i64, i64)"
RTD=" - a tuple is returned by a fn declared with its values, \`: (i64, i64)\`"
TL5='    var t = (1, 2);\n    return t;\n}\n'
refused r14a "$RT$RTD" "R14a (S6): an undeclared fn's \`return t;\`, refused once" "fn g() {\n${TL5}syscall(60, g());\n"
refused r14b "$RT$RTD" "R14b: a scalar fn" "fn g(): i64 {\n${TL5}syscall(60, g());\n"
refused r14c "$RT$RTD" "R14c: an 8-byte struct fn (its value class)" "struct Q { a; }\nfn g(): Q {\n${TL5}syscall(60, 0);\n"
refused r14d "is returned in two registers, so \`return\` takes a local of that struct or a call returning it" "R14d: a 9-16 B struct fn: its own class refuses \`t\` (once)" "${P}fn g(): P {\n${TL5}syscall(60, 0);\n"
refused r14e "struct-return: identifier type != fn ret_sid" "R14e: a retptr struct fn: \`_ret_struct_big\` reports first" "struct P3 { a; b; c; }\nfn g(): P3 {\n    var t = (1, 2, 3);\n    return t;\n}\nsyscall(60, 0);\n"
refused r14f "$RT$RTD" "R14f: a vector fn" "fn g(): f64v2 {\n${TL5}syscall(60, 0);\n"
refused r14g "$RT from 'g' - it returns (i64, i64, i64)" "R14g: an arity mismatch" "fn g(): (i64, i64, i64) {\n${TL5}syscall(60, 0);\n"
refused r14h "$RT from 'g' - it returns (i64, f64)" "R14h: an element class mismatch (i64 / f64)" "fn g(): (i64, f64) {\n${TL5}syscall(60, 0);\n"
refused r14i "$RT from 'g' - it returns (bool, i64)" "R14i: an i64 element into a declared bool value" "fn g(): (bool, i64) {\n${TL5}syscall(60, 0);\n"
refused r14j "cannot return tuple 't' (bool, i64) from 'g' - it returns (i64, i64)" "R14j: a bool element into a declared i64 value (classes match exactly)" "fn g(): (i64, i64) {\n    var t: (bool, i64) = (true, 2);\n    return t;\n}\nsyscall(60, 0);\n"
refused r14k "tuple 't' used as a value" "R14k: a closure's \`return t;\` of a captured tuple: the value refusal" "include \"lib/alloc.cyr\"\nfn g(): i64 {\n    var t = (1, 2);\n    var c = fncall0(|| { return t; });\n    return c;\n}\nsyscall(60, 0);\n"
refused r14l "cannot return tuple 'u' (i64, i64)$RTD" "R14l: a closure's own tuple local" "include \"lib/alloc.cyr\"\nfn g(): i64 {\n    var c = fncall0(|| { var u = (3, 4); return u; });\n    return c;\n}\nsyscall(60, 0);\n"
refused r14n "tuple field 'p' used as a value" "R14n: \`return h.p;\` (a tuple field)" "struct H { a; p: (i64, i64); }\nfn g(): (i64, i64) {\n    var h: H;\n    return h.p;\n}\nsyscall(60, 0);\n"
refused r14o "cannot return tuple 'G' (i64, i64)$RTD" "R14o: a tuple global from a scalar fn" "var G = (1, 2);\nfn g(): i64 { return G; }\nsyscall(60, g());\n"
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc5"; chmod +x "$T/acc5"
CC_SV=$CC; CC="$T/acc5"
refused r14m "$RT from an \`async fn\` - it returns one value" "R14m: an \`async fn\` declared \`: (i64, i64)\` (its Future carries one i64)" "include \"lib/alloc.cyr\"\nasync fn g(): (i64, i64) {\n${TL5}syscall(60, 0);\n"
refused r14p "$RT from an \`async fn\` - it returns one value" "R14p: an undeclared \`async fn\`" "include \"lib/alloc.cyr\"\nasync fn g() {\n${TL5}syscall(60, 0);\n"
CC=$CC_SV
# R15 — `f().N` on a multi-value call: today's refusal plus how to read the values.
R15="cannot take a field of the result of 'mk': it returns 2 values - bind them first, \`var t: (i64, i64) = mk(..);\`, then read \`t.0\`"
refused r15a "$R15" "R15a: \`return mk(1).0;\`" "${MK}fn f(): i64 { return mk(1).0; }\nsyscall(60, f());\n"
refused r15b "$R15" "R15b: in an operand" "${MK}fn f(): i64 { var x = mk(1).0 + 1; return x; }\nsyscall(60, f());\n"
refused r15c "it returns 2 values - bind them first, \`var t: (i64, f64) = B_mk(..);\`" "R15c: a method's result (its declared values spelled)" "struct B { v; }\nimpl B { fn mk(self, a): (i64, f64) { return (a, 1.5); } }\nfn f(): i64 { var b: B; return b.mk(1).1; }\nsyscall(60, f());\n"
# R16 — a capture refused, mirroring the destructure. Its own texts for a callee class or element that
# disagrees; a one-value callee, a wrapped call, \`f()?\`, \`callptr\` or any other value is no capture at
# all — the tuple's "not a tuple" refusal (R12).
refused r16a "${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16a: an f64 value into an i64 element" "${MK}${MF}${F5}    var t: (i64, i64) = mkf(1);${E5}"
refused r16b "${CAP}mk' into tuple (f64, f64) - it returns 2 values, (i64, i64)" "R16b: an i64 value into an f64 element" "${MK}${F5}    var t: (f64, f64) = mk(1);${E5}"
refused r16c "${CAP}mk' into tuple (bool, i64) - it returns 2 values, (i64, i64)" "R16c: a non-bool value into a bool element" "${MK}${F5}    var t: (bool, i64) = mk(1);${E5}"
refused r16d "${CAP}mk' into tuple (i64, i64, i64) - it returns 2 values, (i64, i64)" "R16d: a declared-arity mismatch (3 from 2)" "${MK}${F5}    var t: (i64, i64, i64) = mk(1);${E5}"
refused r16e "${CAP}mk3' into tuple (i64, i64) - it returns 3 values, (i64, i64, i64)" "R16e: ... (2 from 3)" "fn mk3(a): (i64, i64, i64) { return (a, a, a); }\n${F5}    var t: (i64, i64) = mk3(1);${E5}"
refused r16f "${CAP}mk' into tuple (i64, i64, i64, i64) - a call returns at most 3 values" "R16f: 4 or more elements" "${MK}${F5}    var t: (i64, i64, i64, i64) = mk(1);${E5}"
refused r16g "${CAP}mkp' into tuple (i64, i64) - it returns struct 'P', not a tuple" "R16g: a struct-returning callee" "${P}fn mkp(): P { var p: P; p.a = 1; p.b = 2; return p; }\n${F5}    var t: (i64, i64) = mkp();${E5}"
refused r16h "${CAP}vv' into tuple (i64, i64) - it returns a vector, not a tuple" "R16h: a vector-returning callee" "fn vv(): f64v2 { var v: f64v2; return v; }\n${F5}    var t: (i64, i64) = vv();${E5}"
refused r16i "${CAP}mf2' into tuple (i64, f64) - it is declared \`: f64\`, so every value it returns is an f64" "R16i: a \`: f64\` callee into an i64 element" "fn mf2(a): f64 { ret2(a, a); }\n${F5}    var t: (i64, f64) = mf2(1);${E5}"
refused r16j "${CAP}dm' into tuple (bool, i64) - element 0 is a bool, and the call does not declare that value bool" "R16j: an undeclared callee into a bool element" "fn dm(a, b) { return (a / b, a % b); }\n${F5}    var t: (bool, i64) = dm(1, 2);${E5}"
refused r16k "$I12 't' with a value that is not a tuple" "R16k: a provably one-value callee (the R12 refusal)" "fn one(x) { return x; }\n${F5}    var t: (i64, i64) = one(1);${E5}"
refused r16l "$I12 't' with a value that is not a tuple" "R16l: a wrapped call \`(mk(1))\` (the destructure refuses it too)" "${MK}${F5}    var t: (i64, i64) = (mk(1));${E5}"
refused r16m "$I12 't' with a value that is not a tuple" "R16m: \`f()?\` (one value)" "enum Res: stack { Ok(v); Err(e); }\nfn sok(x) { return Ok(x); }\nfn g(): i64 { var t: (i64, i64) = sok(1)?; return Ok(t.0); }\nsyscall(60, 0);\n"
refused r16n "$I12 't' with a value that is not a tuple" "R16n: a call that is not the whole value" "${MK}${F5}    var t: (i64, i64) = mk(1) + 1;${E5}"
refused r16o "$I12 't' with a value that is not a tuple" "R16o: \`callptr\`" "${MK}${F5}    var p = 0;\n    var t: (i64, i64) = callptr(p, 1);${E5}"
refused r16p "${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16p: \`t = f();\` into an existing tuple" "${MK}${MF}${F5}    var t: (i64, i64);\n    t = mkf(1);${E5}"
refused r16q "$A12 't'" "R16q: \`t = (mk(1));\`, wrapped (R12)" "${MK}${F5}    var t: (i64, i64);\n    t = (mk(1));${E5}"
refused r16r "${CAP}mk' into tuple (i64, f64) - it returns 2 values, (i64, i64)" "R16r: a declaration-zone capture (the replay judges the callee)" "${MK}var G: (i64, f64) = mk(1);\nsyscall(60, 0);\n"
refused r16s "$I12 'G' with a value that is not a tuple" "R16s: a zone capture of a one-value callee (pass 1 registered it inline)" "fn one(x) { return x; }\nvar G: (i64, i64) = one(1);\nsyscall(60, 0);\n"
refused r16t "${CAP}mk' into tuple (i64, i64, i64) - it returns 2 values, (i64, i64)" "R16t: a global capture after the first statement" "${MK}syscall(1, 1, \"\", 0);\nvar G: (i64, i64, i64) = mk(1);\nsyscall(60, 0);\n"
refused r16u "$A12 'G'" "R16u: \`G = mk(2) + 1;\` at top level (R12)" "${MK}var G: (i64, i64) = mk(1);\nG = mk(2) + 1;\nsyscall(60, 0);\n"
refused r16v "${CAP}mk' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16v: a method's declared values" "struct B { v; }\nimpl B { fn mk(self, a): (i64, f64) { return (a, 1.5); } }\n${F5}    var b: B;\n    var t: (i64, i64) = b.mk(1);${E5}"
refused r16w "${CAP}mk' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16w: a classic-for step \`t = mk(i)\`" "${MF}fn mk(a): (i64, f64) { return (a, 0.5); }\n${F5}    var t: (i64, i64);\n    for (var i = 0; i < 2; t = mk(i)) { i = i + 1; }${E5}"
# R17 — a multi-value call stored into a tuple FIELD: bind it first (the argument form is T3's R17a-h).
R17F="is not stored into a tuple field - bind it first: \`var t: (i64, i64) = "
TH5='struct H { a; p: (i64, i64); }\n'
refused r17i "a multi-value call 'mk' $R17F" "R17i: \`h.p = mk(3);\`" "${TH5}${MK}${F5}    var h: H;\n    h.p = mk(3);${E5}"
refused r17j "a multi-value call 'B_mk' $R17F" "R17j: a method" "${TH5}struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a); } }\n${F5}    var h: H;\n    var b: B;\n    h.p = b.mk(3);${E5}"
refused r17k "a multi-value call 'mk' $R17F" "R17k: a global's field, at top level" "${TH5}${MK}var GH = H { 1, 2, 3 };\nGH.p = mk(3);\nsyscall(60, 0);\n"
refused r17l "a multi-value call 'mk' $R17F" "R17l: a classic-for step's field" "${TH5}${MK}${F5}    var h: H;\n    for (var i = 0; i < 2; h.p = mk(i)) { i = i + 1; }${E5}"
# R18 — `a, b = f();` re-assigns plain variables: every other target refused by name (each was "expected '='").
NP="a multi-value assignment \`a, b = f();\` re-assigns plain variables"
TGT=" from a multi-value call - its targets are i64, f64 or bool variables"
refused r18a "$NP - a field is not one" "R18a: a field first target \`h.x, b = ..\`" "struct H1 { x; }\n${MK}${F5V}    var h: H1;\n    h.x, b = mk(1);${E5}"
refused r18b "$NP - an element is not one" "R18b: a subscript first target" "${MK}${F5V}    var arr: i64[2];\n    arr[0], b = mk(1);${E5}"
refused r18c "$NP - \`*p\` is not one" "R18c: a deref first target" "${MK}${F5V}    var p = &a;\n    *p, b = mk(1);${E5}"
refused r18d "$NP - a field is not one" "R18d: a tuple element first target \`t.0, b = ..\`" "${MK}${F5V}    var t = (1, 2);\n    t.0, b = mk(1);${E5}"
refused r18e "$NP - a field is not one" "R18e: a later field target" "${MK}${F5V}    var h = (1, 2);\n    a, h.0 = mk(1);${E5}"
refused r18f "$NP - an element is not one" "R18f: a later subscript target" "${MK}${F5V}    var arr: i64[2];\n    a, arr[1] = mk(1);${E5}"
refused r18g "$NP - \`*p\` is not one" "R18g: a later deref target" "${MK}${F5V}    var p = &a;\n    a, *p = mk(1);${E5}"
refused r18h "$NP - its form is \`=\`, not a compound \`OP=\`" "R18h: \`a, b += f();\`" "${MK}${F5V}    a, b += mk(1);${E5}"
refused r18i "a multi-value assignment re-assigns 2 or 3 variables - a call returns at most 3 values" "R18i: 4 targets" "${MK}${F5V}    var c = 0;\n    var d = 0;\n    a, b, c, d = mk(1);${E5}"
refused r18j "a multi-value assignment re-assigns each variable once - this one is named twice" "R18j: a duplicate target" "${MK}${F5V}    a, a = mk(1);${E5}"
refused r18k "cannot assign to const 'C'" "R18k: a const target" "${MK}const C = 1;\n${F5V}    a, C = mk(1);${E5}"
refused r18l "cannot assign to enum constant 'EA'" "R18l: an enum constant target" "${MK}enum E { EA, EB }\n${F5V}    EA, b = mk(1);${E5}"
refused r18m "cannot re-assign struct 'p'$TGT" "R18m: a struct target" "${P}${MK}${F5V}    var p: P;\n    p, b = mk(1);${E5}"
refused r18n "cannot re-assign tuple 't' from a multi-value call - capture the call into it whole: \`t = f();\`" "R18n: a tuple target" "${MK}${F5V}    var t = (1, 2);\n    t, b = mk(1);${E5}"
refused r18o "cannot re-assign vector 'v'$TGT" "R18o: a vector target" "${MK}${F5V}    var v: f64v2;\n    v, b = mk(1);${E5}"
refused r18p "cannot re-assign array 'arr'$TGT" "R18p: an array target" "${MK}${F5V}    var arr: i64[2];\n    arr, b = mk(1);${E5}"
refused r18q "cannot re-assign u128 'u'$TGT" "R18q: a u128 target" "${MK}${F5V}    var u: u128 = 0;\n    u, b = mk(1);${E5}"
refused r18r "cannot re-assign slice 's'$TGT" "R18r: a slice target" "${MK}${F5V}    var s: [u8] = 0;\n    s, b = mk(1);${E5}"
refused r18s "cannot re-assign f32 'x'$TGT" "R18s: an f32 target" "${MK}${F5V}    var x: f32 = 0.0;\n    x, b = mk(1);${E5}"
refused r18t "cannot assign a value that is not a bool to bool 'k' - the call does not declare that value bool" "R18t: a bool target from a declared i64 value" "${MK}${F5V}    var k: bool = false;\n    k, b = mk(1);${E5}"
refused r18u "cannot assign a value that is not a bool to bool 'k' - the call does not declare that value bool" "R18u: a bool target from an undeclared callee" "fn dm(a, b) { return (a / b, a % b); }\n${F5V}    var k: bool = false;\n    k, b = dm(1, 2);${E5}"
refused r18v "undefined variable 'zz'" "R18v: an undefined target (as \`x = ..\` reports it)" "${MK}${F5V}    zz, b = mk(1);${E5}"
refused r18w "undefined variable 'a'" "R18w: a closure's captured target (as \`x = ..\` inside a closure)" "include \"lib/alloc.cyr\"\n${MK}${F5V}    var c = fncall0(|| { var z = 0; a, z = mk(1); return z; });${E5}"
refused r18x "cannot re-assign tuple 'GV' from a multi-value call" "R18x: a global tuple target" "${MK}var GV = (1, 2);\n${F5V}    GV, b = mk(1);${E5}"
# R19 — a right-hand side that is not one whole call: the destructure's own texts.
R19="multi-value destructure needs a call on the right-hand side"
refused r19a "$R19" "R19a: \`a, b = 5;\`" "${MK}${F5V}    a, b = 5;${E5}"
refused r19b "$R19" "R19b: \`a, b = (b, a);\` (a literal is no call)" "${MK}${F5V}    a, b = (b, a);${E5}"
refused r19c "$R19" "R19c: \`a, b = t;\`" "${MK}${F5V}    var t = (1, 2);\n    a, b = t;${E5}"
refused r19d "$R19" "R19d: a wrapped call" "${MK}${F5V}    a, b = (mk(1));${E5}"
refused r19e "$R19" "R19e: a call that is not the whole value" "${MK}${F5V}    a, b = mk(1) + 1;${E5}"
refused r19f "multi-value destructure binds 2 names, but 'one' returns 1 value" "R19f: a provably one-value callee" "fn one(x) { return x; }\n${F5V}    a, b = one(1);${E5}"
refused r19g "multi-value destructure count does not match the fn's declared return arity" "R19g: a declared-arity mismatch" "fn mk3(a): (i64, i64, i64) { return (a, a, a); }\n${F5V}    a, b = mk3(1);${E5}"
refused r19h "$R19" "R19h: a classic-for step whose value is not a call" "${MK}${F5V}    for (var i = 0; i < 2; a, b = i) { i = i + 1; }${E5}"
# R20 — unchanged: `(a, b) = f();` and `var (q, r) = f();` keep their errors.
refused r20a "unexpected '('" "R20a: \`(a, b) = f();\` (unchanged)" "${MK}${F5V}    (a, b) = mk(1);${E5}"
refused r20b "expected identifier, got '('" "R20b: \`var (q, r) = f();\` (unchanged)" "${MK}fn f(): i64 {\n    var (q, r) = mk(1);\n    return 0;\n}\nsyscall(60, f());\n"
# AS2 — a capture and a multi-value assignment in a SUSPENDING `async fn`, across awaits: the block's span
# recorded before the call, every value pushed before any store, the stores addressed (the coroutine's heap
# frame, whose slots ascend, holds the block whole).
CC_SV=$CC; CC="$T/acc5"
exits as2 0 "AS2: \`var t: (i64, i64, i64) = m3(..);\`, \`t = m3(..);\` and \`a, q = m2(a);\` across awaits" 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nstruct P2 { x; y; }\nfn nopark(): i64 { return 0; }\nfn m3(x, y, z): (i64, i64, i64) { return (x, y, z); }\nfn m2(x): (i64, i64) { return (x, 1); }\nasync fn steps(C): i64 {\n    var a = 3;\n    var t: (i64, i64, i64) = m3(5, 6, 7);\n    var p = P2 { 1, 2 };\n    var b = 4;\n    var s1 = await nopark();\n    t = m3(t.2, t.0, b);\n    var q = 0;\n    var s2 = await nopark();\n    a, q = m2(a);\n    return t.0 * 1000 + t.1 * 100 + t.2 * 10 + a + p.y * 10000 + q * 100000;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(0);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    if (r3 != 127543) { syscall(60, 1); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# ── X: --syntax-only (cyrius lint's pre-pass) ──────────────────────────────────────────────────────
# A fn with a tuple parameter, its call, and calls to a sibling file's fns (unknown here) with a tuple
# argument and a sibling's call as a tuple argument: nothing tuple-related is reported.
printf 'fn take(t: (i64, i64), k): i64 { return t.0 * 10 + t.1 + k; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n    return take(t, 3) + sib_take(t, 4) + take(sib_mk(), 5);\n}\nsyscall(60, f());\n' > "$T/x03.cyr"
"$CC" --syntax-only < "$T/x03.cyr" > /dev/null 2> "$T/x03.err" || true
if grep -q "tuple\|^error:<source>" "$T/x03.err"; then bad "X3: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x03.err")"
else ok "X3: --syntax-only: a tuple parameter, a sibling's fn given a tuple, a sibling's call as a tuple argument — silent"; fi
# X4: literals — declared, assigned, stored into a field, passed to a local tuple parameter and to a sibling
# file's fn (unknown here: its literal is skipped quietly, no false accusation).
printf 'struct H { a; p: (i64, i64); }\nfn take(t: (i64, i64), k): i64 { return t.0 + k; }\nfn f(): i64 {\n    var t = (1, 2);\n    var u: (i64, f64) = (3, 0.5);\n    t = (t.1, t.0);\n    var h: H;\n    h.p = ((4, 5));\n    return take((6, 7), 1) + sib_take((8, 9), 2) + u.0 + h.p.1;\n}\nsyscall(60, f());\n' > "$T/x04.cyr"
"$CC" --syntax-only < "$T/x04.cyr" > /dev/null 2> "$T/x04.err" || true
if grep -q "tuple\|^error:<source>" "$T/x04.err"; then bad "X4: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x04.err")"
else ok "X4: --syntax-only: literals declared, assigned, stored, passed (a sibling's fn too) — silent"; fi
# X5 (T5): a sibling file's globals as `a, b = f()` targets (their stores dropped), a sibling's callee
# captured (into a bool element too: an unknown callee is not judged here), `t = f()`, a for step, and
# `return t;` — nothing reported.
printf 'fn f(): i64 {\n    var b = 0;\n    sib_a, b = sib_mk();\n    var t: (i64, i64) = sib_mk2(1);\n    t = sib_mk2(2);\n    var k: (bool, i64) = sib_mk3();\n    b, sib_c, sib_d = sib_mk3();\n    for (var i = 0; i < 2; b, sib_a = sib_mk()) { i = i + 1; }\n    return t.0;\n}\nfn g(): (i64, i64) { var t = (1, 2); return t; }\nsyscall(60, f());\n' > "$T/x05.cyr"
"$CC" --syntax-only < "$T/x05.cyr" > /dev/null 2> "$T/x05.err" || true
if grep -q "tuple\|^error:<source>" "$T/x05.err"; then bad "X5: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x05.err")"
else ok "X5: --syntax-only: sibling targets and callees in captures and multi-value assignments, \`return t;\` — silent"; fi

# ── A: tests/tcyr/crossos/tuple_values.tcyr on every pipeline and target ───────────────────────────
TV="$ROOT/tests/tcyr/crossos/tuple_values.tcyr"
want=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TV")
[ "$want" -ge 168 ] || bad "A0: only $want assertions derived from $TV (floor 168)"
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
echo "PASS: tuple_checked — tuples: the lexer (L); the type in a var, a struct field and a parameter, \`t.N\`, copies (S, P); the literal in its five positions, wrapped, in both zones and a kernel build (C, S1, S4, K1, PW, AS); every open shape refused by name (R1-R13, R17, R21); the bridge — captures, \`return t;\`, \`a, b = f();\` — and its refusals (R14-R20, AS2); --syntax-only silent (X); tuple_values.tcyr on x86 / IR / DCE / aarch64 / cx / PE (A)"
