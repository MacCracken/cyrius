#!/bin/sh
# dce_kernel_compaction_boots.sh — 6.7.11. A `kernel;` image compacted by CYRIUS_DCE=1 BOOTS: its
# code reads a string and an array element from data that moved down with the code.
#
# THE DEFECT (filed by agnos: issues/2026-10-10-agnos-kernel-dce-compaction-moves-data.md). A
# kernel image puts .bss / .rodata right after the code, and FIXUP patches every data address in
# BEFORE compaction shrinks the code. Through 6.6.19 the data moved and the addresses did not:
# agnos printed ~18 serial lines of NUL bytes and died before its banner. 6.6.20 declined
# compaction on kernel images instead, so a kernel could not shrink. Since 6.7.11 the compaction
# moves the patched data addresses with the data (ir.cyr _wp_data_follows / _wp_data_fix).
# dce_data_vaddr_frozen.sh rows 7-9 DECODE the image; this gate RUNS one.
#
# THE PROBE. QEMU's -kernel loads only multiboot1 (an ELF32 `kernel;`), which enters in 32-bit
# protected mode, so the probe opens with a top-level asm shim that switches to long mode (page
# tables at 0x70000, a 64-bit GDT, a far return to the next instruction) before any compiled
# code runs. Six dead fns sit between the shim and the code that reads the data, so compaction
# moves that code and the data under it. `putc` writes rdi's low byte to COM1; the program
# writes the string "kdata-ok " and A[2] + G - 40 ('C' from a static array initializer and a
# static global) and leaves through isa-debug-exit (QEMU exits 33). Without the fix the string
# and the element read as NUL bytes.
#
# ROWS
#   C  CYRIUS_DCE=1 compacts the probe (`dead code eliminated`, a smaller image).
#   B0 the plain build boots: serial "kdata-ok C", QEMU exit 33 (anti-vacuous: the probe works).
#   B1 the compacted build boots the same.
# Exit 77 (a SKIP, never a pass) when qemu-system-x86_64 is absent; a FAIL instead under
# CYRIUS_REQUIRE_BOOT=1, as scripts/qemu-boot-gate.sh does.
# Mutations (6.7.11): the data shift dropped from _wp_data_fix -> B1 RED (serial is 10 NUL bytes
# and a LF); the slot-open compiler (the 6.6.20 decline) -> C RED.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL: dce_kernel_compaction_boots: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: dce_kernel_compaction_boots: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: dce_kernel_compaction_boots: no build/cycc"; exit 1; }
FAILS=0
fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

cat > "$T/k.cyr" <<'EOF'
kernel;
# multiboot1 enters in 32-bit protected mode: switch to long mode before any compiled code runs.
asm {
    0xFA;                                     # cli
    0xBC; 0x00; 0x00; 0x09; 0x00;             # mov esp, 0x90000
    0xBF; 0x00; 0x00; 0x07; 0x00;             # mov edi, 0x70000
    0xB9; 0x00; 0x10; 0x00; 0x00;             # mov ecx, 0x1000
    0x31; 0xC0;                               # xor eax, eax
    0xFC;                                     # cld
    0xF3; 0xAB;                               # rep stosd   (zero 0x70000..0x74000)
    0xC7; 0x05; 0x00; 0x00; 0x07; 0x00; 0x03; 0x10; 0x07; 0x00;   # PML4[0] = 0x71003
    0xC7; 0x05; 0x00; 0x10; 0x07; 0x00; 0x03; 0x20; 0x07; 0x00;   # PDPT[0] = 0x72003
    0xC7; 0x05; 0x00; 0x20; 0x07; 0x00; 0x83; 0x00; 0x00; 0x00;   # PD[0] = 0x000083 (2 MB page)
    0xC7; 0x05; 0x08; 0x20; 0x07; 0x00; 0x83; 0x00; 0x20; 0x00;   # PD[1] = 0x200083
    0xC7; 0x05; 0x0C; 0x30; 0x07; 0x00; 0x00; 0x9A; 0x20; 0x00;   # GDT[1] = 64-bit code
    0xC7; 0x05; 0x14; 0x30; 0x07; 0x00; 0x00; 0x92; 0x00; 0x00;   # GDT[2] = data
    0x66; 0xC7; 0x05; 0x00; 0x31; 0x07; 0x00; 0x17; 0x00;         # GDTR.limit = 23
    0xC7; 0x05; 0x02; 0x31; 0x07; 0x00; 0x00; 0x30; 0x07; 0x00;   # GDTR.base = 0x73000
    0x0F; 0x01; 0x15; 0x00; 0x31; 0x07; 0x00;                     # lgdt [0x73100]
    0xB8; 0x00; 0x00; 0x07; 0x00;             # mov eax, 0x70000
    0x0F; 0x22; 0xD8;                         # mov cr3, eax
    0x0F; 0x20; 0xE0;                         # mov eax, cr4
    0x83; 0xC8; 0x20;                         # or eax, 0x20 (PAE)
    0x0F; 0x22; 0xE0;                         # mov cr4, eax
    0xB9; 0x80; 0x00; 0x00; 0xC0;             # mov ecx, 0xC0000080 (EFER)
    0x0F; 0x32;                               # rdmsr
    0x0D; 0x00; 0x01; 0x00; 0x00;             # or eax, 0x100 (LME)
    0x0F; 0x30;                               # wrmsr
    0x0F; 0x20; 0xC0;                         # mov eax, cr0
    0x0D; 0x01; 0x00; 0x00; 0x80;             # or eax, 0x80000001 (PG | PE)
    0x0F; 0x22; 0xC0;                         # mov cr0, eax
    0xE8; 0x00; 0x00; 0x00; 0x00;             # call next
    0x5B;                                     # next: pop ebx
    0x83; 0xC3; 0x08;                         # add ebx, 8 (-> the 64-bit code below)
    0x6A; 0x08;                               # push 0x08 (the 64-bit code selector)
    0x53;                                     # push ebx
    0xCB;                                     # retf
    0x48; 0xBC; 0x00; 0x00; 0x09; 0x00; 0x00; 0x00; 0x00; 0x00;   # mov rsp, 0x90000
    0x48; 0x89; 0xE5;                         # mov rbp, rsp
}
fn dead0(x): i64 { var a = x * 3; var b = a + 7; var c = b * b; return c - a + 7; }
fn dead1(x): i64 { var a = x * 4; var b = a + 7; var c = b * b; return c - a + 1007; }
fn dead2(x): i64 { var a = x * 5; var b = a + 7; var c = b * b; return c - a + 2007; }
fn dead3(x): i64 { var a = x * 6; var b = a + 7; var c = b * b; return c - a + 3007; }
fn dead4(x): i64 { var a = x * 7; var b = a + 7; var c = b * b; return c - a + 4007; }
fn dead5(x): i64 { var a = x * 8; var b = a + 7; var c = b * b; return c - a + 5007; }
var G = 40;
var A: i64[4] = {65, 66, 67, 68};
# COM1 transmit: the byte arrives in rdi (the first argument register), untouched by the prologue.
fn putc(c): i64 {
    asm { 0x89; 0xF8; 0xBA; 0xF8; 0x03; 0x00; 0x00; 0xEE; }   # mov eax, edi; mov edx, 0x3F8; out dx, al
    return 0;
}
fn main(): i64 {
    var s = "kdata-ok ";
    var i = 0;
    while (i < 9) { putc(load8(s + i)); i = i + 1; }
    putc(A[2] + G - 40);
    putc(10);
    return 0;
}
main();
asm {
    0xB0; 0x10;                               # mov al, 0x10
    0xE6; 0xF4;                               # out 0xF4, al  (isa-debug-exit: QEMU exits 33)
    0xFA; 0xF4; 0xEB; 0xFE;                   # cli; hlt; jmp $
}
EOF

