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
#   P  (6.7.11, issues/archived/2026-10-13-generic-pointer-returning-call-as-struct-source.md) a GENERIC call declared
#      `: *T` is a struct source, as `fn gp(): *S` is: the filed repro VERBATIM (16 B) — `l = gpg<S>()` 8,
#      `var q: S = *gpg<S>()` 58, `take(*gpg<S>())` 58, `a - *gpg<S>()` 41, `*gpg<S>() + a` 69, the field
#      form `gpg<S>().v` 5, the control 58 (through 6.7.10: 102, 139 x4, refused, 58); the field form at top
#      level, through a chain (`gpw<S>().p.v`) and inferred (`gpi(p).w`); a `*U` instance refused by name,
#      naming the CALL (`gug`, not its type argument) — into a variable, a field, a by-value argument, an
#      operator's operand, a declaration-zone global; a zone global from a generic fn declared below it
#      refused by name, as `*gp()` is. The values on every leg are tests/tcyr/crossos/
#      generic_ptr_struct_source.tcyr (small_struct_handle_line.sh R12).
#
# Mutations (scratch trees): skip `_sdef_gen_prescan` -> C and the tcyr RED (the instance's fields
# land inside the outer's pool slice); `_sfield_named` straight to `_add_named_field` -> C RED
# (`expected identifier, got '<'`); `PP_DTARGS` back to one identifier -> D1 RED (W_m undefined);
# drop `_sname_minted` -> S3 RED (reported twice).
# 6.7.11 (P, the same method; each a scratch copy of the tree with the one change):
#   the tree before it (7a9938e8)                    -> RED 17: P1 102, P2-P5 139, P6 refused; PF1-PF3 refused;
#                                                       PR1-PR7 compiled clean; PB compiled (it SIGSEGVs)
#   MP1 `_hl_pchain` without the generic arm (the early returns back) -> RED 13: P1 102, P2-P5 139, PR1-PR7
#                                                       compiled, PB compiled (P6 / PF stay green: the
#                                                       instance's record); the tcyr SIGSEGVs at its zone row
#   MP2 `_ret_ptr_record` reading `*T` without the binding (`_ptr_ann_sid`) -> RED 4: P6, PF1-PF3 refused
#                                                       (the tcyr does not build)
#   MP3 `_call_ptr_field` without the explicit `g<..>(` arm -> RED 3: P6, PF1, PF2 refused (PF3, inferred,
#                                                       stays green; the tcyr does not build)
#   MP4 `_hl_lastnm` without the type-argument skip -> RED 8: PR1-PR7 name 'U', PB names 'S'
#
#   PG (6.7.14, issues/2026-10-14-generic-pointer-to-generic-struct-return-refused.md) a generic declared `: *Box<T>`:
#      the filed repro verbatim (exit 3; refused twice, "unknown type 'T' as a type argument"), `gp(mkp(p))` 8,
#      `mkp<Pt>(p).n` 8, `var q: *Box<Pt> = mkp(p); q.v.y` 7, `mkp(5).n` 8; an unknown `: *Box<Zork>` refused once,
#      generic or not (twice before); a struct declared below the fn as its type argument compiles (pass 1 refused it).
#      `_ret_ptr_annot` binds the base's T -> i64 (`_ret_ptr_base_bind`); pass 1 reads a `*G<..>` return only when its
#      arguments resolve (`_ret_ptr_sid`). The values on every leg: generic_ptr_struct_source.tcyr `pb*`.
#   MG1 `_ret_ptr_base_bind` returns 0 (2026-10-16)  -> RED 5: PG0-PG4 (refused: unknown type 'T'; the tcyr
#                                                       does not build)
#   MG2 `_ret_ptr_sid` without its pass-1 test       -> RED 3: PG5 PG6 (reported twice), PG7 (refused)
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

# P — 6.7.11: a generic call declared `: *T` is a struct source (issues/2026-10-13-generic-pointer-returning-call-
# as-struct-source.md). The filed repro, verbatim (its `row` helper's run and refusal, paths only moved).
PH='struct S { v; w; }
var GS = S { 5, 8 };
fn gpg<T>(): *T { return &GS; }
fn take(s: S): i64 { return s.v * 10 + s.w; }
fn S_sub(a: *S, b: *S): S { var r: S; r.v = a.v - b.v; r.w = a.w - b.w; return r; }
fn S_add(a: *S, b: *S): S { var r: S; r.v = a.v + b.v; r.w = a.w + b.w; return r; }'
prow() {   # <name> <want exit> <what> <main> — the filed `row`: built with the header, run
    printf '%s\n%s\nsyscall(60, main());\n' "$PH" "$4" > "$T/$1.cyr"
    exits "$1" "$2" "$3"
}
prow p1 8 "P1: l = gpg<S>() copies (l.w 8; 102 = the pointer word in l.v)" \
  'fn main(): i64 { var l: S; l.v = 1; l.w = 2; l = gpg<S>(); return (l.v == &GS) * 100 + l.w; }'
