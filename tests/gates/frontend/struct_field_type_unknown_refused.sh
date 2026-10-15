#!/bin/sh
# struct_field_type_unknown_refused.sh — 6.6.10: a struct / union field type that names nothing
# is refused BY NAME, and a struct used as a field type above its declaration is refused with
# "declare it before".
#
# ⛔ WHY. The field ladder's last arm was `ADDFIELDTYPED(.., FINDSTRUCT(name))`, and FINDSTRUCT
# answers 0 — the i64 encoding — for a name it does not know. So `struct T { a: Nonexist; }`
# compiled (sizeof 8), and `struct A { b: B; x; }` declared above `struct B { p; q; }` gave A a
# 16-byte layout where the same text below B gives 24: `a.b` loaded 8 bytes of a 16-byte field,
# silently. The same arm swallowed `Vec<Nonexist>` elements, and the prefix-only scalar test
# registered `v: i16v8` as a 2-byte i16 field.
#
#   A  unknown struct field type               -> refused, names the type and the field
#   B  unknown union field type                -> refused by name
#   C  a struct declared BELOW its field use   -> "declare it before 'A'" (struct and union)
#   D  Vec<Unknown> element                    -> refused by name
#   E  i16v8 / f64v2 as a field type           -> refused as a vector type
#   F  `i8x` (a scalar-name prefix)            -> refused by name
#   G  two bad fields in two structs           -> BOTH reported
#   H  control: every accepted spelling builds, with its documented width — i8..i64,
#      u8/u16/u32/u64 (1 / 2 / 4 / 8 since 6.7.10; 8 each before), f32 (4; 8 before), f64,
#      cstring, Result/Option/Tagged, an enum
#      declared above or below, a generic's own `T` (default and CYRIUS_MONOMORPH=0),
#      Vec / Vec<i32> / Vec<P>, a struct declared above
#   I  `s: Str` without lib/str.cyr is refused; with it, the field builds (8 bytes)
#   J  a struct / union naming ITSELF as a field type -> refused by name (the compiler SIGSEGV'd:
#      STRUCTSZ recursed through the field forever); Vec<Self> still builds
#   K  (the field-copy side, same release) a struct of a DIFFERENT type assigned into a
#      struct-typed field — from a name, a call or another field — is refused by name (it stored
#      one word, silently); a struct-valued call into a field at top level is refused (no frame)
#   V  (6.7.11) a `Vec<T>` ANNOTATION reads its T as the D field form does (the user's decision (a),
#      2026-10-13; issues/2026-10-09-vec-annotation-type-argument-unchecked.md). Through 6.7.10 a local,
#      a global, a parameter, `*Vec<T>` and `sizeof(Vec<T>)` skipped the `<..>` unread, so every row here
#      compiled. V1 the filed repro VERBATIM: its four annotations, each refused once (and nothing
#      else); V2 an unknown name and V3 a token that is no type (`1 + 2`) in each position — a local, both
#      global zones, a parameter called above its definition, a `*Vec` local / parameter / declaration-zone
#      global / struct field / return, a `**Vec` parameter, a `*fn(Vec<..>)` parameter, `Vec<Vec<..>>`,
#      `sizeof`, a generic fn's local over its base and two instances — exactly one error naming the
#      variable or parameter; V4 the rest of the vocabulary: a second argument, a trailing operator, a
#      vector, a slice, u128, a prefix-only name (its note), a struct declared below a zone global, two bad
#      elements in one fn (both reported); V5 what keeps compiling: tests/tcyr/crossos/
#      vec_annotation_element.tcyr (every accepted element in every position; the crossos leg runs it on
#      every fork), a generic fn's `Vec<T>` by default and under CYRIUS_MONOMORPH=0, `Vec<dyn Show>` gives
#      the dyn refusal alone, a program's own `struct Vec` is that struct; V6 CYRIUS_MONOMORPH=0 refuses as
#      well; V7 the forks — the repro through the aarch64 and cx compilers built from this tree and the PE
#      target: the same four errors
#
# Mutations: make `_refuse_field_type` return without reporting -> A-G RED (rc 0). Drop the
# `_declared_later` arm -> C RED (refused as "unknown"). Drop `_field_scalar_width` from the
# ladders -> E (i16v8) and F RED (rc 0). Drop the latch clear -> G RED (one error). Drop the
# `fsid == si + 1` arm in `_add_named_field` -> J RED (compiler rc 139). Make `_fsc_src`
# (parse_decl.cyr) return 0 -> K RED (rc 0).
# V (6.7.11; each a one-edit copy of the tree, its compiler built by the fixed one, this gate run from that copy
# with CYCC= it, 2026-10-14; each measured):
#   MV1 `_vec_ann_chk` returning at once -> every V1-V4, V6 and V7 row RED (each builds); V5 green
#   MV2 `_vec_ann_list` without its nested-`Vec` arm -> V2 nest, V3 nest
#   MV3 `_param_type_step` without its check -> V1, V2 / V3 par and ppar, V4b, V7 (the forks' parameter)
#   MV4 `_pty_name` without its check -> V2 / V3 pppar and cb
#   MV5 `_vec_elem_ok` answering 1 -> V1, every V2, V4c, V4f, V4g, V4h, V6, V7
#   MV6 `_vec_tok_err` silent -> V1, every V3, V4a, V4b, V4e, V7
#   MV7 `_gen_ann_sid` without its check -> V1, V2 / V3 loc, gz, gp, nest, szof and gen, V4a, V4c-V4h, V6, V7
#   MV8 `_vec_ann_vn` answering -1 (the message drops the name) -> V1, V2 / V3 loc, gz, gp, nest and gen, V4a,
#       V4c, V4e, V4f, V4h, V6, V7
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: struct_field_type_unknown_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: struct_field_type_unknown_refused: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() { # <name> <message fragment> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "$2" "$T/$1.err"; then
        bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

printf 'struct T { a: Nonexist; x; }\nsyscall(60, sizeof(T));\n' > "$T/a.cyr"
refused a "unknown type 'Nonexist' for struct field 'a'" "A: unknown struct field type"
printf 'union V { a: Nope; b; }\nsyscall(60, sizeof(V));\n' > "$T/b.cyr"
refused b "unknown type 'Nope' for struct field 'a'" "B: unknown union field type"

printf 'struct A { b: B; x: i64; }\nstruct B { p; q; }\nfn main(): i64 { var a: A; a.x = 1; return sizeof(A); }\nsyscall(60, main());\n' > "$T/c1.cyr"
refused c1 "struct field type 'B' is declared after its use; declare it before 'A'" "C: a struct field type declared below"
printf 'union A { b: B; x: i64; }\nunion B { p; q; }\nsyscall(60, sizeof(A));\n' > "$T/c2.cyr"
refused c2 "struct field type 'B' is declared after its use; declare it before 'A'" "C: a union field type declared below"

printf 'struct X { v: Vec<Nope>; }\nsyscall(60, sizeof(X));\n' > "$T/d.cyr"
refused d "unknown type 'Nope' for struct field 'v'" "D: Vec<unknown> element"

for v in i16v8 f64v2; do
    printf 'struct W { v: %s; }\nsyscall(60, sizeof(W));\n' "$v" > "$T/e_$v.cyr"
    refused "e_$v" "vector type '$v' cannot be a struct field type" "E: '$v' as a field type"
done

printf 'struct Z { a: i8x; }\nsyscall(60, sizeof(Z));\n' > "$T/f.cyr"
refused f "unknown type 'i8x' for struct field 'a'" "F: a scalar-name prefix"

printf 'struct T1 { a: Nope1; }\nstruct T2 { b: Nope2; }\nsyscall(60, 0);\n' > "$T/g.cyr"
build g
n=$(grep -c "^error" "$T/g.err")
if [ "$rc" -eq 0 ]; then bad "G: two bad fields: BUILT (rc 0)"
elif [ "$n" -ne 2 ] || ! grep -q "'Nope2'" "$T/g.err"; then bad "G: two bad fields: $n error(s) reported, want 2"
else ok "G: two bad fields: both reported"; fi

cat > "$T/h.cyr" <<'EOF'
enum Color { RED; GREEN; }
struct P { x; y; }
struct Y { a: i8; b: i16; c: i32; d: i64; e: u8; f: u16; g: u32; h: u64; }
struct Z { f: f32; d: f64; s: cstring; r: Result; o: Option; t: Tagged; c: Color; l: Late; }
struct Box<T> { v: T; n; }
struct V { a: Vec; b: Vec<i32>; c: Vec<P>; p: P; }
enum Late { A; B; }
syscall(60, sizeof(Y) + sizeof(Z) + sizeof(Box) + sizeof(V));
EOF
exits h 146 "H: control: every accepted spelling (30 + 60 + 16 + 40: u8..u32 and f32 are their widths)"
cp "$T/h.cyr" "$T/h0.cyr"
rc=0; CYRIUS_MONOMORPH=0 "$CC" < "$T/h0.cyr" > "$T/h0.bin" 2> "$T/h0.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "H: control under CYRIUS_MONOMORPH=0: rc $rc: $(grep '^error' "$T/h0.err" | head -1)"
else ok "H: control under CYRIUS_MONOMORPH=0 builds (own T accepted)"; fi

printf 'struct S1 { s: Str; n; }\nsyscall(60, sizeof(S1));\n' > "$T/i1.cyr"
refused i1 "unknown type 'Str' for struct field 's'" "I: Str without lib/str.cyr"
printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/str.cyr"\nstruct S1 { s: Str; n; }\nsyscall(60, sizeof(S1));\n' > "$T/i2.cyr"
exits i2 16 "I: Str with lib/str.cyr (an 8-byte pointer slot)"

printf 'struct Node { next: Node; val; }\nsyscall(60, sizeof(Node));\n' > "$T/j1.cyr"
refused j1 "field 'next' makes a struct contain itself: 'Node'" "J: a struct containing itself"
printf 'union UN { next: UN; val; }\nsyscall(60, sizeof(UN));\n' > "$T/j2.cyr"
refused j2 "field 'next' makes a struct contain itself: 'UN'" "J: a union containing itself"
printf 'struct Tree { kids: Vec<Tree>; val; }\nsyscall(60, sizeof(Tree));\n' > "$T/j3.cyr"
exits j3 16 "J: Vec<Self> (a handle) still builds"

K='struct Pt { x; y; }\nstruct Big { a; b; c; }\nstruct Box { v: Pt; n; }\nstruct BB { k; w: Big; }\nfn mkbig(a): Big { var p: Big; p.a = a; p.b = a; p.c = a; return p; }\n'
printf "$K"'fn f(): i64 { var g: Big; g.a = 1; var b: Box; b.v = g; return b.n; }\nsyscall(60, f());\n' > "$T/k1.cyr"
refused k1 "cannot copy 'g' into a struct field of a different struct type: 'v'" "K: a different struct type (a name) into a field"
printf "$K"'fn f(): i64 { var b: Box; b.v = mkbig(1); return b.n; }\nsyscall(60, f());\n' > "$T/k2.cyr"
refused k2 "cannot copy 'mkbig' into a struct field of a different struct type: 'v'" "K: a different struct type (a call) into a field"
printf "$K"'fn f(): i64 { var q: BB; q.k = 0; var b: Box; b.v = q.w; return b.n; }\nsyscall(60, f());\n' > "$T/k3.cyr"
refused k3 "cannot copy 'w' into a struct field of a different struct type: 'v'" "K: a different struct type (a field) into a field"
printf "$K"'fn mkpt(a): Pt { var p: Pt; p.x = a; p.y = a; return p; }\nvar GB = Box { 0, 0, 0 };\nGB.v = mkpt(1);\nsyscall(60, GB.v.y);\n' > "$T/k4.cyr"
refused k4 "'mkpt' returns a struct by value, and a struct result needs storage" "K: a struct-valued call into a field at top level"

# ── V (6.7.11): a `Vec<T>` annotation reads its T ──────────────────────────────────────────────────
refused1() {   # <name> <fragment> <what>: refused, exactly one error line, holding the fragment
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep '^error' "$T/$1.err" | grep -qF "$2"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
repro4() {   # <name> <what>: the filed repro's four refusals, at their places, and nothing else
    n=$(grep -c '^error' "$T/$1.err")
    a=$(grep -c "^error:<source>:11:13: a tuple type cannot be a Vec element" "$T/$1.err")
    b=$(grep -c "^error:<source>:14:16: unknown type 'nosuchtype' as the Vec element of 'v'" "$T/$1.err")
    c=$(grep -c "^error:<source>:15:16: expected a Vec element type for 'w', got number 1" "$T/$1.err")
    d=$(grep -c "^error:<source>:16:16: a tuple type cannot be a Vec element" "$T/$1.err")
    if [ "$rc" -ne 0 ] && [ "$n" -eq 4 ] && [ "$a$b$c$d" = "1111" ]; then ok "$2: the four annotations refused, once each"
    else bad "$2: rc $rc, $n error lines ($a$b$c$d): $(grep '^error' "$T/$1.err" | head -4 | tr '\n' '|')"; fi
}
VR="$ROOT/docs/development/issues/repros/2026-10-09-vec-annotation-type-argument-unchecked.cyr"
if [ -f "$VR" ]; then cp "$VR" "$T/v1.cyr"; build v1; repro4 v1 "V1: the filed repro verbatim (it compiled and exited 1)"
else bad "V1: $VR missing"; fi
# vpos <id> <var or -> <what> <source, %s the element>: V2 (an unknown name) and V3 (`1 + 2`) at one position
vpos() {
    printf "$4" "nosuch" > "$T/v2_$1.cyr"
    printf "$4" "1 + 2" > "$T/v3_$1.cyr"
    if [ "$2" = "-" ]; then
        refused1 "v2_$1" "unknown type 'nosuch' as a Vec element" "V2 $1: $3, an unknown name"
        refused1 "v3_$1" "expected a Vec element type, got number 1" "V3 $1: $3, \`1 + 2\`"
    else
        refused1 "v2_$1" "unknown type 'nosuch' as the Vec element of '$2'" "V2 $1: $3, an unknown name"
        refused1 "v3_$1" "expected a Vec element type for '$2', got number 1" "V3 $1: $3, \`1 + 2\`"
    fi
}
vpos loc v "a local" 'fn f(): i64 {\n    var v: Vec<%s> = 0;\n    return 3;\n}\nsyscall(60, f());\n'
vpos gz G "a declaration-zone global" 'var G: Vec<%s> = 0;\nfn f(): i64 { return G; }\nsyscall(60, f());\n'
vpos gp G "a global after the first statement" 'fn f(): i64 { return 3; }\nf();\nvar G: Vec<%s> = 0;\nsyscall(60, G);\n'
vpos par v "a parameter, called above its definition" 'fn f(): i64 { return g(0, 3); }\nfn g(v: Vec<%s>, b): i64 { return b; }\nsyscall(60, f());\n'
vpos ploc p "a \`*Vec\` local" 'fn f(): i64 {\n    var b = 0;\n    var p: *Vec<%s> = &b;\n    return 3;\n}\nsyscall(60, f());\n'
vpos ppar p "a \`*Vec\` parameter" 'fn g(p: *Vec<%s>): i64 { return 1; }\nsyscall(60, g(0));\n'
vpos pgz G "a \`*Vec\` declaration-zone global" 'var G: *Vec<%s> = 0;\nsyscall(60, 0);\n'
vpos pfld p "a \`*Vec\` struct field" 'struct H { p: *Vec<%s>; n; }\nfn f(): i64 { var h: H; h.n = 3; return h.n; }\nsyscall(60, f());\n'
vpos pret - "a \`*Vec\` return" 'fn g(): *Vec<%s> { return 0; }\nsyscall(60, 0);\n'
vpos pppar p "a \`**Vec\` parameter" 'fn g(p: **Vec<%s>): i64 { return 1; }\nsyscall(60, g(0));\n'
vpos cb cb "a \`*fn(Vec<..>): i64\` parameter" 'fn g(cb: *fn(Vec<%s>): i64): i64 { return 1; }\nsyscall(60, g(0));\n'
vpos nest v "\`Vec<Vec<..>>\`" 'fn f(): i64 {\n    var v: Vec<Vec<%s>> = 0;\n    return 3;\n}\nsyscall(60, f());\n'
vpos szof - "\`sizeof(Vec<..>)\`" 'fn f(): i64 { return sizeof(Vec<%s>); }\nsyscall(60, f());\n'
vpos gen v "a generic fn's local, at i64, a struct and i64 again (once)" 'struct Pt { x; y; }\nfn g<T>(x: T): i64 {\n    var v: Vec<%s> = 0;\n    return 1;\n}\nfn f(): i64 { var p: Pt; return g(1) + g(p) + g(2); }\nsyscall(60, f());\n'
printf 'fn f(): i64 {\n    var v: Vec<i64, i64> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v4a.cyr"
refused1 v4a "expected '>' after the Vec element type for 'v', got ','" "V4a: a second argument \`Vec<i64, i64>\`"
printf 'fn g(v: Vec<i64 + 2>): i64 { return 1; }\nsyscall(60, g(0));\n' > "$T/v4b.cyr"
refused1 v4b "expected '>' after the Vec element type for 'v', got '+'" "V4b: \`Vec<i64 + 2>\`"
printf 'fn f(): i64 {\n    var v: Vec<f64v2> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v4c.cyr"
refused1 v4c "vector type 'f64v2' cannot be the Vec element of 'v'" "V4c: a vector element (the field form's E)"
printf 'fn f(): i64 {\n    var v: Vec<[u8]> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v4d.cyr"
refused1 v4d "a slice cannot be a Vec element (6.7.8: slices are fn-locals)" "V4d: a slice element"
printf 'fn f(): i64 {\n    var v: Vec<u128> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v4e.cyr"
refused1 v4e "expected a Vec element type for 'v', got u128" "V4e: u128 (the field form refuses it too)"
printf 'fn f(): i64 {\n    var v: Vec<i8x> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v4f.cyr"
refused1 v4f "unknown type 'i8x' as the Vec element of 'v'" "V4f: a scalar-name prefix"
if grep -qF "'i8x' is not 'i8' - a type name must match whole" "$T/v4f.err"; then ok "V4f: and its prefix note"; else bad "V4f: no prefix note"; fi
printf 'var G: Vec<Later> = 0;\nstruct Later { a; }\nsyscall(60, 0);\n' > "$T/v4g.cyr"
refused1 v4g "type 'Later' is declared after its use; declare it above the first use" "V4g: a declaration-zone global's element declared below (as \`var G: Later\`)"
printf 'fn f(): i64 {\n    var a: Vec<nope1> = 0;\n    var b: Vec<nope2> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v4h.cyr"
build v4h
n=$(grep -c "^error" "$T/v4h.err")
if [ "$rc" -ne 0 ] && [ "$n" -eq 2 ] && grep -q "'nope2' as the Vec element of 'b'" "$T/v4h.err"; then ok "V4h: two bad elements in one fn: both reported"
else bad "V4h: rc $rc, $n error(s), want both"; fi
cp "$ROOT/tests/tcyr/crossos/vec_annotation_element.tcyr" "$T/v5a.cyr"
build v5a
if [ "$rc" -ne 0 ]; then bad "V5a: vec_annotation_element.tcyr: rc $rc: $(grep '^error' "$T/v5a.err" | head -1)"
else
    chmod +x "$T/v5a.bin"; got=0; "$T/v5a.bin" > "$T/v5a.out" 2>&1 || got=$?
    want=$(grep -c 'assert_eq(' "$ROOT/tests/tcyr/crossos/vec_annotation_element.tcyr")
    if [ "$got" -eq 0 ] && grep -q "^$want passed, 0 failed" "$T/v5a.out"; then ok "V5a: vec_annotation_element.tcyr: $want passed (every accepted element, every position)"
    else bad "V5a: exit $got: $(tail -1 "$T/v5a.out")"; fi
fi
# V5b: by default and under CYRIUS_MONOMORPH=0 (which has no explicit `g<T>(..)` call, so not the tcyr): a type
# parameter in scope, the accepted elements, a struct declared below the fn
cat > "$T/v5b.cyr" <<'VEOF'
include "lib/vec.cyr"
struct Box<T> { v: T; }
struct Pt { x; y; }
enum Col { R, G }
var GZ: Vec<Pt> = 0;
fn g<T>(v: Vec<T>): i64 { var w: Vec<T> = v; var pw: *Vec<T> = &w; return vec_len(w); }
fn h(v: Vec<Box<i64>>, u: *Vec<i64>, q: **Vec<Pt>, cb: *fn(Vec<i64>): i64): i64 { return vec_len(v); }
fn main(): i64 {
    var v: Vec<i64> = vec_new(); var b: Vec<Box<i64>> = vec_new(); vec_push(v, 1);
    var c: Vec<Col> = 0; var n: Vec<Vec<Box<i64>>> = 0; var l: Vec<Later> = 0;
    return g(v) + h(b, &v, 0, 0) + sizeof(Vec<i64>) + sizeof(Vec<Vec<Pt>>);
}
struct Later { a; }
syscall(60, main());
VEOF
for mm in 1 0; do
    rc=0; CYRIUS_MONOMORPH=$mm "$CC" < "$T/v5b.cyr" > "$T/v5b$mm.bin" 2> "$T/v5b$mm.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "V5b: CYRIUS_MONOMORPH=$mm: rc $rc: $(grep '^error' "$T/v5b$mm.err" | head -1)"; continue; fi
    chmod +x "$T/v5b$mm.bin"; got=0; "$T/v5b$mm.bin" || got=$?
    if [ "$got" -eq 17 ]; then ok "V5b: CYRIUS_MONOMORPH=$mm: a generic fn's Vec<T> / *Vec<T>, the accepted elements: exit 17"
    else bad "V5b: CYRIUS_MONOMORPH=$mm: exit $got, want 17"; fi
done
printf 'trait Show { fn show(self): i64; }\nfn f(v: Vec<dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n' > "$T/v5c.cyr"
refused1 v5c "dyn Show cannot be a type argument" "V5c: \`Vec<dyn Show>\`: the dyn refusal alone (no Vec message)"
printf 'struct Vec { a; b; }\nstruct W<T> { a: T; }\nfn f(): i64 { var v: Vec; v.a = 3; var p: *Vec = &v; return v.a + sizeof(Vec); }\nsyscall(60, f());\n' > "$T/v5d.cyr"
exits v5d 19 "V5d: a program's own \`struct Vec\` is that struct (3 + 16)"
printf 'fn f(): i64 {\n    var v: Vec<nosuch> = 0;\n    return 3;\n}\nsyscall(60, f());\n' > "$T/v6.cyr"
rc=0; CYRIUS_MONOMORPH=0 "$CC" < "$T/v6.cyr" > "$T/v6.bin" 2> "$T/v6.err" || rc=$?
n=$(grep -c '^error' "$T/v6.err")
if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ] && grep -qF "unknown type 'nosuch' as the Vec element of 'v'" "$T/v6.err"; then ok "V6: CYRIUS_MONOMORPH=0 refuses an unknown element too, once"
else bad "V6: CYRIUS_MONOMORPH=0: rc $rc, $n error(s)"; fi
# V7: the forks. The aarch64 and cx compilers are built from this tree by $CC; PE is $CC's own target.
if [ -f "$VR" ]; then
    for fk in aarch64 cx; do
        if ( cd "$ROOT" && "$CC" < "src/main_$fk.cyr" > "$T/cc_$fk" 2> /dev/null ) && [ -s "$T/cc_$fk" ]; then
            chmod +x "$T/cc_$fk"
            rc=0; ( cd "$ROOT" && "$T/cc_$fk" < "$VR" > "$T/v7_$fk.bin" 2> "$T/v7_$fk.err" ) || rc=$?
            repro4 "v7_$fk" "V7 $fk: the filed repro through the $fk compiler"
        else bad "V7 $fk: NOT RUN — src/main_$fk.cyr did not build"; fi
    done
    rc=0; ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$VR" > "$T/v7_pe.bin" 2> "$T/v7_pe.err" ) || rc=$?
    repro4 v7_pe "V7 PE: the filed repro, CYRIUS_TARGET_WIN=1"
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: struct_field_type_unknown_refused — $fails axis(es) red"; exit 1; fi
echo "PASS: struct_field_type_unknown_refused — an unknown field type is refused by name (A-B, D-G), a field type declared below its use says 'declare it before' (C), every accepted spelling builds at its documented width (H), Str needs its include (I), a struct containing itself is refused (J), a different struct type into a struct field is refused (K), a \`Vec<T>\` annotation reads its T as the field form does (V)"
