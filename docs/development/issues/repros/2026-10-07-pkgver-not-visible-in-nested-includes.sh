#!/bin/sh
# CYRIUS_PKG_VERSION resolves from a file the entry includes, but not from one that file includes.
#
# Expected: all three builds succeed and print 1.2.3.
# Observed (6.6.14, 6.6.19, 6.7.2, 6.7.3): A and B succeed; C fails with
#   error:src/inc.cyr:1:..: undefined variable 'CYRIUS_PKG_VERSION' (missing include or enum?)
set -u
D=$(mktemp -d) || exit 1
mkdir -p "$D/src"
cd "$D" || exit 1
PIN=$(cyrius --version 2>/dev/null | head -1 | awk '{print $2}')
cat > cyrius.cyml <<EOF
[package]
name = "pkgnested"
version = "1.2.3"
language = "cyrius"
cyrius = "$PIN"

[build]
entry = "src/main.cyr"
output = "pkgnested"

[deps]
stdlib = ["syscalls", "alloc", "str", "string", "fmt", "io"]
EOF
printf 'fn pkg_print(): i64 { println(CYRIUS_PKG_VERSION); return 0; }\n' > src/inc.cyr
printf 'include "src/inc.cyr"\n' > src/mid.cyr
# A: the entry names the constant itself.
printf 'println(CYRIUS_PKG_VERSION);\nsys_exit_group(0);\n' > src/a.cyr
# B: one level — the entry includes the file that names it (the 6.5.34 fix).
printf 'include "src/inc.cyr"\npkg_print();\nsys_exit_group(0);\n' > src/b.cyr
# C: two levels — the entry includes a file that includes the file that names it.
printf 'include "src/mid.cyr"\npkg_print();\nsys_exit_group(0);\n' > src/c.cyr
for v in a b c; do
    if cyrius build "src/$v.cyr" "out-$v" > "build-$v.log" 2>&1; then
        echo "$v: $(./out-$v)"
    else
        echo "$v: FAILED — $(grep -o 'error.*' "build-$v.log" | head -1)"
    fi
done
rm -rf "$D"
