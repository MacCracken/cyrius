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
#   PG (6.7.14, issues/archived/2026-10-14-generic-pointer-to-generic-struct-return-refused.md) a generic declared `: *Box<T>`:
#      the filed repro verbatim (exit 3; refused twice, "unknown type 'T' as a type argument"), `gp(mkp(p))` 8,
#      `mkp<Pt>(p).n` 8, `var q: *Box<Pt> = mkp(p); q.v.y` 7, `mkp(5).n` 8; an unknown `: *Box<Zork>` refused once,
#      generic or not (twice before); a struct declared below the fn as its type argument compiles (pass 1 refused it).
#      `_ret_ptr_annot` binds the base's T -> i64 (`_ret_ptr_base_bind`); pass 1 reads a `*G<..>` return only when its
#      arguments resolve (`_ret_ptr_sid`). The values on every leg: generic_ptr_struct_source.tcyr `pb*`.
#   MG1 `_ret_ptr_base_bind` returns 0 (2026-10-16)  -> RED 5: PG0-PG4 (refused: unknown type 'T'; the tcyr
#                                                       does not build)
#   MG2 `_ret_ptr_sid` without its pass-1 test       -> RED 3: PG5 PG6 (reported twice), PG7 (refused)
#   PD (6.7.15, docs/development/issues/2026-10-16-double-pointer-generic-return-read-in-pass-one.md) a `: **G<..>`
#      return's pin is not read by pass 1 while its arguments do not resolve (`_ret_ptr_unres`, shared with
#      `_ret_ptr_sid`'s one-star test): PD1 the filed repro 2 verbatim (`fn mk(): **Box<Later>`, Later declared below:
#      refused "unknown type 'Later'" before) exits 2, PD2 the filed repro 1 verbatim (`: **Box<Zork>`) one error,
#      PD3 `**Box<Pt>` with Pt declared above keeps its pin — `**mk()`, `*mk()` and `take(**mk())` read (25), from a
#      caller below mk and one ABOVE it (pass 1's record, unchanged), PD4 a caller above mk with Later below reads
#      through a `**Box<Later>` local's pin (`**q`, `*q`: 2), PD5 a caller below mk reads `**mk()` through the call's
#      pin (25). (`**mk()` itself in a caller ABOVE mk with Later below is the pre-existing pass-1 record gap that
#      `*Later` / `**Later` / `*Box<Later>` returns share — filed, not this row.)
#   MPD1 `_ret_ptr_record` reads the pin in pass 1 again (the fix reverted; 2026-10-18) -> RED 3: PD1 PD4 PD5 (refused
#                                                       "unknown type 'Later'")
#   MPD2 `_ret_ptr_unres` without its star skip (one `*` only) -> RED 3: PD1 PD4 PD5, as MPD1
#
#   PA (6.7.15, the user's D8 (a), 2026-10-18; docs/development/issues/2026-10-16-pointer-field-generic-type-args-read-only-
#      at-use.md) a late `p: *G<..>` field's type arguments are checked AT THE FIELD, once, used or not (they were read
#      only at a use, so an unused field compiled): PA1 the filed repro verbatim (`p: *Box<Zork>`, unused; exit 7
#      before) refused once at 3:24, PA2 `p: *Box<1>` unused (exit 7 before), PA3 the used form one error line in all,
#      PA4 a use in a fn ABOVE the struct one error, PA5 `*Later<Zork>` with the generic Later declared below, PA6
#      `*Box<Box<Zork>>`, PA7 `struct W<T> { p: *Box<Zork>; }` at two instances, PA8 `*Box<E>` with the enum E declared
#      below (its enum line, not "unknown type"), PA9 three bad fields of one struct each once (three lines); and what
#      stays valid: PA10 two structs pointing at each other through `*Box<B>` / `*Box<A>`, B declared below (52), PA11
#      `*Box<Later<Pt>>` with both declared below (5)
#   MPA1 `_fld_targ_chk` returns at once (2026-10-18)   -> RED 6: PA1 PA2 PA5 PA6 PA7 PA9 compiled (PA3 PA4 PA8 green:
#                                                       their use reports it, once)
#   MPA2 `_ta_late` never set (no name declared below) -> RED 3: PA10 PA11 refused "unknown type 'B'" / 'Later'; PA8
#                                                       "unknown type 'E'", then the use's enum line
#   MPA3 `_is_enum_name` without its declared-below arm -> RED 1: PA8 (two lines, as MPA2)
#
#   HF (6.7.15, docs/development/issues/2026-10-16-generic-struct-pointer-field-does-not-hop.md) a generic struct's
#      `p: *T` field hops in its instance as a `p: *Pt` field does (6.6.17): `b.p.y` with `b: Pb<Pt>` was "expected ';',
#      got '.'". HF1 the filed repro verbatim (9), HF2 a store `b.p.y = 3` (3), HF3 a method `b.p.m()` (78), HF4 inside
#      a generic `fn g<T>(b: Pb<T>) { return b.p.y; }` (9), HF5 `Pb<i32>`'s `b.p + 1` steps 4 (9, unchanged) — on
#      x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine). More shapes on every leg (a compound
#      store, `*Pb<Pt>`, a call's result, a struct's `Pb<Pt>` field, `Pb<Box<Pt>>`, two parameters, a global):
#      tests/tcyr/crossos/generic_pointer_receivers.tcyr's PF rows (generic_ptr_param_infer.sh PT).
#   MHF1 `_fld_ptr_late` without its type-parameter arm (2026-10-18; a scratch tree, its own legs) -> RED 20: HF1-HF4
#                                                       on every leg ("expected ';', got '.'"); HF5 green (and
#                                                       generic_ptr_param_infer.sh PT on every leg: does not build)
#   MHF2 `_fld_ptr_sid` back on `_ptr_tok_sid` (T read unbound) -> RED 20: HF1-HF4 on every leg; HF5 green (PT as MHF1)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: generic_struct_field: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: generic_struct_field: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit (the HF legs).
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

