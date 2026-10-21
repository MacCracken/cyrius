#!/bin/sh
# tests/gates/frontend/generic_tparam_count_refused.sh — 6.7.16
#
# A THIRD TYPE PARAMETER IS REFUSED AT THE DECLARATION, ONCE, BY NAME. A generic records two type parameters
# (`_capture_tparams` packs two names; `GSTP` / `GFTP`, the guide's two-slot model), and a third was consumed and
# bound nothing: `fn g3<A, B, C>` compiled and `g3(1, 2, s)` read `sizeof(C)` as 8 for a 24-byte struct (the
# filed program exited 108 where 124 was written), `struct Three<A, B, C>` laid C out as an i64, and every
# explicit three-argument use was a parse error ("expected '=', got ','"). The third parameter is now refused —
# "a third type parameter 'C': a generic takes at most two type parameters" (the user's D8, 2026-10-19) — in
# pass 1, in source order, never by an instance's re-emit; its uses say nothing more (the count refusal of D5
# is quiet for a generic refused here), and a bound on it is refused with it (the old "a bound on a third type
# parameter" line is gone). It needs no name resolved, so --syntax-only (cyrius lint) reports it too.
# CYRIUS_MONOMORPH=0 records no list at all and is unchanged (type_name_refused.sh tparams_mono0).
# Filed: docs/development/issues/2026-10-18-third-type-parameter-accepted-and-unrecorded.md
#
#   R   the filed programs, verbatim: g3.cyr refused at 2:13 alone (exit 108 before); `var t: Three<i8, i16, i32>`,
#       `sizeof(Three<i8, i16, i32>)` and `g3<i32, i16, i8>(1, 2, 3)` each the declaration's line alone (their
#       parse errors before)
#   S   `struct Three<A, B, C>` and every use spelling — bare, two, three and four arguments, sizeof: one line
#   B   a bounded third parameter, a fn's and a struct's: the parameter's line alone, no bound line
#   M   a generic method `fn m<A, B, C>`, called explicitly and inferred: one line
#   F   four parameters (`<A, B, C, D>`), a fn and a struct: one line each, at C
#   L   a struct declared further down, used by a `*Later<i64, i64, i64>` field above it: its line alone
#   G   a generic body forwarding `g3<T, T, T>`, two instances: one line
#   O   two refusals in source order (a fn's above a struct's)
#   X   --syntax-only reports it (rc 1)
#   T   (6.7.16, f16 FG2, the user's D92) a trait member's own third type parameter, at the member: trm.cyr / trm2.cyr
#       verbatim (they built), a default inherited / overridden / unreached / below its impl (one line each), lint,
#       member and impl both `<A, B, C>` (one line per declaration, source order), four / bounded / after a bounded
#       second, a fn's + a member's + a struct's in source order; T8 control: `<V: Show + Eq, U>` and `<U>` members
#   C   controls, unchanged: `<T: Show + Eq, U>`, an enum-erased `<T, E>` and a two-parameter struct build and
#       exit 36 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine)
#   A   R1 (and T1) refused with the same line by the aarch64, cx and PE compilers (T1: and the Mach-O env leg)
#
# MUTATION (2026-10-20):
#   M1  CYCC = the lane's previous compiler (e65308eb2, D5 without D8) -> RED 15: every R, S, B, M, F, L, G, O and
#       X row and A [pe] (each builds, or prints the count refusal "'Three' takes 2 type arguments, 3 given" / the
#       old bound line instead); C and A [a64] / [cx] green (those two cross compilers are built from the tree's src)
#   M2  a scratch copy of the tree without `_ta_x3`'s check in `_ta_xrefuse` (the uses not quieted) -> RED 9: R2-R4,
#       S1, M1, F1, F2, L1, G1 (the declaration's line and a count line at each use)
# MUTATION (2026-10-21, f16 FG2; a scratch copy of src/ with the one change, its cycc, CYCC= it):
#   M3  the lane before it (02adedff4) -> RED 10: T1 T2 T3b T3c T4-T7, A [pe] / A [macho] T1 (each built, T5 / T7 the
#       impl's or the struct's line alone; T3 / T3d green: an inherited default was PARSE_FN_DEF's already)
#   M4  the report made in pass 2 by the member's signature walk (`_tr_sig_check`, the triage's plan) instead of
#       `_tl_trait1`'s -> RED 2: T5 T7 (the member's line after pass 1's); `_tl_trait1` not walking at all -> M3's 10
#   M5  `_tp_nth_at` counting a bound's trait names as parameters -> RED 2: T6 (at `Nope`), T8 (`Eq` refused)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_tparam_count_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS CYRIUS_MONOMORPH
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
M="a generic takes at most two type parameters"

