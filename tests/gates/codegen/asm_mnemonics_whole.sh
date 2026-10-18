#!/bin/sh
# tests/gates/codegen/asm_mnemonics_whole.sh — 6.7.14
#
# An `asm { }` block assembles what its source says, or refuses it by name
# (issues/archived/2026-10-08-asm-in-mnemonic-unreachable.md; the user's decision D16, 2026-10-16: an asm block
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
#   5  aarch64 and cx refuse `in` by name (no port input; cx has no inline asm), rc 1, nothing written;
#      cx names any mnemonic it refuses and moves on (until 6.7.14 it named none and the block loop
#      stalled until the watchdog's `parser recovery aborted`)
#   6  a mnemonic is matched on its whole name; one the assembler does not have is refused by name, rc 1,
#      nothing written: x86 `clix`, `inb al, dx`, `nopx`, `stix`, `mfencex`, `outb dx, al`,
#      `param_loadx(rax, 0)`; aarch64 `nopx`, `dmbx`, `retx`, `eretx`, `param_loadx(x0, 0)` — and the
#      aarch64 names keep their words (dmb dsb isb nop wfi wfe svc ret eret). 6.7.15
#      (issues/2026-10-16-guide-ifplat-example-dmb-ish-does-not-compile.md): a bare dmb / dsb / isb is the
#      full-system barrier, sy (D5033FBF / D5033F9F / D5033FDF), and wfe is hint #2 (D503205F) — llvm-mc's
#      words; until 6.7.15 dmb and isb encoded the reserved option #0, dsb was SSBB (a speculative-store-
#      bypass barrier) and wfe `msr S0_3_C1_C0_1, x0`
#   7  (6.7.15, issues/2026-10-16-x86-asm-operands-ignored-lgdt-lidt-invlpg-mov-cr-ltr-int.md) x86 lgdt /
#      lidt / invlpg / mov crN / ltr encode the register the source names — until 6.7.15 each encoded rax / ax
#      whatever it named (`lgdt [rbx]` 0f 01 10, `mov cr8, rax` 0f 22 c0 = mov cr0, rax): each form's bytes
#      (llvm-mc's encodings: REX.B for r8-r15, a SIB for rsp / r12, disp8 0 for rbp / r13, REX.R for cr8),
#      in a program, a `kernel;` build, PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1)
#   8  an operand those cannot take is refused by name, rc 1, nothing written (6.7.14's D16): `mov cr9, rax`
#      ('cr9'; it was mov cr1, rax), `int 256` ('256'; it was int 0), `int 0x1FF` ('0x1FF'; it was int 0xff),
#      `ltr eax` ('eax'), and a name only a register's first letters match (`lgdt [raxx]`, `ltr r8d`)
#   9  (6.7.15, the same guide item; the user's decision D37, 2026-10-18: a barrier accepts its option) an
#      aarch64 barrier takes its option: `dmb ish` bf 3b 03 d5, `dsb sy` 9f 3f 03 d5, `isb sy` df 3f 03 d5 and
#      each other dmb / dsb option to llvm-mc's word; a bare barrier is sy; the next mnemonic is not an option
#      (`dmb dsb isb`, and the three on three lines as inline_asm_fences.tcyr writes them, stay three barriers);
#      a word the barrier has no option for is refused by name, rc 1, nothing written: `dmb foo` ('foo'),
#      `dsb isht` ('isht'), `isb ish` ('ish' — isb has sy only). Until 6.7.15 `dmb ish` was `unknown aarch64
#      asm mnemonic 'ish'`. On hardware, tests/tcyr/crossos/asm_barrier_options.tcyr executes every option
#
# Mutations (6.7.14, each in a scratch copy of the tree, the compiler rebuilt):
#   the asm arm's keyword-76 route dropped                     -> 1 RED (`unexpected in`), 2 RED, 5 RED
#   ASM_IN / ASM_OUT emit EC / EE whatever the width (6.7.13)  -> 1 RED (66 ED, ED, 66 EF, EF)
#   _asm_acc_width answers al for any operand                  -> 4 RED (in bl, in rax, out dx, ebx compile)
#   x86 cli / nop / sti matched on 3 bytes again (6.7.13)      -> 6 RED (clix, nopx, stix compile)
#   aarch64 nop matched on 3 bytes again (6.7.13)              -> 6 RED (aarch64 nopx compiles)
#   cx ASM_MNEMONIC back to its 6.7.13 ERR_MSG                 -> 5 RED (no name; recovery aborted)
# (6.7.15) the 6.7.14 x86 emitters (lgdt .. int)               -> 7 RED (every register but rax / ax), 8 RED
#   _asm_x86_gpr reading the first letters only (no NUL test)  -> 8 RED (lgdt [raxx] compiles)
#   the 6.7.14 aarch64 dmb / dsb / isb / wfe words              -> 6 RED (the word row)
#   the aarch64 barrier option dropped (no lookahead, 6.7.14)   -> 9 RED (every option form refused; foo /
#                                                                 isht / ish named as unknown mnemonics)
#   the option read without the mnemonic test                  -> 9 RED (the forms no longer compile:
#                                                                 `dmb dsb isb` refuses 'dsb' as an option)
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
  refused 5 "$D/cc_cx" 'cli;' "inline asm not supported in cyrius-x: 'cli'"
  if grep -q 'parser recovery aborted' "$D/r.err"; then bad "5: cx's asm refusal stalled the block loop (parser recovery aborted)"
  else echo "  ok   5: cx's asm refusal moves on (no recovery abort)"; fi
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
  w='00 bf 3f 03 d5 9f 3f 03 d5 df 3f 03 d5 1f 20 03 d5 7f 20 03 d5 5f 20 03 d5 01 00 00 d4 c0 03 5f d6 e0 03 9f d6'
  if [ "$rc" -ne 0 ]; then bad "6: aarch64 dmb .. eret were refused (rc $rc): $(grep -v '^note\|^warning' "$D/a64.err" | head -1)"
  else g=$(bytes "$D/a64" | head -1)
    [ "$g" = "$w" ] && echo "  ok   6: aarch64 dmb dsb isb nop wfi wfe svc ret eret keep their words" || bad "6: aarch64 dmb .. eret assembled to [$g], want [$w]"; fi
