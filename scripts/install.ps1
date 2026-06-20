# install.ps1 - native Windows installer for the Cyrius toolchain (v6.0.85).
#
# The POSIX install.sh needs WSL/git-bash; this is the native PowerShell
# equivalent so Windows users get a working toolchain with no Unix layer:
#
#   %USERPROFILE%\.cyrius\
#     bin\                 active-version binaries (on PATH): cycc.exe, cyrius.exe, ...
#     lib\                 active-version stdlib
#     versions\<v>\bin     version-specific binaries
#     versions\<v>\lib     version-specific stdlib
#     current              active version
#
# Windows has no ring-3 symlinks by default, so the active version is a COPY of
# versions\<v>\* into bin\/lib\ (install.sh symlinks on POSIX). The cyrius
# wrapper resolves cycc at <home>\bin\cycc.exe (cbt/core.cyr; the .exe suffix +
# the GetEnvironmentVariableA env-read were added v6.0.85). Run it from a
# tarball or a pre-extracted staging dir:
#
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Tarball cyrius-<v>-x86_64-windows.tar.gz
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Stage   <extracted-dir>
#
# Env: CYRIUS_HOME overrides the install root (default %USERPROFILE%\.cyrius).
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads scripts as the
# system ANSI codepage, so a UTF-8 em-dash breaks the parser.
param(
    [string]$Tarball = "",
    [string]$Stage   = "",
    [string]$Sha256  = "",
    [switch]$NoPath
)
$ErrorActionPreference = "Stop"

$CyriusHome = if ($env:CYRIUS_HOME) { $env:CYRIUS_HOME } else { Join-Path $env:USERPROFILE ".cyrius" }

# Resolve the staging dir (an extracted "cyrius-<v>-x86_64-windows" tree).
if (-not $Stage) {
    if (-not $Tarball) { throw "provide -Tarball <path.tar.gz> or -Stage <dir>" }
    if (-not (Test-Path $Tarball)) { throw "tarball not found: $Tarball" }

    # CVE-21 (v6.2.30): verify the tarball checksum fail-closed before extract.
    # Pre-fix install.ps1 had NO hash check. Accept an explicit -Sha256 <hex>,
    # else a "<tarball>.sha256" sidecar (the release publishes one next to every
    # artifact; sha256sum format is "<hex>  <name>" so take the first token).
    # Refuse to extract an unverified tarball.
    $expected = $Sha256
    if (-not $expected) {
        $sidecar = "$Tarball.sha256"
        if (Test-Path $sidecar) {
            $expected = ((Get-Content $sidecar -Raw).Trim() -split '\s+')[0]
        }
    }
    if (-not $expected) {
        throw "no checksum for $Tarball (pass -Sha256 <hex> or place $Tarball.sha256 beside it) - refusing to install unverified tarball"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Tarball).Hash
    if ($actual -ine $expected) {
        throw "checksum mismatch for $Tarball (expected $expected, got $actual) - aborting"
    }
    Write-Host "checksum verified"

    # CVE-13 (v6.2.31): if a trusted cyrsign.exe is available (a prior install on
    # PATH or in <home>\bin) AND a signed SHA256SUMS(.sig) sits next to the
    # tarball, verify the sovereign Ed25519 signature and that this tarball
    # matches the SIGNED manifest hash. Fail-closed; skip if absent (the SHA256
    # check above is the floor). Keep ASCII-only (PS 5.1 ANSI codepage).
    $pub = "adbde6b11ccf8d86dc760387fa7f4dfbe3942fa318e459fb6e62d1536e254008"
    $sums = Join-Path (Split-Path -Parent (Resolve-Path $Tarball)) "SHA256SUMS"
    $sumsSig = "$sums.sig"
    $cyrsign = $null
    $cmd = Get-Command cyrsign.exe -ErrorAction SilentlyContinue
    if ($cmd) { $cyrsign = $cmd.Source }
    elseif (Test-Path (Join-Path $CyriusHome "bin\cyrsign.exe")) { $cyrsign = Join-Path $CyriusHome "bin\cyrsign.exe" }
    if ($cyrsign -and (Test-Path $sums) -and (Test-Path $sumsSig)) {
        $pubfile = Join-Path $env:TEMP ("cyrius-release-" + [System.Guid]::NewGuid().ToString("N") + ".pub")
        Set-Content -Path $pubfile -Value $pub -NoNewline
        & $cyrsign verify $sums $sumsSig $pubfile | Out-Null
        $sigok = ($LASTEXITCODE -eq 0)
        Remove-Item $pubfile -ErrorAction SilentlyContinue
        if (-not $sigok) { throw "release signature verification FAILED - refusing" }
        $tname = Split-Path -Leaf $Tarball
        $line = (Get-Content $sums | Where-Object { $_ -match ("\s" + [regex]::Escape($tname) + "$") } | Select-Object -First 1)
        if (-not $line) { throw "tarball $tname not in signed SHA256SUMS - refusing" }
        $signedHash = ($line -split '\s+')[0]
        if ($actual -ine $signedHash) { throw "tarball hash != signed manifest hash - refusing" }
        Write-Host "signature verified (Ed25519)"
    } else {
        Write-Host "signature check skipped (no prior cyrsign.exe / unsigned tarball)"
    }

    $tmp = Join-Path $env:TEMP ("cyrius-install-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    # tar.exe ships in System32 on Windows 10 1803+; the release tarball is .tar.gz.
    & tar.exe -xzf $Tarball -C $tmp
    if ($LASTEXITCODE -ne 0) { throw "tar extraction failed ($LASTEXITCODE)" }
    $Stage = (Get-ChildItem -Directory $tmp | Select-Object -First 1).FullName
}
if (-not (Test-Path (Join-Path $Stage "VERSION"))) { throw "no VERSION in staging dir: $Stage" }

$Ver    = (Get-Content (Join-Path $Stage "VERSION") -Raw).Trim()
$VerDir = Join-Path $CyriusHome "versions\$Ver"

foreach ($d in @("$VerDir\bin", "$VerDir\lib", "$CyriusHome\bin", "$CyriusHome\lib")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# Version-specific tree.
Copy-Item "$Stage\bin\*" "$VerDir\bin\" -Force -Recurse
Copy-Item "$Stage\lib\*" "$VerDir\lib\" -Force -Recurse
# Active version: copy into <home>\bin + <home>\lib (no symlinks on Windows).
Copy-Item "$VerDir\bin\*" "$CyriusHome\bin\" -Force -Recurse
Copy-Item "$VerDir\lib\*" "$CyriusHome\lib\" -Force -Recurse
Set-Content -Path (Join-Path $CyriusHome "current") -Value $Ver -NoNewline

# Refuse to "succeed" with no compiler (the install pillar guard): a platform is
# not supported if its installer yields no working toolchain.
if (-not (Test-Path (Join-Path $CyriusHome "bin\cycc.exe"))) {
    throw "install produced no cycc.exe - refusing (no toolchain == platform not supported)"
}

# Put <home>\bin on the User PATH (idempotent).
if (-not $NoPath) {
    $binPath  = Join-Path $CyriusHome "bin"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { $userPath = "" }
    if (($userPath -split ';') -notcontains $binPath) {
        $newPath = if ($userPath) { "$binPath;$userPath" } else { $binPath }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added $binPath to your User PATH (restart the shell to pick it up)."
    }
}

Write-Host "Cyrius $Ver installed to $CyriusHome"
Write-Host "  cycc.exe   : $CyriusHome\bin\cycc.exe"
Write-Host "  cyrius.exe : $CyriusHome\bin\cyrius.exe"
