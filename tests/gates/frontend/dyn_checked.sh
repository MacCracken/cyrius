#!/bin/sh
# tests/gates/frontend/dyn_checked.sh — 6.7.8 (the checked `dyn` lane, bite D4: the keyword and the type)
#
# CHECKED `dyn`. The user's decisions (2026-10-07): `o: dyn Show` is an ordinary 16-byte struct of two
# words {data, vtable} — ADR-002's one-word model holds; the compiler builds and verifies the vtable from
# `impl Show for T`; `o.show()` is an indirect call visible in the declared type; static dispatch stays
# the default. D4 lands the word and the type: `dyn` is reserved (token 173); `dyn X` is folded into ONE
# identifier token named `dyn X` before any prepass records a token index (`_dyn_fold`), registered as a
# struct of two 8-byte words (" data", " vtable" — no field access reaches them) before any user struct
# (`_dyn_prepass`), so every struct position takes it unchanged; every position the decisions leave open
# is refused by name, once per token. Forming a dyn (D5) and calling through one (D6) are later bites:
# here a dyn value comes from a record's dyn field (heap memory, `get`), the way a program would keep one.
#
#   K   the reserved word: `var dyn`, `fn dyn`, a field `dyn`, a method `dyn` — "got reserved keyword 'dyn'"
#   TY  each position compiles (and runs, the two words intact): TY1 a local copy, TY2 a global after the
#       first statement (its annotation resolves — the value is the backstop's), TY3 a parameter, TY4 a
#       return threaded through three fns declared below the caller (the rough pair scan, H3), TY5 a
#       struct field, TY6 a trait member's signature
#   S   S2 `struct H { a; o: dyn Show; b; }` is 32 bytes, `b` intact; S3 a forward call to a fn declared
#       below taking `(o: dyn Show, k)` (pass 1's parameter scan, H4); S5 `#derive` refuses a dyn field
#   T   the type positions the decisions leave open: T1 `dyn X` where X is no trait; T2 `dyn A + B` (one
#       report, the parse in sync); T3 `dyn` with no trait name in a type position; T4 a type argument
#       (`Vec<dyn S>`, `Box<dyn S>`, `f<dyn S>(..)`, `Pr<i64, dyn S>`); T5 a pointer (`*dyn S`, `**`,
#       `*fn(dyn S)`); T6 an array / slice / tuple / multi-value element; T7 `dyn S<..>`; T8 `sizeof`;
#       T9 `impl .. for dyn S` / `impl dyn S`; T10 any other position (an expression, a name); T11 in a
#       generic (signature or body), `async`, `const` or `#naked` fn; T12 a dyn field in a generic struct,
#       in a union, or a union holding a struct that holds one; T13 a `const` (its own refusal)
#   U   uninitialised: U1 `var o: dyn S;` in a fn; U2 `var h: H;` where H holds a dyn (directly, through a
#       nested struct, through a generic instance), and `var hs: H[N]` — struct locals are not zeroed
#   V   opacity (decision 7): V1 a dyn name as a value; V2 `&o`; V3 a whole dyn field as a value; V4 a
#       dyn-returning call as a value (not a destination's whole expression; an un-annotated `var x =
#       (mk());`); V5 `o.data` / `o.vtable` / `o.0` / `o.m` (FINDFIELD's own words); V6 a multi-value
#       destructure; V7 `return (a, b)` / `ret2` in a fn returning a dyn; V8 a struct literal writing a
#       dyn field's words; the backstops (`var o: dyn S = 5;`, `o = 5;`, `h.o = 5;`)
#   P   every destination of a dyn call result takes it whole — a var (annotated, inferred), an
#       assignment, a field store, an argument, a struct-literal element, a `return` (tail, wrapped,
#       non-tail in a `defer` fn) — bare and wrapped in parentheses; a method result too; the values
#       checked word by word (the over-refusal mutation M-T10 turns these RED)
#   H28 the fold across a newline and a comment; the caret of a diagnostic sits on `dyn`
#   X   `--syntax-only` (cyrius lint's pre-pass) reports no dyn refusal (they resolve types), and still
#       reports the reserved word
#   TT  the tools: `[embed]`'s reserved list holds `dyn` (embed_manifest_refusals.sh derives and checks
#       it); cyrius-lsp colours `dyn` a keyword (and `dynamo` not); the VS Code grammar lists it
#   A   the P program on x86 (default, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine,
#       a private prefix). A leg whose tool is missing is a SKIP that names it (exit 77).
#
# MUTATION LEDGER (2026-10-10, bite D4; each a one-edit scratch COPY of src/, its compiler rebuilt from
# the mutated src, then this gate run with CYCC= the mutant; each measured RED, the real tree 115/115; the
# base compiler (the lane's HEAD before D4) is RED on 107 of them):
#   M-T1  the fold disabled (`_dyn_fold` returns at once)          -> 100 rows (every TY / S / T / U / V / P
#         row, H28a / H28b, X1, the A legs: `dyn Show` is two tokens)
#   M-T2  the fold placed AFTER `_tr_prepass`                       -> TY6 (the trait / impl records keep
#         pre-compaction token indices: an impl after a dyn-typed trait member is read one token off)
#   M-T3  no position rule (`_dyn_pos` accepts any predecessor)     -> T4a-e, T5a-c, T6b-e, T8a-b, T9a-b, T10a-d
#   M-T4  no `+ B` drop in the fold                                 -> T2 (a parse cascade)
#   M-T5  the prev-`<` arm gone                                     -> T4a, T4b, T4c, T4e (T4d is the `,` arm)
#   M-T6  `_dyn_rchk` gone from `_tup_rchk`                          -> V1a-l, V2a-b, V4a-g (BUILT)
#   M-T7  `PP_DDYN` gone                                            -> S5 (BUILT, every field after `o` lost)
#   M-T8  `_embed_reserved_list` without ` dyn` (cbt/manifest.cyr)   -> toolchain/embed_manifest_refusals.sh
#         axis 5 ("reserved names cbt accepts: dyn") and TT1
#   M-T9  `_tup_var` without `_dyn_var` (U1 / U2)                   -> U1, U2a, U2b, U2d (BUILT)
#   M-T10 V4's destination exemption gone (every dyn result refused) -> TY6, P1-P21, A x86 IR3 / DCE / aarch64 /
#         cx / PE (the over-refusal is caught)
#   M-T11 no `_dyn_ret_arm` (`return pass(o);` in a dyn fn unarmed)  -> P1-P21 and the A legs
#   M-T12 a bare `dyn` reported but not turned into an identifier  -> T3c (a second error: the return type's
#         ERR_EXPECT names the reserved word)
#   M-T13 a dyn type in a value position not turned into `0`         -> T10a (a second "undefined variable")
#   M-T14 `_dyn_held` not recursive (a direct dyn field only)       -> U2b, U2d (BUILT)
#   M-T15 V3 (`_tup_fld_rchk`'s dyn arm) gone                        -> V3a-c (BUILT)
#   M-T16 V8 (`_spi_nested`'s dyn refusal) gone                      -> V8 (BUILT: the dyn's words from 2, 3)
#   M-T17 the async by-value struct-parameter refusal not skipping a dyn -> T11c (a second error, advising
#         `o: *dyn Show`, which is refused)
#   M-T18 the union arm of `_dyn_field_chk` gone                     -> T12b, T12c (BUILT)
#   M-T19 the destination exemption reaching through `(` (`_sc_want` before the call) -> V4d (BUILT: an
#         un-annotated `var x = (pass(o));` kept the dyn's DATA word as an i64)
#   M-T20 no enclosing-fn check (T11)                                -> T11a-f
#   M-T21 no trait-name check (T1)                                   -> T1a-c, H28b
#   M-T22 the `+ B` drop not reported                                -> T2 (BUILT)
#   M-T23 V6 (`_dt_arity_check`'s dyn arm) gone                      -> V6a (BUILT)
#   M-T24 V7 (`_mret_land`'s dyn arm) gone                           -> V7a, V7b (BUILT)
#   M-T25 the backstop's whole-call skip gone                        -> TY2b (a second error)
#   M-T26 the backstop's dyn arm gone (`_tup_ptr_refuse`)            -> TY2, V9a (BUILT)
#   M-T27 a bare `dyn` not recorded by the fold (T3)                 -> T3a-f (BUILT, or another error)
#   M-T28 the async struct-RETURN refusal not skipping a dyn          -> T11d
#   M-T29 the generic-struct arm of `_dyn_field_chk` gone             -> T12a (BUILT)
#   M-T30 `_arr_ebytes` without `_dyn_uninit`                         -> U2c (BUILT)
#   M-T31 / M-T32 the assignment / field-store backstops' dyn arms gone -> V9b / V9c
#   M-T33 the type-argument refusal not skipping the bare `dyn`        -> T3f (a second error)
#   MTT2 / MTT3 the VS Code grammar / the LSP's len-3 arm without `dyn` -> TT2 / TT3
# Defensive, no killing row (named): `_op_fn_peek`'s dyn arm ("dyn Show has no operators") — every dyn
# operand is refused at its factor first (V1 / V3 / V4 clear the stamp, V4 the `_lsc` record), so no
# operator dispatch is reached with a dyn type today; the arm keeps a future path from dispatching
# `dyn Show_add`. (M-T34, the arm removed, leaves every row green.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: dyn_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: dyn_checked: mktemp -d failed"; exit 1; }
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
# A trait, a record holding a dyn, and the helpers every P / TY row uses: `get(mkw(d, v))` reads a dyn
# whose words are (d, v) out of a heap record (D4 forms none); `dw(o)` reads the two words back through
# a wrapper struct (`load64(&w)`: data, `+ 8`: vtable) as d * 10 + v.
SH='trait Show { fn show(self): i64; }\nstruct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a; } }\n'
HP='include "lib/alloc.cyr"\ntrait Show { fn show(self): i64; }\nstruct W { o: dyn Show; }\nstruct H { a; o: dyn Show; b; }\nfn mkw(d, v): i64 { var m = alloc(16); store64(m, d); store64(m + 8, v); return m; }\nfn get(w: *W): dyn Show { var o: dyn Show = w.o; return o; }\nfn pass(o: dyn Show): dyn Show { return o; }\nfn dw(o: dyn Show): i64 { var w: W = W { o }; return load64(&w) * 10 + load64(&w + 8); }\nfn g(x): i64 { return x; }\n'
FO='fn f(o: dyn Show): i64 { '
FE=' }\nsyscall(60, 0);\n'
FM='fn main(): i64 {\n    alloc_init();\n    var o: dyn Show = get(mkw(4, 9));\n'
ME='}\nsyscall(60, main());\n'
RV='used as a value - call one of its methods, or copy it whole into a dyn'