fi

# 7 — x86 lgdt / lidt / invlpg / mov crN / ltr encode the named register: one fn per form, every
# form's bytes in each output mode (the emitter is shared; the container is what differs)
cat > "$D/x7.txt" <<'X7'
lgdt [rbx];|0f 01 13
lgdt [r12];|41 0f 01 14 24
lgdt [rbp];|0f 01 55 00
lgdt [rsp];|0f 01 14 24
lgdt [r8];|41 0f 01 10
lidt [rcx];|0f 01 19
lidt [r13];|41 0f 01 5d 00
invlpg [rdi];|0f 01 3f
invlpg [r13];|41 0f 01 7d 00
mov cr3, rbx;|0f 22 db
mov rbx, cr3;|0f 20 db
mov cr8, rax;|44 0f 22 c0
mov cr0, r8;|41 0f 22 c0
mov r9, cr8;|45 0f 20 c1
mov cr2, r15;|41 0f 22 d7
mov r12, cr4;|41 0f 20 e4
ltr bx;|0f 00 db
ltr sp;|0f 00 dc
ltr r8w;|41 0f 00 d8
ltr r15w;|41 0f 00 df
int 255;|cd ff
X7
n7=$(wc -l < "$D/x7.txt" | tr -d ' ')
for mode in program kernel pe macho; do
  { [ "$mode" = kernel ] && printf 'kernel;\n'; k=0
    while IFS='|' read -r x w; do k=$((k + 1))
      printf 'fn h%s(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; }\n    asm { %s }\n    asm { 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\n' $k "$x"; done < "$D/x7.txt"
    printf 'syscall(60, 0);\n'; } > "$D/x7_$mode.cyr"
  rc=0
  case $mode in
    pe) CYRIUS_TARGET_WIN=1 "$CC" < "$D/x7_$mode.cyr" > "$D/x7_$mode" 2> "$D/x7_$mode.err" || rc=$? ;;
    macho) CYRIUS_MACHO=1 "$CC" < "$D/x7_$mode.cyr" > "$D/x7_$mode" 2> "$D/x7_$mode.err" || rc=$? ;;
    *) "$CC" < "$D/x7_$mode.cyr" > "$D/x7_$mode" 2> "$D/x7_$mode.err" || rc=$? ;;
  esac
  if [ "$rc" -ne 0 ] || [ ! -s "$D/x7_$mode" ]; then bad "7: the operand forms do not compile in a $mode build (rc $rc): $(grep -v '^note\|^warning' "$D/x7_$mode.err" | head -1)"; continue; fi
  bytes "$D/x7_$mode" > "$D/x7_$mode.hex"
  k=0; okn=0
  while IFS='|' read -r x w; do k=$((k + 1))
    g=$(sed -n "${k}p" "$D/x7_$mode.hex")
    if [ "$g" = "$w" ]; then okn=$((okn + 1)); else bad "7 ($mode): \`asm { $x }\` assembled to [$g], want [$w]"; fi
  done < "$D/x7.txt"
  [ "$okn" -eq "$n7" ] && echo "  ok   7: lgdt / lidt / invlpg / mov crN / ltr / int encode the named operand in a $mode build, all $n7 forms"
