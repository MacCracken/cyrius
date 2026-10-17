#!/bin/sh
# aarch64_wx_layout_64k.sh — 6.7.14. The aarch64 W^X executable layout 6.7.13's D45 keeps.
#
# With segment-level W^X (the default; src/backend/aarch64/fixup.cyr EMITELF_USER) the aarch64
# ELF writer puts the data segment at a 64 KB-aligned FILE offset (p_align 0x10000) and a 2 MB-
# aligned vaddr, and writes the bytes between the code's end and that offset as zeros outside
# both LOADs' filesz. So every aarch64 W^X executable is at least ~64 KB (`syscall(60, 7);` is
# 65,888 B; 520 B with CYRIUS_WX=0; 4,448 B on x86, whose p_align is 4 KB) and its size moves in
# 64 KB steps. That is the price of exact W^X on 4, 16 and 64 KB-page arm64 kernels: the loader
# maps whole pages, and only a 64 KB-aligned data offset keeps the code's last page and the
# data's first apart on all three. D45 (the user, 2026-10-15): keep it and document the cost.
# issues/2026-10-15-aarch64-wx-layout-pads-every-binary-to-64k.md
#
# Axis 1  the one-line program, W^X: exactly two PT_LOADs — code R E at file offset 0, data RW
#         at file offset 0x10000 and vaddr 0x600000, both p_align 0x10000, p_vaddr ≡ p_offset
#         (mod p_align); every byte from the code's end to 0x10000 is zero; the file is at
#         least 64 KB; qemu-aarch64 runs it to exit 7.
# Axis 2  the same source with CYRIUS_WX=0: ONE PT_LOAD, RWE, and a file under 4 KB (no pad).
# Axis 3  the 64 KB step: a program whose code passes 64 KB puts its data at the next 64 KB
#         boundary past the code (0x20000 here), not right after it, and still runs (exit 7).
# Mutation (6.7.14): EMITELF_USER's data offset aligned to 4 KB (`+ 0xFFF) & (0 - 0x1000)`) ->
# RED axis 1 (data p_offset 0x1000) and axis 3. qemu-user maps 4 KB pages, so it would run that
# file: only this gate sees the layout change.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL: aarch64_wx_layout_64k: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: aarch64_wx_layout_64k: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC="${CYCC:-$R/build/cycc}"
[ -x "$CC" ] || { echo "FAIL aarch64_wx_layout_64k: no compiler at $CC"; exit 1; }
fail() { echo "FAIL aarch64_wx_layout_64k $1"; exit 1; }

"$CC" < "$R/src/main_aarch64.cyr" > "$T/cc_a64" 2> "$T/cc.err" && [ -s "$T/cc_a64" ] \
  || fail "setup: cannot cross-build src/main_aarch64.cyr: $(grep -m1 error "$T/cc.err")"
chmod +x "$T/cc_a64"

# _loads <elf> -> one line per PT_LOAD: "<flags> <offset> <vaddr> <filesz> <memsz> <align>" (decimal)
_u() { od -An -t "u$2" -j "$1" -N "$2" "$3" | tr -d ' '; }
_loads() {
  phoff=$(_u 32 8 "$1"); phnum=$(_u 56 2 "$1"); i=0
  while [ "$i" -lt "${phnum:-0}" ]; do
    p=$((phoff + i * 56))
    if [ "$(_u "$p" 4 "$1")" = 1 ]; then
      echo "$(_u $((p + 4)) 4 "$1") $(_u $((p + 8)) 8 "$1") $(_u $((p + 16)) 8 "$1") $(_u $((p + 32)) 8 "$1") $(_u $((p + 40)) 8 "$1") $(_u $((p + 48)) 8 "$1")"
    fi
    i=$((i + 1))
  done
}
_zero_span() {   # <elf> <from> <to> -> exit 0 when every byte in [from, to) is zero
  [ "$3" -le "$2" ] && return 0
  [ -z "$(od -An -tx1 -v -j "$2" -N $(($3 - $2)) "$1" | tr -s ' ' '\n' | grep -v '^$' | grep -v '^00$' | head -1)" ]
}
_run() {   # <elf> <want exit> <row>
  command -v qemu-aarch64 > /dev/null 2>&1 || { echo "  SKIP aarch64_wx_layout_64k $3: qemu-aarch64 not installed (the layout rows ran)"; return 0; }
  chmod +x "$1"; got=0; timeout 20 qemu-aarch64 "$1" || got=$?
  [ "$got" = "$2" ] || fail "$3: qemu-aarch64 exits $got, want $2"
}
# _wx_layout <elf> <row> <want data p_offset> — the two-LOAD D45 shape; prints the code filesz
_wx_layout() {
  _loads "$1" > "$T/loads"
  [ "$(wc -l < "$T/loads")" = 2 ] || fail "$2: $(wc -l < "$T/loads") PT_LOADs, want 2 (code R E, data RW): $(cat "$T/loads")"
  set -- "$1" "$2" "$3" $(sed -n 1p "$T/loads") $(sed -n 2p "$T/loads")
  # $4.. code: flags off vaddr filesz memsz align; ${10}.. data: flags off vaddr filesz memsz align
  [ "$4" = 5 ] && [ "$5" = 0 ] && [ "$9" = 65536 ] || fail "$2: the code LOAD is flags $4 offset $5 align $9, want R E (5) at 0, p_align 0x10000"
  [ "${10}" = 6 ] && [ "${15}" = 65536 ] || fail "$2: the data LOAD is flags ${10} align ${15}, want RW (6), p_align 0x10000"
  [ "${11}" = "$3" ] || fail "$2: the data LOAD's file offset is ${11}, want $3 — the 64 KB-aligned offset D45 keeps"
  [ $(( ${11} % 65536 )) = 0 ] || fail "$2: the data file offset ${11} is not 64 KB-aligned"
  [ $(( ${12} % 2097152 )) = 0 ] || fail "$2: the data vaddr ${12} is not 2 MB-aligned"
  [ $(( (${6} - ${5}) % 65536 )) = 0 ] && [ $(( (${12} - ${11}) % 65536 )) = 0 ] || fail "$2: p_vaddr is not congruent to p_offset mod 0x10000"
  [ $(( ${5} + ${7} )) -le "${11}" ] || fail "$2: the code (filesz $7) runs past the data offset ${11}"
  _zero_span "$1" $(( ${5} + ${7} )) "${11}" || fail "$2: the pad between the code's end ($(( ${5} + ${7} ))) and the data (${11}) is not all zero"
  sz=$(wc -c < "$1")
  [ "$sz" -ge "${11}" ] || fail "$2: the file is $sz B, shorter than its data offset ${11}"
  echo "$7"
}