# PG — 6.7.14: a generic declared `: *Box<T>` (issues/archived/2026-10-14-generic-pointer-to-generic-struct-return-refused.md).
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

# PD — 6.7.15: pass 1 leaves a `: **G<..>` return's pin to pass 2 while its arguments do not resolve.
cat > "$T/pd1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Box<T> { v: T; n; }
fn mk(): **Box<Later> { var b: *Box<Later> = alloc(64); b.n = 2; var pp: **Box<Later> = alloc(8); store64(pp, b); return pp; }
struct Later { x; y; }
fn main(): i64 { var q: **Box<Later> = mk(); var b: *Box<Later> = *q; return b.n; }
syscall(60, main());
EOF
exits pd1 2 "PD1: the filed repro 2, fn mk(): **Box<Later> with Later declared below (refused before)"
cat > "$T/pd2.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mkz(x): **Box<Zork> { return 0; }
syscall(60, 3);
EOF
build pd2
ne=$(grep -c '^error' "$T/pd2.err" || true)
if [ "$rc" -ne 0 ] && [ "$ne" -eq 1 ] && grep -qF "error:<source>:3:22: unknown type 'Zork' as a type argument" "$T/pd2.err"; then
    ok "PD2: the filed repro 1, fn mkz(x): **Box<Zork>, refused once at 3:22"
else bad "PD2: rc $rc, $ne error lines (want 1, at 3:22): $(grep '^error' "$T/pd2.err" | tr '\n' ' ')"; fi
PDM='fn mk(): **Box<Pt> { var b: *Box<Pt> = alloc(64); b.n = 2; b.v.y = 5; var pp: **Box<Pt> = alloc(8); store64(pp, b); return pp; }'
PDU='fn main(): i64 { var t: Box<Pt> = **mk(); var p: *Box<Pt> = *mk(); return t.n * 10 + take(**mk()) + p.n * 100 - 200; }'
PDH='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn take(b: Box<Pt>): i64 { return b.v.y; }'
printf '%s
%s
%s
syscall(60, main());
' "$PDH" "$PDM" "$PDU" > "$T/pd3a.cyr"
exits pd3a 25 "PD3a: **Box<Pt> (Pt above): **mk(), *mk(), take(**mk()) below mk (unchanged)"
printf '%s
%s
%s
syscall(60, main());
' "$PDH" "$PDU" "$PDM" > "$T/pd3b.cyr"
exits pd3b 25 "PD3b: ... from a caller ABOVE mk, pass 1's pin (unchanged)"
cat > "$T/pd4.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Box<T> { v: T; n; }
fn main(): i64 { var q: **Box<Later> = mk(); var t: Box<Later> = **q; var b: *Box<Later> = *q; return t.n * 10 + b.v.y; }
fn mk(): **Box<Later> { var b: *Box<Later> = alloc(64); b.n = 2; b.v.y = 5; var pp: **Box<Later> = alloc(8); store64(pp, b); return pp; }
struct Later { x; y; }
syscall(60, main());
EOF
exits pd4 25 "PD4: a caller ABOVE mk (Later below) reads **q / *q through its **Box<Later> local"
cat > "$T/pd5.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Box<T> { v: T; n; }
fn mk(): **Box<Later> { var b: *Box<Later> = alloc(64); b.n = 2; b.v.y = 5; var pp: **Box<Later> = alloc(8); store64(pp, b); return pp; }
struct Later { x; y; }
fn take(b: Box<Later>): i64 { return b.v.y; }
fn main(): i64 { var t: Box<Later> = **mk(); var p: *Box<Later> = *mk(); return t.n * 10 + take(**mk()) + p.n * 100 - 200; }
syscall(60, main());
EOF
exits pd5 25 "PD5: a caller below mk reads **mk() through the call's pin (pass 2's)"