done

# 8 — operands those cannot take, refused by name
refused 8 "$CC" 'mov cr9, rax;' "mov takes a control register (cr0, cr2, cr3, cr4 or cr8) and a 64-bit register, not 'cr9'"
refused 8 "$CC" 'mov cr3, eax;' "mov takes a control register (cr0, cr2, cr3, cr4 or cr8) and a 64-bit register, not 'eax'"
refused 8 "$CC" 'mov rax, rbx;' "mov takes a control register (cr0, cr2, cr3, cr4 or cr8) and a 64-bit register, not 'rbx'"
refused 8 "$CC" 'int 256;' "int takes a vector from 0 to 255, not '256'"
refused 8 "$CC" 'int 0x1FF;' "int takes a vector from 0 to 255, not '0x1FF'"
refused 8 "$CC" 'ltr eax;' "ltr takes a 16-bit register, ax to di or r8w to r15w, not 'eax'"
refused 8 "$CC" 'ltr r8d;' "ltr takes a 16-bit register, ax to di or r8w to r15w, not 'r8d'"
refused 8 "$CC" 'lgdt [raxx];' "lgdt takes one 64-bit register in brackets, [rax] to [r15], not 'raxx'"
refused 8 "$CC" 'lidt rax;' "lidt takes one 64-bit register in brackets, [rax] to [r15], not 'rax'"
refused 8 "$CC" 'invlpg [rax + 8];' "invlpg takes one 64-bit register in brackets, [rax] to [r15], not '+'"

# 9 — aarch64 barrier options (D37, 2026-10-18): each option's word (llvm-mc's), a bare barrier is sy, the next
# mnemonic is not an option, and a word the barrier has no option for is refused by name
if [ -s "$D/cc_a64" ]; then
  cat > "$D/a9.txt" <<'A9'
