#!/bin/sh
# tests/gates/toolchain/cybs_call_arity_named.sh — 6.7.0, stack arguments 6.7.6
#
# cybs (the hand-assembly bootstrap compiler the seed assembles) passed only the six register
# arguments: `emit_fn_call_pops` handled 0..6 and `emit_store_param` stored parameters 0..5. A
# call with 7+ arguments fell to `parse_err` with a bare "syntax error" (found at 6.7.0, when a
# 7-argument helper call in src/frontend/parse_decl.cyr broke seed-derive), so 6.7.0 refused it
# BY NAME and a definition with 7+ parameters kept only its first six (lib/fnptr.cyr's
# fncall6..8, which the compiler includes, were such). 6.7.6 passes them, in cycc's order (the
# user's decision, 2026-10-08, third round — lane B first passed them in the SysV order, argument 7
# at [rsp]): the caller leaves arguments 7+ on the stack with the LAST at [rsp], and the callee
# copies parameter i >= 6 of n from [rbp + 16 + (n - 1 - i) * 8] (cybs counts the parameters
# first) — so one convention holds for cybs and cycc, and lib/fnptr.cyr's hand-written fncall8
# (cycc's order since lane E2) hands a cybs-compiled callee arguments 7 and 8 in place. src/ may
# call a 7+ argument helper. This gate runs cybs over src/main.cyr in check.sh as well, so a
# construct cybs cannot compile in the bootstrap path is caught by the normal suite, not first by
# seed-derive.
#
#   A  closure: the seed assembles cybs, and cybs reproduces the seed
#   S  bootstrap/cybs.cyr fits the seed's caps (input < 131072 B — past it the seed drops the rest
#      silently — and at most 512 labels)
#   B  a 7- and a 9-argument call return the right values — as statements, inside an expression
#      with a value pending (`k + f9(..)`), with a 7-argument call as an argument, and through
#      lib/fnptr.cyr's fncall7 / fncall8 (their 7+ parameters stored, their stack arguments read by
#      a cybs-compiled callee); the same program under build/cycc agrees. Every callee weighs its
#      arguments by POSITION (f8 is `.. + h * 10 + i`), so a swapped pair of stack arguments is red
#      under either compiler — lane E2 had made f8 symmetric while cybs and cycc disagreed (D3).
#   C  ANTI-VACUOUS: a 6-argument call still compiles and runs (exit 42)
#   D  cybs compiles src/main.cyr
#
# Mutations (6.7.6, each verified RED on B in a scratch copy of the tree):
#   emit_store_param's i >= 6 arm back to `jmp emit_sp_done`  (parameters 7+ never stored)
#   emit_fn_call_pops copies from [rsp + 8k] instead of [rsp + 16k]  (lane B's copy loop; gone in D3)
#   emit_fn_call_clean emits nothing                        (`k + f9(..)` pops a stale word)
#   rdi and rsi register loads swapped                       (register arguments misrouted)
#   cybs.cyr padded with comments past 131072 B / given 20 more labels    -> S RED
# D3 (cycc's order; each a scratch copy of the tree with the one change, 2026-10-08):
#   lane B's cybs.cyr (the SysV order) under the restored f8      -> B exits 47 (fncall8, bit 16)
#   emit_store_param reads [rbp + 16 + (i-6)*8] again (SysV slot) -> B exits 1
#   parse_fn_def does not call count_params (n stays 0)            -> B exits 0
#   emit_fn_call_clean drops lane B's 2n-6 words                   -> B exits 59 (`k + f9(..)`)
#   emit_fn_call_pops loads a[0] from [rsp + 8(n-2)]               -> B exits 139
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_call_arity_named: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_call_arity_named: bootstrap/asm missing"; exit 77; }
CC=${CYCC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_call_arity_named: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_call_arity_named $1"; fail=$((fail + 1)); }

# S — the seed (bootstrap/asm, from bootstrap/asm.cyr) reads at most 131072 input bytes and DROPS the
# rest with exit 0 (probed 6.7.6: 3 bytes over assembled a cybs 1 byte short, silently), and its
# label table holds 512 entries. cybs.cyr must stay inside both; the seed itself is the trust root.
sz=$(wc -c < bootstrap/cybs.cyr)
nl=$(grep -cE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:' bootstrap/cybs.cyr)
if [ "$sz" -ge 131072 ]; then bad "S: bootstrap/cybs.cyr is $sz B — the seed reads 131072 and silently drops the rest"
elif [ "$nl" -gt 512 ]; then bad "S: bootstrap/cybs.cyr defines $nl labels — the seed's label table holds 512"
else echo "  ok   S: bootstrap/cybs.cyr fits the seed: $sz / 131072 B, $nl / 512 labels"; fi

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_call_arity_named: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }
cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
cmp -s "$D/asm2" bootstrap/asm && echo "  ok   A: closure — cybs reproduces the seed" || bad "A: closure — cybs no longer reproduces the seed"

# B — each check adds its bit; all six = 63. Compiled from ROOT, so `include "lib/fnptr.cyr"`
# resolves (cybs predefines CYRIUS_TARGET_LINUX / CYRIUS_ARCH_X86: fncallN's x86 asm is live).
cat > "$D/sa.cyr" <<'EOF'
include "lib/fnptr.cyr"
var gr = 0;
fn f7(a, b, c, d, e, g, h) { return a * 1000000 + b * 100000 + c * 10000 + d * 1000 + e * 100 + g * 10 + h; }
fn f8(a, b, c, d, e, g, h, i) { return a + b + c + d + e + g - 21 + h * 10 + i; }
fn f9(a, b, c, d, e, g, h, i, j) {
    var t = h * 100 + i * 10 + j;
    return t + a + b + c + d + e + g - 21;
}
fn s9(a, b, c, d, e, g, h, i, j) { gr = j * 100 + i * 10 + h; return 0; }
fn bump(x) { return x + 1; }
fn t1() { return f7(1, 2, 3, 4, 5, 6, 7); }
fn t2() { return f9(1, 2, 3, 4, 5, 6, 7, 8, 9); }
fn t3() {
    var k = 5;
    return k + f9(1, 2, 3, 4, 5, 6, bump(6), 8, f7(0, 0, 0, 0, 0, 0, 9)) * 2;
}
fn t4() { s9(1, 2, 3, 4, 5, 6, 7, 8, 9); return gr; }
fn t5() { return fncall8(&f8, 1, 2, 3, 4, 5, 6, 7, 8); }
fn t6() { return fncall7(&f7, 7, 6, 5, 4, 3, 2, 1); }
var ok = 0;
if (t1() == 1234567) { ok = ok + 1; }
if (t2() == 789) { ok = ok + 2; }
if (t3() == 5 + 789 * 2) { ok = ok + 4; }
if (t4() == 987) { ok = ok + 8; }
if (t5() == 78) { ok = ok + 16; }
if (t6() == 7654321) { ok = ok + 32; }
syscall(60, ok);
EOF
rc=0; "$D/cybs" < "$D/sa.cyr" > "$D/sa" 2> "$D/sa.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/sa" ]; then bad "B: cybs refused 7+ argument calls (rc $rc): $(head -1 "$D/sa.err")"
else
  chmod +x "$D/sa"
  got=0; "$D/sa" || got=$?
  if [ "$got" -eq 63 ]; then echo "  ok   B: 7- and 9-argument calls (statement, mid-expression, nested, fncall7/fncall8) return the right values"
  else bad "B: 7+ argument calls exited $got, want 63 (bits: 1 f7, 2 f9, 4 k + f9(.., f7(..)), 8 statement s9, 16 fncall8, 32 fncall7)"; fi