# PA — 6.7.15 (D8 (a)): a late `p: *G<..>` field's type arguments are checked at the field, once, used or not.
one_error() {   # <name> <message fragment> <what>: refused with exactly one error line, which contains the fragment
    build "$1"
    ne=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$ne" -ne 1 ]; then bad "$3: $ne error lines, want 1: $(grep '^error' "$T/$1.err" | tr '\n' ' ')"
    elif grep -qF "$2" "$T/$1.err"; then ok "$3: one error, $2"
    else bad "$3: not '$2': $(grep '^error' "$T/$1.err")"; fi
}
UZ="unknown type 'Zork' as a type argument"
# The filed repro, verbatim (the issue's text).
cat > "$T/pa1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
struct H { p: *Box<Zork>; n; }
fn main(): i64 { var h: H; h.n = 7; return h.n; }
syscall(60, main());
EOF
one_error pa1 "error:<source>:3:24: $UZ" "PA1: the filed repro, p: *Box<Zork> unused, at the field"
sed 's/\*Box<Zork>/*Box<1>/' "$T/pa1.cyr" > "$T/pa2.cyr"
one_error pa2 "error:<source>:3:20: a type argument is a type name, got number 1" "PA2: p: *Box<1> unused"
sed 's/h.n = 7; return h.n;/h.n = 7; h.p.n = 7; return h.p.n;/' "$T/pa1.cyr" > "$T/pa3.cyr"
one_error pa3 "error:<source>:3:24: $UZ" "PA3: used, h.p.n = 7; return h.p.n;"
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nfn f(h: *H): i64 { return h.p.n; }\nstruct H { p: *Box<Zork>; n; }\nfn main(): i64 { var h: H; h.n = 7; return h.n; }\nsyscall(60, main());\n' > "$T/pa4.cyr"
one_error pa4 "error:<source>:4:24: $UZ" "PA4: used in a fn above the struct"
printf 'include "lib/syscalls.cyr"\nstruct H { p: *Later<Zork>; n; }\nstruct Later<T> { v: T; n; }\nfn main(): i64 { var h: H; h.n = 7; return h.n; }\nsyscall(60, main());\n' > "$T/pa5.cyr"
one_error pa5 "$UZ" "PA5: *Later<Zork>, the generic Later declared below"
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nstruct H { p: *Box<Box<Zork>>; n; }\nfn main(): i64 { var h: H; h.n = 7; return h.n; }\nsyscall(60, main());\n' > "$T/pa6.cyr"
one_error pa6 "$UZ" "PA6: *Box<Box<Zork>>"
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nstruct W<T> { p: *Box<Zork>; n; }\nfn main(): i64 { var w: W<i32>; var w2: W<i8>; w.n = 7; return w.n; }\nsyscall(60, main());\n' > "$T/pa7.cyr"
one_error pa7 "$UZ" "PA7: W<T> { p: *Box<Zork>; } at two instances"
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nstruct H { p: *Box<E>; n; }\nenum E { A, B }\nfn main(): i64 { var h: H; h.n = 7; return h.p.n; }\nsyscall(60, main());\n' > "$T/pa8.cyr"
one_error pa8 "'E' is an enum, not a type argument" "PA8: *Box<E>, the enum E declared below (used)"
printf 'include "lib/syscalls.cyr"\nstruct Box<T> { v: T; n; }\nstruct Two<A, B> { a: A; b: B; }\nstruct H { p: *Box<Zork>; q: *Two<i64, Nope>; r: *Box<1 + 2>; n; }\nfn main(): i64 { var h: H; h.n = 7; return h.n; }\nsyscall(60, main());\n' > "$T/pa9.cyr"
build pa9
ne=$(grep -c '^error' "$T/pa9.err" || true)
if [ "$rc" -ne 0 ] && [ "$ne" -eq 3 ] && grep -qF "$UZ" "$T/pa9.err" && grep -qF "unknown type 'Nope' as a type argument" "$T/pa9.err" \
   && grep -qF "got number 1" "$T/pa9.err"; then ok "PA9: three bad pointer fields, one line each"
