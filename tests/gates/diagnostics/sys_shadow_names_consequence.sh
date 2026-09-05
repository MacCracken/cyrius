#!/bin/sh
# sys_shadow_names_consequence.sh — v6.5.50. A conflicting `SYS_*` redefinition must say
# what it DOES, not just that it happened.
#
# WHAT THIS PINS. A consumer's own `var SYS_FOO = <x86_64 number>` shadows the stdlib's
# arch-aware definition (lib/syscalls.cyr -> syscalls_x86_64_linux.cyr /
# syscalls_aarch64_linux.cyr). On x86 the two agree and nothing happens. Everywhere else the
# consumer's value WINS and the emitted svc issues A DIFFERENT, VALID SYSCALL — the build
# succeeds and the wrong call is made silently. MEASURED under qemu on the two live instances
# the v6.5.37 sweep found: `sys_umount2` was issuing getpid(2) on every ELF-aarch64 build.
# The only diagnostic was "duplicate symbol ... (last definition wins)", which reads as a
# cosmetic name-collision note. Filed from darshana (2026-08-23).
#
# ⚠ THE NOTE IS DELIBERATELY NOT GATED ON THE TARGET, and that is the whole reason this can
# ship. The general question — "is this number right for this arch?" — needs an x86_64 ->
# aarch64 CORRESPONDENCE TABLE (~350 rows) that does not exist in src/ and whose home is a
# maintainer design call. THIS case needs no table: a CONFLICTING SYS_* redefinition is wrong
# on every target whose numbers differ, and the author of a cross-compiled source cannot know
# which targets those will be. Do not "improve" this by restricting it to the aarch64 fork.
#
# ⚠ AXIS 3 IS THE ONE THAT CAN ROT. On x86_64 the honest repro (`var SYS_IOCTL = 16`) fires
# NOTHING, because 16 IS the x86 number and CHKDUPVAL only warns on a CONFLICT — so an x86-only
# gate would pass while proving nothing about the case that matters. Axis 3 therefore builds
# the aarch64 emitter and feeds it the x86 number for a syscall whose aarch64 native number
# DIFFERS. That is the actual reported defect.
#
# ⚠ NO `set -e`: compiles here exit non-zero as DATA.
#
# ⚠ MUTATING THIS GATE TAKES TWO DIFFERENT MOVES, and neither alone reddens every axis.
# Measured 2026-09-04:
#   * swap `build/cycc` for a pre-fix compiler  -> axis 1 RED, axis 3 still GREEN
#   * revert src/frontend/parse_types.cyr       -> axis 3 RED, axis 1 still GREEN
# Axis 3 BUILDS the aarch64 emitter from the WORKING-TREE source, so an old host compiler
# still picks up the current parse_types.cyr and the axis passes vacuously — the same trap
# CLAUDE.md records for tests/gates/codegen/cx_multi_return.sh. Axis 1 runs the INSTALLED
# build/cycc, so it survives a source revert. If you are proving this gate still bites,
# do BOTH; concluding from one that an axis is broken is the mistake to avoid.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
CC="$ROOT/build/cycc"
FAIL=0

# Axis 1 — a conflicting SYS_* redefinition explains the consequence.
printf 'include "lib/syscalls.cyr"\nvar SYS_IOCTL = 999;\nfn main(): i64 { return 0; }\nvar r = main();\n' > "$D/a.cyr"
"$CC" < "$D/a.cyr" > /dev/null 2>"$D/a.err"
if [ "$(grep -c "names a syscall number" "$D/a.err")" != 1 ]; then
    echo "FAIL: a conflicting SYS_* redefinition did not explain the syscall consequence"; FAIL=1
else echo "  ok: conflicting SYS_* redefinition names the consequence"; fi

# Axis 2 — a NON-SYS conflicting redefinition must NOT get the note (no blanket noise).
printf 'var FOO = 1;\nvar FOO = 2;\nfn main(): i64 { return 0; }\nvar r = main();\n' > "$D/b.cyr"
"$CC" < "$D/b.cyr" > /dev/null 2>"$D/b.err"
if [ "$(grep -c 'duplicate symbol' "$D/b.err")" -lt 1 ]; then
    echo "FAIL: premise — the plain duplicate-symbol warning no longer fires at all"; FAIL=1
elif [ "$(grep -c 'names a syscall number' "$D/b.err")" != 0 ]; then
    echo "FAIL: a non-SYS_ redefinition got the syscall note"; FAIL=1
else echo "  ok: non-SYS_ redefinition keeps the plain warning, no syscall note"; fi

# Axis 3 — ⭐ THE REPORTED DEFECT: the x86 number on the aarch64 fork.
# SYS_UMOUNT2 is 166 on x86_64 and a different native number on aarch64, so a consumer
# writing 166 conflicts THERE and only there.
"$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2>/dev/null
chmod +x "$D/cc_a64"
if [ ! -s "$D/cc_a64" ]; then
    echo "FAIL: premise — could not build the aarch64 emitter"; FAIL=1
else
    printf 'include "lib/syscalls.cyr"\nvar SYS_UMOUNT2 = 166;\nfn main(): i64 { return 0; }\nvar r = main();\n' > "$D/c.cyr"
    "$D/cc_a64" < "$D/c.cyr" > /dev/null 2>"$D/c.err"
    if [ "$(grep -c "duplicate symbol 'SYS_UMOUNT2'" "$D/c.err")" != 1 ]; then
        echo "FAIL: premise — the x86 number for SYS_UMOUNT2 did not conflict on the aarch64 fork"; FAIL=1
    elif [ "$(grep -c 'names a syscall number' "$D/c.err")" != 1 ]; then
        echo "FAIL: the reported case (x86 syscall number on aarch64) got no consequence note"; FAIL=1
    else echo "  ok: x86 syscall number on the aarch64 fork explains the consequence"; fi
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: SYS_* shadowing is still diagnosed as a cosmetic name collision"; exit 1; fi
echo "PASS sys_shadow_names_consequence (SYS_* shadowing names the syscall it will really issue)"