# ── K: the reserved word ───────────────────────────────────────────────────────────────────────────
KW="got reserved keyword 'dyn'"
refused k01 "$KW" "K1: \`var dyn = 5;\`" 'fn f(): i64 { var dyn = 5; return 0; }\nsyscall(60, f());\n'
refused k02 "$KW" "K2: \`fn dyn()\`" 'fn dyn(): i64 { return 1; }\nsyscall(60, 0);\n'
refused k03 "$KW" "K3: a field \`dyn\`" 'struct Q { a; dyn; }\nsyscall(60, 0);\n'
refused k04 "$KW" "K4: a method \`p.dyn()\`" "${SH}fn f(p: P): i64 { return p.dyn(); }\nsyscall(60, 0);\n"

# ── TY: each position compiles, its two words intact ───────────────────────────────────────────────
exits ty1 49 "TY1: a local, copied (\`var o2: dyn Show = o;\`)" "${HP}${FM}    var o2: dyn Show = o;\n    var o3: dyn Show = o2;\n    return dw(o3);\n${ME}"
refused ty2 "cannot initialize dyn Show 'G' with a value that is not a dyn" "TY2: a global after the first statement (the annotation resolves to the dyn; D4 forms no value)" "${SH}syscall(1, 1, \"\", 0);\nvar G: dyn Show = 5;\nsyscall(60, 0);\n"
refused ty2b "'mkd' returns a struct by value, and a struct result needs storage in a fn's frame" "TY2b: \`var G: dyn Show = mkd();\` at top level: the call refuses itself, once (not also \"not a dyn\")" "${HP}fn mkd(): dyn Show { return get(mkw(4, 9)); }\nsyscall(1, 1, \"\", 0);\nvar G: dyn Show = mkd();\nsyscall(60, 0);\n"
exits ty3 49 "TY3: a parameter (\`fn dw(o: dyn Show)\`)" "${HP}${FM}    return dw(o);\n${ME}"
exits ty4 49 "TY4: a return threaded through three fns declared below the caller (the rough pair scan)" "${HP}${FM}    var r: dyn Show = a1(o);\n    return dw(r);\n}\nfn a1(o: dyn Show): dyn Show { var x: dyn Show = a2(o); return x; }\nfn a2(o: dyn Show): dyn Show { var y: dyn Show = a3(o); return y; }\nfn a3(o: dyn Show): dyn Show { var z: dyn Show = o; return z; }\nsyscall(60, main());\n"
exits ty5 170 "TY5: a struct field — the literal \`H { 1, o, 7 }\`, a store \`h.o = o2;\`, a read \`dw(h.o)\`" "${HP}${FM}    var h: H = H { 1, o, 7 };\n    var o2: dyn Show = get(mkw(5, 6));\n    h.o = o2;\n    return h.a * 100 + h.b * 10 + dw(h.o) - 56;\n${ME}"
exits ty6 49 "TY6: a trait member's signature (\`fn mix(self, o: dyn Show, k): dyn Show;\`), its impl called" "${HP}trait Mix { fn mix(self, o: dyn Show, k): dyn Show; }\nstruct P { a; b; }\nimpl Mix for P { fn mix(self, o: dyn Show, k): dyn Show { var r: dyn Show = o; return r; } }\n${FM}    var p = P { 1, 2 };\n    var r: dyn Show = p.mix(o, 3);\n    return dw(r);\n${ME}"