# lines <name> <expected lines, '|'-joined, each "L:C: text"> <what> [compiler-cmd]: refused with exactly these
# error lines, in this order.
lines() {
    rc=0
    if [ $# -ge 4 ]; then sh -c "$4" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    else "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; fi
    got=$( (grep '^error' "$D/$1.err" || true) | sed 's/^error:<source>://' | tr '\n' '|' | sed 's/|$//')   # no line: '' (bash -eo pipefail)
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$got" != "$2" ]; then bad "$3: got [$got], want [$2]"
    else ok "$3: $2"; fi
}

# ── R: the filed programs, verbatim ─────────────────────────────────────────────────────────────────────────
cat > "$D/g3.cyr" <<'EOF'
struct S { a; b; c; }
fn g3<A, B, C>(a: A, b: B, c: C): i64 { return sizeof(C); }
fn g2<A, B>(a: A, b: B): i64 { return sizeof(B); }
fn main(): i64 { var s = S { 1, 2, 3 }; return g3(1, 2, s) + 100 * g2(1, s) / 24; }
EOF
lines g3 "2:13: a third type parameter 'C': $M" "R1: g3.cyr"
cat > "$D/r2.cyr" <<'EOF'
struct Three<A, B, C> { a: A; b: B; c: C; }
fn main(): i64 { var t: Three<i8, i16, i32>; return 0; }
EOF
lines r2 "1:20: a third type parameter 'C': $M" "R2: var t: Three<i8, i16, i32>"
cat > "$D/r3.cyr" <<'EOF'
struct Three<A, B, C> { a: A; b: B; c: C; }
fn main(): i64 { return sizeof(Three<i8, i16, i32>); }
EOF
lines r3 "1:20: a third type parameter 'C': $M" "R3: sizeof(Three<i8, i16, i32>)"
cat > "$D/r4.cyr" <<'EOF'
fn g3<A, B, C>(a: A, b: B, c: C): i64 { return sizeof(C); }
fn main(): i64 { return g3<i32, i16, i8>(1, 2, 3); }
EOF
lines r4 "1:13: a third type parameter 'C': $M" "R4: g3<i32, i16, i8>(1, 2, 3)"

# ── S: a struct and every use spelling ──────────────────────────────────────────────────────────────────────
cat > "$D/s1.cyr" <<'EOF'
struct Three<A, B, C> { a: A; b: B; c: C; }
fn f(x: Three<i8, i16, i32>, y: *Three<i8, i16, i32, i64>): Three<i8, i16> { var r: Three<i8, i16>; return r; }
fn main(): i64 { var t: Three<i8, i16, i32>; var u: Three; var w: Three<i8, i16>; return sizeof(Three<i8, i16, i32>) + sizeof(Three<i64, i64, i64, i64>); }
EOF
lines s1 "1:20: a third type parameter 'C': $M" "S1: Three, its parameters, return and every local spelling"

# ── B: a bounded third parameter ────────────────────────────────────────────────────────────────────────────
printf 'trait Show { fn show(self): i64; }\nfn g<A, B, C: Show>(a: A, b: B, c: C): i64 { return 1; }\nfn main(): i64 { return 3; }\n' > "$D/b1.cyr"
lines b1 "2:12: a third type parameter 'C': $M" "B1: fn g<A, B, C: Show>"
printf 'trait Show { fn show(self): i64; }\nstruct Three<A, B, C: Show + Nope> { a: A; b: B; c: C; }\nfn main(): i64 { return 3; }\n' > "$D/b2.cyr"
lines b2 "2:20: a third type parameter 'C': $M" "B2: struct Three<A, B, C: Show + Nope> (no unknown-trait line)"

# ── M: a generic method ─────────────────────────────────────────────────────────────────────────────────────
printf 'struct P { a; }\nimpl P { fn m<A, B, C>(self, x: A): i64 { return 1; } }\nfn main(): i64 { var p: P; p.a = 1; return p.m<i8, i16, i32>(4) + p.m(5); }\n' > "$D/m1.cyr"
lines m1 "2:21: a third type parameter 'C': $M" "M1: impl P { fn m<A, B, C> }, explicit and inferred calls"

# ── F: four parameters ──────────────────────────────────────────────────────────────────────────────────────
printf 'fn g4<A, B, C, D>(a: A): i64 { return 1; }\nfn main(): i64 { return g4<i8, i8, i8, i8>(1) + g4(2); }\n' > "$D/f1.cyr"
lines f1 "1:13: a third type parameter 'C': $M" "F1: fn g4<A, B, C, D>"
printf 'struct F<A, B, C, D> { a: A; }\nfn main(): i64 { var f: F<i8, i8, i8, i8>; return sizeof(F<i8, i8>); }\n' > "$D/f2.cyr"
lines f2 "1:16: a third type parameter 'C': $M" "F2: struct F<A, B, C, D>"

# ── L: a struct declared further down ───────────────────────────────────────────────────────────────────────
printf 'struct A { p: *Later<i64, i64, i64>; n; }\nstruct Later<X, Y, Z> { v: X; n; }\nfn main(): i64 { var a: A; a.n = 3; return a.n; }\n' > "$D/l1.cyr"
lines l1 "2:20: a third type parameter 'Z': $M" "L1: *Later<i64, i64, i64> above struct Later<X, Y, Z>"

# ── G: a generic body, two instances ────────────────────────────────────────────────────────────────────────
printf 'fn g3<A, B, C>(a: A, b: B, c: C): i64 { return sizeof(C); }\nfn w<T>(x: T): i64 { return g3<T, T, T>(x, x, x); }\nfn main(): i64 { return w(1) + w<i32>(2); }\n' > "$D/g1.cyr"
lines g1 "1:13: a third type parameter 'C': $M" "G1: g3<T, T, T> forwarded from two instances"

# ── O: source order ─────────────────────────────────────────────────────────────────────────────────────────
printf 'fn g4<A, B, C>(a: A): i64 { return 1; }\nstruct F<A, B, C> { a: A; }\nfn main(): i64 { return 2; }\n' > "$D/o1.cyr"
lines o1 "1:13: a third type parameter 'C': $M|2:16: a third type parameter 'C': $M" "O1: a fn's line above a struct's, in source order"

# ── X: --syntax-only ────────────────────────────────────────────────────────────────────────────────────────
lines g3 "2:13: a third type parameter 'C': $M" "X1: --syntax-only reports it" "$CC --syntax-only"

# ── T: a trait member's own third type parameter (6.7.16, f16 FG2, the user's D92) ─────────────────────────────
# The trait reader stepped a member's `<..>` uncounted, so a bodiless member's third compiled, and so did an impl
# declaring two for it; a default body was refused (PARSE_FN_DEF reads it). Now D8's line at the member's name, in
# pass 1 in source order (`_tl_trait1` -> `_tr_tp3_walk`), once per token.
# Filed: docs/development/issues/2026-10-20-trait-member-third-type-parameter-accepted.md
cat > "$D/trm.cyr" <<'EOF'
trait T { fn g<A, B, C>(self, a: A, b: B, c: C): i64; }
struct P { x; }
fn main(): i64 { return 3; }
EOF
lines trm "1:22: a third type parameter 'C': $M" "T1: trm.cyr verbatim (it built: exit 3)"
cat > "$D/trm2.cyr" <<'EOF'
trait T { fn g<A, B, C>(self, a: A, b: B, c: C): i64; }
struct P { x; }
impl T for P { fn g<A, B>(self, a: A, b: B, c: i64): i64 { return 4; } }
fn main(): i64 { var p = P { 1 }; return p.g(1, 2, 3); }
EOF
lines trm2 "1:22: a third type parameter 'C': $M" "T2: trm2.cyr verbatim — an impl declaring <A, B> for it (it built: exit 4)"
cat > "$D/trm3.cyr" <<'EOF'
trait T { fn g<A, B, C>(self, c: C): i64 { return sizeof(C); } }
struct S3 { a; b; c; }
struct P { x; }
impl T for P { }
fn main(): i64 { var p = P { 1 }; var s = S3 { 1, 2, 3 }; return p.g(s); }
EOF
lines trm3 "1:22: a third type parameter 'C': $M" "T3: the filing's default body, inherited — still one line"
printf 'trait T { fn g<A, B, C>(self, c: C): i64 { return sizeof(C); } }\nstruct P { x; }\nimpl T for P { fn g<A, B>(self, c: i64): i64 { return 5; } }\nfn main(): i64 { var p = P { 1 }; return p.g(2); }\n' > "$D/t3b.cyr"
lines t3b "1:22: a third type parameter 'C': $M" "T3b: a default every impl overrides — one line"
printf 'trait T { fn g<A, B, C>(self, c: C): i64 { return sizeof(C); } }\nstruct P { x; }\nfn main(): i64 { return 3; }\n' > "$D/t3c.cyr"
lines t3c "1:22: a third type parameter 'C': $M" "T3c: a default no impl reaches — one line"
printf 'struct P { x; }\nimpl T for P { }\ntrait T { fn g<A, B, C>(self, c: C): i64 { return 1; } }\nfn main(): i64 { var p = P { 1 }; return p.g(3); }\n' > "$D/t3d.cyr"
lines t3d "3:22: a third type parameter 'C': $M" "T3d: the trait below the impl that inherits its default — one line"
lines trm "1:22: a third type parameter 'C': $M" "T4: --syntax-only reports it" "$CC --syntax-only"
printf 'trait T { fn g<A, B, C>(self, a: A, b: B, c: C): i64; }\nstruct P { x; }\nimpl T for P { fn g<A, B, C>(self, a: A, b: B, c: C): i64 { return 4; } }\nfn main(): i64 { var p = P { 1 }; return p.g(1, 2, 3); }\n' > "$D/t5.cyr"
lines t5 "1:22: a third type parameter 'C': $M|3:27: a third type parameter 'C': $M" "T5: member and impl both <A, B, C> — one line per declaration, in source order"
printf 'trait Show { fn show(self): i64; }\ntrait T { fn g<A, B, C, D>(self, a: A): i64; fn h<X, Y, Z: Show>(self): i64; fn i<U, V: Nope, W>(self): i64; fn k<U>(self, cb: *fn(i64): i64, u: U): i64; }\nfn main(): i64 { return 3; }\n' > "$D/t6.cyr"
lines t6 "2:22: a third type parameter 'C': $M|2:57: a third type parameter 'Z': $M|2:95: a third type parameter 'W': $M" \
    "T6: four parameters, a bounded third, a third after a bounded second — one line per member, at its third"
printf 'fn g4<A, B, C>(a: A): i64 { return 1; }\ntrait T { fn g<A, B, C>(self): i64; }\nstruct F<A, B, C> { a: A; }\nfn main(): i64 { return 2; }\n' > "$D/t7.cyr"
lines t7 "1:13: a third type parameter 'C': $M|2:22: a third type parameter 'C': $M|3:16: a third type parameter 'C': $M" \
    "T7: a fn's, a member's and a struct's, in source order"
cat > "$D/t8.cyr" <<'EOF'
trait Show { fn show(self): i64; }
trait Eq { fn eq(self, o): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.x; } }
impl Eq for Pt { fn eq(self, o): i64 { return 1; } }
trait T { fn g<V: Show + Eq, U>(self, v: V, u: U): i64; fn h<U>(self, cb: *fn(i64): i64, u: U): U; }
struct P { x; }
impl T for P { fn g<V: Show + Eq, U>(self, v: V, u: U): i64 { return v.show() + sizeof(U); } fn h<U>(self, cb: *fn(i64): i64, u: U): U { return u; } }
fn main(): i64 { var p = P { 1 }; var q = Pt { 3, 4 }; return P_g(p, q, 5) + p.h(0, 25); }
EOF
rc=0; "$CC" < "$D/t8.cyr" > "$D/t8.bin" 2> "$D/t8.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "T8: control — <V: Show + Eq, U> and <U> members: rc $rc: $(grep '^error' "$D/t8.err" | head -1)"
else chmod +x "$D/t8.bin"; got=0; "$D/t8.bin" || got=$?
    if [ "$got" -eq 36 ]; then ok "T8: control — <V: Show + Eq, U> and <U> members build and run: exit 36"; else bad "T8: exit $got, want 36"; fi
