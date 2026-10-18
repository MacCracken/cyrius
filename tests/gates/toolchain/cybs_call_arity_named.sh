#!/bin/sh
# tests/gates/toolchain/cybs_call_arity_named.sh — 6.7.0, stack arguments 6.7.6, variable callees 6.7.6 BX,
# the seed's CODE cap 6.7.11
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
#   S  bootstrap/cybs.cyr fits the seed's three unchecked caps: input < 131072 B (past it the seed
#      drops the rest silently), at most 512 labels, and cybs's code < 65536 B (6.7.11: past it the
#      seed overwrites its own label tables and output, silently)
#   S2 src/main.cyr's include closure, as cybs's preprocessor walks it, keeps clear of the preprocessor's
#      buffers with headroom (6.7.14): no included file reaches 2 MB (an include slot), the nesting stays
#      under 8 (the slots), and the input and the expanded stream stay under 15 MB (the input buffer;
#      the expansion buffer is 16 MB). cybs refuses each past its cap since 6.7.14
#      (cybs_diagnostics_named.sh P), so this row is the early warning, before seed-derive stops. The
#      walker (awk) is checked against cybs itself: a copy of cybs that writes its expanded stream and
#      exits must give exactly the walker's length. issues/archived/2026-10-13-cybs-include-scratch-and-buffers-unchecked.md
#   B  a 7- and a 9-argument call return the right values — as statements, inside an expression
#      with a value pending (`k + f9(..)`), with a 7-argument call as an argument, and through
#      lib/fnptr.cyr's fncall7 / fncall8 (their 7+ parameters stored, their stack arguments read by
#      a cybs-compiled callee); the same program under build/cycc agrees. Every callee weighs its
#      arguments by POSITION (f8 is `.. + h * 10 + i`), so a swapped pair of stack arguments is red
#      under either compiler — lane E2 had made f8 symmetric while cybs and cycc disagreed (D3).
#   C  ANTI-VACUOUS: a 6-argument call still compiles and runs (exit 42)
#   E  a call through a function-pointer VARIABLE keeps every argument (6.7.6 BX): cybs loaded a
#      global callee with emit_var_load's `movabs rcx, &g; mov rax, [rcx]` AFTER the argument
#      registers, so argument 4 (rcx) arrived as the global's address — `gp = &f4; gp(1, 2, 3, 4)`
#      gave 1230 + junk. Now `mov rax, [&g]` (48 A1). Rows: a global inside a fn and at top
#      level, a 7-argument call through a global (cycc's stack order), and the local and param
#      shapes (rbp-relative, never clobbered). Calling a variable BY NAME is cybs's spelling;
#      cycc's is `callptr(gp, ..)` — the gate derives both from one template and requires each
#      compiler's run to set all five bits.
#   D  cybs compiles src/main.cyr
#
# Mutations (6.7.6, each verified RED on B in a scratch copy of the tree):
#   emit_store_param's i >= 6 arm back to `jmp emit_sp_done`  (parameters 7+ never stored)
#   emit_fn_call_pops copies from [rsp + 8k] instead of [rsp + 16k]  (lane B's copy loop; gone in D3)
#   emit_fn_call_clean emits nothing                        (`k + f9(..)` pops a stale word)
#   rdi and rsi register loads swapped                       (register arguments misrouted)
#   cybs.cyr padded with comments past 131072 B / given 20 more labels    -> S RED
# 6.7.14 (S2, a scratch copy of the gate each):
#   the file ceiling lowered to 900000 (parse_fn.cyr is ~949 KB)          -> S2 RED (names the file)
#   the walker's `#else` arm dropped (both branches emitted)              -> S2 RED (walker != cybs)
#   (6.7.11: emit_sp_done is a comment in cybs.cyr now, sparing a seed label; restore the label
#   to re-run the first mutation.)
# 6.7.11 (the CODE row; a scratch copy of the gate, because an honest over-cap cybs.cyr cannot be
# built inside the input cap — the seed has no fill directive, so cybs is ~0.19 code B per input B):
#   CODE_CAP lowered to 21000, below cybs's 21,660 B of code          -> S RED (code), A..D green
# D3 (cycc's order; each a scratch copy of the tree with the one change, 2026-10-08):
#   lane B's cybs.cyr (the SysV order) under the restored f8      -> B exits 47 (fncall8, bit 16)
#   emit_store_param reads [rbp + 16 + (i-6)*8] again (SysV slot) -> B exits 1
#   parse_fn_def does not call count_params (n stays 0)            -> B exits 0
#   emit_fn_call_clean drops lane B's 2n-6 words                   -> B exits 59 (`k + f9(..)`)
#   emit_fn_call_pops loads a[0] from [rsp + 8(n-2)]               -> B exits 139
# BX (the variable-callee load; each a scratch copy of the tree with the one change, 2026-10-08):
#   pffn_local_g calls emit_var_load again (the 6.7.5 code)          -> E exits 24 (bits 1, 2, 4)
#   only the top-level arm goes back to emit_var_load                -> E exits 29 (bit 2)
#   the 48 A1 load records no fixup (address 0)                      -> E exits 139
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_call_arity_named: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_call_arity_named: bootstrap/asm missing"; exit 77; }
CC=${CYCC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_call_arity_named: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_call_arity_named $1"; fail=$((fail + 1)); }

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_call_arity_named: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }

