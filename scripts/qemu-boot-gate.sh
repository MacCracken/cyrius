#!/bin/sh
# qemu-boot-gate.sh — D7 (v6.2.28): a REAL boot of the in-repo bare-metal kernel.
#
# Proves the kernel codegen EXECUTES — not merely that it emits a valid-shaped ELF.
# This is the anti-rot gate the macho port never had: the macOS compiler self-host
# rotted for 9 minors behind a CI job that only ran hello-world and never the real
# thing. A green checkmark is NOT verification; the kernel actually running IS.
#
# Builds programs/boot_serial.cyr (a `kernel;` program that writes "AGNOS" to COM1)
# two ways:
#   1. via the formalized triple (--target=x86_64-bare-metal-elf) → ELF64 multiboot2,
#      the class agnos ships: SHAPE-verify (ELF64, entry 0x1000a8, multiboot2 magic,
#      single PT_LOAD, no PT_INTERP). QEMU's built-in -kernel loader is multiboot1
#      only, so the ELF64/multiboot2 path is shape-gated here (GRUB-booted in agnos).
#   2. plain `kernel;` → ELF32 multiboot1: BOOTED under QEMU -kernel; we assert the
#      kernel writes "AGNOS" to serial. This is the real execution proof of the
#      shared kmode codegen (entry, prologue-less _start, the asm{} block, port I/O).
#
# Exit 0 = gate passed (or visibly skipped when QEMU is absent — never a silent
# green: a skip prints a loud SKIP line so a qemu-less CI box can't masquerade as
# "boot verified").

set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CYRIUS="$REPO/build/cyrius"
SRC="$REPO/programs/boot_serial.cyr"
TRIPLE_OUT="$REPO/build/boot_serial_elf64"
BOOT_OUT="$REPO/build/boot_serial"

[ -x "$CYRIUS" ] || { echo "FAIL: $CYRIUS not built"; exit 1; }
[ -f "$SRC" ] || { echo "FAIL: $SRC missing"; exit 1; }

# --- 1. triple → ELF64 multiboot2 (the agnos-shipped class): shape-verify ---
"$CYRIUS" build --target=x86_64-bare-metal-elf "$SRC" "$TRIPLE_OUT" >/dev/null 2>&1 \
    || { echo "FAIL: triple build (--target=x86_64-bare-metal-elf)"; exit 1; }
python3 - "$TRIPLE_OUT" <<'PY' || exit 1
import sys
d = open(sys.argv[1], 'rb').read()
ok = True
if d[:4] != b'\x7fELF':       print("FAIL: not an ELF"); ok = False
if d[4] != 2:                 print("FAIL: triple kernel is not ELF64"); ok = False
entry = int.from_bytes(d[24:32], 'little')
if entry != 0x1000a8:         print(f"FAIL: ELF64 entry {hex(entry)} != 0x1000a8"); ok = False
# multiboot2 header: spec requires it in the first 32768 bytes, 8-byte aligned.
mb2 = (0xE85250D6).to_bytes(4, 'little')
if not any(d[o:o+4] == mb2 for o in range(0, min(len(d), 32768), 8)):
    print("FAIL: no aligned multiboot2 header in first 32 KiB"); ok = False
# single PT_LOAD, no PT_INTERP (freestanding) — phoff/phnum from the ELF64 header
phoff = int.from_bytes(d[32:40], 'little'); phentsize = int.from_bytes(d[54:56], 'little')
phnum = int.from_bytes(d[56:58], 'little')
loads = interp = 0
for i in range(phnum):
    p = phoff + i * phentsize
    t = int.from_bytes(d[p:p+4], 'little')
    if t == 1: loads += 1
    if t == 3: interp += 1
if loads != 1: print(f"FAIL: expected 1 PT_LOAD, got {loads}"); ok = False
if interp != 0: print("FAIL: freestanding kernel has a PT_INTERP"); ok = False
print(f"  ELF64 triple kernel OK: entry {hex(entry)}, {loads} PT_LOAD, multiboot2, no PT_INTERP")
sys.exit(0 if ok else 1)
PY

