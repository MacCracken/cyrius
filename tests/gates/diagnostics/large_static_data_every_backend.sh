#!/bin/sh
# large_static_data_every_backend.sh — 6.6.9 bite 2. The "large static data" advisory prints on
# EVERY backend that writes an executable, not just x86_64 ELF.
#
# ⛔ WHY. The warning lived inline in x86 EMITELF_USER, so `var buf[20000]` (160 KB of statics)
# warned on x86_64 Linux and said nothing on PE, x86 Mach-O, aarch64 ELF, arm64 Mach-O and cx —
# the same program, the same 160 KB, five silent targets. It is now one shared emitter
# (`_warn_large_static`, src/frontend/parse_fn.cyr) called from each backend's emit path.
#
# Rows:
#   big     160 KB of globals            → the warning on all seven output shapes
#   local   an over-budget fn-local array (static storage) → the warning on all seven
#   small   800 B of globals             → silent everywhere (anti-vacuous: a gate that grepped
#                                          for any "warning" would pass on an always-on emitter)
#   cxheap  a cx program that allocates  → silent: lib/alloc_cx.cyr's 128 KB `_cx_heap_buf` IS
#                                          alloc()'s heap, and advising "consider alloc()" about
#                                          it would fire on every cx program that allocates
#
# Compilers are built FROM SOURCE, so a revert turns this RED rather than being masked by a
# stale build/ binary. Mach-O output is produced on Linux (it is not run here).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: large_static_data_every_backend: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL large_static_data_every_backend: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
"$CC" < src/main.cyr > "$T/x86" 2>"$T/eb" || { echo "FAIL large_static_data_every_backend: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
for f in aarch64 win cx; do
  "$T/x86" < "src/main_$f.cyr" > "$T/$f" 2>"$T/eb" || { echo "FAIL large_static_data_every_backend: could not build src/main_$f.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
  chmod +x "$T/$f"
done

printf 'var big[20000];\nvar r = 1;\n' > "$T/big.cyr"
printf 'fn keep(): i64 { var b[200000]; return load8(&b); }\nvar r = keep();\n' > "$T/local.cyr"
printf 'var small[100];\nvar r = 1;\n' > "$T/small.cyr"
cat > "$T/cxheap.cyr" <<'EOF'
include "lib/alloc.cyr"
alloc_init();
var p = alloc(64);
var r = 1;
EOF

fail=0
pass=0
# row <label> <fixture> <want 1|0> <env-or-> <compiler>
row() {
  lbl=$1; fx=$2; want=$3; ev=$4; c=$5
  if [ "$ev" = - ]; then "$T/$c" < "$T/$fx.cyr" > "$T/o" 2>"$T/e"; rc=$?
  else env "$ev" "$T/$c" < "$T/$fx.cyr" > "$T/o" 2>"$T/e"; rc=$?; fi
  if [ "$rc" -ne 0 ] || [ ! -s "$T/o" ]; then echo "  FAIL: $lbl $fx: build rc $rc"; fail=$((fail + 1)); return; fi
  got=0; grep -q '^warning: large static data (' "$T/e" && got=1
  if [ "$got" -ne "$want" ]; then
    if [ "$want" -eq 1 ]; then echo "  FAIL: $lbl $fx: no 'large static data' warning (x86_64 ELF prints it)"
    else echo "  FAIL: $lbl $fx: 'large static data' printed for a program that has none"; fi
    fail=$((fail + 1)); return
  fi
  pass=$((pass + 1))
}
for fx in big local; do
  row x86-elf     $fx 1 -                  x86
  row x86-macho   $fx 1 CYRIUS_MACHO=1     x86
  row pe          $fx 1 -                  win
  row aarch64-elf $fx 1 -                  aarch64
  row arm64-macho $fx 1 CYRIUS_MACHO_ARM=1 aarch64
  row cx          $fx 1 -                  cx
done
row x86-elf     small 0 -                  x86
row x86-macho   small 0 CYRIUS_MACHO=1     x86
row pe          small 0 -                  win
row aarch64-elf small 0 -                  aarch64
row arm64-macho small 0 CYRIUS_MACHO_ARM=1 aarch64
row cx          small 0 -                  cx
row cx          cxheap 0 -                 cx
# the byte count is the same figure on every backend that lays statics out flat
n86=$("$T/x86" < "$T/big.cyr" 2>&1 >/dev/null | sed -n 's/^warning: large static data (\([0-9]*\) bytes).*/\1/p')
na64=$("$T/aarch64" < "$T/big.cyr" 2>&1 >/dev/null | sed -n 's/^warning: large static data (\([0-9]*\) bytes).*/\1/p')
if [ -n "$n86" ] && [ "$n86" = "$na64" ]; then pass=$((pass + 1)); else echo "  FAIL: x86 reports '$n86' bytes, aarch64 '$na64' for the same globals"; fail=$((fail + 1)); fi

if [ "$fail" -ne 0 ]; then echo "FAIL large_static_data_every_backend: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS large_static_data_every_backend: $pass rows — advisory on x86/x86-Mach-O/PE/aarch64/arm64-Mach-O/cx, silent on small statics and on cx's own heap"
exit 0
