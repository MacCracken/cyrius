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
cd "$R" || { echo "FAIL: coroutine_midbody_suspend: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: coroutine_midbody_suspend: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$T/wine"   # axis 12's PE leg: a private prefix — its wineserver stopped and its server dir removed on exit
_wine_down() {
  [ -d "$WP" ] || return 0
  _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
  WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
  WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
  rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
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
chmod +x "$T/a1"; got=0; timeout 30 "$T/a1" || got=$?
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
chmod +x "$T/a2"; g2=0; "$T/a2" || g2=$?
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
${PRE}include "lib/simd.cyr"
fn nopark(): i64 { return 0; }
async fn simd(C): i64 { var v: f64v2 = f64v2_make(1, 2); var s = await nopark(); return f64v2_lane0(&v); }
fn main(): i64 { alloc_init(); syscall(60, 0); return 0; }
var e = main();
EOF
refuse "a SIMD local in a coroutine" "SIMD local"
# 6.6.6 — a value-form VECTOR PARAMETER, in a coroutine AND in a plain (no-await) async fn. The
# constructor captures every parameter as one 8-byte int, so the vector (XMM/V, or by pointer on
# Win64; 2-4 slots) was never captured: the filing's `c2(v, 5)` gave 50 and `a2(v, 5)` 35 for 95,
# exit 0, no diagnostic — while the SIMD LOCAL above was refused. Every vector class, both forms,
# and the diagnostic must NAME the parameter. Then the documented way round it — a pointer — must
# compile and compute. Mutation: drop the `_refuse_async_simd_param` call -> RED ("a f64v2
# parameter of a coro async fn COMPILED").
for vt in f64v2 f32v4 f64v4 i32v4; do
  for form in coro plain; do
    aw=''; [ "$form" = coro ] && aw='var s = await nopark(); '
    cat > "$T/r.cyr" <<EOF
${PRE}include "lib/simd.cyr"
fn nopark(): i64 { return 0; }
async fn av(a, vec: $vt, b): i64 { ${aw}return load64(&vec) + a + b; }
fn main(): i64 { alloc_init(); syscall(60, 0); return 0; }
var e = main();
EOF
    refuse "a $vt parameter of a $form async fn" "async fn parameter 'vec' is a value-form vector"
  done
done
cat > "$T/r.cyr" <<EOF
${PRE}include "lib/simd.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }
async fn c2(pv, a): i64 { var s = await nopark(); return load64(pv) * 10 + a; }
async fn a2(pv, a): i64 { return load64(pv) * 10 + a; }
fn main(): i64 {
    alloc_init();
    var v = f64v2_make(9, 0);
    var C = c2(&v, 5);
    future_force(C); future_force(C);
    var x = future_force(C);
    var F = a2(&v, 5);
    var z = f64v2_make(3, 4);
    var y = future_force(F);
    if (x != 95) { return 1; }
    if (y != 95) { return 2; }
    return 0;
}
var e = main();
syscall(60, e);
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/r.cyr" > "$T/rp" 2>"$T/rp.err" || {
  echo "FAIL coroutine_midbody_suspend axis4: the pointer-to-vector async form did not compile"; grep -m2 '^error' "$T/rp.err"; exit 1; }
[ -s "$T/rp" ] || { echo "FAIL coroutine_midbody_suspend axis4: pointer-to-vector probe is empty"; exit 1; }
chmod +x "$T/rp"; grp=0; "$T/rp" > /dev/null 2>&1 || grp=$?
[ "$grp" -eq 0 ] || { echo "FAIL coroutine_midbody_suspend axis4: the pointer-to-vector async fns exit $grp (1 = coroutine, 2 = plain, want 95 each)"; exit 1; }

# 6.6.16 (C7) — a STRUCT over 8 B passed BY VALUE to an `async fn`, in a coroutine AND in a plain
# async fn. Such a parameter is copied in the callee's prologue (`_sptr_params_localize`), and an
# async body runs at force time: the copy would read the caller's struct LATE, and a coroutine
# impl re-runs its prologue on every resume. Before 6.6.16 it compiled and the body read and wrote
# the CALLER's struct at force time (`f(p)` with p.x 3, then `p.x = 10`, then `await` gave 11).
# The diagnostic names the parameter AND the spelling to use. Then the anti-vacuous half: a
# `p: *P3` parameter, a struct of 8 B or less and a `Str` (a heap handle, 16 B by name) still
# compile and compute. Mutation: drop the `_refuse_async_struct_param` call in `_param_record`
# (parse/fn.cyr) -> RED ("a 24-byte struct parameter of a coro async fn COMPILED").
for sz in 24 16; do
  flds='x; y; z;'; [ "$sz" = 16 ] && flds='x; y;'
  for form in coro plain; do
    aw=''; [ "$form" = coro ] && aw='var s = await nopark(); '
    cat > "$T/r.cyr" <<EOF
${PRE}
struct Pv { $flds }
fn nopark(): i64 { return 0; }
async fn sp(a, pv: Pv, b): i64 { ${aw}return pv.x + a + b; }
fn main(): i64 { alloc_init(); syscall(60, 0); return 0; }
var e = main();
EOF
    refuse "a $sz-byte struct parameter of a $form async fn" "async fn parameter 'pv' is a struct passed by value"
    grep -qF '(`pv: *Pv`)' "$T/r.err" || {
      echo "FAIL coroutine_midbody_suspend axis4: the $sz-byte struct parameter refusal does not name the spelling (pv: *Pv)"
      sed -n 1,2p "$T/r.err" | sed 's/^/    /'; exit 1; }
  done
done
sp_a=4; sp_x=3; sp_b=5
cat > "$T/r.cyr" <<EOF
${PRE}include "lib/str.cyr"
struct P3 { x; y; z; }
struct B1 { x; }
fn nopark(): i64 { return 0; }
async fn cp(a, pp: *P3): i64 { var s = await nopark(); pp.x = pp.x + a; return pp.x; }
async fn ap(a, pp: *P3): i64 { pp.x = pp.x + a; return pp.x; }
async fn cb(a, b1: B1): i64 { var s = await nopark(); b1.x = b1.x + a; return b1.x; }
async fn ab(a, b1: B1): i64 { b1.x = b1.x + a; return b1.x; }
async fn sl(st: Str): i64 { return str_len(st); }
fn main(): i64 {
    alloc_init();
    var p: P3; p.x = $sp_x; p.y = 0; p.z = 0;
    var C = cp($sp_a, &p);
    future_force(C); future_force(C);
    var x = future_force(C);
    var y = future_force(ap($sp_a, &p));
    var b: B1; b.x = $sp_b;
    var D = cb($sp_a, b);
    future_force(D); future_force(D);
    var z = future_force(D);
    var w = future_force(ab($sp_a, b));
    var v = future_force(sl(str_from("abcde")));
    if (x != $(( sp_x + sp_a ))) { return 1; }
    if (y != $(( sp_x + 2 * sp_a ))) { return 2; }
    if (p.x != $(( sp_x + 2 * sp_a ))) { return 3; }
    if (z != $(( sp_b + sp_a ))) { return 4; }
    if (w != $(( sp_b + sp_a ))) { return 5; }
    if (b.x != $sp_b) { return 6; }
    if (v != 5) { return 7; }
    return 0;
}
var e = main();
syscall(60, e);
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/r.cyr" > "$T/rs" 2>"$T/rs.err" || {
  echo "FAIL coroutine_midbody_suspend axis4: a *P3 / <= 8 B / Str parameter of an async fn did not compile"; grep -m2 '^error' "$T/rs.err"; exit 1; }
