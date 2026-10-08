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
#   C  ANTI-VACUOUS: the same shapes with the impl present build and run; an unbounded `T` keeps
#      per-instance method resolution; a program with no bound is untouched
#
# Mutations (scratch trees, each RED here — run 2026-10-07): `_capture_tparams` not reading a bound
#   (every identifier a type parameter again) -> D1 builds, D2-D4 refused only by the cascade;
#   `_bnd_check_fn` answering 0 -> I1/I2 refused only as undefined fns, I3 BUILDS; `_bnd_site` not
#   refusing -> D2/D3 refused only by the cascade; `_bnd_base_bad` answering 0 -> I3-I5 refused
#   with the struct-stub message instead of the bound's; `_bnd_sbase` a no-op -> S2-S4 BUILD; no
#   quiet mode in `_sfield_gen` -> S4 BUILDS (W's base never learns it holds a Box<i64>).
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
refused i7 "generic 'u' has no i64 (or other scalar) instance" "I7: an unbounded generic forwarding T to a bounded one, u(5)"

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
echo "PASS: trait_bounds_checked — bounds checked at the definition (D1-D7), at every instantiation incl. the i64 base, &g and a tail call (I1-I7), and on generic structs incl. their i64 base (S1-S5); well-formed bounded code runs (C)"
