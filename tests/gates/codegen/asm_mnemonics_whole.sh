#!/bin/sh
# tests/gates/codegen/asm_mnemonics_whole.sh — 6.7.14
#
# An `asm { }` block assembles what its source says, or refuses it by name
# (issues/2026-10-08-asm-in-mnemonic-unreachable.md; the user's decision D16, 2026-10-16: an asm block
# naming an instruction cyrius's assembler does not have — a misspelled mnemonic, or an operand the
# instruction cannot take — stops compiling, naming the mnemonic or the operand).
#
# What it was: `in` lexes as the for-in keyword (76), so the block's mnemonic arm (an identifier only)
# never reached `ASM_IN` — the guide's own `asm { in al, dx; }` was `unexpected in`. ASM_IN and ASM_OUT
# skipped their operands unread: `out dx, eax` assembled as out dx, al (EE). And ASM_MNEMONIC matched
# a mnemonic by its FIRST bytes, so `clix` assembled as cli, `inb al, dx` as in al, dx (the only way
# ASM_IN was reachable), `nopx` as nop — on aarch64 too.
#
#   1  x86 in / out encode the accumulator's width: in al,dx EC · in ax,dx 66 ED · in eax,dx ED ·
#      out dx,al EE · out dx,ax 66 EF · out dx,eax EF (the bytes between two F1 F1 F1 markers)
#   2  the guide's Inline Assembly block (docs/guides/cyrius-guide.md), read from the guide, compiles
#      in a `kernel;` build and in a program, every line to the bytes in the table below — the
#      spellings the guide documents keep their encodings; a guide line with no table entry is red
#   3  every other spelling lib/, programs/ and the corpus use keeps its bytes (programs/asmtest.cyr's
#      list and the fences), and programs/asmtest.cyr compiles
#   4  an operand in / out cannot take is refused by name, rc 1, nothing written: `in bl, dx` ('bl'),
#      `in al, 0x60` ('0x60'), `in rax, dx` ('rax'), `out dx, ebx` ('ebx'), `out al, dx` ('al')
#   5  aarch64 and cx refuse `in` by name (no port input; cx has no inline asm), rc 1, nothing written
#   6  a mnemonic is matched on its whole name; one the assembler does not have is refused by name, rc 1,
#      nothing written: x86 `clix`, `inb al, dx`, `nopx`, `stix`, `mfencex`, `outb dx, al`,
#      `param_loadx(rax, 0)`; aarch64 `nopx`, `dmbx`, `retx`, `eretx`, `param_loadx(x0, 0)` — and the
#      aarch64 names keep their words (dmb dsb isb nop wfi wfe svc ret eret)
#
# Mutations (6.7.14, each in a scratch copy of the tree, the compiler rebuilt):
#   the asm arm's keyword-76 route dropped                     -> 1 RED (`unexpected in`), 2 RED, 5 RED
#   ASM_IN / ASM_OUT emit EC / EE whatever the width (6.7.13)  -> 1 RED (66 ED, ED, 66 EF, EF)
#   _asm_acc_width answers al for any operand                  -> 4 RED (in bl, in rax, out dx, ebx compile)
#   x86 cli / nop / sti matched on 3 bytes again (6.7.13)      -> 6 RED (clix, nopx, stix compile)
#   aarch64 nop matched on 3 bytes again (6.7.13)              -> 6 RED (aarch64 nopx compiles)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: asm_mnemonics_whole: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: asm_mnemonics_whole: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: asm_mnemonics_whole: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: asm_mnemonics_whole $1"; fail=$((fail + 1)); }

# bytes <bin>: the hex bytes between each pair of F1 F1 F1 markers, one segment per line
bytes() { od -An -tx1 -v "$1" | tr -d '\n' | tr -s ' ' | sed 's/^ //' | awk '{
  n = split($0, b, " "); seg = ""; on = 0
  for (i = 1; i <= n; i++) {
    if (i + 2 <= n && b[i] == "f1" && b[i + 1] == "f1" && b[i + 2] == "f1") {
      if (on) { print (seg == "" ? "-" : seg); seg = ""; on = 0 } else { on = 1 }
      i += 2; continue
    }
    if (on) seg = (seg == "" ? b[i] : seg " " b[i])
  } }'; }