fi
if [ -x "$CC" ]; then
  "$CC" < "$D/sa.cyr" > "$D/sa_cc" 2>/dev/null || true
  chmod +x "$D/sa_cc" 2>/dev/null || true
  got=0; [ -s "$D/sa_cc" ] && { "$D/sa_cc" || got=$?; }
  [ "$got" -eq 63 ] || bad "B: the fixture is not valid cyrius any more — $(basename "$CC") exited $got, want 63"
fi

printf 'fn f(a, b, c, d, e, g) { return a + g; }\nsyscall(60, f(1, 2, 3, 4, 5, 41));\n' > "$D/c6.cyr"
"$D/cybs" < "$D/c6.cyr" > "$D/c6" 2>/dev/null || true
chmod +x "$D/c6" 2>/dev/null || true
got=0; "$D/c6" || got=$?
[ "$got" -eq 42 ] && echo "  ok   C: a 6-argument call compiles and runs (exit 42)" || bad "C: a 6-argument call exited $got, want 42"

rc=0; "$D/cybs" < src/main.cyr > "$D/gen1" 2> "$D/gen1.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/gen1" ]; then bad "D: cybs could not compile src/main.cyr (rc $rc): $(head -1 "$D/gen1.err")"
else echo "  ok   D: cybs compiles src/main.cyr"; fi

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_call_arity_named — $fail row(s) red"; exit 1; fi
echo "PASS: cybs_call_arity_named — cybs passes 7+ arguments on the stack (7- and 9-argument calls, fncall7/fncall8 right), a 6-argument call works, and cybs compiles src/main.cyr (closure intact)"