prow p2 58 "P2: var q: S = *gpg<S>()" 'fn main(): i64 { var q: S = *gpg<S>(); return q.v * 10 + q.w; }'
prow p3 58 "P3: take(*gpg<S>())" 'fn main(): i64 { return take(*gpg<S>()); }'
prow p4 41 "P4: a - *gpg<S>()" \
  'fn main(): i64 { var a: S; a.v = 9; a.w = 9; var c: S = a - *gpg<S>(); return c.v * 10 + c.w; }'
prow p5 69 "P5: *gpg<S>() + a" \
  'fn main(): i64 { var a: S; a.v = 1; a.w = 1; var c: S = *gpg<S>() + a; return c.v * 10 + c.w; }'
prow p6 5 "P6: gpg<S>().v" 'fn main(): i64 { return gpg<S>().v; }'
prow p7 58 "P7: control, via var p: *S" 'fn main(): i64 { var p: *S = gpg<S>(); var l: S = p; return l.v * 10 + l.w; }'
# the field form at top level, through a chain, inferred
printf '%s\nvar R = gpg<S>().w * 10 + gpg<S>().v;\nsyscall(60, R);\n' "$PH" > "$T/pf1.cyr"
exits pf1 85 "PF1: gpg<S>().w at top level"
printf '%s\nstruct WP { n; p: *S; }\nvar GW = WP { 0, &GS };\nfn gpw<T>(): *T { return &GW; }\nfn main(): i64 { return gpw<WP>().p.w * 10 + gpw<WP>().p.v; }\nsyscall(60, main());\n' "$PH" > "$T/pf2.cyr"
exits pf2 85 "PF2: gpw<WP>().p.w, a chain through the instance's *T"
printf '%s\nfn gpi<T>(x: *T): *T { return x; }\nfn main(): i64 { var p: *S = &GS; return gpi(p).w * 10 + gpi(p).v; }\nsyscall(60, main());\n' "$PH" > "$T/pf3.cyr"
exits pf3 85 "PF3: gpi(p).w, inferred (p: *S)"
# a `*U` instance of another struct, refused by name — naming the CALL, not its type argument
PU="$PH"'
struct U { a; b; }
struct O { k; s: S; }
var GX = U { 1, 2 };
fn gug<T>(): *T { return &GX; }'
prefuse() {   # <name> <message> <what> <body>
    printf '%s\n%s\n' "$PU" "$4" > "$T/$1.cyr"
    refused_once "$1" "$2" "$3"
}
MV="into a variable of a different struct/vector type"
prefuse pr1 "cannot copy 'gug' $MV: 'l'" "PR1: l = gug<U>()" \
  'fn main(): i64 { var l = S { 1, 2 }; l = gug<U>(); return l.v; }
syscall(60, main());'
prefuse pr2 "cannot copy 'gug' $MV: 'q'" "PR2: var q: S = *gug<U>()" \
  'fn main(): i64 { var q: S = *gug<U>(); return q.v; }
syscall(60, main());'
prefuse pr3 "cannot copy 'gug' $MV: 'l'" "PR3: l = *gug<U>()" \
  'fn main(): i64 { var l = S { 1, 2 }; l = *gug<U>(); return l.v; }
syscall(60, main());'
prefuse pr4 "cannot copy 'gug' into a struct field of a different struct type: 's'" "PR4: o.s = gug<U>()" \
  'fn main(): i64 { var o: O; o.s = gug<U>(); return 0; }
syscall(60, main());'
prefuse pr5 "cannot pass 'gug' to a parameter of a different struct type in a call to 'take'" "PR5: take(*gug<U>())" \
  'fn main(): i64 { return take(*gug<U>()); }
syscall(60, main());'
prefuse pr6 "cannot pass 'gug' to a parameter of a different struct type in a call to 'S_sub'" "PR6: a - *gug<U>()" \
  'fn main(): i64 { var a = S { 1, 2 }; var c: S = a - *gug<U>(); return c.v; }