# ── S: shapes ──────────────────────────────────────────────────────────────────────────────────────
exits s02 32 "S2: \`struct H { a; o: dyn Show; b; }\` is 32 bytes, \`a\` / \`b\` intact around the 16-byte dyn" "${HP}${FM}    var h: H = H { 3, o, 7 };\n    if (h.a * 10 + h.b != 37) { return 1; }\n    if (dw(h.o) != 49) { return 2; }\n    return sizeof(H);\n${ME}"
exits s03 149 "S3: a forward call to \`fn later(o: dyn Show, k)\` declared below (pass 1 scans the dyn parameter)" "${HP}${FM}    return later(o, 100);\n}\nfn later(o: dyn Show, k): i64 { return dw(o) + k; }\nsyscall(60, main());\n"
refused s05 "#derive reads named field types; 'o' is a dyn (in the declaration of D)" "S5: \`#derive\` on a struct with a dyn field (the walk read \`dyn\` as the type and \`Show\` as a field)" "${SH}#derive(accessors)\nstruct D { a; o: dyn Show; b; }\nsyscall(60, 0);\n"

# ── T: type positions left open ────────────────────────────────────────────────────────────────────
refused t01a "'Nope' is not a trait - \`dyn\` takes a declared trait's name" "T1a: \`dyn Nope\`" "${SH}fn f(o: dyn Nope): i64 { return 0; }\nsyscall(60, 0);\n"
refused t01b "'P' is not a trait" "T1b: \`dyn P\`, a struct" "${SH}fn f(o: dyn P): i64 { return 0; }\nsyscall(60, 0);\n"
refused t01c "'T' is not a trait" "T1c: \`dyn T\`, a type parameter's name" "${SH}fn f(o: dyn T): i64 { return 0; }\nsyscall(60, 0);\n"
refused t02 "\`dyn A + B\` is refused - a dyn holds one vtable, of one trait" "T2: \`dyn Show + Eq\` (one report, the parse in sync)" "${SH}trait Eq { fn eq(self): i64; }\nfn f(o: dyn Show + Eq, k): i64 { return k; }\nsyscall(60, 0);\n"
T3M="\`dyn\` takes a trait's name - \`dyn Show\` for \`trait Show\`"
refused t03a "$T3M" "T3a: \`o: dyn)\` (the parameter type arm took any one token)" "${SH}fn f(o: dyn): i64 { return 0; }\nsyscall(60, 0);\n"
refused t03b "$T3M" "T3b: \`var o: dyn = 5;\`" "${SH}fn f(): i64 { var o: dyn = 5; return 0; }\nsyscall(60, 0);\n"
refused t03c "$T3M" "T3c: \`var o: dyn;\` and a return \`: dyn\`" "${SH}fn f(): dyn { return 0; }\nsyscall(60, 0);\n"
refused t03d "$T3M" "T3d: \`Vec<dyn>\` (it compiled)" "${SH}include \"lib/vec.cyr\"\nfn f(v: Vec<dyn>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t03e "$T3M" "T3e: \`*dyn\` (it compiled)" "${SH}fn f(v: *dyn): i64 { return 0; }\nsyscall(60, 0);\n"
refused t03f "$T3M" "T3f: \`Pr<i64, dyn>\`" "${SH}struct Pr<A, B> { a: A; b: B; }\nfn f(): i64 { var b: Pr<i64, dyn>; return 0; }\nsyscall(60, 0);\n"
T4M="dyn Show cannot be a type argument - a collection holds pointers to records that hold a dyn"
refused t04a "$T4M" "T4a: \`Vec<dyn Show>\`" "${SH}include \"lib/vec.cyr\"\nfn f(v: Vec<dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t04b "$T4M" "T4b: \`Box<dyn Show>\`" "${SH}struct Box<T> { v: T; }\nfn f(b: Box<dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t04c "$T4M" "T4c: \`g<dyn Show>(o)\`" "${SH}fn g<T>(x: T): i64 { return 0; }\nfn f(o: dyn Show): i64 { return g<dyn Show>(o); }\nsyscall(60, 0);\n"
refused t04d "$T4M" "T4d: \`Pr<i64, dyn Show>\` (the second argument)" "${SH}struct Pr<A, B> { a: A; b: B; }\nfn f(b: Pr<i64, dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t04e "$T4M" "T4e: \`Box<Box<dyn Show>>\` (nested, \`>>\`)" "${SH}struct Box<T> { v: T; }\nfn f(b: Box<Box<dyn Show>>): i64 { return 0; }\nsyscall(60, 0);\n"
T5M="a pointer to dyn Show is refused"
refused t05a "$T5M" "T5a: \`*dyn Show\`" "${SH}fn f(o: *dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t05b "$T5M" "T5b: \`**dyn Show\`" "${SH}fn f(): i64 { var p: **dyn Show = 0; return 0; }\nsyscall(60, 0);\n"
refused t05c "dyn Show cannot be a \`*fn(..)\` parameter" "T5c: \`*fn(dyn Show): i64\` (a trait member's parameter)" "${SH}trait Cb { fn on(self, cb: *fn(dyn Show): i64): i64; }\nsyscall(60, 0);\n"
refused t06a "dyn Show cannot be an array element" "T6a: \`dyn Show[4]\`" "${SH}fn f(): i64 { var a: dyn Show[4]; return 0; }\nsyscall(60, 0);\n"
refused t06b "dyn Show cannot be a slice element" "T6b: \`[dyn Show]\`" "${SH}fn f(): i64 { var a: [dyn Show] = 0; return 0; }\nsyscall(60, 0);\n"
refused t06c "dyn Show cannot be a slice element" "T6c: \`slice<dyn Show>\`" "${SH}fn f(): i64 { var a: slice<dyn Show> = 0; return 0; }\nsyscall(60, 0);\n"
refused t06d "dyn Show cannot be a tuple or multi-value element" "T6d: \`(dyn Show, i64)\`" "${SH}fn f(): i64 { var t: (dyn Show, i64); return 0; }\nsyscall(60, 0);\n"
refused t06e "dyn Show cannot be a tuple or multi-value element" "T6e: a multi-value return \`: (i64, dyn Show)\`" "${SH}fn f(): (i64, dyn Show) { return (1, 2); }\nsyscall(60, 0);\n"
refused t07 "dyn Show takes no type arguments - a trait has none" "T7: \`dyn Show<i64>\`" "${SH}fn f(o: dyn Show<i64>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t08a "sizeof(dyn Show) is refused" "T8a: \`sizeof(dyn Show)\`" "${SH}fn f(): i64 { return sizeof(dyn Show); }\nsyscall(60, f());\n"
refused t08b "sizeof(dyn Show) is refused" "T8b: \`#assert sizeof(dyn Show) == 16\`" "${SH}#assert sizeof(dyn Show) == 16, \"x\"\nsyscall(60, 0);\n"
T9M="\`impl\` takes a type that is not a dyn"
refused t09a "$T9M" "T9a: \`impl Show for dyn Show\`" "${SH}impl Show for dyn Show { fn show(self): i64 { return 1; } }\nsyscall(60, 0);\n"
refused t09b "$T9M" "T9b: \`impl dyn Show\`" "${SH}impl dyn Show { fn show2(self): i64 { return 1; } }\nsyscall(60, 0);\n"
T10M="dyn Show is a type - write it after a \`:\` (\`o: dyn Show\`)"
refused t10a "$T10M" "T10a: an expression \`var x = dyn Show;\`" "${SH}fn f(): i64 { var x = dyn Show; return 0; }\nsyscall(60, 0);\n"
refused t10b "$T10M" "T10b: a name \`struct dyn Show\`" "${SH}struct dyn Show { a; }\nsyscall(60, 0);\n"
refused t10c "$T10M" "T10c: a parameter with no name \`fn f(dyn Show)\`" "${SH}fn f(dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t10d "$T10M" "T10d: \`var dyn Show = 1;\`" "${SH}fn f(): i64 { var dyn Show = 1; return 0; }\nsyscall(60, 0);\n"
refused t11a "a dyn type in a generic fn is refused" "T11a: a generic fn's signature" "${SH}fn g<T>(x: T, o: dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t11b "a dyn type in a generic fn is refused" "T11b: a generic fn's body" "${SH}fn h<T>(x: T, k): i64 {\n    if (k > 0) { var o: dyn Show; }\n    return 0;\n}\nsyscall(60, 0);\n"
printf '%b' "include \"lib/alloc.cyr\"\n${SH}async fn g(o: dyn Show, k): i64 { return k; }\nsyscall(60, 0);\n" > "$T/t11c.cyr"
rc=0; CYRIUS_ASYNC=1 timeout 60 "$CC" < "$T/t11c.cyr" > "$T/t11c.bin" 2> "$T/t11c.err" || rc=$?
if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$T/t11c.err")" -eq 1 ] && grep -qF "a dyn type in an \`async fn\` is refused" "$T/t11c.err"; then ok "T11c: an \`async fn\`'s dyn parameter (CYRIUS_ASYNC=1): refused once (not also as a by-value struct parameter)"
else bad "T11c: rc $rc: $(grep '^error' "$T/t11c.err" | head -2 | tr '\n' '|')"; fi
printf '%b' "include \"lib/alloc.cyr\"\n${SH}async fn g(k): dyn Show { return k; }\nsyscall(60, 0);\n" > "$T/t11d.cyr"
rc=0; CYRIUS_ASYNC=1 timeout 60 "$CC" < "$T/t11d.cyr" > "$T/t11d.bin" 2> "$T/t11d.err" || rc=$?
if [ "$rc" -ne 0 ] && grep -qF "a dyn type in an \`async fn\` is refused" "$T/t11d.err" && ! grep -qF 'a Future carries one i64' "$T/t11d.err"; then ok "T11d: an \`async fn\` returning a dyn: refused at its type (not also as a struct returned by value)"
else bad "T11d: rc $rc: $(grep '^error' "$T/t11d.err" | head -2 | tr '\n' '|')"; fi
refused t11e "a dyn type in a \`const fn\` is refused" "T11e: a \`const fn\`" "${SH}const fn g(o: dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t11f "a dyn type in a \`#naked\` fn is refused" "T11f: a \`#naked\` fn" "${SH}#naked\nfn g(o: dyn Show) { asm { 0xC3; } }\nsyscall(60, 0);\n"
exits t11g 0 "T11g: a fn below a bodyless generic trait member is not \`inside\` it" "${SH}trait Pk { fn pick<U>(self, u: U): i64; }\nstruct Hd { o: dyn Show; }\nsyscall(60, sizeof(Hd) - 16);\n"
refused t12a "a dyn field in a generic struct is refused" "T12a: a dyn field in a generic struct" "${SH}struct B<T> { v: T; o: dyn Show; }\nsyscall(60, 0);\n"
refused t12b "a union cannot hold a dyn" "T12b: a union member" "${SH}union U { o: dyn Show; x: i64; }\nsyscall(60, 0);\n"
refused t12c "a union cannot hold a dyn" "T12c: a union member holding a struct that holds one" "${SH}struct Hd { a; o: dyn Show; }\nunion U { h: Hd; x: i64; }\nsyscall(60, 0);\n"
refused t13 "a const takes no type annotation" "T13: \`const C: dyn Show\` (the const's own refusal)" "${SH}const C: dyn Show = 5;\nsyscall(60, 0);\n"

# ── U: uninitialised — struct locals are not zeroed ────────────────────────────────────────────────
UM="with its value - "
refused u01 "declare dyn Show 'o' ${UM}struct locals are not zeroed" "U1: \`var o: dyn Show;\` in a fn" "${SH}fn f(): i64 { var o: dyn Show; return 0; }\nsyscall(60, 0);\n"
refused u02a "declare Hd 'h' ${UM}it holds a dyn" "U2a: \`var h: Hd;\`, Hd holding a dyn" "${SH}struct Hd { a; o: dyn Show; }\nfn f(): i64 { var h: Hd; h.a = 1; return h.a; }\nsyscall(60, 0);\n"
refused u02b "declare H2 'h' ${UM}it holds a dyn" "U2b: through a nested struct field" "${SH}struct Hd { a; o: dyn Show; }\nstruct H2 { h: Hd; b; }\nfn f(): i64 { var h: H2; return 0; }\nsyscall(60, 0);\n"
refused u02c "an array of Hd in a fn is refused" "U2c: \`var hs: Hd[4];\`" "${SH}struct Hd { a; o: dyn Show; }\nfn f(): i64 { var hs: Hd[4]; return 0; }\nsyscall(60, 0);\n"
refused u02d "declare Box\$Hd 'b' ${UM}it holds a dyn" "U2d: through a generic instance \`Box<Hd>\`" "${SH}struct Hd { a; o: dyn Show; }\nstruct Box<T> { v: T; }\nfn f(): i64 { var b: Box<Hd>; return 0; }\nsyscall(60, 0);\n"
exits u03 3 "U3: a struct holding no dyn is still declared uninitialised (unchanged)" "${SH}struct Q { a; b; }\nfn f(): i64 { var q: Q; q.a = 1; q.b = 2; return q.a + q.b; }\nsyscall(60, f());\n"

# ── V: opacity — a dyn is not a value (decision 7) ─────────────────────────────────────────────────
refused v01a "dyn Show 'o' $RV" "V1a: \`o + 1\` (no \`dyn Show_add\` dispatch)" "${HP}${FO}return o + 1;${FE}"
refused v01b "dyn Show 'o' $RV" "V1b: \`1 + o\`" "${HP}${FO}return 1 + o;${FE}"
refused v01c "dyn Show 'o' $RV" "V1c: \`if (o)\`" "${HP}${FO}if (o) { return 1; } return 0;${FE}"
refused v01d "dyn Show 'o' $RV" "V1d: \`!o\`" "${HP}${FO}return !o;${FE}"
refused v01e "dyn Show 'o' $RV" "V1e: \`-o\`" "${HP}${FO}return -o;${FE}"
refused v01f "dyn Show 'o' $RV" "V1f: \`var x = o;\` (it took the data word)" "${HP}${FO}var x = o; return x;${FE}"
refused v01g "dyn Show 'o' $RV" "V1g: an untyped argument \`g(o)\`" "${HP}${FO}return g(o);${FE}"
refused v01h "dyn Show 'o' $RV" "V1h: \`load64(o)\`" "${HP}${FO}return load64(o);${FE}"
refused v01i "dyn Show 'o' $RV" "V1i: \`callptr(&g, o)\`" "${HP}${FO}return callptr(&g, o);${FE}"
refused v01j "dyn Show 'o' $RV" "V1j: \`match o\`" "${HP}${FO}match o { _ => { return 1; } } return 0;${FE}"
refused v01k "dyn Show 'o' $RV" "V1k: \`while (o)\`" "${HP}${FO}while (o) { return 1; } return 0;${FE}"
refused v01l "dyn Show 'o' $RV" "V1l: \`(o) + 1\`" "${HP}${FO}return (o) + 1;${FE}"
refused v01m "compound assignment to struct 'o' is refused" "V1m: \`o += 1\` (the struct rule's own refusal)" "${HP}${FO}o += 1; return 0;${FE}"
refused v02a "the words of dyn Show 'o' are not addressable" "V2a: \`&o\` (a parameter)" "${HP}${FO}return &o;${FE}"
refused v02b "the words of dyn Show 'o2' are not addressable" "V2b: \`var p = &o2;\` (a local)" "${HP}${FO}var o2: dyn Show = o; var p = &o2; return p;${FE}"
refused v03a "dyn Show 'o' (a field) $RV" "V3a: \`h.o + 1\`" "${HP}${FO}var h: H = H { 1, o, 2 }; return h.o + 1;${FE}"
refused v03b "dyn Show 'o' (a field) $RV" "V3b: \`g(w.o)\`, an untyped argument" "${HP}${FO}var w: W = W { o }; return g(w.o);${FE}"
refused v03c "dyn Show 'o' (a field) $RV" "V3c: \`return w.o;\` from an i64 fn" "${HP}${FO}var w: W = W { o }; return w.o;${FE}"
refused v04a "a dyn Show result $RV" "V4a: \`pass(o) + 1\`" "${HP}${FO}return pass(o) + 1;${FE}"
refused v04b "a dyn Show result $RV" "V4b: \`g(pass(o))\`, an untyped argument" "${HP}${FO}return g(pass(o));${FE}"
refused v04c "a dyn Show result $RV" "V4c: \`(pass(o)) + 1\`" "${HP}${FO}return (pass(o)) + 1;${FE}"
refused v04d "a dyn Show result $RV" "V4d: an un-annotated \`var x = (pass(o));\` (it kept the data word)" "${HP}${FO}var x = (pass(o)); return 0;${FE}"
refused v04e "a dyn Show result $RV" "V4e: a method result, \`p.mk(o) + 1\`" "${HP}struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\n${FO}var q = Q { 1, 2 }; return q.mk(o) + 1;${FE}"
refused v04f "a dyn Show result $RV" "V4f: \`1 + p.mk(o)\`" "${HP}struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\n${FO}var q = Q { 1, 2 }; return 1 + q.mk(o);${FE}"
refused v04g "a dyn Show result $RV" "V4g: \`return pass(o);\` from an i64 fn" "${HP}fn f(o: dyn Show, k): i64 { if (k > 0) { return 1; } return (pass(o)); }\nsyscall(60, 0);\n"
VF="unknown field '"
refused v05a "${VF}data' on struct 'dyn Show'" "V5a: \`o.data\`" "${HP}${FO}return o.data;${FE}"
refused v05b "${VF}vtable' on struct 'dyn Show'" "V5b: \`o.vtable\`" "${HP}${FO}return o.vtable;${FE}"
refused v05c "${VF}data' on struct 'dyn Show'" "V5c: \`o.data = 5;\`" "${HP}${FO}o.data = 5; return 0;${FE}"
refused v05d "${VF}0' on struct 'dyn Show'" "V5d: \`o.0\`" "${HP}${FO}return o.0;${FE}"
refused v05e "${VF}show' on struct 'dyn Show'" "V5e: \`o.show\` (no call)" "${HP}${FO}return o.show;${FE}"
refused v06a "multi-value destructure of a dyn Show 'pass' result" "V6a: \`var a, b = pass(o);\`" "${HP}${FO}var a, b = pass(o); return a;${FE}"
refused v06b "cannot re-assign from 'pass' - it returns struct 'dyn Show', not multiple values" "V6b: \`a, b = pass(o);\` (the re-assignment's own refusal)" "${HP}${FO}var a = 0; var b = 0; a, b = pass(o); return a;${FE}"
refused v07a "a fn returning dyn Show returns a whole dyn" "V7a: \`return (a, b);\` in a fn returning a dyn" "${HP}fn mk(a, b): dyn Show { return (a, b); }\nsyscall(60, 0);\n"
refused v07b "a fn returning dyn Show returns a whole dyn" "V7b: \`ret2(a, b)\`" "${HP}fn mk(a, b): dyn Show { ret2(a, b); }\nsyscall(60, 0);\n"
refused v08 "dyn Show 'o' (a field) is set from a whole dyn - a struct literal cannot write its words" "V8: \`H { 1, 2, 3, 4 }\` (its leaves were the dyn's two words)" "${HP}${FO}var h: H = H { 1, 2, 3, 4 }; return h.a;${FE}"
refused v09a "cannot initialize dyn Show 'x' with a value that is not a dyn" "V9a: backstop \`var x: dyn Show = 5;\`" "${HP}${FO}var x: dyn Show = 5; return 0;${FE}"
refused v09b "cannot assign a value that is not a dyn to dyn Show 'x'" "V9b: backstop \`x = 5;\`" "${HP}${FO}var x: dyn Show = o; x = 5; return 0;${FE}"
refused v09c "cannot store a value that is not a dyn into dyn Show 'o' (a field)" "V9c: backstop \`h.o = 5;\`" "${HP}${FO}var h: H = H { 1, o, 2 }; h.o = 5; return 0;${FE}"

# ── P: every destination of a dyn call result takes it whole ───────────────────────────────────────
# The value rows: each line returns its own code when the dyn it received is not (4, 9).
PB="${HP}struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\nfn take(k, o: dyn Show, j): i64 { return k * 1000 + dw(o) * 10 + j; }\nfn rw(o: dyn Show): dyn Show { return (pass(o)); }\nfn rd(o: dyn Show): dyn Show {\n    defer { syscall(1, 1, \"\", 0); }\n    return pass(o);\n}\nfn rr(o: dyn Show, k): dyn Show {\n    if (k > 0) { return rr(o, k - 1); }\n    return pass(o);\n}\n${FM}    var q = Q { 1, 2 };\n"
PL='    var y1: dyn Show = pass(o);\n    if (dw(y1) != 49) { return 1; }\n    var y2: dyn Show = (pass(o));\n    if (dw(y2) != 49) { return 2; }\n    var x3 = pass(o);\n    if (dw(x3) != 49) { return 3; }\n    var z: dyn Show = get(mkw(1, 2));\n    z = pass(o);\n    if (dw(z) != 49) { return 4; }\n    z = get(mkw(1, 2));\n    z = (pass(o));\n    if (dw(z) != 49) { return 5; }\n    var h: H = H { 7, get(mkw(1, 2)), 8 };\n    h.o = pass(o);\n    if (dw(h.o) != 49) { return 6; }\n    h.o = get(mkw(1, 2));\n    h.o = (pass(o));\n    if (dw(h.o) + h.a * 1000 + h.b * 100 != 7849) { return 7; }\n    if (take(3, pass(o), 5) != 3495) { return 8; }\n    if (take(3, (pass(o)), 5) != 3495) { return 9; }\n    var h2: H = H { 6, pass(o), 2 };\n    if (dw(h2.o) + h2.a * 1000 + h2.b * 100 != 6249) { return 10; }\n    var m1: dyn Show = q.mk(o);\n    if (dw(m1) != 49) { return 11; }\n    var m2: dyn Show = (q.mk(o));\n    if (dw(m2) != 49) { return 12; }\n    var m3 = q.mk(o);\n    if (dw(m3) != 49) { return 13; }\n    z = q.mk(o);\n    if (dw(z) != 49) { return 14; }\n    if (take(2, q.mk(o), 1) != 2491) { return 15; }\n    if (dw(rw(o)) != 49) { return 16; }\n    if (dw(rd(o)) != 49) { return 17; }\n    if (dw(rr(o, 3)) != 49) { return 18; }\n    if (dw(pass(pass(o))) != 49) { return 19; }\n    var c = || dw(o);\n    if (callptr(c) != 49) { return 20; }\n    secret var s: dyn Show = o;\n    if (dw(s) != 49) { return 21; }\n    return 42;\n'
exits p01 42 "P1-P21: var (annotated, wrapped, inferred), assignment (bare, wrapped), field store (bare, wrapped), argument (bare, wrapped), struct-literal element, a method result (var / wrapped / inferred / assignment / argument), return (wrapped, non-tail in a \`defer\` fn, after a tail call), a nested call, a closure capture, \`secret var\` — each takes the dyn whole" "${PB}${PL}${ME}"

# ── H28: the fold, across a newline and a comment; the caret on `dyn` ───────────────────────────────
exits h28a 49 "H28a: \`dyn\` and its trait split across a newline and a comment fold to one type" "${HP}fn k(o: dyn\n    # a comment\n    Show): i64 { return dw(o); }\n${FM}    return k(o);\n${ME}"
printf '%b' "${SH}fn f(o: dyn\n    Nope): i64 { return 0; }\nsyscall(60, 0);\n" > "$T/h28b.cyr"
build h28b
cl=$(grep -A2 '^error' "$T/h28b.err" | sed -n 3p)
if [ "$rc" -ne 0 ] && grep -qF "error:<source>:4:9: 'Nope' is not a trait" "$T/h28b.err" && [ "$cl" = "            ^" ]; then ok "H28b: a diagnostic on a folded \`dyn Nope\` points at \`dyn\` (4:9, the caret under it)"
else bad "H28b: rc $rc: $(head -3 "$T/h28b.err" | tr '\n' '|')"; fi
exits h28c 7 "H28c: a unit spelling no \`dyn\` folds nothing (\`dynamo\` stays a name)" 'fn f(): i64 { var dynamo = 7; return dynamo; }\nsyscall(60, f());\n'

# ── X: --syntax-only (cyrius lint's pre-pass) ──────────────────────────────────────────────────────
printf '%b' "${SH}fn f(o: dyn Nope, v: *dyn Show): i64 { var u: dyn Show; return 0; }\nsyscall(60, 0);\n" > "$T/x01.cyr"
rc=0; "$CC" --syntax-only < "$T/x01.cyr" > /dev/null 2> "$T/x01.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/x01.err"; then ok "X1: --syntax-only reports no dyn refusal (T1 / T5 / U1 resolve types)"
else bad "X1: --syntax-only rc $rc: $(grep '^error' "$T/x01.err" | head -1)"; fi
printf 'fn f(): i64 { var dyn = 5; return 0; }\nsyscall(60, f());\n' > "$T/x02.cyr"
rc=0; "$CC" --syntax-only < "$T/x02.cyr" > /dev/null 2> "$T/x02.err" || rc=$?
if [ "$rc" -ne 0 ] && grep -qF "$KW" "$T/x02.err"; then ok "X2: --syntax-only still reports \`var dyn\` (the reserved word is grammar)"
else bad "X2: --syntax-only rc $rc: $(head -1 "$T/x02.err")"; fi

# ── TT: the tools ──────────────────────────────────────────────────────────────────────────────────
if awk '/^fn _embed_reserved_list\(/,/^}/' cbt/manifest.cyr | grep -q ' dyn '; then ok "TT1: \`[embed]\`'s reserved list holds \`dyn\` (embed_manifest_refusals.sh axis 5 checks it against the compiler)"
else bad "TT1: cbt/manifest.cyr _embed_reserved_list lacks dyn"; fi
if grep -q '|trait|const|dyn)' editors/vscode/syntaxes/cyrius.tmLanguage.json; then ok "TT2: the VS Code grammar lists \`dyn\` as a keyword"
else bad "TT2: editors/vscode/syntaxes/cyrius.tmLanguage.json lacks dyn"; fi
mkdir -p "$T/tl" "$T/tl/home"
printf 'trait Show { fn show(self): i64; }\nfn f(o: dyn Show): i64 { return 0; }\nvar dynamo = 1;\n' > "$T/tl/st.cyr"
if "$CC" < programs/cyrius-lsp.cyr > "$T/tl/lsp" 2> "$T/tl/lsp.err" && [ "$(wc -c < "$T/tl/lsp")" -gt 20000 ]; then
    chmod +x "$T/tl/lsp"
    lsp_frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c | tr -d ' ')" "$1"; }
    { lsp_frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
      lsp_frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$T/tl/st.cyr"'","languageId":"cyrius","version":1,"text":""}}}'
      lsp_frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/semanticTokens/full","params":{"textDocument":{"uri":"file://'"$T/tl/st.cyr"'"}}}'
      lsp_frame '{"jsonrpc":"2.0","id":99,"method":"shutdown"}'; } > "$T/tl/lsp.in"
    (cd "$T/tl" && PATH=/usr/bin:/bin HOME="$T/tl/home" timeout 30 ./lsp < lsp.in > lsp.out 2> lsp.run.err) || :
    grep -o '"id":2,"result":{"data":\[[0-9,]*\]' "$T/tl/lsp.out" | sed 's/.*\[//; s/\]$//' | tr ',' '\n' | \
        awk 'NF { a[n++] = $1 } END { l = 0; c = 0; for (i = 0; i + 4 < n; i += 5) { if (a[i] > 0) { l += a[i]; c = a[i + 1] } else { c += a[i + 1] }; print l ":" c ":" a[i + 2] ":" a[i + 3] } }' > "$T/tl/st.tok"
    if grep -qx '1:8:3:5' "$T/tl/st.tok" && ! grep -q '^2:4:6:5$' "$T/tl/st.tok"; then ok "TT3: cyrius-lsp colours \`dyn\` a keyword (1:8, type 5), \`dynamo\` not"
    else bad "TT3: cyrius-lsp semantic tokens: $(tr '\n' ' ' < "$T/tl/st.tok")"; fi
else bad "TT3: could not build programs/cyrius-lsp.cyr: $(head -1 "$T/tl/lsp.err")"; fi

# ── A: the P program on every backend ──────────────────────────────────────────────────────────────
printf '%b' "${PB}${PL}${ME}" > "$T/ap.cyr"
for mode in IR3 DCE; do
    if [ "$mode" = IR3 ]; then ev=CYRIUS_IR=3; else ev=CYRIUS_DCE=1; fi
    rc=0; env $ev "$CC" < "$T/ap.cyr" > "$T/ap_$mode.bin" 2> "$T/ap_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "A $mode: rc $rc: $(grep '^error' "$T/ap_$mode.err" | head -1)"
    else chmod +x "$T/ap_$mode.bin"; got=0; timeout 10 "$T/ap_$mode.bin" || got=$?
        [ "$got" -eq 42 ] && ok "A x86 $ev: the P program exits 42" || bad "A x86 $ev: exit $got, want 42"; fi
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        if "$T/cc_a64" < "$T/ap.cyr" > "$T/ap.a" 2> "$T/ap.aerr"; then
            chmod +x "$T/ap.a"; got=0; (cd "$T" && timeout 60 qemu-aarch64 ./ap.a > /dev/null 2>&1) || got=$?
            [ "$got" -eq 42 ] && ok "A aarch64 (qemu): exit 42" || bad "A aarch64 (qemu): exit $got, want 42"
        else bad "A aarch64: did not compile: $(grep '^error' "$T/ap.aerr" | head -1)"; fi
    else bad "A aarch64: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$T/ap.cyr" > "$T/ap.cyx" 2> "$T/ap.cxerr" && [ -s "$T/ap.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/ap.cyx" > /dev/null 2>&1 || got=$?
        [ "$got" -eq 42 ] && ok "A cx (cxvm): exit 42" || bad "A cx (cxvm): exit $got, want 42"
    else bad "A cx: did not compile: $(grep '^error' "$T/ap.cxerr" | head -1)"; fi
else bad "A cx: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$T/ap.cyr" > "$T/ap.exe" 2> "$T/ap.werr" && [ -s "$T/ap.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./ap.exe > /dev/null 2>&1) || got=$?
        [ "$got" -eq 42 ] && ok "A PE (wine): exit 42" || bad "A PE (wine): exit $got, want 42"
    else bad "A PE: did not compile: $(grep '^error' "$T/ap.werr" | head -1)"; fi
else echo "  SKIP A PE — wine not installed"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: dyn_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: dyn_checked — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: dyn_checked — \`dyn\`: the reserved word (K); the type in a local, a global, a parameter, a return, a field and a trait signature (TY, S); every open type position refused by name (T1-T13); uninitialised dyn locals (U); opacity — no value, no address, no words (V1-V9); every destination of a dyn result takes it whole (P); the fold across lines (H28); --syntax-only (X); the tools (TT); the P program on x86 / IR=3 / DCE / aarch64 / cx / PE (A)"
