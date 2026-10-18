#!/bin/sh
# tests/gates/frontend/trait_bounds_checked.sh — 6.7.1 (C3)
#
# TRAIT BOUNDS ON TYPE PARAMETERS ARE CHECKED: `fn f<T: Show + Eq>`, `struct Box<T: Show>`.
#
# Before 6.7.1 `<T: Show>` minted a SECOND type parameter named `Show`, so `f(p)` with a struct was
# refused as "a struct beside a second type argument" and nothing was checked. The user's decisions
# (2026-10-07): a bound is a CONTRACT — on a bounded T, `v.m()` must be a method of a bound's trait,
# checked at the generic's definition; `T: A + B` requires every impl; a bound is satisfied by
# `impl Trait for X` whatever X is. The runtime half is tests/tcyr/crossos/trait_bounds.tcyr.
#
#   D  the definition: an undeclared trait in a bound; a method no bound declares (the contract),
#      also on a `var q: T` local; a method two bounds declare (ambiguous); a bound with type
#      arguments; a bound on a third type parameter; `<T: >` — each refused once, by name
#   I  an instantiation whose type has no impl: inferred, explicit, the i64 base reached by a scalar
#      call (whose body is then the dead stub), `&g`, a tail call, a second bounded parameter, and
#      an unbounded generic forwarding its T to a bounded one — refused once, naming the trait and
#      the `impl` it needs
#   S  a bounded generic STRUCT: `Box<R>`, a written `Box<i64>` and a bare `Box` (its i64 base) with
#      no impl are refused; `struct W<T> { b: Box<T>; }` is fine until W's i64 base is used; a
#      generic fn instantiating `Box<T>` has no i64 instance (refused at `mk(5)`, not at `mk`)
#   B  (6.7.14) more than 64 bounded receivers in one generic: the receivers' table (`_bnr_tab`) held 64
#      and dropped the rest, so a later `z.show()` was no bounded site and the i64 base (live: `impl Show
#      for i64`) refused it — "no struct type in scope for 'z'". B1 a parameter, 65 `var cN: T = v;`, then
#      `z.show()`: exit 5; B1b 130 (two growths). issues/archived/2026-10-14-generic-carrier-table-caps-at-64-silently.md
#   F  (6.7.14) A GENERIC FORWARDING ITS T TO A BOUNDED GENERIC: the stub scan counted the forward a struct use
#      whenever the callee's base was bad for its bound, so `fn o<T>(x: T) { return gb(x); }` with only `impl Show
#      for f64` had the stub base, which has no scalar instance — `o(h)` / `o<f64>(h)` were refused "uses its type
#      parameter as a struct" with a note naming i64. The forward now makes o's base bad at i64 alone
#      (`_bnd_base_bad` -> `_bbs_fwd_bad`): o(h) calls o$f64, o(3) is refused naming the forward and the impl i64
#      lacks. F0 the filed repro verbatim (5); F1 o<f64>(h); F2 o(3) refused once, the forward and the note, not the
#      stub text; F3 both impls (56); F4 / F4b two levels o2 -> o -> gb; F5 an explicit gb<T>(x) forward with a
#      struct too; F6 / F6b a generic method forward; F7 / F7b a forward to a generic instantiating a bounded
#      struct; F8 / F8b / F8c / F8d mutual recursion (a cycle ends); F9 &o; F10 a tail call; F11 the definition alone;
#      F12 a chain of 64 forwards (the judgement's reach: `_bbf_dep`'s cap, filed for a deeper chain).
#      I7 (an unbounded generic forwarding to a bounded one, u(5)) now names the forward, not the stub text.
#      Filed: docs/development/issues/archived/2026-10-14-generic-forwarding-to-bounded-generic-refused-at-f64.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MF1 `_bnd_base_bad` without its forwarding arm (`_bbs_fwd_bad` answering 0) -> RED I7 and every F row but F3
#      (the forwarder's i64 base is emitted and refused at its definition naming gb, called or not — F11 too);
#      MF2 the stub scan's mode 1 counting a bound-bad callee again (6.7.1's test; = the compiler before) -> RED I7
#      F0 F1 F2 F4 F4b F5 F6 F6b F7 F7b F8b F8c F9 F10 (refused, or with the struct-stub text and no note);
#      MF3 `_bbf_push` never deduping (no visited list) -> RED F8d (the compile hangs: every level of the three-way
#      cycle branches twice, to the depth cap);
#      MF4 (2026-10-17) the depth cap at 32 (`_bbf_dep > 32`) -> RED F12 (o33's base refused at its definition)
#   BC (6.7.14) A BOUNDED CALL ON A STRUCT CARRIER'S T FIELD: `b.v.show()` with `b: Box<T>` (`v: T`), `T: Show`, was
#      no bounded site (only a name declared `T` / `*T` was), so 6.7.11's carrier rule counted it a struct use: the
#      base was the stub, and `gs(bi)` with `bi: Box<i64>` was refused although `impl Show for i64` exists. The call
#      is now a bounded site (`_bnd_fsite`), the scan reads it as a trait use (`_gs_bfield`), and at a scalar T the
#      bound's impl takes the field's value as `self` (`_load_bs_field`; a method on a scalar field leaf had no path
#      at all). BC0 the filed repro verbatim (65); BC1 gs(b) alone; BC2 a `*Box<T>` carrier; BC3 no i64 impl: gs(bi)
#      refused naming `impl Show for i64`; BC4 f64 / i32 instances; BC5 a `var c: Box<T>` carrier, a `var r =`
#      receive and a statement; BC6 gs<i64>(bi); BC7 control — a method no bound declares keeps its reading; BC8 a
#      non-inlinable caller; BC9 the documented workaround unchanged; BC10 the definition alone (no i64 impl).
#      Filed: docs/development/issues/archived/2026-10-14-bounded-method-call-on-carrier-field-is-a-struct-use.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MBC1 `_bnd_sites` without the `_bnd_fsite` call (no site) -> RED BC0 BC2 BC4-BC6 BC8 (the stub refusal);
#      MBC2 `_gs_bfield` answering 0 (the site recorded, the scan still a struct use) -> RED BC0 BC2 BC4-BC6 BC8;
#      MBC3 `_fld_meth_inline` without its scalar arm (no `_load_bs_field`) -> RED BC0 BC2 BC4-BC6 BC8 ("expected
#      ';', got '.'" at the definition, every BC row that builds the i64 base)
#   N  (6.7.14) a bound refusal the panic latch swallows prints nothing: after a stub generic's refusal in
#      the same statement (`gs(5) + gb(3)`), `gb(3)`'s error was swallowed but its note was printed alone —
#      "the bound on type parameter 'T' needs `impl Show for i64`" under gs's error. N1: one error line, no
#      note. Mutant (the `_panic` test in `_bnd_check` removed, a one-edit scratch copy of the tree, its 2-stage
#      cycc, this gate run from it) -> RED N1 (the orphan note).
#   C  ANTI-VACUOUS: the same shapes with the impl present build and run; an unbounded `T` keeps
#      per-instance method resolution; a program with no bound is untouched
#
# Mutations (scratch trees, each RED here — run 2026-10-07): `_capture_tparams` not reading a bound
#   (every identifier a type parameter again) -> D1 builds, D2-D4 refused only by the cascade;
#   `_bnd_check_fn` answering 0 -> I1/I2 refused only as undefined fns, I3 BUILDS; `_bnd_site` not
#   refusing -> D2/D3 refused only by the cascade; `_bnd_base_bad` answering 0 -> I3-I5 refused
#   with the struct-stub message instead of the bound's; `_bnd_sbase` a no-op -> S2-S4 BUILD; no
#   quiet mode in `_sfield_gen` -> S4 BUILDS (W's base never learns it holds a Box<i64>).
# 6.7.11 I8: `_gen_call_inst` resolving the inner call with the cursor left on the outer one -> RED
#   I8's column (the refusal named `gx`'s column, 12 for 15 in the filed shape).
# 6.7.14 B1 / B1b: `_bnr_add` dropping the 65th bounded receiver again (a one-edit scratch copy of the
#   tree, its 2-stage mutant cycc, this gate run from it) -> RED B1 / B1b ("generic 'f' has no i64 (or
#   other scalar) instance": `z.show()` was no bounded site, so the scan counted it a struct use; with the
#   T-typed names' table capped too, as at the slot open, it is "no struct type in scope for 'z'").
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: trait_bounds_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: trait_bounds_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what>
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
H='struct Pt { x; y; }
struct R { r; }
trait Show { fn show(self): i64; }
trait Eq { fn eq(self, o: Pt): i64; }
trait Size { fn size(self): i64; }
trait Other { fn size(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x + self.y; } }
impl Size for Pt { fn size(self): i64 { return 2; } }
impl Other for Pt { fn size(self): i64 { return 3; } }'
P='var p: Pt; p.x = 40; p.y = 2;'
mk() {   # <name> <decls> <main body>
    printf '%s\n%s\nfn main(): i64 { %s %s }\nsyscall(60, main());\n' "$H" "$2" "$P" "$3" > "$T/$1.cyr"
}