# C — the compacted build exists and is smaller (needs no QEMU)
"$CC" < "$T/k.cyr" > "$T/k0.bin" 2> "$T/k0.err" || { echo "FAIL: dce_kernel_compaction_boots: the plain kernel build failed: $(cat "$T/k0.err")"; exit 1; }
CYRIUS_DCE=1 "$CC" < "$T/k.cyr" > "$T/k1.bin" 2> "$T/k1.err" || { echo "FAIL: dce_kernel_compaction_boots: the CYRIUS_DCE=1 kernel build failed: $(cat "$T/k1.err")"; exit 1; }
grep -q 'bytes of dead code eliminated' "$T/k1.err" || fail "C: CYRIUS_DCE=1 does not compact the kernel: $(cat "$T/k1.err")"
S0=$(wc -c < "$T/k0.bin"); S1=$(wc -c < "$T/k1.bin")
[ "$S1" -lt "$S0" ] || fail "C: the CYRIUS_DCE=1 kernel is $S1 B, not smaller than the plain one's $S0 B"

QEMU=$(command -v qemu-system-x86_64 || true)
if [ -z "$QEMU" ]; then
    if [ "$FAILS" -gt 0 ]; then echo "FAIL: dce_kernel_compaction_boots ($FAILS)"; exit 1; fi
    if [ "${CYRIUS_REQUIRE_BOOT:-0}" = "1" ]; then
        echo "FAIL: dce_kernel_compaction_boots: qemu-system-x86_64 absent but CYRIUS_REQUIRE_BOOT=1"; exit 1
    fi
    echo "SKIP: dce_kernel_compaction_boots — qemu-system-x86_64 not installed, the compacted kernel was built ($S0 -> $S1 B) but NOT booted"
    exit 77
fi
for D in 0 1; do
    QR=0
    timeout 60 "$QEMU" -accel tcg -kernel "$T/k$D.bin" -serial "file:$T/s$D" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 || QR=$?
    OUT=$(od -An -tx1 -v "$T/s$D" 2>/dev/null | tr -d ' \n')
    # "kdata-ok C\n"
    [ "$QR" = 33 ] && [ "$OUT" = 6b646174612d6f6b20430a ] \
        || fail "B$D: the CYRIUS_DCE=$D kernel exits QEMU $QR with serial bytes '$OUT' (want 33 and 6b646174612d6f6b20430a, \"kdata-ok C\\n\")"
done
if [ "$FAILS" -gt 0 ]; then echo "FAIL: dce_kernel_compaction_boots ($FAILS)"; exit 1; fi
echo "PASS: dce_kernel_compaction_boots (a CYRIUS_DCE=1 kernel image, $S0 -> $S1 B, boots under QEMU and reads its moved string and array element)"
exit 0
