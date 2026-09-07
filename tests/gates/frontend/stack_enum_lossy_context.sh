#!/bin/sh
# stack_enum_lossy_context.sh — v6.5.67. A `: stack` enum value is TWO registers (rax = tag,
# rdx = payload). Consuming it in a context that keeps only one must be a hard ERROR, never
# silent data loss.
#
# ⛔ WHY THIS EXISTS. v6.5.55 shipped the representation with nothing recording which calls
# produce a pair, so every lossy context silently kept the tag and dropped the payload. Measured
# on the pre-fix compiler, modelling the idiomatic forwarding shape:
#
#     fn fwd() { var r = mk(3); var j = noise(7,8,9); return r; }
#     var t, p = fwd();     ->  p == 9, not 3
#
# 9 is the third argument left in rdx by the intervening call. **Exit 0, no diagnostic, allocator
# delta 0.** That is the v6.5.15 class — "a failed open reported as SUCCESS" — reincarnated on the
# payload instead of the tag, and the v6.5.55 corpus could not see it because every stack-enum
# test in the tree destructures at the call site.
#
# Separately, `?` on a stack enum compiled clean and SIGSEGV'd (rc=139): it dereferences its
# operand, so it read the TAG (0 or 1) as a pointer. The guide already said `?` does not apply to
# the stack form — it had just never said so to the compiler.
#
# ⭐ AXIS 6 IS THE ANTI-VACUOUS ONE AND IT IS THE ONE THAT MATTERS. The check must fire ONLY for
# `: stack` enums. A BOXED Result is a single pointer and `var r = Ok(1)` / `r?` are the
# documented, ubiquitous idiom — 340 construction sites in this repo and 2,215 across 37 sibling
# repos. An over-firing check would refuse every one of them, so a gate that only proved the
# errors fire would be worse than none.
#
# ⚠ Those two numbers are DERIVED, and the definition is part of them: `Ok(`/`Err(`/`Some(`/
# `None(`/`Left(`/`Right(` in .cyr/.tcyr/.fcyr/.bcyr with comments and string literals stripped,
# siblings counted on their OWN source with the vendored lib/ excluded. Three earlier figures for
# this one quantity (~306, 385, ~1,864) each came from a different unstated definition — the
# self-drifting-value shape this cycle keeps finding. Re-derive, do not copy.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL stack_enum_lossy_context: no build/cycc"; exit 1; }

PRE='include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
enum SR: stack { SOk(v); SErr(e); }
fn mk(x) { return SOk(x); }
fn noise(a, b, c) { return a + b + c; }
'

# refuse <label> <axis> — source on stdin MUST fail to compile, and the message must name the fix.
refuse() {
  cat > "$T/p.cyr"
  if "$CC" < "$T/p.cyr" > "$T/p" 2>"$T/p.err"; then
    echo "FAIL stack_enum_lossy_context $2: $1 COMPILED — the payload is silently dropped."
    exit 1
  fi
  grep -q "stack" "$T/p.err" || {
    echo "FAIL stack_enum_lossy_context $2: $1 was refused, but the message does not mention the"
    echo "  stack form. A diagnostic that does not name the fix sends the author hunting."
    sed 's/^/    /' "$T/p.err" | head -3
    exit 1
  }
}
# accept <label> <axis> <expected-exit> — source on stdin MUST compile AND produce the right value.
accept() {
  cat > "$T/p.cyr"
  "$CC" < "$T/p.cyr" > "$T/p" 2>"$T/p.err" || {
    echo "FAIL stack_enum_lossy_context $2: $1 was REFUSED but is legal."
    grep -E '^error' "$T/p.err" | head -2 | sed 's/^/    /'
    exit 1
  }
  chmod +x "$T/p"; "$T/p"; got=$?
  [ "$got" -eq "$3" ] || { echo "FAIL stack_enum_lossy_context $2: $1 ran but gave ${got}, expected $3"; exit 1; }
}

