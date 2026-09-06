#!/bin/sh
# coroutine_midbody_suspend.sh — v6.5.69. An `async fn` that awaits MID-BODY suspends and
# resumes where it left off, with its locals intact.
#
# ⛔ WHY. v6.3.11 shipped `async`/`await` as deferred-then-forced Futures: `await e` lowered
# to a plain synchronous call to `future_force`, and a parked task re-entered its body FROM
# THE TOP — which `lib/async.cyr` states outright as the contract. So the natural shape (a
# loop that awaits mid-body and continues) COMPILED CLEAN AND DID NOTHING. Measured on the
# pre-fix compiler, a two-direction TTY relay written that way builds with zero errors,
# relays ZERO bytes, reports both live fds as closed, and hangs. That is the v6.5.63
# `#inline` class — a shipped syntax with nothing behind it — not a missing feature.
#
# ⭐ AXIS 1 ASSERTS A SIDE-EFFECT TRACE, NOT A VALUE, AND THAT IS THE WHOLE POINT. The
# obvious assertion — "the accumulator holds the right number" — PASSES ON A COMPILER WITH NO
# TRANSFORM AT ALL: restart-from-top re-runs the tail on the final entry, so the arithmetic
# still lands on 327. Only the ORDER and COUNT of side effects discriminate. Measured:
#     no transform : body top runs 3 times, trace 1121123
#     transform    : body top runs 1 time,  trace 123
# This is the v6.5.36 shape (a gate pinning the property while the mechanism is wrong) caught
# before it was written rather than after five bad releases.
#
# ⚠ `async`/`await` are gated behind CYRIUS_ASYNC=1, which is why this is a SHELL gate and
# not a `.tcyr`: the tcyr runner cannot set an env var, so the cross-OS leg cannot carry it.
# The transform itself is target-independent and its x86 guard is axis 4.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL coroutine_midbody_suspend: no build/cycc"; exit 1; }

# Build stage1 FROM SOURCE — the transform lives in the compiler being built, so a source
# revert must flip this gate RED rather than be masked by a stale build/cycc.
"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL coroutine_midbody_suspend: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
'

# ── axis 1 — TRACE + ENTRY COUNT (load-bearing) ──────────────────────────────────────────
cat > "$T/a1.cyr" <<EOF
${PRE}
var g_entries = 0;
var g_trace = 0;
fn nopark(): i64 { return 0; }
async fn steps(C): i64 {
    g_entries = g_entries + 1;
    var x = 7;
    g_trace = g_trace * 10 + 1;
    var s1 = await nopark();
    x = x + 20;
    g_trace = g_trace * 10 + 2;
    var s2 = await nopark();
    x = x + 300;
    g_trace = g_trace * 10 + 3;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C);
    var r2 = future_force(C);
    var r3 = future_force(C);
    if (g_entries != 1) { syscall(60, 100 + (g_entries & 0x3F)); }
    if (g_trace != 123) { syscall(60, 200); }
    if (r3 != 327) { syscall(60, 201); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a1.cyr" > "$T/a1" 2>"$T/a1.err" || {
  echo "FAIL coroutine_midbody_suspend axis1: probe did not compile"; grep -m2 '^error' "$T/a1.err"; exit 1; }
chmod +x "$T/a1"; timeout 30 "$T/a1"; got=$?
if [ $got -ne 0 ]; then
  echo "FAIL coroutine_midbody_suspend axis1: exit $got"
  echo "  101-163 = the body top ran that many times minus 100 (a real suspend runs it ONCE)"
  echo "  200     = the side-effect trace was not 123 — stages ran out of order or repeated"
  echo "  201     = a local did not survive a suspend (expected 7+20+300 = 327)"
  echo "  124     = it hung: a resume landed nowhere."
  exit 1
fi

