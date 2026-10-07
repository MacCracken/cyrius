#!/bin/sh
# tests/gates/frontend/impl_self_typed.sh — 6.7.0 (arc A4)
#
# AN UNTYPED `self` IN AN `impl … for T` IS A `*T`, AND ARITHMETIC ON IT IS REFUSED.
#
# Before 6.7.0 an untyped `self` was a bare address: `self.x` was "no struct type in scope for
# 'self'", so every method read `load64(self)`, and the direct call `T_m(o)` passed o's VALUE
# where `o.m()` passed `&o` — on an 8-byte struct the method then loaded through 7 (SIGSEGV).
# Typed `*T`, it reads and writes fields, and `T_m(o)` / `T_m(&o)` / `o.m()` agree. A `*T` steps
# sizeof(T) under `+` / `-`, so `load64(self + 8)` would have changed meaning SILENTLY; the
# user's decision (2026-10-07) is to REFUSE arithmetic on an untyped `self`, by name.
#
#   A  fields through `self` (8 B and 24 B structs), read and write; the three call spellings agree
#   B  every arithmetic spelling is refused, once, naming the struct: `self + n`, `n + self`,
#      `self - n`, `self +% n`, `self[i]`, `self += n`
#   C  ANTI-VACUOUS: what stays legal compiles and runs — `self.a + self.b` (a `+` beside a FIELD
#      read), `self != 0`, passing `self` on, `var a = self;` then byte arithmetic on `a`
#   D  an explicit `self: *T` is untouched: its arithmetic compiles (and steps elements)
#   E  a GENERIC method's instance (re-parsed from its call site, outside the impl) types `self` too
#
# Mutations: make `_iself_def_sid` return 0 -> A + E RED ("no struct type in scope"). Drop the
# `_iself_arith_check` call in PARSE_FACTOR -> B RED (all but `+=` build). Drop its `PEEKT == 41`
# arm -> C RED (`self.a + self.b` refused). Make `_iself_sid_for` ignore `_impl_tnoff` -> D still
# GREEN but the explicit-`self` fixture of A goes through the same path (covered by A's rc).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: impl_self_typed: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: impl_self_typed: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
refused_once() {   # <name> <what>
    build "$1"
    n=$(grep -c "arithmetic on an untyped \`self\` is refused\|compound assignment to an untyped \`self\` is refused" "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$2: BUILT (rc 0)"
    elif [ "$n" -ne 1 ]; then bad "$2: rc $rc, $n refusal line(s) (want 1): $(grep '^error' "$T/$1.err" | head -1)"
    elif ! grep -q "points at 'N3'" "$T/$1.err"; then bad "$2: refused without naming the struct"
    else ok "$2: refused once, naming N3"; fi
}
H='include "lib/syscalls.cyr"
struct B1 { v; }
struct N3 { a; b; c; }
'

# ── A ──
printf "$H"'impl B1 { fn m(self): i64 { return self.v; } fn setv(self, x) { self.v = x; return 0; } }
impl N3 { fn sum(self): i64 { return self.a + self.b + self.c; } fn first(self): i64 { return load64(self); } }
fn main(): i64 {
    var b = B1 { 7 }; var n = N3 { 1, 2, 3 }; var r = 0;
    if (b.m() == 7) { r = r + 1; }
    if (B1_m(b) == 7) { r = r + 2; }
    if (B1_m(&b) == 7) { r = r + 4; }
    b.setv(9);
    if (b.v == 9) { r = r + 8; }
    if (n.sum() == 6) { r = r + 16; }
    if (N3_sum(n) == 6) { r = r + 32; }
    if (n.first() == 1) { r = r + 64; }
    return r;
}
syscall(60, main());
' > "$T/a.cyr"
exits a 127 "A: fields through self; o.m() == T_m(o) == T_m(&o) at 8 B and 24 B"

# ── B ──
i=0
for body in 'return load64(self + 8);' 'return load64(8 + self);' 'return load64(self - 8);' 'return load64(self +% 8);' 'return self[1];' 'self += 8; return 0;'; do
    i=$((i + 1))
    printf "$H"'impl N3 { fn f(self): i64 { %s } }\nvar n = N3 { 1, 2, 3 };\nsyscall(60, n.f());\n' "$body" > "$T/b$i.cyr"
    refused_once "b$i" "B: \`$body\`"
done

# ── C ──
printf "$H"'fn take(p): i64 { return load64(p + 8); }
impl N3 { fn f(self): i64 {
    var r = 0;
    if (self.a + self.b == 3) { r = r + 1; }
    if (self != 0) { r = r + 2; }
    if (take(self) == 2) { r = r + 4; }
    var a = self;
    if (load64(a + 16) == 3) { r = r + 8; }
    return r; } }
var n = N3 { 1, 2, 3 };
syscall(60, n.f());
' > "$T/c.cyr"
exits c 15 "C: field arithmetic, comparison, passing self on, a plain-address copy"

# ── D ──
printf "$H"'impl N3 { fn nxt(self: *N3): i64 { var q = self + 1; return q - self; } }
var n = N3 { 1, 2, 3 };
syscall(60, n.nxt());
' > "$T/d.cyr"
build d
if [ "$rc" -ne 0 ]; then bad "D: an explicit \`self: *N3\` with arithmetic did not build: $(grep '^error' "$T/d.err" | head -1)"
else ok "D: an explicit \`self: *T\` keeps its arithmetic"; fi

# ── E ──
printf "$H"'impl B1 { fn g<T>(self, x: T): i64 { return self.v + x; } }
fn main(): i64 { var b = B1 { 40 }; var a: i32 = 2; return b.g(a); }
syscall(60, main());
' > "$T/e.cyr"
exits e 42 "E: a generic method instance types self (re-parsed outside the impl)"

if [ "$fails" -ne 0 ]; then echo "FAIL: impl_self_typed — $fails row(s) red"; exit 1; fi
echo "PASS: impl_self_typed — an untyped impl \`self\` is a \`*T\` (fields, the three call spellings, generic instances) and arithmetic on it is refused by name (6 spellings); field arithmetic, comparison, pass-on and an explicit \`self: *T\` are untouched"
