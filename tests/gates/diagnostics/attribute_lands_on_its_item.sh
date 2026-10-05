#!/bin/sh
# attribute_lands_on_its_item.sh — 6.6.17. A fn attribute (`#must_use`, `#pure`, `#io`, `#alloc`,
# `#inline`, `#regalloc`, `#deprecated`) belongs to the definition it precedes — including an
# `impl` method — and does what it does on a top-level fn.
#
# ⛔ THE DEFECTS (measured on the 6.6.17-open compiler):
#   A. an attribute armed before a top-level STATEMENT that first instantiates a generic
#      (`#must_use` / `y = g<i32>(1);` / `fn b()`) was consumed by the instance, which PARSE_FN_DEF
#      emits: `b();` was silent (it warns with `y = 7;` in that place) — `_attr_park`;
#   B. an `impl` body took only `pub` and `fn`: any directive before a method was "expected '}',
#      got unknown" — `_impl_attrs`;
#   C. the dot call `p.m(..);` never had the #must_use discard check, nor `#pure`'s #io / #alloc
#      check (a method could not carry the attributes, so neither was reachable before B).
# `#deprecated`'s rows (an impl method, the generic-instance case) are in
# deprecated_every_call_path.sh fixtures `impl_attr` and `geninst`.
#
# Each row asserts the EXACT set of warning lines, so a missing, a doubled and a misplaced warning
# are all red, plus the run's exit code where the program runs. Exit 77 = could not run.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 77
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: attribute_lands_on_its_item: no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: attribute_lands_on_its_item: mktemp -d failed"; exit 77; }
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
# $1 label  $2 source  $3 grep pattern for the counted warnings  $4 wanted line list ("3 7 ")
#   $5 wanted exit code of the program
row() {
    printf '%s' "$2" > "$T/a.cyr"
    crc=0
    "$CC" < "$T/a.cyr" > "$T/a.bin" 2> "$T/a.err" || crc=$?
    if [ "$crc" -ne 0 ]; then
        echo "  FAIL: $1 did not compile (rc $crc): $( { grep -v '^note' "$T/a.err" || true; } | head -1)"; fail=$((fail + 1)); return
    fi
    got=$( { grep -- "$3" "$T/a.err" || true; } | sed -n 's/^warning:<source>:\([0-9]*\):.*/\1/p' | tr '\n' ' ')
    if [ "$got" != "$4" ]; then
        echo "  FAIL: $1 warned on lines {$got}, want {$4}"; { grep '^warning' "$T/a.err" || true; } | head -6 | sed 's/^/      /'
        fail=$((fail + 1)); return
    fi
    chmod +x "$T/a.bin"
    rrc=0
    "$T/a.bin" > /dev/null 2>&1 || rrc=$?
    if [ "$rrc" -ne "$5" ]; then echo "  FAIL: $1 ran rc $rrc, want $5"; fail=$((fail + 1)); return; fi
    echo "  ok: $1"; pass=$((pass + 1))
}

row A1 'include "lib/syscalls.cyr"
fn g<T>(x: T): T { return x + 6; }
var y = 0;
#must_use
y = g<i32>(1);
fn b(): i64 { return 3; }
fn m(): i64 { b(); var k = g<i32>(2); return y + k; }
syscall(60, m());
' "#must_use result of" "7 " 15

row A2 'include "lib/syscalls.cyr"
fn g<T>(x: T): T { return x + 6; }
#io
fn io_f(): i64 { return 2; }
var y = 0;
#pure
y = g<i32>(1);
fn b(): i64 { return io_f(); }
fn m(): i64 { return y + b(); }
syscall(60, m());
' "#pure fn calls" "8 " 9

row B1 'include "lib/syscalls.cyr"
struct P { x; }
impl Pm for P {
    #must_use
    fn mu(self): i64 { return 2; }
    #inline
    fn inl(self): i64 { return 4; }
    #regalloc
    fn ra(self): i64 { var a = 1; var b = 2; return a + b; }
    #assert sizeof(P) == 8
    fn me(self: P): P { return self; }
    fn plain2(self, a): i64 { return a; }
}
fn m(): i64 {
    var p = P { 1 };
    p.mu();
    p.me().mu();
    var k = p.mu();
    p.plain2(p.mu());
    P_mu(&p);
    return k + p.inl() + p.ra();
}
syscall(60, m());
' "#must_use result of" "16 17 20 " 9

row C1 'include "lib/syscalls.cyr"
struct P { x; }
impl Pm for P {
    #io
    fn io(self): i64 { return 3; }
    #alloc
    fn al(self): i64 { return 4; }
    #pure
    fn pu(self: *P): i64 { return self.io(); }
}
#pure
fn pf(p: *P): i64 { return p.io() + p.al(); }
fn m(): i64 { var p = P { 1 }; return pf(&p) + p.pu(); }
syscall(60, m());
' "#pure fn calls" "9 12 12 " 10

if [ "$fail" -ne 0 ]; then echo "FAIL attribute_lands_on_its_item: $fail failed, $pass passed"; exit 1; fi
echo "PASS attribute_lands_on_its_item: $pass rows — a pending attribute skips a generic instance; impl methods take every directive; #must_use and #pure checks reach the dot call"
exit 0