# one <row> <asm text> <want bytes>: the text alone in a fn, between markers, assembles to want
one() {
  printf 'fn f(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; }\n    asm { %s }\n    asm { 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\nsyscall(60, f());\n' "$2" > "$D/one.cyr"
  rc=0; "$CC" < "$D/one.cyr" > "$D/one" 2> "$D/one.err" || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$D/one" ]; then bad "$1: \`asm { $2 }\` was refused (rc $rc): $(grep -v '^note\|^warning' "$D/one.err" | head -1)"; return; fi
  got=$(bytes "$D/one" | head -1)
  [ "$got" = "$3" ] && echo "  ok   $1: asm { $2 } -> $got" || bad "$1: asm { $2 } assembled to [$got], want [$3]"
}
# refused <row> <compiler> <asm text> <want stderr substring>: rc 1, nothing written, the message
refused() {
  printf 'fn f(): i64 {\n    asm { %s }\n    return 0;\n}\nsyscall(60, f());\n' "$3" > "$D/r.cyr"
  rc=0; "$2" < "$D/r.cyr" > "$D/r" 2> "$D/r.err" || rc=$?
  if [ "$rc" -ne 1 ]; then bad "$1: \`asm { $3 }\` exited $rc, want 1: $(grep -v '^note\|^warning' "$D/r.err" | head -1)"
  elif [ -s "$D/r" ]; then bad "$1: \`asm { $3 }\` was refused but a binary was written"
  elif grep -qF "$4" "$D/r.err"; then echo "  ok   $1: asm { $3 } -> $(grep -F "$4" "$D/r.err" | head -1)"
  else bad "$1: \`asm { $3 }\` printed [$(head -1 "$D/r.err")], want [$4]"; fi
}

# 1 — in / out widths
one 1 'in al, dx;' 'ec'
one 1 'in ax, dx;' '66 ed'
one 1 'in eax, dx;' 'ed'
one 1 'out dx, al;' 'ee'
one 1 'out dx, ax;' '66 ef'
one 1 'out dx, eax;' 'ef'

# 2 — the guide's Inline Assembly block: every `asm { X }` line, X -> its bytes
want_of() { case "$1" in
  '0x90;') echo '90' ;;          'cli;') echo 'fa' ;;          'sti;') echo 'fb' ;;
  'hlt;') echo 'f4' ;;           'mov cr3, rax;') echo '0f 22 d8' ;;
  'lgdt [rax];') echo '0f 01 10' ;;  'lidt [rax];') echo '0f 01 18' ;;  'iretq;') echo '48 cf' ;;
  'int 3;') echo 'cd 03' ;;      'invlpg [rax];') echo '0f 01 38' ;;
  'in al, dx;') echo 'ec' ;;     'out dx, al;') echo 'ee' ;;
  'wrmsr; rdmsr; cpuid;') echo '0f 30 0f 32 0f a2' ;;
  *) echo '?' ;; esac; }
awk '/^## Inline Assembly$/ { s = 1; next } s && /^```/ { if (in_) exit; in_ = 1; next } s && in_' docs/guides/cyrius-guide.md \
  | sed -n 's/^asm { \(.*\) }.*$/\1/p' | sed 's/ *$//' > "$D/guide.txt"
ng=$(wc -l < "$D/guide.txt" | tr -d ' ')
if [ "$ng" -lt 12 ]; then bad "2: read $ng asm lines from the guide's Inline Assembly block — the extractor no longer finds it"
else
  for mode in kernel program; do
    { [ "$mode" = kernel ] && printf 'kernel;\n'; k=0
      while IFS= read -r x; do k=$((k + 1))
        printf 'fn g%s(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; }\n    asm { %s }\n    asm { 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\n' $k "$x"; done < "$D/guide.txt"
      printf 'syscall(60, 0);\n'; } > "$D/g_$mode.cyr"
    rc=0; "$CC" < "$D/g_$mode.cyr" > "$D/g_$mode" 2> "$D/g_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$D/g_$mode" ]; then bad "2: the guide's block does not compile in a $mode (rc $rc): $(grep -v '^note\|^warning' "$D/g_$mode.err" | head -1)"; continue; fi
    bytes "$D/g_$mode" > "$D/g_$mode.hex"
    k=0; okn=0
    while IFS= read -r x; do k=$((k + 1))
      w=$(want_of "$x"); g=$(sed -n "${k}p" "$D/g_$mode.hex")
      if [ "$w" = '?' ]; then bad "2: the guide documents \`asm { $x }\`, which this gate's table does not know — add its encoding"
      elif [ "$g" != "$w" ]; then bad "2 ($mode): the guide's \`asm { $x }\` assembled to [$g], want [$w]"
      else okn=$((okn + 1)); fi
    done < "$D/guide.txt"
    [ "$okn" -eq "$ng" ] && echo "  ok   2: the guide's Inline Assembly block compiles in a $mode, all $ng lines to their encodings"
  done
fi

