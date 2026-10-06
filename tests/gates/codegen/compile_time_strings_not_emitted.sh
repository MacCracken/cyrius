#!/bin/sh
# compile_time_strings_not_emitted.sh — 6.6.17. A string only a DIAGNOSTIC reads — a
# `#deprecated("…")` message, an `#assert …, "…"` message (including the ones `#derive`
# generates) — is not in the binary.
#
# THE DEFECT. The lexer's string pool is copied into every binary whole, so each such message
# cost its bytes in .rodata whether or not anything referenced it (+16 B for "use new_f"; the
# `#derive` layout backstop's 120-byte message rode along in every program including a #derive'd
# struct). The lexer now moves a directive's message to a side table the two diagnostics read
# (`_lex_dir_msg_fix` / `_lit_ptr`, src/frontend/lex.cyr).
#
# Rows, through x86, the aarch64 cross, PE (CYRIUS_TARGET_WIN=1) and cx:
#   I  the same program with long messages, with different short ones, and with no #assert at
#      all compiles BYTE-IDENTICAL (on the slot-open compiler the three differ).
#   D  the diagnostics still print the messages: the deprecation warning and a failing #assert.
#   L  ANTI-VACUOUS: a real literal whose text equals a message — one lexed BEFORE the message
#      (the message shares its bytes) and one AFTER it — is still emitted and prints at run time.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: compile_time_strings_not_emitted: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: compile_time_strings_not_emitted: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: compile_time_strings_not_emitted: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
"$CC" < src/main_aarch64.cyr > "$D/xa64" 2>/dev/null && chmod +x "$D/xa64" \
  || { echo "FAIL: compile_time_strings_not_emitted: could not build src/main_aarch64.cyr"; exit 1; }
"$CC" < src/main_cx.cyr > "$D/xcx" 2>/dev/null && chmod +x "$D/xcx" \
  || { echo "FAIL: compile_time_strings_not_emitted: could not build src/main_cx.cyr"; exit 1; }
fail=0
bad() { echo "  FAIL: compile_time_strings_not_emitted $1"; fail=$((fail + 1)); }

# gen <file> <dep-msg> <assert-block>
gen() {
  printf 'struct Pt { x; y; z; }\nfn new_f(): i64 { return 7; }\n#deprecated("%s")\nfn old_f(): i64 { return 2; }\n%s\nfn main(): i64 { return new_f(); }\nvar r = main();\nsyscall(60, r);\n' "$2" "$3" > "$D/$1"
}
gen long.cyr "use new_f, which returns the same value and is not deprecated" '#assert sizeof(Pt) == 24, "Pt must stay three words: the wire format depends on it";
#assert 1 == 1,
  "a wrapped message on the next line";'
gen short.cyr "x" '#assert sizeof(Pt) == 24, "y";
#assert 1 == 1, "z";'
gen none.cyr "q" ''
for c in "$CC" "$D/xa64" "WIN" "$D/xcx"; do
  if [ "$c" = WIN ]; then l=PE; run() { CYRIUS_TARGET_WIN=1 "$CC" < "$1" > "$2" 2> "$2.err"; }
  else l=$(basename "$c"); run() { "$c" < "$1" > "$2" 2> "$2.err"; }; fi
  for f in long short none; do run "$D/$f.cyr" "$D/$f.$l" || true; done
  [ -s "$D/long.$l" ] || { bad "I $l: the long-message program did not compile"; continue; }
  cmp -s "$D/long.$l" "$D/short.$l" || bad "I $l: changing only the message text changed the binary ($(wc -c < "$D/long.$l") vs $(wc -c < "$D/short.$l") B)"
  cmp -s "$D/long.$l" "$D/none.$l" || bad "I $l: the #assert messages are in the binary (with: $(wc -c < "$D/long.$l") B, without: $(wc -c < "$D/none.$l") B)"
done

# D — the diagnostics still read the messages
printf 'fn new_f(): i64 { return 1; }\n#deprecated("use new_f instead")\nfn old_f(): i64 { return 2; }\nvar a = old_f();\n#assert 1 == 2, "the false assertion";\n' > "$D/d.cyr"
"$CC" < "$D/d.cyr" > "$D/d.bin" 2> "$D/d.err" || true
grep -q "'old_f' is deprecated: use new_f instead" "$D/d.err" || bad "D: the deprecation warning lost its message: $(grep -m1 deprecated "$D/d.err")"
grep -q "#assert failed: the false assertion" "$D/d.err" || bad "D: the #assert failure lost its message: $(grep -m1 assert "$D/d.err")"

# L — anti-vacuous: real literals equal to a message are still emitted
cat > "$D/l.cyr" <<'EOF'
include "lib/string.cyr"
fn before(): i64 { println("shared text"); return 0; }
#deprecated("shared text")
fn old_a(): i64 { return 1; }
#assert 1 == 1, "later text";
fn main(): i64 {
    before();
    println("later text");
    return 0;
}
var r = main();
EOF
rc=0; "$CC" < "$D/l.cyr" > "$D/l.bin" 2> "$D/l.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "L: did not compile"; else
  chmod +x "$D/l.bin"; out=$("$D/l.bin" 2>/dev/null | head -2 | tr '\n' '|')
  [ "$out" = "shared text|later text|" ] || bad "L: printed '$out', want 'shared text|later text|'"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL compile_time_strings_not_emitted: $fail row(s) red"; exit 1; fi
echo "PASS compile_time_strings_not_emitted: #deprecated / #assert messages leave no bytes in the binary (x86, aarch64 cross, PE, cx), the diagnostics still print them, and literals equal to a message are still emitted"
exit 0
