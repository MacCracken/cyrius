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

# ── axis 6 — ANTI-VACUOUS CONTROL: a BOXED enum must be entirely unaffected ─────────────────
# If this fires, the check is over-firing and would refuse the documented Result idiom at every
# one of the 2,215 sibling-repo construction sites.
accept "boxed Ok(9): single bind + is_ok" axis6 1 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
include "lib/syscalls.cyr"
fn main(): i64 { alloc_init(); var r = Ok(9); syscall(60, is_ok(r) & 0xFF, 0,0,0,0); return 0; }
var e = main();
EOF
accept "boxed Result through ? still works" axis6b 9 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
include "lib/syscalls.cyr"
fn produce() { return Ok(9); }
fn consume(): i64 { var v = produce()?; return v; }
fn main(): i64 { alloc_init(); syscall(60, consume() & 0xFF, 0,0,0,0); return 0; }
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

echo 'PASS stack_enum_lossy_context: lossy binds refused on stack enums (bare ctor, forwarding wrapper) · `?` propagates the pair with its Err payload intact · destructure and return-forwarding still work · BOXED Result unaffected · nullary variants allowed and unflagged'
exit 0
