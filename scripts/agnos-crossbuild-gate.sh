#!/bin/sh
# AGNOS cross-build gate (v6.0.87 — the arc-.32 gate). The `CYRIUS_TARGET_AGNOS`
# target landed .48-.49 + boot-to-prompt .55-.56, but nothing GUARDS agnos
# codegen from silent rot — the exact "found by ports" class that rotted the
# macOS port for 9 minors. This compiles a representative agnos-target program
# (+ agnoshi, the gating consumer, if checked out) and asserts a valid agnos-ABI
# ELF. Runs in CI (ci.yml) and standalone.
#
#   sh scripts/agnos-crossbuild-gate.sh
#
# Exit 0 = pass. A missing agnoshi checkout is FLAGGED (not silently skipped,
# per feedback_flag_missing_repos_dont_skip) but does not fail the gate — the
# always-present in-tree probe is the hard gate. Set CYRIUS_AGNOSHI_DIR to point
# at a non-default agnoshi checkout.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }
[ -x build/cyrius ] || { echo "ERROR: build/cyrius missing"; exit 1; }

# A valid agnos ring-3 binary is a statically-linked x86-64 ELF (the agnos
# target emits a flat static ELF over the agnos syscall ABI; no interpreter).
assert_agnos_elf() {
    f="$1"
    [ -f "$f" ] || { echo "FAIL: $f not produced"; exit 1; }
    magic=$(xxd -l4 -p "$f" 2>/dev/null)
    [ "$magic" = "7f454c46" ] || { echo "FAIL: $f not an ELF (magic=$magic)"; exit 1; }
    file "$f" | grep -q "x86-64" || { echo "FAIL: $f not x86-64"; exit 1; }
    file "$f" | grep -q "statically linked" || { echo "FAIL: $f not statically linked"; exit 1; }
}

# 1. In-tree probe — exercises the agnos peer surface that's bitten us before:
#    args (entry rsp capture), getenv (envp walk, v6.0.87), alloc, syscalls.
cat > /tmp/_agnos_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/args.cyr"
fn main(): i64 {
    var h = getenv("HOME");          # envp walk on agnos (1.43.2 ABI §4.6)
    if (h == 0) { return 1; }
    var n = argc();                   # entry init-rsp capture
    if (n < 1) { return 2; }
    return load8(h);
}
CYR
build/cyrius build --agnos /tmp/_agnos_gate.cyr /tmp/_agnos_gate.out >/dev/null 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS probe did not compile (agnos codegen/peer regression)"; exit 1; }
assert_agnos_elf /tmp/_agnos_gate.out
echo "PASS: CYRIUS_TARGET_AGNOS probe (args + getenv envp) -> valid agnos ELF"

# 2. agnoshi — the gating consumer (agnsh is the first agnos userland program).
AGNOSHI="${CYRIUS_AGNOSHI_DIR:-$ROOT/../agnoshi}"
if [ -f "$AGNOSHI/src/agnsh.cyr" ]; then
    ( cd "$AGNOSHI" && CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_NO_WARN_SHADOW_LIB=1 \
        "$ROOT/build/cyrius" build --agnos src/agnsh.cyr /tmp/_agnsh_gate.out >/dev/null 2>&1 ) \
        || { echo "FAIL: agnoshi did not cross-build for CYRIUS_TARGET_AGNOS"; exit 1; }
    assert_agnos_elf /tmp/_agnsh_gate.out
    echo "PASS: agnoshi (agnsh) -> valid agnos ELF"
else
    echo "FLAG: agnoshi checkout not at $AGNOSHI (set CYRIUS_AGNOSHI_DIR) — consumer cross-build NOT verified"
fi