# D — the definition
mk d1 'fn f<T: Shw>(v: T): i64 { return 1; }' 'return f(p);'
refused d1 "unknown trait 'Shw' in the bound on type parameter 'T'" "D1: an undeclared trait in a bound"
mk d2 'fn f<T: Show>(v: T): i64 { return v.size(); }' 'return f(p);'
refused d2 "method 'size' is not in the bound on type parameter 'T'" "D2: the contract — v.size() under T: Show"
mk d3 'fn f<T: Show>(v: T): i64 { var q: T = v; return q.nope(); }' 'return f(p);'
refused d3 "method 'nope' is not in the bound on type parameter 'T'" "D3: the contract on a var q: T local"
mk d4 'fn f<T: Size + Other>(v: T): i64 { return v.size(); }' 'return f(p);'
refused d4 "ambiguous method 'size': more than one trait in this type parameter's bound declares it" "D4: two bounds declare the method"
mk d5 'fn f<T: Show<i64>>(v: T): i64 { return 1; }' 'return f(p);'
refused d5 "a trait in a bound takes no type arguments: 'Show'" "D5: a bound with type arguments"
mk d6 'fn f<A, B, C: Show>(a: A): i64 { return 1; }' 'return f(p);'
refused d6 "a bound on a third type parameter" "D6: a bound on a third type parameter"
mk d7 'fn f<T: >(v: T): i64 { return 1; }' 'return f(p);'
refused d7 "expected a trait name in a type parameter's bound" "D7: <T: >"

