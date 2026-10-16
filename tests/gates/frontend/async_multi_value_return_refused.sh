#!/bin/sh
# tests/gates/frontend/async_multi_value_return_refused.sh — 6.7.11 (returns lane)
#
# AN `async fn` THAT RETURNS SEVERAL VALUES IS REFUSED BY NAME — a Future carries one i64.
# (issues/archived/2026-10-09-async-fn-multi-value-return-loses-second-value.md)
#
# THE DEFECT (measured on 6.7.11's returns-lane tip before the fix, CYRIUS_ASYNC=1): an `async fn`
# hands its result back through ONE word — `future_force` returns what the body left in rax, and a
# plain Future memoises that word. `async fn g(): (i64, i64) { return (1, 2); }` compiled with no
# diagnostic: `await g()` yielded 1, the second value was gone, and the documented `rethi()` read got
# it only on the force that ran the body — the issue's repro (force, an intervening multi-value call,
# force again, `rethi()`) exits 19 where 12 is right, on x86_64, aarch64, cx and PE. The undeclared
# `return (a, b);` and `ret2(a, b)` in an async body lost it the same way. 6.6.6 refused a struct and
# a vector return for this reason ("a Future carries one i64"); a declared multi-value return records
# MULTIRET_SID, which neither refusal reads. Refused by name now (the user's decision, 2026-10-13):
#   `async fn g` returns 2 values, and a Future carries one i64 - return a pointer to a struct holding them
# at the declaration (`: (T1, T2)` / `: (T1, T2, T3)`), and in an undeclared body at `return (a, b[, c]);`
# and `ret2(a, b)` — in a plain async fn and in a coroutine (an `await` in the body) alike. A declared
# fn is reported once, at its declaration (its body's spellings agree with it). A closure in an async
# fn, an #inline replay of a multi-value fn, and a one-value async fn are untouched; a tuple `return
# t;` keeps 6.7.7's own refusal.
#
# LEG: x86_64 (a frontend refusal, the same on every target; the repro was measured refused on the
# aarch64, cx and PE compilers too).
#
# MUTATION LEDGER (2026-10-14, each a scratch copy of the tree with the one change, its compiler built
# from it, this gate run from the copy as CYCC=<mutant>):
#   M0 the tree before the fix (92b690cb)                    -> RED V0 D2 D3 DC2 DC3 DB U2 U3 UC2 UC3 R2 RR
#                                                               RC RM (BUILT); DT (T5's refusal, not this)
#   M1 the declaration's `_refuse_async_multi_return` dropped -> RED V0 D2 D3 DC2 DC3 (BUILT), DB DT (BUILT:
#                                                               the body is left to the declaration)
#   M2 PARSE_RETURN's `_async_mv_ret` dropped                -> RED U2 U3 UC2 UC3 (BUILT), RM (1 error)
#   M3 the ret2 builtin's `_refuse_async_mv_body` dropped    -> RED R2 RR RC (BUILT), RM (1 error)
#   M4 `_refuse_async_mv_body` without the GIDEP test        -> RED K3 (the #inline replay refused)
#   M5 `_refuse_async_mv_body` without the declared skip     -> RED V0 D2 D3 DC2 DC3 DB (2-3 errors: the
#                                                               body's spellings again)
#   M6 `_refuse_async_mv_body` without `_fn_async_impl`      -> RED K2 K3 K5 (a closure's, a plain fn's, a sync
#                                                               fn's `return (a, b)` / ret2 refused)
#   M7 `_ret_tup_ok` reporting T5 for a declared async fn   -> RED DT (2 errors: + "cannot return tuple 't'")
#
# 6.7.13 — AXIS F: `return h(..);` FORWARDING A MULTI-VALUE CALL in such a body is the third spelling of the loss
# (D24 A, the user's decision, 2026-10-15; issues/2026-10-14-async-fn-forwarding-multi-value-call-loses-second-value.md):
# the repro built clean and exited 19 on x86_64 / aarch64 / cx / PE (the memoised 1, then h's 9 from rethi()). The
# callee declared `: (T1, T2[, T3])`, counted by pass 1, a method or a generic instance, parentheses around the whole
# call transparent — refused with the same text, at the forwarded call (`_ret_mv_fwd`, PARSE_RETURN). Wherever the
# literal is refused the forward is (a `: i64`-declared async fn included, as `return (1, 2);` there since 6.7.11).
# A one-value forward, `callptr(fp, ..)` (its callee unknown), a closure's own forward and a sync fn's still run.
#   M8 `_ret_mv_fwd` answering 0 at once                    -> RED F1 F2 F3 F4 F6 F7 F8 FD (BUILT)
#   M9 `_ret_mv_fwd` without the wrap step (k = 0)          -> RED F4 F7 (BUILT)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=async_multi_value_return_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
rows=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# refused <name> <fragment> <what> [<errors>]: $T/<name>.cyr, CYRIUS_ASYNC=1; <errors> (default 1)
refused() {
    rows=$((rows + 1))
    want=${4:-1}
    crc=0
    CYRIUS_ASYNC=1 timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" || crc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$crc" -eq 0 ]; then bad "$1 $3: BUILT (rc 0)"
    elif ! grep '^error' "$T/$1.err" | head -1 | grep -qF "$2"; then bad "$1 $3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1 || true)"
    elif [ "$n" -ne "$want" ]; then bad "$1 $3: $n error lines (want $want): $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|' || true)"
    elif [ -s "$T/$1.out" ]; then bad "$1 $3: refused, but a binary was written"
    else ok "$1 $3: refused ($n)"; fi
}
# runs <name> <want> <what>
runs() {
    rows=$((rows + 1))
    crc=0
    CYRIUS_ASYNC=1 timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" || crc=$?
    if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.out" ]; then bad "$1 $3: did not build (rc $crc): $(grep '^error' "$T/$1.err" | head -1 || true)"; return 0; fi
    chmod +x "$T/$1.out"; got=0
    timeout 30 "$T/$1.out" > /dev/null 2>&1 || got=$?
    if [ "$got" = "$2" ]; then ok "$1 $3: exit $got"; else bad "$1 $3: exit $got, want $2"; fi
}
REP=docs/development/issues/repros/2026-10-09-async-fn-multi-value-return.cyr
[ -f "$REP" ] || { echo "FAIL: $G: the issue's repro is missing ($REP)"; exit 1; }
M2="returns 2 values, and a Future carries one i64 - return a pointer to a struct holding them"
M3="returns 3 values, and a Future carries one i64 - return a pointer to a struct holding them"

