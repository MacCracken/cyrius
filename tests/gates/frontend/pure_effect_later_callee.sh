#!/bin/sh
# pure_effect_later_callee.sh — 6.7.14: `#pure`'s `#io` / `#alloc` check sees a callee defined LATER. The check
# reads the callee's fn_flags bits 16 / 32 at the call, and only PARSE_FN_DEF (pass 2, in source order) wrote them:
# a callee defined below its `#pure` caller — a plain call, a tail call `return wr();`, an impl method `p.m()` —
# warned nothing, while the callees-first order warned all four. Pass 1 now records the pair as it records
# `#deprecated` (`_tl_arm1` arms a pass-1-only pair where pass 1 steps the token — the top-level scan, an impl body,
# the scan after the first statement, a top-level block; `_prescan_eff_take` ORs the bits onto the fn
# `_prescan_fn_sig` registers; `_pre_attr_drop` where no fn takes them). Warnings only: no exit code changes
# (issues/2026-10-08-pure-check-misses-later-defined-callee.md).
#
#   P1  the filed repro verbatim: its four warnings, exactly (line:col and name), and the program still runs (5)
#   P2  the callees-first control: the same four, none doubled
#   P3  a callee defined after the first top-level statement (the tail scan)
#   P4  a callee defined inside a top-level block (`if (..) { #io fn wr() .. }`, the block-fn scan)
#   P5  a trait-impl method defined later
#   P6  an `#io` that lands on no fn of its own is not handed to the wrong one: `#io var x = 1;` then `fn pl` is
#       what pass 2 makes of it (pl is `#io` both orders), and a `#pure` fn calling a later plain fn stays quiet
#
# MUTATION (measured, 6.7.14): `_prescan_eff_take` not called from `_prescan_fn_sig` -> P1, P3, P4, P5 and P6's
# later order RED (no warning); `_tl_arm1` not called from `_prescan_tail_loop` -> P3 and P6's later order RED;
# not from `_prescan_skip_stmt` -> P4 RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: pure_effect_later_callee: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: pure_effect_later_callee: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pure_effect_later_callee: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: pure_effect_later_callee $1"; fail=$((fail + 1)); }

# row ID WANT_EXIT WANT — the source on stdin compiles (rc 0, no error), its warning lines (with `<source>:`
# stripped, joined by '|') are exactly WANT, and the program exits WANT_EXIT.
row() {
  rows=$((rows + 1))
  cat > "$D/$1.cyr"
  rc=0; "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || rc=$?
  [ "$rc" -eq 0 ] || { bad "$1: compile rc $rc: $(grep -E '^error' "$D/$1.err" | head -1)"; return; }
  [ -s "$D/$1" ] || { bad "$1: empty output"; return; }
  got=$(grep -E '^(error|warning)' "$D/$1.err" | sed 's/^warning:<source>://' | tr '\n' '|')
  [ "$got" = "$3" ] || { bad "$1: warnings {$got}, want {$3}"; return; }
  chmod +x "$D/$1"
  x=0; "$D/$1" > /dev/null 2>&1 || x=$?
  [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
}

row P1 5 "7:26: #pure fn calls #io fn 'wr'|7:42: #pure fn calls #alloc fn 'grab'|9:25: #pure fn calls #io fn 'wr'|11:33: #pure fn calls #io fn 'A_m'|" <<'EOF'
# 2026-10-08 — `#pure`'s #io / #alloc check misses a callee defined LATER.
# Expected: four warnings — f calls #io 'wr' and #alloc 'grab', g tail-calls #io 'wr',
#   h calls #io method 'A_m'. Actual (6.7.6): none. Moving the callees above the #pure fns
#   gives all four.
struct A { v; }
#pure
fn f(): i64 { var a = wr(); var b = grab(); return a + b; }
#pure
fn g(): i64 { return wr(); }
#pure
fn h(p: *A): i64 { return p.m() + 0; }
#io
fn wr(): i64 { syscall(1, 1, "x", 1); return 1; }
#alloc
fn grab(): i64 { return 2; }
impl A {
    #io
    fn m(self): i64 { syscall(1, 1, "y", 1); return 1; }
}
fn main(): i64 { var a: A; a.v = 0; return f() + g() + h(&a); }
syscall(60, main());
EOF
row P2 5 "11:26: #pure fn calls #io fn 'wr'|11:42: #pure fn calls #alloc fn 'grab'|13:25: #pure fn calls #io fn 'wr'|15:33: #pure fn calls #io fn 'A_m'|" <<'EOF'
struct A { v; }
#io
fn wr(): i64 { syscall(1, 1, "x", 1); return 1; }
#alloc
fn grab(): i64 { return 2; }
impl A {
    #io
    fn m(self): i64 { syscall(1, 1, "y", 1); return 1; }
}
#pure
fn f(): i64 { var a = wr(); var b = grab(); return a + b; }
#pure
fn g(): i64 { return wr(); }
#pure
fn h(p: *A): i64 { return p.m() + 0; }
fn main(): i64 { var a: A; a.v = 0; return f() + g() + h(&a); }
syscall(60, main());
EOF
row P3 3 "2:25: #pure fn calls #io fn 'wr'|2:34: #pure fn calls #alloc fn 'grab'|" <<'EOF'
#pure
fn f(): i64 { return wr() + grab(); }
var r = 0;
r = f();
#io
fn wr(): i64 { return 1; }
#alloc
fn grab(): i64 { return 2; }
syscall(60, r);
EOF
row P4 1 "2:25: #pure fn calls #io fn 'wr'|" <<'EOF'
#pure
fn f(): i64 { return wr() + 0; }
var r = 0;
if (r == 0) {
    #io
    fn wr(): i64 { return 1; }
}
syscall(60, f());
EOF
row P5 1 "4:33: #pure fn calls #io fn 'A_m'|" <<'EOF'
struct A { v; }
trait Tr { fn m(self): i64; }
#pure
fn h(p: *A): i64 { return p.m() + 0; }
impl Tr for A {
    #io
    fn m(self): i64 { return 1; }
}
fn main(): i64 { var a: A; a.v = 0; return h(&a); }
syscall(60, main());
EOF
row P6a 1 "6:25: #pure fn calls #io fn 'pl'|" <<'EOF'
syscall(1, 1, 0, 0);
#io
var x = 1;
fn pl(): i64 { return 1; }
#pure
fn f(): i64 { return pl(); }
syscall(60, f());
EOF
row P6b 1 "3:25: #pure fn calls #io fn 'pl'|" <<'EOF'
syscall(1, 1, 0, 0);
#pure
fn f(): i64 { return pl(); }
#io
var x = 1;
fn pl(): i64 { return 1; }
syscall(60, f());
EOF
row P6c 3 "" <<'EOF'
#pure
fn f(): i64 { return pl() + wr(0); }
#pure
fn wr(a): i64 { return a + 2; }
fn pl(): i64 { return 1; }
#io
fn later(): i64 { return 4; }
syscall(60, f());
EOF

[ "$rows" -ge 8 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL pure_effect_later_callee: $fail of $rows row(s) red"; exit 1; fi
echo "PASS pure_effect_later_callee: $rows rows — #pure's #io / #alloc check warns on a callee defined later (plain, tail, method, after a statement, in a block, a trait impl), once"
exit 0
