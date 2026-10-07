#!/bin/sh
# tests/gates/toolchain/cybs_call_arity_named.sh — 6.7.0
#
# cybs (the hand-assembly bootstrap compiler the seed assembles) passes only the six register
# arguments: `emit_fn_call_pops` handles 0..6. A call with 7+ arguments used to fall to
# `parse_err` and print a bare "syntax error" — found at 6.7.0, when a 7-argument helper call in
# src/frontend/parse_decl.cyr broke seed-derive with nothing to say why. It is refused BY NAME
# now, and this gate runs cybs over src/main.cyr in check.sh, so such a call in the bootstrap
# path is caught by the normal suite, not first by seed-derive in the release gate.
# (A DEFINITION with 7+ parameters keeps its first six — lib/fnptr.cyr's fncall6..8 are such —
# and is unreachable with all its arguments: see the comment at `emit_store_param`. Teaching cybs
# real stack arguments is scheduled in roadmap.md, v6.7.x.)
#
#   A  closure: the seed assembles cybs, and cybs reproduces the seed
#   B  a 7-argument call is refused naming the limit, not "syntax error"
#   C  ANTI-VACUOUS: a 6-argument call still compiles and runs (exit 42)
#   D  cybs compiles src/main.cyr (no 7+ argument call in the bootstrap path)
#
# Mutation: point `emit_fn_call_pops`'s 7+ arm back at `parse_err` -> B RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_call_arity_named: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_call_arity_named: bootstrap/asm missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_call_arity_named: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_call_arity_named $1"; fail=$((fail + 1)); }

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_call_arity_named: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }
cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
cmp -s "$D/asm2" bootstrap/asm || bad "A: closure — cybs no longer reproduces the seed"

printf 'fn f(a, b, c, d, e, g, h) { return a + h; }\nsyscall(60, f(1, 2, 3, 4, 5, 6, 7));\n' > "$D/c7.cyr"
rc=0; "$D/cybs" < "$D/c7.cyr" > "$D/c7" 2> "$D/c7.err" || rc=$?
if [ "$rc" -eq 0 ]; then bad "B: a 7-argument call compiled (rc 0)"
elif grep -q "more than 6 arguments" "$D/c7.err"; then echo "  ok   B: a 7-argument call is refused naming the limit"
else bad "B: a 7-argument call failed without naming the limit: $(head -1 "$D/c7.err")"; fi

printf 'fn f(a, b, c, d, e, g) { return a + g; }\nsyscall(60, f(1, 2, 3, 4, 5, 41));\n' > "$D/c6.cyr"
"$D/cybs" < "$D/c6.cyr" > "$D/c6" 2>/dev/null || true
chmod +x "$D/c6" 2>/dev/null || true
got=0; "$D/c6" || got=$?
[ "$got" -eq 42 ] && echo "  ok   C: a 6-argument call compiles and runs (exit 42)" || bad "C: a 6-argument call exited $got, want 42"

rc=0; "$D/cybs" < src/main.cyr > "$D/gen1" 2> "$D/gen1.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/gen1" ]; then bad "D: cybs could not compile src/main.cyr (rc $rc): $(head -1 "$D/gen1.err")"
else echo "  ok   D: cybs compiles src/main.cyr"; fi

if [ "$fail" -ne 0 ]; then echo "FAIL: cybs_call_arity_named — $fail row(s) red"; exit 1; fi
echo "PASS: cybs_call_arity_named — cybs refuses a 7+ argument call by name, a 6-argument call works, and cybs compiles src/main.cyr (closure intact)"