[ -s "$T/rs" ] || { echo "FAIL coroutine_midbody_suspend axis4: the struct-parameter anti-vacuous probe is empty"; exit 1; }
chmod +x "$T/rs"; grs=0; "$T/rs" > /dev/null 2>&1 || grs=$?
[ "$grs" -eq 0 ] || { echo "FAIL coroutine_midbody_suspend axis4: the *P3 / <= 8 B / Str async parameters exit $grs (1-3 = *P3, 4-6 = B1, 7 = Str)"; exit 1; }

# ── axis 4b — a BY-VALUE STRUCT RETURN from an `async fn` (6.6.6) ────────────────────────
# A Future carries ONE i64 (`future_force` returns what the body left in rax), so the two
# by-value struct return ABIs never arrive: over 16 B the hidden retptr is consumed building
# the Future (the constructor is itself classified as a retptr callee) and the body writes
# through whatever the first argument register held; 9-16 B is rax:rdx and the Future drops
# rdx. BOTH WERE SILENT. Measured on the pre-fix compiler at 6.6.5 with this exact fixture:
# the 24 B `P3` printed 0 and exited 0, and the 16 B `P2` came back holding `.x` only.
# A struct of 8 B or less IS one i64, so it must keep working — that is the anti-vacuous half,
# and it is why the refusal keys on `_ret_agg_class` and not on "returns a struct".
# Mutation: drop the `_refuse_async_struct_return` call in parse/fn.cyr -> RED
# ("a 24-byte struct return COMPILED"). Ledger: mutated tree RED, real tree GREEN (2026-09-19).
for sz in 24 16; do
  flds='x; y; z;'; [ "$sz" = 16 ] && flds='x; y;'
  cat > "$T/r.cyr" <<EOF
${PRE}
struct Pv { $flds }
async fn mkv(a, b): Pv { var p: Pv; p.x = a; p.y = b; return p; }
fn main(): i64 { alloc_init(); syscall(60, future_force(mkv(4, 5)) & 0xFF); return 0; }
var e = main();
EOF
  refuse "a $sz-byte struct return from an async fn" "returns a struct by value, and a Future carries one i64"
done
# ... and the <= 8 B struct, which IS one i64, still compiles AND computes. Expected value is
# built here by shell arithmetic from the same two inputs, not copied from the probe.
as_a=17; as_b=23; as_want=$(( as_a + as_b ))
cat > "$T/r8.cyr" <<EOF
${PRE}
struct P1 { x; }
async fn mk1(a, b): P1 { var p: P1; p.x = a + b; return p; }
fn main(): i64 { alloc_init(); syscall(60, future_force(mk1($as_a, $as_b)) & 0xFF); return 0; }
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/r8.cyr" > "$T/r8" 2>"$T/r8.err" || {
  echo "FAIL coroutine_midbody_suspend axis4b: the 8-byte struct return did not compile"; grep -m2 '^error' "$T/r8.err"; exit 1; }
[ -s "$T/r8" ] || { echo "FAIL coroutine_midbody_suspend axis4b: 8-byte struct-return probe is empty"; exit 1; }
chmod +x "$T/r8"; g8=0; "$T/r8" > /dev/null 2>&1 || g8=$?
[ "$g8" -eq "$as_want" ] || {
  echo "FAIL coroutine_midbody_suspend axis4b: the 8-byte struct return exits $g8, want $as_want"; exit 1; }

# ── axis 4c — a VALUE-FORM VECTOR RETURN from an `async fn` (6.6.6, bite 16 review) ──────
# The same "a Future carries ONE i64" limit as 4b, one type class over — and it survived 4b
# because that refusal keys on `_ret_agg_class`, which answers only for structs. A vector
# travels in XMM/V (SysV/aarch64) or by pointer (Win64) and never in rax. Measured on the
# compiler that shipped 16a: `async fn av(a,b): f64v2 { ... return v; }` +
# `future_force(av(7,9))` compiled with ZERO diagnostics and yielded 0, where the
# byte-identical SYNC fn yields 7 — that sync control is the anti-vacuous half below, so a
# refusal that merely broke vectors outright would not pass this axis. Both size classes
# (16 B / 32 B) and both element kinds, because `_is_simd_any` is a BAND test.
# Mutation: drop the `_refuse_async_vec_return` call in parse/fn.cyr -> RED
# ("an f64v2 return COMPILED"). Ledger: mutated tree RED, real tree GREEN (2026-09-19).
for vt in f64v2 f32v4 f64v4 i32v4; do
  cat > "$T/r.cyr" <<EOF
${PRE}include "lib/simd.cyr"
async fn av(a, b): $vt { var v: $vt; store64(&v, a); store64(&v + 8, b); return v; }
fn main(): i64 { alloc_init(); var g = future_force(av(7, 9)); syscall(60, load64(&g) & 0xFF); return 0; }
var e = main();
EOF
  refuse "an $vt return from an async fn" "returns a value-form vector, which an .async fn. does not capture yet"
done
# ... and the byte-identical SYNCHRONOUS fn still compiles AND computes, so what is refused is
# the `async`, not the vector. Inputs are shell variables; the probe never carries a literal.
vs_a=7; vs_b=9
cat > "$T/rv.cyr" <<EOF
${PRE}include "lib/simd.cyr"
fn av(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn main(): i64 { alloc_init(); var g: f64v2 = av($vs_a, $vs_b); syscall(60, load64(&g) & 0xFF); return 0; }
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/rv.cyr" > "$T/rv" 2>"$T/rv.err" || {
  echo "FAIL coroutine_midbody_suspend axis4c: the SYNC vector return did not compile"; grep -m2 '^error' "$T/rv.err"; exit 1; }
[ -s "$T/rv" ] || { echo "FAIL coroutine_midbody_suspend axis4c: sync vector-return probe is empty"; exit 1; }
chmod +x "$T/rv"; gv=0; "$T/rv" > /dev/null 2>&1 || gv=$?
[ "$gv" -eq "$vs_a" ] || {
  echo "FAIL coroutine_midbody_suspend axis4c: the sync vector return exits $gv, want $vs_a"; exit 1; }