# I — instantiations
B1='fn f<T: Show>(v: T): i64 { var t = 0; var i = 0; while (i < 1) { t = t + v.show(); i = i + 1; } return t; }'
mk i1 "$B1" 'var r: R; r.r = 1; return f(r);'
refused i1 "generic 'f': its type argument does not implement trait 'Show'" "I1: f(r), R has no impl Show (inferred)"
grep -qF "needs \`impl Show for R\`" "$T/i1.err" && ok "I1: the note names the impl it needs" || bad "I1: no note naming \`impl Show for R\`"
mk i2 "$B1" 'var r: R; r.r = 1; return f<R>(r);'
refused i2 "generic 'f': its type argument does not implement trait 'Show'" "I2: f<R>(r), explicit"
mk i3 "$B1" 'return f(5);'
refused i3 "generic 'f': its type argument does not implement trait 'Show'" "I3: f(5), the i64 base"
grep -qF "needs \`impl Show for i64\`" "$T/i3.err" && ok "I3: the note names \`impl Show for i64\`" || bad "I3: no note naming \`impl Show for i64\`"
printf 'include "lib/fnptr.cyr"\n%s\n%s\nfn main(): i64 { var g = &f; return fncall1(g, 5); }\nsyscall(60, main());\n' "$H" "$B1" > "$T/i4.cyr"
refused i4 "generic 'f': its type argument does not implement trait 'Show'" "I4: &f (its address is the i64 base)"
mk i5 "$B1
fn h(n): i64 { return f(n); }" 'return h(5);'
refused i5 "generic 'f': its type argument does not implement trait 'Show'" "I5: return f(n); (a tail call)"
mk i6 'fn g<A: Show, B: Size>(a: A, b: B): i64 { return a.show() + b.size(); }' 'var r: R; r.r = 1; return g(p, r);'
refused i6 "generic 'g': its type argument does not implement trait 'Size'" "I6: the second bounded parameter"
mk i7 "$B1
fn u<T>(v: T): i64 { return f(v); }" 'return u(5);'
refused i7 "generic 'u' has no i64 instance: it forwards its type parameter to 'f'" "I7: an unbounded generic forwarding T to a bounded one, u(5) (6.7.14: names the forward)"
grep -qF "needs \`impl Show for i64\`" "$T/i7.err" && ok "I7: the note names \`impl Show for i64\`" || bad "I7: no note naming \`impl Show for i64\`"
# 6.7.11: a bounded generic CALLED AS ANOTHER GENERIC'S ARGUMENT is resolved while the outer call infers T
# (a generic call's own result binds T, `_gen_call_inst`) — its refusal still names the inner call's column.
mk i8 'struct Box<T> { v: T; n; }
fn mkb<T: Show>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n; }
fn g<T>(p: T): i64 { return p.n; }' 'var r: R; r.r = 1; return gx(mkb(r)) + g(mkb(r));'
refused i8 "generic 'mkb': its type argument does not implement trait 'Show'" "I8: gx(mkb(r)) + g(mkb(r)), R has no impl Show"
c8=$(grep '^fn main' "$T/i8.cyr" | awk '{ print index($0, "gx(mkb") + 3 }')
if grep -q ":$c8: generic 'mkb'" "$T/i8.err"; then ok "I8: ... reported at the inner call (column $c8)"
else bad "I8: not reported at the inner call's column $c8: $(grep '^error' "$T/i8.err" | head -1)"; fi