# --- 1b. aarch64 triple → ELF64: shape-verify the entry/base the D6 report claims ---
# (no QEMU boot — cross-compiled from x86, shape-only, mirroring the x86 ELF64 leg;
# this closes the drift window on the 0x40000078 value printed by cbt/commands.cyr.)
AA_OUT="$REPO/build/boot_serial_aa64"
if "$CYRIUS" build --target=aarch64-bare-metal-elf "$SRC" "$AA_OUT" >/dev/null 2>&1; then
    python3 - "$AA_OUT" <<'PY' || exit 1
import sys
d = open(sys.argv[1], 'rb').read()
ok = True
if d[4] != 2:                 print("FAIL: aarch64 kernel not ELF64"); ok = False
mach = int.from_bytes(d[18:20], 'little')
if mach != 0xB7:              print(f"FAIL: e_machine {hex(mach)} != EM_AARCH64"); ok = False
entry = int.from_bytes(d[24:32], 'little')
if entry != 0x40000078:       print(f"FAIL: aarch64 entry {hex(entry)} != 0x40000078 (D6 report would be stale)"); ok = False
phoff = int.from_bytes(d[32:40], 'little'); phentsize = int.from_bytes(d[54:56], 'little')
phnum = int.from_bytes(d[56:58], 'little'); loads = interp = 0
for i in range(phnum):
    p = phoff + i * phentsize; t = int.from_bytes(d[p:p+4], 'little')
    if t == 1:
        loads += 1
        if int.from_bytes(d[p+16:p+24], 'little') != 0x40000000:
            print("FAIL: aarch64 PT_LOAD p_vaddr != 0x40000000"); ok = False
    if t == 3: interp += 1
if loads != 1:  print(f"FAIL: aarch64 expected 1 PT_LOAD, got {loads}"); ok = False
if interp != 0: print("FAIL: aarch64 freestanding kernel has a PT_INTERP"); ok = False
print(f"  ELF64 aarch64 kernel OK: entry {hex(entry)}, base 0x40000000, {loads} PT_LOAD")
sys.exit(0 if ok else 1)
PY
else
    echo "  SKIP aarch64 shape-check: cycc_aarch64 not built (run the build job first)"
fi

# --- 2. plain kernel; → ELF32 multiboot1: REAL boot under QEMU ---
"$CYRIUS" build "$SRC" "$BOOT_OUT" >/dev/null 2>&1 \
    || { echo "FAIL: plain kernel build"; exit 1; }

QEMU="$(command -v qemu-system-x86_64 || true)"
if [ -z "$QEMU" ]; then
    # In CI the runner MUST have qemu — a qemu-less skip there would be the exact
    # green-checkmark-without-boot placebo this gate exists to kill. CYRIUS_REQUIRE_BOOT=1
    # (set by the CI job) turns the skip into a hard failure; dev boxes skip cleanly.
    if [ "${CYRIUS_REQUIRE_BOOT:-0}" = "1" ]; then
        echo "FAIL: qemu-system-x86_64 absent but CYRIUS_REQUIRE_BOOT=1 — CI must boot the kernel, not skip"
        exit 1
    fi
    echo "SKIP: qemu-system-x86_64 not installed — kernel BOOT not run (install 'qemu-system-x86' to gate execution; the ELF64 shape-checks above still passed)"
    exit 0
fi

# boot_serial ends in `cli; hlt; jmp $` — it HALTS after printing, it does NOT
# self-exit, so QEMU idles until this timeout. "AGNOS" lands within ~1s; the
# timeout is the steady-state stop (and a backstop against a genuine hang).
OUT="$(timeout 12 "$QEMU" -accel tcg -kernel "$BOOT_OUT" -serial stdio -display none -no-reboot 2>/dev/null | tr -d '\0' || true)"
case "$OUT" in
    *AGNOS*) echo "  BOOT OK: kernel executed, serial emitted 'AGNOS'"; echo "PASS: qemu boot gate"; exit 0 ;;
    *)       echo "FAIL: kernel booted but did not emit 'AGNOS' (got: $(printf '%s' "$OUT" | head -c 80))"; exit 1 ;;
esac
