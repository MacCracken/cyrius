#!/bin/sh
# inline_directive.sh — v6.5.63. `#inline` must actually inline, must say so when it cannot,
# and must not change results.
#
# WHY THIS GATE EXISTS. `#inline` had no handler anywhere in `src/` until v6.5.63: it lexed as
# a comment and did nothing, silently, while consumers wrote it. svara carries four markers in
# `src/formant.cyr` and its own `src/lod.cyr` records that adding one "moved `tract
# process_sample` by +0.7% -- noise" — a measurement of an optimisation that was not there.
# The failure mode of this feature is therefore NOT a crash; it is a directive that quietly
# reverts to doing nothing. A results-only test cannot see that (results are correct either
# way), so the gate has to assert the CODEGEN and the DIAGNOSTIC.
#
# ⭐ Axis 2 is what keeps the feature honest: a `#inline` that cannot be honoured must WARN.
# Without it, re-introducing "silently does nothing" is invisible again — the exact defect
# this directive was added to end, wearing a token.
#
# Correctness on every target lives in tests/tcyr/crossos/inline_directive.tcyr; the `callq`
# counts here are host-specific, which is why they are in a shell gate and not a .tcyr.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL inline_directive: no build/cycc"; exit 1; }

# One fixture, generated twice: MARK becomes `#inline` or nothing. Identical otherwise, so the
# only variable is the directive.
cat > "$T/fix.tmpl" <<'EOF'
include "lib/syscalls.cyr"
var ST = 0;
MARK
fn A_f0(s) { return load64(s + 0); }
MARK
fn A_f1(s) { return load64(s + 8); }
MARK
fn A_f2(s) { return load64(s + 16); }
MARK
fn A_f3(s) { return load64(s + 24); }
MARK
fn A_f4(s) { return load64(s + 32); }
MARK
fn A_f5(s) { return load64(s + 40); }
MARK
fn A_f6(s) { return load64(s + 48); }
MARK
fn A_f7(s) { return load64(s + 56); }
fn main(): i64 {
    var b[64];
    var i = 0;
    while (i < 8) { store64(&b + i * 8, i + 1); i = i + 1; }
    ST = &b;
    var acc = 0;
    var k = 0;
    while (k < 1000000) {
        acc = acc + A_f0(ST) + A_f1(ST) + A_f2(ST) + A_f3(ST) + A_f4(ST) + A_f5(ST) + A_f6(ST) + A_f7(ST);
        k = k + 1;
    }
    syscall(60, acc & 0xFF, 0, 0, 0, 0);
    return 0;
}
var e = main();
EOF
sed 's/^MARK$/#inline/' "$T/fix.tmpl" > "$T/yes.cyr"
sed 's/^MARK$//'        "$T/fix.tmpl" > "$T/no.cyr"
for n in yes no; do
  "$CC" < "$T/$n.cyr" > "$T/$n" 2>/dev/null || { echo "FAIL inline_directive: $n fixture did not compile"; exit 1; }
  chmod +x "$T/$n"
done

# ── axis 1 — the directive must remove call sites ───────────────────────────────────────────
CY=$(objdump -d "$T/yes" 2>/dev/null | grep -c 'call')
CN=$(objdump -d "$T/no"  2>/dev/null | grep -c 'call')
[ "$CN" -gt 0 ] || { echo "FAIL inline_directive axis1: could not count calls (objdump missing?)"; exit 1; }
if [ "$CY" -ge "$CN" ]; then
  echo "FAIL inline_directive axis1: #inline removed no call sites (with=${CY} without=${CN})."
  echo "  The directive has reverted to doing nothing — the exact defect it was added to end."
  exit 1
fi

# ── axis 2 — an UNHONOURABLE #inline must WARN, and an honourable one must NOT ──────────────
# Anti-vacuous pair: warning on everything, or on nothing, both fail here.
mkw() { printf '%s\n' "$2" > "$T/w.cyr"; "$CC" < "$T/w.cyr" > /dev/null 2>"$T/w.err"; grep -c "#inline ignored" "$T/w.err"; }
W_ARITY=$(mkw arity 'include "lib/syscalls.cyr"
#inline
fn f3(a, b, c) { return a + b + c; }
fn main(): i64 { syscall(60, f3(1,2,3), 0,0,0,0); return 0; }
var e = main();')
W_CTL=$(mkw ctl 'include "lib/syscalls.cyr"
#inline
fn fc(a) { if (a > 1) { return 1; } return 0; }
fn main(): i64 { syscall(60, fc(5), 0,0,0,0); return 0; }
var e = main();')
W_OK=$(mkw ok 'include "lib/syscalls.cyr"
#inline
fn f2(a, b) { return a + b; }
fn main(): i64 { syscall(60, f2(20,22), 0,0,0,0); return 0; }
var e = main();')
[ "$W_ARITY" -ge 1 ] || { echo "FAIL inline_directive axis2: a 3-param #inline was silently ignored (no warning)"; exit 1; }
[ "$W_CTL" -ge 1 ]   || { echo "FAIL inline_directive axis2: a control-flow-bodied #inline was silently ignored (no warning)"; exit 1; }
[ "$W_OK" -eq 0 ]    || { echo "FAIL inline_directive axis2: an HONOURABLE #inline warned — the warning is firing indiscriminately"; exit 1; }

# ── axis 3 — it must be worth something. Ratio, measured back-to-back. ──────────────────────
best() { b=999999; r=0; while [ $r -lt 5 ]; do s=$(date +%s%N); "$1"; e=$(date +%s%N); m=$(( (e - s) / 1000000 )); [ $m -lt $b ] && b=$m; r=$((r + 1)); done; echo $b; }
TY=$(best "$T/yes"); TN=$(best "$T/no")
if [ "$TN" -ge 4 ]; then
  P=$(( TY * 100 / TN ))
  # Measured at v6.5.63: 20.84 ms -> 6.04 ms = 29 %. Bound 70 % leaves wide headroom while
  # still failing if the directive degrades to a no-op (which would read ~100 %).
  if [ "$P" -ge 70 ]; then
    echo "FAIL inline_directive axis3: #inline bought nothing — ${TY}ms vs ${TN}ms (${P}%, bound 70%)."
    exit 1
  fi
else
  P="skipped(too-fast)"
fi

# ── axis 4 — CONTROL: results must be identical with and without ────────────────────────────
"$T/yes"; RY=$?
"$T/no";  RN=$?
[ "$RY" -eq "$RN" ] || { echo "FAIL inline_directive axis4: #inline CHANGED THE RESULT (with=${RY} without=${RN})"; exit 1; }

echo "PASS inline_directive: calls ${CN}->${CY} · warns on unhonourable, silent on honourable · ${TY}ms vs ${TN}ms (${P}%) · results identical (${RY})"
exit 0