# S — bounded generic structs
SB='struct Box<T: Show> { v: T; n; }'
mk s1 "$SB" 'var b: Box<R>; return 1;'
refused s1 "generic 'Box': its type argument does not implement trait 'Show'" "S1: Box<R>"
mk s2 "$SB" 'var b: Box<i64>; return 1;'
refused s2 "generic 'Box': its type argument does not implement trait 'Show'" "S2: a written Box<i64>"
mk s3 "$SB
fn bs(b: Box): i64 { return b.n; }" 'return 1;'
refused s3 "generic 'Box': its type argument does not implement trait 'Show'" "S3: a bare Box (its i64 base)"
mk s4 "$SB
struct W<T> { b: Box<T>; m; }" 'var w: W<Pt>; w.b.v = p; w.m = 1; var u: W; return 1;'
refused s4 "generic struct 'W' has no i64 instance" "S4: W<Pt> is fine; the bare W's Box<i64> is not"
mk s5 "$SB
fn mk<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 1; return b; }" 'var a: Box<Pt> = mk(p); return mk(5).n;'
refused s5 "generic 'mk' has no i64 instance" "S5: mk(p) is fine; mk(5) would need Box<i64>"

# B — more than 64 bounded receivers (6.7.14). `brgen <name> <n>`: f's parameter v and <n> locals.
brgen() {
    _bd='impl Show for i64 { fn show(self): i64 { return self + 1; } }
fn f<T: Show>(v: T): i64 {'
    k=1; while [ "$k" -le "$2" ]; do _bd="$_bd
    var c$k: T = v;"; k=$((k + 1)); done
    mk "$1" "$_bd
    var z: T = v;
    return z.show();
}" 'return f(p) + f(2) - 40;'
}
brgen b1 65
exits b1 5 "B1: 66 bounded receivers (v + 65 locals), then z.show() — on Pt (42) and on i64 (3)"
brgen b1b 130
exits b1b 5 "B1b: 131 bounded receivers (the table grows twice)"