# ── axis 5 — MULTI-PARAMETER coroutines (v6.5.70; refused outright at v6.5.69) ───────────
# The constructor pre-binds arguments into coroutine-frame slots. This is the SAME machinery
# as the arity-7 fix in the same release — the constructor could not place arguments into
# frame slots at all, whether those slots were on the stack or in a coroutine frame.
cat > "$T/a5.cyr" <<EOF
${PRE}
var g5 = 0;
fn nopark(): i64 { return 0; }
async fn addup(a, b, c): i64 {
    g5 = g5 + 1;
    var acc = a;
    var s1 = await nopark();
    acc = acc + b;
    var s2 = await nopark();
    acc = acc + c;
    return acc;
}
fn main(): i64 {
    alloc_init();
    var C = addup(5, 60, 200);
    future_force(C); future_force(C);
    var r = future_force(C);
    if (g5 != 1) { syscall(60, 100 + g5); }
    if (r != 265) { syscall(60, 201); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a5.cyr" > "$T/a5" 2>"$T/a5.err" || {
  echo "FAIL coroutine_midbody_suspend axis5: the 3-parameter coroutine did not compile"; grep -m2 '^error' "$T/a5.err"; exit 1; }
chmod +x "$T/a5"; g5=0; timeout 30 "$T/a5" || g5=$?
[ "$g5" -eq 0 ] || { echo "FAIL coroutine_midbody_suspend axis5: 3-param coroutine exit $g5 (201 = a+b+c wrong, 101+ = body top re-ran)"; exit 1; }

# ── axis 6 — a suspend INSIDE A LOOP, which is the filed consumer shape ──────────────────
# stiva's `exec -it` relay is a loop that awaits mid-body; a transform that only handled
# straight-line bodies would pass every axis above and still not deliver the feature.
cat > "$T/a6.cyr" <<EOF
${PRE}
var g6 = 0;
fn ready(): i64 { return 0; }
async fn pump(n): i64 {
    g6 = g6 + 1;
    var moved = 0;
    var i = 0;
    while (i < n) {
        var chunk = i + 1;
        var s = await ready();
        moved = moved + chunk;
        i = i + 1;
    }
    return moved;
}
fn main(): i64 {
    alloc_init();
    var C = pump(4);
    var r = 0;
    var turns = 0;
    while (turns < 5) { r = future_force(C); turns = turns + 1; }
    if (g6 != 1) { syscall(60, 100 + g6); }
    if (r != 10) { syscall(60, 201); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a6.cyr" > "$T/a6" 2>"$T/a6.err" || {
  echo "FAIL coroutine_midbody_suspend axis6: the in-loop suspend did not compile"; grep -m2 '^error' "$T/a6.err"; exit 1; }
chmod +x "$T/a6"; g6=0; timeout 30 "$T/a6" || g6=$?
[ "$g6" -eq 0 ] || { echo "FAIL coroutine_midbody_suspend axis6: suspend inside a loop gave $g6 (201 = accumulator wrong across iterations)"; exit 1; }

# ── axis 7 — &local across a suspend (v6.5.70; refused at v6.5.69) ───────────────────────
cat > "$T/a7.cyr" <<EOF
${PRE}
fn nopark(): i64 { return 0; }
async fn buffed(seed): i64 {
    var buf: i64[4];
    store64(&buf, seed);
    store64(&buf + 8, seed * 2);
    var s1 = await nopark();
    store64(&buf + 16, seed * 3);
    var s2 = await nopark();
    return load64(&buf) + load64(&buf + 8) + load64(&buf + 16);
}
fn main(): i64 {
    alloc_init();
    var C = buffed(7);
    future_force(C); future_force(C);
    var r = future_force(C);
    if (r != 42) { syscall(60, 201); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a7.cyr" > "$T/a7" 2>"$T/a7.err" || {
  echo "FAIL coroutine_midbody_suspend axis7: &local in a coroutine did not compile"; grep -m2 '^error' "$T/a7.err"; exit 1; }
chmod +x "$T/a7"; g7=0; timeout 30 "$T/a7" || g7=$?
[ "$g7" -eq 0 ] || { echo "FAIL coroutine_midbody_suspend axis7: a local array did not survive two suspends (exit $g7)"; exit 1; }

# ── axis 8 — ARITY LADDER: the v6.5.69 silent miscompile ─────────────────────────────────
# `async fn` at 7+ parameters returned code-address-shaped garbage, exit 0, no diagnostic,
# while the 6-parameter async form and the PLAIN 7-parameter fn were both correct. TWO causes:
# the constructor never spilled parameters past the sixth, and `future_force` laddered only
# `fncall0..6` and fell through. The plain fn at the same arity is the control on every rung —
# it is what isolated the defect to the async lowering in the first place.
cat > "$T/a8.cyr" <<EOF
${PRE}
async fn a6(a,b,c,d,e,f): i64 { return a+b+c+d+e+f; }
async fn a7(a,b,c,d,e,f,g): i64 { return a+b+c+d+e+f+g; }
async fn a8(a,b,c,d,e,f,g,h): i64 { return a+b+c+d+e+f+g+h; }
fn p7(a,b,c,d,e,f,g): i64 { return a+b+c+d+e+f+g; }
fn p8(a,b,c,d,e,f,g,h): i64 { return a+b+c+d+e+f+g+h; }
fn main(): i64 {
    alloc_init();
    if (await a6(1,2,3,4,5,6) != 21) { syscall(60, 60); }
    if (p7(1,2,3,4,5,6,7) != 28) { syscall(60, 70); }
    if (await a7(1,2,3,4,5,6,7) != 28) { syscall(60, 71); }
    if (p8(1,2,3,4,5,6,7,8) != 36) { syscall(60, 80); }
    if (await a8(1,2,3,4,5,6,7,8) != 36) { syscall(60, 81); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a8.cyr" > "$T/a8" 2>"$T/a8.err" || {
  echo "FAIL coroutine_midbody_suspend axis8: the arity ladder did not compile"; grep -m2 '^error' "$T/a8.err"; exit 1; }
chmod +x "$T/a8"; g8=0; timeout 30 "$T/a8" || g8=$?
[ "$g8" -eq 0 ] || {
  echo "FAIL coroutine_midbody_suspend axis8: exit $g8 — 71/81 = the async form is wrong at that"
  echo "  arity while 60/70/80 (the 6-param async and the PLAIN fns) would have been correct."
  exit 1; }

# ── axis 9 — THE ADDRESS OF A STRUCT LOCAL IN A COROUTINE (6.6.5) ────────────────────────
# ⛔ `EFLADDR` / `EFLADDR_X1` emitted `lea rN, [rbp - disp]` unconditionally, so every
# struct-field access and every method `self` inside a suspending `async fn` addressed THE
# STACK FRAME — the one thing a coroutine does not keep across a suspend. It read as correct
# for years only because the resumed frame usually lands back on the same bytes.
# ⛔ AND THE FIRST CUT OF THE FIX SPLIT ONE VARIABLE IN HALF: `EFLADDR_X1` learned the heap
# frame while `ELOAD_LOCAL_ADDR` (the `&name` path) kept the stack form, because v6.5.70 had
# guarded its recovery on `_cur_fn_regalloc == 0` — a condition that is NEVER true in an
# `async fn` body (it reserves the five callee-saved slots like any other fn), so that
# recovery had never once fired. The store went to `r11+off` and the read to `rbp-disp`:
# `peek(&q)` answered 0 where 11 was right. Hence `&q` AND `q.v` in the SAME assertion.
#
# ⭐ `trash()` IS LOAD-BEARING. Without a stack-destroying recursion between the forces, the
# resumed frame still holds the right bytes and the STACK form passes — the same false-green
# shape axis 1 exists for. ⭐ TWO INSTANCES SEEDED DIFFERENTLY, interleaved, so a shared or
# aliased slot shows up as one answering the other's value. ⭐ EXPECTED VALUES COME FROM
# NON-ASYNC CONTROL FNS with identical bodies, never from a constant written here.
#
# MUTATION LEDGER (each rebuilt to the self-host fixpoint and measured):
#   * the 6.6.4 compiler                          -> exit 91 (the single-slot `&q` leg).
#   * remove the two `_ECORO_LEA` call sites      -> exit 91 (the split, the other way round:
#     the field store goes to the stack while `&q` reaches the heap frame).
#   * restore v6.5.70's `_cur_fn_regalloc == 0` guard on ELOAD_LOCAL_ADDR's recovery
#                                                 -> exit 91 (the split as shipped in the
#     first cut of this bite).
#   * refuse span > 1 instead of recovering it    -> axis 9 FAILS TO COMPILE, which is how the
#     refusal was caught as a capability regression: 6.6.4 compiled `two`/`pre` and answered
#     correctly, so a diagnostic there takes working code away.
#   * move `SLAGG` in `_STRUCT_LIT_LOCAL` back BELOW the initialisers (i.e. the 6.6.5 bite-4
#     first cut)                                  -> exit 98. Found by review round 2: the
#     rows below did not exist, so a literal whose OWN stores went to the wrong slots — and up
#     to `nslots-1` slots PAST its block, over the next local — read GREEN here. (96/97, the
#     single-word rows, stay green under this mutant: a span of 1 bases at the same slot
#     either way, which is exactly why the multi-word rows are not redundant with them.)
#   * keep `_sl_zero_slots` addressing slot-by-slot (`EFLADDR_X1(named - k)`) while the span
#     IS recorded early                           -> NOT CAUGHT, recorded here because that is
#     worth knowing: it zeroes the block's lowest heap slot twice and never zeroes the named
#     one, so the only bytes that differ are a struct's PADDING, and a coroutine frame comes
#     from freshly-zeroed pages. The one-base form is still what ships — the zero-fill and the
#     field stores must ask the same question about where the block is — but no row here
#     proves it, and inventing one that "passes" for a mutant it cannot see is the false-green
#     shape this file exists to reject.
#
# ⭐ THE LITERAL ROWS ARE NOT A DUPLICATE OF THE TYPED ONES. `var p: P2;` and
# `var p = P2 {..}` are DIFFERENT registration paths: the typed form records the aggregate's
# span at registration, the literal form emits a zero-fill and every field store first. Only
# the second can disagree with itself about where the block is, and it did.
cat > "$T/a9.cyr" <<EOF
${PRE}
struct S1 { v; }
struct P2 { x; y; }
struct W4 { a; b; c; d; }
fn nopark(): i64 { return 0; }
fn peek(p) { return load64(p); }
fn trash(n) { var pad[512]; store64(&pad, 123456789); if (n > 0) { trash(n - 1); } return load64(&pad); }
fn ctrl_one(seed) { var q: S1; q.v = seed; return peek(&q) + q.v; }
fn ctrl_two(seed) { var p: P2; p.x = seed; p.y = seed * 2; return p.x * 10 + p.y; }
fn ctrl_lit1(seed) { var q = S1 { seed }; return peek(&q) + q.v; }
fn ctrl_lit4(seed) { var p = W4 { seed, seed * 2, seed * 3, seed * 4 }; return p.a * 1000 + p.b * 100 + p.c * 10 + p.d; }
async fn one(seed): i64 {
    var q: S1;
    q.v = seed;
    var s1 = await nopark();
    return peek(&q) + q.v;
}
async fn two(seed): i64 {
    var p: P2;
    p.x = seed; p.y = seed * 2;
    var s1 = await nopark();
    return p.x * 10 + p.y;
}
async fn pre(seed): i64 {
    var p: P2;
    p.x = seed; p.y = seed * 2;
    var t = p.x * 10 + p.y;
    var s1 = await nopark();
    return t;
}
async fn lit1(seed): i64 {
    var q = S1 { seed };
    var s1 = await nopark();
    return peek(&q) + q.v;
}
async fn lit4(seed): i64 {
    var p = W4 { seed, seed * 2, seed * 3, seed * 4 };
    var guard = 7777;
    var s1 = await nopark();
    if (guard != 7777) { return 0 - 1; }
    return p.a * 1000 + p.b * 100 + p.c * 10 + p.d;
}
fn main(): i64 {
    alloc_init();
    var A = one(5); var B = one(9);
    future_force(A); future_force(B);
    trash(40);
    var ra = future_force(A); var rb = future_force(B);
    if (ra != ctrl_one(5)) { syscall(60, 91); }
    if (rb != ctrl_one(9)) { syscall(60, 92); }
    var C = two(3); var D = two(6);
    future_force(C); future_force(D);
    trash(40);
    var rc = future_force(C); var rd = future_force(D);
    if (rc != ctrl_two(3)) { syscall(60, 93); }
    if (rd != ctrl_two(6)) { syscall(60, 94); }
    var E = pre(4);
    future_force(E);
    trash(40);
    var re = future_force(E);
    if (re != ctrl_two(4)) { syscall(60, 95); }
    var F = lit1(5); var G = lit1(9);
    future_force(F); future_force(G);
    trash(40);
    var rf = future_force(F); var rg = future_force(G);
    if (rf != ctrl_lit1(5)) { syscall(60, 96); }
    if (rg != ctrl_lit1(9)) { syscall(60, 97); }
    var H = lit4(1); var I = lit4(2);
    future_force(H); future_force(I);
    trash(40);
    var rh = future_force(H); var ri = future_force(I);
    if (rh != ctrl_lit4(1)) { syscall(60, 98); }
    if (ri != ctrl_lit4(2)) { syscall(60, 99); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a9.cyr" > "$T/a9" 2>"$T/a9.err" || {
  echo "FAIL coroutine_midbody_suspend axis9: a struct local in a suspending async fn did not compile"
  echo "  (a REFUSAL here is a capability regression — 6.6.4 compiled this and answered correctly)"
  grep -m2 '^error' "$T/a9.err"; exit 1; }
[ -s "$T/a9" ] || { echo "FAIL coroutine_midbody_suspend axis9: empty binary"; exit 1; }
chmod +x "$T/a9"; g9=0; timeout 30 "$T/a9" || g9=$?
[ "$g9" -eq 0 ] || {
  echo "FAIL coroutine_midbody_suspend axis9: exit $g9 — 91/92 = \`&q\` and \`q.v\` disagree on which"
  echo "  frame a single-slot struct local lives in; 93/94 = a multi-word struct local reads the wrong"
  echo "  heap slots; 95 = a struct used only BEFORE the first suspend; 96/97 = a single-word struct"
  echo "  LITERAL; 98/99 = a 4-word literal (and its stores running past the block into the next"
  echo "  local, which the \`guard\` word catches). Controls are the non-async fns."
  exit 1; }

# ── axis 10 — THE REACTOR RESUMES A COROUTINE WHOSE AWAIT DID NOT PARK (6.6.11) ──────────
# ⛔ Every backend's `_async_step` marked a task that returned still-READY as DONE. A coroutine
# that suspends at `await inner(a)` (a plain async fn) or at `await f()` (a call that does not
# park) returns 0 from that suspend while still READY — so under async_spawn_future + async_run
# it was finished with 0 and never resumed. Measured at 6.6.10: `outer(4)` gave 0 (state DONE)
# where future_force gave 41. The guide wrote the defect down as a rule ("force such a coroutine
# yourself"). Rows 1/2: the values, through async_run AND task_join. Row 3: a coroutine that
# keeps awaiting non-parking work is run every step, so the reactor must still poll its fds or a
# parked task starves — the waiter here is what ends the spinner, so without the non-blocking
# poll the probe HANGS (timeout 124). Row 4: the same starvation for async_with_timeout's
# deadline sentinel.
# Mutations (measured 6.6.11): drop the `_async_coro_pending` keep in lib/async.cyr's
# _async_step -> exit 1; drop its `elif (kept == 1)` non-blocking poll -> 124.
cat > "$T/a10.cyr" <<EOF
${PRE}
var g_flag = 0;
var g_pfd: i64[2];
var g_wstep = 0;
fn nopark(): i64 { return 0; }
async fn inner(a): i64 { return a * 10; }
async fn outer(a): i64 {
    var v = await inner(a);
    var s = await nopark();
    return v + s + 1;
}
async fn spinner(n): i64 {
    var turns = 0;
    while (g_flag == 0) { var s = await nopark(); turns = turns + 1; }
    return n;
}
fn waiter(rt): i64 {
    if (g_wstep == 0) { g_wstep = 1; async_wait_fd(rt, load32(&g_pfd)); return 0; }
    g_flag = 1;
    return 7;
}
fn writer(a): i64 { sys_write(load32(&g_pfd + 4), "x", 1); return 0; }
fn main(): i64 {
    alloc_init();
    var rt = async_new();
    var h = async_spawn_future(rt, outer(4));
    async_run(rt);
    if (load64(h + 40) != 41) { return 1; }
    var rt2 = async_new();
    var h2 = async_spawn_future(rt2, outer(6));
    if (task_join(rt2, h2) != 61) { return 2; }
    sys_pipe(&g_pfd);
    var rt3 = async_new();
    var hs = async_spawn_future(rt3, spinner(33));
    async_spawn(rt3, &waiter, rt3);
    async_spawn(rt3, &writer, 0);
    async_run(rt3);
    if (load64(hs + 40) != 33) { return 3; }
    g_flag = 0;
    var rt4 = async_new();
    var hf = async_spawn_future(rt4, spinner(5));
    if (async_with_timeout(rt4, hf, 100) != 0) { return 4; }
    return 0;
}
var e = main();
syscall(60, e);
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a10.cyr" > "$T/a10" 2>"$T/a10.err" || {
  echo "FAIL coroutine_midbody_suspend axis10: the reactor probe did not compile"; grep -m2 '^error' "$T/a10.err"; exit 1; }
[ -s "$T/a10" ] || { echo "FAIL coroutine_midbody_suspend axis10: empty binary"; exit 1; }
chmod +x "$T/a10"; g10=0; timeout 30 "$T/a10" > /dev/null 2>&1 || g10=$?
[ "$g10" -eq 0 ] || {
  echo "FAIL coroutine_midbody_suspend axis10: exit $g10 — 1 = async_run finished outer() with its"
  echo "  suspend's 0 (want 41); 2 = task_join the same (want 61); 3 = the spinner's value was lost;"
  echo "  4 = async_with_timeout did not report the deadline; 124 = a task parked on an fd (or the"
  echo "  deadline sentinel) starved behind a coroutine that never parks."
  exit 1; }

# ── axis 11 — A CLOSURE'S CAPTURE OF A MULTI-WORD LOCAL IN A COROUTINE (6.7.9) ─────────────
# ⛔ The closure's env copy walked its SOURCE by slot index (word k from slot base - k, the stack
# layout) and wrote its DESTINATION by word offset, the one consumer of axis 9's aggregate that did
# not ask `_ECORO_AGG_OFF` where the block is. The coroutine frame ascends with the slot index, so
# every captured struct, tuple, u128, array and slice reached the closure with its words REVERSED:
# `P2 { 1, 2 }` read as `{ 2, 1 }`, silently, since 6.6.8 (6.6.0 - 6.6.7 crashed on it). The copy
# now reads the words through the aggregate's address, as every other coroutine consumer does.
# Rows (exit 100 + row): 1 a 2-word struct literal, the closure made AFTER the await (the filed
# repro); 2 a 3-word literal, the closure made BEFORE it; 3 a typed `var p: P2;`; 4 / 5 a 2- and a
# 3-tuple; 6 a 24-byte struct from a call; 7 a copy-init `var q: P2 = p;`; 8 a u128 (its words
# through `&w`); 9 an `i64[3]`; 10 a slice; 11 scalars on both sides of a struct; 12 a nested
# closure capturing through the outer one's env. Expected values come from the NON-ASYNC control
# fns with identical bodies; `trash()` runs between the forces, as in axis 9.
# MUTATION LEDGER (each rebuilt from the mutated src and measured, 2026-10-11):
#   * the pre-fix compiler, or the coroutine arm of `_cl_emit_cap_word` disabled (the slot walk)
#                                                 -> exit 101, and EVERY row red on its own
#     (the probe rewritten to report all twelve); tuple_checked.sh AS3 red too.
#   * `EFLADDR(S, base - k)` per word (a slot walk spelled as addresses) -> exit 101.
#   * the arm taken for every `w > 1` capture, coroutine or not -> GREEN (tuple_checked.sh too, its
#     aarch64 / cx / PE legs included): on the stack `&base + k*8` IS slot base - k. The
#     `_cur_fn_coro` test keeps the stack form byte-identical; it is not what makes this right.
cat > "$T/a11.cyr" <<EOF
${PRE}
include "lib/fnptr.cyr"
include "lib/slice.cyr"
struct P2 { x; y; }
struct P3 { x; y; z; }
var g_buf[16];
fn nopark(): i64 { return 0; }
fn trash(n) { var pad[512]; store64(&pad, 123456789); if (n > 0) { trash(n - 1); } return load64(&pad); }
fn mk3(a, b, c): P3 { var r = P3 { a, b, c }; return r; }
fn run2(F): i64 { future_force(F); trash(40); return future_force(F); }
async fn lit2(s): i64 { var p = P2 { s, s + 5 }; var s1 = await nopark(); var c = || p.y * 100 + p.x; return fncall0(c); }
fn ctrl_lit2(s): i64 { var p = P2 { s, s + 5 }; var c = || p.y * 100 + p.x; return fncall0(c); }
async fn lit3(s): i64 { var q = P3 { s, s + 1, s + 2 }; var d = || q.z * 10000 + q.y * 100 + q.x; var s1 = await nopark(); return fncall0(d); }
fn ctrl_lit3(s): i64 { var q = P3 { s, s + 1, s + 2 }; var d = || q.z * 10000 + q.y * 100 + q.x; return fncall0(d); }
async fn typed2(s): i64 { var p: P2; p.x = s; p.y = s * 3; var s1 = await nopark(); var c = || p.y * 100 + p.x; return fncall0(c); }
fn ctrl_typed2(s): i64 { var p: P2; p.x = s; p.y = s * 3; var c = || p.y * 100 + p.x; return fncall0(c); }
async fn tup2(s): i64 { var t = (s, s + 7); var s1 = await nopark(); var c = || t.1 * 100 + t.0; return fncall0(c); }
fn ctrl_tup2(s): i64 { var t = (s, s + 7); var c = || t.1 * 100 + t.0; return fncall0(c); }
async fn tup3(s): i64 { var t = (s, s + 1, s + 2); var c = || t.2 * 10000 + t.1 * 100 + t.0; var s1 = await nopark(); return fncall0(c); }
fn ctrl_tup3(s): i64 { var t = (s, s + 1, s + 2); var c = || t.2 * 10000 + t.1 * 100 + t.0; return fncall0(c); }
async fn call3(s): i64 { var p = mk3(s, s + 2, s + 4); var s1 = await nopark(); var c = || p.z * 10000 + p.y * 100 + p.x; return fncall0(c); }
fn ctrl_call3(s): i64 { var p = mk3(s, s + 2, s + 4); var c = || p.z * 10000 + p.y * 100 + p.x; return fncall0(c); }
async fn copy2(s): i64 { var p = P2 { s, s + 4 }; var q: P2 = p; var s1 = await nopark(); var c = || q.y * 100 + q.x; return fncall0(c); }
fn ctrl_copy2(s): i64 { var p = P2 { s, s + 4 }; var q: P2 = p; var c = || q.y * 100 + q.x; return fncall0(c); }
async fn wide(s): i64 { var w: u128 = 0; store64(&w, s); store64(&w + 8, s + 6); var s1 = await nopark(); var c = || load64(&w + 8) * 100 + load64(&w); return fncall0(c); }
fn ctrl_wide(s): i64 { var w: u128 = 0; store64(&w, s); store64(&w + 8, s + 6); var c = || load64(&w + 8) * 100 + load64(&w); return fncall0(c); }
async fn arr3(s): i64 { var a: i64[3]; a[0] = s; a[1] = s + 1; a[2] = s + 2; var s1 = await nopark(); var c = || a[2] * 10000 + a[1] * 100 + a[0]; return fncall0(c); }
fn ctrl_arr3(s): i64 { var a: i64[3]; a[0] = s; a[1] = s + 1; a[2] = s + 2; var c = || a[2] * 10000 + a[1] * 100 + a[0]; return fncall0(c); }
async fn sl(s): i64 { var v: [u8] = 0; slice_set(&v, &g_buf, s); var s1 = await nopark(); var c = || slice_len(&v) * 10 + (slice_ptr(&v) == &g_buf); return fncall0(c); }
fn ctrl_sl(s): i64 { var v: [u8] = 0; slice_set(&v, &g_buf, s); var c = || slice_len(&v) * 10 + (slice_ptr(&v) == &g_buf); return fncall0(c); }
async fn mixed(s): i64 { var a = s; var p = P2 { s + 1, s + 2 }; var b = s + 3; var s1 = await nopark(); var c = || a * 1000000 + p.y * 10000 + p.x * 100 + b; return fncall0(c); }
fn ctrl_mixed(s): i64 { var a = s; var p = P2 { s + 1, s + 2 }; var b = s + 3; var c = || a * 1000000 + p.y * 10000 + p.x * 100 + b; return fncall0(c); }
async fn nest(s): i64 { var p = P2 { s, s + 8 }; var s1 = await nopark(); var c = || { var d = || p.y * 100 + p.x; return fncall0(d); }; return fncall0(c); }
fn ctrl_nest(s): i64 { var p = P2 { s, s + 8 }; var c = || { var d = || p.y * 100 + p.x; return fncall0(d); }; return fncall0(c); }
fn main(): i64 {
    alloc_init();
    if (run2(lit2(1)) != ctrl_lit2(1)) { return 101; }
    if (run2(lit3(1)) != ctrl_lit3(1)) { return 102; }
    if (run2(typed2(2)) != ctrl_typed2(2)) { return 103; }
    if (run2(tup2(1)) != ctrl_tup2(1)) { return 104; }
    if (run2(tup3(3)) != ctrl_tup3(3)) { return 105; }
    if (run2(call3(1)) != ctrl_call3(1)) { return 106; }
    if (run2(copy2(2)) != ctrl_copy2(2)) { return 107; }
    if (run2(wide(1)) != ctrl_wide(1)) { return 108; }
    if (run2(arr3(4)) != ctrl_arr3(4)) { return 109; }
    if (run2(sl(7)) != ctrl_sl(7)) { return 110; }
    if (run2(mixed(1)) != ctrl_mixed(1)) { return 111; }
    if (run2(nest(1)) != ctrl_nest(1)) { return 112; }
    return 0;
}
var e = main();
syscall(60, e);
EOF
CYRIUS_ASYNC=1 "$T/stage1" < "$T/a11.cyr" > "$T/a11" 2>"$T/a11.err" || {
  echo "FAIL coroutine_midbody_suspend axis11: the capture probe did not compile"; grep -m2 '^error' "$T/a11.err"; exit 1; }
[ -s "$T/a11" ] || { echo "FAIL coroutine_midbody_suspend axis11: empty binary"; exit 1; }
chmod +x "$T/a11"; g11=0; timeout 30 "$T/a11" || g11=$?
[ "$g11" -eq 0 ] || {
  echo "FAIL coroutine_midbody_suspend axis11: exit $g11 — a closure made in a suspending async fn read a"
  echo "  captured multi-word local wrong (100 + row: 1 a 2-word struct, 2 a 3-word one made before the"
  echo "  await, 3 a typed struct, 4/5 tuples, 6 a struct from a call, 7 a copy-init, 8 a u128, 9 an array,"
  echo "  10 a slice, 11 scalars around a struct, 12 a nested closure). Words reversed = the env copy walked"
  echo "  the coroutine frame by slot index (_cl_emit_cap_word)."
  exit 1; }


# ── axis 12 — A NARROW PARAMETER OR LOCAL OF A COROUTINE (6.7.17, the user's decision D27) ──────
# ⛔ A coroutine's slots live in its heap frame, and EFLLOAD_W / EFLSTORE_W (the i8 .. u32 load /
# store ladder) refused that frame: a narrow LOCAL was "a sub-word local in an `async fn` is not
# supported yet", and a narrow PARAMETER was left untyped (`_pnw_apply` skipped a coroutine), so it
# held the caller's whole word where 6.7.16's D72 narrows every other parameter: the filed repro
# printed `98304 511 255 -32768`. D27 (2026-10-22): narrowed, as D72 — the ladder addresses
# `[r11 + disp32]` (`_ECORO_LOAD_W` / `_ECORO_STORE_W`), so the repro prints `-32768 255 255 -32768`
# and a narrow local compiles. The same refusal fired on every read and assignment of a typed-pointer
# local whose pointee is a word — `*i64` / `*u64` / `*f64` / `*bool` / an enum's `*E`, and every
# pointer to a pointer (`**T`, `***T`): its slot type is 8, so its load / store also goes through
# EFLLOAD_W / EFLSTORE_W, at width 8 (a `*i8` .. `*u32`, `*f32`, `*u128` or struct pointer never took
# that path) — so those compile since D27 too; N28 pins that one shared path.
# Rows: R the filed repro verbatim (its stdout); N1-N28 (stdout "N<row>" for each red row) every
# width's parameter read after a suspend, every width's `+= 1` wrap, every width's local (stored
# before or after the suspend), and the other spellings — a narrow param into a narrow local, `*(&y)`
# (6.7.16's D21), a stack-passed parameter, a closure's capture of a narrow param / local, two
# suspends, a `u8` loop counter across suspends, a defer, `<<=`, a typed-pointer local whose pointee is
# a word (N28: `*i64` `+= 1`, `*u64` `= q + 2`, `*f64`, `**i64` through `&p`). Each async row is
# compared with its literal value AND a plain-fn control with the same body (D72's answer); `trash()`
# runs between forces. Legs: x86_64, CYRIUS_IR=3 (its LASE / DCE / DSE see the narrow coroutine
# nodes), PE (wine, a private prefix). aarch64 and cx refuse a suspending `async fn` (axis 4's x86
# guard); x86 Mach-O shares this emitter and ran on ach by hand (6.7.17).
# MUTATION LEDGER (2026-10-22, a copy of src/ mutated, stage1 rebuilt from it; every leg alike):
#   the pre-fix src (e65604d5d)                      -> R prints `98304 511 255 -32768`; the rows
#     probe refused ("a sub-word local in an `async fn` is not supported yet"), N28's a28 alone too
#     (at its `p += 1` and its `*p` read)
#   `_pnw_apply`'s coroutine skip alone restored     -> R `98304 511 255 -32768`; N 1-12 19-22 24-27
#   `_ECORO_LOAD_W` zero-extending every width       -> R `32768 255 255 -32768`; N 1 3 5 7 9 11 13
#     15 17 19 22 (every signed row)
cat > "$T/a12r.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
fn nopark(): i64 { return 0; }
async fn st(C, y: i16): i64 {
    var s1 = await nopark();
    y += 1;
    return y;
}
async fn st1(y: u8): i64 {
    var s1 = await nopark();
    return y;
}
async fn ns(y: u8): i64 { return y; }
fn sync16(y: i16): i64 { y += 1; return y; }
fn main(): i64 {
    alloc_init();
    var C = st(0, 0x17FFF);
    future_force(C);
    pr(future_force(C));
    var D = st1(0x1FF);
    future_force(D);
    pr(future_force(D));
    var E = ns(0x1FF);
    pr(future_force(E));
    pr(sync16(0x17FFF));
    syscall(SYS_WRITE, 1, "\n", 1);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
cat > "$T/a12.cyr" <<EOF
${PRE}include "lib/fnptr.cyr"
var g_red = 0;
var g_d = 0;
fn nopark(): i64 { return 0; }
fn trash(n) { var pad[512]; store64(&pad, 123456789); if (n > 0) { trash(n - 1); } return load64(&pad); }
fn runf(F): i64 { var r = future_force(F); while (future_pending(F) == 1) { trash(40); r = future_force(F); } return r; }
fn chk(row, got, ctl, want): i64 {
    if (got != want || ctl != want) { fmt_int(row); syscall(SYS_WRITE, 1, " ", 1); g_red = g_red + 1; }
    return 0;
}
async fn a1(y: i8): i64 { var s = await nopark(); return y; }
fn c1(y: i8): i64 { return y; }
async fn a2(y: u8): i64 { var s = await nopark(); return y; }
fn c2(y: u8): i64 { return y; }
async fn a3(y: i16): i64 { var s = await nopark(); return y; }
fn c3(y: i16): i64 { return y; }
async fn a4(y: u16): i64 { var s = await nopark(); return y; }
fn c4(y: u16): i64 { return y; }
async fn a5(y: i32): i64 { var s = await nopark(); return y; }
fn c5(y: i32): i64 { return y; }
async fn a6(y: u32): i64 { var s = await nopark(); return y; }
fn c6(y: u32): i64 { return y; }
async fn a7(y: i8): i64 { var s = await nopark(); y += 1; return y; }
fn c7(y: i8): i64 { y += 1; return y; }
async fn a8(y: u8): i64 { var s = await nopark(); y += 1; return y; }
fn c8(y: u8): i64 { y += 1; return y; }
async fn a9(y: i16): i64 { y += 1; var s = await nopark(); return y; }
fn c9(y: i16): i64 { y += 1; return y; }
async fn a10(y: u16): i64 { var s = await nopark(); y += 1; return y; }
fn c10(y: u16): i64 { y += 1; return y; }
async fn a11(y: i32): i64 { var s = await nopark(); y += 1; return y; }
fn c11(y: i32): i64 { y += 1; return y; }
async fn a12(y: u32): i64 { var s = await nopark(); y += 1; return y; }
fn c12(y: u32): i64 { y += 1; return y; }
async fn a13(C): i64 { var y: i8 = 0 - 3; var s = await nopark(); return y; }
fn c13(C): i64 { var y: i8 = 0 - 3; return y; }
async fn a14(C): i64 { var y: u8 = 0 - 3; var s = await nopark(); return y; }
fn c14(C): i64 { var y: u8 = 0 - 3; return y; }
async fn a15(C): i64 { var y: i16 = 5; var s = await nopark(); y = 0x18000; return y; }
fn c15(C): i64 { var y: i16 = 5; y = 0x18000; return y; }
async fn a16(C): i64 { var y: u16 = 0; var s = await nopark(); y = 0 - 1; return y; }
fn c16(C): i64 { var y: u16 = 0; y = 0 - 1; return y; }
async fn a17(C): i64 { var y: i32 = 0x7FFFFFFF; var s = await nopark(); y += 1; return y; }
fn c17(C): i64 { var y: i32 = 0x7FFFFFFF; y += 1; return y; }
async fn a18(C): i64 { var y: u32 = 0xFFFFFFFF; var s = await nopark(); y += 1; return y; }
fn c18(C): i64 { var y: u32 = 0xFFFFFFFF; y += 1; return y; }
async fn a19(a: u8, b: i16, c): i64 { var s = await nopark(); var d: i8 = a; return d * 1000000 + b * 100 + c; }
fn c19(a: u8, b: i16, c): i64 { var d: i8 = a; return d * 1000000 + b * 100 + c; }
async fn a20(y: u8): i64 { var s = await nopark(); var a = *(&y); *(&y) = 0x2FF; var b = y; *(&y) += 1; return a * 1000000 + b * 1000 + y; }
fn c20(y: u8): i64 { var a = *(&y); *(&y) = 0x2FF; var b = y; *(&y) += 1; return a * 1000000 + b * 1000 + y; }
async fn a21(a, b, c, d, e, f, y: u8): i64 { var s = await nopark(); return y; }
fn c21(a, b, c, d, e, f, y: u8): i64 { return y; }
async fn a22(y: i16): i64 { var f = |k| y + k; var s = await nopark(); return fncall1(f, 0); }
fn c22(y: i16): i64 { var f = |k| y + k; return fncall1(f, 0); }
async fn a23(C): i64 { var s = await nopark(); var b: u16 = 0 - 2; var k = |z| b + z; return callptr(k, 0); }
fn c23(C): i64 { var b: u16 = 0 - 2; var k = |z| b + z; return callptr(k, 0); }
async fn a24(y: i16): i64 { var s = await nopark(); y = y + 0x10000; var t = await nopark(); return y; }
fn c24(y: i16): i64 { y = y + 0x10000; return y; }
async fn a25(n: u8): i64 { var acc = 0; var i: u8 = 250; while (i != 4) { var s = await nopark(); acc = acc + 1; i += 1; } return acc * 1000 + n; }
fn c25(n: u8): i64 { var acc = 0; var i: u8 = 250; while (i != 4) { acc = acc + 1; i += 1; } return acc * 1000 + n; }
async fn a26(y: i8): i64 { defer { g_d = y; } var s = await nopark(); y -= 1; return 0; }
fn c26(y: i8): i64 { defer { g_d = y; } y -= 1; return 0; }
async fn a27(y: u8): i64 { var s = await nopark(); y = y << 1; y <<= 1; return y; }
fn c27(y: u8): i64 { y = y << 1; y <<= 1; return y; }
async fn a28(buf): i64 { var p: *i64 = buf; var q: *u64 = buf; var f: *f64 = buf; var pp: **i64 = &p; var s = await nopark(); p += 1; q = q + 2; var t = await nopark(); return *p + *q + load64(f) + load64(*pp); }
fn c28(buf): i64 { var p: *i64 = buf; var q: *u64 = buf; var f: *f64 = buf; var pp: **i64 = &p; p += 1; q = q + 2; return *p + *q + load64(f) + load64(*pp); }
fn main(): i64 {
    alloc_init();
    chk(1, runf(a1(0x1FF)), c1(0x1FF), 0 - 1);
    chk(2, runf(a2(0x1FF)), c2(0x1FF), 255);
    chk(3, runf(a3(0x18000)), c3(0x18000), 0 - 32768);
    chk(4, runf(a4(0x1FFFF)), c4(0x1FFFF), 65535);
    chk(5, runf(a5(0x180000000)), c5(0x180000000), 0 - 2147483648);
    chk(6, runf(a6(0x1FFFFFFFF)), c6(0x1FFFFFFFF), 4294967295);
    chk(7, runf(a7(127)), c7(127), 0 - 128);
    chk(8, runf(a8(255)), c8(255), 0);
    chk(9, runf(a9(0x7FFF)), c9(0x7FFF), 0 - 32768);
    chk(10, runf(a10(0xFFFF)), c10(0xFFFF), 0);
    chk(11, runf(a11(0x7FFFFFFF)), c11(0x7FFFFFFF), 0 - 2147483648);
    chk(12, runf(a12(0xFFFFFFFF)), c12(0xFFFFFFFF), 0);
    chk(13, runf(a13(0)), c13(0), 0 - 3);
    chk(14, runf(a14(0)), c14(0), 253);
    chk(15, runf(a15(0)), c15(0), 0 - 32768);
    chk(16, runf(a16(0)), c16(0), 65535);
    chk(17, runf(a17(0)), c17(0), 0 - 2147483648);
    chk(18, runf(a18(0)), c18(0), 0);
    chk(19, runf(a19(0x181, 0x1FFFF, 7)), c19(0x181, 0x1FFFF, 7), 0 - 127000093);
    chk(20, runf(a20(0x1C8)), c20(0x1C8), 200255000);
    chk(21, runf(a21(1, 2, 3, 4, 5, 6, 0x3FF)), c21(1, 2, 3, 4, 5, 6, 0x3FF), 255);
    chk(22, runf(a22(0x18000)), c22(0x18000), 0 - 32768);
    chk(23, runf(a23(0)), c23(0), 65534);
    chk(24, runf(a24(0x17FFF)), c24(0x17FFF), 32767);
    chk(25, runf(a25(0x105)), c25(0x105), 10005);
    runf(a26(0x180)); var d1 = g_d; g_d = 0; c26(0x180); chk(26, d1, g_d, 127);
    chk(27, runf(a27(0x41)), c27(0x41), 4);
    var B = alloc(24); store64(B, 1); store64(B + 8, 1000); store64(B + 16, 1000000);
    chk(28, runf(a28(B)), c28(B), 1002001);
    syscall(SYS_WRITE, 1, "\n", 1);
    return g_red;
}
var e = main();
syscall(60, e);
EOF
A12_WANT='-32768 255 255 -32768 '
a12_skip=0
a12_red=0
# a12_leg <label> <runner or ""> [ENV=V]: the repro prints A12_WANT, the rows probe exits 0.
a12_leg() {
  for p in a12r a12; do
    rc=0
    if [ -n "${3:-}" ]; then env CYRIUS_ASYNC=1 "$3" "$T/stage1" < "$T/$p.cyr" > "$T/$p.bin" 2> "$T/$p.err" || rc=$?
    else CYRIUS_ASYNC=1 "$T/stage1" < "$T/$p.cyr" > "$T/$p.bin" 2> "$T/$p.err" || rc=$?; fi
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$p.bin" ]; then
      echo "  FAIL axis12 $1 $p: did not build (rc $rc): $(grep '^error' "$T/$p.err" | head -1)"; a12_red=$((a12_red + 1)); continue; fi
    chmod +x "$T/$p.bin"
    got=0
    if [ -n "$2" ]; then out=$(timeout 120 $2 "$T/$p.bin" 2>/dev/null) || got=$?
    else out=$(timeout 30 "$T/$p.bin" 2>/dev/null) || got=$?; fi
    out=$(printf '%s' "$out" | tr -d '\r')
    if [ "$p" = a12r ]; then
      [ "$got" -eq 0 ] && [ "$out" = "$A12_WANT" ] || {
        echo "  FAIL axis12 $1 R: the filed repro printed '$out' (exit $got), want '$A12_WANT'"; a12_red=$((a12_red + 1)); }
    else
      [ "$got" -eq 0 ] || { echo "  FAIL axis12 $1: exit $got, red rows N: $out"; a12_red=$((a12_red + 1)); }
    fi
  done
}
a12_leg "x86_64" ""
a12_leg "CYRIUS_IR=3" "" CYRIUS_IR=3
if command -v wine > /dev/null 2>&1; then
  mkdir -p "$T/whome"
  printf '#!/bin/sh\ncp "$1" "$1.exe" || exit 1\ncd "%s" && WINEPREFIX="%s" HOME="%s" XDG_CACHE_HOME="%s/.cache" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1.exe"\n' \
    "$T" "$WP" "$T/whome" "$T/whome" > "$T/winrun"; chmod +x "$T/winrun"
  a12_leg "PE (wine)" "$T/winrun" CYRIUS_TARGET_WIN=1
else echo "  SKIP coroutine_midbody_suspend axis12: the PE leg (wine not installed)"; a12_skip=1; fi
[ "$a12_red" -eq 0 ] || {
  echo "FAIL coroutine_midbody_suspend axis12: $a12_red leg(s) red — a coroutine's narrow parameter or local"
  echo "  does not hold its type's value (N<row>: 1-6 a parameter of each width, 7-12 each width's += 1 wrap,"
  echo "  13-18 a local of each width, 19 a param into a narrow local, 20 *(&y), 21 stack-passed, 22 / 23 a"
  echo "  closure's capture, 24 two suspends, 25 a u8 loop counter, 26 a defer, 27 <<=, 28 a typed-pointer"
  echo "  local whose pointee is a word: *i64 / *u64 / *f64 / **i64)."
  exit 1; }

if [ "$a12_skip" -eq 1 ]; then echo "SKIP coroutine_midbody_suspend: every axis that ran passed, but axis 12's PE leg could not run (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS coroutine_midbody_suspend: a narrow (i8 .. u32) parameter or local of a coroutine holds its type's value (D27: the filed repro prints -32768 255 255 -32768; 28 rows on x86_64 / IR=3 / PE) · a closure made in a coroutine captures a struct / tuple / u128 / array / slice in field order (before and after the await, nested) · the reactor resumes a coroutine whose await did not park (async_run, task_join; parked tasks and the deadline are not starved) · vector params refused by name (4 classes x coroutine/plain; a pointer works) · by-value struct params over 8 B (24 B / 16 B x coroutine/plain) refused by name with the p: *T spelling (a *P3, a <= 8 B struct and a Str still compute) · by-value struct returns (24 B / 16 B) and value-form vector returns (4 classes) refused by name, with the <= 8 B struct and the sync vector fn still computing · mid-body suspend resumes in place · in loops · multi-parameter · &local across suspends · arity 6/7/8 against plain-fn controls · &struct-local (typed AND literal, single- and multi-word) across a suspend with a trashed stack · no-await async fns bit-identical"
exit 0
