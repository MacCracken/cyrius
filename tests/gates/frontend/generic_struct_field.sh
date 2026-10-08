#!/bin/sh
# tests/gates/frontend/generic_struct_field.sh — 6.7.1 (C3 prerequisite)
#
# A STRUCT FIELD TYPED WITH A GENERIC STRUCT INSTANCE, `b: Box<i32>`, AND `#derive` OVER NESTED TYPE
# ARGUMENTS. Before 6.7.1 the field was `expected identifier, got '<'`, and `#derive`'s field walk
# took one identifier inside `<..>` and wanted `>`, so `xs: Vec<Box<i64>>` stopped it and every
# field after that one lost its derived code (`#derive(accessors)` never defined `W_m`). The runtime
# half — layouts, reads and writes through the instance field, in plain / generic / union outers —
# is tests/tcyr/crossos/generic_struct_field.tcyr.
#
#   S  a field naming the struct being defined — directly (`b: W<i32>` in `W<T>`) or inside its type
#      arguments (`b: Box<A>` in `A`, `b: Box<W<T>>`, a union) — is refused ONCE, by name: the
#      struct would contain itself (the instance re-parse stays quiet)
#   D1 `#derive(accessors)` walks past `xs: Vec<Box<i64>>` and `ps: Vec<Pair<i64, i64>>`: the
#      accessors of the fields after them exist and run (exit 42)
#   D2 a `#derive`d struct holding a generic instance INLINE is refused by the derive layout
#      backstop, as one holding any struct that is not itself derived is (never a silent layout)
#   C  ANTI-VACUOUS: `b: Box<i32>` builds and runs (exit 42)
#
# Mutations (scratch trees): skip `_sdef_gen_prescan` -> C and the tcyr RED (the instance's fields
# land inside the outer's pool slice); `_sfield_named` straight to `_add_named_field` -> C RED
# (`expected identifier, got '<'`); `PP_DTARGS` back to one identifier -> D1 RED (W_m undefined);
# drop `_sname_minted` -> S3 RED (reported twice).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: generic_struct_field: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: generic_struct_field: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused_once() {   # <name> <message fragment> <what>
    build "$1"
    n=$(grep -cF "$2" "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$n" -ne 1 ]; then bad "$3: '$2' reported $n times (want 1): $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
BX='struct Box<T> { v: T; n; }'

printf '%s\nstruct A { a; b: Box<A>; }\nsyscall(60, 1);\n' "$BX" > "$T/s1.cyr"
refused_once s1 "field 'b' makes a struct contain itself: 'A'" "S1: b: Box<A> inside A"
printf 'struct W<T> { a; b: W<i32>; }\nsyscall(60, 1);\n' > "$T/s2.cyr"
refused_once s2 "field 'b' makes a struct contain itself: 'W'" "S2: b: W<i32> inside W<T>"
printf '%s\nstruct W<T> { a: T; b: Box<W<T>>; }\nfn f(): i64 { var w: W<i32>; return 1; }\nsyscall(60, f());\n' "$BX" > "$T/s3.cyr"
refused_once s3 "field 'b' makes a struct contain itself: 'W'" "S3: b: Box<W<T>>, and W<i32> used (the instance stays quiet)"
printf '%s\nunion U { a; b: Box<U>; }\nsyscall(60, 1);\n' "$BX" > "$T/s4.cyr"
refused_once s4 "field 'b' makes a struct contain itself: 'U'" "S4: a union"

cat > "$T/d1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
struct Box<T> { v: T; n; }
struct Pair<A, B> { a: A; b: B; }
#derive(accessors)
struct W { n: i64; xs: Vec<Box<i64>>; ps: Vec<Pair<i64, i64>>; m: i64; }
fn main(): i64 { var w: W; W_set_n(&w, 40); W_set_m(&w, 2); return W_n(&w) + W_m(&w); }
syscall(60, main());
EOF
exits d1 42 "D1: #derive(accessors) past Vec<Box<i64>> and Vec<Pair<i64, i64>>"
printf 'include "lib/syscalls.cyr"\n%s\n#derive(accessors)\nstruct W { a: i64; b: Box<i32>; m: i64; }\nfn main(): i64 { var w: W; return 1; }\nsyscall(60, main());\n' "$BX" > "$T/d2.cyr"
refused_once d2 "field offsets disagree with the struct layout" "D2: an inline Box<i32> in a #derive'd struct (the layout backstop)"

printf '%s\nstruct H { a: i64; b: Box<i32>; c: i64; }\nfn main(): i64 { var h: H; h.a = 30; h.b.v = 5; h.b.n = 6; h.c = 1; return h.a + h.b.v + h.b.n + h.c + sizeof(H) - 28; }\nsyscall(60, main());\n' "$BX" > "$T/c.cyr"
exits c 42 "C: b: Box<i32> builds and runs (sizeof 28)"

if [ "$fails" -ne 0 ]; then echo "FAIL: generic_struct_field — $fails row(s) red"; exit 1; fi
echo "PASS: generic_struct_field — a field naming its own struct is refused once (S1-S4), #derive walks nested type arguments (D1) and refuses an inline instance by its layout backstop (D2), and b: Box<i32> runs (C)"