# --- the issue's repro, verbatim ---
cp "$REP" "$T/V0.cyr"
refused V0 "\`async fn g\` $M2" "the repro verbatim (it exited 19)"

H='include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }
fn h(): (i64, i64) { return (7, 9); }'
row() { printf '%s\n%s\nfn main(): i64 { alloc_init(); return 0; }\nsyscall(60, main());\n' "$H" "$2" > "$T/$1.cyr"; }

# --- the declaration: plain and coroutine, 2 and 3 values ---
row D2 'async fn g(a): (i64, i64) { return (a, a + 1); }'
refused D2 "\`async fn g\` $M2" "declared \`: (i64, i64)\`"
row D3 'async fn g(a): (i64, i64, i64) { return (a, a + 1, a + 2); }'
refused D3 "\`async fn g\` $M3" "declared \`: (i64, i64, i64)\`"
row DC2 'async fn g(a): (i64, i64) { var s = await nopark(); return (a, s); }'
refused DC2 "\`async fn g\` $M2" "declared \`: (i64, i64)\`, a coroutine"
row DC3 'async fn g(a): (i64, i64, i64) { var s = await nopark(); return (a, s, 1); }'
refused DC3 "\`async fn g\` $M3" "declared \`: (i64, i64, i64)\`, a coroutine"
row DB 'async fn g(a): (i64, i64) { if (a > 0) { ret2(a, 1); } return (a, 2); }'
refused DB "\`async fn g\` $M2" "declared, with \`return (a, b)\` and \`ret2\` in its body: reported once, at the declaration"
row DT 'async fn g(a): (i64, i64) { var t: (i64, i64) = (a, 1); return t; }'
refused DT "\`async fn g\` $M2" "declared, with a tuple \`return t;\`: reported once, at the declaration (T5 silent)"

# --- the undeclared body: `return (a, b[, c]);` and ret2, plain and coroutine ---
row U2 'async fn g(a) { return (a, a + 1); }'
refused U2 "\`async fn g\` $M2" "undeclared \`return (a, b);\`"
row U3 'async fn g(a) { if (a > 0) { return (a, 1, 2); } return 0; }'
refused U3 "\`async fn g\` $M3" "undeclared \`return (a, b, c);\` beside a one-value return"
row UC2 'async fn g(a) { var s = await nopark(); return (a, s); }'
refused UC2 "\`async fn g\` $M2" "undeclared \`return (a, b);\`, a coroutine"
row UC3 'async fn g(a) { var s = await nopark(); return (a, s, 1); }'
refused UC3 "\`async fn g\` $M3" "undeclared \`return (a, b, c);\`, a coroutine"
row R2 'async fn g(a) { ret2(a, a + 1); }'
refused R2 "\`async fn g\` $M2" "\`ret2(a, b);\`"
row RR 'async fn g(a) { return ret2(a, a + 1); }'
refused RR "\`async fn g\` $M2" "\`return ret2(a, b);\`"
row RC 'async fn g(a) { var s = await nopark(); ret2(a, s); }'
refused RC "\`async fn g\` $M2" "\`ret2(a, b);\`, a coroutine"
row RM 'async fn g(a) { ret2(a, 1); }
async fn k(a) { return (a, 2, 3); }'
refused RM "\`async fn g\` $M2" "two async fns, each refused" 2