# 3 — the other spellings lib/, programs/ and the corpus use
one 3 'nop;' '90'
one 3 'mfence;' '0f ae f0'
one 3 'lfence;' '0f ae e8'
one 3 'sfence;' '0f ae f8'
one 3 'pushfq;' '9c'
one 3 'popfq;' '9d'
one 3 'mov rax, cr3;' '0f 20 d8'
one 3 'mov cr0, rax;' '0f 22 c0'
one 3 'int 0x80;' 'cd 80'
rc=0; "$CC" < programs/asmtest.cyr > "$D/asmtest" 2> "$D/asmtest.err" || rc=$?
if [ "$rc" -eq 0 ] && [ -s "$D/asmtest" ]; then echo "  ok   3: programs/asmtest.cyr compiles"
else bad "3: programs/asmtest.cyr was refused (rc $rc): $(grep -v '^note\|^warning' "$D/asmtest.err" | head -1)"; fi

# 4 — operands in / out cannot take
refused 4 "$CC" 'in bl, dx;' "in takes al, ax or eax and then dx, not 'bl'"
refused 4 "$CC" 'in al, 0x60;' "in takes al, ax or eax and then dx, not '0x60'"
refused 4 "$CC" 'in rax, dx;' "in takes al, ax or eax and then dx, not 'rax'"
refused 4 "$CC" 'out dx, ebx;' "out takes dx and then al, ax or eax, not 'ebx'"
refused 4 "$CC" 'out al, dx;' "out takes dx and then al, ax or eax, not 'al'"

# 5 — aarch64 and cx refuse `in` by name
"$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2>/dev/null; chmod +x "$D/cc_a64" 2>/dev/null
"$CC" < src/main_cx.cyr > "$D/cc_cx" 2>/dev/null; chmod +x "$D/cc_cx" 2>/dev/null
if [ ! -s "$D/cc_a64" ] || [ ! -s "$D/cc_cx" ]; then bad "5: cannot build src/main_aarch64.cyr / src/main_cx.cyr with $(basename "$CC")"
else
  refused 5 "$D/cc_a64" 'in al, dx;' "unknown aarch64 asm mnemonic 'in'"
  refused 5 "$D/cc_cx" 'in al, dx;' "inline asm not supported in cyrius-x: 'in'"
fi

# 6 — whole mnemonics
for m in 'clix;' 'inb al, dx;' 'nopx;' 'stix;' 'mfencex;' 'outb dx, al;' 'param_loadx(rax, 0);'; do
  n=$(printf '%s' "$m" | sed 's/[ (;].*//')
  refused 6 "$CC" "$m" "unknown x86 asm mnemonic '$n'"
done
if [ -s "$D/cc_a64" ]; then
  for m in 'nopx;' 'dmbx;' 'retx;' 'eretx;' 'param_loadx(x0, 0);'; do
    n=$(printf '%s' "$m" | sed 's/[ (;].*//')
    refused 6 "$D/cc_a64" "$m" "unknown aarch64 asm mnemonic '$n'"
  done
  # each marker block is padded to 4 bytes (F1 F1 F1 00), so the words stay aligned and the segment
  # starts with that 00
  printf 'fn f(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; }\n    asm { dmb; dsb; isb; nop; wfi; wfe; svc; ret; eret; }\n    asm { 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\nsyscall(60, f());\n' > "$D/a64.cyr"
  rc=0; "$D/cc_a64" < "$D/a64.cyr" > "$D/a64" 2> "$D/a64.err" || rc=$?
  w='00 bf 30 03 d5 9f 30 03 d5 df 30 03 d5 1f 20 03 d5 7f 20 03 d5 20 10 03 d5 01 00 00 d4 c0 03 5f d6 e0 03 9f d6'
  if [ "$rc" -ne 0 ]; then bad "6: aarch64 dmb .. eret were refused (rc $rc): $(grep -v '^note\|^warning' "$D/a64.err" | head -1)"
  else g=$(bytes "$D/a64" | head -1)
    [ "$g" = "$w" ] && echo "  ok   6: aarch64 dmb dsb isb nop wfi wfe svc ret eret keep their words" || bad "6: aarch64 dmb .. eret assembled to [$g], want [$w]"; fi
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: asm_mnemonics_whole — $fail row(s) red"; exit 1; fi
echo "PASS: asm_mnemonics_whole — mnemonics match on their whole names and an unknown one is refused by name (x86, aarch64), in / out encode the accumulator's width, the guide's Inline Assembly block and the corpus's spellings keep their bytes (kernel and program), an operand in / out cannot take is refused by name, and aarch64 / cx refuse in by name"