fi

# ── C: controls, every leg ──────────────────────────────────────────────────────────────────────────────────
cat > "$D/c.cyr" <<'EOF'
trait Show { fn show(self): i64; }
trait Eq { fn eq(self, o): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.x; } }
impl Eq for Pt { fn eq(self, o): i64 { return 1; } }
enum E { A; B; }
fn h<T: Show + Eq, U>(a: T, b: U): i64 { return a.show() + sizeof(U); }
fn k<T, E>(a: T, b: E): i64 { return sizeof(T); }
struct Two<A, B> { a: A; b: B; }
fn main(): i64 { var p = Pt { 3, 4 }; var t: Two<i8, Pt>; return h(p, 5) + k(1, 2) + sizeof(Two<i8, Pt>); }
EOF
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
crun() {   # <leg>: build c.cyr for <leg> and run it; RC = its exit (-1 = no build)
    RC=-1
    case "$1" in
        x86) "$CC" < "$D/c.cyr" > "$D/c_$1" 2> /dev/null || return 0 ;;
        a64) "$A64" < "$D/c.cyr" > "$D/c_$1" 2> /dev/null || return 0 ;;
        cx)  "$CXCC" < "$D/c.cyr" > "$D/c_$1" 2> /dev/null || return 0 ;;
        pe)  CYRIUS_TARGET_WIN=1 "$CC" < "$D/c.cyr" > "$D/c_$1.exe" 2> /dev/null || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86) chmod +x "$D/c_$1"; timeout 60 "$D/c_$1" > /dev/null 2>&1 || RC=$? ;;
        a64) chmod +x "$D/c_$1"; timeout 300 qemu-aarch64 "$D/c_$1" > /dev/null 2>&1 || RC=$? ;;
        cx)  timeout 300 "$D/cxvm" < "$D/c_$1" > /dev/null 2>&1 || RC=$? ;;
        pe)  (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$D/c_$1.exe" > /dev/null 2>&1) || RC=$? ;;
    esac
}
LEGS="x86"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"
[ "$WINE" = 1 ] && LEGS="$LEGS pe"
for L in $LEGS; do
    crun "$L"
    if [ "$RC" -eq 36 ]; then ok "C [$L]: the controls exit 36"; else bad "C [$L]: exit $RC, want 36"; fi
