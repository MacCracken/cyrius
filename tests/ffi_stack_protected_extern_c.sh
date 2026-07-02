#!/bin/sh
# v6.3.26 regression gate — "Class B FFI / fncall6" reframed.
#
# The long-standing folklore "fncall6 into extern-C wgpu is unreliable" was a
# MISDIAGNOSIS. fncall4/5/6/7 arg-passing (rdi,rsi,rdx,rcx,r8,r9 + 16-byte stack
# alignment) is CORRECT. The real failure was TLS/%fs: a glibc-compiled C
# function (all of wgpu-native) reads its stack-protector canary from %fs:0x28,
# and cyrius either (a) never bootstrapped a glibc-compatible %fs, or (b)
# arch_prctl-clobbered the host's %fs via thread_local_init. Either way the C
# callee faults on its prologue `mov %fs:0x28,%rax`, regardless of arg count.
#
# This gate locks two guarantees so the wgpu C-hook path (NVIDIA route, live
# through mabda v5.0 per ADR-006) can never silently rot:
#   (A) a STACK-PROTECTED extern-C fn taking 4/5/6/7 integer args returns the
#       correct result when called via fncallN with a glibc TLS bootstrap.
#   (B) thread_local_use_foreign_tls() lets cyrius thread-locals coexist with a
#       host-owned %fs WITHOUT clobbering it or the C stack canary (%fs:0x28).
#
# Skips gracefully off Linux/x86_64, or without gcc / libc.so.6 / build/cycc.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CYCC="$ROOT/build/cycc"

# --- platform gate: this exercises the SysV x86_64 / glibc path only ---
uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)
if [ "$uname_s" != "Linux" ] || [ "$uname_m" != "x86_64" ]; then
    echo "SKIP: extern-C fncallN gate is Linux/x86_64 only (host: $uname_s/$uname_m)"
    exit 0
fi
if ! command -v gcc >/dev/null 2>&1; then
    echo "SKIP: gcc not available (needed to build the stack-protected C .so)"
    exit 0
fi
if [ ! -x "$CYCC" ]; then
    echo "SKIP: build/cycc not built"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- (A) stack-protected C library: 4/5/6/7-arg int fns, each with an array
#         local so -fstack-protector-all emits the %fs:0x28 canary read/check.
cat > "$TMP/extc.c" <<'CEOF'
#include <stdint.h>
/* array local => stack protector => `mov %fs:0x28,%rax` in the prologue. */
long sum4(long a,long b,long c,long d){ volatile long s[4]={a,b,c,d}; return s[0]+s[1]+s[2]+s[3]; }
long sum5(long a,long b,long c,long d,long e){ volatile long s[5]={a,b,c,d,e}; return s[0]+s[1]+s[2]+s[3]+s[4]; }
long sum6(long a,long b,long c,long d,long e,long f){ volatile long s[6]={a,b,c,d,e,f}; return s[0]+s[1]+s[2]+s[3]+s[4]+s[5]; }
long sum7(long a,long b,long c,long d,long e,long f,long g){ volatile long s[7]={a,b,c,d,e,f,g}; return s[0]+s[1]+s[2]+s[3]+s[4]+s[5]+s[6]; }
CEOF
if ! gcc -O2 -fstack-protector-all -fno-omit-frame-pointer -shared -fPIC \
        -o "$TMP/libextc.so" "$TMP/extc.c" 2>"$TMP/gcc.err"; then
    echo "SKIP: gcc could not build the stack-protected .so"
    sed 's/^/  /' "$TMP/gcc.err" 2>/dev/null | head -5
    exit 0
fi