else bad "PA9: rc $rc, $ne error lines (want 3: Zork, Nope, number 1): $(grep '^error' "$T/pa9.err" | tr '\n' ' ')"; fi
cat > "$T/pa10.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
struct A { pb: *Box<B>; k; }
struct B { pa: *Box<A>; j; }
fn main(): i64 { var a: A; var b: B; var bb: Box<B>; var ba: Box<A>; bb.v.j = 5; ba.v.k = 2; a.pb = &bb; b.pa = &ba; bb.v.pa = &ba; return a.pb.v.j * 10 + b.pa.v.k + a.pb.v.pa.v.k * 100; }
syscall(60, main() - 200);
EOF
exits pa10 52 "PA10: A / B through *Box<B> / *Box<A>, B declared below (unchanged)"
cat > "$T/pa11.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
struct H { p: *Box<Later<Pt>>; n; }
struct Later<T> { v: T; n; }
struct Pt { x; y; }
fn main(): i64 { var b: Box<Later<Pt>>; b.v.n = 5; var h: H; h.p = &b; return h.p.v.n; }
syscall(60, main());
EOF
exits pa11 5 "PA11: *Box<Later<Pt>>, both declared below (unchanged)"

# HF — 6.7.15: a generic struct's `*T` field hops in its instance, on every leg this box can run.
skips=0
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"; A64="$T/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: HF aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> /dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"; CXCC="$T/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: HF PE legs (wine not installed)"; skips=$((skips + 1)); fi
LEGS="x86 x86:CYRIUS_IR=3"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"
[ "$WINE" = 1 ] && LEGS="$LEGS pe"
# run_leg <leg> <src> <out>: compile for <leg> and run; RC = the exit (-1: did not build)
run_leg() {
    RC=-1
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > /dev/null 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > /dev/null 2>&1 || RC=$? ;;
        cx)   timeout 300 "$T/cxvm" < "$3" > /dev/null 2>&1 || RC=$? ;;
        pe)   (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > /dev/null 2>&1) || RC=$? ;;
    esac
}
xr() {   # <id> <src> <want> <what>: the exit on every leg
    for leg in $LEGS; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$T/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$T/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}
# The filed repro, verbatim (the issue's text).
cat > "$T/hf1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Pb<T> { p: *T; n; }
fn go(): i64 { var q: Pt; q.x = 1; q.y = 9; var b: Pb<Pt>; b.p = &q; b.n = 1; return b.p.y; }
syscall(60, go());
EOF
xr HF1 "$T/hf1.cyr" 9 "the filed repro, b.p.y through Pb<Pt>"
cat > "$T/hf2.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Pb<T> { p: *T; n; }
fn go(): i64 { var q: Pt; q.x = 1; q.y = 9; var b: Pb<Pt>; b.p = &q; b.n = 1; b.p.y = 3; return q.y; }
syscall(60, go());
EOF
xr HF2 "$T/hf2.cyr" 3 "a store, b.p.y = 3"
cat > "$T/hf3.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
impl Pt { fn m(self): i64 { return self.x * 10 + self.y; } }
struct Pb<T> { p: *T; n; }
fn go(): i64 { var q: Pt; q.x = 7; q.y = 8; var b: Pb<Pt>; b.p = &q; b.n = 1; return b.p.m(); }
syscall(60, go());
EOF
xr HF3 "$T/hf3.cyr" 78 "a method, b.p.m()"
cat > "$T/hf4.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Pb<T> { p: *T; n; }
fn g<T>(b: Pb<T>): i64 { return b.p.y; }
fn go(): i64 { var q: Pt; q.x = 1; q.y = 9; var b: Pb<Pt>; b.p = &q; b.n = 1; return g<Pt>(b); }
syscall(60, go());
EOF
xr HF4 "$T/hf4.cyr" 9 "inside a generic, g<Pt>(b) reading b.p.y"
cat > "$T/hf5.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pb<T> { p: *T; n; }
fn go(): i64 { var a: i32[4]; var b: Pb<i32>; b.p = &a; b.n = 1; var e = b.p + 1; return e - b.p + 5; }
syscall(60, go());
EOF
xr HF5 "$T/hf5.cyr" 9 "Pb<i32>'s b.p + 1 steps 4 (unchanged)"

if [ "$fails" -ne 0 ]; then echo "FAIL: generic_struct_field — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: generic_struct_field — $skips HF leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: generic_struct_field — a field naming its own struct is refused once (S1-S4), #derive walks nested type arguments (D1) and refuses an inline instance by its layout backstop (D2), b: Box<i32> runs (C), a generic call declared : *T is a struct source (P, PF, PR, PB), a generic declared : *Box<T> compiles (PG), pass 1 leaves an unresolved : **Box<..> return's pin to pass 2 (PD), a pointer field's type arguments are checked at the field once (PA), and a generic struct's *T field hops in its instance on x86_64 / IR / aarch64 / cx / PE (HF)"
