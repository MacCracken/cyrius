#!/bin/sh
# tests/gates/frontend/type_args_on_nongeneric_refused.sh — 6.7.16
#
# A TYPE-ARGUMENT LIST ON A CALLEE THAT TAKES NONE IS REFUSED ONCE, AT ITS NAME. With `fn nf(a)` and `impl Pt { fn
# m(self, k) }` (neither generic), `nf<i64>(6)` and `p.m<i64>(1)` read the `<` as less-than: "undefined variable 'nf'"
# + "undefined variable 'i64'" + "expected ';', got '>'", or "unknown field 'm' on struct 'Pt'" + "undefined variable
# 'i64'" — two or three errors, none naming the list; a bounded T's non-generic member (`v.show<i64>()` under `T:
# Show`) was "no struct type in scope for 'v'" at a scalar T and "expected ';', got '.'" on a carrier's field. The
# list is now refused with D6 / D7's words for `Pt<i64>` — "'nf' is not a generic fn: it takes no type arguments",
# "'Pt.m' is not a generic method: it takes no type arguments" (`_eta_gen`, `_meth_ngt`) — stepped, and the call parsed
# as `nf(6)` / `p.m(1)`, so nothing cascades; a `.m<types>(` with no method m, or on a receiver of no known struct, is
# stepped too and reports what `p.m(1)` reports. Only a list whose every name is a type (`_tylist_at`): a comparison
# `p.y < a, b > (1)` keeps its reading. `--syntax-only` (cyrius lint) is silent, as D6's refusals are. Found by 6.7.16's
# genbind lane (unit GB2) beside the user's D4 (a bound's member called with an explicit list).
#
#   R   a fn: returned, a statement, a `var` initializer, an argument, two arguments, a nested instance in the list,
#       a method called by its fn name (`Pt_m<i64>(&p, 1)`)
#   M   a method: returned, a statement, an inline struct field `w.v.m<i64>(1)`, a `*Pt` field, a `*Pt` receiver
#   B   a bounded T's non-generic member at a scalar T (once for two instances) and on a carrier's field
#   U   no method m (`p.zz<i64>(1)`: as `p.zz(1)`, the undefined-fn refusal), an untyped receiver (as `q.m(1)`)
#   X   --syntax-only silent (rc 0)
#   K   controls, unchanged: comparisons `p.y < a, b > (1)` / `w.n < a, b > (1)`, a generic fn and method with their
#       lists — build and exit 26
#   A   R1 and M1 refused with the same line by the aarch64, cx and PE compilers
#
# MUTATION (2026-10-20, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler (b6ccc7a50)
# -> RED 19: R1-R7, M1-M5, B1, B2, U1, U2, X1 and A [pe] x2 (the cascades; X2 / X3 were silent since b6ccc7a50, and
# A [a64] / [cx] build their cross compilers from the tree's src); `_eta_gen` without its refusal -> RED 9: R1-R7, X1,
# A [pe] R1; `_meth_ngt` answering 0 -> RED 10: M1-M5, B1, B2, U1, U2, A [pe] M1; `_mtargs_ng` as `_mtargs_at` (the
# field walks not stopping at the list) -> RED 2: M3, B2.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=type_args_on_nongeneric_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS CYRIUS_MONOMORPH
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# one <name> <expected text> <what> [compiler-cmd]: refused with EXACTLY one error line, which carries <text>.
one() {
    rc=0
    if [ $# -ge 4 ]; then sh -c "$4" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    else "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; fi
    n=$(grep -c '^error' "$D/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want 1: $(grep '^error' "$D/$1.err" | tr '\n' '|')"
    elif ! grep -qF -- "$2" "$D/$1.err"; then bad "$3: refused, but not with \"$2\": $(grep '^error' "$D/$1.err")"
    else ok "$3: $2"; fi
}
H='include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
impl Pt { fn m(self, k): i64 { return self.y + k; } }
struct W { v: Pt; p: *Pt; n; }
struct Box<T> { v: T; n; }
fn nf(a): i64 { return a; }
fn id(a): i64 { return a; }'
mk() { printf '%s\n%s\nsyscall(60, go());\n' "$H" "$2" > "$D/$1.cyr"; }
FN="'nf' is not a generic fn: it takes no type arguments"
MT="'Pt.m' is not a generic method: it takes no type arguments"

# ── R: a fn that is not generic ──────────────────────────────────────────────────────────────────────────────
mk r1 'fn go(): i64 { return nf<i64>(6); }'
one r1 "11:23: $FN" "R1: return nf<i64>(6)"
mk r2 'fn go(): i64 { nf<i64>(6); return 1; }'
one r2 "11:16: $FN" "R2: nf<i64>(6); — a statement (it was \"expected '=', got '<'\")"
mk r3 'fn go(): i64 { var r = nf<i64>(6); return r; }'
one r3 "11:24: $FN" "R3: var r = nf<i64>(6);"
mk r4 'fn go(): i64 { return id(nf<i64>(6)); }'
one r4 "11:26: $FN" "R4: an argument, id(nf<i64>(6))"
mk r5 'fn go(): i64 { return nf<i64, Pt>(6); }'
one r5 "11:23: $FN" "R5: two type arguments"
mk r6 'fn go(): i64 { return nf<Box<i64>>(6); }'
one r6 "11:23: $FN" "R6: a nested instance in the list (its \`>>\` close)"
mk r7 'fn go(): i64 { var p: Pt; p.y = 6; return Pt_m<i64>(&p, 1); }'
one r7 "11:43: 'Pt_m' is not a generic fn: it takes no type arguments" "R7: a method by its fn name, Pt_m<i64>(&p, 1)"

# ── M: a method that is not generic ──────────────────────────────────────────────────────────────────────────
mk m1 'fn go(): i64 { var p: Pt; p.y = 6; return p.m<i64>(1); }'
one m1 "11:45: $MT" "M1: return p.m<i64>(1) (it was \"unknown field 'm' on struct 'Pt'\" + \"undefined variable 'i64'\")"
mk m2 'fn go(): i64 { var p: Pt; p.y = 6; p.m<i64>(1); return 1; }'
one m2 "11:38: $MT" "M2: p.m<i64>(1); — a statement"
mk m3 'fn go(): i64 { var w: W; w.v.y = 6; return w.v.m<i64>(1); }'
one m3 "11:48: $MT" "M3: an inline struct field, w.v.m<i64>(1)"
mk m4 'fn go(): i64 { var w: W; var p: Pt; p.y = 6; w.p = &p; return w.p.m<i64>(1); }'
one m4 "11:67: $MT" "M4: a *Pt field, w.p.m<i64>(1)"
mk m5 'fn gq(q: *Pt): i64 { return q.m<i64>(1); }
fn go(): i64 { var p: Pt; p.y = 6; return gq(&p); }'
one m5 "11:31: $MT" "M5: a *Pt receiver"

# ── B: a bounded T's member that is not generic ──────────────────────────────────────────────────────────────
mk b1 'fn gn<T: Show>(v: T): i64 { return v.show<i64>(); }
fn go(): i64 { var p: Pt; p.y = 6; return gn(p) + gn(5); }'
one b1 "11:38: 'i64.show' is not a generic method: it takes no type arguments" "B1: v.show<i64>() at a scalar and a struct T — once (it was \"no struct type in scope for 'v'\" + 2)"
mk b2 'fn gs<T: Show>(b: Box<T>): i64 { return b.v.show<i64>(); }
fn go(): i64 { var b: Box<i64>; b.v = 5; var c: Box<Pt>; c.v.y = 6; return gs(b) + gs(c); }'
one b2 "11:45: 'i64.show' is not a generic method: it takes no type arguments" "B2: b.v.show<i64>() on a carrier's field (it was \"expected ';', got '.'\" + 2)"

# ── U: no such method; a receiver of no known struct ────────────────────────────────────────────────────────
mk u1 'fn go(): i64 { var p: Pt; p.y = 6; return p.zz<i64>(1); }'
mk u1b 'fn go(): i64 { var p: Pt; p.y = 6; return p.zz(1); }'
"$CC" < "$D/u1.cyr" > /dev/null 2> "$D/u1.err"; a=$(grep '^error' "$D/u1.err")
"$CC" < "$D/u1b.cyr" > /dev/null 2> "$D/u1b.err"; b=$(grep '^error' "$D/u1b.err")
if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "U1: p.zz<i64>(1) reports what p.zz(1) reports: $a"
else bad "U1: p.zz<i64>(1) [$a] differs from p.zz(1) [$b]"; fi
mk u2 'fn go(): i64 { var p: Pt; p.y = 6; var q = &p; var r = q.m<i64>(1); return r; }'
one u2 "no struct type in scope for 'q'; a method call needs its struct declaration" "U2: an untyped receiver, as q.m(1) (it was the '.field' message + \"undefined variable 'i64'\")"

# ── X: --syntax-only says nothing ────────────────────────────────────────────────────────────────────────────
for x in r1:X1 m1:X2 b1:X3; do
    f=${x%%:*}; w=${x##*:}
    rc=0; "$CC" --syntax-only < "$D/$f.cyr" > /dev/null 2> "$D/$f.so" || rc=$?
    n=$(grep -c '^error' "$D/$f.so")
    if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then ok "$w: --syntax-only on $f is silent (rc 0)"
    else bad "$w: --syntax-only on $f: rc $rc, $n error line(s): $(grep '^error' "$D/$f.so" | tr '\n' '|')"; fi
done

# ── K: controls ──────────────────────────────────────────────────────────────────────────────────────────────
mk k1 'fn id2(a, b): i64 { return a * 10 + b; }
fn gid<T>(x: T): i64 { return sizeof(T); }
impl Pt { fn gm<V>(self, k: V): i64 { return self.y + sizeof(V); } }
fn go(): i64 { var p: Pt; p.y = 6; var w: W; w.n = 3; var a = 9; var b = 3; return id2(p.y < a, b > (1)) + id2(w.n < a, b > (1)) + gid<i32>(4) + p.gm<i16>(1) + gid(7) - 16; }'
rc=0; "$CC" < "$D/k1.cyr" > "$D/k1.bin" 2> "$D/k1.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "K1: rc $rc: $(grep '^error' "$D/k1.err" | head -2 | tr '\n' '|')"
else chmod +x "$D/k1.bin"; got=0; "$D/k1.bin" || got=$?
    if [ "$got" -eq 26 ]; then ok "K1: comparisons keep their reading; a generic fn and method take their lists (exit 26)"
    else bad "K1: exit $got, want 26"; fi
fi

# ── A: the refusal from every cross compiler ─────────────────────────────────────────────────────────────────
A64="$D/cc_a64"; CXCC="$D/cc_cx"
if "$CC" < src/main_aarch64.cyr > "$A64" 2> /dev/null && [ -s "$A64" ]; then chmod +x "$A64"
    one r1 "11:23: $FN" "A [a64]: R1" "$A64"; one m1 "11:45: $MT" "A [a64]: M1" "$A64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$CXCC" 2> /dev/null && [ -s "$CXCC" ]; then chmod +x "$CXCC"
    one r1 "11:23: $FN" "A [cx]: R1" "$CXCC"; one m1 "11:45: $MT" "A [cx]: M1" "$CXCC"
else bad "cx: src/main_cx.cyr did not build"; fi
one r1 "11:23: $FN" "A [pe]: R1" "CYRIUS_TARGET_WIN=1 $CC"
one m1 "11:45: $MT" "A [pe]: M1" "CYRIUS_TARGET_WIN=1 $CC"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — a type-argument list on a fn or method that is not generic is refused once, at its name, and the call parsed as its plain spelling: a fn (R), a method (M), a bounded T's member (B), no such method / an untyped receiver as the plain spelling (U), silent under --syntax-only (X), comparisons and generic callees unchanged (K), every cross compiler (A)"
exit 0
