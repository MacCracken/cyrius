# funcgate-win.ps1 -- Windows (PE) functional gate.
#
# The cyrius CLI WRAPPER cannot run on Windows yet: compiled for PE it has
# sys_fork/execve/waitpid/dup2/mkdir/unlink/chmod undefined and most syscall(n)
# values trap (STATUS_ILLEGAL_INSTRUCTION), so init/lib-sync/build (which spawn
# processes + mutate the fs) can't execute. So the wrapper-driven funcgate flow
# used on Linux/macOS is not portable here (tracked as a finding). What IS
# native-testable -- and what today's hello-world/exit-code Windows CI never
# exercises -- is whether cycc.exe correctly compiles + runs ALLOCATING programs.
# An allocator/heap or hashmap codegen bug ships green under the old smoke jobs;
# this gate catches it: build+run a vec-grown fib and a u64-hashmap, assert the
# results, and confirm the build is reproducible.
#
# Usage: funcgate-win.ps1 -Cycc <cycc.exe> -Work <dir-containing-lib>
# The Work dir MUST contain lib/ (cycc resolves `include "lib/X.cyr"` relative
# to its cwd). Distinct non-zero exit per failing step:
#   13 fib-build  14 fib-run/alloc  15 non-reproducible  16 map-build  17 map-run
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Cycc,
  [Parameter(Mandatory=$true)][string]$Work
)
$ErrorActionPreference = "Stop"
$Cycc = (Resolve-Path $Cycc).Path
if (-not (Test-Path (Join-Path $Work "lib"))) { Write-Output "FUNCGATE-WIN FAIL(12): -Work has no lib/ (cycc cannot resolve includes)"; exit 12 }
Set-Location $Work

function Build-Cyr([string]$src, [string]$out) {
  # cmd redirection preserves binary bytes; PowerShell '>' would re-encode and
  # corrupt the PE. Mirrors the existing Windows self-host step.
  if (Test-Path $out) { Remove-Item $out -Force }
  cmd /c "`"$Cycc`" < `"$src`" > `"$out`""
  return $LASTEXITCODE
}

# -- fib via vec (heap allocation) -> exit 42 --
@'
include "lib/alloc.cyr"
include "lib/vec.cyr"
fn main(): i64 {
    alloc_init();
    var seq = vec_new();
    vec_push(seq, 0); vec_push(seq, 1);
    var i = 2;
    while (i <= 30) { vec_push(seq, vec_get(seq, i - 1) + vec_get(seq, i - 2)); i = i + 1; }
    if (vec_get(seq, 30) == 832040) { return 42; }
    return 1;
}
'@ | Set-Content -Encoding ASCII -NoNewline fgw_fib.cyr

Write-Output "funcgate-win: build fib (vec alloc)"
if ((Build-Cyr "fgw_fib.cyr" "fgw_fib.exe") -ne 0 -or -not (Test-Path "fgw_fib.exe")) { Write-Output "FUNCGATE-WIN FAIL(13): fib failed to build"; exit 13 }
Write-Output "funcgate-win: run fib (assert 832040 -> exit 42)"
& .\fgw_fib.exe; $rf = $LASTEXITCODE
if ($rf -ne 42) { Write-Output "FUNCGATE-WIN FAIL(14): fib exit=$rf (expected 42) -- allocator/codegen broken"; exit 14 }

Write-Output "funcgate-win: reproducible-build"
Build-Cyr "fgw_fib.cyr" "fgw_fib2.exe" | Out-Null
$h1 = (Get-FileHash "fgw_fib.exe" -Algorithm SHA256).Hash
$h2 = (Get-FileHash "fgw_fib2.exe" -Algorithm SHA256).Hash
if ($h1 -ne $h2) { Write-Output "FUNCGATE-WIN FAIL(15): non-reproducible build (hashes differ: $h1 vs $h2)"; exit 15 }

# -- u64 hashmap + str/fmt (hash + more alloc) -> exit 43 --
@'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
include "lib/hashmap.cyr"
fn main(): i64 {
    alloc_init();
    var m = map_u64_new();
    var i = 1;
    while (i <= 50) { map_u64_set(m, i, i * i); i = i + 1; }
    var sum = 0;
    var k = 1;
    while (k <= 50) { sum = sum + map_u64_get(m, k); k = k + 1; }
    if (sum == 42925 && map_count(m) == 50) { return 43; }
    return 1;
}
'@ | Set-Content -Encoding ASCII -NoNewline fgw_map.cyr

Write-Output "funcgate-win: build hashmap program"
if ((Build-Cyr "fgw_map.cyr" "fgw_map.exe") -ne 0 -or -not (Test-Path "fgw_map.exe")) { Write-Output "FUNCGATE-WIN FAIL(16): hashmap program failed to build"; exit 16 }
Write-Output "funcgate-win: run hashmap program (assert sum-of-squares -> exit 43)"
& .\fgw_map.exe; $rm = $LASTEXITCODE
if ($rm -ne 43) { Write-Output "FUNCGATE-WIN FAIL(17): mapprog exit=$rm (expected 43) -- hashmap/str codegen broken"; exit 17 }

Write-Output "FUNCGATE_WIN_OK hash=$h1 (fib+hashmap codegen verified on Windows)"
exit 0
