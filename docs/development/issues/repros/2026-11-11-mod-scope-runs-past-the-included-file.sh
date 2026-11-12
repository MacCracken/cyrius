#!/usr/bin/env bash
# cyrius 6.7.18: `mod NAME;` at the top of an included library file stays in force past that file, to the end of the
# compilation unit, so it mangles the including program's own functions too (ushma 2.0.0 port, M0 probe 6). No form
# ends the scope (`mod;`, a second `mod` …), so `mod` can't namespace a distlib bundle. Exits 1 while the consumer's
# `main` is mangled and the build fails.
set -u
d=$(mktemp -d)
cd "$d" || exit 2
mkdir -p src
cat > cyrius.cyml <<'EOF'
[package]
name = "modscope"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "src/main.cyr"
output = "build/modscope"

[deps]
stdlib = ["syscalls", "string", "alloc", "fmt", "io"]
EOF
cat > src/lib_us.cyr <<'EOF'
mod us;

# The library's one function: us_helper once mangled.
fn helper(): i64 { return 7; }
EOF
cat > src/main.cyr <<'EOF'
include "src/lib_us.cyr"
use us.helper;

# The consumer's own entry point, which should stay `main`.
fn main(): i64 {
    alloc_init();
    return helper();
}

var r = main();
sys_exit_group(r);
EOF
cyrius deps > /dev/null 2>&1
out=$(cyrius build src/main.cyr build/modscope 2>&1)
rc=$?
printf '%s\n' "$out" | grep -E 'error|warning|OK' | head -5
if [ $rc -ne 0 ]; then echo "build failed: the consumer's code was mangled into mod us"; exit 1; fi
./build/modscope
echo "main returned $? (7 expected)"
exit 0