# --- controls ---
cat > "$T/K1.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }
fn h(): (i64, i64) { return (7, 9); }
async fn one(a) { var x, y = h(); return a * 10 + y - x; }
fn main(): i64 {
    alloc_init();
    var f = one(3);
    var a = await f;
    var b = await f;
    return a + b - 30;
}
syscall(60, main());
EOF
runs K1 34 "control: one-value async fns (one calls a multi-value fn and binds both), awaited twice"
cat > "$T/K2.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
async fn g(a) { var c = |x| { return (x, x + 1); }; var p = fncall1(c, a); return p + rethi(); }
fn main(): i64 { alloc_init(); return await g(16); }
syscall(60, main());
EOF
runs K2 33 "control: a closure's \`return (a, b)\` inside an async fn is the closure's"
cat > "$T/K3.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
#inline
fn two(a) { return (a, a + 1); }
async fn g(a) { var x, y = two(a); return x + y; }
fn main(): i64 { alloc_init(); return await g(16); }
syscall(60, main());
EOF
runs K3 33 "control: an #inline multi-value fn replayed in an async body"
row K4 'async fn g(a) { var t: (i64, i64) = (a, 1); return t; }'
refused K4 "cannot return tuple 't' (i64, i64) from an \`async fn\` - it returns one value" "control: \`return t;\` keeps 6.7.7's T5 refusal"
cat > "$T/K5.cyr" <<'EOF'
fn two(a) { return (a, a + 1); }
fn three(a): (i64, i64, i64) { return (a, 1, 2); }
fn r2(a) { ret2(a, a + 2); }
fn main(): i64 { var x, y = two(10); var p, q, r = three(20); var m, n = r2(1); return x + y + p + q + r + m + n - 14; }
syscall(60, main());
EOF
runs K5 34 "control: a sync fn's \`return (a, b)\`, \`: (T1, T2, T3)\` and ret2 under CYRIUS_ASYNC=1"

# --- axis F (6.7.13, D24 A): `return h(..);` forwarding a multi-value call ---
# the issue's repro, verbatim
cat > "$T/F1.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn h2(): (i64, i64) { return (1, 2); }
async fn g() { return h2(); }
fn h(): (i64, i64) { return (7, 9); }
fn main(): i64 {
    alloc_init();
    var f = g();
    var a0 = await f;
    var x, y = h();
    var a = await f;
    var b = rethi();
    return a * 10 + b;
}
syscall(60, main());
EOF
refused F1 "5:23: \`async fn g\` $M2" "the repro verbatim (it exited 19)"
row F2 'fn h2(a) { return (a, 2); }
async fn g(a) { return h2(a); }'
refused F2 "\`async fn g\` $M2" "an undeclared callee pass 1 counted (the issue's second form)"
row F3 'struct B { z; }
impl B { fn mk(self, a): (i64, i64) { return (a, 1); } }
async fn g(a) { var b = B { 0 }; return b.mk(a); }'
refused F3 "\`async fn g\` $M2" "a method callee"
row F4 'fn h2(a) { return (a, 2); }
async fn g(a) { return (h2(a)); }'
refused F4 "\`async fn g\` $M2" "wrapped: \`return (h2(a));\`"
row F6 'async fn g(a) { var s = await nopark(); return h(); }'
refused F6 "\`async fn g\` $M2" "a coroutine body"
row F7 'fn h3(a): (i64, i64, i64) { return (a, 1, 2); }
async fn g(a) { return ((h3(a))); }'
refused F7 "\`async fn g\` $M3" "three values, at depth 2"
row F8 'fn hg<T>(a: T): (T, T) { return (a, a + 1); }
async fn g(a) { return hg<i64>(a); }'
refused F8 "\`async fn g\` $M2" "a generic instance"
row FD 'async fn g(a): i64 { return h(); }'
refused FD "\`async fn g\` $M2" "a \`: i64\` async fn, as its \`return (a, b);\` is (6.7.11)"
cat > "$T/F5.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn h(): (i64, i64) { return (7, 9); }
fn one(a) { return a + 1; }
async fn g(a) { return one(a); }
async fn gp(a) { var fp = &h; return callptr(fp); }
async fn gc(a) { var c = |x| { return h(); }; var p = fncall1(c, a); return p; }
fn fw(a) { return h(); }
fn main(): i64 {
    alloc_init();
    var f = g(1);
    var a = await f;
    var b = await gp(0);
    var c = await gc(0);
    var x, y = fw(0);
    if (a != 2) { return 1; }
    if (b != 7) { return 2; }
    if (c != 7) { return 3; }
    if (y != 9) { return 4; }
    return 42;
}
syscall(60, main());
EOF
runs F5 42 "control: a one-value forward (2), \`callptr\` (7), a closure's own forward (7), a sync fn's (9)"
[ "$rows" -ge 29 ] || bad "only $rows rows ran (floor 29)"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails check(s) red"; exit 1; fi
echo "PASS: $G ($rows rows) — an \`async fn\` returning several values is refused by name: declared \`: (T1, T2[, T3])\` at its declaration, \`return (a, b[, c]);\` and \`ret2\` in an undeclared body, plain and coroutine; one-value async fns, a closure's and an #inline replay's multi-value return, a sync fn's and T5's tuple refusal unchanged"
