#!/bin/sh
# string_token_decoders.sh — every consumer of a string-literal token value decodes
# the SAME pack the lexer produces, and the text it prints is the literal's text.
#
# v6.6.4. The lexer packs a string token as `(pool offset << 32) | length` (was
# `<< 16` — a 16-bit length that shifted every literal >= 64 KB, see
# tests/tcyr/frontend/string_literal_64k.tcyr). There are FOUR decoders of that
# value: ESADDR (every string expression — pinned by the whole corpus), the
# `#assert` failure message and `#pe_import` symbol name in parse.cyr, and the
# `#deprecated` message in parse_fn.cyr. ⛔ Nothing in the tree asserted the TEXT
# of the last three: a compiler with the #deprecated decoder left at the old pack
# still self-hosted at the same size, passed tests/tcyr/lang/deprecated_attr.tcyr
# 3/3, and printed every deprecation message as NUL bytes (measured during the
# 6.6.4 review). Small literals suffice — under the new pack, a decoder at the old
# shift reads offset 0 / length 0 for EVERY message, so any skew garbles the text.
#
# Axis 2 also pins a second v6.6.4 fix: `return olde();` (the TAIL-CALL path)
# bypassed PARSE_FNCALL and warned NOTHING, contradicting the "fires at EVERY call
# site" contract; the warning is now one helper (_DEPRECATED_WARN) on both paths.
#
# Mutation-proven: reverting parse_fn.cyr's decoder to `>> 16` / `& 0xFFFF` reds
# axes 1-2; reverting parse.cyr:1534-1535 reds axis 3; reverting :1576 reds axis 4;
# dropping the tail-path _DEPRECATED_WARN call reds axis 2 alone.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: string_token_decoders: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

PRE='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
'

echo "axis 1 — #deprecated message text at an ordinary call site:"
cat > "$D/a1.cyr" <<EOF
$PRE
#deprecated("use newe instead — marker-DEP-ONE")
fn olde(): i64 { return 1; }
fn main(): i64 { var v = olde(); return v; }
var r = main();
syscall(60, r);
EOF
rc=0; "$CC" < "$D/a1.cyr" > "$D/a1" 2> "$D/a1.err" || rc=$?
if [ "$rc" -eq 0 ] && [ -s "$D/a1" ] && grep -q "'olde' is deprecated: use newe instead — marker-DEP-ONE" "$D/a1.err"; then
    ok "ordinary call prints the full message"
else bad "ordinary call (rc=$rc): $(head -c 300 "$D/a1.err")"; fi

echo "axis 2 — #deprecated fires on the TAIL-CALL path too (return olde();):"
cat > "$D/a2.cyr" <<EOF
$PRE
#deprecated("marker-DEP-TAIL")
fn olde(): i64 { return 1; }
fn main(): i64 { return olde(); }
var r = main();
syscall(60, r);
EOF
rc=0; "$CC" < "$D/a2.cyr" > "$D/a2" 2> "$D/a2.err" || rc=$?
n=$(grep -c "'olde' is deprecated: marker-DEP-TAIL" "$D/a2.err" || true)
if [ "$rc" -eq 0 ] && [ -s "$D/a2" ] && [ "$n" -eq 1 ]; then
    ok "tail call warns exactly once with the message"
else bad "tail call (rc=$rc, matches=$n): $(head -c 300 "$D/a2.err")"; fi

echo "axis 3 — a failing #assert prints ITS message and emits no binary:"
cat > "$D/a3.cyr" <<EOF
$PRE
#assert 1 == 2, "marker-ASSERT-TEXT";
fn main(): i64 { return 0; }
var r = main();
syscall(60, r);
EOF
rc=0; "$CC" < "$D/a3.cyr" > "$D/a3" 2> "$D/a3.err" || rc=$?
if [ "$rc" -ne 0 ] && [ ! -s "$D/a3" ] && grep -q "#assert failed: marker-ASSERT-TEXT" "$D/a3.err"; then
    ok "#assert failure names the message, rc=$rc, no output"
else bad "#assert (rc=$rc, size=$(wc -c < "$D/a3")): $(head -c 300 "$D/a3.err")"; fi

echo "axis 4 — #pe_import symbol name reaches the PE import table:"
cat > "$D/a4.cyr" <<EOF
$PRE
#pe_import("kernel32.dll", "GetLogicalDrives");
fn main(): i64 { return 0; }
var r = main();
syscall(60, r);
EOF
rc=0; CYRIUS_TARGET_WIN=1 "$CC" < "$D/a4.cyr" > "$D/a4.exe" 2> "$D/a4.err" || rc=$?
if [ "$rc" -eq 0 ] && [ -s "$D/a4.exe" ] && grep -a -q "GetLogicalDrives" "$D/a4.exe"; then
    ok "import name is present in the .exe"
else bad "pe_import (rc=$rc, size=$(wc -c < "$D/a4.exe")): $(head -c 300 "$D/a4.err")"; fi

echo "axis 5 — anti-vacuous: a control with NO directive prints no such text:"
cat > "$D/a5.cyr" <<EOF
$PRE
fn olde(): i64 { return 1; }
fn main(): i64 { return olde(); }
var r = main();
syscall(60, r);
EOF
rc=0; "$CC" < "$D/a5.cyr" > "$D/a5" 2> "$D/a5.err" || rc=$?
if [ "$rc" -eq 0 ] && [ -s "$D/a5" ] && ! grep -q "is deprecated" "$D/a5.err" && ! grep -a -q "GetLogicalDrives" "$D/a5"; then
    ok "control is silent"
else bad "control (rc=$rc): $(head -c 200 "$D/a5.err")"; fi

echo "string_token_decoders: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
