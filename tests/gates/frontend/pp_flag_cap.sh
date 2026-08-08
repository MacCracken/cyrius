#!/bin/sh
# v6.4.15 (absorber-band L1): the lex_pp #define/#ifdef feature-flag table is a
# FIXED 16-slot array — the hash table at S+0x190800 and the value table at
# S+0x190880 are only 0x80 bytes (16 slots) apart. Before v6.4.15 the 17th
# registered flag silently wrote its hash over value[0] (heap corruption with no
# diagnostic). PP_PREDEFINE / PP_DEFINE now hard-error past 16 total entries.
#
# The counter is SHARED across builtin predefines (CYRIUS_ARCH_*, CYRIUS_TARGET_*,
# ~3 on Linux x86_64) and user #defines, so the user budget is 16 minus whatever
# builtins the active target fires. This test stays target-robust: 20 user
# #defines exceed the cap on ANY target (even with 0 builtins), and 5 stay well
# under it (even with the worst-case ~9 builtins).
#
# Reject-test convention (cannot use assert_summary — the program must fail to
# compile): exit code + stderr grep, like tests/gates/codegen/simd_vec_reject.sh.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
T=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$E"' EXIT

# --- Guard: 20 #defines overflow the 16-slot table -> hard-error ---
: > "$T"
i=0; while [ "$i" -lt 20 ]; do echo "#define PPCAP_D$i" >> "$T"; i=$((i + 1)); done
echo 'fn main(): i64 { return 0; }' >> "$T"
echo 'var ec = main();' >> "$T"
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: 20 #defines compiled — must hard-error (16-slot table overflow)"; exit 1
fi
grep -q 'too many preprocessor #define/flag entries' "$E" || { echo "FAIL: overflow gave wrong error:"; cat "$E"; exit 1; }

# --- Positive control: a handful of #defines compile clean ---
: > "$T"
i=0; while [ "$i" -lt 5 ]; do echo "#define PPCAP_D$i" >> "$T"; i=$((i + 1)); done
echo 'fn main(): i64 { return 0; }' >> "$T"
echo 'var ec = main();' >> "$T"
"$CC" < "$T" > /dev/null 2>&1 || { echo "FAIL: 5 #defines failed to compile (guard over-firing?)"; exit 1; }

echo "PASS: PP flag table hard-errors past 16 entries; small #define sets compile clean (L1, v6.4.15)"
