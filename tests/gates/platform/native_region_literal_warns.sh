#!/bin/sh
# native_region_literal_warns.sh — 6.7.12: a raw syscall literal inside a native-aarch64 region
# that an ESYSXLAT x86-compat row RENUMBERS is warned at compile time, and still translated.
#
# THE DEFECT (filed 2026-10-08, docs/development/issues/2026-10-08-aarch64-native-region-literal-
# translated-silently.md). In a region compiled only for aarch64 (`#ifdef CYRIUS_ARCH_AARCH64`,
# `#ifplat aarch64`, `#ifndef CYRIUS_ARCH_X86`) a raw number reads as the native one — 6.6.12
# silences the "this is x86 <name>" warning there for that reason — but the chain matches NUMBERS:
# `syscall(9, …)` meant as lgetxattr is renumbered to mmap (9 → 222) and `syscall(39, …)` meant as
# umount2 returns a PID (39 → 172 getpid). No warning, a clean build, the wrong call.
#
# THE DECISION (D1, the user, 2026-10-15): WARN ONLY — the literal is still translated, so no
# program changes behaviour. The warning names the number it becomes, what that runs, and the
# spelling that reaches the native call: `1000+N` when the private band has a row for it (derived
# by running the same chain with 1000+N), else that no alias exists.
#
# WHAT IS JUDGED (src/backend/aarch64/emit.cyr `_esx_native_warn`): a single integer-literal token
# as the number, inside a region opened in the call's OWN file. A `SYS_*` / enum constant is not a
# raw literal (the stdlib's own constants renumber by design: SYS_FSYNC = 74 → 82), and a file
# INCLUDED from inside a region is not judged by its includer's region — the stdlib's shared
# syscall files sit inside lib/syscalls.cyr's aarch64 region and deliberately write x86 numbers
# (fd_wait_ready's raw 7, sys_epoll_wait's raw 232), the frame rule
# raw_syscall_literals_routed.sh applies to lib/.
#
#   axis 1  the filed repro VERBATIM: one warning naming 9 → 222 (mmap) and 1009 for native
#           lgetxattr; under qemu-aarch64 it still exits 22 (mmap ran: warn only)
#   axis 2  the 1009 control: silent, exits 0 under qemu (native lgetxattr → -ENOENT)
#   axis 3  syscall(39) in a region names 172 (getpid) and 1039 for native umount2
#   axis 4  the same literal OUTSIDE a region prints no new warning
#   axis 5  a region literal with no ELF row (134, a pass-through) stays silent
#   axis 6  no alias: raw 1 in a region says no 1000+N alias exists for native io_destroy
#   axis 7  an enum constant in a region, and a file included from inside a region, stay silent;
#           a region in the includer AFTER that include still warns (the file stack resumes)
#   axis 8  warn only: the repro's binary is byte-identical to the same source with its region
#           lines blanked (the warning changes nothing that is emitted)
#   axis 9  a stdlib hello (syscalls + alloc + io) builds for aarch64 with zero of these warnings
#           (syscall_xlat_generated.sh axes 2/7/8 hold the CLI and cycc's own aarch64 source to
#           zero `raw syscall` warnings, which covers this text too)
#
# MUTATION LEDGER (measured 6.7.12 on the emitter, restored after each; the gate stops at its
# first red axis, so a later one is measured separately):
#   (a) no warning (`_esx_native_warn` returns at entry)          -> axis 1 FAILS (0 warnings)
#   (b) the region test is PP_A64_NATIVE_AT (the includer's region
#       counts)                                                     -> axis 7 FAILS (inc/arm.cyr
#                                                                      warned); axis 9 too: the
#                                                                      stdlib hello prints 2
#                                                                      (fd_wait_ready's 7,
#                                                                      sys_epoll_wait's 232)
#   (c) the raw-literal test dropped (any folded number)            -> axis 7 FAILS (the enum
#                                                                      constant warned)
#   (d) the alias derived as "1000+N fits the cmp" instead of by
#       running the chain                                           -> axis 6 FAILS (write 1001)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
fail() { echo "FAIL native_region_literal_warns: $1" >&2; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL native_region_literal_warns: mktemp -d"; exit 1; }
trap 'rm -rf "$T"' EXIT

REPRO="$ROOT/docs/development/issues/repros/2026-10-08-aarch64-native-region-literal-translated-silently.cyr"
[ -f "$REPRO" ] || fail "the filed repro is missing: $REPRO"

rc=0; (cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$T/cca" 2> "$T/cca.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/cca" ] || fail "cross-building cycc_aarch64 from src failed (rc $rc): $(head -3 "$T/cca.err")"
chmod +x "$T/cca"

QEMU=0
if command -v qemu-aarch64 >/dev/null 2>&1; then QEMU=1; fi

# _cc <name> : compile $T/<name>.cyr from $T (so a relative include resolves there); rc 0 and a
# non-empty binary are required — a compile that failed prints no warning either.
_cc() {
    rc=0; (cd "$T" && "$T/cca" < "$1.cyr" > "$1.bin" 2> "$1.err") || rc=$?
    [ "$rc" = 0 ] && [ -s "$T/$1.bin" ] || fail "$1: the probe did not compile (rc $rc): $(head -3 "$T/$1.err")"
    chmod +x "$T/$1.bin"
}
_nw() { grep -c 'inside a native-aarch64 region' "$T/$1.err" || true; }
_run() { rc=0; (cd "$T" && timeout 30 qemu-aarch64 "./$1.bin" > /dev/null 2>&1) || rc=$?; echo "$rc"; }

# ── axis 1: the filed repro, verbatim ───────────────────────────────────────────────
cp "$REPRO" "$T/repro.cyr"
_cc repro
[ "$(_nw repro)" = 1 ] || fail "axis 1: the filed repro printed $(_nw repro) native-region warnings, want 1: $(cat "$T/repro.err")"
grep -q 'raw syscall 9 inside a native-aarch64 region is renumbered → 222 (mmap); write 1009 for native lgetxattr' "$T/repro.err" \
  || fail "axis 1: the warning does not name 9 → 222 (mmap) and 1009 for native lgetxattr: $(cat "$T/repro.err")"
grep -q '^warning:<source>:10:' "$T/repro.err" || fail "axis 1: the warning does not point at the call's line (10): $(cat "$T/repro.err")"
if [ "$QEMU" = 1 ]; then
    r1=$(_run repro)
    [ "$r1" = 22 ] || fail "axis 1: the repro exits $r1 under qemu, want 22 — warn only: the literal must still be translated (mmap)"
    echo "  axis 1: the filed repro warns (9 → 222 mmap; write 1009 for native lgetxattr) and still exits 22 under qemu"
else
    echo "  axis 1: the filed repro warns (9 → 222 mmap; write 1009) — its qemu run SKIPPED: qemu-aarch64 absent"
fi

# ── axis 2: the 1009 control ────────────────────────────────────────────────────────
sed 's/syscall(9, /syscall(1009, /' "$REPRO" > "$T/ctl.cyr"
grep -q 'syscall(1009, ' "$T/ctl.cyr" || fail "axis 2: the control's sed did not apply to the repro"
_cc ctl
[ "$(_nw ctl)" = 0 ] || fail "axis 2: the 1009 alias spelling warned: $(cat "$T/ctl.err")"
if [ "$QEMU" = 1 ]; then
    r2=$(_run ctl)
    [ "$r2" = 0 ] || fail "axis 2: the 1009 control exits $r2 under qemu, want 0 (native lgetxattr → -ENOENT)"
    echo "  axis 2: the 1009 control is silent and exits 0 under qemu"
else
    echo "  axis 2: the 1009 control is silent — its qemu run SKIPPED: qemu-aarch64 absent"
fi

# ── axis 3: 39 names 1039 ───────────────────────────────────────────────────────────
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(39, "/nonexistent", 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/r39.cyr"
_cc r39
grep -q 'raw syscall 39 inside a native-aarch64 region is renumbered → 172 (getpid); write 1039 for native umount2' "$T/r39.err" \
  || fail "axis 3: syscall(39) in a region does not name 172 (getpid) and 1039: $(cat "$T/r39.err")"
echo "  axis 3: syscall(39) in a region names 172 (getpid) and 1039 for native umount2"

# ── axis 4: the same literal outside a region ───────────────────────────────────────
printf '%s\n' 'fn f(): i64 { return syscall(9, 0, 4096, 3, 0x22, 0 - 1, 0); }' 'var x = f();' 'syscall(60, 0);' > "$T/out.cyr"
_cc out
[ "$(_nw out)" = 0 ] || fail "axis 4: syscall(9) OUTSIDE a region warned: $(cat "$T/out.err")"
echo "  axis 4: syscall(9) outside a region prints no new warning"

# ── axis 5: no ELF row → silent ─────────────────────────────────────────────────────
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(134, 0, 0, 0, 8);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/r134.cyr"
_cc r134
[ "$(_nw r134)" = 0 ] || fail "axis 5: a region literal with no ELF row (134) warned: $(cat "$T/r134.err")"
echo "  axis 5: a region literal no row renumbers (134) stays silent"

# ── axis 6: no alias exists ─────────────────────────────────────────────────────────
printf '%s\n' 'fn f(): i64 {' '    var r = 0;' '#ifplat aarch64' '    r = syscall(1, 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/noal.cyr"
_cc noal
grep -q 'raw syscall 1 inside a native-aarch64 region is renumbered → 64 (write); no 1000+N alias exists for native io_destroy (the chain has no 1001 row)' "$T/noal.err" \
  || fail "axis 6: raw 1 in an #ifplat aarch64 region does not say no 1000+N alias exists: $(cat "$T/noal.err")"
echo "  axis 6: raw 1 in an #ifplat region: no 1000+N alias exists for native io_destroy"

# ── axis 7: not a raw literal, or not this file's region ────────────────────────────
printf '%s\n' 'enum MyNr { MY_LGX = 9; }' 'fn f(): i64 {' '    var r = 0;' '#ifdef CYRIUS_ARCH_AARCH64' '    r = syscall(MY_LGX, "/x", "user.x", 0, 0);' '#endif' '    return r;' '}' 'var x = f();' 'syscall(60, 0);' > "$T/en.cyr"
_cc en
[ "$(_nw en)" = 0 ] || fail "axis 7: an enum-constant number in a region warned (not a raw literal): $(cat "$T/en.err")"
mkdir -p "$T/inc"
printf '%s\n' 'fn armf(): i64 { return syscall(9, "/x", "user.x", 0, 0); }' > "$T/inc/arm.cyr"
printf '%s\n' '#ifdef CYRIUS_ARCH_AARCH64' 'include "inc/arm.cyr"' '#endif' 'fn g(): i64 {' '#ifndef CYRIUS_ARCH_X86' '    return syscall(39, 0, 0);' '#endif' '    return 0;' '}' 'var x = g();' 'syscall(60, 0);' > "$T/incl.cyr"
_cc incl
[ "$(_nw incl)" = 1 ] || fail "axis 7: the include probe printed $(_nw incl) warnings, want 1 (the includer's own region only): $(cat "$T/incl.err")"
grep -q '^warning:<source>:6:.*raw syscall 39 ' "$T/incl.err" || fail "axis 7: the includer's region after the include did not warn on its raw 39 (the file stack did not resume): $(cat "$T/incl.err")"
grep -q 'inc/arm.cyr' "$T/incl.err" && fail "axis 7: a file included from inside a region was judged by its includer's region: $(cat "$T/incl.err")"
echo "  axis 7: an enum constant and an included file stay silent; the includer's own region after the include warns"

# ── axis 8: warn only — nothing emitted changes ─────────────────────────────────────
sed 's/^#ifdef CYRIUS_ARCH_AARCH64$//; s/^#endif$//' "$REPRO" > "$T/flat.cyr"
[ "$(wc -l < "$T/flat.cyr")" = "$(wc -l < "$REPRO")" ] || fail "axis 8: blanking the region lines changed the line count"
_cc flat
[ "$(_nw flat)" = 0 ] || fail "axis 8: the region-free twin warned: $(cat "$T/flat.err")"
cmp -s "$T/repro.bin" "$T/flat.bin" || fail "axis 8: the repro's binary differs from its region-free twin — the warning changed what is emitted"
echo "  axis 8: the repro's binary is byte-identical to its region-free twin (warn only)"

# ── axis 9: the stdlib stays silent ─────────────────────────────────────────────────
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/alloc.cyr"' 'include "lib/io.cyr"' 'fn main(): i64 { return 0; }' 'var r = main();' 'syscall(60, r);' > "$T/hello.cyr"
rc=0; (cd "$ROOT" && "$T/cca" < "$T/hello.cyr" > "$T/hello.bin" 2> "$T/hello.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/hello.bin" ] || fail "axis 9: the stdlib hello did not build for aarch64 (rc $rc): $(head -3 "$T/hello.err")"
[ "$(_nw hello)" = 0 ] || fail "axis 9: the stdlib hello prints native-region warnings — a false positive on lib/: $(grep 'native-aarch64 region' "$T/hello.err" | head -3)"
echo "  axis 9: a stdlib hello (syscalls + alloc + io) builds for aarch64 with zero native-region warnings"

echo "PASS native_region_literal_warns (a raw region literal a compat row renumbers is warned, with its 1000+N spelling or none; still translated; constants, included files and the stdlib stay silent)"
