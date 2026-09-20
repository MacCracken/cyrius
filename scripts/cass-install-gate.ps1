# cass-install-gate.ps1 - runs ON cass (Windows). The install-pillar half of
# `cyrius audit` for Windows (v6.0.85): run the REAL install.ps1 into a scratch
# CYRIUS_HOME, then `cyrius build` a return-42 program and assert exit 42 -
# catching a tarball missing cyrius.exe, a broken installer, or a non-runnable
# build output. The Windows analog of the ecb install gate. Exit 0 = pass.
# ASCII-only (Windows PowerShell 5.1 reads scripts as the system codepage).
# v6.6.6: -RunDir is the caller's per-run staging directory. install.ps1, the scratch
# CYRIUS_HOME and the build output all used FIXED names under %USERPROFILE% (_coiw,
# _co_tw.exe), so two runs of this gate clobbered each other's install sandbox. It
# defaults to %USERPROFILE% so an older caller still works. CHANGELOG [6.6.6]
param([string]$Tarball, [string]$Test, [string]$RunDir = "")
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($RunDir)) { $RunDir = $env:USERPROFILE }

$env:CYRIUS_HOME = Join-Path $RunDir "iw"
Remove-Item -Recurse -Force $env:CYRIUS_HOME -ErrorAction SilentlyContinue

& powershell -ExecutionPolicy Bypass -File (Join-Path $RunDir "install.ps1") -Tarball $Tarball -NoPath
if ($LASTEXITCODE -ne 0) { Write-Host "INSTALL FAIL ($LASTEXITCODE)"; exit 1 }

$out = Join-Path $RunDir "tw.exe"
Remove-Item $out -ErrorAction SilentlyContinue
& (Join-Path $env:CYRIUS_HOME "bin\cyrius.exe") build $Test $out
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAIL ($LASTEXITCODE)"; exit 1 }
if (-not (Test-Path $out)) { Write-Host "NO OUTPUT"; exit 1 }

& $out
$rc = $LASTEXITCODE
if ($rc -ne 42) { Write-Host "RUN exit $rc != 42"; exit 1 }
Write-Host "OK"
exit 0
