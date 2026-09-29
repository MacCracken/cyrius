#!/bin/sh
# pe_hosted_elf_object.sh — 6.6.10. The Windows-hosted compiler emits an ELF object (`object;`
# with CYRIUS_TARGET_WIN=0) byte-identical to the Linux one, and EMITELF_OBJ uses no raw brk.
#
# THE BUG. EMITELF_OBJ (src/backend/x86/fixup.cyr) extended brk for its scratch tables, on the
# stale premise "Compiler has no alloc()". It was the last raw brk in shared x86 code:
#   - brk is ENOSYS on Windows, and the path IS reachable there — main_win.cyr accepts
#     `object;` and CYRIUS_TARGET_WIN=0 makes cycc.exe emit ELF — so every such compile died
#     with "error: EMITELF_OBJ could not extend brk for its scratch tables" (wine AND real cass);
#   - building the x86 Mach-O compiler (CYRIUS_MACHO=1 < src/main_x86_macho.cyr) printed the
#     syscall-12 "not routed" warning twice (the path is DCE-live there, never run).
# THE FIX. `alloc(scratch_need)` plus a zero check. CHANGELOG [6.6.10]
#
# ROWS
#   1  x86 Mach-O compiler build: zero "syscall 12 not routed" warnings (was 2). No wine needed.
#   2  source pin: no SYS_BRK / syscall(12 anywhere in src/backend/x86/fixup.cyr.
#   3  under wine (SKIP without it): the PE compiler built FROM SOURCE, run with
#      CYRIUS_TARGET_WIN=0 over the four object fixtures in tests/fixtures/linker/, exits 0 and
#      writes an .o byte-identical to the Linux compiler's for the same fixture. The Linux .o
#      must itself be an ELF relocatable (anti-vacuous: two empty files are equal too).
# MUTATION (6.6.10, built and run): restore the brk pair → row 1 reports 2 warnings, row 2
# names the line, row 3 fails every fixture with the brk error — RED on all three.
# HARDWARE: measured on real cass at 6.6.10 (cycc.exe, CYRIUS_TARGET_WIN=0, object; → .o
# identical to Linux); wine is the local approximation.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL pe_hosted_elf_object: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL pe_hosted_elf_object: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# ── row 1: the x86 Mach-O compiler builds without the brk warning ──────────────────────────
CYRIUS_MACHO=1 "$CC" < src/main_x86_macho.cyr > "$T/mx" 2> "$T/mx.err"
if [ ! -s "$T/mx" ]; then _bad "the x86 Mach-O compiler did not build"; sed -n 1,3p "$T/mx.err"
else
  n=$(grep -c 'syscall 12 not routed' "$T/mx.err")
  if [ "$n" -ne 0 ]; then _bad "building the x86 Mach-O compiler warns about an unrouted brk $n time(s)"; else pass=$((pass + 1)); fi
fi

# ── row 2: no raw brk left in the x86 fixup ────────────────────────────────────────────────
if grep -nE 'SYS_BRK|syscall\(12[,)]' src/backend/x86/fixup.cyr > "$T/brk"; then _bad "src/backend/x86/fixup.cyr uses a raw brk again: $(head -1 "$T/brk")"; else pass=$((pass + 1)); fi

# ── row 3: the Windows-hosted compiler's ELF-object path ──────────────────────────────────
if ! command -v wine > /dev/null 2>&1; then
  echo "  SKIP row 3: wine absent — the Windows-hosted object path is covered only by the cass measurement"
else
  CYRIUS_TARGET_WIN=1 "$CC" < src/main_win.cyr > "$T/cycc.exe" 2> "$T/pe.err"
  if [ ! -s "$T/cycc.exe" ]; then _bad "the PE compiler did not build"; grep -m3 '^error' "$T/pe.err"
  else
    export WINEPREFIX="$T/wp" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    nfx=0
    for fx in tests/fixtures/linker/*.cyr; do
      grep -q '^object;' "$fx" || continue
      nfx=$((nfx + 1))
      b=$(basename "$fx" .cyr)
      "$CC" < "$fx" > "$T/$b.lin.o" 2> /dev/null
      if [ "$(head -c 4 "$T/$b.lin.o" | od -An -tx1 | tr -d ' ')" != "7f454c46" ] || [ "$(od -An -tu1 -j16 -N1 "$T/$b.lin.o" | tr -d ' ')" != "1" ]; then
        _bad "$b: the Linux compiler's output is not an ELF relocatable (anti-vacuous)"; continue
      fi
      CYRIUS_TARGET_WIN=0 wine "$T/cycc.exe" < "$fx" > "$T/$b.pe.o" 2> "$T/$b.pe.err"; rc=$?
      if [ "$rc" -ne 0 ]; then _bad "$b: cycc.exe (CYRIUS_TARGET_WIN=0) rc $rc — $(grep -m1 '^error' "$T/$b.pe.err")"
      elif ! cmp -s "$T/$b.lin.o" "$T/$b.pe.o"; then _bad "$b: the Windows-hosted .o differs from the Linux .o"
      else pass=$((pass + 1)); fi
    done
    [ "$nfx" -ge 4 ] || _bad "only $nfx object fixtures under tests/fixtures/linker (floor 4)"
    rm -rf "$T/wp"
  fi
fi

if [ "$fail" -ne 0 ]; then echo "FAIL pe_hosted_elf_object: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS pe_hosted_elf_object: $pass rows — no raw brk in the x86 fixup, the x86 Mach-O compiler builds warning-free, and the Windows-hosted compiler's ELF objects match Linux byte for byte"
exit 0
