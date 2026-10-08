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
    [switch]$NoPath,
    [switch]$AllowUnsigned
)
$ErrorActionPreference = "Stop"

$CyriusHome = if ($env:CYRIUS_HOME) { $env:CYRIUS_HOME } else { Join-Path $env:USERPROFILE ".cyrius" }

# 6.6.20 (SEC-07): the FIRST signed release. Every release from 6.2.31 on publishes SHA256SUMS +
# SHA256SUMS.sig (release.yml refuses to publish one without, since that tag - the release-signing hardening item). So with a
# trusted cyrsign.exe on this machine, a tarball that arrives WITHOUT the signed pair beside it is
# refused: the pair was stripped (or never downloaded). This installer used to print "signature
# check skipped" and install it. Unlike install.sh / ci.sh there is NO pre-signing carve-out here:
# theirs keys on a version the OPERATOR typed (CYRIUS_VERSION / argv), and the only version this
# installer sees is the tarball's file name and the VERSION file inside it, both of which come from
# the download (a server can suggest the name). Windows pre-signing releases are 6.0.85-6.2.30, so
# a downgrade to one with a verifier present passes -AllowUnsigned. Same constant as
# scripts/install.sh and scripts/ci.sh; tests/gates/toolchain/install_signature_required.sh holds
# the three in step, and scripts/cass-install-gate.ps1 runs the refusals on real Windows.
# -AllowUnsigned (or CYRIUS_ALLOW_UNSIGNED=1) is the explicit override. CHANGELOG [6.6.20]
$FirstSignedRelease = "6.2.31"
$tarVer = $null

