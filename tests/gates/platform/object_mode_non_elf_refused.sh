#!/bin/sh
# object_mode_non_elf_refused.sh — 6.6.10. `kernel;` / `shared;` / `object;` are refused BY NAME
# (rc 1, no output) on every output format that has no emitter for them, and keep working where
# one exists.
#
# THE BUG. Only the ELF emitters implement the modes (x86: EMITELF_KERNEL / _SHARED / _OBJ;
# aarch64: EMITELF_KERNEL). Every fork's pass 1 accepted the directives unconditionally and both
# EMITELF ladders dispatch Mach-O / PE before reading the mode, so — silently, measured at 6.6.9:
#   PE           `object;` rc 0 and ZERO bytes; `shared;` an exe that access-violates
#                (0xC0000005 on real cass); `kernel;` identical to no mode (that one is FINE)
#   x86 Mach-O   `object;` ran and exited 72 on real ach; `kernel;` identical to no mode;
#                `shared;` an executable, not a dylib
#   aarch64 ELF  `shared;` an ELF EXECUTABLE (no EMITELF_SHARED arm)
#   arm64 Mach-O `kernel;` / `shared;` byte-identical to no mode
#   cx           `kernel;` / `shared;` byte-identical to no mode (pass 1 set it, nothing read it)
# THE RULE IS PER MODE, NOT PER FORMAT. `kernel;` on PE/EFI is legitimate and must keep
# building: gnoboot/src/main.cyr (the UEFI bootloader), programs/efi_probe.cyr and
# programs/efi_fn_exit_probe.cyr carry it, and it drives the #host_only bare-metal refusal. The
# positive rows below pin exactly that. CHANGELOG [6.6.10]
#
# ONE ROW PER (compiler configuration × mode): x86 ELF, PE, EFI, x86 Mach-O, aarch64 ELF, arm64
# Mach-O, cx. The compilers are built FROM SOURCE with $CC, so reverting the fix turns this RED.
# `object;` is not a directive at all on the aarch64 and cx forks ("unexpected object"), which is
# a refusal already; those rows require rc 1 and the word `object`.
# (The native macOS drivers main_x86_macho.cyr / main_aarch64_macho.cyr share these fixups; they
# cannot run here and were measured on ach / ecb at 6.6.10.)
#
# MUTATION (6.6.10, built and run): make _mode_unsupported (runtime.cyr) return 0 → 10 refusal
# rows go red (PE ×2, EFI ×2, x86 Mach-O ×3, aarch64 ELF shared, arm64 Mach-O ×2); drop the cx
# _cx_mode_refused call → the 2 cx rows go red. Refusing `kernel;` on PE too → the PE/EFI
# positive rows and efi_probe go red.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL object_mode_non_elf_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL object_mode_non_elf_refused: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0

