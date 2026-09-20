#!/bin/sh
# cass install pillar gate (v6.0.85) — the Windows analog of the ecb-install arm
# of `cyrius audit`. Builds the Windows tarball via the single-source-of-truth
# build-windows-tarball.sh, ships it + install.ps1 + the cass-side gate to cass,
# runs the REAL install.ps1, and asserts `cyrius build` of fn main(){return 42}
# yields exit 42. Catches a tarball missing cyrius.exe, a broken installer, or a
# non-runnable build — the "found by ports" class, one platform over from macOS.
#
# Exit 0 = pass, 1 = broken (PUBLISH BLOCKED), 3 = unreachable (also blocks).
# The default cass ssh shell is PowerShell, so the remote command is powershell.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
V=$(tr -d '[:space:]' < VERSION)
TB="cyrius-${V}-x86_64-windows.tar.gz"

[ -x build/cycc ] || { echo "ERROR: build/cycc missing"; exit 1; }

# ── v6.6.6: PER-RUN STAGING, LOCAL AND REMOTE (same fix as cross-os-selfhost.sh) ──
# This staged at the fixed /tmp/_co_windist + /tmp/_co_tw.cyr and dropped four fixed
# names straight into cass's %USERPROFILE% (plus a fixed _coiw home inside the .ps1),
# so two runs overwrote each other's tarball, test source and install sandbox — and a
# second run could install a tarball the first was still unpacking. CHANGELOG [6.6.6]
T=$(mktemp -d "${TMPDIR:-/tmp}/cyrius-cig.XXXXXX") && [ -d "$T" ] || {
    echo "ERROR: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
RUNID="$$_$(basename "$T" | sed 's/.*\.//' | tr -cd 'A-Za-z0-9')"
RD="_cig_$RUNID"
_cig_cleanup() {
    _crc=$?
    rm -rf "$T"
    if [ "$_crc" = 0 ]; then
        ssh -o ConnectTimeout=20 -o BatchMode=yes cass \
            "cmd /c \"rmdir /s /q %USERPROFILE%\\$RD\"" >/dev/null 2>&1 || true
    else
        echo "  (remote staging kept on cass for inspection: %USERPROFILE%\\$RD)"
    fi
    exit "$_crc"
}
trap _cig_cleanup EXIT

sh scripts/build-windows-tarball.sh "$T/windist" >/dev/null 2>&1
printf 'fn main(): i64 { return 42; }' > "$T/tw.cyr"

# Reachability — distinct exit 3 so the audit says "couldn't verify" (still blocks).
ssh -o ConnectTimeout=15 -o BatchMode=yes cass 'cmd /c "echo ok"' >/dev/null 2>&1 \
    || { echo "UNREACHABLE: cass"; exit 3; }

ssh -o ConnectTimeout=20 -o BatchMode=yes cass "cmd /c \"mkdir %USERPROFILE%\\$RD\"" >/dev/null 2>&1 \
    || { echo "UNREACHABLE: cass (could not create the staging dir)"; exit 3; }
scp -q scripts/install.ps1 scripts/cass-install-gate.ps1 "$T/tw.cyr" \
    "$T/windist/${TB}" "cass:$RD/" \
    || { echo "UNREACHABLE: cass (scp failed)"; exit 3; }

# The .ps1 exit code propagates back through ssh. Full Windows paths (the home
# is %USERPROFILE% = C:\Users\<user>); cass's user is Administrator.
_UP="C:\\Users\\Administrator\\$RD"
ssh cass "powershell -ExecutionPolicy Bypass -File ${_UP}\\cass-install-gate.ps1 -RunDir ${_UP} -Tarball ${_UP}\\${TB} -Test ${_UP}\\tw.cyr"
