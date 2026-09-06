#!/bin/sh
# derive_accessors_inlined.sh — v6.5.71. `#derive(accessors)` getters/setters are inlined at
# their call sites, and stacked `#derive` blocks still work.
#
# ⛔ WHY THE SECOND HALF IS IN THE SAME GATE. The obvious implementation — emit `#inline` into
# the generated text — DOES NOT WORK AND CANNOT BE MADE TO. Derive bodies are FLATTENED ONTO A
# SINGLE LINE to keep the user's line numbering honest, and `#` opens a COMMENT in cyrius, so
# the `#` comments out the rest of that line: the user's tail AND the following `#derive`.
# Measured on a compiler built with that emit: a two-struct fixture that gives exit 10 normally
# fails with `error: <source>:5:1: unexpected struct` — the SECOND derive never fires and its
# `struct` reaches the parser. The request therefore travels beside the text, as a recorded
# hash the parser consults, and axis 2 exists so nobody "simplifies" it back to a text emit.
# (Same fact as v6.4.81's "`#` is a COMMENT so `#include` probes are inert".)
#
# ⚠ MUTATION-PROVEN: with `_pp_inl_add` stubbed to a no-op, axis 1's call count does not drop
# (7 callq, not 3) while every answer stays correct — which is exactly why axis 1 asserts the
# CALL COUNT and not just the value. An inlining change is invisible to a result assertion.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL derive_accessors_inlined: no build/cycc"; exit 1; }
command -v llvm-objdump >/dev/null 2>&1 || { echo "SKIP derive_accessors_inlined: no llvm-objdump"; exit 0; }

"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL derive_accessors_inlined: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

# ── axis 1 — the accessors are INLINED (call count drops) and the answer is unchanged ────
cat > "$T/a1.cyr" <<'EOF'
include "lib/syscalls.cyr"
#derive(accessors)
struct P { a; b; }
fn main(): i64 {
    var p: P;
    P_set_a(&p, 5);
    P_set_b(&p, 9);
    var t = 0;
    var i = 0;
    while (i < 100) { t = t + P_a(&p) + P_b(&p); i = i + 1; }
    syscall(60, t & 0xFF);
    return 0;
}
var e = main();
EOF
"$T/stage1" < "$T/a1.cyr" > "$T/a1" 2>/dev/null || { echo "FAIL derive_accessors_inlined axis1: probe did not compile"; exit 1; }
chmod +x "$T/a1"; "$T/a1"; got=$?
[ "$got" -eq 120 ] || { echo "FAIL derive_accessors_inlined axis1: probe gave $got, expected 120 — inlining changed the ANSWER"; exit 1; }
NC=$(llvm-objdump -d "$T/a1" 2>/dev/null | grep -c callq)
[ "$NC" -le 5 ] || {
  echo "FAIL derive_accessors_inlined axis1: $NC callq in the probe (inlined is 3, out-of-line is 7)."
  echo "  The accessors are not reaching the inline-replay path. A value assertion cannot see this,"
  echo "  which is why this row counts CALLS."
  exit 1; }

# ── axis 2 — ANTI-REGRESSION: STACKED derives still work ─────────────────────────────────
# This is the row that fails the moment someone re-implements the feature as an `#inline` text
# emit: the flattened line makes the `#` swallow the next `#derive`.
cat > "$T/a2.cyr" <<'EOF'
include "lib/syscalls.cyr"
#derive(accessors)
struct A { x; y; }
#derive(accessors)
struct B { p; q; }
fn main(): i64 {
    var a: A; A_set_x(&a, 7);
    var b: B; B_set_q(&b, 3);
    syscall(60, A_x(&a) + B_q(&b));
    return 0;
}
var e = main();
EOF
"$T/stage1" < "$T/a2.cyr" > "$T/a2" 2>"$T/a2.err" || {
  echo "FAIL derive_accessors_inlined axis2: the SECOND #derive did not fire."
  echo "  'unexpected struct' here means an emitted '#' commented out the rest of the flattened line."
  grep -m2 '^error' "$T/a2.err" | sed 's/^/    /'
  exit 1; }
chmod +x "$T/a2"; "$T/a2"; g2=$?
[ "$g2" -eq 10 ] || { echo "FAIL derive_accessors_inlined axis2: stacked derives gave $g2, expected 10"; exit 1; }

# ── axis 3 — ANTI-VACUOUS: an ordinary fn is NOT swept into the inline path ──────────────
# The side channel is keyed on a name hash. A collision or an over-broad match would inline
# functions the user never asked for, so this row pins that a plain fn of the same shape stays
# out of line.
cat > "$T/a3.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn plain_get(p) { return load64(p + 0); }
fn main(): i64 {
    var buf: i64[2];
    store64(&buf, 42);
    var t = 0;
    var i = 0;
    while (i < 100) { t = t + plain_get(&buf); i = i + 1; }
    syscall(60, (t / 100) & 0xFF);
    return 0;
}
var e = main();
EOF
"$T/stage1" < "$T/a3.cyr" > "$T/a3" 2>/dev/null || { echo "FAIL derive_accessors_inlined axis3: control did not compile"; exit 1; }
chmod +x "$T/a3"; "$T/a3"; g3=$?
[ "$g3" -eq 42 ] || { echo "FAIL derive_accessors_inlined axis3: control gave $g3, expected 42"; exit 1; }
PC=$(llvm-objdump -d "$T/a3" 2>/dev/null | grep -c callq)
[ "$PC" -ge 2 ] || {
  echo "FAIL derive_accessors_inlined axis3: a PLAIN fn was inlined ($PC callq). The side channel"
  echo "  must fire only for names the preprocessor generated."
  exit 1; }

echo "PASS derive_accessors_inlined: generated accessors inlined ($NC callq vs 7 out-of-line) · stacked #derive still fires · a plain fn of the same shape stays out of line"
exit 0