done

# ── A: the refusal from every cross compiler ────────────────────────────────────────────────────────────────
[ -n "$A64" ] && lines g3 "2:13: a third type parameter 'C': $M" "A [a64]: R1" "$A64"
[ -n "$CXCC" ] && lines g3 "2:13: a third type parameter 'C': $M" "A [cx]: R1" "$CXCC"
lines g3 "2:13: a third type parameter 'C': $M" "A [pe]: R1" "CYRIUS_TARGET_WIN=1 $CC"
[ -n "$A64" ] && lines trm "1:22: a third type parameter 'C': $M" "A [a64]: T1" "$A64"
[ -n "$CXCC" ] && lines trm "1:22: a third type parameter 'C': $M" "A [cx]: T1" "$CXCC"
lines trm "1:22: a third type parameter 'C': $M" "A [pe]: T1" "CYRIUS_TARGET_WIN=1 $CC"
lines trm "1:22: a third type parameter 'C': $M" "A [macho]: T1" "CYRIUS_MACHO=1 $CC"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — a third type parameter is refused at its declaration, once, by name (the user's D8): the filed programs (R), a struct and every use (S), bounded (B), a method (M), four parameters (F), a struct declared below (L), a generic body (G), source order (O), --syntax-only (X), a trait member's own (T, the user's D92), the controls on x86_64 / aarch64 / cx / PE (C) and every cross compiler (A)"
exit 0