# cyrius driver: bootstrap glibc TLS, dlopen, call sum4/5/6/7 via fncallN, assert.
cat > "$TMP/drv.cyr" <<EOF
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/fnptr.cyr"
include "lib/dynlib.cyr"
alloc_init();
# glibc TLS bootstrap — installs the %fs block whose 0x28 canary the C fns read.
var boot = dynlib_bootstrap_cpu_features();
if (boot != 0) { syscall(SYS_WRITE, 1, "SKIP_NOGLIBC\n", 13); syscall(60, 77); }
if (dynlib_bootstrap_tls() == 0) { syscall(60, 60); }
dynlib_bootstrap_stack_end(0);
var h = dynlib_open("$TMP/libextc.so");
if (h == 0) { syscall(60, 61); }
var bias = load64(h + 40);
_dynlib_apply_irelative(h, bias, load64(h + 88), load64(h + 96));
_dynlib_apply_irelative(h, bias, load64(h + 104), load64(h + 112));
var f4 = dynlib_sym(h, "sum4");
var f5 = dynlib_sym(h, "sum5");
var f6 = dynlib_sym(h, "sum6");
var f7 = dynlib_sym(h, "sum7");
if (f4 == 0) { syscall(60, 62); }
if (f5 == 0) { syscall(60, 63); }
if (f6 == 0) { syscall(60, 64); }
if (f7 == 0) { syscall(60, 65); }
if (fncall4(f4, 1, 2, 3, 4) != 10) { syscall(60, 66); }
if (fncall5(f5, 1, 2, 3, 4, 5) != 15) { syscall(60, 67); }
if (fncall6(f6, 1, 2, 3, 4, 5, 6) != 21) { syscall(60, 68); }
if (fncall7(f7, 1, 2, 3, 4, 5, 6, 7) != 28) { syscall(60, 69); }
syscall(60, 0);
EOF
if ! "$CYCC" < "$TMP/drv.cyr" > "$TMP/drv" 2>"$TMP/drv.err"; then
    echo "FAIL: could not compile the fncallN extern-C driver"
    sed 's/^/  /' "$TMP/drv.err" | head -8
    exit 1
fi
chmod +x "$TMP/drv"
set +e
"$TMP/drv"
rc=$?
set -e
if [ "$rc" = "77" ]; then
    echo "SKIP: no glibc on host (dynlib_bootstrap_cpu_features failed)"
    exit 0
fi
if [ "$rc" != "0" ]; then
    echo "FAIL(A): stack-protected extern-C via fncallN returned exit $rc (expected 0)"
    echo "  62-65=sym resolve; 66=sum4 67=sum5 68=sum6 69=sum7; 60/61=bootstrap/open"
    exit 1
fi
echo "  PASS(A): sum4/sum5/sum6/sum7 (stack-protected extern-C) correct via fncallN"

# --- (B) foreign-%fs coexistence: thread_local_use_foreign_tls() must leave a
#         host-owned %fs (and its 0x28 canary) untouched, routing slots to the
#         process-global fallback.
cat > "$TMP/coexist.cyr" <<'EOF'
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/thread_local.cyr"
alloc_init();
var fake = alloc(4096);
var i = 0; while (i < 4096) { store8(fake + i, 0); i = i + 1; }
store64(fake + 0x28, 0xCA11AB1E);          # sentinel canary at %fs:0x28
syscall(158, 0x1002, fake);                # arch_prctl(SET_FS, fake) — simulate glibc host
var out = alloc(8);
store64(out, 0); syscall(158, 0x1003, out); var fs0 = load64(out);
thread_local_use_foreign_tls();
thread_local_init();                        # must NOT clobber %fs
store64(out, 0); syscall(158, 0x1003, out); var fs1 = load64(out);
thread_local_set(8, 999);
thread_local_set(5, 777);                   # slot 5 == %fs:0x28 in %fs mode
if (fs0 != fs1) { syscall(60, 1); }         # %fs clobbered
if (thread_local_get(8) != 999) { syscall(60, 2); }
if (thread_local_get(5) != 777) { syscall(60, 2); }
if (load64(fake + 0x28) != 0xCA11AB1E) { syscall(60, 3); }  # canary corrupted
syscall(60, 0);
EOF
if ! "$CYCC" < "$TMP/coexist.cyr" > "$TMP/coexist" 2>"$TMP/coexist.err"; then
    echo "FAIL: could not compile the foreign-TLS coexistence check"
    sed 's/^/  /' "$TMP/coexist.err" | head -8
    exit 1
fi
chmod +x "$TMP/coexist"
set +e
"$TMP/coexist"
rc2=$?
set -e
if [ "$rc2" != "0" ]; then
    echo "FAIL(B): foreign-TLS coexistence exit $rc2 (1=%fs clobbered, 2=roundtrip, 3=canary corrupted)"
    exit 1
fi
echo "  PASS(B): thread_local_use_foreign_tls() coexists — %fs + canary intact, slots via fallback"

echo "PASS: fncallN into stack-protected extern-C + foreign-%fs coexistence (v6.3.26)"
exit 0