dmb ish|bf 3b 03 d5
dmb sy|bf 3f 03 d5
dmb st|bf 3e 03 d5
dmb ld|bf 3d 03 d5
dmb ishst|bf 3a 03 d5
dmb ishld|bf 39 03 d5
dmb nsh|bf 37 03 d5
dmb nshst|bf 36 03 d5
dmb nshld|bf 35 03 d5
dmb osh|bf 33 03 d5
dmb oshst|bf 32 03 d5
dmb oshld|bf 31 03 d5
dsb sy|9f 3f 03 d5
dsb ish|9f 3b 03 d5
dsb ishst|9f 3a 03 d5
dsb oshld|9f 31 03 d5
isb sy|df 3f 03 d5
dmb|bf 3f 03 d5
dmb ish; dsb sy; isb sy;|bf 3b 03 d5 9f 3f 03 d5 df 3f 03 d5
dmb dsb isb|bf 3f 03 d5 9f 3f 03 d5 df 3f 03 d5
dmb ish nop|bf 3b 03 d5 1f 20 03 d5
A9
  n9=$(wc -l < "$D/a9.txt" | tr -d ' ')
  { k=0
    while IFS='|' read -r x w; do k=$((k + 1))
      printf 'fn b%s(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; }\n    asm { %s }\n    asm { 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\n' $k "$x"; done < "$D/a9.txt"
    printf 'syscall(60, 0);\n'; } > "$D/a9.cyr"
  # the newline-separated trio, as tests/tcyr/codegen/inline_asm_fences.tcyr writes it
  printf 'fn bt(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; }\n    asm {\n        dmb\n        dsb\n        isb\n    }\n    asm { 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\n' >> "$D/a9.cyr"
  rc=0; "$D/cc_a64" < "$D/a9.cyr" > "$D/a9" 2> "$D/a9.err" || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$D/a9" ]; then bad "9: the aarch64 barrier options do not compile (rc $rc): $(grep -v '^note\|^warning' "$D/a9.err" | head -1)"
  else
    # each marker block is padded to 4 bytes (F1 F1 F1 00): drop the leading 00
    bytes "$D/a9" | sed 's/^00 //' > "$D/a9.hex"
    k=0; okn=0
    while IFS='|' read -r x w; do k=$((k + 1))
      g=$(sed -n "${k}p" "$D/a9.hex")
      if [ "$g" = "$w" ]; then okn=$((okn + 1)); else bad "9: aarch64 \`asm { $x }\` assembled to [$g], want [$w]"; fi
    done < "$D/a9.txt"
    [ "$okn" -eq "$n9" ] && echo "  ok   9: aarch64 barriers take their options, all $n9 forms to llvm-mc's words"
    g=$(sed -n "$((n9 + 1))p" "$D/a9.hex"); w='bf 3f 03 d5 9f 3f 03 d5 df 3f 03 d5'
    [ "$g" = "$w" ] && echo "  ok   9: dmb / dsb / isb on three lines stay three barriers" || bad "9: the newline-separated dmb / dsb / isb assembled to [$g], want [$w]"
  fi
  refused 9 "$D/cc_a64" 'dmb foo;' "dmb takes sy, st, ld, ish, ishst, ishld, nsh, nshst, nshld, osh, oshst or oshld, not 'foo'"
  refused 9 "$D/cc_a64" 'dsb isht;' "dsb takes sy, st, ld, ish, ishst, ishld, nsh, nshst, nshld, osh, oshst or oshld, not 'isht'"
  refused 9 "$D/cc_a64" 'isb ish;' "isb takes sy, not 'ish'"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: asm_mnemonics_whole — $fail row(s) red"; exit 1; fi
echo "PASS: asm_mnemonics_whole — mnemonics match on their whole names and an unknown one is refused by name (x86, aarch64), in / out encode the accumulator's width, lgdt / lidt / invlpg / mov crN / ltr / int encode the operand they name (program, kernel, PE, Mach-O) and refuse one they cannot take by name, aarch64 barriers take their options (dmb ish) and refuse one they lack by name, the guide's Inline Assembly block and the corpus's spellings keep their bytes (kernel and program), an operand in / out cannot take is refused by name, and aarch64 / cx refuse in by name"
