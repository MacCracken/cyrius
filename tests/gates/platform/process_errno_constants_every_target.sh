#!/bin/sh
# process_errno_constants_every_target.sh — 6.6.10. `PROC_ECHILD` and `PROC_ETIMEDOUT` are
# defined by lib/process.cyr on EVERY target it builds for, not only in its POSIX block.
#
# THE BUG. 6.6.7 added both errno names to the POSIX block of lib/process.cyr. The Windows peer
# (lib/process_win.cyr) spelled them as the literals 110 / 10 and the agnos peer
# (lib/process_agnos.cyr) copied PROC_ECHILD only. An undefined VARIABLE is a hard error in
# cyrius whatever the reachability, so a portable caller that compared a Result against the
# names — `if (r == PROC_ETIMEDOUT)` — failed to COMPILE for PE (both names) and agnos
# (PROC_ETIMEDOUT). Measured at the 6.6.10 premise check: native rc 0, CYRIUS_MACHO=1 rc 0,
# CYRIUS_TARGET_WIN=1 rc 1, CYRIUS_TARGET_AGNOS=1 rc 1. CHANGELOG [6.6.10]
#
# THE ROWS: one probe that includes ONLY lib/process.cyr (the module names its own definers
# since 6.6.9) and reads both names, compiled for x86_64 Linux, aarch64 Linux, x86_64 macOS,
# arm64 macOS, Windows PE and agnos. The x86_64 Linux build also RUNS, and must exit
# 10 + 110 = 120 — the same values on every peer, so it is one number to agree on.
#
# MUTATION (6.6.10, run): delete `var PROC_ETIMEDOUT` from process_win.cyr → the PE row fails
# with "undefined variable 'PROC_ETIMEDOUT'"; delete it from process_agnos.cyr → the agnos row
# fails the same way. Every other row stays green.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL process_errno_constants_every_target: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL process_errno_constants_every_target: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0
fail=0
pass=0

cat > "$T/p.cyr" <<'EOF'
include "lib/process.cyr"
var a = PROC_ECHILD;
var b = PROC_ETIMEDOUT;
syscall(SYS_EXIT, a + b);
EOF

# The aarch64 compiler, built from THIS tree (the tracked cross-bins can be stale).
"$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/eb" || { echo "FAIL process_errno_constants_every_target: could not build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/cc_a64"

# row <label> <compiler> [VAR=1] — the probe must compile, with no undefined PROC_* name.
row() {
    _lbl=$1; _cc=$2; shift 2
    if [ $# -gt 0 ]; then env "$@" "$_cc" < "$T/p.cyr" > "$T/o.$_lbl" 2> "$T/e.$_lbl"; _rc=$?
    else "$_cc" < "$T/p.cyr" > "$T/o.$_lbl" 2> "$T/e.$_lbl"; _rc=$?; fi
    _und=$(grep -c "undefined variable 'PROC_" "$T/e.$_lbl" || true)
    if [ "$_rc" = 0 ] && [ "$_und" = 0 ]; then
        echo "  ok: $_lbl — compiles"; pass=$((pass + 1))
    else
        echo "  FAIL: $_lbl — rc $_rc, $(grep -m1 -E 'error|undefined' "$T/e.$_lbl")"; fail=$((fail + 1))
    fi
}

row linux-x86_64 "$CC"
row linux-aarch64 "$T/cc_a64"
row macos-x86_64 "$CC" CYRIUS_MACHO=1
row macos-arm64 "$T/cc_a64" CYRIUS_MACHO_ARM=1
row windows-pe "$CC" CYRIUS_TARGET_WIN=1
row agnos "$CC" CYRIUS_TARGET_AGNOS=1

chmod +x "$T/o.linux-x86_64"
"$T/o.linux-x86_64"; rc=$?
if [ "$rc" = 120 ]; then echo "  ok: the values are ECHILD 10 + ETIMEDOUT 110 (exit 120)"; pass=$((pass + 1))
else echo "  FAIL: expected exit 120 (10 + 110), got $rc"; fail=$((fail + 1)); fi

if [ "$pass" -lt 7 ] || [ "$fail" -ne 0 ]; then
    echo "FAIL process_errno_constants_every_target: $fail failed, $pass passed"
    exit 1
fi
echo "PASS process_errno_constants_every_target ($pass rows)"
exit 0
