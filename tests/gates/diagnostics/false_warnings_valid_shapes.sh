#!/bin/sh
# false_warnings_valid_shapes.sh — 6.6.17. Four warnings that fired on valid code (each built and
# ran correctly), each paired with a row proving the warning still fires on a genuinely wrong
# shape — a gate that only checks silence passes a deleted warning.
#
#   B  `warning: undefined function 'f'` for a fn defined inside a TOP-LEVEL block and called
#      from a fn earlier in the file: the relaxed-ordering prescan did not descend into blocks.
#      (The same blind spot miscompiled a forward call passing a struct: rc 139 — pinned at run
#      time by tests/tcyr/lang/toplevel_block_fn_forward_call.tcyr.) Control: a call to a fn
#      defined nowhere still warns.
#   P  `assigning non-pointer to typed pointer` for a RHS of exactly the local's struct type:
#      `a = GP` (a pointer-mode struct global), `b = q.name()` (a method declared `: Str`),
#      `b = q.name` / `b = w.q.name` (a `: Str` field, nested). Controls: an integer, a global of
#      ANOTHER struct type, an i64 field and an i64 method still warn — one each.
# RED on the slot-open compiler (4a37046b): B1, B1a and P1.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: false_warnings_valid_shapes: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: false_warnings_valid_shapes: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: false_warnings_valid_shapes: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: false_warnings_valid_shapes $1"; fail=$((fail + 1)); }
# chk <row> <file> <needle> <want-count> [<want-exit>]
chk() {
  rc=0; "$CC" < "$D/$2" > "$D/$2.bin" 2> "$D/$2.err" || rc=$?
  [ "$rc" = 0 ] || { bad "$1: did not compile (rc $rc): $(grep -m1 error "$D/$2.err")"; return; }
  n=$(grep -c -- "$3" "$D/$2.err" || true)
  [ "$n" = "$4" ] || { bad "$1: '$3' printed $n time(s), want $4"; grep -- "$3" "$D/$2.err" | head -4; return; }
  if [ -n "${5:-}" ]; then
    chmod +x "$D/$2.bin"; x=0; "$D/$2.bin" > /dev/null 2>&1 || x=$?
    [ "$x" = "$5" ] || bad "$1: ran to $x, want $5"
  fi
}

cat > "$D/b1.cyr" <<'EOF'
fn early(): i64 { return inner(1) + deep(0); }
var z = 0;
if (z == 0) {
    fn inner(x): i64 { return x + 40; }
    while (z == 0) {
        fn deep(x): i64 { return x + 1; }
        z = 1;
    }
}
syscall(60, early());
EOF
chk "B1 (fns in top-level blocks, called earlier)" b1.cyr "undefined function" 0 42
# B1a (review find): an attribute line before the block fn kept it unprescanned
cat > "$D/b1a.cyr" <<'EOF'
fn early(): i64 { return inner(1) + deep(0); }
var z = 0;
if (z == 0) {
    #pure
    fn inner(x): i64 { return x + 40; }
    #deprecated("use something else")
    fn deep(x): i64 { return x + 1; }
}
syscall(60, early());
EOF
chk "B1a (attributed fns in a top-level block)" b1a.cyr "undefined function" 0 42
cat > "$D/b2.cyr" <<'EOF'
fn early(): i64 { return nowhere(1); }
var z = 0;
if (z == 0) {
    fn inner(x): i64 { return x + 40; }
}
var q = inner(1);
EOF
"$CC" < "$D/b2.cyr" > /dev/null 2> "$D/b2.err" || true
n=$(grep -c "warning: undefined function 'nowhere'" "$D/b2.err" || true)
[ "$n" = 1 ] || bad "B2 (control): a fn defined nowhere warned $n time(s), want 1"
grep -q "undefined function 'inner'" "$D/b2.err" && bad "B2 (control): the block fn beside it warned"

cat > "$D/p1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
struct Pt { x; y; z; }
struct Q { name: Str; n; }
struct W { q: Q; k; }
fn Q_name(self: Q): Str { return self.name; }
var GP: Pt = alloc(24);
var GS: Str = str_from("gs");
fn main(): i64 {
    alloc_init();
    var a: Pt = alloc(24);
    a = GP;
    var q: Q;
    q.name = str_from("qq");
    q.n = 3;
    var w: W;
    w.q = q;
    w.k = 0;
    var b: Str = str_from("b");
    b = q.name();
    b = q.name;
    b = w.q.name;
    b = GS;
    return str_len(b);
}
syscall(60, main());
EOF
chk "P1 (a RHS of the local's own struct type)" p1.cyr "assigning non-pointer to typed pointer" 0 2
cat > "$D/p2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
struct Pt { x; y; z; }
struct Q { name: Str; n; }
fn Q_count(self: Q): i64 { return self.n; }
var GQ: Q = alloc(16);
fn main(): i64 {
    alloc_init();
    var a: Pt = alloc(24);
    var n = 5;
    a = n;
    a = GQ;
    var q: Q;
    q.name = str_from("qq");
    q.n = 3;
    var b: Str = str_from("b");
    b = q.n;
    b = q.count();
    return 0;
}
syscall(60, main());
EOF
chk "P2 (control: int, another struct's global, i64 field, i64 method)" p2.cyr "assigning non-pointer to typed pointer" 4