# ── axis 1 — the one-line program, W^X ───────────────────────────────────────────────────────
printf 'syscall(60, 7);\n' > "$T/tiny.cyr"
"$T/cc_a64" < "$T/tiny.cyr" > "$T/tiny" 2> "$T/tiny.err" && [ -s "$T/tiny" ] || fail "axis1: tiny.cyr did not compile: $(cat "$T/tiny.err")"
CODE1=$(_wx_layout "$T/tiny" axis1 65536) || { echo "$CODE1"; exit 1; }
SZ1=$(wc -c < "$T/tiny")
[ "$SZ1" -ge 65536 ] || fail "axis1: the W^X file is $SZ1 B, want >= 65,536"
[ "$CODE1" -lt 4096 ] || fail "axis1: the one-line program's code LOAD is $CODE1 B"
_run "$T/tiny" 7 axis1

# ── axis 2 — CYRIUS_WX=0: one RWE LOAD, no pad ───────────────────────────────────────────────
CYRIUS_WX=0 "$T/cc_a64" < "$T/tiny.cyr" > "$T/tiny0" 2> "$T/tiny0.err" && [ -s "$T/tiny0" ] || fail "axis2: tiny.cyr did not compile under CYRIUS_WX=0"
_loads "$T/tiny0" > "$T/loads0"
[ "$(wc -l < "$T/loads0")" = 1 ] || fail "axis2: CYRIUS_WX=0 gives $(wc -l < "$T/loads0") PT_LOADs, want 1"
set -- $(cat "$T/loads0")
[ "$1" = 7 ] || fail "axis2: the CYRIUS_WX=0 LOAD's flags are $1, want RWE (7)"
SZ0=$(wc -c < "$T/tiny0")
[ "$SZ0" -lt 4096 ] || fail "axis2: the CYRIUS_WX=0 file is $SZ0 B, want under 4 KB"
_run "$T/tiny0" 7 axis2

# ── axis 3 — the 64 KB step: code past 64 KB puts the data at 0x20000 ────────────────────────
awk 'BEGIN { for (i = 0; i < 550; i++) printf "fn f%d(x): i64 { var a = x + %d; var b = a * 3; return b - a; }\n", i, i
             print "var t = 0;"; for (i = 0; i < 550; i++) printf "t = t + f%d(0);\n", i
             print "syscall(60, 7);" }' > "$T/big.cyr"
"$T/cc_a64" < "$T/big.cyr" > "$T/big" 2> "$T/big.err" && [ -s "$T/big" ] || fail "axis3: big.cyr did not compile: $(grep -m1 error "$T/big.err")"
_loads "$T/big" | sed -n 1p > "$T/bl"; set -- $(cat "$T/bl")
[ "${4:-0}" -gt 65536 ] || fail "axis3: big.cyr's code LOAD is ${4:-?} B — the row needs more than 64 KB of code to show the step"
WANT3=$(( (${2} + ${4} + 65535) / 65536 * 65536 ))
CODE3=$(_wx_layout "$T/big" axis3 "$WANT3") || { echo "$CODE3"; exit 1; }
_run "$T/big" 7 axis3

echo "PASS aarch64_wx_layout_64k: W^X 'syscall(60, 7);' is $SZ1 B (code LOAD $CODE1 B, data at 0x10000, zero pad, p_align 0x10000) vs $SZ0 B with CYRIUS_WX=0 (one RWE LOAD); $CODE3 B of code puts the data at $(printf '0x%x' "$WANT3") (the 64 KB step) — D45's layout"
exit 0