# F — a generic forwarding its T to a bounded generic (6.7.14)
cat > "$T/f0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn o<T>(x: T): i64 { return gb(x); }
fn main(): i64 { var h: f64 = 1.5; return o(h); }
syscall(60, main());
EOF
exits f0 5 "F0: the filed repro, verbatim — o(h) forwards an f64 to gb, which has only impl Show for f64"
FH='struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
impl Show for Pt { fn show(self): i64 { return self.y; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn o<T>(x: T): i64 { return gb(x); }'
fmk() {   # <name> <decls> <main body>
    printf 'include "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\n%s\n%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$FH" "$2" "$3" > "$T/$1.cyr"
}
fwdref() {   # <name> <generic> <callee> <root> <what>: refused once, naming the forward and the impl i64 lacks
    refused "$1" "generic '$2' has no i64 instance: it forwards its type parameter to '$3'" "$5"
    if grep -q "uses its type parameter as a struct" "$T/$1.err"; then bad "$5: ... with the struct-stub text"; fi
    if [ "$(grep -c '^  note:' "$T/$1.err")" -ne 1 ]; then bad "$5: $(grep -c '^  note:' "$T/$1.err") note lines (want 1)"
    elif ! grep -qF "$4" "$T/$1.err"; then bad "$5: the note does not say: $4"
    else ok "$5: one note: $4"; fi
}
fmk f1 '' 'var h: f64 = 1.5; return o<f64>(h);'
exits f1 5 "F1: o<f64>(h), explicit"
fmk f2 '' 'return o(3);'
fwdref f2 o gb "the bound on type parameter 'T' of 'gb' needs \`impl Show for i64\`" "F2: o(3), only the f64 impl"
fmk f3 'impl Show for i64 { fn show(self): i64 { return 6; } }' 'var h: f64 = 1.5; return o(h) * 10 + o(3);'
exits f3 56 "F3: with impl Show for i64 too, o(h) * 10 + o(3)"
fmk f4 'fn o2<T>(x: T): i64 { return o(x); }' 'var h: f64 = 1.5; var p: Pt; p.x = 1; p.y = 4; return o2(h) * 10 + o2(p);'
exits f4 54 "F4: two levels, o2(h) -> o -> gb (5) and o2(p) (4)"
fmk f4b 'fn o2<T>(x: T): i64 { return o(x); }' 'return o2(3);'
fwdref f4b o2 o "the bound on type parameter 'T' of 'gb' needs \`impl Show for i64\`" "F4b: o2(3), two levels — the note names the chain's end"
fmk f5 'fn ox<T>(x: T): i64 { return gb<T>(x); }' 'var h: f64 = 1.5; var p: Pt; p.x = 1; p.y = 4; return ox(h) + ox(p) * 10;'
exits f5 45 "F5: an explicit forward gb<T>(x), f64 and a struct"
FM='struct P { a; }
impl P { fn gbm<T: Show>(self, x: T): i64 { return self.a + x.show(); } }
fn om<T>(q: P, x: T): i64 { return q.gbm(x); }'
fmk f6 "$FM" 'var q: P = P { 10 }; var h: f64 = 1.5; return om(q, h);'
exits f6 15 "F6: a forward to a bounded generic METHOD, q.gbm(x)"
fmk f6b "$FM" 'var q: P = P { 10 }; return om(q, 3);'
fwdref f6b om P_gbm "the bound on type parameter 'T' of 'P_gbm' needs \`impl Show for i64\`" "F6b: om(q, 3)"
FS='struct Box<T: Show> { v: T; n; }
fn mkn<T>(x: T): i64 { var b: Box<T>; b.v = x; b.n = 3; return b.n; }
fn os<T>(x: T): i64 { return mkn(x); }'
fmk f7 "$FS" 'var h: f64 = 1.5; return os(h);'
exits f7 3 "F7: a forward to a generic instantiating a bounded struct Box<T: Show>"
fmk f7b "$FS" 'return os(3);'
fwdref f7b os mkn "'mkn' instantiates the bounded generic struct 'Box' with its type parameter, and i64 does not satisfy its bound" "F7b: os(3)"
FC='fn pa<T>(x: T, n): i64 { if (n == 0) { return gb(x); } return pb(x, n - 1) + 1; }
fn pb<T>(x: T, n): i64 { if (n == 0) { return 2; } return pa(x, n - 1) + 2; }'
fmk f8 'fn qa<T>(x: T, n): i64 { if (n == 0) { return 1; } return qb(x, n - 1) + 1; }
fn qb<T>(x: T, n): i64 { if (n == 0) { return 2; } return qa(x, n - 1) + 2; }' 'return qa(3, 3);'
exits f8 6 "F8: control — two generics forwarding to each other, no bound reached: qa(3, 3) runs"
fmk f8b "$FC" 'var h: f64 = 1.5; return pa(h, 3) * 10 + pb(h, 3);'
exits f8b 70 "F8b: the cycle reaches gb: pa(h, 3) / pb(h, 3) at f64"
fmk f8c "$FC" 'return pb(3, 3);'
fwdref f8c pb pa "the bound on type parameter 'T' of 'gb' needs \`impl Show for i64\`" "F8c: pb(3, 3) through the cycle"
# F8d: three generics forwarding to each other two ways — each is scanned once per judgement (`_bbf_vis`);
# without the visited list the walk branches at every level (2^64 scans to its depth cap): a hung compile.
fmk f8d 'fn ra<T>(x: T, n): i64 { if (n == 0) { return 1; } return rb(x, n - 1) + rc(x, n - 1); }
fn rb<T>(x: T, n): i64 { if (n == 0) { return 2; } return ra(x, n - 1) + rc(x, n - 1); }
fn rc<T>(x: T, n): i64 { if (n == 0) { return 3; } return ra(x, n - 1) + rb(x, n - 1); }' 'return ra(3, 2);'
rc=0; timeout 60 "$CC" < "$T/f8d.cyr" > "$T/f8d.bin" 2> "$T/f8d.err" || rc=$?
if [ "$rc" -eq 124 ]; then bad "F8d: a three-way forwarding cycle: the compile did not finish in 60 s"
elif [ "$rc" -ne 0 ]; then bad "F8d: a three-way forwarding cycle: rc $rc: $(grep '^error' "$T/f8d.err" | head -1)"
else chmod +x "$T/f8d.bin"; got=0; "$T/f8d.bin" || got=$?
    if [ "$got" -eq 7 ]; then ok "F8d: a three-way forwarding cycle compiles and runs: exit 7"; else bad "F8d: exit $got, want 7"; fi
fi
fmk f9 '' 'var g = &o; return fncall1(g, 3);'
fwdref f9 o gb "needs \`impl Show for i64\`" "F9: &o"
fmk f10 'fn h(n): i64 { return o(n); }' 'return h(3);'
fwdref f10 o gb "needs \`impl Show for i64\`" "F10: return o(n); (a tail call)"
fmk f11 '' 'return 9;'
exits f11 9 "F11: the definition alone, never called"
# F12: the judgement follows a chain of 64 forwards (o63 -> .. -> o0 -> gb), its stated reach; a deeper chain is the
# filed `_bbf_dep` cap (a 66-deep one is refused at a definition) — see the staged issue on the cap
{ printf 'include "lib/syscalls.cyr"\ntrait Show { fn show(self): i64; }\nimpl Show for f64 { fn show(self): i64 { return 5; } }\n'
  printf 'fn gb<T: Show>(x: T): i64 { return x.show(); }\nfn o0<T>(x: T): i64 { return gb(x); }\n'
  k=1; while [ "$k" -lt 64 ]; do printf 'fn o%d<T>(x: T): i64 { return o%d(x); }\n' "$k" "$((k - 1))"; k=$((k + 1)); done
  printf 'fn main(): i64 { var h: f64 = 1.5; return o63(h); }\nsyscall(60, main());\n'; } > "$T/f12.cyr"
exits f12 5 "F12: a chain of 64 forwards to gb at f64, o63(h)"

# BC — a bounded call on a struct carrier's T field (6.7.14)
cat > "$T/bc0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
struct Box<T> { v: T; n; }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.show(); }
fn go(): i64 {
    var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2;
    var bi: Box<i64>; bi.v = 4; bi.n = 1;
    return gs(b) * 10 + gs(bi);
}
syscall(60, go());
EOF
exits bc0 65 "BC0: the filed repro, verbatim — gs(b) * 10 + gs(bi), b.v.show() on Pt and on i64"
BCH='trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
struct Box<T> { v: T; n; }'
BCI='impl Show for i64 { fn show(self): i64 { return self + 1; } }'
BCB='var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2; var bi: Box<i64>; bi.v = 4; bi.n = 1;'
bcmk() {   # <name> <decls> <go body>
    printf 'include "lib/syscalls.cyr"\n%s\n%s\nfn go(): i64 { %s %s }\nsyscall(60, go());\n' "$BCH" "$2" "$BCB" "$3" > "$T/$1.cyr"
}
BCG='fn gs<T: Show>(b: Box<T>): i64 { return b.v.show(); }'
bcmk bc1 "$BCG" 'return gs(b);'
exits bc1 6 "BC1: gs(b) alone, no i64 impl"
bcmk bc2 "$BCI
fn gp<T: Show>(b: *Box<T>): i64 { return b.v.show() + b.n; }" 'return gp(&b) * 10 + gp(&bi);'
exits bc2 86 "BC2: a *Box<T> carrier, gp(&b) * 10 + gp(&bi)"
bcmk bc3 "$BCG" 'return gs(bi);'
refused bc3 "generic 'gs': its type argument does not implement trait 'Show'" "BC3: gs(bi) with no impl Show for i64"
grep -qF "needs \`impl Show for i64\`" "$T/bc3.err" && ok "BC3: the note names \`impl Show for i64\`" || bad "BC3: no note naming \`impl Show for i64\`"
bcmk bc4 "impl Show for f64 { fn show(self): i64 { return 30; } }
impl Show for i32 { fn show(self): i64 { return self + 40; } }
$BCG" 'var bf: Box<f64>; bf.v = 1.5; bf.n = 1; var bw: Box<i32>; bw.v = 2; bw.n = 1; return gs(bf) + gs(bw);'
exits bc4 72 "BC4: f64 and i32 instances, gs(bf) + gs(bw) (30 + 42)"
bcmk bc5 "$BCI
fn gl<T: Show>(b: Box<T>): i64 { var c: Box<T> = b; var r = c.v.show(); c.v.show(); return r + c.n; }" 'return gl(b) * 10 + gl(bi);'
exits bc5 86 "BC5: a var c: Box<T> carrier, var r = c.v.show(); and the statement c.v.show();"
bcmk bc6 "$BCI
$BCG" 'return gs<i64>(bi) + gs(bi);'
exits bc6 10 "BC6: gs<i64>(bi), explicit"
bcmk bc7 "$BCI
impl Pt { fn other(self): i64 { return 77; } }
fn go2<T: Show>(b: Box<T>): i64 { return b.v.other(); }" 'return go2(b);'
exits bc7 77 "BC7: control — b.v.other(), a method no bound declares, keeps its 6.7.11 reading (Pt's)"
bcmk bc8 "$BCI
fn gn<T: Show>(b: Box<T>): i64 { return b.v.show() + b.n; }" 'var s = 0; var i = 0; while (i < 3) { s = s + gn(bi); i = i + 1; } return s;'
exits bc8 18 "BC8: in a loop, gn(bi) three times"
bcmk bc9 "$BCI
fn gw<T: Show>(b: Box<T>): i64 { var t: T = b.v; return t.show(); }" 'return gw(b) * 10 + gw(bi);'
exits bc9 65 "BC9: the documented workaround (var t: T = b.v;) unchanged"
bcmk bc10 "$BCG" 'return 4;'
exits bc10 4 "BC10: the definition alone, no impl Show for i64"

# N — a bound refusal swallowed by the panic latch (6.7.14)
mk n1 'fn gb<T: Show>(x: T): i64 { var t = 0; var i = 0; while (i < 1) { t = t + x.show(); i = i + 1; } return t; }
fn gs<T>(q: T): i64 { var s = 0; var i = 0; while (i < 2) { s = s + q.y; i = i + 1; } return s; }' 'var b = gs(5) + gb(3); return b;'
refused n1 "generic 'gs' has no i64 (or other scalar) instance" "N1: gs(5) + gb(3) — the stub's refusal"
if grep -q "^  note:" "$T/n1.err"; then bad "N1: an orphan note under the stub's error: $(grep '^  note:' "$T/n1.err" | head -1)"
else ok "N1: no orphan note for the swallowed gb(3) refusal"; fi

# C — anti-vacuous
mk c1 'trait Eq2 { fn eq2(self, o: Pt): i64; }
impl Eq2 for Pt { fn eq2(self, o: Pt): i64 { return self.x - o.x; } }
fn f<T: Show + Eq2>(a: T, b: T): i64 { return a.show() + a.eq2(b); }
fn s<T: Size>(v: T): i64 { return v.size(); }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
fn g<T: Show>(v: T): i64 { return v.show(); }
struct Box<T: Show> { v: T; n; }
fn u<T>(v: T): i64 { return v.show(); }' 'var b: Box<Pt>; b.n = 0; return f(p, p) - 42 + s(p) + g(5) - 6 + b.n + u(p) - 42 + 42;'
exits c1 44 "C1: T: Show + Eq2, a colliding size picked by T: Size, i64's impl, Box<Pt>, an unbounded T"
printf 'fn id<T>(v: T): i64 { return v + 1; }\nsyscall(60, id(41));\n' > "$T/c2.cyr"
exits c2 42 "C2: a program with no bound"

if [ "$fails" -ne 0 ]; then echo "FAIL: trait_bounds_checked — $fails row(s) red"; exit 1; fi
echo "PASS: trait_bounds_checked — bounds checked at the definition (D1-D7), at every instantiation incl. the i64 base, &g, a tail call and an inner generic call (I1-I8), and on generic structs incl. their i64 base (S1-S5); past 64 bounded receivers (B, 6.7.14); a generic forwarding T to a bounded one is bad at i64 alone, named by its forward (F, 6.7.14); a bounded call on a carrier's T field is a trait use, a scalar T's taking the field's value (BC, 6.7.14); a refusal the panic latch swallows prints no orphan note (N, 6.7.14); well-formed bounded code runs (C)"