# ── axis 2 — ANTI-VACUOUS: an `async fn` with NO mid-body await is UNCHANGED ─────────────
# ⛔ THIS ROW IS WHY THE TRANSFORM IS SELECTED BY THE BODY AND NOT BY THE KEYWORD. Applying
# it to every `async fn` breaks the ones that already work: `tests/fixtures/async/
# async_closure_generic.cyr` has `async fn compute(n)` whose body contains no `await` — it is
# awaited by its CALLER — so `n` would be read as a coroutine frame pointer.
cat > "$T/a2.cyr" <<EOF
${PRE}
async fn compute(n): i64 { return n + 41; }
fn main(): i64 {
    alloc_init();
    var v = await compute(1);
    syscall(60, v & 0xFF);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a2.cyr" > "$T/a2" 2>"$T/a2.err" || {
  echo "FAIL coroutine_midbody_suspend axis2: the no-await async fn did not compile"; grep -m2 '^error' "$T/a2.err"; exit 1; }
chmod +x "$T/a2"; "$T/a2"; g2=$?
[ "$g2" -eq 42 ] || { echo "FAIL coroutine_midbody_suspend axis2: deferred-then-forced async gave $g2, expected 42."; echo "  The transform fired on a body with no suspend point and mistook its parameter for a frame."; exit 1; }

# ── axis 3 — the shipped async fixtures must be bit-for-bit unaffected ───────────────────
# Broader than axis 2: these are the programs that exercised the v6.3.11 semantics before
# this release, and they are the regression surface a body-selected transform must not touch.
for fx in async_await async_closure_generic async_reactor async_taskjoin; do
  f="$R/tests/fixtures/async/$fx.cyr"
  [ -f "$f" ] || continue
  CYRIUS_ASYNC=1 "$T/stage1" < "$f" > "$T/n_$fx" 2>/dev/null
  CYRIUS_ASYNC=1 "$CC"       < "$f" > "$T/o_$fx" 2>/dev/null
  cmp -s "$T/n_$fx" "$T/o_$fx" || {
    echo "FAIL coroutine_midbody_suspend axis3: $fx.cyr now compiles to different bytes."
    echo "  A body with no mid-body await must take exactly the path it took before."
    exit 1; }
done

# ── axis 4 — REFUSALS: every gap is a diagnostic, never a quiet miscompile ───────────────
# A coroutine's locals live in the heap frame, so forms the frame does not handle must be
# hard errors. This project's standing rule (v6.5.63 `#inline`, v6.5.67 `: stack` enums) is
# that a capability gap says so.
refuse() {   # refuse <label> <needle>
  CYRIUS_ASYNC=1 "$T/stage1" < "$T/r.cyr" > /dev/null 2>"$T/r.err" && {
    echo "FAIL coroutine_midbody_suspend axis4: $1 COMPILED — it must be refused, not miscompiled."; exit 1; }
  grep -q "$2" "$T/r.err" || {
    echo "FAIL coroutine_midbody_suspend axis4: $1 was refused without naming the reason."
    sed -n 1,2p "$T/r.err" | sed 's/^/    /'; exit 1; }
}
cat > "$T/r.cyr" <<EOF
${PRE}
fn nopark(): i64 { return 0; }
async fn two(a, b): i64 { var s = await nopark(); return a + b; }
fn main(): i64 { alloc_init(); syscall(60, 0); return 0; }
var e = main();
EOF
refuse "a multi-parameter coroutine" "exactly one parameter"

cat > "$T/r.cyr" <<EOF
${PRE}
fn nopark(): i64 { return 0; }
async fn addr(C): i64 { var buf: i64[4]; var s = await nopark(); return load64(&buf); }
fn main(): i64 { alloc_init(); syscall(60, 0); return 0; }
var e = main();
EOF
refuse "taking the address of a coroutine local" "address of a local"

echo "PASS coroutine_midbody_suspend: mid-body suspend resumes in place (trace 123, body top ran once, locals survived) · no-await async fns bit-identical · multi-param and &local refused by name"
exit 0