# ── axis 1 — single-variable bind of a bare constructor ─────────────────────────────────────
refuse "var r = SOk(9)" axis1 <<EOF
${PRE}fn main(): i64 { var r = SOk(9); syscall(60, r & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF

# ── axis 2 — single-variable bind through a FORWARDING wrapper (the idiomatic shape) ─────────
# This is the one that was silently wrong; the flag has to propagate through `return`.
refuse "var r = mk(3) via wrapper" axis2 <<EOF
${PRE}fn fwd() { var r = mk(3); var j = noise(7, 8, 9); return r; }
fn main(): i64 { var t, p = fwd(); syscall(60, p & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF

# ── axis 3 — `?` on a stack enum PROPAGATES THE PAIR (v6.5.74) ──────────────────────────────
# ⛔ THIS ROW USED TO ASSERT THE OPPOSITE, and the flip is the point. v6.5.67 made `?` on a
# value-form enum a hard error because the operator DEREFERENCED its operand — reading the tag
# (0 or 1) as a pointer, compiling clean and then SIGSEGV'ing. Refusing was the right stopgap.
# v6.5.74 lowers it properly, so a gate that still demanded the refusal would block the fix —
# the same shape as the v6.5.68 gate that pinned the sentence encoding its own limitation.
#
# ⭐ THE ASSERTION THAT MATTERS IS THE ERR PAYLOAD. Propagating out of the enclosing function
# means returning a PAIR, so the Err path has to re-emit rdx as well as rax; restoring only rax
# hands the caller a correct tag with a stale payload — the v6.5.67 silent-loss defect one level
# up, and invisible to any check that only looks at the tag.
accept "SOk/SErr propagate through ? with the payload intact" axis3 33 <<EOF
${PRE}fn produce(n) { if (n < 0) { return SErr(33); } return SOk(n); }
fn relay(n) { var v = produce(n)?; return SOk(v + 1); }
fn main(): i64 {
    var t1, v1 = relay(7);
    var t2, v2 = relay(0 - 1);
    if (t1 != 0) { syscall(60, 101, 0,0,0,0); }
    if (v1 != 8) { syscall(60, 102, 0,0,0,0); }
    if (t2 != 1) { syscall(60, 103, 0,0,0,0); }
    syscall(60, v2 & 0xFF, 0,0,0,0);
    return 0;
}
var e = main();
EOF

# ── axis 4 — CONTROL: destructuring is the correct form and must work ───────────────────────
accept "var t, p = SOk(9)" axis4 9 <<EOF
${PRE}fn main(): i64 { var t, p = SOk(9); syscall(60, p & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF
accept "var t, p = mk(9)" axis4b 9 <<EOF
${PRE}fn main(): i64 { var t, p = mk(9); syscall(60, p & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF

# ── axis 5 — CONTROL: forwarding a pair via `return` stays legal ────────────────────────────
accept "return mk(9) forwards the pair" axis5 9 <<EOF
${PRE}fn fwd2() { return mk(9); }
fn main(): i64 { var t, p = fwd2(); syscall(60, p & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF

# ── axis 6 — THE STDLIB Result IS THE VALUE FORM NOW (v6.6.0) ───────────────────────────────
# ⛔ THIS AXIS USED TO ASSERT THE OPPOSITE. Until v6.6.0 `lib/result.cyr` was BOXED, so `var r =
# Ok(1)` was the documented idiom at thousands of sites and this axis existed to prove the check
# did not over-fire on it. v6.6.0 flipped Result/Option/Either themselves, so that same line is
# now a genuine lossy bind and MUST be refused — a gate still demanding it compile would forbid
# the release. The anti-vacuous job it used to do moved to axis 11, which uses a locally
# declared BOXED enum: that is the thing that must stay unaffected, and it still exists.
refuse "stdlib Ok(9) single bind is lossy too" axis6 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
include "lib/syscalls.cyr"
fn main(): i64 { alloc_init(); var r = Ok(9); syscall(60, r & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF
accept "stdlib Result destructures and its helpers take the tag" axis6b 9 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    alloc_init();
    var t, v = Ok(9);
    if (is_ok(t) != 1) { syscall(60, 101, 0,0,0,0); }
    if (is_err_result(t) != 0) { syscall(60, 102, 0,0,0,0); }
    if (result_unwrap(t, v) != 9) { syscall(60, 103, 0,0,0,0); }
    var et, ev = Err(4);
    if (err_code_of(et, ev) != 4) { syscall(60, 104, 0,0,0,0); }
    if (result_unwrap_or(et, ev, 9) != 9) { syscall(60, 105, 0,0,0,0); }
    syscall(60, v & 0xFF, 0,0,0,0);
    return 0;
}
var e = main();
EOF
accept "stdlib Result through ? keeps the Err payload" axis6c 12 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
include "lib/syscalls.cyr"
fn produce(n) { if (n < 0) { return Err(12); } return Ok(n); }
fn consume(n) { var v = produce(n)?; return Ok(v + 1); }
fn main(): i64 {
    alloc_init();
    var t, v = consume(0 - 1);
    if (t != 1) { syscall(60, 101, 0,0,0,0); }
    syscall(60, v & 0xFF, 0,0,0,0);
    return 0;
}
var e = main();
EOF

# ── axis 7 — NULLARY variants: allowed, and NOT pair-returning (v6.5.67) ────────────────────
# ⛔ Until v6.5.67 `enum Option: stack { None(); Some(v); }` was a COMPILE ERROR — "stack enum
# variant must take exactly 1 field" — which blocked the one type this whole arc exists to
# migrate, and no roadmap line mentioned it. A nullary variant carries no payload, so it needs no
# second register: it returns its tag alone, is NOT flagged pair-returning, and a single-variable
# bind of it is correct (there is nothing to lose).
accept "Option-shaped: None() binds to one value" axis7 0 <<'EOF'
include "lib/syscalls.cyr"
enum Opt: stack { ONone(); OSome(v); }
fn main(): i64 { var n = ONone(); syscall(60, n & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF
accept "Option-shaped: OSome(42) destructures" axis7b 42 <<'EOF'
include "lib/syscalls.cyr"
enum Opt: stack { ONone(); OSome(v); }
fn main(): i64 { var t, v = OSome(42); syscall(60, v & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF
# Arity 2+ still cannot fit the pair and must stay refused.
refuse "arity-2 stack variant" axis7c <<'EOF'
include "lib/syscalls.cyr"
enum E2: stack { P(a, b); }
fn main(): i64 { syscall(60, 0, 0,0,0,0); return 0; }
var e = main();
EOF

# ── axis 8 — v6.6.0: the OTHER lossy contexts. Refusing only `var x = f();` was enough while
# `: stack` was an opt-in nobody used; flipping Result/Option/Either to the value form makes
# every other single-value context live across the ecosystem. Two of them compiled clean and
# dropped the payload in SILENCE, and `store64` is the one that matters — it is how every
# collection of Results is written, and the half it discarded is the error code.
refuse "assignment x = mk(3)" axis8 <<EOF
${PRE}fn main(): i64 { var x = 0; x = mk(3); syscall(60, x & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF
refuse "store64(&slot, mk(3))" axis8b <<EOF
${PRE}fn main(): i64 { var slot[16]; store64(&slot, mk(3)); syscall(60, 0, 0,0,0,0); return 0; }
var e = main();
EOF

# ── axis 9 — v6.6.0: `?` in STATEMENT position, on the value form ───────────────────────────
# ⛔ PARSE_STMT dispatches IDENT+LPAREN straight to PARSE_FNCALL and never reaches the term
# parser, so the `?` desugar exists TWICE. v6.6.0 first taught only the expression copy the pair
# form; the statement copy kept dereferencing its operand, so `f()?;` as a bare statement
# compiled clean and SIGSEGV'd while `var x = f()?;` was correct. Both halves of the Err path
# are asserted: exit 33 can only be produced by rdx surviving the propagation.
accept "bare f()?; propagates the pair from statement position" axis9 33 <<EOF
${PRE}fn produce(n) { if (n < 0) { return SErr(33); } return SOk(n); }
fn relay(n) { produce(n)?; return SOk(7); }
fn main(): i64 {
    var t1, v1 = relay(5);
    var t2, v2 = relay(0 - 1);
    if (t1 != 0) { syscall(60, 111, 0,0,0,0); }
    if (v1 != 7) { syscall(60, 112, 0,0,0,0); }
    if (t2 != 1) { syscall(60, 113, 0,0,0,0); }
    syscall(60, v2 & 0xFF, 0,0,0,0);
    return 0;
}
var e = main();
EOF

# ── axis 10 — v6.6.0: TOP-LEVEL destructure ─────────────────────────────────────────────────
# Binding both halves is the only correct way to receive a pair, so while this was refused
# (`multi-var destructure only supported inside functions`, and at top level it did not even
# reach that message) a top-level Result bind had no legal spelling at all.
accept "top-level var t, v = mk(9)" axis10 9 <<EOF
${PRE}var t, v = mk(9);
syscall(60, v & 0xFF, 0,0,0,0);
EOF
accept "top-level destructure after a bare expression statement" axis10b 5 <<EOF
${PRE}fn nop(): i64 { return 0; }
nop();
var t2, v2 = mk(5);
syscall(60, v2 & 0xFF, 0,0,0,0);
EOF

# ── axis 11 — ANTI-VACUOUS: every v6.6.0 refusal must leave BOXED enums alone ────────────────
# If this fires, the checks are over-firing and would refuse ordinary boxed-enum code.
accept "boxed enum: assignment, store64 and statement-? all still legal" axis11 42 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
enum B { BOk(v); BErr(e); }
fn look(n) { if (n < 0) { return BErr(55); } return BOk(n * 2); }
fn chain(n) { look(n)?; return BOk(9); }
fn main(): i64 {
    alloc_init();
    var q = 0;
    q = look(3);
    var slot[16];
    store64(&slot, look(4));
    var a = chain(3);
    var b = chain(0 - 1);
    if (load64(q + 8) != 6) { return 101; }
    if (load64(load64(&slot) + 8) != 8) { return 102; }
    if (load64(a + 8) != 9) { return 103; }
    if (load64(b + 8) != 55) { return 104; }
    return 42;
}
var e = main();
syscall(60, main() & 0xFF, 0,0,0,0);
EOF

# ── axis 12 — v6.6.0: FORWARD REFERENCES. The single most dangerous shape of the flip ───────
# ⛔ Flag 256 ("returns a pair") is set on an enum constructor in pass 1, but on an ORDINARY fn
# only while its own body is parsed. So a caller appearing EARLIER IN THE FILE than its callee
# read the flag as unset and `?` took the BOXED lowering — dereferencing the tag (0 or 1) as a
# pointer. Compiled clean, SIGSEGV at run time, and the lossy-bind diagnostic went silent at the
# same time. That is not exotic: it is how every flattened dist bundle is laid out.
#
# ⚠ AND THE FIRST FIX DID NOT WORK, which is why the axis asserts behaviour and not machinery.
# The propagation pass is demand-driven, and the first demand arrives BEFORE the enum
# declaration is reached — measured: it ran over a complete 3,498-token stream and flagged
# nothing, because no constructor yet carried the flag to propagate FROM. It is now invalidated
# whenever a `: stack` constructor is registered.
accept "? on a callee defined LATER in the file" axis12 33 <<'EOF'
include "lib/syscalls.cyr"
enum R: stack { ROk(v); RErr(e); }
fn relay(n) { var v = look(n)?; return ROk(v + 1); }
fn look(n) { if (n < 0) { return RErr(33); } return ROk(n); }
fn main(): i64 {
    var t1, v1 = relay(7);
    var t2, v2 = relay(0 - 1);
    if (t1 != 0) { syscall(60, 101, 0,0,0,0); }
    if (v1 != 8) { syscall(60, 102, 0,0,0,0); }
    if (t2 != 1) { syscall(60, 103, 0,0,0,0); }
    syscall(60, v2 & 0xFF, 0,0,0,0);
    return 0;
}
var e = main();
EOF
accept "forward CHAIN — a forwards to b forwards to the ctor" axis12b 21 <<'EOF'
include "lib/syscalls.cyr"
enum R: stack { ROk(v); RErr(e); }
fn top(n) { var v = mid(n)?; return ROk(v + 1); }
fn mid(n) { return low(n); }
fn low(n) { if (n < 0) { return RErr(21); } return ROk(n); }
fn main(): i64 {
    var t, v = top(4);
    var t2, v2 = top(0 - 1);
    if (t != 0) { syscall(60, 101, 0,0,0,0); }
    if (v != 5) { syscall(60, 102, 0,0,0,0); }
    if (t2 != 1) { syscall(60, 103, 0,0,0,0); }
    syscall(60, v2 & 0xFF, 0,0,0,0);
    return 0;
}
var e = main();
EOF
# ...and the diagnostic must reach forward too, or a lossy bind on a later-defined callee is a
# SILENT payload drop rather than a named error.
refuse "lossy bind of a callee defined LATER" axis12c <<'EOF'
include "lib/syscalls.cyr"
enum R: stack { ROk(v); RErr(e); }
fn caller(n) { var r = look(n); return r; }
fn look(n) { if (n < 0) { return RErr(33); } return ROk(n); }
fn main(): i64 { syscall(60, 0, 0,0,0,0); return 0; }
var e = main();
EOF

echo 'PASS stack_enum_lossy_context: lossy binds refused on stack enums (bare ctor, forwarding wrapper) · `?` propagates the pair with its Err payload intact · destructure and return-forwarding still work · nullary variants allowed and unflagged · assignment and store64 refused (v6.6.0) · statement-position `?` propagates the pair · top-level destructure works · BOXED enums unaffected by all of it · forward references resolve (`?`, chains, and the diagnostic)'
exit 0
