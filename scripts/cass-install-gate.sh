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
sh scripts/build-windows-tarball.sh /tmp/_co_windist >/dev/null 2>&1
printf 'fn main(): i64 { return 42; }' > /tmp/_co_tw.cyr

# Reachability — distinct exit 3 so the audit says "couldn't verify" (still blocks).
ssh -o ConnectTimeout=15 -o BatchMode=yes cass 'cmd /c "echo ok"' >/dev/null 2>&1 \
    || { echo "UNREACHABLE: cass"; exit 3; }

scp -q scripts/install.ps1 scripts/cass-install-gate.ps1 /tmp/_co_tw.cyr \
    "/tmp/_co_windist/${TB}" cass:~/ \
    || { echo "UNREACHABLE: cass (scp failed)"; exit 3; }

# The .ps1 exit code propagates back through ssh. Full Windows paths (the home
# is %USERPROFILE% = C:\Users\<user>); cass's user is Administrator.
ssh cass "powershell -ExecutionPolicy Bypass -File C:\\Users\\Administrator\\cass-install-gate.ps1 -Tarball C:\\Users\\Administrator\\${TB} -Test C:\\Users\\Administrator\\_co_tw.cyr"
