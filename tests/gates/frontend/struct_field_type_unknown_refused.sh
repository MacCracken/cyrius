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
#      u8/u16/u32/u64 and f32 (8 bytes each), f64, cstring, Result/Option/Tagged, an enum
#      declared above or below, a generic's own `T` (default and CYRIUS_MONOMORPH=0),
#      Vec / Vec<i32> / Vec<P>, a struct declared above
#   I  `s: Str` without lib/str.cyr is refused; with it, the field builds (8 bytes)
#   J  a struct / union naming ITSELF as a field type -> refused by name (the compiler SIGSEGV'd:
#      STRUCTSZ recursed through the field forever); Vec<Self> still builds
#
# Mutations: make `_refuse_field_type` return without reporting -> A-G RED (rc 0). Drop the
# `_declared_later` arm -> C RED (refused as "unknown"). Drop `_field_scalar_width` from the
# ladders -> E (i16v8) and F RED (rc 0). Drop the latch clear -> G RED (one error). Drop the
# `fsid == si + 1` arm in `_add_named_field` -> J RED (compiler rc 139).
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
exits h 167 "H: control: every accepted spelling (47 + 64 + 16 + 40: u8..u64 and f32 are 8 bytes each)"
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

if [ "$fails" -ne 0 ]; then echo "FAIL: struct_field_type_unknown_refused — $fails axis(es) red"; exit 1; fi
echo "PASS: struct_field_type_unknown_refused — an unknown field type is refused by name (A-B, D-G), a field type declared below its use says 'declare it before' (C), every accepted spelling builds at its documented width (H), Str needs its include (I), a struct containing itself is refused (J)"