# D (6.7.13, D9 (a), the user 2026-10-15; issues/2026-10-13-double-pointer-dereference-is-an-untyped-word.md):
# `*pp` of a `pp: **T` is a `*T`, so `var q: *T = *pp;` and `q = *pp;` are silent — a `**i64` local, parameter,
# global (in a fn and at top level), field and `: **i64` call, and a `***i64`'s `**ppp`. It warned "assigning
# non-pointer to typed pointer" at each (the filed repro: line 9). D2 (controls): `**pp` (the i64 element) and an
# integer still warn — one each. D3: `*pp - b` with `b: *u8` is a pointer difference of two element sizes now,
# refused by name (it was a byte count of an untyped word). Mutation: `_pp_inner` answering 0 -> D0, D1 RED (the
# warnings return; D0's repro exits 1) and D3 RED (it compiles).
DR="$ROOT/docs/development/issues/2026-10-13-double-pointer-dereference-is-an-untyped-word.md"
if [ -f "$DR" ]; then
  awk '/^```cyrius$/ { f = 1; next } /^```$/ { if (f) exit } f' "$DR" > "$D/d0.cyr"
  chk "D0 (the filed repro verbatim: silent, exit 0)" d0.cyr "assigning non-pointer to typed pointer" 0 0
fi
cat > "$D/d1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct H { k; pp: **i64; }
var GA: i64[3];
var GP: *i64 = &GA;
fn sec(pp: **i64): i64 { var q: *i64 = *pp; q = *pp; return *(q + 1); }
fn trip(ppp: ***i64): i64 { var q: *i64 = **ppp; return *(q + 2); }
GA[1] = 4;
GA[2] = 5;
var GPP: **i64 = &GP;
var TQ: *i64 = *GPP;
fn gpp(): **i64 { return GPP; }
fn main(): i64 {
    var p: *i64 = &GA;
    var pp: **i64 = &p;
    var q: *i64 = *pp;
    q = *pp;
    var g: *i64 = *GPP;
    var h: H;
    h.pp = &p;
    var f: *i64 = *h.pp;
    var c: *i64 = *gpp();
    return *(q + 1) + sec(pp) + *(g + 1) + *(f + 1) + *(c + 2) + trip(&pp) + *(TQ + 1) - 25;
}
syscall(60, main());
EOF
chk "D1 (var q: *i64 = *pp: a local, a parameter, a global in a fn and at top level, a field, a call, ***)" d1.cyr "assigning non-pointer to typed pointer" 0 5
cat > "$D/d2.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: i64[2];
    var p: *i64 = &a;
    var pp: **i64 = &p;
    var q: *i64 = **pp;
    var r: *i64 = 7;
    return 0;
}
syscall(60, main());
EOF
chk "D2 (control: **pp, the element, and an integer still warn)" d2.cyr "assigning non-pointer to typed pointer" 2
cat > "$D/d3.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: i64[4];
    var p: *i64 = &a;
    var b: *u8 = &a;
    var pp: **i64 = &p;
    return *pp - b;
}
syscall(60, main());
EOF
rc=0; "$CC" < "$D/d3.cyr" > /dev/null 2> "$D/d3.err" || rc=$?
n=$(grep -c "pointer difference of pointers with different element sizes" "$D/d3.err" || true)
[ "$rc" != 0 ] && [ "$n" = 1 ] || bad "D3 (*pp - b, a *i64 less a *u8): rc $rc, refused $n time(s), want refused once"

if [ "$fail" -ne 0 ]; then echo "FAIL false_warnings_valid_shapes: $fail row(s) red"; exit 1; fi
echo "PASS false_warnings_valid_shapes: fns in top-level blocks are not 'undefined' (a fn defined nowhere still is); a same-typed global / Str method / Str field (nested too) assigned into a typed local is not 'non-pointer' (int, foreign struct, i64 field and i64 method still are); \`*pp\` of a \`**T\` is a \`*T\` (D9 (a))"
exit 0
