#!/bin/sh
# self_compile_no_large_static_advisory.sh — 6.7.17: the compiler's own self-compile prints no
# "large static data" advisory, on any fork and through any backend a self-host runs.
#
# ⛔ WHY. Every x86 self-compile (cycc, the PE cross compiler, the x86 Mach-O compiler) printed
# `warning: large static data (142880 bytes) — consider alloc() for buffers >4KB` at rc 0: the
# TypeScript front end's node-index scratch stack was a top-level `var _ts_cst[8192];` (65,536 B,
# a bare top-level array is N × 8), half of cycc's var data, untouched by a plain cyrius compile.
# One warning on every bootstrap, fixpoint, release gate and lane rebuild trains readers to skip
# the stderr real warnings land on. The stack is alloc()'d on first TS use now
# (src/frontend/ts/parse.cyr _ts_cst_buf); _warn_large_static is unchanged, no special case.
# CHANGELOG [6.7.17] (issues/archived/2026-10-13-self-compile-prints-large-static-advisory.md)
#
# Rows (each: rc 0, non-empty output, no `large static data` line on stderr):
#   host     the x86_64 stage compiler compiles every fork source (main, main_win,
#            main_x86_macho, main_aarch64, main_aarch64_macho, main_cx)
#   selfhost each host's own self-compile shape: the PE cross compiler on main_win (cass),
#            CYRIUS_MACHO=1 on main_x86_macho (ach), the aarch64 cross compiler on main_aarch64
#            and main_aarch64_native (pi) and CYRIUS_MACHO_ARM=1 on main_aarch64_macho (ecb)
#   control  the same stage compiler on a 160 KB-of-globals program DOES print the advisory, so
#            a grep that never matches cannot pass the rows above
#
# Compilers are built FROM SOURCE, so a revert turns this RED rather than being masked by a
# stale build/ binary. Mach-O and PE output is produced on Linux (it is not run here).
#
# Mutation (6.7.17): `var _ts_cst[8192];` restored (the pointer and _ts_cst_buf() reverted) ->
# 5 rows RED: host main / main_win / main_x86_macho and selfhost-pe / selfhost-x86-macho.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: self_compile_no_large_static_advisory: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL self_compile_no_large_static_advisory: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
"$CC" < src/main.cyr > "$T/x86" 2>"$T/eb" || { echo "FAIL self_compile_no_large_static_advisory: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"

fail=0
pass=0
# row <label> <compiler> <source> <env-or--> [<keep-output-as>]
# The output is kept whenever it BUILT (rc 0, non-empty), advisory or not, so a red host row
# still hands its compiler to the self-host rows below and they are scored too.
row() {
  lbl=$1; c=$2; src=$3; ev=$4; keep=${5:-}
  if [ "$ev" = - ]; then "$c" < "$src" > "$T/o" 2>"$T/e"; rc=$?
  else env "$ev" "$c" < "$src" > "$T/o" 2>"$T/e"; rc=$?; fi
  if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then
    echo "  FAIL: $lbl $src: build rc $rc, $(wc -c < "$T/o") bytes"; sed -n 1,3p "$T/e"; fail=$((fail + 1)); return 0
  fi
  if [ -n "$keep" ]; then cp "$T/o" "$keep" && chmod +x "$keep"; fi
  if grep -q 'large static data' "$T/e"; then
    echo "  FAIL: $lbl $src: the compiler's own build prints the advisory: $(grep 'large static data' "$T/e" | sed -n 1p)"
    fail=$((fail + 1)); return 0
  fi
  pass=$((pass + 1))
  return 0
}

for f in main main_win main_x86_macho main_aarch64 main_aarch64_macho main_cx; do
  # the PE and aarch64 cross compilers built here are the next rows' compilers
  row host "$T/x86" "src/$f.cyr" - "$T/bin_$f"
done

# the self-host shapes: each host's compiler (built above from source) on the source it self-hosts
if [ -x "$T/bin_main_win" ]; then
  row selfhost-pe "$T/bin_main_win" src/main_win.cyr -
else echo "  FAIL: selfhost-pe: no PE cross compiler was built"; fail=$((fail + 1)); fi
row selfhost-x86-macho "$T/x86" src/main_x86_macho.cyr CYRIUS_MACHO=1
if [ -x "$T/bin_main_aarch64" ]; then
  row selfhost-aarch64 "$T/bin_main_aarch64" src/main_aarch64.cyr -
  row selfhost-aarch64-native "$T/bin_main_aarch64" src/main_aarch64_native.cyr -
  row selfhost-arm64-macho "$T/bin_main_aarch64" src/main_aarch64_macho.cyr CYRIUS_MACHO_ARM=1
else echo "  FAIL: selfhost-aarch64: no aarch64 cross compiler was built"; fail=$((fail + 1)); fi

# control: the advisory still fires on a program that has the static data
printf 'var big[20000];\nvar r = 1;\n' > "$T/big.cyr"
"$T/x86" < "$T/big.cyr" > "$T/o" 2>"$T/e"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^warning: large static data (160' "$T/e"; then pass=$((pass + 1))
else echo "  FAIL: control: 160 KB of globals built rc $rc without the advisory (the rows above prove nothing)"; fail=$((fail + 1)); fi

if [ "$fail" -ne 0 ]; then echo "FAIL self_compile_no_large_static_advisory: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS self_compile_no_large_static_advisory: $pass rows — no advisory on any fork's build or self-host shape (x86, PE, x86/arm64 Mach-O, aarch64, cx); the control still warns"
exit 0