# Resolve the staging dir (an extracted "cyrius-<v>-x86_64-windows" tree).
if (-not $Stage) {
    if (-not $Tarball) { throw "provide -Tarball <path.tar.gz> or -Stage <dir>" }
    if (-not (Test-Path $Tarball)) { throw "tarball not found: $Tarball" }

    # the release-integrity hardening item (v6.2.30): verify the tarball checksum fail-closed before extract.
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

    # the release-signing hardening item (v6.2.31): if a trusted cyrsign.exe is available (a prior install on
    # PATH or in <home>\bin) AND a signed SHA256SUMS(.sig) sits next to the
    # tarball, verify the sovereign Ed25519 signature and that this tarball
    # matches the SIGNED manifest hash. Fail-closed; skip if absent (the SHA256
    # check above is the floor). Keep ASCII-only (PS 5.1 ANSI codepage).
    $pub = "adbde6b11ccf8d86dc760387fa7f4dfbe3942fa318e459fb6e62d1536e254008"
    $sums = Join-Path (Split-Path -Parent (Resolve-Path $Tarball)) "SHA256SUMS"
    $sumsSig = "$sums.sig"
    # The release the tarball NAMES: cyrius-<N.N.N>-<arch>-windows.tar.gz. It buys nothing (see
    # $FirstSignedRelease above), but it is held against the VERSION file after extraction, so the
    # name the signed SHA256SUMS line was matched on and the version installed are one release.
    if ((Split-Path -Leaf $Tarball) -match '^cyrius-((?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8}))-') {
        $tarVer = $Matches[1]
    }
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
    } elseif ($cyrsign) {
        if ($tarVer -and ([version]$tarVer -lt [version]$FirstSignedRelease)) {
            $why = "a trusted cyrsign.exe is present ($cyrsign) and no SHA256SUMS + SHA256SUMS.sig sits beside $Tarball, whose name says $tarVer - a release before signing began ($FirstSignedRelease), but that name and the VERSION file inside both come from the download, so install.ps1 cannot tell it from a renamed signed-era tarball"
        } else {
            $named = if ($tarVer) { $tarVer } else { "(no version in the name)" }
            $why = "every Cyrius release since $FirstSignedRelease is signed and a trusted cyrsign.exe is present ($cyrsign), but no SHA256SUMS + SHA256SUMS.sig sits beside $Tarball (release $named)"
        }
        if ($AllowUnsigned -or ($env:CYRIUS_ALLOW_UNSIGNED -eq "1")) {
            Write-Host "WARNING: signature required but absent: $why - allowed via -AllowUnsigned / CYRIUS_ALLOW_UNSIGNED=1 (NOT recommended)"
        } else {
            throw "refusing UNSIGNED tarball: $why. Download SHA256SUMS and SHA256SUMS.sig from the same release page into the tarball's directory, or pass -AllowUnsigned only for a tarball you built yourself or a pre-signing release you chose."
        }
    } else {
        Write-Host "signature check skipped (no prior cyrsign.exe; integrity is the SHA256 above)"
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
# 6.6.20 (SEC-07): the version the tarball's NAME carries decided whether its signature could be
# skipped, so the tree it unpacked must BE that version.
if ($tarVer -and ($Ver -ne $tarVer)) {
    throw "tarball $(Split-Path -Leaf $Tarball) names release $tarVer but its VERSION file says $Ver - refusing"
}
$VerDir = Join-Path $CyriusHome "versions\$Ver"

foreach ($d in @("$VerDir\bin", "$VerDir\lib", "$CyriusHome\bin", "$CyriusHome\lib")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# 6.6.20 (SEC-07): a bin copy RETRIES a sharing violation. The verified upgrade runs the installed
# <home>\bin\cyrsign.exe and then overwrites that same file, and Windows can hold an image that
# has just exited for a moment: measured on cass, 2 of 27 verified upgrades died at the active copy
# with "cyrsign.exe ... is being used by another process" (old and new installer alike), leaving
# <home>\bin half old, half new; with the retry, 0 of 25, and an upgrade run while another bin file
# was held open retried 17 times and finished where the bare Copy-Item died. Before the SEC-07 floor
# an upgrade with no SHA256SUMS beside it never ran the verifier; now every upgrade with one present
# does. Bounded (40 x 250 ms): a lock that does not clear is still an error, by name. ONLY a sharing
# or lock violation is retried (an IOException with HResult 0x80070020 / 0x80070021, measured on
# cass for a file held with FileShare.None); access denied (UnauthorizedAccessException 0x80070005),
# a missing source, a full disk fail on the first attempt. CHANGELOG [6.6.20]
function Copy-BinWithRetry([string]$From, [string]$To) {
    for ($i = 1; ; $i++) {
        try {
            Copy-Item $From $To -Force -Recurse -ErrorAction Stop
            return
        } catch {
            $hr = '{0:X8}' -f $_.Exception.HResult
            if (($hr -ne '80070020') -and ($hr -ne '80070021')) { throw }
            if ($i -ge 40) { throw }
            Write-Host ("note: " + $_.Exception.Message + " - retrying (" + $i + ")")
            Start-Sleep -Milliseconds 250
        }
    }
}

# Version-specific tree.
Copy-BinWithRetry "$Stage\bin\*" "$VerDir\bin\"
Copy-Item "$Stage\lib\*" "$VerDir\lib\" -Force -Recurse
# v6.6.6: programs\ (the cyrius-init scaffolding templates). cyrius-init.exe resolves
# <its own dir>\..\programs\cyrius-init-templates, and bin\ here is a COPY at both
# levels, so the tree has to exist beside BOTH bin directories -- versions\<v>\bin and
# <home>\bin. install.sh does the same for the POSIX stores. Without this the binary
# ships and runs and then reports "missing template" for every file it should write.
if (Test-Path "$Stage\programs") {
    New-Item -ItemType Directory -Force -Path "$VerDir\programs", "$CyriusHome\programs" | Out-Null
    Copy-Item "$Stage\programs\*" "$VerDir\programs\" -Force -Recurse
    Copy-Item "$VerDir\programs\*" "$CyriusHome\programs\" -Force -Recurse
}
# Active version: copy into <home>\bin + <home>\lib (no symlinks on Windows).
Copy-BinWithRetry "$VerDir\bin\*" "$CyriusHome\bin\"
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
