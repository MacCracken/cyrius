#!/bin/sh
# dead_static_hint_every_backend.sh — 6.6.10. The two fixup diagnostics that read the liveness
# pass say what they mean, on every backend that has one.
#
# (1) THE DEAD-STATIC HINT. Under "warning: large static data", a hint names the static bytes
#     declared inside UNREACHABLE fns ("DCE NOPs code but keeps .bss"). Two defects:
#       - only the x86 FIXUP computed it; the aarch64 FIXUP had live[] and never did, and its
#         EMITELF passed 0, 0 — so the hint never fired on aarch64 ELF or arm64 Mach-O;
#       - the x86 loop counted EVERY dead fn: one static holder plus two empty dead fns printed
#         "inside 3 unreachable fn(s)".
#     Fix: _dead_static_stash (src/backend/common/runtime.cyr), shared by both FIXUPs, counts
#     only dead fns with GFVB > 0. Rows: x86 ELF, PE, x86 Mach-O, aarch64 ELF, arm64 Mach-O each
#     print "200000 bytes inside 1 unreachable fn(s)" for the fixture below; the anti-vacuous
#     twin (the same static in a REACHABLE fn) prints the warning and NO hint. cx has no liveness
#     pass, so it has no hint (stated, not gated).
# (2) THE REACHABLE-UNDEFINED WORDING. The second warning line before the reachable-undefined
#     refusal said "(call site may be unreachable)" — printed ONLY for sites the v5.11.59 filter
#     had judged REACHABLE, one line above "refusing to emit binary with 1 reachable undefined
#     function(s)". It reads "(reachable call site)" now, on x86, PE and aarch64; and the old
#     inverted text appears nowhere.
# CHANGELOG [6.6.10]
#
# MUTATION (6.6.10, built and run): drop the aarch64 _dead_static_stash call → the aarch64 ELF
# and arm64 Mach-O hint rows go red; restore "count every dead fn" → the three x86-family rows
# say "inside 3" → red; restore the old suffix → the three wording rows go red.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL dead_static_hint_every_backend: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL dead_static_hint_every_backend: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0

"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" || { echo "FAIL dead_static_hint_every_backend: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
"$T/x86" < src/main_aarch64.cyr > "$T/aarch64" 2> "$T/eb" || { echo "FAIL dead_static_hint_every_backend: could not build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/aarch64"
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# one 200000-byte static in a dead fn, plus TWO dead fns that hold nothing
cat > "$T/dead.cyr" <<'EOF'
fn dead_holder(): i64 { var b[200000]; return load8(&b); }
fn dead_empty1(): i64 { return 1; }
fn dead_empty2(): i64 { return 2; }
fn main(): i64 { return 0; }
var r = main();
EOF
# the same static, reachable
cat > "$T/live.cyr" <<'EOF'
fn holder(): i64 { var b[200000]; return load8(&b); }
fn main(): i64 { return holder(); }
var r = main();
EOF
cat > "$T/undef.cyr" <<'EOF'
fn main(): i64 { return nope(1); }
var r = main();
EOF

# comp <env-assignment|-> <compiler> <fixture> — stderr in $T/e
comp() {
  if [ "$1" = - ]; then env -u CYRIUS_TARGET_WIN -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM "$T/$2" < "$T/$3.cyr" > "$T/o" 2> "$T/e"
  else env -u CYRIUS_TARGET_WIN -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM "$1" "$T/$2" < "$T/$3.cyr" > "$T/o" 2> "$T/e"; fi
}

for cfg in "x86-ELF - x86" "PE CYRIUS_TARGET_WIN=1 x86" "x86-Mach-O CYRIUS_MACHO=1 x86" "aarch64-ELF - aarch64" "arm64-Mach-O CYRIUS_MACHO_ARM=1 aarch64"; do
  set -- $cfg
  comp "$2" "$3" dead
  if ! grep -q '^warning: large static data' "$T/e"; then _bad "$1: no large-static warning at all (anti-vacuous: the fixture must trigger it)"
  elif ! grep -q '^  hint: 200000 bytes inside 1 unreachable fn(s)' "$T/e"; then _bad "$1: expected 'hint: 200000 bytes inside 1 unreachable fn(s)', got: $(grep -m1 'hint:' "$T/e" || echo 'no hint')"
  else pass=$((pass + 1)); fi
  comp "$2" "$3" live
  if ! grep -q '^warning: large static data' "$T/e"; then _bad "$1 live twin: no large-static warning"
  elif grep -q 'hint:' "$T/e"; then _bad "$1 live twin: a hint about unreachable fns for a static in a REACHABLE fn"
  else pass=$((pass + 1)); fi
done

for cfg in "x86 - x86" "PE CYRIUS_TARGET_WIN=1 x86" "aarch64 - aarch64"; do
  set -- $cfg
  comp "$2" "$3" undef
  if ! grep -q 'refusing to emit binary with 1 reachable undefined' "$T/e"; then _bad "$1 undef: the reachable-undefined refusal did not fire (anti-vacuous)"
  elif ! grep -qx "warning: undefined function 'nope' (reachable call site)" "$T/e"; then _bad "$1 undef: no \"(reachable call site)\" line"
  elif grep -q 'may be unreachable' "$T/e"; then _bad "$1 undef: the inverted \"may be unreachable\" wording is back"
  else pass=$((pass + 1)); fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL dead_static_hint_every_backend: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS dead_static_hint_every_backend: $pass rows — the dead-static hint fires on x86 ELF/PE/x86 Mach-O/aarch64 ELF/arm64 Mach-O counting only static-holding dead fns (not in reachable twins); the reachable-undefined line reads '(reachable call site)'"
exit 0