# S — the seed (bootstrap/asm, from bootstrap/asm.cyr) checks none of its three fixed caps, so
# cybs.cyr, the one input it assembles, must stay inside each; the seed itself is the trust root
# (issues/2026-10-08-seed-asm-silent-caps-input-labels-code.md):
#   input  131072 B — past it the read stops and the rest is DROPPED with exit 0 (probed 6.7.6: 3
#          bytes over assembled a cybs 1 byte short, silently);
#   labels 512 — ADDL writes entry 512+k over the next table (a false `label not found`, or worse);
#   code   65536 B — EB stores past CODE into the label tables and then into OUT, and EELF copies
#          back bytes it has already overwritten: the emitted tail is earlier output, silently. The
#          assembled cybs is EELF's 120 B header + the code (fsz = 120 + cp). CHANGELOG [6.7.11]
CODE_CAP=65536
sz=$(wc -c < bootstrap/cybs.cyr)
nl=$(grep -cE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:' bootstrap/cybs.cyr)
code=$(( $(wc -c < "$D/cybs") - 120 ))
if [ "$sz" -ge 131072 ]; then bad "S: bootstrap/cybs.cyr is $sz B — the seed reads 131072 and silently drops the rest"
elif [ "$nl" -gt 512 ]; then bad "S: bootstrap/cybs.cyr defines $nl labels — the seed's label table holds 512"
elif [ "$code" -ge "$CODE_CAP" ]; then bad "S: cybs's code is $code B — the seed's CODE buffer holds $CODE_CAP and past it overwrites its label tables and output, silently"
else echo "  ok   S: bootstrap/cybs.cyr fits the seed: $sz / 131072 B input, $nl / 512 labels, $code / $CODE_CAP B code"; fi

# S2 — the walk mirrors pp_expand: a directive at a line's start after blanks; #ifdef / #ifndef / #else
# / #endif on one stack across files; a name is defined when it reads CYRIUS_ARCH_X.. or
# CYRIUS_TARGET_L.. (pp_defined); `include "f"` taken while emitting, once per spelling, from ROOT.
cat > "$D/walk.awk" <<'EOF'
function defd(n) { return (substr(n, 8, 1) == "A" && substr(n, 13, 1) == "X") || (substr(n, 8, 1) == "T" && substr(n, 15, 1) == "L") }
function nm(r) { sub(/^[ \t]+/, "", r); return r }
function push(c) { saved[sp] = emit; cond[sp] = c; if (c == 0) emit = 0; sp++ }
function ln(l, depth,   t, f) {
  t = l; sub(/^[ \t]+/, "", t)
  if (substr(t, 1, 1) == "#") {
    if (substr(t, 2, 6) == "ifdef ") { push(defd(nm(substr(t, 8)))); return }
    if (substr(t, 2, 7) == "ifndef ") { push(1 - defd(nm(substr(t, 9)))); return }
    if (substr(t, 2, 4) == "else") { emit = (saved[sp - 1] == 1 && cond[sp - 1] == 0); return }
    if (substr(t, 2, 5) == "endif") { sp--; emit = saved[sp]; return }
  } else if (substr(t, 1, 8) == "include ") {
    if (emit == 1 && substr(t, 9, 1) == "\"") { f = substr(t, 10); sub(/".*/, "", f); inc(f, depth) }
    return
  }
  if (emit == 1) out += length(l) + 1
}
function inc(f, depth,   l, sz) {
  if (f in seen) return
  seen[f] = 1
  if (depth + 1 > maxd) { maxd = depth + 1; deepf = f }
  sz = 0
  while ((getline l < f) > 0) { sz += length(l) + 1; ln(l, depth + 1) }
  close(f)
  if (sz > maxsz) { maxsz = sz; bigf = f }
}
BEGIN { emit = 1; sp = 0 }
{ insz += length($0) + 1; ln($0, 0) }
END { print insz, maxsz, bigf, maxd, deepf, out }
EOF
awk '{ print } /^    call preprocess$/ && !d { print "    mov rax, 1"; print "    mov rdi, 1"; print "    mov rsi, r15"; print "    mov rdx, r12"; print "    syscall"; print "    call sys_exit_ok"; d = 1 }' \
  bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs_pp" 2>/dev/null || true
chmod +x "$D/cybs_pp" 2>/dev/null || true
read -r w_in w_max w_big w_dep w_deep w_out <<EOF
$(LC_ALL=C awk -f "$D/walk.awk" < src/main.cyr)
EOF
pp_out=$("$D/cybs_pp" < src/main.cyr 2>/dev/null | wc -c | tr -d ' ')
if [ -z "${w_out:-}" ] || [ "${pp_out:-0}" -eq 0 ]; then bad "S2: the closure walk produced nothing (walker [${w_out:-}], cybs's own expansion ${pp_out:-0} B)"
elif [ "$w_out" -ne "$pp_out" ]; then bad "S2: the walker's expansion of src/main.cyr is $w_out B, cybs's own is $pp_out B — the walker no longer mirrors pp_expand"
elif [ "$w_max" -ge 2097152 ]; then bad "S2: $w_big is $w_max B — cybs's include slot holds 2 MB (2097152), cybs refuses it"
elif [ "$w_dep" -ge 8 ]; then bad "S2: $w_deep is included $w_dep deep — cybs has 8 include slots"
elif [ "$w_in" -ge 15728640 ] || [ "$w_out" -ge 15728640 ]; then bad "S2: src/main.cyr is $w_in B, $w_out B expanded — cybs's input buffer takes 15 MB, its expansion buffer 16 MB"
else echo "  ok   S2: src/main.cyr's include closure fits cybs's preprocessor: largest $w_big $w_max / 2097152 B, $w_dep / 8 deep ($w_deep), $w_out B expanded / 15728640 (cybs's own expansion agrees)"; fi

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

# E — IND(fp, ..) is `fp(..)` for cybs and `callptr(fp, ..)` for cycc; each check adds its bit, 31.
cat > "$D/ind.tpl" <<'EOF'
var gp = 0;
var gq = 0;
fn f4(a, b, c, d) { return a * 1000 + b * 100 + c * 10 + d; }
fn f7(a, b, c, d, e, g, h) { return a * 1000000 + b * 100000 + c * 10000 + d * 1000 + e * 100 + g * 10 + h; }
fn t1() { gp = &f4; return IND(gp, 1, 2, 3, 4); }
fn t3() { gq = &f7; return IND(gq, 1, 2, 3, 4, 5, 6, 7); }
fn t4() { var p = &f4; return IND(p, 1, 2, 3, 4); }
fn tp(q) { return IND(q, 7, 6, 5, 4, 3, 2, 1); }
fn t5() { return tp(&f7); }
var ok = 0;
if (t1() == 1234) { ok = ok + 1; }
var r2 = IND(gp, 4, 3, 2, 1);
if (r2 == 4321) { ok = ok + 2; }
if (t3() == 1234567) { ok = ok + 4; }
if (t4() == 1234) { ok = ok + 8; }
if (t5() == 7654321) { ok = ok + 16; }
syscall(60, ok);
EOF
sed 's/IND(\([a-z]*\), /\1(/g' "$D/ind.tpl" > "$D/ind_cybs.cyr"
sed 's/IND(/callptr(/g' "$D/ind.tpl" > "$D/ind_cycc.cyr"
ebits="bits: 1 global in a fn, 2 global at top level, 4 global 7 arguments, 8 local, 16 param 7 arguments"
rc=0; "$D/cybs" < "$D/ind_cybs.cyr" > "$D/ind" 2> "$D/ind.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/ind" ]; then bad "E: cybs refused a call through a function-pointer variable (rc $rc): $(head -1 "$D/ind.err")"
else
  chmod +x "$D/ind"
  got=0; "$D/ind" || got=$?
  if [ "$got" -eq 31 ]; then echo "  ok   E: calls through a global / local / param function pointer keep all their arguments (4 and 7)"
  else bad "E: calls through a function-pointer variable exited $got, want 31 ($ebits)"; fi
fi
if [ -x "$CC" ]; then
  "$CC" < "$D/ind_cycc.cyr" > "$D/ind_cc" 2>/dev/null || true
  chmod +x "$D/ind_cc" 2>/dev/null || true
  got=0; [ -s "$D/ind_cc" ] && { "$D/ind_cc" || got=$?; }
  [ "$got" -eq 31 ] || bad "E: the fixture is not valid cyrius any more — $(basename "$CC") (callptr spelling) exited $got, want 31 ($ebits)"
fi

rc=0; "$D/cybs" < src/main.cyr > "$D/gen1" 2> "$D/gen1.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/gen1" ]; then bad "D: cybs could not compile src/main.cyr (rc $rc): $(head -1 "$D/gen1.err")"
else echo "  ok   D: cybs compiles src/main.cyr"; fi

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_call_arity_named — $fail row(s) red"; exit 1; fi
echo "PASS: cybs_call_arity_named — cybs.cyr fits the seed (input, labels, code), src/main.cyr's include closure fits cybs's preprocessor with headroom, cybs passes 7+ arguments on the stack (7- and 9-argument calls, fncall7/fncall8 right), a 6-argument call works, a call through a function-pointer variable keeps argument 4, and cybs compiles src/main.cyr (closure intact)"
