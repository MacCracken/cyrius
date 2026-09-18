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
# This gate locks three guarantees so the wgpu C-hook path (NVIDIA route, live
# through mabda v5.0 per ADR-006) can never silently rot:
#   (A) a STACK-PROTECTED extern-C fn taking 4/5/6/7 integer args returns the
#       correct result when called via fncallN with a glibc TLS bootstrap.
#   (B) thread_local_use_foreign_tls() lets cyrius thread-locals coexist with a
#       host-owned %fs WITHOUT clobbering it or the C stack canary (%fs:0x28).
#   (C) 6.6.5: the same calls from NESTED expression positions, which is where
#       the alignment actually broke.
#
# ⛔ 6.6.5 — WHAT (A) DID NOT COVER, AND WHY THAT MATTERED FOR SIX MINORS. Every
# fncallN in (A) is at TOP LEVEL, in left-operand position (`if (fncallN(...) !=
# K)`), where no value is pending on the expression stack — so every call it makes
# was aligned even while `f(0, fncallN(...))` was not. Its C callees WOULD have
# caught a misaligned call (gcc -O2 -fstack-protector-all gives sum4..sum7
# `movdqa`/`movaps` on stack slots), which is exactly what makes the omission
# costly: the gate looked like proof that "16-byte alignment into extern C is
# correct", and cyrius's own docs cited it as such, while the nested position
# SIGSEGV'd. This is the "a gate proves only the position it tests" lesson.
# Part (C) below adds those positions. See docs/development/issues/archived/
# 2026-09-16-mabda-cycc-nested-call-stack-misalignment.md.
#
# MUTATION LEDGER (measured 2026-09-17 on x86_64 Linux / glibc):
#   * the 6.6.4 compiler            -> PASS(A) PASS(B), FAIL(C) SIGSEGV. That split is the
#     clearest statement of what the v6.3.26 gate did and did not prove: the same C callees,
#     the same fncallN, only the expression position differs.
#   * a stub `build/cycc` that drains stdin and exits 0 (an EMPTY, executable output) ->
#     before the `[ -s ... ]` guards below: PASS(A) PASS(B) PASS(C), final PASS, rc=0. After
#     them: FAIL at the first compile. An empty file IS executable and `sh` runs it as an
#     empty script, so exit-status-only checking cannot see this.
#
# Skips gracefully off Linux/x86_64, or without gcc / libc.so.6 / build/cycc.
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
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
# ⛔ An EMPTY file is executable and `sh` runs it as an empty script — exit 0. cycc exits 0
# on empty stdin, so without this size check a compiler that produced nothing scored PASS on
# all three parts of this gate. Measured with a stub `build/cycc` that drains stdin and exits
# 0: PASS(A) PASS(B) PASS(C), final PASS, rc=0. CHANGELOG [6.6.5]
if [ ! -s "$TMP/drv" ]; then
    echo "FAIL: the fncallN extern-C driver compiled to an EMPTY binary"
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
if [ ! -s "$TMP/coexist" ]; then
    echo "FAIL: the foreign-TLS coexistence check compiled to an EMPTY binary"
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

# --- (C) 6.6.5: the SAME stack-protected callees, from NESTED expression positions.
#         An argument slot, a store64 argument, an operator's right operand, and one
#         intermediate cyrius frame. Each of these put an odd number of values on the
#         expression stack before the call; before 6.6.5 that entered sum4/sum7 with
#         rsp 8 bytes off and their movdqa/movaps spills took a #GP.
#         The expected sums are the same arithmetic as (A) — computed here, not read
#         back from the callee — so a callee returning garbage fails on the VALUE as
#         well as on the fault.
cat > "$TMP/nested.cyr" <<EOF
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/fnptr.cyr"
include "lib/dynlib.cyr"
fn snd(a, b): i64 { return b; }
fn thd(a, b, c): i64 { return c; }
fn hop4(f): i64 { var v = fncall4(f, 1, 2, 3, 4); return v; }
alloc_init();
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
var f7 = dynlib_sym(h, "sum7");
if (f4 == 0) { syscall(60, 62); }
if (f7 == 0) { syscall(60, 65); }
var slot[8];
var zero = 0;
# argument 2 of a 2-arg call: one value pending
if (snd(0, fncall4(f4, 1, 2, 3, 4)) != 10) { syscall(60, 70); }
# argument 3 of a 3-arg call: two pending (the aligned case — a control)
if (thd(0, 0, fncall4(f4, 1, 2, 3, 4)) != 10) { syscall(60, 71); }
# store64's second argument
store64(&slot, fncall7(f7, 1, 2, 3, 4, 5, 6, 7));
if (load64(&slot) != 28) { syscall(60, 72); }
# right operand of an operator
if (zero + fncall7(f7, 1, 2, 3, 4, 5, 6, 7) != 28) { syscall(60, 73); }
# through one intermediate cyrius frame, itself called from a nested position
if (snd(0, hop4(f4)) != 10) { syscall(60, 74); }
# a 7-arg extern call nested one level in (nextra x depth parity)
if (snd(0, fncall7(f7, 1, 2, 3, 4, 5, 6, 7)) != 28) { syscall(60, 75); }
syscall(60, 0);
EOF
if ! "$CYCC" < "$TMP/nested.cyr" > "$TMP/nested" 2>"$TMP/nested.err"; then
    echo "FAIL: could not compile the nested-position extern-C driver"
    sed 's/^/  /' "$TMP/nested.err" | head -8
    exit 1
fi
if [ ! -s "$TMP/nested" ]; then
    echo "FAIL(C): the nested-position extern-C driver compiled to an EMPTY binary"
    exit 1
fi
chmod +x "$TMP/nested"
set +e
"$TMP/nested"
rc3=$?
set -e
if [ "$rc3" = "77" ]; then
    echo "SKIP(C): no glibc on host"
    exit 0
fi
if [ "$rc3" = "139" ]; then
    echo "FAIL(C): SIGSEGV — a stack-protected extern-C callee was entered with rsp 8 bytes"
    echo "         off 16-byte alignment from a NESTED expression position (6.6.5 class)"
    exit 1
fi
if [ "$rc3" != "0" ]; then
    echo "FAIL(C): nested-position extern-C exit $rc3 (70=arg2 71=arg3 72=store64 73=operator"
    echo "         74=via a cyrius frame 75=7-arg nested; 60/61=bootstrap/open, 62/65=symbols)"
    exit 1
fi
echo "  PASS(C): the same callees from nested argument / store64 / operator / one-frame positions"

echo "PASS: fncallN into stack-protected extern-C, top-level AND nested + foreign-%fs coexistence (v6.3.26, v6.6.5)"
exit 0