syscall(60, main());'
prefuse pr7 "cannot copy 'gug' $MV: 'Z'" "PR7: a declaration-zone var Z: S = *gug<U>()" \
  'var Z: S = *gug<U>();
fn main(): i64 { return Z.v; }
syscall(60, main());'
# a zone global from a generic fn declared BELOW it: refused by name, as `*gp()` is (it SIGSEGV'd)
printf 'struct S { v; w; }\nvar GS = S { 5, 8 };\nvar Z: S = *gpg<S>();\nfn gpg<T>(): *T { return &GS; }\nfn main(): i64 { return Z.v * 10 + Z.w; }\nsyscall(60, main());\n' > "$T/pb.cyr"
refused_once pb "cannot copy-init 'Z' from a dereference of a global or fn declared below it (declare it first): 'gpg'" "PB: var Z: S = *gpg<S>() above gpg"

# PG — 6.7.14: a generic declared `: *Box<T>` (issues/2026-10-14-generic-pointer-to-generic-struct-return-refused.md).
# The filed repro, verbatim; its rows; an unknown type argument in a `: *G<..>` return refused once (pass 1 reads it
# only when its arguments resolve, as it sizes it — it reported in pass 1 AND pass 2); and so a struct declared below
# the fn, which pass 1 does not know yet, is no longer refused there (as `: *Later` never was).
cat > "$T/pg0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mkp<T>(x: T): *Box<T> { return 0; }
syscall(60, 3);
EOF
exits pg0 3 "PG0: the filed repro verbatim, fn mkp<T>(x: T): *Box<T> (refused twice before)"
PGH='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mkp<T>(x: T): *Box<T> { var b: *Box<T> = alloc(32); b.v = x; b.n = 8; return b; }'
pgrow() {   # <name> <want exit> <what> <rest>
    printf '%s\n%s\nsyscall(60, main());\n' "$PGH" "$4" > "$T/$1.cyr"
    exits "$1" "$2" "$3"
}
pgrow pg1 8 "PG1: gp(mkp(p)) — a *Box<T> carrier given the *Box<T> call" \
  'fn gp<T>(b: *Box<T>): i64 { return b.n; }
fn main(): i64 { var p = Pt { 6, 7 }; return gp(mkp(p)); }'
pgrow pg2 8 "PG2: mkp<Pt>(p).n" 'fn main(): i64 { var p = Pt { 6, 7 }; return mkp<Pt>(p).n; }'
pgrow pg3 7 "PG3: var q: *Box<Pt> = mkp(p); q.v.y" \
  'fn main(): i64 { var p = Pt { 6, 7 }; var q: *Box<Pt> = mkp(p); return q.v.y; }'
pgrow pg4 8 "PG4: mkp(5).n (the i64 base)" 'fn main(): i64 { return mkp(5).n; }'
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nfn mkz<T>(x: T): *Box<Zork> { return 0; }\nsyscall(60, 3);\n' > "$T/pg5.cyr"
refused_once pg5 "unknown type 'Zork' as a type argument" "PG5: fn mkz<T>(x: T): *Box<Zork> (twice before)"
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nfn mkz(x): *Box<Zork> { return 0; }\nsyscall(60, 3);\n' > "$T/pg6.cyr"
refused_once pg6 "unknown type 'Zork' as a type argument" "PG6: fn mkz(x): *Box<Zork> (twice before)"
cat > "$T/pg7.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Box<T> { v: T; n; }
fn mk(): *Box<Later> { var b: *Box<Later> = alloc(64); b.v.y = 7; b.n = 2; return b; }
struct Later { x; y; }
fn main(): i64 { var q: *Box<Later> = mk(); return q.v.y * 10 + mk().n; }
syscall(60, main());
EOF
exits pg7 72 "PG7: fn mk(): *Box<Later> with Later declared below it (pass 1 refused it 'unknown type')"

if [ "$fails" -ne 0 ]; then echo "FAIL: generic_struct_field — $fails row(s) red"; exit 1; fi
echo "PASS: generic_struct_field — a field naming its own struct is refused once (S1-S4), #derive walks nested type arguments (D1) and refuses an inline instance by its layout backstop (D2), b: Box<i32> runs (C), a generic call declared : *T is a struct source (P, PF, PR, PB), and a generic declared : *Box<T> compiles (PG)"