"$CC" < src/main.cyr > "$T/x86" 2> "$T/eb" || { echo "FAIL object_mode_non_elf_refused: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
for f in aarch64 cx; do
  "$T/x86" < "src/main_$f.cyr" > "$T/$f" 2> "$T/eb" || { echo "FAIL object_mode_non_elf_refused: could not build src/main_$f.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
  chmod +x "$T/$f"
done
for m in kernel shared object; do
  printf '%s;\nfn f(): i64 { return 42; }\nvar r = f();\n' "$m" > "$T/$m.cyr"
done
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# comp <label> <mode> <env-assignment|-> <compiler> — sets rc, output in $T/o, stderr in $T/e
comp() {
  if [ "$3" = - ]; then env -u CYRIUS_TARGET_WIN -u CYRIUS_TARGET_EFI -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM "$T/$4" < "$T/$2.cyr" > "$T/o" 2> "$T/e"; rc=$?
  else env -u CYRIUS_TARGET_WIN -u CYRIUS_TARGET_EFI -u CYRIUS_MACHO -u CYRIUS_MACHO_ARM "$3" "$T/$4" < "$T/$2.cyr" > "$T/o" 2> "$T/e"; rc=$?; fi
}
# ok <label> <mode> <env> <compiler> — must build: rc 0 and a non-empty output
ok() {
  comp "$@"
  if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then _bad "$1 \`$2;\`: rc $rc, $(wc -c < "$T/o") bytes — must still build"; grep -m2 '^error' "$T/e" | sed 's/^/      /'
  else pass=$((pass + 1)); fi
}
# refused <label> <mode> <env> <compiler> <needle> — rc 1, zero bytes, the needle on stderr
refused() {
  lab=$1; md=$2; nd=$5
  comp "$1" "$2" "$3" "$4"
  if [ "$rc" -ne 1 ] || [ -s "$T/o" ] || ! grep -q -- "$nd" "$T/e"; then
    _bad "$lab \`$md;\`: rc $rc, $(wc -c < "$T/o") bytes — expected rc 1, no output, and '$nd'"; grep -m2 '^error' "$T/e" | sed 's/^/      /'
  else pass=$((pass + 1)); fi
}

# x86 ELF — every mode has an emitter (anti-vacuous: a gate that refused everything fails here)
for m in kernel shared object; do ok "x86 ELF" "$m" - x86; done
# PE and EFI — kernel; stays (the UEFI bare-metal gate); shared; and object; are refused
for pair in "PE CYRIUS_TARGET_WIN=1" "EFI CYRIUS_TARGET_EFI=1"; do
  set -- $pair
  ok "$1" kernel "$2" x86
  refused "$1" shared "$2" x86 '`shared;` is not supported for PE output'
  refused "$1" object "$2" x86 '`object;` is not supported for PE output'
done
# x86 Mach-O — no emitter for any mode
for m in kernel shared object; do refused "x86 Mach-O" "$m" CYRIUS_MACHO=1 x86 "\`$m;\` is not supported for x86_64 Mach-O output"; done
# aarch64 ELF — kernel; has an emitter, shared; does not, object; is not a directive there
ok "aarch64 ELF" kernel - aarch64
refused "aarch64 ELF" shared - aarch64 '`shared;` is not supported for aarch64 ELF output'
refused "aarch64 ELF" object - aarch64 'object'
# arm64 Mach-O — none
refused "arm64 Mach-O" kernel CYRIUS_MACHO_ARM=1 aarch64 '`kernel;` is not supported for arm64 Mach-O output'
refused "arm64 Mach-O" shared CYRIUS_MACHO_ARM=1 aarch64 '`shared;` is not supported for arm64 Mach-O output'
refused "arm64 Mach-O" object CYRIUS_MACHO_ARM=1 aarch64 'object'
# cx — none
refused cx kernel - cx '`kernel;` is not supported by the cx bytecode backend'
refused cx shared - cx '`shared;` is not supported by the cx bytecode backend'
refused cx object - cx 'object'

# The in-tree `kernel;` UEFI programs still build (check.sh's platform_efi also compiles efi_probe).
for p in programs/efi_probe.cyr programs/efi_fn_exit_probe.cyr; do
  if grep -q '^kernel;' "$p"; then
    CYRIUS_TARGET_EFI=1 "$T/x86" < "$p" > "$T/o" 2> "$T/e"; rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then _bad "$p (CYRIUS_TARGET_EFI=1, carries \`kernel;\`): rc $rc — must still build"; grep -m2 '^error' "$T/e" | sed 's/^/      /'
    else pass=$((pass + 1)); fi
  else _bad "$p no longer carries \`kernel;\` — this row would prove nothing; point it at a program that does"; fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL object_mode_non_elf_refused: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS object_mode_non_elf_refused: $pass rows — kernel;/shared;/object; refused by name on PE (kernel; kept), EFI (kernel; kept), x86 Mach-O, aarch64 ELF (shared;), arm64 Mach-O and cx; every mode still builds on x86 ELF; the EFI kernel; programs build"
exit 0
