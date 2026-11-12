#!/usr/bin/env bash
# cyrius 6.7.18: the ELF loaders in lib/fdlopen.cyr and lib/dynlib.cyr make six raw syscalls that have no PE route —
# fdlopen.cyr:472 (stat), :530 (fstat), :626 (mprotect), :954 (lstat); dynlib.cyr:674 (fstat), :950 (arch_prctl) —
# so a `--win` build that links them warns "syscall N with K argument(s) is not routed on CYRIUS_TARGET_WIN=1; it
# returns -38". sandhi pulls both in, so every PE build of an HTTP client carries them (ushma 2.0.0 port, M0 probe
# 10: after DCE, each [lib.ai] consumer's PE build keeps dynlib.cyr:674), and a project whose gates require
# warning-free builds has to filter `lib/`. Exits 1 while any of the six warns.
set -u
d=$(mktemp -d)
cd "$d" || exit 2
mkdir -p src
cat > cyrius.cyml <<'EOF'
[package]
name = "dynlibpe"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "src/main.cyr"
output = "build/dynlibpe"

[deps]
stdlib = ["syscalls", "string", "alloc", "str", "fmt", "io", "vec", "fdlopen", "dynlib"]
EOF
cat > src/main.cyr <<'EOF'
# Reaches dynlib's loader, as sandhi's TLS path does.
fn main(): i64 {
    alloc_init();
    var h = dynlib_open("libnothing.so");
    if (h == 0) { return 0; }
    return 1;
}

var r = main();
sys_exit_group(r);
EOF
cyrius deps > /dev/null 2>&1
out=$(cyrius build --win src/main.cyr build/dynlibpe.exe 2>&1)
printf '%s\n' "$out" | grep -oE 'lib/(fdlopen|dynlib)\.cyr:[0-9]+:[0-9]+: syscall [0-9]+' 
printf '%s\n' "$out" | grep -qE 'lib/(fdlopen|dynlib)\.cyr:.*not routed' && exit 1
exit 0
